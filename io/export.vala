using Singularity.Vector;

namespace Singularity.Apps.Vector {

    [CCode (cname = "vector_tiff_cmyk", cheader_filename = "vector_cms.h")]
    extern bool tiff_cmyk (string path, uint8* cmyk, int width, int height, uint8* profile, int profile_length, double dpi);

    public class PdfOptions : Object {
        public bool all_artboards = true;
        public int artboard = 0;
        public double bleed = 0;
        public bool crop_marks = false;
        public string standard = "none";
        public bool use_doc_bleed = true;
    }

    public class Export {
        public static Rect area_for (VectorDocument doc, int artboard, Gee.List<Node>? only = null) {
            if (only != null && only.size > 0) {
                var box = Rect (0, 0, -1, -1);
                bool first = true;
                foreach (var n in only) {
                    var b = n.visual_bounds ();
                    if (b.w < 0) continue;
                    box = first ? b : box.union (b);
                    first = false;
                }
                return box;
            }
            if (artboard >= 0 && artboard < doc.artboards.size) return doc.artboards[artboard].rect ();
            return doc.content_bounds ();
        }

        public static Cairo.ImageSurface render (VectorDocument doc, Rect area, double scale, bool transparent, Gee.List<Node>? only = null, bool antialias = true) {
            int w = int.max (1, (int) Math.round (area.w * scale));
            int h = int.max (1, (int) Math.round (area.h * scale));
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            if (!antialias) cr.set_antialias (Cairo.Antialias.NONE);
            if (!transparent) {
                cr.set_source_rgb (1, 1, 1);
                cr.paint ();
            }
            cr.scale (scale, scale);
            cr.translate (-area.x, -area.y);
            var ctx = new RenderContext (doc);
            ctx.print = true;
            ctx.hide_templates = true;
            if (only != null) {
                foreach (var n in only) Renderer.draw_node (cr, n, ctx);
            } else {
                Renderer.draw_document (cr, ctx);
            }
            surface.flush ();
            return surface;
        }

        public static Gdk.Pixbuf to_pixbuf (Cairo.ImageSurface s) {
            return Gdk.pixbuf_get_from_texture (texture (s));
        }

        public static Gdk.Texture texture (Cairo.ImageSurface s) {
            s.flush ();
            int w = s.get_width (), h = s.get_height (), stride = s.get_stride ();
            unowned uint8[] data = s.get_data ();
            data.length = stride * h;
            var copy = new uint8[stride * h];
            Memory.copy (copy, data, stride * h);
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, new Bytes (copy), stride);
        }

