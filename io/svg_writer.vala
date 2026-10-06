using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class SvgOptions : Object {
        public int decimals = 3;
        public string styling = "attributes";
        public bool native = true;
        public bool minify = false;
        public bool responsive = false;
        public bool text_outlines = false;
        public bool link_images = false;
        public int artboard = -1;
        public bool all_artboards = true;
        public Rect? area = null;
        public Gee.List<Node>? only = null;
        public double scale = 1;
    }

    public class SvgWriter {
        public const string NS = "urn:singularityos:vector:1";
        private VectorDocument doc;
        private SvgOptions opts;
        private StringBuilder defs = new StringBuilder ();
        private StringBuilder css = new StringBuilder ();
        private Gee.HashMap<string, string> classes = new Gee.HashMap<string, string> ();
        private Gee.HashSet<string> symbols_written = new Gee.HashSet<string> ();
        private Gee.HashSet<string> patterns_written = new Gee.HashSet<string> ();
        private int ids = 0;
        private RenderContext ctx;

        private SvgWriter (VectorDocument doc, SvgOptions opts) {
            this.doc = doc;
            this.opts = opts;
            ctx = new RenderContext (doc);
            ctx.print = true;
        }

        public static string write (VectorDocument doc, SvgOptions? options = null) {
            var w = new SvgWriter (doc, options ?? new SvgOptions ());
            return w.document ();
        }

        public static string selection_svg (VectorDocument doc, Gee.List<Node> nodes) {
            var o = new SvgOptions ();
            o.native = false;
            o.only = nodes;
            var box = Rect (0, 0, -1, -1);
            bool first = true;
            foreach (var n in nodes) {
                var b = n.visual_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            o.area = first ? Rect (0, 0, 1, 1) : box;
            return write (doc, o);
        }

        private string next_id (string prefix) {
            return "%s%d".printf (prefix, ++ids);
        }

        private string n (double v) {
            return PathData.fmt (v, opts.decimals);
        }

        private string esc (string s) {
            return Markup.escape_text (s);
        }

        private string nl () {
            return opts.minify ? "" : "\n";
        }

        private Rect area () {
            if (opts.area != null) return opts.area;
            if (opts.artboard >= 0 && opts.artboard < doc.artboards.size) return doc.artboards[opts.artboard].rect ();
            if (doc.artboards.size == 0) {
                var c = doc.content_bounds ();
                return c.w > 0 ? c : Rect (0, 0, 100, 100);
            }
            var box = doc.artboards[0].rect ();
            if (opts.all_artboards) foreach (var a in doc.artboards) box = box.union (a.rect ());
            return box;
        }

        private string document () {
            var r = area ();
            var body = new StringBuilder ();
            if (opts.only != null) {
                foreach (var node in opts.only) body.append (node_svg (node, 1));
            } else {
                foreach (var l in doc.layers) {
                    if (!l.printable && !opts.native) continue;
                    body.append (node_svg (l, 1));
                }
            }
            var out_svg = new StringBuilder ();
            out_svg.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + nl ());
            out_svg.append ("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"");
            if (!opts.responsive) out_svg.append (" width=\"%s\" height=\"%s\"".printf (n (r.w * opts.scale), n (r.h * opts.scale)));
            out_svg.append (" viewBox=\"%s %s %s %s\"".printf (n (r.x), n (r.y), n (r.w), n (r.h)));
            out_svg.append (">" + nl ());
            if (doc.title != "" && opts.native) out_svg.append ("<title>%s</title>%s".printf (esc (doc.title), nl ()));
            if (css.len > 0) out_svg.append ("<style>%s%s</style>%s".printf (nl (), css.str, nl ()));
            if (defs.len > 0) out_svg.append ("<defs>%s%s</defs>%s".printf (nl (), defs.str, nl ()));
            out_svg.append (body.str);
            if (opts.native) {
                string hash = Checksum.compute_for_string (ChecksumType.SHA256, out_svg.str);
                string native = NativeFormat.to_string (doc, true);
                uint8[] packed = Gzip.compress (native.data);
                out_svg.append ("<metadata><vector:document xmlns:vector=\"%s\" version=\"1\" encoding=\"gzip-base64\" preview-sha256=\"%s\">%s</vector:document></metadata>%s".printf (NS, hash, Base64.encode (packed), nl ()));
            }
            out_svg.append ("</svg>" + nl ());
            return out_svg.str;
        }

        private string style_attrs (Gee.HashMap<string, string> props) {
            if (props.size == 0) return "";
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (props.keys);
            keys.sort ();
            if (opts.styling == "inline") {
                var b = new StringBuilder ();
                foreach (var k in keys) b.append ("%s:%s;".printf (k, props[k]));
                return " style=\"%s\"".printf (esc (b.str));
            }
            if (opts.styling == "classes") {
                var b = new StringBuilder ();
                foreach (var k in keys) b.append ("%s:%s;".printf (k, props[k]));
                string decl = b.str;
                if (!classes.has_key (decl)) {
                    string cls = "cls-%d".printf (classes.size + 1);
                    classes[decl] = cls;
                    css.append (".%s{%s}%s".printf (cls, decl, nl ()));
                }
                return " class=\"%s\"".printf (classes[decl]);
            }
            var a = new StringBuilder ();
            foreach (var k in keys) {
                if (k == "mix-blend-mode" || k == "isolation") continue;
                a.append (" %s=\"%s\"".printf (k, esc (props[k])));
            }
            var extra = new StringBuilder ();
            foreach (var k in keys) if (k == "mix-blend-mode" || k == "isolation") extra.append ("%s:%s;".printf (k, props[k]));
            if (extra.len > 0) a.append (" style=\"%s\"".printf (extra.str));
            return a.str;
        }

        private string matrix_attr (Cairo.Matrix m) {
            if (m.xx == 1 && m.yx == 0 && m.xy == 0 && m.yy == 1 && m.x0 == 0 && m.y0 == 0) return "";
            return " transform=\"matrix(%s %s %s %s %s %s)\"".printf (n (m.xx), n (m.yx), n (m.xy), n (m.yy), n (m.x0), n (m.y0));
        }

        private string color (Ink ink) {
            var c = Renderer.resolve_ink (ink, ctx);
            return c.to_hex ();
        }

        private string paint_ref (Paint p, Rect box) {
            switch (p.kind) {
                case PaintKind.SOLID:
                    return color (p.color);
                case PaintKind.LINEAR:
                case PaintKind.RADIAL:
                    return "url(#%s)".printf (gradient_def (p));
                case PaintKind.PATTERN:
                    var id = pattern_def (p);
                    return id != null ? "url(#%s)".printf (id) : "none";
                case PaintKind.FREEFORM:
                    return "url(#%s)".printf (raster_paint_def (p, box));
                default:
                    return "none";
            }
        }

        private string gradient_def (Paint p) {
            var g = p.gradient;
            string id = next_id ("grad");
            var b = new StringBuilder ();
            if (p.kind == PaintKind.RADIAL) {
                double r = Math.hypot (g.x2 - g.x1, g.y2 - g.y1);
                double angle = Math.atan2 (g.y2 - g.y1, g.x2 - g.x1) * 180 / Math.PI;
                string tr = "";
                if ((g.aspect - 1).abs () > 1e-6) tr = " gradientTransform=\"translate(%s %s) rotate(%s) scale(1 %s) rotate(%s) translate(%s %s)\"".printf (n (g.x1), n (g.y1), n (angle), n (g.aspect), n (-angle), n (-g.x1), n (-g.y1));
                b.append ("<radialGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" cx=\"%s\" cy=\"%s\" r=\"%s\" fx=\"%s\" fy=\"%s\"%s spreadMethod=\"%s\">".printf (id, n (g.x1), n (g.y1), n (r), n (g.fx), n (g.fy), tr, g.spread));
            } else {
                b.append ("<linearGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" spreadMethod=\"%s\">".printf (id, n (g.x1), n (g.y1), n (g.x2), n (g.y2), g.spread));
            }
            var stops = new Gee.ArrayList<GradientStop> ();
            stops.add_all (g.stops);
            stops.sort ((x, y) => x.offset < y.offset ? -1 : x.offset > y.offset ? 1 : 0);
            for (int i = 0; i < stops.size; i++) {
                var s = stops[i];
                b.append ("<stop offset=\"%s\" stop-color=\"%s\"%s/>".printf (n (s.offset), color (s.color), s.opacity < 1 ? " stop-opacity=\"%s\"".printf (n (s.opacity)) : ""));
                if (i + 1 < stops.size && (s.midpoint - 0.5).abs () > 0.01) {
                    var nx = stops[i + 1];
                    var mid = Interpolate.ink (Renderer.resolve_ink (s.color, ctx), Renderer.resolve_ink (nx.color, ctx), 0.5);
                    b.append ("<stop offset=\"%s\" stop-color=\"%s\"/>".printf (n (s.offset + (nx.offset - s.offset) * s.midpoint), mid.to_hex ()));
                }
            }
            b.append (p.kind == PaintKind.RADIAL ? "</radialGradient>" : "</linearGradient>");
            defs.append (b.str + nl ());
            return id;
        }

        private string? pattern_def (Paint p) {
            var def = doc.find_pattern (p.pattern);
            if (def == null) return null;
            string id = next_id ("pat");
            var tile_box = def.tile.geometric_bounds ();
            double ox = tile_box.w >= 0 ? -tile_box.x : 0, oy = tile_box.w >= 0 ? -tile_box.y : 0;
            double tw = def.w + def.hspace, th = def.h + def.vspace;
            double pw = tw, ph = th;
            var b = new StringBuilder ();
            var content = new StringBuilder ();
            var saved_only = opts.only;
            string inner = node_svg (def.tile, 2);
            if (def.tiling == "brick-row" || def.tiling == "hex-row") {
                ph = def.tiling == "hex-row" ? th * 1.5 : th * 2;
                double shift = def.tiling == "hex-row" ? tw / 2 : def.offset * tw;
                double dy = def.tiling == "hex-row" ? th * 0.75 : th;
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox), n (oy), inner));
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox + shift), n (oy + dy), inner));
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox + shift - tw), n (oy + dy), inner));
            } else if (def.tiling == "brick-col" || def.tiling == "hex-col") {
                pw = def.tiling == "hex-col" ? tw * 1.5 : tw * 2;
                double shift = def.tiling == "hex-col" ? th / 2 : def.offset * th;
                double dx = def.tiling == "hex-col" ? tw * 0.75 : tw;
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox), n (oy), inner));
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox + dx), n (oy + shift), inner));
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox + dx), n (oy + shift - th), inner));
            } else {
                content.append ("<g transform=\"translate(%s %s)\">%s</g>".printf (n (ox), n (oy), inner));
            }
            opts.only = saved_only;
            var m = p.pattern_matrix;
            string tr = "";
            if (!(m.xx == 1 && m.yx == 0 && m.xy == 0 && m.yy == 1 && m.x0 == 0 && m.y0 == 0)) tr = " patternTransform=\"matrix(%s %s %s %s %s %s)\"".printf (n (m.xx), n (m.yx), n (m.xy), n (m.yy), n (m.x0), n (m.y0));
            b.append ("<pattern id=\"%s\" patternUnits=\"userSpaceOnUse\" width=\"%s\" height=\"%s\"%s>%s</pattern>".printf (id, n (pw), n (ph), tr, content.str));
            defs.append (b.str + nl ());
            return id;
        }

        private string raster_paint_def (Paint p, Rect box) {
            string id = next_id ("img");
            double scale = 2;
            int w = int.max (1, (int) (box.w * scale)), h = int.max (1, (int) (box.h * scale));
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            cr.scale (scale, scale);
            cr.translate (-box.x, -box.y);
            Renderer.set_paint (cr, p, box, ctx);
            cr.paint ();
            string data = png_base64 (surface);
            defs.append ("<pattern id=\"%s\" patternUnits=\"userSpaceOnUse\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\"><image width=\"%s\" height=\"%s\" href=\"data:image/png;base64,%s\"/></pattern>%s".printf (id, n (box.x), n (box.y), n (box.w), n (box.h), n (box.w), n (box.h), data, nl ()));
            return id;
        }

        public static string png_base64 (Cairo.ImageSurface surface) {
            var buffer = new ByteArray ();
            surface.write_to_png_stream ((data) => {
                buffer.append (data);
                return Cairo.Status.SUCCESS;
            });
            return Base64.encode (buffer.data);
        }

        private string? filter_def (Node node) {
            var parts = new StringBuilder ();
            var merge = new Gee.ArrayList<string> ();
            int k = 0;
            bool blur_source = false;
            foreach (var e in node.effects) {
                if (!e.enabled || !e.is_raster ()) continue;
                k++;
                string res = "e%d".printf (k);
                switch (e.kind) {
                    case "drop-shadow":
                        var c = Ink.hex (e.get_str ("color", "#000000"));
                        parts.append ("<feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"%s\"/>".printf (n (e.get_num ("blur", 5) / 2)));
                        parts.append ("<feOffset dx=\"%s\" dy=\"%s\" result=\"%so\"/>".printf (n (e.get_num ("dx", 7)), n (e.get_num ("dy", 7)), res));
                        parts.append ("<feFlood flood-color=\"%s\" flood-opacity=\"%s\"/>".printf (c.to_hex (), n (e.get_num ("opacity", 0.6))));
                        parts.append ("<feComposite in2=\"%so\" operator=\"in\" result=\"%s\"/>".printf (res, res));
                        merge.add (res);
                        break;
                    case "outer-glow":
                        var c = Ink.hex (e.get_str ("color", "#000000"));
                        parts.append ("<feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"%s\" result=\"%sb\"/>".printf (n (e.get_num ("blur", 5) / 2), res));
                        parts.append ("<feFlood flood-color=\"%s\" flood-opacity=\"%s\"/>".printf (c.to_hex (), n (e.get_num ("opacity", 0.75))));
                        parts.append ("<feComposite in2=\"%sb\" operator=\"in\" result=\"%s\"/>".printf (res, res));
                        merge.add (res);
                        break;
                    case "blur":
                        parts.append ("<feGaussianBlur in=\"SourceGraphic\" stdDeviation=\"%s\" result=\"src\"/>".printf (n (e.get_num ("blur", 5) / 2)));
                        blur_source = true;
                        break;
                    case "feather":
                        parts.append ("<feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"%s\" result=\"fa\"/><feComposite in=\"SourceGraphic\" in2=\"fa\" operator=\"in\" result=\"src\"/>".printf (n (e.get_num ("blur", 5) / 2)));
                        blur_source = true;
                        break;
                    case "inner-glow":
                        var c = Ink.hex (e.get_str ("color", "#ffffff"));
                        parts.append ("<feComponentTransfer in=\"SourceAlpha\" result=\"%si\"><feFuncA type=\"table\" tableValues=\"1 0\"/></feComponentTransfer>".printf (res));
                        parts.append ("<feGaussianBlur in=\"%si\" stdDeviation=\"%s\" result=\"%sb\"/>".printf (res, n (e.get_num ("blur", 5) / 2), res));
                        parts.append ("<feFlood flood-color=\"%s\" flood-opacity=\"%s\"/>".printf (c.to_hex (), n (e.get_num ("opacity", 0.75))));
                        parts.append ("<feComposite in2=\"%sb\" operator=\"in\"/>".printf (res));
                        parts.append ("<feComposite in2=\"SourceAlpha\" operator=\"in\" result=\"%s\"/>".printf (res));
                        merge.add ("@" + res);
                        break;
                }
            }
            if (k == 0) return null;
            string id = next_id ("fx");
            var m = new StringBuilder ("<feMerge>");
            foreach (var r in merge) if (!r.has_prefix ("@")) m.append ("<feMergeNode in=\"%s\"/>".printf (r));
            m.append ("<feMergeNode in=\"%s\"/>".printf (blur_source ? "src" : "SourceGraphic"));
            foreach (var r in merge) if (r.has_prefix ("@")) m.append ("<feMergeNode in=\"%s\"/>".printf (r.substring (1)));
            m.append ("</feMerge>");
            defs.append ("<filter id=\"%s\" x=\"-50%%\" y=\"-50%%\" width=\"200%%\" height=\"200%%\" color-interpolation-filters=\"sRGB\">%s%s</filter>%s".printf (id, parts.str, m.str, nl ()));
            return id;
        }

        private string common (Node node) {
            var b = new StringBuilder ();
            if (node.name != "" && !opts.minify) b.append (" id=\"%s\"".printf (esc (safe_id (node.name))));
            var props = new Gee.HashMap<string, string> ();
            if (node.opacity < 1) props["opacity"] = n (node.opacity);
            if (node.blend != BlendMode.NORMAL) props["mix-blend-mode"] = node.blend.to_id ();
            if (node.isolate) props["isolation"] = "isolate";
            if (node.hidden) props["display"] = "none";
            b.append (style_attrs (props));
            var f = filter_def (node);
            if (f != null) b.append (" filter=\"url(#%s)\"".printf (f));
            if (node.mask != null) b.append (" mask=\"url(#%s)\"".printf (mask_def (node)));
            return b.str;
        }

        private string safe_id (string name) {
            var b = new StringBuilder ();
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) b.append_unichar (c.isalnum () || c == '-' || c == '_' ? c : '_');
            string r = b.str;
            if (r == "" || r.get_char (0).isdigit ()) r = "n" + r;
            return r + "-" + (++ids).to_string ();
        }

        private string mask_def (Node node) {
            string id = next_id ("mask");
            var inner = node_svg (node.mask, 2);
            string content = inner;
            if (node.mask_invert) {
                string fid = next_id ("inv");
                defs.append ("<filter id=\"%s\"><feColorMatrix type=\"matrix\" values=\"-1 0 0 0 1 0 -1 0 0 1 0 0 -1 0 1 0 0 0 1 0\"/></filter>%s".printf (fid, nl ()));
                var b = node.visual_bounds ().union (node.mask.visual_bounds ());
                content = "<g filter=\"url(#%s)\"><rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"#000000\"/>%s</g>".printf (fid, n (b.x), n (b.y), n (b.w), n (b.h), inner);
            } else if (!node.mask_clip) {
                var b = node.visual_bounds ();
                content = "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"#ffffff\"/>%s".printf (n (b.x), n (b.y), n (b.w), n (b.h), inner);
            }
            defs.append ("<mask id=\"%s\" maskUnits=\"userSpaceOnUse\" x=\"-100000\" y=\"-100000\" width=\"200000\" height=\"200000\">%s</mask>%s".printf (id, content, nl ()));
            return id;
        }

        private string indent (int depth) {
            if (opts.minify) return "";
            return string.nfill (depth, ' ');
        }

        private Gee.HashMap<string, string> layer_props (PaintLayer l, Rect box, bool even_odd) {
            var props = new Gee.HashMap<string, string> ();
            if (l.stroke) {
                props["fill"] = "none";
                props["stroke"] = paint_ref (l.paint, box.inflate (l.width));
                props["stroke-width"] = n (l.width);
                if (l.cap == CapKind.ROUND) props["stroke-linecap"] = "round";
                else if (l.cap == CapKind.SQUARE) props["stroke-linecap"] = "square";
                if (l.join == JoinKind.ROUND) props["stroke-linejoin"] = "round";
                else if (l.join == JoinKind.BEVEL) props["stroke-linejoin"] = "bevel";
                else if (l.miter != 4) props["stroke-miterlimit"] = n (l.miter);
                if (l.dashes.length > 0) {
                    string[] parts = {};
                    foreach (double d in l.dashes) parts += n (d);
                    props["stroke-dasharray"] = string.joinv (" ", parts);
                    if (l.dash_offset != 0) props["stroke-dashoffset"] = n (l.dash_offset);
                }
                if (l.paint.kind == PaintKind.SOLID && l.opacity < 1) props["stroke-opacity"] = n (l.opacity);
            } else {
                props["fill"] = paint_ref (l.paint, box);
                if (even_odd) props["fill-rule"] = "evenodd";
                if (l.paint.kind == PaintKind.SOLID && l.opacity < 1) props["fill-opacity"] = n (l.opacity);
            }
            if (l.blend != BlendMode.NORMAL) props["mix-blend-mode"] = l.blend.to_id ();
            if (l.paint.kind != PaintKind.SOLID && l.opacity < 1) props["opacity"] = n (l.opacity);
            return props;
        }

        private static bool simple_layer (PaintLayer l) {
            return l.effects.size == 0 && l.brush == "" && l.profile.size == 0 && l.arrow_start == "" && l.arrow_end == "" && l.blend == BlendMode.NORMAL && (l.opacity >= 1 || l.paint.kind == PaintKind.SOLID);
        }

        private string path_layers (Node node, PathData geometry, bool even_odd, int depth, Ink? override_color = null) {
            var b = new StringBuilder ();
            var box = geometry.bounds ();
            var visible = new Gee.ArrayList<PaintLayer> ();
            foreach (var l in node.appearance) if (l.visible && l.paint.visible ()) visible.add (l);
            if (visible.size == 0) return "";
            if (visible.size == 2 && !visible[0].stroke && visible[1].stroke && override_color == null && simple_layer (visible[0]) && simple_layer (visible[1]) && !(visible[1].align != StrokeAlign.CENTER && PathOps.all_closed (geometry))) {
                var props = layer_props (visible[0], box, even_odd);
                foreach (var kv in layer_props (visible[1], box, false).entries) if (kv.key != "fill") props[kv.key] = kv.value;
                return "%s<path d=\"%s\"%s/>%s".printf (indent (depth), geometry.to_svg (opts.decimals), style_attrs (props), nl ());
            }
            foreach (var l in visible) {
                var geo = Renderer.vector_effects (geometry, l.effects);
                var layer = l;
                if (override_color != null && l.paint.kind == PaintKind.SOLID && !l.stroke) {
                    layer = l.copy ();
                    layer.paint = new Paint.solid (override_color);
                }
                if (l.stroke && (l.brush != "" || l.profile.size > 0 || (l.align != StrokeAlign.CENTER && PathOps.all_closed (geo)) || l.arrow_start != "" || l.arrow_end != "")) {
                    if (l.brush != "") {
                        var brush = doc.find_brush (l.brush);
                        if (brush != null) {
                            var expanded = Brushes.expand (geo, l, brush, ctx);
                            foreach (var c in expanded.children) b.append (node_svg (c, depth));
                            continue;
                        }
                    }
                    PathData outline;
                    if (l.profile.size > 0) outline = CurveOffset.variable (geo, l.width, l.profile, l.cap);
                    else outline = CurveOffset.stroke (l.dashes.length > 0 ? CurveOffset.dash (geo, l.dashes, l.dash_offset) : geo, l.width, l.join, l.cap, l.miter, l.align);
                    var fill_layer = new PaintLayer.fill (layer.paint.copy ());
                    fill_layer.opacity = l.opacity;
                    fill_layer.blend = l.blend;
                    b.append ("%s<path d=\"%s\"%s/>%s".printf (indent (depth), outline.to_svg (opts.decimals), style_attrs (layer_props (fill_layer, outline.bounds (), false)), nl ()));
                    continue;
                }
                b.append ("%s<path d=\"%s\"%s/>%s".printf (indent (depth), geo.to_svg (opts.decimals), style_attrs (layer_props (layer, box, even_odd)), nl ()));
            }
            return b.str;
        }

        private string wrap (Node node, string inner, int depth, string extra = "") {
            string c = common (node);
            if (c == "" && extra == "") return inner;
            return "%s<g%s%s>%s%s%s</g>%s".printf (indent (depth), c, extra, nl (), inner, indent (depth), nl ());
        }

        public string node_svg (Node node, int depth) {
            if (opts.only == null && !opts.native && node.hidden) return "";
            var g = node as GroupNode;
            if (g != null) {
                var gen = g.generated (doc);
                var inner = new StringBuilder ();
                string extra = "";
                if (g.is_layer && opts.native) extra = " data-layer=\"%s\"".printf (esc (g.name));
                if (gen != null) {
                    foreach (var c in gen.children) inner.append (node_svg (c, depth + 1));
                } else if (g.clip && g.children.size > 0) {
                    var cp = g.children[0].outline ();
                    string cid = next_id ("clip");
                    var cpn = g.children[0] as PathNode;
                    defs.append ("<clipPath id=\"%s\"><path d=\"%s\"%s/></clipPath>%s".printf (cid, cp != null ? cp.to_svg (opts.decimals) : "", cpn != null && cpn.even_odd ? " clip-rule=\"evenodd\"" : "", nl ()));
                    var clipped = new StringBuilder ();
                    for (int i = 1; i < g.children.size; i++) clipped.append (node_svg (g.children[i], depth + 2));
                    inner.append ("%s<g clip-path=\"url(#%s)\">%s%s%s</g>%s".printf (indent (depth + 1), cid, nl (), clipped.str, indent (depth + 1), nl ()));
                    if (cp != null) inner.append (path_layers (g.children[0], cp, cpn != null && cpn.even_odd, depth + 1));
                } else {
                    foreach (var c in g.children) inner.append (node_svg (c, depth + 1));
                }
                string c = common (node);
                return "%s<g%s%s>%s%s%s</g>%s".printf (indent (depth), c, extra, nl (), inner.str, indent (depth), nl ());
            }
            var pn = node as PathNode;
            if (pn != null) {
                if (pn.guide) return "";
                var geo = Renderer.vector_effects (pn.render_path (), node.effects);
                return wrap (node, path_layers (node, geo, pn.even_odd, depth + 1), depth);
            }
            var tn = node as TextNode;
            if (tn != null) return text_svg (tn, depth);
            var im = node as ImageNode;
            if (im != null) return wrap (node, image_svg (im, depth + 1), depth);
            var sy = node as SymbolNode;
            if (sy != null) return symbol_svg (sy, depth);
            var me = node as MeshNode;
            if (me != null) return wrap (node, mesh_svg (me, depth + 1), depth);
            return "";
        }

        private string text_svg (TextNode tn, int depth) {
            if (opts.text_outlines || tn.effects.size > 0) {
                var b = new StringBuilder ();
                foreach (var part in TextLayout.parts (tn)) b.append (path_layers (tn, Renderer.vector_effects (part.path, tn.effects), false, depth + 1, part.color));
                return wrap (tn, b.str, depth, " aria-label=\"%s\"".printf (esc (tn.text)));
            }
            var props = new Gee.HashMap<string, string> ();
            props["font-family"] = tn.style.family;
            props["font-size"] = n (tn.style.size);
            if (tn.style.weight != 400) props["font-weight"] = tn.style.weight.to_string ();
            if (tn.style.italic) props["font-style"] = "italic";
            if (tn.style.tracking != 0) props["letter-spacing"] = n (tn.style.tracking / 1000 * tn.style.size);
            if (tn.style.underline || tn.style.strike) props["text-decoration"] = (tn.style.underline ? "underline " : "") + (tn.style.strike ? "line-through" : "");
            if (tn.style.features != "") props["font-feature-settings"] = features_css (tn.style.features);
            if (tn.style.caps == "small") props["font-variant"] = "small-caps";
            if (tn.style.caps == "all") props["text-transform"] = "uppercase";
            var fill = tn.first_fill ();
            props["fill"] = fill != null && fill.paint.visible () ? paint_ref (fill.paint, tn.geometric_bounds ()) : "none";
            var stroke = tn.first_stroke ();
            if (stroke != null && stroke.paint.visible ()) {
                props["stroke"] = paint_ref (stroke.paint, tn.geometric_bounds ());
                props["stroke-width"] = n (stroke.width);
            }
            var b = new StringBuilder ();
            if (tn.mode == "path" && tn.on_path != null) {
                string pid = next_id ("tp");
                var path = tn.path_flip ? PathOps.reversed (tn.on_path) : tn.on_path;
                defs.append ("<path id=\"%s\" d=\"%s\"/>%s".printf (pid, path.to_svg (opts.decimals), nl ()));
                string anchor = tn.para.align == "center" ? " text-anchor=\"middle\" startOffset=\"50%\"" : (tn.para.align == "right" ? " text-anchor=\"end\" startOffset=\"100%\"" : " startOffset=\"%s\"".printf (n (tn.path_offset)));
                b.append ("%s<text%s%s><textPath href=\"#%s\"%s>%s</textPath></text>%s".printf (indent (depth), style_attrs (props), common (tn), pid, anchor, runs_svg (tn, 0, tn.text.length), nl ()));
                return b.str;
            }
            var lines = TextLayout.lines (tn);
            var m = tn.mode == "area" ? Cairo.Matrix.identity () : tn.matrix;
            if (tn.style.hscale != 1 || tn.style.vscale != 1) {
                var s = Cairo.Matrix.identity ();
                s.scale (tn.style.hscale, tn.style.vscale);
                m = Transforms.multiply (s, m);
            }
            var head = tn.mode == "area" ? TextLayout.chain_head (tn) : tn;
            b.append ("%s<text xml:space=\"preserve\"%s%s%s>".printf (indent (depth), style_attrs (props), matrix_attr (m), common (tn)));
            foreach (var line in lines) {
                int end = int.min (line.start + line.length, head.text.length);
                string chunk = runs_svg (head, line.start, end);
                b.append ("<tspan x=\"%s\" y=\"%s\">%s</tspan>".printf (n (line.x), n (line.y), chunk));
            }
            b.append ("</text>" + nl ());
            return b.str;
        }

        private string features_css (string features) {
            string[] parts = {};
            foreach (var f in features.split (",")) {
                var kv = f.strip ().split ("=");
                if (kv[0] == "") continue;
                parts += "\"%s\" %s".printf (kv[0], kv.length > 1 ? kv[1] : "1");
            }
            return string.joinv (",", parts);
        }

        private string runs_svg (TextNode tn, int start, int end) {
            if (end <= start) return "";
            string text = tn.text;
            var cuts = new Gee.TreeSet<int> ();
            cuts.add (start);
            cuts.add (end);
            foreach (var r in tn.runs) {
                if (r.start > start && r.start < end) cuts.add (r.start);
                if (r.end > start && r.end < end) cuts.add (r.end);
            }
            var b = new StringBuilder ();
            int prev = -1;
            foreach (int c in cuts) {
                if (prev >= 0) {
                    string piece = text.substring (prev, c - prev).replace ("\n", "");
                    TextRun? run = null;
                    foreach (var r in tn.runs) if (prev >= r.start && prev < r.end) run = r;
                    if (run == null) {
                        b.append (esc (piece));
                    } else {
                        var props = new Gee.HashMap<string, string> ();
                        var s = run.style;
                        if (s.family != tn.style.family) props["font-family"] = s.family;
                        if (s.size != tn.style.size) props["font-size"] = n (s.size);
                        if (s.weight != tn.style.weight) props["font-weight"] = s.weight.to_string ();
                        if (s.italic != tn.style.italic) props["font-style"] = s.italic ? "italic" : "normal";
                        if (s.color != null) props["fill"] = color (s.color);
                        if (s.baseline != 0) props["baseline-shift"] = n (-s.baseline);
                        if (s.tracking != 0) props["letter-spacing"] = n (s.tracking / 1000 * s.size);
                        if (s.underline) props["text-decoration"] = "underline";
                        b.append ("<tspan%s>%s</tspan>".printf (style_attrs (props), esc (piece)));
                    }
                }
                prev = c;
            }
            return b.str;
        }

        private string image_svg (ImageNode im, int depth) {
            string href;
            if (im.link != "" && opts.link_images) {
                href = File.new_for_path (im.link).get_uri ();
            } else if (doc.assets.has_key (im.asset)) {
                href = "data:%s;base64,%s".printf (doc.assets[im.asset].mime, Base64.encode (doc.assets[im.asset].data.get_data ()));
            } else if (im.link != "") {
                try {
                    uint8[] data;
                    FileUtils.get_data (im.link, out data);
                    href = "data:%s;base64,%s".printf (im.mime, Base64.encode (data));
                } catch (Error e) {
                    href = File.new_for_path (im.link).get_uri ();
                }
            } else {
                return "";
            }
            return "%s<image width=\"%d\" height=\"%d\" preserveAspectRatio=\"none\"%s href=\"%s\"/>%s".printf (indent (depth), im.pixel_width, im.pixel_height, matrix_attr (im.matrix), href, nl ());
        }

        private string symbol_svg (SymbolNode sy, int depth) {
            var def = doc.find_symbol (sy.symbol);
            if (def == null) return "";
            if (sy.overrides.size > 0) {
                var art = sy.resolve (doc);
                return art != null ? wrap (sy, node_svg (art, depth + 1), depth) : "";
            }
            string sid = "sym-" + def.id;
            if (!symbols_written.contains (sid)) {
                symbols_written.add (sid);
                var inner = new StringBuilder ();
                foreach (var c in def.art.children) inner.append (node_svg (c, 2));
                defs.append ("<symbol id=\"%s\" overflow=\"visible\">%s%s</symbol>%s".printf (sid, opts.native && !opts.minify ? "<title>%s</title>".printf (esc (def.name)) : "", inner.str, nl ()));
            }
            return "%s<use href=\"#%s\"%s%s/>%s".printf (indent (depth), sid, matrix_attr (sy.matrix), common (sy), nl ());
        }

        private string mesh_svg (MeshNode me, int depth) {
            var box = me.geometric_bounds ();
            double scale = 2;
            int w = int.max (1, (int) (box.w * scale)), h = int.max (1, (int) (box.h * scale));
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            cr.scale (scale, scale);
            cr.translate (-box.x, -box.y);
            Renderer.draw_mesh (cr, me);
            return "%s<image x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" preserveAspectRatio=\"none\" href=\"data:image/png;base64,%s\"/>%s".printf (indent (depth), n (box.x), n (box.y), n (box.w), n (box.h), png_base64 (surface), nl ());
        }
    }

    public class Gzip {
        public static uint8[] compress (uint8[] data) {
            try {
                var conv = new ZlibCompressor (ZlibCompressorFormat.GZIP, 9);
                var mem = new MemoryOutputStream.resizable ();
                var stream = new ConverterOutputStream (mem, conv);
                stream.write_all (data, null);
                stream.close ();
                var bytes = mem.steal_as_bytes ();
                return bytes.get_data ();
            } catch (Error e) {
                return data;
            }
        }

        public static uint8[] decompress (uint8[] data) throws Error {
            var conv = new ZlibDecompressor (ZlibCompressorFormat.GZIP);
            var mem = new MemoryOutputStream.resizable ();
            var input = new ConverterInputStream (new MemoryInputStream.from_data (data), conv);
            mem.splice (input, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            var bytes = mem.steal_as_bytes ();
            return bytes.get_data ();
        }
    }
}
