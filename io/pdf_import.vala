using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class PdfImport {
        private class GState {
            public Cairo.Matrix ctm;
            public Ink fill = new Ink ();
            public Ink stroke = new Ink ();
            public PaintKind fill_kind = PaintKind.SOLID;
            public Paint? fill_paint = null;
            public double fill_alpha = 1;
            public double stroke_alpha = 1;
            public double width = 1;
            public int cap = 0;
            public int join = 0;
            public double miter = 10;
            public double[] dash = {};
            public double dash_phase = 0;
            public BlendMode blend = BlendMode.NORMAL;
            public PathData? clip = null;
            public bool clip_even_odd = false;
            public string fill_space = "DeviceGray";
            public string stroke_space = "DeviceGray";
            public string fill_spot = "";
            public string stroke_spot = "";

            public GState copy () {
                var g = new GState ();
                g.ctm = ctm;
                g.fill = fill.copy ();
                g.stroke = stroke.copy ();
                g.fill_kind = fill_kind;
                g.fill_paint = fill_paint;
                g.fill_alpha = fill_alpha;
                g.stroke_alpha = stroke_alpha;
                g.width = width;
                g.cap = cap;
                g.join = join;
                g.miter = miter;
                g.dash = dash;
                g.dash_phase = dash_phase;
                g.blend = blend;
                g.clip = clip;
                g.clip_even_odd = clip_even_odd;
                g.fill_space = fill_space;
                g.stroke_space = stroke_space;
                g.fill_spot = fill_spot;
                g.stroke_spot = stroke_spot;
                return g;
            }
        }

        private Singularity.Pdf.Document pdf;
        private VectorDocument doc;
        private GroupNode target;
        private double page_h;
        private double offset_y;
        private int depth = 0;
        private PathData? last_clip = null;
        private GroupNode? clip_group = null;

        public static VectorDocument load (string path) throws Error {
            var reader = new PdfImport ();
            return reader.read (Singularity.Pdf.Document.open_file (path), Path.get_basename (path));
        }

        public static VectorDocument load_ai (string path) throws Error {
            uint8[] head = new uint8[8];
            var f = FileStream.open (path, "rb");
            if (f == null) throw new IOError.NOT_FOUND (_("The file could not be read."));
            f.read (head);
            if (head[0] == '%' && head[1] == 'P' && head[2] == 'D' && head[3] == 'F') return load (path);
            if (head[0] == '%' && head[1] == '!') return load_postscript (path);
            throw new IOError.NOT_SUPPORTED (_("This Illustrator file was saved without PDF compatibility, so its private data cannot be read. Save it again with Create PDF Compatible File turned on, or export SVG or PDF."));
        }

        public static string? ghostscript () {
            string? env = Environment.get_variable ("SINGULARITY_VECTOR_GHOSTSCRIPT");
            if (env != null && env != "" && FileUtils.test (env, FileTest.IS_EXECUTABLE)) return env;
            return Environment.find_program_in_path ("gs");
        }

        public static VectorDocument load_postscript (string path) throws Error {
            string? gs = ghostscript ();
            if (gs != null) {
                string tmp = Path.build_filename (Environment.get_tmp_dir (), "vector-eps-%u.pdf".printf (Random.next_int ()));
                string[] argv = { gs, "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=pdfwrite", "-dEPSCrop", "-sOutputFile=" + tmp, path };
                int status;
                string out_text, err_text;
                Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out out_text, out err_text, out status);
                try {
                    if (status == 0 && FileUtils.test (tmp, FileTest.EXISTS)) {
                        var d = load (tmp);
                        d.title = Path.get_basename (path);
                        return d;
                    }
                } finally {
                    FileUtils.unlink (tmp);
                }
            }
            var preview = eps_preview (path);
            if (preview != null) {
                var d = VectorDocument.blank (preview.width, preview.height);
                uint8[] png;
                preview.save_to_buffer (out png, "png");
                var im = new ImageNode ();
                im.asset = d.store_asset (new Bytes (png), "image/png");
                im.pixel_width = preview.width;
                im.pixel_height = preview.height;
                d.active_layer.add (im);
                d.ensure_ids ();
                d.title = Path.get_basename (path);
                d.modified = false;
                return d;
            }
            throw new IOError.NOT_SUPPORTED (_("Opening PostScript artwork needs Ghostscript, and this file has no preview image to show instead."));
        }

        private static Gdk.Pixbuf? eps_preview (string path) {
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                if (data.length < 30 || data[0] != 0xC5 || data[1] != 0xD0 || data[2] != 0xD3 || data[3] != 0xC6) return null;
                uint32 tiff_off = data[20] | (data[21] << 8) | (data[22] << 16) | (data[23] << 24);
                uint32 tiff_len = data[24] | (data[25] << 8) | (data[26] << 16) | (data[27] << 24);
                if (tiff_off == 0 || tiff_len == 0 || tiff_off + tiff_len > data.length) return null;
                var loader = new Gdk.PixbufLoader ();
                loader.write (data[tiff_off:tiff_off + tiff_len]);
                loader.close ();
                return loader.get_pixbuf ();
            } catch (Error e) {
                return null;
            }
        }

        private VectorDocument read (Singularity.Pdf.Document pdf, string title) throws Error {
            this.pdf = pdf;
            doc = new VectorDocument ();
            doc.title = title;
            int pages = pdf.page_count ();
            if (pages == 0) throw new IOError.INVALID_DATA (_("The PDF has no pages."));
            var layer = doc.new_layer (_("Layer 1"));
            doc.layers.add (layer);
            doc.active_layer = layer;
            offset_y = 0;
            for (int p = 0; p < pages && p < 200; p++) {
                var box = pdf.page_box (p, "CropBox");
                if (box.length < 4) box = pdf.page_box (p);
                double x1 = double.min (box[0], box[2]), y1 = double.min (box[1], box[3]);
                double w = (box[2] - box[0]).abs (), h = (box[3] - box[1]).abs ();
                double s = 96.0 / 72.0;
                var a = new Artboard (pages > 1 ? _("Page %d").printf (p + 1) : _("Artboard 1"), 0, offset_y, w * s, h * s);
                doc.add_artboard (a);
                var page_group = new GroupNode ();
                page_group.name = a.name;
                target = page_group;
                last_clip = null;
                clip_group = null;
                var base_m = Cairo.Matrix (s, 0, 0, -s, -x1 * s, offset_y + (y1 + h) * s);
                var gs = new GState ();
                gs.ctm = base_m;
                var ops = Singularity.Pdf.Content.parse (pdf.page_content (p));
                run (ops, pdf.page_resources (p, false), gs);
                import_text (p, base_m);
                if (pages > 1) layer.add (page_group);
                else {
                    var kids = new Gee.ArrayList<Node> ();
                    kids.add_all (page_group.children);
                    foreach (var k in kids) {
                        page_group.remove (k);
                        layer.add (k);
                    }
                }
                offset_y += h * s + 60;
            }
            doc.default_swatches ();
            doc.default_brushes ();
            doc.relink ();
            doc.ensure_ids ();
            doc.modified = false;
            return doc;
        }

        private Cairo.Matrix pdf_matrix (Singularity.Pdf.Op op) {
            return Cairo.Matrix (op.num (0), op.num (1), op.num (2), op.num (3), op.num (4), op.num (5));
        }

        private Ink color_from (Gee.List<Singularity.Pdf.Obj> args, string space, out string spot) {
            spot = "";
            int n = 0;
            foreach (var a in args) if (a.is_number ()) n++;
            double[] v = {};
            foreach (var a in args) if (a.is_number ()) v += a.as_number ();
            if (space.has_prefix ("Separation:")) {
                spot = space.substring (11);
                var parts = spot.split ("|");
                spot = parts[0];
                double t = v.length > 0 ? v[0] : 1;
                var alt = parts.length > 1 ? Ink.hex (parts[1]) : new Ink.rgb (0, 0, 0);
                var ink = new Ink.rgb (1 - (1 - alt.r) * t, 1 - (1 - alt.g) * t, 1 - (1 - alt.b) * t);
                ink.spot = spot;
                ink.tint = 1;
                return ink;
            }
            if (n == 4) return new Ink.cmyk (v[0], v[1], v[2], v[3]);
            if (n == 3) return new Ink.rgb (v[0], v[1], v[2]);
            if (n >= 1) return new Ink.rgb (v[0], v[0], v[0]);
            return new Ink ();
        }

        private string space_of (Singularity.Pdf.Obj res, string name) {
            if (name == "DeviceRGB" || name == "DeviceCMYK" || name == "DeviceGray" || name == "Pattern") return name;
            var spaces = pdf.lookup (res, "ColorSpace");
            if (!spaces.is_dict ()) return name;
            var cs = pdf.resolve (spaces.get (name));
            if (cs.is_array () && cs.length > 0) {
                var kind = pdf.resolve (cs.at (0));
                if (kind.is_name ("Separation") && cs.length >= 4) {
                    string spot = pdf.resolve (cs.at (1)).name ?? "Spot";
                    var fn = pdf.resolve (cs.at (3));
                    string alt_hex = "#000000";
                    var c1 = pdf.resolve (fn.get ("C1"));
                    if (c1 != null && c1.is_array ()) {
                        double[] v = {};
                        for (int i = 0; i < c1.length; i++) v += pdf.resolve (c1.at (i)).as_number ();
                        Ink alt = v.length == 4 ? new Ink.cmyk (v[0], v[1], v[2], v[3]) : (v.length == 3 ? new Ink.rgb (v[0], v[1], v[2]) : new Ink.rgb (v.length > 0 ? v[0] : 0, v.length > 0 ? v[0] : 0, v.length > 0 ? v[0] : 0));
                        alt_hex = alt.to_hex ();
                    }
                    return "Separation:%s|%s".printf (spot, alt_hex);
                }
                if (kind.is_name ("Pattern")) return "Pattern";
                if (kind.is_name ("ICCBased") && cs.length >= 2) {
                    var stream = pdf.resolve (cs.at (1));
                    int ncomp = stream.get ("N") != null ? pdf.resolve (stream.get ("N")).as_int (3) : 3;
                    return ncomp == 4 ? "DeviceCMYK" : (ncomp == 1 ? "DeviceGray" : "DeviceRGB");
                }
            }
            return name;
        }

        private Paint? pattern_paint (Singularity.Pdf.Obj res, string name, Cairo.Matrix ctm_at_use) {
            var pats = pdf.lookup (res, "Pattern");
            if (!pats.is_dict ()) return null;
            var p = pdf.resolve (pats.get (name));
            if (!p.is_dict ()) return null;
            int type = p.get ("PatternType") != null ? pdf.resolve (p.get ("PatternType")).as_int (1) : 1;
            if (type != 2) return null;
            var m = Cairo.Matrix.identity ();
            var mo = pdf.resolve (p.get ("Matrix"));
            if (mo != null && mo.is_array () && mo.length == 6) m = Cairo.Matrix (pdf.resolve (mo.at (0)).as_number (), pdf.resolve (mo.at (1)).as_number (), pdf.resolve (mo.at (2)).as_number (), pdf.resolve (mo.at (3)).as_number (), pdf.resolve (mo.at (4)).as_number (), pdf.resolve (mo.at (5)).as_number ());
            return shading_paint (pdf.resolve (p.get ("Shading")), Transforms.multiply (m, base_matrix));
        }

        private Cairo.Matrix base_matrix;

        private Paint? shading_paint (Singularity.Pdf.Obj sh, Cairo.Matrix m) {
            if (!sh.is_dict ()) return null;
            int type = pdf.resolve (sh.get ("ShadingType")).as_int (0);
            if (type != 2 && type != 3) return null;
            var coords = pdf.resolve (sh.get ("Coords"));
            if (!coords.is_array ()) return null;
            double[] c = {};
            for (int i = 0; i < coords.length; i++) c += pdf.resolve (coords.at (i)).as_number ();
            var paint = new Paint ();
            paint.kind = type == 2 ? PaintKind.LINEAR : PaintKind.RADIAL;
            var cs = pdf.resolve (sh.get ("ColorSpace"));
            int ncomp = 3;
            if (cs.is_name ("DeviceCMYK")) ncomp = 4;
            else if (cs.is_name ("DeviceGray")) ncomp = 1;
            add_function_stops (paint.gradient, pdf.resolve (sh.get ("Function")), 0, 1, ncomp);
            if (paint.gradient.stops.size < 2) return null;
            var g = paint.gradient;
            if (type == 2 && c.length >= 4) {
                double x1 = c[0], y1 = c[1], x2 = c[2], y2 = c[3];
                m.transform_point (ref x1, ref y1);
                m.transform_point (ref x2, ref y2);
                g.x1 = x1;
                g.y1 = y1;
                g.x2 = x2;
                g.y2 = y2;
            } else if (c.length >= 6) {
                double fx = c[0], fy = c[1], cx = c[3], cy = c[4], rx = c[3] + c[5], ry = c[4];
                m.transform_point (ref fx, ref fy);
                m.transform_point (ref cx, ref cy);
                m.transform_point (ref rx, ref ry);
                g.x1 = cx;
                g.y1 = cy;
                g.x2 = rx;
                g.y2 = ry;
                g.fx = fx;
                g.fy = fy;
            }
            return paint;
        }

        private void add_function_stops (Gradient g, Singularity.Pdf.Obj fn, double t0, double t1, int ncomp) {
            if (!fn.is_dict ()) return;
            int type = pdf.resolve (fn.get ("FunctionType")).as_int (-1);
            if (type == 2) {
                var c0 = pdf.resolve (fn.get ("C0"));
                var c1 = pdf.resolve (fn.get ("C1"));
                g.stops.add (new GradientStop (t0, ink_of (c0, ncomp, 0)));
                g.stops.add (new GradientStop (t1, ink_of (c1, ncomp, 1)));
            } else if (type == 3) {
                var fns = pdf.resolve (fn.get ("Functions"));
                var bounds = pdf.resolve (fn.get ("Bounds"));
                if (!fns.is_array ()) return;
                double prev = t0;
                for (int i = 0; i < fns.length; i++) {
                    double next = i < bounds.length ? pdf.resolve (bounds.at (i)).as_number () : t1;
                    add_function_stops (g, pdf.resolve (fns.at (i)), prev, next, ncomp);
                    prev = next;
                }
            } else if (type == 0) {
                g.stops.add (new GradientStop (t0, new Ink.rgb (0, 0, 0)));
                g.stops.add (new GradientStop (t1, new Ink.rgb (1, 1, 1)));
            }
        }

        private Ink ink_of (Singularity.Pdf.Obj? arr, int ncomp, double fallback) {
            if (arr == null || !arr.is_array ()) return new Ink.rgb (fallback, fallback, fallback);
            double[] v = {};
            for (int i = 0; i < arr.length; i++) v += pdf.resolve (arr.at (i)).as_number ();
            if (ncomp == 4 && v.length >= 4) return new Ink.cmyk (v[0], v[1], v[2], v[3]);
            if (v.length >= 3) return new Ink.rgb (v[0], v[1], v[2]);
            if (v.length >= 1) return new Ink.rgb (v[0], v[0], v[0]);
            return new Ink ();
        }

        private void emit (Node n, GState gs) {
            if (gs.clip == null) {
                last_clip = null;
                clip_group = null;
                target.add (n);
                return;
            }
            if (gs.clip != last_clip || clip_group == null) {
                clip_group = new GroupNode ();
                clip_group.clip = true;
                var cp = new PathNode.with_path (gs.clip.copy ());
                cp.even_odd = gs.clip_even_odd;
                clip_group.add (cp);
                target.add (clip_group);
                last_clip = gs.clip;
            }
            clip_group.add (n);
        }

        private void paint_path (PathData path, GState gs, bool fill, bool stroke, bool even_odd) {
            if (path.is_empty ()) return;
            var pn = new PathNode.with_path (path.transformed (gs.ctm));
            pn.even_odd = even_odd;
            if (fill) {
                Paint p;
                if (gs.fill_kind == PaintKind.SOLID || gs.fill_paint == null) {
                    var ink = gs.fill.copy ();
                    p = new Paint.solid (ink);
                } else {
                    p = gs.fill_paint.copy ();
                }
                var l = new PaintLayer.fill (p);
                l.opacity = gs.fill_alpha;
                pn.appearance.add (l);
            }
            if (stroke) {
                double s = Transforms.scale_factor (gs.ctm);
                var l = new PaintLayer.line (new Paint.solid (gs.stroke.copy ()), double.max (gs.width * s, 0.25));
                l.opacity = gs.stroke_alpha;
                l.cap = (CapKind) gs.cap.clamp (0, 2);
                l.join = (JoinKind) gs.join.clamp (0, 2);
                l.miter = gs.miter;
                if (gs.dash.length > 0) {
                    double[] d = {};
                    foreach (double v in gs.dash) d += v * s;
                    l.dashes = d;
                    l.dash_offset = gs.dash_phase * s;
                }
                pn.appearance.add (l);
            }
            pn.blend = gs.blend;
            emit (pn, gs);
        }

        private void run (Gee.List<Singularity.Pdf.Op> ops, Singularity.Pdf.Obj res, GState start) {
            if (++depth > 24) {
                depth--;
                return;
            }
            var gs = start;
            var stack = new Gee.ArrayList<GState> ();
            var path = new PathData ();
            double cx = 0, cy = 0;
            bool pending_clip = false, pending_eo = false;
            bool in_text = false;
            foreach (var op in ops) {
                switch (op.name) {
                    case "q": stack.add (gs.copy ()); break;
                    case "Q":
                        if (stack.size > 0) gs = stack.remove_at (stack.size - 1);
                        break;
                    case "cm": gs.ctm = Transforms.multiply (pdf_matrix (op), gs.ctm); break;
                    case "w": gs.width = op.num (0); break;
                    case "J": gs.cap = (int) op.num (0); break;
                    case "j": gs.join = (int) op.num (0); break;
                    case "M": gs.miter = op.num (0); break;
                    case "d":
                        if (op.args.size > 0 && op.args[0].is_array ()) {
                            double[] d = {};
                            for (int i = 0; i < op.args[0].length; i++) d += op.args[0].at (i).as_number ();
                            gs.dash = d;
                            gs.dash_phase = op.num (1);
                        }
                        break;
                    case "gs":
                        var states = pdf.lookup (res, "ExtGState");
                        if (states.is_dict () && op.args.size > 0) {
                            var st = pdf.resolve (states.get (op.args[0].name ?? ""));
                            if (st.is_dict ()) {
                                if (st.get ("ca") != null) gs.fill_alpha = pdf.resolve (st.get ("ca")).as_number (1);
                                if (st.get ("CA") != null) gs.stroke_alpha = pdf.resolve (st.get ("CA")).as_number (1);
                                if (st.get ("LW") != null) gs.width = pdf.resolve (st.get ("LW")).as_number (1);
                                var bm = st.get ("BM") != null ? pdf.resolve (st.get ("BM")) : null;
                                if (bm != null && bm.is_name ()) gs.blend = BlendMode.from_id (pdf_blend (bm.name));
                            }
                        }
                        break;
                    case "m":
                        path.move_to (op.num (0), op.num (1));
                        cx = op.num (0);
                        cy = op.num (1);
                        break;
                    case "l":
                        path.line_to (op.num (0), op.num (1));
                        cx = op.num (0);
                        cy = op.num (1);
                        break;
                    case "c":
                        path.curve_to (op.num (0), op.num (1), op.num (2), op.num (3), op.num (4), op.num (5));
                        cx = op.num (4);
                        cy = op.num (5);
                        break;
                    case "v":
                        path.curve_to (cx, cy, op.num (0), op.num (1), op.num (2), op.num (3));
                        cx = op.num (2);
                        cy = op.num (3);
                        break;
                    case "y":
                        path.curve_to (op.num (0), op.num (1), op.num (2), op.num (3), op.num (2), op.num (3));
                        cx = op.num (2);
                        cy = op.num (3);
                        break;
                    case "h": path.close (); break;
                    case "re":
                        path.move_to (op.num (0), op.num (1));
                        path.line_to (op.num (0) + op.num (2), op.num (1));
                        path.line_to (op.num (0) + op.num (2), op.num (1) + op.num (3));
                        path.line_to (op.num (0), op.num (1) + op.num (3));
                        path.close ();
                        break;
                    case "S":
                    case "s":
                    case "f":
                    case "F":
                    case "f*":
                    case "B":
                    case "B*":
                    case "b":
                    case "b*":
                    case "n":
                        if (op.name == "s" || op.name == "b" || op.name == "b*") path.close ();
                        bool fill = op.name.has_prefix ("f") || op.name == "F" || op.name.has_prefix ("B") || op.name.has_prefix ("b");
                        bool stroke = op.name == "S" || op.name == "s" || op.name.has_prefix ("B") || op.name.has_prefix ("b");
                        bool eo = op.name.has_suffix ("*");
                        if (op.name != "n") paint_path (path, gs, fill, stroke, eo);
                        if (pending_clip) {
                            gs.clip = gs.clip == null ? path.transformed (gs.ctm) : CurveBoolean.apply (gs.clip, path.transformed (gs.ctm), BoolOp.INTERSECT, gs.clip_even_odd, pending_eo);
                            gs.clip_even_odd = pending_eo && gs.clip == null;
                            pending_clip = false;
                        }
                        path = new PathData ();
                        break;
                    case "W":
                    case "W*":
                        pending_clip = true;
                        pending_eo = op.name == "W*";
                        break;
                    case "g":
                        gs.fill = color_from (op.args, "DeviceGray", out gs.fill_spot);
                        gs.fill_kind = PaintKind.SOLID;
                        break;
                    case "G": gs.stroke = color_from (op.args, "DeviceGray", out gs.stroke_spot); break;
                    case "rg":
                        gs.fill = color_from (op.args, "DeviceRGB", out gs.fill_spot);
                        gs.fill_kind = PaintKind.SOLID;
                        break;
                    case "RG": gs.stroke = color_from (op.args, "DeviceRGB", out gs.stroke_spot); break;
                    case "k":
                        gs.fill = color_from (op.args, "DeviceCMYK", out gs.fill_spot);
                        gs.fill_kind = PaintKind.SOLID;
                        break;
                    case "K": gs.stroke = color_from (op.args, "DeviceCMYK", out gs.stroke_spot); break;
                    case "cs":
                        gs.fill_space = op.args.size > 0 ? space_of (res, op.args[0].name ?? "") : "DeviceGray";
                        break;
                    case "CS":
                        gs.stroke_space = op.args.size > 0 ? space_of (res, op.args[0].name ?? "") : "DeviceGray";
                        break;
                    case "sc":
                    case "scn":
                        if (gs.fill_space == "Pattern" && op.args.size > 0 && op.args[op.args.size - 1].is_name ()) {
                            base_matrix = gs.ctm;
                            var pp = pattern_paint (res, op.args[op.args.size - 1].name, gs.ctm);
                            if (pp != null) {
                                gs.fill_paint = pp;
                                gs.fill_kind = pp.kind;
                            }
                        } else {
                            gs.fill = color_from (op.args, gs.fill_space, out gs.fill_spot);
                            gs.fill_kind = PaintKind.SOLID;
                        }
                        break;
                    case "SC":
                    case "SCN":
                        gs.stroke = color_from (op.args, gs.stroke_space, out gs.stroke_spot);
                        break;
                    case "sh":
                        var shadings = pdf.lookup (res, "Shading");
                        if (shadings.is_dict () && op.args.size > 0) {
                            var paint = shading_paint (pdf.resolve (shadings.get (op.args[0].name ?? "")), gs.ctm);
                            if (paint != null) {
                                PathData area;
                                if (gs.clip != null) area = gs.clip.copy ();
                                else {
                                    var a = doc.current_artboard ();
                                    area = new PathData.rect (a.x, offset_y, a.w, a.h);
                                }
                                var pn = new PathNode.with_path (area);
                                pn.appearance.add (new PaintLayer.fill (paint));
                                pn.opacity = gs.fill_alpha;
                                target.add (pn);
                                last_clip = null;
                                clip_group = null;
                            }
                        }
                        break;
                    case "BT": in_text = true; break;
                    case "ET": in_text = false; break;
                    case "Do":
                        var xobjects = pdf.lookup (res, "XObject");
                        if (!xobjects.is_dict () || op.args.size == 0) break;
                        var xo = pdf.resolve (xobjects.get (op.args[0].name ?? ""));
                        if (!xo.is_dict ()) break;
                        var subtype = xo.get ("Subtype");
                        if (subtype != null && pdf.resolve (subtype).is_name ("Form")) {
                            var fm = Cairo.Matrix.identity ();
                            var mo = xo.get ("Matrix");
                            if (mo != null) {
                                var ma = pdf.resolve (mo);
                                if (ma.is_array () && ma.length == 6) fm = Cairo.Matrix (pdf.resolve (ma.at (0)).as_number (), pdf.resolve (ma.at (1)).as_number (), pdf.resolve (ma.at (2)).as_number (), pdf.resolve (ma.at (3)).as_number (), pdf.resolve (ma.at (4)).as_number (), pdf.resolve (ma.at (5)).as_number ());
                            }
                            var child_gs = gs.copy ();
                            child_gs.ctm = Transforms.multiply (fm, gs.ctm);
                            var fres = xo.get ("Resources") != null ? pdf.resolve (xo.get ("Resources")) : res;
                            try {
                                var data = pdf.stream_data (xo);
                                run (Singularity.Pdf.Content.parse (data), fres, child_gs);
                            } catch (Error e) {
                            }
                        } else if (subtype != null && pdf.resolve (subtype).is_name ("Image")) {
                            var pix = Singularity.Pdf.Images.decode (pdf, xo);
                            if (pix == null) break;
                            uint8[] png;
                            try {
                                pix.save_to_buffer (out png, "png");
                            } catch (Error e) {
                                break;
                            }
                            var im = new ImageNode ();
                            im.asset = doc.store_asset (new Bytes (png), "image/png");
                            im.pixel_width = pix.width;
                            im.pixel_height = pix.height;
                            var unit = Cairo.Matrix (1.0 / pix.width, 0, 0, -1.0 / pix.height, 0, 1);
                            im.matrix = Transforms.multiply (unit, gs.ctm);
                            im.opacity = gs.fill_alpha;
                            emit (im, gs);
                        }
                        break;
                    default:
                        break;
                }
            }
            depth--;
        }

        private static string pdf_blend (string name) {
            switch (name) {
                case "Multiply": return "multiply";
                case "Screen": return "screen";
                case "Overlay": return "overlay";
                case "Darken": return "darken";
                case "Lighten": return "lighten";
                case "ColorDodge": return "color-dodge";
                case "ColorBurn": return "color-burn";
                case "HardLight": return "hard-light";
                case "SoftLight": return "soft-light";
                case "Difference": return "difference";
                case "Exclusion": return "exclusion";
                case "Hue": return "hue";
                case "Saturation": return "saturation";
                case "Color": return "color";
                case "Luminosity": return "luminosity";
                default: return "normal";
            }
        }

        private void import_text (int page, Cairo.Matrix base_m) {
            var interp = new Singularity.Pdf.Interpreter (pdf);
            interp.run_page (page);
            foreach (var item in interp.items) {
                if (item.kind != Singularity.Pdf.ItemKind.TEXT || item.render_mode == 3) continue;
                string text = item.text ().strip ();
                if (text == "" || item.glyphs.size == 0) continue;
                var tm = item.text_matrix;
                var ctm = item.ctm;
                var full = tm.multiply (ctm);
                double ox, oy;
                full.apply (0, item.rise, out ox, out oy);
                double scale_y = Math.hypot (full.c, full.d);
                double angle = Math.atan2 (full.b, full.a);
                double dx = ox, dy = oy;
                base_m.transform_point (ref dx, ref dy);
                double s = Transforms.scale_factor (base_m);
                var t = new TextNode ();
                t.text = item.text ();
                t.style.size = double.max (item.font_size * scale_y * s, 1);
                if (item.font != null) {
                    string fam = item.font.family_hint ();
                    if (fam != "") t.style.family = fam;
                    string bf = item.font.base_font.down ();
                    if (bf.contains ("bold")) t.style.weight = 700;
                    if (bf.contains ("italic") || bf.contains ("oblique")) t.style.italic = true;
                }
                if (item.h_scale != 1 && item.h_scale > 0) t.style.hscale = item.h_scale / 100.0 > 0.05 ? item.h_scale / 100.0 : 1;
                var m = Cairo.Matrix.identity ();
                m.rotate (-angle);
                t.matrix = Transforms.multiply (m, Transforms.translate (dx, dy));
                t.appearance.add (new PaintLayer.fill (new Paint.solid (new Ink.rgb (item.fill_rgb[0], item.fill_rgb[1], item.fill_rgb[2]))));
                target.add (t);
            }
        }
    }
}