        public static void save_raster (VectorDocument doc, string path, Rect area, double scale, string format, bool transparent, Gee.List<Node>? only = null, int quality = 92, bool cmyk = false, bool antialias = true) throws Error {
            bool opaque = format == "jpeg" || !transparent;
            var surface = render (doc, area, scale, !opaque, only, antialias);
            if (format == "png" && !cmyk) {
                var status = surface.write_to_png (path);
                if (status != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("Could not write the image: %s").printf (status.to_string ()));
                return;
            }
            if (format == "tiff" && cmyk) {
                write_cmyk_tiff (surface, path, 96 * scale);
                return;
            }
            var pix = to_pixbuf (surface);
            if (format == "jpeg" && pix.has_alpha) {
                var rgb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, pix.width, pix.height);
                rgb.fill ((uint32) 0xffffffffu);
                pix.composite (rgb, 0, 0, pix.width, pix.height, 0, 0, 1, 1, Gdk.InterpType.NEAREST, 255);
                pix = rgb;
            }
            switch (format) {
                case "jpeg":
                    pix.savev (path, "jpeg", { "quality" }, { quality.to_string () });
                    break;
                case "webp":
                    pix.savev (path, "webp", { "quality" }, { quality.to_string () });
                    break;
                case "tiff":
                    pix.savev (path, "tiff", {}, {});
                    break;
                default:
                    pix.savev (path, "png", {}, {});
                    break;
            }
        }

        public static void write_cmyk_tiff (Cairo.ImageSurface s, string path, double dpi) throws Error {
            int w = s.get_width (), h = s.get_height (), stride = s.get_stride ();
            unowned uint8[] data = s.get_data ();
            data.length = stride * h;
            var cmyk = new uint8[w * h * 4];
            var cm = ColorManager.get_default ();
            var cache = new Gee.HashMap<uint32, uint32> ();
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int o = y * stride + x * 4;
                    double a = data[o + 3] / 255.0;
                    double r = a > 0 ? data[o + 2] / 255.0 / a + (1 - a) : 1;
                    double g = a > 0 ? data[o + 1] / 255.0 / a + (1 - a) : 1;
                    double b = a > 0 ? data[o] / 255.0 / a + (1 - a) : 1;
                    r = r * a + (1 - a);
                    g = g * a + (1 - a);
                    b = b * a + (1 - a);
                    uint32 key = ((uint32) (r.clamp (0, 1) * 255) << 16) | ((uint32) (g.clamp (0, 1) * 255) << 8) | (uint32) (b.clamp (0, 1) * 255);
                    uint32 val;
                    if (cache.has_key (key)) {
                        val = cache[key];
                    } else {
                        double c, m, yy, k;
                        cm.rgb_to_cmyk (((key >> 16) & 0xff) / 255.0, ((key >> 8) & 0xff) / 255.0, (key & 0xff) / 255.0, out c, out m, out yy, out k);
                        val = ((uint32) (c.clamp (0, 1) * 255) << 24) | ((uint32) (m.clamp (0, 1) * 255) << 16) | ((uint32) (yy.clamp (0, 1) * 255) << 8) | (uint32) (k.clamp (0, 1) * 255);
                        if (cache.size < 200000) cache[key] = val;
                    }
                    int t = (y * w + x) * 4;
                    cmyk[t] = (uint8) (val >> 24);
                    cmyk[t + 1] = (uint8) ((val >> 16) & 0xff);
                    cmyk[t + 2] = (uint8) ((val >> 8) & 0xff);
                    cmyk[t + 3] = (uint8) (val & 0xff);
                }
            }
            var profile = cm.profile_bytes ();
            if (!tiff_cmyk (path, cmyk, w, h, profile, profile != null ? profile.length : 0, dpi)) throw new IOError.FAILED (_("Could not write the CMYK TIFF file."));
        }

        private static void crop_marks (Cairo.Context cr, Rect trim, double bleed) {
            double gap = double.max (bleed, 6) + 3, len = 18;
            cr.save ();
            cr.set_source_rgb (0, 0, 0);
            cr.set_line_width (0.5);
            double[] xs = { trim.x, trim.x + trim.w };
            double[] ys = { trim.y, trim.y + trim.h };
            foreach (double x in xs) {
                foreach (double y in ys) {
                    double sx = x == trim.x ? -1 : 1, sy = y == trim.y ? -1 : 1;
                    cr.move_to (x + sx * gap, y);
                    cr.line_to (x + sx * (gap + len), y);
                    cr.move_to (x, y + sy * gap);
                    cr.line_to (x, y + sy * (gap + len));
                }
            }
            cr.stroke ();
            cr.restore ();
        }

        public static int save_pdf (VectorDocument doc, string path, PdfOptions opts) throws Error {
            var boards = new Gee.ArrayList<Artboard> ();
            if (opts.all_artboards) boards.add_all (doc.artboards);
            else if (opts.artboard >= 0 && opts.artboard < doc.artboards.size) boards.add (doc.artboards[opts.artboard]);
            if (boards.size == 0) throw new IOError.INVALID_DATA (_("There are no artboards to export."));
            var prep = new Prepress (doc);
            var original = prep.apply ();
            string tmp = Path.build_filename (Environment.get_tmp_dir (), "vector-pdf-%u.pdf".printf (Random.next_int ()));
            var pages = new Gee.ArrayList<double?> ();
            try {
                double pt = 72.0 / 96.0;
                var first = boards[0];
                double first_bleed = opts.use_doc_bleed ? first.bleed : opts.bleed;
                double first_margin = opts.crop_marks ? double.max (first_bleed, 6) + 24 : first_bleed;
                var surf = new Cairo.PdfSurface (tmp, (first.w + first_margin * 2) * pt, (first.h + first_margin * 2) * pt);
                surf.restrict_to_version (Cairo.PdfVersion.VERSION_1_5);
                surf.set_metadata (Cairo.PdfMetadata.TITLE, doc.title);
                surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Singularity Vector");
                var cr = new Cairo.Context (surf);
                var ctx = new RenderContext (doc);
                ctx.print = true;
                ctx.hide_templates = true;
                foreach (var a in boards) {
                    double bleed = opts.use_doc_bleed ? a.bleed : opts.bleed;
                    double margin = opts.crop_marks ? double.max (bleed, 6) + 24 : bleed;
                    surf.set_size ((a.w + margin * 2) * pt, (a.h + margin * 2) * pt);
                    cr.save ();
                    cr.scale (pt, pt);
                    cr.translate (margin - a.x, margin - a.y);
                    cr.save ();
                    cr.rectangle (a.x - bleed, a.y - bleed, a.w + bleed * 2, a.h + bleed * 2);
                    cr.clip ();
                    if (a.background != "") {
                        var bg = Ink.hex (a.background);
                        cr.set_source_rgb (bg.r, bg.g, bg.b);
                        cr.paint ();
                    }
                    Renderer.draw_document (cr, ctx);
                    cr.restore ();
                    if (opts.crop_marks) crop_marks (cr, a.rect (), bleed);
                    cr.restore ();
                    cr.show_page ();
                    pages.add (margin * pt);
                    pages.add (bleed * pt);
                }
                surf.finish ();
                if (surf.status () != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("Could not write the PDF."));
                prep.restore (original);
                uint8[] data;
                FileUtils.get_data (tmp, out data);
                var pdf = Singularity.Pdf.Document.open_bytes (data);
                prep.post_process (pdf);
                for (int i = 0; i < pdf.page_count () && i < boards.size; i++) {
                    var page = pdf.page (i);
                    double m = pages[i * 2], b = pages[i * 2 + 1];
                    var media = pdf.page_box (i, "MediaBox");
                    double w = media[2] - media[0], h = media[3] - media[1];
                    page.set ("TrimBox", Singularity.Pdf.Obj.numbers ({ m, m, w - m, h - m }));
                    page.set ("BleedBox", Singularity.Pdf.Obj.numbers ({ m - b, m - b, w - m + b, h - m + b }));
                }
                Singularity.Pdf.SaveOptions save;
                if (opts.standard != "none") {
                    Singularity.Pdf.Standards.convert_pdfx (pdf, opts.standard, out save);
                } else {
                    save = new Singularity.Pdf.SaveOptions ();
                    save.mode = Singularity.Pdf.SaveMode.FULL;
                    save.garbage_collect = true;
                }
                pdf.save_to_file (path, save);
            } finally {
                if (FileUtils.test (tmp, FileTest.EXISTS)) FileUtils.unlink (tmp);
                prep.restore (original);
            }
            return boards.size;
        }

        public static void save_eps (VectorDocument doc, string path, int artboard) throws Error {
            var a = doc.artboards[artboard.clamp (0, doc.artboards.size - 1)];
            double pt = 72.0 / 96.0;
            var surf = new Cairo.PsSurface (path, a.w * pt, a.h * pt);
            surf.set_eps (true);
            var cr = new Cairo.Context (surf);
            cr.scale (pt, pt);
            cr.translate (-a.x, -a.y);
            var ctx = new RenderContext (doc);
            ctx.print = true;
            Renderer.draw_document (cr, ctx);
            cr.show_page ();
            surf.finish ();
        }
    }

    public class Prepress {
        private VectorDocument doc;
        private Gee.HashMap<string, Ink> sentinels = new Gee.HashMap<string, Ink> ();
        private Gee.HashMap<string, bool> overprints = new Gee.HashMap<string, bool> ();
        private int next = 1;

        public Prepress (VectorDocument doc) {
            this.doc = doc;
        }

        private Ink sentinel (Ink real, bool overprint) {
            int n = next++;
            var s = new Ink.rgb (((n >> 8) & 0xff) / 255.0, (n & 0xff) / 255.0, 0.996);
            string key = s.to_hex () + "|" + PathData.fmt (s.r, 4) + "," + PathData.fmt (s.g, 4) + "," + PathData.fmt (s.b, 4);
            sentinels[key] = real.copy ();
            overprints[key] = overprint;
            return s;
        }

        public Gee.HashMap<Paint, Ink> apply () {
            var originals = new Gee.HashMap<Paint, Ink> ();
            foreach (var n in doc.all_nodes ()) {
                foreach (var l in n.appearance) {
                    var p = l.paint;
                    if (p.kind != PaintKind.SOLID) continue;
                    var real = Renderer.resolve_ink (p.color, new RenderContext (doc));
                    if (real.spot == "" && p.color.spot != "") real.spot = p.color.spot;
                    if (real.spot == "" && !p.overprint) continue;
                    originals[p] = p.color;
                    p.color = sentinel (real, p.overprint);
                }
            }
            return originals;
        }

        public void restore (Gee.HashMap<Paint, Ink> originals) {
            foreach (var e in originals.entries) e.key.color = e.value;
        }

        private string? match (double r, double g, double b) {
            foreach (var key in sentinels.keys) {
                var parts = key.split ("|")[1].split (",");
                if ((double.parse (parts[0]) - r).abs () < 0.0015 && (double.parse (parts[1]) - g).abs () < 0.0015 && (double.parse (parts[2]) - b).abs () < 0.0015) return key;
            }
            return null;
        }

        public void post_process (Singularity.Pdf.Document pdf) {
            if (sentinels.size == 0) return;
            for (int p = 0; p < pdf.page_count (); p++) {
                var res = pdf.page_resources (p, true);
                var ops = Singularity.Pdf.Content.parse (pdf.page_content (p));
                if (rewrite (pdf, ops, res)) pdf.set_page_content (p, Singularity.Pdf.Content.serialize (ops));
                var xobjects = pdf.lookup (res, "XObject");
                if (xobjects.is_dict ()) rewrite_forms (pdf, xobjects, 0);
            }
        }

        private void rewrite_forms (Singularity.Pdf.Document pdf, Singularity.Pdf.Obj xobjects, int depth) {
            if (depth > 8 || xobjects.dict == null) return;
            foreach (var key in xobjects.dict.keys.to_array ()) {
                var xo = pdf.resolve (xobjects.get (key));
                if (!xo.is_stream ()) continue;
                var st = xo.get ("Subtype");
                if (st == null || !pdf.resolve (st).is_name ("Form")) continue;
                var fres = xo.get ("Resources") != null ? pdf.resolve (xo.get ("Resources")) : null;
                if (fres == null) {
                    fres = Singularity.Pdf.Obj.dictionary ();
                    xo.set ("Resources", fres);
                }
                var ops = Singularity.Pdf.Content.parse (pdf.stream_data (xo));
                if (rewrite (pdf, ops, fres)) pdf.set_stream_data (xo, Singularity.Pdf.Content.serialize (ops));
                var inner = pdf.lookup (fres, "XObject");
                if (inner.is_dict ()) rewrite_forms (pdf, inner, depth + 1);
            }
        }

        private Gee.HashMap<string, string> spot_names = new Gee.HashMap<string, string> ();

        private bool rewrite (Singularity.Pdf.Document pdf, Gee.ArrayList<Singularity.Pdf.Op> ops, Singularity.Pdf.Obj res) {
            bool changed = false;
            for (int i = 0; i < ops.size; i++) {
                var op = ops[i];
                if ((op.name != "rg" && op.name != "RG") || op.args.size < 3) continue;
                string? key = match (op.num (0), op.num (1), op.num (2));
                if (key == null) continue;
                var ink = sentinels[key];
                bool stroke = op.name == "RG";
                var replacement = new Gee.ArrayList<Singularity.Pdf.Op> ();
                if (ink.spot != "") {
                    string cs = spot_space (pdf, res, ink);
                    replacement.add (new Singularity.Pdf.Op.with (stroke ? "CS" : "cs", { Singularity.Pdf.Obj.name_obj (cs) }));
                    replacement.add (new Singularity.Pdf.Op.with (stroke ? "SCN" : "scn", { Singularity.Pdf.Obj.number (ink.tint) }));
                } else {
                    ink.ensure_cmyk ();
                    replacement.add (new Singularity.Pdf.Op.with (stroke ? "K" : "k", { Singularity.Pdf.Obj.number (ink.c), Singularity.Pdf.Obj.number (ink.m), Singularity.Pdf.Obj.number (ink.y), Singularity.Pdf.Obj.number (ink.k) }));
                }
                if (overprints[key]) {
                    string gs = overprint_state (pdf, res);
                    replacement.insert (0, new Singularity.Pdf.Op.with ("gs", { Singularity.Pdf.Obj.name_obj (gs) }));
                }
                ops.remove_at (i);
                for (int k = 0; k < replacement.size; k++) ops.insert (i + k, replacement[k]);
                i += replacement.size - 1;
                changed = true;
            }
            return changed;
        }

        private string spot_space (Singularity.Pdf.Document pdf, Singularity.Pdf.Obj res, Ink ink) {
            var spaces = pdf.sub_dict (res, "ColorSpace");
            string name = "CSspot%d".printf (spot_names.size);
            if (spot_names.has_key (ink.spot)) name = spot_names[ink.spot];
            else spot_names[ink.spot] = name;
            if (spaces.get (name) != null) return name;
            var alt = ink.copy ();
            alt.ensure_cmyk ();
            var fn = Singularity.Pdf.Obj.dictionary ();
            fn.set ("FunctionType", Singularity.Pdf.Obj.integer (2));
            fn.set ("Domain", Singularity.Pdf.Obj.numbers ({ 0, 1 }));
            fn.set ("C0", Singularity.Pdf.Obj.numbers ({ 0, 0, 0, 0 }));
            fn.set ("C1", Singularity.Pdf.Obj.numbers ({ alt.c, alt.m, alt.y, alt.k }));
            fn.set ("N", Singularity.Pdf.Obj.integer (1));
            var arr = Singularity.Pdf.Obj.array ();
            arr.add (Singularity.Pdf.Obj.name_obj ("Separation"));
            arr.add (Singularity.Pdf.Obj.name_obj (ink.spot.replace (" ", "_")));
            arr.add (Singularity.Pdf.Obj.name_obj ("DeviceCMYK"));
            arr.add (pdf.add_ref (fn));
            spaces.set (name, pdf.add_ref (arr));
            return name;
        }

        private string overprint_state (Singularity.Pdf.Document pdf, Singularity.Pdf.Obj res) {
            var states = pdf.sub_dict (res, "ExtGState");
            if (states.get ("GSop") == null) {
                var gs = Singularity.Pdf.Obj.dictionary ();
                gs.set ("Type", Singularity.Pdf.Obj.name_obj ("ExtGState"));
                gs.set ("OP", Singularity.Pdf.Obj.boolean (true));
                gs.set ("op", Singularity.Pdf.Obj.boolean (true));
                gs.set ("OPM", Singularity.Pdf.Obj.integer (1));
                states.set ("GSop", pdf.add_ref (gs));
            }
            return "GSop";
        }
    }
}
