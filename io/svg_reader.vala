using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class SvgStyle {
        public string fill = "#000000";
        public string stroke = "none";
        public double stroke_width = 1;
        public double fill_opacity = 1;
        public double stroke_opacity = 1;
        public string linecap = "butt";
        public string linejoin = "miter";
        public double miter = 4;
        public string dasharray = "none";
        public double dashoffset = 0;
        public string fill_rule = "nonzero";
        public string font_family = "Sans";
        public double font_size = 16;
        public string font_weight = "normal";
        public string font_style = "normal";
        public string text_anchor = "start";
        public double letter_spacing = 0;
        public string text_decoration = "none";
        public string color = "#000000";
        public bool display = true;
        public bool visible = true;

        public SvgStyle copy () {
            var s = new SvgStyle ();
            s.fill = fill;
            s.stroke = stroke;
            s.stroke_width = stroke_width;
            s.fill_opacity = fill_opacity;
            s.stroke_opacity = stroke_opacity;
            s.linecap = linecap;
            s.linejoin = linejoin;
            s.miter = miter;
            s.dasharray = dasharray;
            s.dashoffset = dashoffset;
            s.fill_rule = fill_rule;
            s.font_family = font_family;
            s.font_size = font_size;
            s.font_weight = font_weight;
            s.font_style = font_style;
            s.text_anchor = text_anchor;
            s.letter_spacing = letter_spacing;
            s.text_decoration = text_decoration;
            s.color = color;
            s.visible = visible;
            return s;
        }
    }

    public class CssRule {
        public string selector;
        public Gee.HashMap<string, string> props;

        public CssRule (string selector, Gee.HashMap<string, string> props) {
            this.selector = selector;
            this.props = props;
        }
    }

    public class SvgReader {
        private VectorDocument doc;
        private Gee.HashMap<string, Xml.Node*> ids = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.ArrayList<CssRule> rules = new Gee.ArrayList<CssRule> ();
        private string? base_dir;
        private int depth_guard = 0;
        private Gee.HashSet<string> symbols_done = new Gee.HashSet<string> ();

        private SvgReader (string? base_dir) {
            this.base_dir = base_dir;
            doc = new VectorDocument ();
        }

        public static VectorDocument parse (string text, string? base_dir = null) throws Error {
            Xml.Doc* xml = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING | Xml.ParserOption.HUGE);
            if (xml == null || xml->get_root_element () == null) throw new IOError.INVALID_DATA (_("The file is not a valid SVG document."));
            try {
                var root = xml->get_root_element ();
                if (root->name != "svg") throw new IOError.INVALID_DATA (_("The file is not an SVG document."));
                var native = native_document (root, text);
                if (native != null) return native;
                var reader = new SvgReader (base_dir);
                return reader.import (root);
            } finally {
                delete xml;
            }
        }

        private static VectorDocument? native_document (Xml.Node* root, string text) {
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "metadata") continue;
                for (Xml.Node* m = c->children; m != null; m = m->next) {
                    if (m->type != Xml.ElementType.ELEMENT_NODE || m->name != "document" || m->ns == null || m->ns->href != SvgWriter.NS) continue;
                    string? hash = m->get_prop ("preview-sha256");
                    string content = m->get_content ().strip ();
                    int meta = text.last_index_of ("<metadata><vector:document");
                    if (meta < 0 || hash == null) return null;
                    string preview = text.substring (0, meta);
                    if (Checksum.compute_for_string (ChecksumType.SHA256, preview) != hash) return null;
                    try {
                        uint8[] data = Base64.decode (content);
                        if (m->get_prop ("encoding") == "gzip-base64") data = Gzip.decompress (data);
                        string json = ((string) data).substring (0, data.length);
                        var d = NativeFormat.parse (json);
                        d.modified = false;
                        d.clear_history ();
                        return d;
                    } catch (Error e) {
                        return null;
                    }
                }
            }
            return null;
        }

        private void index (Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string? id = c->get_prop ("id");
                if (id != null) ids[id] = c;
                if (c->name == "style") parse_css (c->get_content ());
                index (c);
            }
        }

        private void parse_css (string text) {
            string clean = text;
            int a;
            while ((a = clean.index_of ("/*")) >= 0) {
                int b = clean.index_of ("*/", a + 2);
                clean = clean.substring (0, a) + (b >= 0 ? clean.substring (b + 2) : "");
            }
            foreach (var block in clean.split ("}")) {
                int brace = block.index_of ("{");
                if (brace < 0) continue;
                string selectors = block.substring (0, brace).strip ();
                var props = declarations (block.substring (brace + 1));
                if (selectors.has_prefix ("@")) continue;
                foreach (var sel in selectors.split (",")) rules.add (new CssRule (sel.strip (), props));
            }
        }

        public static Gee.HashMap<string, string> declarations (string text) {
            var props = new Gee.HashMap<string, string> ();
            foreach (var decl in text.split (";")) {
                int colon = decl.index_of (":");
                if (colon < 0) continue;
                string k = decl.substring (0, colon).strip ().down ();
                string v = decl.substring (colon + 1).strip ();
                if (v.has_suffix ("!important")) v = v.substring (0, v.length - 10).strip ();
                props[k] = v;
            }
            return props;
        }

        private bool matches (string sel, Xml.Node* n) {
            string s = sel.strip ();
            if (s.contains (" ") || s.contains (">")) {
                var parts = s.replace (">", " ").split (" ");
                string last = "";
                foreach (var p in parts) if (p.strip () != "") last = p.strip ();
                return matches (last, n);
            }
            string? id = n->get_prop ("id");
            string? cls = n->get_prop ("class");
            if (s.has_prefix ("#")) return id != null && id == s.substring (1);
            string element = s;
            string? klass = null;
            int dot = s.index_of (".");
            if (dot >= 0) {
                element = s.substring (0, dot);
                klass = s.substring (dot + 1);
            }
            if (element != "" && element != "*" && element != n->name) return false;
            if (klass != null) {
                if (cls == null) return false;
                bool found = false;
                foreach (var c in cls.split (" ")) if (c.strip () == klass) found = true;
                return found;
            }
            return element != "";
        }

        private Gee.HashMap<string, string> props_of (Xml.Node* n) {
            var props = new Gee.HashMap<string, string> ();
            string[] names = { "fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "fill-rule", "clip-rule", "font-family", "font-size", "font-weight", "font-style", "text-anchor", "letter-spacing", "text-decoration", "color", "display", "visibility", "opacity", "mix-blend-mode", "stop-color", "stop-opacity", "isolation" };
            foreach (var name in names) {
                string? v = n->get_prop (name);
                if (v != null) props[name] = v.strip ();
            }
            foreach (var r in rules) if (matches (r.selector, n)) foreach (var kv in r.props.entries) props[kv.key] = kv.value;
            string? style = n->get_prop ("style");
            if (style != null) foreach (var kv in declarations (style).entries) props[kv.key] = kv.value;
            return props;
        }

        private SvgStyle apply_style (SvgStyle parent, Gee.HashMap<string, string> p) {
            var s = parent.copy ();
            s.display = true;
            if (p.has_key ("color")) s.color = p["color"];
            if (p.has_key ("fill")) s.fill = p["fill"] == "currentColor" ? s.color : p["fill"];
            if (p.has_key ("stroke")) s.stroke = p["stroke"] == "currentColor" ? s.color : p["stroke"];
            if (p.has_key ("stroke-width")) s.stroke_width = length (p["stroke-width"], 1);
            if (p.has_key ("fill-opacity")) s.fill_opacity = number (p["fill-opacity"], 1);
            if (p.has_key ("stroke-opacity")) s.stroke_opacity = number (p["stroke-opacity"], 1);
            if (p.has_key ("stroke-linecap")) s.linecap = p["stroke-linecap"];
            if (p.has_key ("stroke-linejoin")) s.linejoin = p["stroke-linejoin"];
            if (p.has_key ("stroke-miterlimit")) s.miter = number (p["stroke-miterlimit"], 4);
            if (p.has_key ("stroke-dasharray")) s.dasharray = p["stroke-dasharray"];
            if (p.has_key ("stroke-dashoffset")) s.dashoffset = length (p["stroke-dashoffset"], 0);
            if (p.has_key ("fill-rule")) s.fill_rule = p["fill-rule"];
            if (p.has_key ("font-family")) s.font_family = p["font-family"].replace ("'", "").replace ("\"", "").split (",")[0].strip ();
            if (p.has_key ("font-size")) s.font_size = length (p["font-size"], s.font_size);
            if (p.has_key ("font-weight")) s.font_weight = p["font-weight"];
            if (p.has_key ("font-style")) s.font_style = p["font-style"];
            if (p.has_key ("text-anchor")) s.text_anchor = p["text-anchor"];
            if (p.has_key ("letter-spacing")) s.letter_spacing = length (p["letter-spacing"], 0);
            if (p.has_key ("text-decoration")) s.text_decoration = p["text-decoration"];
            if (p.has_key ("display") && p["display"] == "none") s.display = false;
            if (p.has_key ("visibility")) s.visible = p["visibility"] != "hidden" && p["visibility"] != "collapse";
            return s;
        }

        public static double number (string? s, double fallback) {
            if (s == null) return fallback;
            string t = s.strip ();
            if (t.has_suffix ("%")) return double.parse (t.substring (0, t.length - 1)) / 100;
            double v;
            if (double.try_parse (t, out v)) return v;
            var sc = new PathScanner (t);
            if (sc.number (out v)) return v;
            return fallback;
        }

        public static double length (string? s, double fallback, double percent_base = 100) {
            if (s == null) return fallback;
            string t = s.strip ();
            double f = 1;
            if (t.has_suffix ("px")) t = t.substring (0, t.length - 2);
            else if (t.has_suffix ("pt")) {
                t = t.substring (0, t.length - 2);
                f = 96.0 / 72;
            } else if (t.has_suffix ("mm")) {
                t = t.substring (0, t.length - 2);
                f = 96.0 / 25.4;
            } else if (t.has_suffix ("cm")) {
                t = t.substring (0, t.length - 2);
                f = 96.0 / 2.54;
            } else if (t.has_suffix ("in")) {
                t = t.substring (0, t.length - 2);
                f = 96;
            } else if (t.has_suffix ("pc")) {
                t = t.substring (0, t.length - 2);
                f = 16;
            } else if (t.has_suffix ("em")) {
                t = t.substring (0, t.length - 2);
                f = 16;
            } else if (t.has_suffix ("%")) {
                t = t.substring (0, t.length - 1);
                f = percent_base / 100;
            }
            double v;
            if (!double.try_parse (t.strip (), out v)) {
                var sc = new PathScanner (t);
                if (!sc.number (out v)) return fallback;
            }
            return v * f;
        }

        public static Cairo.Matrix transform (string? text) {
            var m = Cairo.Matrix.identity ();
            if (text == null) return m;
            string t = text;
            int pos = 0;
            while (pos < t.length) {
                int open = t.index_of ("(", pos);
                if (open < 0) break;
                int close = t.index_of (")", open);
                if (close < 0) break;
                string name = t.substring (pos, open - pos).strip ().replace (",", "").strip ();
                double[] v = {};
                var sc = new PathScanner (t.substring (open + 1, close - open - 1));
                double x;
                while (sc.number (out x)) v += x;
                var step = Cairo.Matrix.identity ();
                switch (name) {
                    case "matrix":
                        if (v.length == 6) step = Cairo.Matrix (v[0], v[1], v[2], v[3], v[4], v[5]);
                        break;
                    case "translate":
                        step.translate (v.length > 0 ? v[0] : 0, v.length > 1 ? v[1] : 0);
                        break;
                    case "scale":
                        step.scale (v.length > 0 ? v[0] : 1, v.length > 1 ? v[1] : (v.length > 0 ? v[0] : 1));
                        break;
                    case "rotate":
                        if (v.length >= 3) {
                            step.translate (v[1], v[2]);
                            step.rotate (v[0] * Math.PI / 180);
                            step.translate (-v[1], -v[2]);
                        } else if (v.length > 0) {
                            step.rotate (v[0] * Math.PI / 180);
                        }
                        break;
                    case "skewX":
                        if (v.length > 0) step = Cairo.Matrix (1, 0, Math.tan (v[0] * Math.PI / 180), 1, 0, 0);
                        break;
                    case "skewY":
                        if (v.length > 0) step = Cairo.Matrix (1, Math.tan (v[0] * Math.PI / 180), 0, 1, 0, 0);
                        break;
                }
                m = Transforms.multiply (step, m);
                pos = close + 1;
            }
            return m;
        }

        public static Ink? color (string? text) {
            if (text == null) return null;
            string t = text.strip ().down ();
            if (t == "none" || t == "transparent" || t == "") return null;
            if (t.has_prefix ("#")) {
                var ink = new Ink ();
                if (ink.set_hex (t)) return ink;
                return null;
            }
            if (t.has_prefix ("rgb")) {
                int a = t.index_of ("("), b = t.index_of (")");
                if (a < 0 || b < 0) return null;
                var parts = t.substring (a + 1, b - a - 1).replace ("/", ",").replace (" ", ",").split (",");
                double[] v = {};
                foreach (var p in parts) {
                    if (p.strip () == "") continue;
                    v += p.has_suffix ("%") ? double.parse (p.substring (0, p.length - 1)) * 2.55 : double.parse (p);
                }
                if (v.length < 3) return null;
                return new Ink.rgb (v[0] / 255, v[1] / 255, v[2] / 255);
            }
            if (t.has_prefix ("hsl")) {
                int a = t.index_of ("("), b = t.index_of (")");
                if (a < 0 || b < 0) return null;
                var parts = t.substring (a + 1, b - a - 1).replace ("%", "").replace (" ", ",").split (",");
                double[] v = {};
                foreach (var p in parts) if (p.strip () != "") v += double.parse (p);
                if (v.length < 3) return null;
                return Ink.from_hsl (v[0] / 360, v[1] / 100, v[2] / 100);
            }
            string? hex = named (t);
            return hex != null ? Ink.hex (hex) : null;
        }

        private static string? named (string name) {
            switch (name) {
                case "black": return "#000000";
                case "white": return "#ffffff";
                case "red": return "#ff0000";
                case "green": return "#008000";
                case "lime": return "#00ff00";
                case "blue": return "#0000ff";
                case "yellow": return "#ffff00";
                case "cyan":
                case "aqua": return "#00ffff";
                case "magenta":
                case "fuchsia": return "#ff00ff";
                case "gray":
                case "grey": return "#808080";
                case "silver": return "#c0c0c0";
                case "maroon": return "#800000";
                case "olive": return "#808000";
                case "purple": return "#800080";
                case "teal": return "#008080";
                case "navy": return "#000080";
                case "orange": return "#ffa500";
                case "pink": return "#ffc0cb";
                case "brown": return "#a52a2a";
                case "gold": return "#ffd700";
                case "indigo": return "#4b0082";
                case "violet": return "#ee82ee";
                case "darkgray":
                case "darkgrey": return "#a9a9a9";
                case "lightgray":
                case "lightgrey": return "#d3d3d3";
                case "darkblue": return "#00008b";
                case "darkred": return "#8b0000";
                case "darkgreen": return "#006400";
                case "skyblue": return "#87ceeb";
                case "tomato": return "#ff6347";
                case "coral": return "#ff7f50";
                case "salmon": return "#fa8072";
                case "khaki": return "#f0e68c";
                case "beige": return "#f5f5dc";
                case "tan": return "#d2b48c";
                case "crimson": return "#dc143c";
                case "turquoise": return "#40e0d0";
                case "steelblue": return "#4682b4";
                case "royalblue": return "#4169e1";
                case "slategray": return "#708090";
                case "whitesmoke": return "#f5f5f5";
                case "chocolate": return "#d2691e";
                case "orchid": return "#da70d6";
                case "plum": return "#dda0dd";
                case "lavender": return "#e6e6fa";
                default: return null;
            }
        }

        private Xml.Node* resolve_href (Xml.Node* n) {
            string? href = n->get_prop ("href");
            if (href == null) href = n->get_ns_prop ("href", "http://www.w3.org/1999/xlink");
            if (href == null || !href.has_prefix ("#")) return null;
            string id = href.substring (1);
            return ids.has_key (id) ? ids[id] : null;
        }

        private string? url_id (string? value) {
            if (value == null) return null;
            string v = value.strip ();
            if (!v.has_prefix ("url(")) return null;
            int a = v.index_of ("#"), b = v.index_of (")");
            if (a < 0 || b < a) return null;
            return v.substring (a + 1, b - a - 1).replace ("'", "").replace ("\"", "");
        }

        private string? gattr (Xml.Node* n, string name) {
            int guard = 0;
            Xml.Node* cur = n;
            while (cur != null && guard++ < 16) {
                string? v = cur->get_prop (name);
                if (v != null) return v;
                cur = resolve_href (cur);
            }
            return null;
        }

        private Paint? gradient_paint (string id, Rect bbox, Cairo.Matrix ctm) {
            if (!ids.has_key (id)) return null;
            Xml.Node* g = ids[id];
            if (g->name == "pattern" || g->name == "meshgradient") return null;
            var paint = new Paint ();
            paint.kind = g->name == "radialGradient" ? PaintKind.RADIAL : PaintKind.LINEAR;
            Xml.Node* stops_owner = g;
            int guard = 0;
            while (stops_owner != null && guard++ < 16) {
                bool has = false;
                for (Xml.Node* c = stops_owner->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "stop") has = true;
                if (has) break;
                stops_owner = resolve_href (stops_owner);
            }
            if (stops_owner != null) {
                for (Xml.Node* c = stops_owner->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "stop") continue;
                    var p = props_of (c);
                    double off = number (c->get_prop ("offset"), 0).clamp (0, 1);
                    var ink = color (p.has_key ("stop-color") ? p["stop-color"] : "#000000") ?? new Ink ();
                    double op = p.has_key ("stop-opacity") ? number (p["stop-opacity"], 1) : 1;
                    paint.gradient.stops.add (new GradientStop (off, ink, op));
                }
            }
            if (paint.gradient.stops.size == 0) return null;
            if (paint.gradient.stops.size == 1) return new Paint.solid (paint.gradient.stops[0].color);
            bool bbox_units = gattr (g, "gradientUnits") != "userSpaceOnUse";
            var gt = transform (gattr (g, "gradientTransform"));
            var m = gt;
            if (bbox_units) {
                var bm = Cairo.Matrix (bbox.w, 0, 0, bbox.h, bbox.x, bbox.y);
                m = Transforms.multiply (gt, bm);
            } else {
                m = Transforms.multiply (gt, ctm);
            }
            var gr = paint.gradient;
            string spread = gattr (g, "spreadMethod") ?? "pad";
            gr.spread = spread;
            if (paint.kind == PaintKind.LINEAR) {
                double x1 = length (gattr (g, "x1"), 0, bbox_units ? 1 : 100), y1 = length (gattr (g, "y1"), 0, bbox_units ? 1 : 100);
                double x2 = length (gattr (g, "x2"), bbox_units ? 1 : 100, bbox_units ? 1 : 100), y2 = length (gattr (g, "y2"), 0, bbox_units ? 1 : 100);
                if (bbox_units && gattr (g, "x2") == null) x2 = 1;
                m.transform_point (ref x1, ref y1);
                m.transform_point (ref x2, ref y2);
                gr.x1 = x1;
                gr.y1 = y1;
                gr.x2 = x2;
                gr.y2 = y2;
            } else {
                double cx = length (gattr (g, "cx"), 0.5, bbox_units ? 1 : 100), cy = length (gattr (g, "cy"), 0.5, bbox_units ? 1 : 100);
                double r = length (gattr (g, "r"), 0.5, bbox_units ? 1 : 100);
                double fx = gattr (g, "fx") != null ? length (gattr (g, "fx"), cx, bbox_units ? 1 : 100) : cx;
                double fy = gattr (g, "fy") != null ? length (gattr (g, "fy"), cy, bbox_units ? 1 : 100) : cy;
                double ax = cx + r, ay = cy, bx = cx, by = cy + r;
                m.transform_point (ref cx, ref cy);
                m.transform_point (ref ax, ref ay);
                m.transform_point (ref bx, ref by);
                m.transform_point (ref fx, ref fy);
                double ra = Math.hypot (ax - cx, ay - cy), rb = Math.hypot (bx - cx, by - cy);
                gr.x1 = cx;
                gr.y1 = cy;
                if (ra >= rb) {
                    gr.x2 = ax;
                    gr.y2 = ay;
                    gr.aspect = ra > 0 ? rb / ra : 1;
                } else {
                    gr.x2 = bx;
                    gr.y2 = by;
                    gr.aspect = rb > 0 ? ra / rb : 1;
                }
                gr.fx = fx;
                gr.fy = fy;
            }
            return paint;
        }

        private Paint? pattern_paint (string id, Cairo.Matrix ctm) {
            if (!ids.has_key (id)) return null;
            Xml.Node* p = ids[id];
            if (p->name != "pattern") return null;
            string pid = "svgpat-" + id;
            if (doc.find_pattern (pid) == null) {
                var def = new PatternDef ();
                def.id = pid;
                def.name = id;
                def.w = length (gattr (p, "width"), 10);
                def.h = length (gattr (p, "height"), 10);
                Xml.Node* content = p;
                int guard = 0;
                while (content != null && content->children == null && guard++ < 8) content = resolve_href (content);
                if (content != null) {
                    var tile = new GroupNode ();
                    var vb = gattr (p, "viewBox");
                    var base_m = Cairo.Matrix.identity ();
                    if (vb != null) {
                        double[] v = numbers (vb);
                        if (v.length == 4 && v[2] > 0 && v[3] > 0) {
                            base_m.scale (def.w / v[2], def.h / v[3]);
                            base_m.translate (-v[0], -v[1]);
                        }
                    }
                    children (content, tile, new SvgStyle (), base_m);
                    tile.add (invisible_rect (def.w, def.h), 0);
                    def.tile = tile;
                }
                doc.patterns.add (def);
            }
            var paint = new Paint ();
            paint.kind = PaintKind.PATTERN;
            paint.pattern = pid;
            var pt = transform (gattr (p, "patternTransform"));
            var origin = Transforms.translate (length (gattr (p, "x"), 0), length (gattr (p, "y"), 0));
            paint.pattern_matrix = Transforms.multiply (Transforms.multiply (origin, pt), ctm);
            return paint;
        }

        private PathNode invisible_rect (double w, double h) {
            var r = new PathNode.with_path (new PathData.rect (0, 0, w, h));
            r.guide = false;
            return r;
        }

        private static double[] numbers (string s) {
            double[] v = {};
            var sc = new PathScanner (s);
            double x;
            while (sc.number (out x)) v += x;
            return v;
        }

        private Paint? paint_for (string spec, Rect bbox, Cairo.Matrix ctm) {
            string? id = url_id (spec);
            if (id != null) {
                var p = gradient_paint (id, bbox, ctm) ?? pattern_paint (id, ctm);
                if (p != null) return p;
                int sp = spec.index_of (")");
                if (sp >= 0 && sp + 1 < spec.length) {
                    var fallback = color (spec.substring (sp + 1));
                    if (fallback != null) return new Paint.solid (fallback);
                }
                return null;
            }
            var ink = color (spec);
            return ink != null ? new Paint.solid (ink) : null;
        }

        private void appearance (Node node, SvgStyle s, Rect bbox, Cairo.Matrix ctm) {
            node.appearance.clear ();
            var fill = paint_for (s.fill, bbox, ctm);
            if (fill != null) {
                var l = new PaintLayer.fill (fill);
                l.opacity = s.fill_opacity;
                node.appearance.add (l);
            }
            var stroke = paint_for (s.stroke, bbox, ctm);
            if (stroke != null && s.stroke_width > 0) {
                double scale = Transforms.scale_factor (ctm);
                var l = new PaintLayer.line (stroke, s.stroke_width * scale);
                l.opacity = s.stroke_opacity;
                l.cap = s.linecap == "round" ? CapKind.ROUND : (s.linecap == "square" ? CapKind.SQUARE : CapKind.BUTT);
                l.join = s.linejoin == "round" ? JoinKind.ROUND : (s.linejoin == "bevel" ? JoinKind.BEVEL : JoinKind.MITER);
                l.miter = s.miter;
                if (s.dasharray != "none") {
                    double[] d = {};
                    foreach (double v in numbers (s.dasharray)) d += v * scale;
                    if (d.length % 2 == 1) {
                        double[] dd = d;
                        foreach (double v in dd) d += v;
                    }
                    l.dashes = d;
                    l.dash_offset = s.dashoffset * scale;
                }
                node.appearance.add (l);
            }
        }

        private VectorDocument import (Xml.Node* root) {
            index (root);
            double w = length (root->get_prop ("width"), 0);
            double h = length (root->get_prop ("height"), 0);
            var vb = root->get_prop ("viewBox");
            var base_m = Cairo.Matrix.identity ();
            Rect board;
            if (vb != null) {
                double[] v = numbers (vb);
                if (v.length == 4 && v[2] > 0 && v[3] > 0) {
                    if (w <= 0) w = v[2];
                    if (h <= 0) h = v[3];
                    double sx = w / v[2], sy = h / v[3];
                    string par = root->get_prop ("preserveAspectRatio") ?? "xMidYMid meet";
                    if (!par.contains ("none")) sx = sy = double.min (sx, sy);
                    base_m.scale (sx, sy);
                    base_m.translate (-v[0], -v[1]);
                }
            }
            if (w <= 0) w = 800;
            if (h <= 0) h = 600;
            board = Rect (0, 0, w, h);
            doc.title = root->get_prop ("title") ?? "";
            var a = new Artboard (_("Artboard 1"), board.x, board.y, board.w, board.h);
            doc.add_artboard (a);
            var root_style = apply_style (new SvgStyle (), props_of (root));
            bool has_layers = false;
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "g") continue;
                string? mode = c->get_ns_prop ("groupmode", "http://www.inkscape.org/namespaces/inkscape");
                if (mode == "layer" || c->get_prop ("data-layer") != null) has_layers = true;
            }
            GroupNode? loose = null;
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "title") {
                    doc.title = c->get_content ().strip ();
                    continue;
                }
                string? mode = c->get_ns_prop ("groupmode", "http://www.inkscape.org/namespaces/inkscape");
                bool is_layer = has_layers && c->name == "g" && (mode == "layer" || c->get_prop ("data-layer") != null);
                if (is_layer) {
                    var layer = doc.new_layer (c->get_ns_prop ("label", "http://www.inkscape.org/namespaces/inkscape") ?? c->get_prop ("data-layer") ?? c->get_prop ("id") ?? _("Layer %d").printf (doc.layers.size + 1));
                    var lp = props_of (c);
                    var ls = apply_style (root_style, lp);
                    if (lp.has_key ("opacity")) layer.opacity = number (lp["opacity"], 1);
                    layer.hidden = !ls.display;
                    children (c, layer, ls, Transforms.multiply (transform (c->get_prop ("transform")), base_m));
                    doc.layers.add (layer);
                    loose = null;
                    continue;
                }
                if (loose == null) {
                    loose = doc.new_layer (_("Layer %d").printf (doc.layers.size + 1));
                    doc.layers.add (loose);
                }
                element (c, loose, root_style, base_m);
            }
            if (doc.layers.size == 0) doc.layers.add (doc.new_layer (_("Layer 1")));
            doc.active_layer = doc.layers[doc.layers.size - 1];
            doc.default_brushes ();
            if (doc.swatches.size == 0) doc.default_swatches ();
            doc.relink ();
            doc.ensure_ids ();
            doc.modified = false;
            return doc;
        }

        private void children (Xml.Node* parent, GroupNode target, SvgStyle style, Cairo.Matrix ctm) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) element (c, target, style, ctm);
            }
        }

        private void element (Xml.Node* n, GroupNode target, SvgStyle parent_style, Cairo.Matrix parent_ctm) {
            if (++depth_guard > 20000) return;
            string name = n->name;
            switch (name) {
                case "defs":
                case "style":
                case "title":
                case "desc":
                case "metadata":
                case "linearGradient":
                case "radialGradient":
                case "pattern":
                case "clipPath":
                case "mask":
                case "filter":
                case "symbol":
                case "marker":
                case "script":
                    return;
            }
            var p = props_of (n);
            var style = apply_style (parent_style, p);
            if (!style.display) return;
            var ctm = Transforms.multiply (transform (n->get_prop ("transform")), parent_ctm);
            Node? node = null;
            switch (name) {
                case "g":
                case "a":
                case "switch":
                    var g = new GroupNode ();
                    children (n, g, style, ctm);
                    node = g;
                    break;
                case "svg":
                    var g = new GroupNode ();
                    var m = Transforms.translate (length (n->get_prop ("x"), 0), length (n->get_prop ("y"), 0));
                    var vb = n->get_prop ("viewBox");
                    if (vb != null) {
                        double[] v = numbers (vb);
                        double w = length (n->get_prop ("width"), v.length == 4 ? v[2] : 100), h = length (n->get_prop ("height"), v.length == 4 ? v[3] : 100);
                        if (v.length == 4 && v[2] > 0 && v[3] > 0) {
                            var s = Cairo.Matrix.identity ();
                            s.scale (w / v[2], h / v[3]);
                            s.translate (-v[0], -v[1]);
                            m = Transforms.multiply (s, m);
                        }
                    }
                    children (n, g, style, Transforms.multiply (m, ctm));
                    node = g;
                    break;
                case "path":
                    string? d = n->get_prop ("d");
                    if (d != null) node = shape (PathData.parse_svg (d), style, ctm);
                    break;
                case "rect":
                    double x = length (n->get_prop ("x"), 0), y = length (n->get_prop ("y"), 0);
                    double w = length (n->get_prop ("width"), 0), h = length (n->get_prop ("height"), 0);
                    if (w <= 0 || h <= 0) break;
                    double rx = length (n->get_prop ("rx") ?? n->get_prop ("ry"), 0);
                    var pn = shape (rx > 0 ? new PathData.round_rect (x, y, w, h, double.min (rx, double.min (w, h) / 2)) : new PathData.rect (x, y, w, h), style, ctm);
                    if (ctm.xy == 0 && ctm.yx == 0 && ctm.xx > 0 && ctm.yy > 0) {
                        pn.live = new LiveShape ();
                        pn.live.kind = "rectangle";
                        double cx = x + w / 2, cy = y + h / 2;
                        ctm.transform_point (ref cx, ref cy);
                        pn.live.cx = cx;
                        pn.live.cy = cy;
                        pn.live.w = w * ctm.xx;
                        pn.live.h = h * ctm.yy;
                        pn.live.radius = double.min (rx, double.min (w, h) / 2) * Math.sqrt (ctm.xx * ctm.yy);
                        pn.rebuild_live ();
                    }
                    node = pn;
                    break;
                case "circle":
                case "ellipse":
                    double cx = length (n->get_prop ("cx"), 0), cy = length (n->get_prop ("cy"), 0);
                    double rx = name == "circle" ? length (n->get_prop ("r"), 0) : length (n->get_prop ("rx"), 0);
                    double ry = name == "circle" ? rx : length (n->get_prop ("ry"), 0);
                    if (rx <= 0 || ry <= 0) break;
                    var pn = shape (new PathData.ellipse (cx, cy, rx, ry), style, ctm);
                    if (ctm.xy == 0 && ctm.yx == 0 && ctm.xx > 0 && ctm.yy > 0) {
                        pn.live = new LiveShape ();
                        pn.live.kind = "ellipse";
                        double tx = cx, ty = cy;
                        ctm.transform_point (ref tx, ref ty);
                        pn.live.cx = tx;
                        pn.live.cy = ty;
                        pn.live.w = rx * 2 * ctm.xx;
                        pn.live.h = ry * 2 * ctm.yy;
                        pn.rebuild_live ();
                    }
                    node = pn;
                    break;
                case "line":
                    var path = new PathData ();
                    path.move_to (length (n->get_prop ("x1"), 0), length (n->get_prop ("y1"), 0));
                    path.line_to (length (n->get_prop ("x2"), 0), length (n->get_prop ("y2"), 0));
                    node = shape (path, style, ctm);
                    break;
                case "polyline":
                case "polygon":
                    double[] v = numbers (n->get_prop ("points") ?? "");
                    if (v.length < 4) break;
                    var path = new PathData ();
                    path.move_to (v[0], v[1]);
                    for (int i = 2; i + 1 < v.length; i += 2) path.line_to (v[i], v[i + 1]);
                    if (name == "polygon") path.close ();
                    node = shape (path, style, ctm);
                    break;
                case "text":
                    node = text (n, style, ctm);
                    break;
                case "image":
                    node = image (n, ctm);
                    break;
                case "use":
                    node = use_element (n, style, ctm);
                    break;
            }
            if (node == null) return;
            if (p.has_key ("opacity")) node.opacity = number (p["opacity"], 1).clamp (0, 1);
            if (p.has_key ("mix-blend-mode")) node.blend = BlendMode.from_id (p["mix-blend-mode"]);
            if (p.has_key ("isolation") && p["isolation"] == "isolate") node.isolate = true;
            if (!style.visible) node.hidden = true;
            string? id = n->get_prop ("id");
            if (id != null && !id.has_prefix ("path") && !id.has_prefix ("g") && !id.has_prefix ("rect")) node.name = id;
            string? filter = url_id (p.has_key ("filter") ? p["filter"] : n->get_prop ("filter"));
            if (filter != null) effects_from_filter (filter, node, ctm);
            string? mask = url_id (p.has_key ("mask") ? p["mask"] : n->get_prop ("mask"));
            if (mask != null && ids.has_key (mask)) {
                var mg = new GroupNode ();
                children (ids[mask], mg, new SvgStyle (), parent_ctm);
                node.mask = mg;
            }
            string? clip = url_id (n->get_prop ("clip-path") ?? (p.has_key ("clip-path") ? p["clip-path"] : null));
            if (clip != null && ids.has_key (clip)) {
                Xml.Node* cp = ids[clip];
                var cg = new GroupNode ();
                var clip_ctm = Transforms.multiply (transform (cp->get_prop ("transform")), parent_ctm);
                if (cp->get_prop ("clipPathUnits") == "objectBoundingBox") {
                    var b = node.geometric_bounds ();
                    clip_ctm = Transforms.multiply (Cairo.Matrix (b.w, 0, 0, b.h, b.x, b.y), Transforms.multiply (transform (cp->get_prop ("transform")), Cairo.Matrix.identity ()));
                }
                children (cp, cg, new SvgStyle (), clip_ctm);
                var outline = new PathData ();
                foreach (var c in cg.children) {
                    var o = c.outline ();
                    if (o != null) outline.append (o);
                }
                var clip_node = new PathNode.with_path (outline);
                var wrapper = new GroupNode ();
                wrapper.clip = true;
                wrapper.add (clip_node);
                wrapper.add (node);
                node = wrapper;
            }
            target.add (node);
        }

        private void effects_from_filter (string id, Node node, Cairo.Matrix ctm) {
            if (!ids.has_key (id)) return;
            Xml.Node* f = ids[id];
            double blur = 0, dx = 0, dy = 0;
            bool offset = false, flood = false;
            string flood_color = "#000000";
            double flood_opacity = 0.5;
            for (Xml.Node* c = f->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "feGaussianBlur") blur = number (c->get_prop ("stdDeviation"), 0);
                if (c->name == "feOffset") {
                    offset = true;
                    dx = number (c->get_prop ("dx"), 0);
                    dy = number (c->get_prop ("dy"), 0);
                }
                if (c->name == "feDropShadow") {
                    offset = true;
                    flood = true;
                    blur = number (c->get_prop ("stdDeviation"), 2);
                    dx = number (c->get_prop ("dx"), 2);
                    dy = number (c->get_prop ("dy"), 2);
                    flood_color = c->get_prop ("flood-color") ?? "#000000";
                    flood_opacity = number (c->get_prop ("flood-opacity"), 1);
                }
                if (c->name == "feFlood") {
                    flood = true;
                    flood_color = c->get_prop ("flood-color") ?? "#000000";
                    flood_opacity = number (c->get_prop ("flood-opacity"), 1);
                }
            }
            double s = Transforms.scale_factor (ctm);
            if (offset) {
                var ink = color (flood_color) ?? new Ink ();
                node.effects.add (new Effect ("drop-shadow").set_num ("dx", dx * s).set_num ("dy", dy * s).set_num ("blur", blur * 2 * s).set_num ("opacity", flood ? flood_opacity : 0.5).set_str ("color", ink.to_hex ()));
            } else if (blur > 0) {
                node.effects.add (new Effect ("blur").set_num ("blur", blur * 2 * s));
            }
        }

        private PathNode shape (PathData path, SvgStyle style, Cairo.Matrix ctm) {
            var local_box = path.bounds ();
            var pn = new PathNode ();
            path.transform (ctm);
            pn.path = path;
            pn.even_odd = style.fill_rule == "evenodd";
            appearance (pn, style, local_box, ctm);
            if (pn.appearance.size > 0) {
                foreach (var l in pn.appearance) {
                    if (l.paint.kind == PaintKind.LINEAR || l.paint.kind == PaintKind.RADIAL) {
                        if (style.fill.has_prefix ("url(") || style.stroke.has_prefix ("url(")) {
                            var id = url_id (l.stroke ? style.stroke : style.fill);
                            if (id != null && ids.has_key (id) && gattr (ids[id], "gradientUnits") != "userSpaceOnUse") {
                                var np = gradient_paint (id, local_box, ctm);
                                if (np != null) {
                                    var m = ctm;
                                    m.transform_point (ref np.gradient.x1, ref np.gradient.y1);
                                    m.transform_point (ref np.gradient.x2, ref np.gradient.y2);
                                    m.transform_point (ref np.gradient.fx, ref np.gradient.fy);
                                    l.paint = np;
                                }
                            }
                        }
                    }
                }
            }
            return pn;
        }

        private TextNode? text (Xml.Node* n, SvgStyle style, Cairo.Matrix ctm) {
            var t = new TextNode ();
            double x = length (first_number (n->get_prop ("x")), 0), y = length (first_number (n->get_prop ("y")), 0);
            var b = new StringBuilder ();
            bool first_line = true;
            double line_y = y;
            Xml.Node* path_ref = null;
            collect_text (n, b, ref first_line, ref line_y, t, style, ref path_ref);
            t.text = b.str.strip ();
            if (t.text == "") return null;
            t.style.family = style.font_family;
            t.style.size = style.font_size * Math.sqrt ((ctm.xx * ctm.yy - ctm.xy * ctm.yx).abs ()) / Math.sqrt ((ctm.xx * ctm.yy - ctm.xy * ctm.yx).abs ().clamp (1e-9, 1e9));
            t.style.weight = style.font_weight == "bold" ? 700 : (style.font_weight == "normal" ? 400 : int.parse (style.font_weight).clamp (100, 900));
            if (t.style.weight == 0) t.style.weight = 400;
            t.style.italic = style.font_style == "italic" || style.font_style == "oblique";
            t.style.tracking = style.font_size > 0 ? style.letter_spacing / style.font_size * 1000 : 0;
            t.style.underline = style.text_decoration.contains ("underline");
            t.style.strike = style.text_decoration.contains ("line-through");
            t.para.align = style.text_anchor == "middle" ? "center" : (style.text_anchor == "end" ? "right" : "left");
            if (path_ref != null) {
                string? d = path_ref->get_prop ("d");
                if (d != null) {
                    t.mode = "path";
                    var path = PathData.parse_svg (d);
                    path.transform (Transforms.multiply (transform (path_ref->get_prop ("transform")), ctm));
                    t.on_path = path;
                    t.style.size *= Transforms.scale_factor (ctm);
                }
            } else {
                t.matrix = Transforms.multiply (Transforms.translate (x, y), ctm);
            }
            appearance (t, style, Rect (x, y - style.font_size, style.font_size * t.text.length * 0.5, style.font_size), Cairo.Matrix.identity ());
            return t;
        }

        private string? first_number (string? s) {
            if (s == null) return null;
            var parts = s.strip ().replace (",", " ").split (" ");
            return parts.length > 0 ? parts[0] : s;
        }

        private void collect_text (Xml.Node* n, StringBuilder b, ref bool first_line, ref double line_y, TextNode t, SvgStyle style, ref Xml.Node* path_ref) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    b.append (c->content.replace ("\n", " ").replace ("\t", " "));
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "textPath") {
                    path_ref = resolve_href (c);
                    collect_text (c, b, ref first_line, ref line_y, t, style, ref path_ref);
                    continue;
                }
                if (c->name != "tspan") continue;
                string? ty = c->get_prop ("y");
                string? dy = c->get_prop ("dy");
                bool new_line = (ty != null && (length (first_number (ty), line_y) - line_y).abs () > 0.01) || (dy != null && length (first_number (dy), 0) > 0.01 && c->get_prop ("x") != null);
                if (new_line && b.len > 0) {
                    b.append ("\n");
                    if (ty != null) {
                        double ny = length (first_number (ty), line_y);
                        if (t.style.leading == 0 && ny > line_y) t.style.leading = ny - line_y;
                        line_y = ny;
                    }
                }
                var sp = props_of (c);
                int start = (int) b.len;
                collect_text (c, b, ref first_line, ref line_y, t, style, ref path_ref);
                int end = (int) b.len;
                if (end > start && sp.size > 0) {
                    var s = apply_style (style, sp);
                    var cs = t.style.copy ();
                    cs.family = s.font_family;
                    cs.size = s.font_size;
                    cs.weight = s.font_weight == "bold" ? 700 : 400;
                    cs.italic = s.font_style == "italic";
                    if (sp.has_key ("fill")) cs.color = color (s.fill);
                    t.runs.add (new TextRun (start, end, cs));
                }
            }
        }

        private ImageNode? image (Xml.Node* n, Cairo.Matrix ctm) {
            string? href = n->get_prop ("href") ?? n->get_ns_prop ("href", "http://www.w3.org/1999/xlink");
            if (href == null) return null;
            uint8[]? data = null;
            string mime = "image/png";
            string link = "";
            if (href.has_prefix ("data:")) {
                int comma = href.index_of (",");
                if (comma < 0) return null;
                string head = href.substring (5, comma - 5);
                mime = head.split (";")[0];
                string payload = href.substring (comma + 1);
                if (head.contains ("base64")) data = Base64.decode (payload.replace ("\n", "").replace (" ", ""));
                else data = Uri.unescape_string (payload).data;
            } else {
                string path = href;
                if (href.has_prefix ("file://")) {
                    try {
                        path = Filename.from_uri (href);
                    } catch (Error e) {
                        return null;
                    }
                } else if (!Path.is_absolute (href) && base_dir != null) {
                    path = Path.build_filename (base_dir, href);
                }
                if (href.has_prefix ("http")) return null;
                link = path;
                try {
                    FileUtils.get_data (path, out data);
                } catch (Error e) {
                    data = null;
                }
                string lower = path.down ();
                if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg")) mime = "image/jpeg";
                else if (lower.has_suffix (".webp")) mime = "image/webp";
                else if (lower.has_suffix (".gif")) mime = "image/gif";
                else if (lower.has_suffix (".svg")) mime = "image/svg+xml";
            }
            if (data == null) return null;
            var im = new ImageNode ();
            im.mime = mime;
            try {
                var pix = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_data (data));
                im.pixel_width = pix.width;
                im.pixel_height = pix.height;
            } catch (Error e) {
                return null;
            }
            if (link != "") im.link = link;
            im.asset = doc.store_asset (new Bytes (data), mime);
            double x = length (n->get_prop ("x"), 0), y = length (n->get_prop ("y"), 0);
            double w = length (n->get_prop ("width"), im.pixel_width), h = length (n->get_prop ("height"), im.pixel_height);
            var m = Cairo.Matrix (w / im.pixel_width, 0, 0, h / im.pixel_height, x, y);
            im.matrix = Transforms.multiply (m, ctm);
            return im;
        }

        private Node? use_element (Xml.Node* n, SvgStyle style, Cairo.Matrix ctm) {
            Xml.Node* r = resolve_href (n);
            if (r == null) return null;
            var m = Transforms.multiply (Transforms.translate (length (n->get_prop ("x"), 0), length (n->get_prop ("y"), 0)), ctm);
            if (r->name == "symbol") {
                string id = r->get_prop ("id") ?? "symbol";
                string sid = "svgsym-" + id;
                if (!symbols_done.contains (sid)) {
                    symbols_done.add (sid);
                    var def = new SymbolDef ();
                    def.id = sid;
                    def.name = id;
                    var sm = Cairo.Matrix.identity ();
                    var vb = r->get_prop ("viewBox");
                    if (vb != null) {
                        double[] v = numbers (vb);
                        double w = length (n->get_prop ("width"), v.length == 4 ? v[2] : 100), h = length (n->get_prop ("height"), v.length == 4 ? v[3] : 100);
                        if (v.length == 4 && v[2] > 0 && v[3] > 0) {
                            sm.scale (w / v[2], h / v[3]);
                            sm.translate (-v[0], -v[1]);
                        }
                    }
                    children (r, def.art, style, sm);
                    doc.symbols.add (def);
                }
                var inst = new SymbolNode ();
                inst.symbol = sid;
                inst.doc = doc;
                inst.matrix = m;
                return inst;
            }
            var g = new GroupNode ();
            element (r, g, style, m);
            if (g.children.size == 1) {
                var only = g.children[0];
                g.remove (only);
                return only;
            }
            return g;
        }
    }
}
