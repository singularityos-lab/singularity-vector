using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class NativeFormat {
        public const int VERSION = 1;

        private static Json.Object obj () {
            return new Json.Object ();
        }

        private static double num (Json.Object o, string key, double fallback) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            var t = n.get_value_type ();
            if (t == typeof (double)) return n.get_double ();
            if (t == typeof (int64)) return (double) n.get_int ();
            if (t == typeof (bool)) return n.get_boolean () ? 1 : 0;
            return fallback;
        }

        private static string str (Json.Object o, string key, string fallback) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () != Json.NodeType.VALUE || n.get_value_type () != typeof (string)) return fallback;
            return n.get_string ();
        }

        private static bool flag (Json.Object o, string key, bool fallback) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (bool)) return n.get_boolean ();
            return num (o, key, fallback ? 1 : 0) != 0;
        }

        private static Json.Array arr (Json.Object o, string key) {
            if (o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.ARRAY) return o.get_array_member (key);
            return new Json.Array ();
        }

        private static Json.Object? child (Json.Object o, string key) {
            if (o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.OBJECT) return o.get_object_member (key);
            return null;
        }

        private static Json.Array matrix_out (Cairo.Matrix m) {
            var a = new Json.Array ();
            foreach (double v in new double[] { m.xx, m.yx, m.xy, m.yy, m.x0, m.y0 }) a.add_double_element (v);
            return a;
        }

        private static Cairo.Matrix matrix_in (Json.Object o, string key) {
            var a = arr (o, key);
            if (a.get_length () != 6) return Cairo.Matrix.identity ();
            return Cairo.Matrix (a.get_double_element (0), a.get_double_element (1), a.get_double_element (2), a.get_double_element (3), a.get_double_element (4), a.get_double_element (5));
        }

        private static string path_out (PathData p) {
            return p.to_svg (5);
        }

        private static Json.Array numbers_out (double[] v) {
            var a = new Json.Array ();
            foreach (double d in v) a.add_double_element (d);
            return a;
        }

        private static double[] numbers_in (Json.Object o, string key) {
            var a = arr (o, key);
            double[] r = new double[a.get_length ()];
            for (uint i = 0; i < a.get_length (); i++) {
                var n = a.get_element (i);
                r[i] = n.get_value_type () == typeof (int64) ? (double) n.get_int () : n.get_double ();
            }
            return r;
        }

        public static Json.Object ink_out (Ink i) {
            var o = obj ();
            o.set_string_member ("hex", i.to_hex ());
            o.set_double_member ("r", i.r);
            o.set_double_member ("g", i.g);
            o.set_double_member ("b", i.b);
            if (i.has_cmyk) o.set_array_member ("cmyk", numbers_out ({ i.c, i.m, i.y, i.k }));
            if (i.spot != "") o.set_string_member ("spot", i.spot);
            if (i.tint != 1) o.set_double_member ("tint", i.tint);
            if (i.swatch != "") o.set_string_member ("swatch", i.swatch);
            return o;
        }

        public static Ink ink_in (Json.Object? o) {
            var i = new Ink ();
            if (o == null) return i;
            if (o.has_member ("r")) {
                i.r = num (o, "r", 0);
                i.g = num (o, "g", 0);
                i.b = num (o, "b", 0);
            } else {
                i.set_hex (str (o, "hex", "#000000"));
            }
            var c = numbers_in (o, "cmyk");
            if (c.length == 4) {
                i.has_cmyk = true;
                i.c = c[0];
                i.m = c[1];
                i.y = c[2];
                i.k = c[3];
            }
            i.spot = str (o, "spot", "");
            i.tint = num (o, "tint", 1);
            i.swatch = str (o, "swatch", "");
            return i;
        }

        public static Json.Object paint_out (Paint p) {
            var o = obj ();
            o.set_string_member ("kind", p.kind.to_id ());
            if (p.kind == PaintKind.SOLID) o.set_object_member ("color", ink_out (p.color));
            if (p.kind == PaintKind.LINEAR || p.kind == PaintKind.RADIAL) {
                var g = obj ();
                var stops = new Json.Array ();
                foreach (var s in p.gradient.stops) {
                    var so = obj ();
                    so.set_double_member ("offset", s.offset);
                    so.set_object_member ("color", ink_out (s.color));
                    so.set_double_member ("opacity", s.opacity);
                    so.set_double_member ("midpoint", s.midpoint);
                    stops.add_object_element (so);
                }
                g.set_array_member ("stops", stops);
                g.set_array_member ("geometry", numbers_out ({ p.gradient.x1, p.gradient.y1, p.gradient.x2, p.gradient.y2, p.gradient.fx, p.gradient.fy, p.gradient.aspect, p.gradient.radius }));
                g.set_string_member ("spread", p.gradient.spread);
                o.set_object_member ("gradient", g);
            }
            if (p.kind == PaintKind.FREEFORM) {
                var pts = new Json.Array ();
                foreach (var f in p.freeform) {
                    var fo = obj ();
                    fo.set_double_member ("x", f.x);
                    fo.set_double_member ("y", f.y);
                    fo.set_double_member ("spread", f.spread);
                    fo.set_object_member ("color", ink_out (f.color));
                    pts.add_object_element (fo);
                }
                o.set_array_member ("points", pts);
            }
            if (p.kind == PaintKind.PATTERN) {
                o.set_string_member ("pattern", p.pattern);
                o.set_array_member ("matrix", matrix_out (p.pattern_matrix));
            }
            if (p.overprint) o.set_boolean_member ("overprint", true);
            return o;
        }

        public static Paint paint_in (Json.Object? o) {
            var p = new Paint ();
            if (o == null) return p;
            p.kind = PaintKind.from_id (str (o, "kind", "none"));
            p.color = ink_in (child (o, "color"));
            var g = child (o, "gradient");
            if (g != null) {
                foreach (var n in arr (g, "stops").get_elements ()) {
                    var so = n.get_object ();
                    var s = new GradientStop (num (so, "offset", 0), ink_in (child (so, "color")), num (so, "opacity", 1));
                    s.midpoint = num (so, "midpoint", 0.5);
                    p.gradient.stops.add (s);
                }
                var geo = numbers_in (g, "geometry");
                if (geo.length >= 8) {
                    p.gradient.x1 = geo[0];
                    p.gradient.y1 = geo[1];
                    p.gradient.x2 = geo[2];
                    p.gradient.y2 = geo[3];
                    p.gradient.fx = geo[4];
                    p.gradient.fy = geo[5];
                    p.gradient.aspect = geo[6];
                    p.gradient.radius = geo[7];
                }
                p.gradient.spread = str (g, "spread", "pad");
            }
            foreach (var n in arr (o, "points").get_elements ()) {
                var fo = n.get_object ();
                var f = new FreeformPoint (num (fo, "x", 0), num (fo, "y", 0), ink_in (child (fo, "color")));
                f.spread = num (fo, "spread", 0.6);
                p.freeform.add (f);
            }
            p.pattern = str (o, "pattern", "");
            if (o.has_member ("matrix")) p.pattern_matrix = matrix_in (o, "matrix");
            p.overprint = flag (o, "overprint", false);
            return p;
        }

        public static Json.Object effect_out (Effect e) {
            var o = obj ();
            o.set_string_member ("kind", e.kind);
            o.set_boolean_member ("enabled", e.enabled);
            var nums = obj ();
            foreach (var kv in e.num.entries) nums.set_double_member (kv.key, kv.value);
            o.set_object_member ("num", nums);
            var strs = obj ();
            foreach (var kv in e.str.entries) strs.set_string_member (kv.key, kv.value);
            o.set_object_member ("str", strs);
            return o;
        }

        public static Effect effect_in (Json.Object o) {
            var e = new Effect (str (o, "kind", ""));
            e.enabled = flag (o, "enabled", true);
            var nums = child (o, "num");
            if (nums != null) foreach (var key in nums.get_members ()) e.num[key] = num (nums, key, 0);
            var strs = child (o, "str");
            if (strs != null) foreach (var key in strs.get_members ()) e.str[key] = str (strs, key, "");
            return e;
        }

        private static Json.Array effects_out (Gee.List<Effect> list) {
            var a = new Json.Array ();
            foreach (var e in list) a.add_object_element (effect_out (e));
            return a;
        }

        private static void effects_in (Json.Object o, string key, Gee.List<Effect> list) {
            list.clear ();
            foreach (var n in arr (o, key).get_elements ()) if (n.get_node_type () == Json.NodeType.OBJECT) list.add (effect_in (n.get_object ()));
        }

        public static Json.Object layer_out (PaintLayer l) {
            var o = obj ();
            o.set_boolean_member ("stroke", l.stroke);
            o.set_object_member ("paint", paint_out (l.paint));
            o.set_double_member ("opacity", l.opacity);
            o.set_string_member ("blend", l.blend.to_id ());
            o.set_boolean_member ("visible", l.visible);
            if (l.stroke) {
                o.set_double_member ("width", l.width);
                o.set_int_member ("cap", (int) l.cap);
                o.set_int_member ("join", (int) l.join);
                o.set_double_member ("miter", l.miter);
                o.set_array_member ("dashes", numbers_out (l.dashes));
                o.set_double_member ("dash_offset", l.dash_offset);
                o.set_int_member ("align", (int) l.align);
                var prof = new Json.Array ();
                foreach (var w in l.profile) prof.add_array_element (numbers_out ({ w.t, w.left, w.right }));
                o.set_array_member ("profile", prof);
                o.set_string_member ("brush", l.brush);
                o.set_double_member ("brush_scale", l.brush_scale);
                o.set_string_member ("arrow_start", l.arrow_start);
                o.set_string_member ("arrow_end", l.arrow_end);
            }
            o.set_array_member ("effects", effects_out (l.effects));
            return o;
        }

        public static PaintLayer layer_in (Json.Object o) {
            var l = new PaintLayer ();
            l.stroke = flag (o, "stroke", false);
            l.paint = paint_in (child (o, "paint"));
            l.opacity = num (o, "opacity", 1);
            l.blend = BlendMode.from_id (str (o, "blend", "normal"));
            l.visible = flag (o, "visible", true);
            l.width = num (o, "width", 1);
            l.cap = (CapKind) (int) num (o, "cap", 0);
            l.join = (JoinKind) (int) num (o, "join", 0);
            l.miter = num (o, "miter", 10);
            l.dashes = numbers_in (o, "dashes");
            l.dash_offset = num (o, "dash_offset", 0);
            l.align = (StrokeAlign) (int) num (o, "align", 0);
            foreach (var n in arr (o, "profile").get_elements ()) {
                var a = n.get_array ();
                if (a.get_length () == 3) l.profile.add (new WidthPoint (a.get_double_element (0), a.get_double_element (1), a.get_double_element (2)));
            }
            l.brush = str (o, "brush", "");
            l.brush_scale = num (o, "brush_scale", 1);
            l.arrow_start = str (o, "arrow_start", "");
            l.arrow_end = str (o, "arrow_end", "");
            effects_in (o, "effects", l.effects);
            return l;
        }

        private static Json.Object char_out (CharStyle s) {
            var o = obj ();
            o.set_string_member ("family", s.family);
            o.set_double_member ("size", s.size);
            o.set_int_member ("weight", s.weight);
            o.set_boolean_member ("italic", s.italic);
            o.set_double_member ("tracking", s.tracking);
            o.set_double_member ("leading", s.leading);
            o.set_double_member ("baseline", s.baseline);
            o.set_double_member ("hscale", s.hscale);
            o.set_double_member ("vscale", s.vscale);
            o.set_boolean_member ("underline", s.underline);
            o.set_boolean_member ("strike", s.strike);
            o.set_string_member ("caps", s.caps);
            o.set_string_member ("features", s.features);
            o.set_string_member ("language", s.language);
            if (s.color != null) o.set_object_member ("color", ink_out (s.color));
            return o;
        }

        private static CharStyle char_in (Json.Object? o) {
            var s = new CharStyle ();
            if (o == null) return s;
            s.family = str (o, "family", "Sans");
            s.size = num (o, "size", 24);
            s.weight = (int) num (o, "weight", 400);
            s.italic = flag (o, "italic", false);
            s.tracking = num (o, "tracking", 0);
            s.leading = num (o, "leading", 0);
            s.baseline = num (o, "baseline", 0);
            s.hscale = num (o, "hscale", 1);
            s.vscale = num (o, "vscale", 1);
            s.underline = flag (o, "underline", false);
            s.strike = flag (o, "strike", false);
            s.caps = str (o, "caps", "none");
            s.features = str (o, "features", "");
            s.language = str (o, "language", "");
            var c = child (o, "color");
            if (c != null) s.color = ink_in (c);
            return s;
        }

        public static Json.Object node_out (Node n) {
            var o = obj ();
            o.set_string_member ("t", n.kind_name ());
            o.set_string_member ("id", n.id);
            if (n.name != "") o.set_string_member ("name", n.name);
            if (n.hidden) o.set_boolean_member ("hidden", true);
            if (n.locked) o.set_boolean_member ("locked", true);
            if (n.opacity != 1) o.set_double_member ("opacity", n.opacity);
            if (n.blend != BlendMode.NORMAL) o.set_string_member ("blend", n.blend.to_id ());
            if (n.isolate) o.set_boolean_member ("isolate", true);
            if (n.knockout) o.set_boolean_member ("knockout", true);
            var app = new Json.Array ();
            foreach (var l in n.appearance) app.add_object_element (layer_out (l));
            o.set_array_member ("appearance", app);
            if (n.effects.size > 0) o.set_array_member ("effects", effects_out (n.effects));
            if (n.mask != null) {
                o.set_object_member ("mask", node_out (n.mask));
                o.set_boolean_member ("mask_clip", n.mask_clip);
                o.set_boolean_member ("mask_invert", n.mask_invert);
            }
            if (n.style_id != "") o.set_string_member ("style", n.style_id);
            if (n.note != "") o.set_string_member ("note", n.note);
            var pn = n as PathNode;
            if (pn != null) {
                o.set_string_member ("d", path_out (pn.path));
                if (pn.even_odd) o.set_boolean_member ("evenodd", true);
                if (pn.guide) o.set_boolean_member ("guide", true);
                if (pn.live != null) {
                    var lv = obj ();
                    lv.set_string_member ("kind", pn.live.kind);
                    lv.set_array_member ("v", numbers_out ({ pn.live.cx, pn.live.cy, pn.live.w, pn.live.h, pn.live.angle, pn.live.radius, pn.live.sides, pn.live.inner, pn.live.x2, pn.live.y2 }));
                    o.set_object_member ("live", lv);
                }
                if (pn.modes.size > 0) {
                    var mo = obj ();
                    foreach (var kv in pn.modes.entries) mo.set_int_member (kv.key.to_string (), kv.value);
                    o.set_object_member ("modes", mo);
                }
                if (pn.corners.size > 0) {
                    var co = obj ();
                    foreach (var kv in pn.corners.entries) co.set_double_member (kv.key.to_string (), kv.value);
                    o.set_object_member ("corners", co);
                    var ck = obj ();
                    foreach (var kv in pn.corner_kinds.entries) ck.set_int_member (kv.key.to_string (), kv.value);
                    o.set_object_member ("corner_kinds", ck);
                }
            }
            var g = n as GroupNode;
            if (g != null) {
                var kids = new Json.Array ();
                foreach (var c in g.children) kids.add_object_element (node_out (c));
                o.set_array_member ("children", kids);
                if (g.is_layer) {
                    o.set_boolean_member ("layer", true);
                    o.set_string_member ("color", g.color);
                    o.set_boolean_member ("printable", g.printable);
                    if (g.template) o.set_boolean_member ("template", true);
                }
                if (g.clip) o.set_boolean_member ("clip", true);
                var bl = n as BlendNode;
                if (bl != null) {
                    o.set_string_member ("spacing", bl.spacing);
                    o.set_int_member ("steps", bl.steps);
                    o.set_double_member ("distance", bl.distance);
                    if (bl.spine != null) o.set_string_member ("spine", path_out (bl.spine));
                    o.set_boolean_member ("align_spine", bl.align_spine);
                }
                var rp = n as RepeatNode;
                if (rp != null) {
                    o.set_string_member ("mode", rp.mode);
                    o.set_array_member ("v", numbers_out ({ rp.count, rp.radius, rp.start_angle, rp.rows, rp.cols, rp.hspace, rp.vspace, rp.axis_angle, rp.axis_offset }));
                }
                var ev = n as EnvelopeNode;
                if (ev != null) {
                    o.set_string_member ("mode", ev.mode);
                    o.set_string_member ("style", ev.style);
                    o.set_array_member ("v", numbers_out ({ ev.bend, ev.hdist, ev.vdist, ev.vertical ? 1 : 0, ev.mesh_rows, ev.mesh_cols }));
                    double[] gp = {};
                    foreach (var p in ev.grid) {
                        gp += p.x;
                        gp += p.y;
                    }
                    o.set_array_member ("grid", numbers_out (gp));
                    double[] qp = {};
                    foreach (var p in ev.quad) {
                        qp += p.x;
                        qp += p.y;
                    }
                    o.set_array_member ("quad", numbers_out (qp));
                }
                var lp = n as LivePaintNode;
                if (lp != null) {
                    var fills = new Json.Array ();
                    foreach (var f in lp.fills) {
                        var fo = obj ();
                        fo.set_double_member ("x", f.sample.x);
                        fo.set_double_member ("y", f.sample.y);
                        fo.set_object_member ("paint", paint_out (f.paint));
                        fills.add_object_element (fo);
                    }
                    o.set_array_member ("fills", fills);
                }
                var ch = n as ChartNode;
                if (ch != null) ch.write_json (o);
                var s3 = n as Shape3DNode;
                if (s3 != null) s3.write_json (o);
            }
            var tn = n as TextNode;
            if (tn != null) {
                o.set_string_member ("text", tn.text);
                o.set_string_member ("mode", tn.mode);
                o.set_array_member ("matrix", matrix_out (tn.matrix));
                o.set_object_member ("char", char_out (tn.style));
                var po = obj ();
                po.set_string_member ("align", tn.para.align);
                po.set_array_member ("v", numbers_out ({ tn.para.indent_first, tn.para.indent_left, tn.para.indent_right, tn.para.space_before, tn.para.space_after, tn.para.hyphenate ? 1 : 0 }));
                o.set_object_member ("para", po);
                var runs = new Json.Array ();
                foreach (var r in tn.runs) {
                    var ro = obj ();
                    ro.set_int_member ("start", r.start);
                    ro.set_int_member ("end", r.end);
                    ro.set_object_member ("style", char_out (r.style));
                    runs.add_object_element (ro);
                }
                o.set_array_member ("runs", runs);
                if (tn.area != null) o.set_string_member ("area", path_out (tn.area));
                if (tn.on_path != null) o.set_string_member ("on_path", path_out (tn.on_path));
                o.set_double_member ("path_offset", tn.path_offset);
                o.set_boolean_member ("path_flip", tn.path_flip);
                o.set_string_member ("thread_next", tn.thread_next);
                o.set_array_member ("cols", numbers_out ({ tn.columns, tn.gutter, tn.inset }));
            }
            var im = n as ImageNode;
            if (im != null) {
                o.set_string_member ("asset", im.asset);
                o.set_string_member ("link", im.link);
                o.set_string_member ("mime", im.mime);
                o.set_int_member ("pw", im.pixel_width);
                o.set_int_member ("ph", im.pixel_height);
                o.set_array_member ("matrix", matrix_out (im.matrix));
            }
            var sy = n as SymbolNode;
            if (sy != null) {
                o.set_string_member ("symbol", sy.symbol);
                o.set_array_member ("matrix", matrix_out (sy.matrix));
                var ov = obj ();
                foreach (var kv in sy.overrides.entries) ov.set_string_member (kv.key, kv.value);
                o.set_object_member ("overrides", ov);
            }
            var me = n as MeshNode;
            if (me != null) {
                o.set_int_member ("rows", me.rows);
                o.set_int_member ("cols", me.cols);
                var vs = new Json.Array ();
                foreach (var v in me.vertices) {
                    var vo = obj ();
                    vo.set_double_member ("x", v.x);
                    vo.set_double_member ("y", v.y);
                    vo.set_double_member ("opacity", v.opacity);
                    vo.set_object_member ("color", ink_out (v.color));
                    vs.add_object_element (vo);
                }
                o.set_array_member ("vertices", vs);
                o.set_array_member ("h", numbers_out (me.hcontrols));
                o.set_array_member ("vc", numbers_out (me.vcontrols));
            }
            return o;
        }

        public static Node? node_in (Json.Object o) {
            string t = str (o, "t", "");
            Node n;
            switch (t) {
                case "path": n = new PathNode (); break;
                case "group":
                case "layer": n = new GroupNode (); break;
                case "blend": n = new BlendNode (); break;
                case "repeat": n = new RepeatNode (); break;
                case "envelope": n = new EnvelopeNode (); break;
                case "livepaint": n = new LivePaintNode (); break;
                case "chart": n = new ChartNode (); break;
                case "shape3d": n = new Shape3DNode (); break;
                case "text": n = new TextNode (); break;
                case "image": n = new ImageNode (); break;
                case "symbol": n = new SymbolNode (); break;
                case "mesh": n = new MeshNode (); break;
                default: return null;
            }
            n.id = str (o, "id", "");
            n.name = str (o, "name", "");
            n.hidden = flag (o, "hidden", false);
            n.locked = flag (o, "locked", false);
            n.opacity = num (o, "opacity", 1);
            n.blend = BlendMode.from_id (str (o, "blend", "normal"));
            n.isolate = flag (o, "isolate", false);
            n.knockout = flag (o, "knockout", false);
            foreach (var e in arr (o, "appearance").get_elements ()) if (e.get_node_type () == Json.NodeType.OBJECT) n.appearance.add (layer_in (e.get_object ()));
            effects_in (o, "effects", n.effects);
            var mo = child (o, "mask");
            if (mo != null) {
                n.mask = node_in (mo);
                n.mask_clip = flag (o, "mask_clip", true);
                n.mask_invert = flag (o, "mask_invert", false);
            }
            n.style_id = str (o, "style", "");
            n.note = str (o, "note", "");
            var pn = n as PathNode;
            if (pn != null) {
                pn.path = PathData.parse_svg (str (o, "d", ""));
                pn.even_odd = flag (o, "evenodd", false);
                pn.guide = flag (o, "guide", false);
                var lv = child (o, "live");
                if (lv != null) {
                    var v = numbers_in (lv, "v");
                    if (v.length >= 10) {
                        pn.live = new LiveShape ();
                        pn.live.kind = str (lv, "kind", "rectangle");
                        pn.live.cx = v[0];
                        pn.live.cy = v[1];
                        pn.live.w = v[2];
                        pn.live.h = v[3];
                        pn.live.angle = v[4];
                        pn.live.radius = v[5];
                        pn.live.sides = (int) v[6];
                        pn.live.inner = v[7];
                        pn.live.x2 = v[8];
                        pn.live.y2 = v[9];
                    }
                }
                var modes = child (o, "modes");
                if (modes != null) foreach (var k in modes.get_members ()) pn.modes[int.parse (k)] = (int) num (modes, k, 0);
                var co = child (o, "corners");
                if (co != null) foreach (var k in co.get_members ()) pn.corners[int.parse (k)] = num (co, k, 0);
                var ck = child (o, "corner_kinds");
                if (ck != null) foreach (var k in ck.get_members ()) pn.corner_kinds[int.parse (k)] = (int) num (ck, k, 0);
            }
            var g = n as GroupNode;
            if (g != null) {
                foreach (var e in arr (o, "children").get_elements ()) {
                    if (e.get_node_type () != Json.NodeType.OBJECT) continue;
                    var c = node_in (e.get_object ());
                    if (c != null) g.add (c);
                }
                g.is_layer = flag (o, "layer", false);
                g.color = str (o, "color", "#4a90d9");
                g.printable = flag (o, "printable", true);
                g.template = flag (o, "template", false);
                g.clip = flag (o, "clip", false);
                var bl = n as BlendNode;
                if (bl != null) {
                    bl.spacing = str (o, "spacing", "steps");
                    bl.steps = (int) num (o, "steps", 5);
                    bl.distance = num (o, "distance", 20);
                    if (o.has_member ("spine")) bl.spine = PathData.parse_svg (str (o, "spine", ""));
                    bl.align_spine = flag (o, "align_spine", false);
                }
                var rp = n as RepeatNode;
                if (rp != null) {
                    rp.mode = str (o, "mode", "radial");
                    var v = numbers_in (o, "v");
                    if (v.length >= 9) {
                        rp.count = (int) v[0];
                        rp.radius = v[1];
                        rp.start_angle = v[2];
                        rp.rows = (int) v[3];
                        rp.cols = (int) v[4];
                        rp.hspace = v[5];
                        rp.vspace = v[6];
                        rp.axis_angle = v[7];
                        rp.axis_offset = v[8];
                    }
                }
                var ev = n as EnvelopeNode;
                if (ev != null) {
                    ev.mode = str (o, "mode", "warp");
                    ev.style = str (o, "style", "arc");
                    var v = numbers_in (o, "v");
                    if (v.length >= 6) {
                        ev.bend = v[0];
                        ev.hdist = v[1];
                        ev.vdist = v[2];
                        ev.vertical = v[3] != 0;
                        ev.mesh_rows = (int) v[4];
                        ev.mesh_cols = (int) v[5];
                    }
                    var gp = numbers_in (o, "grid");
                    Point[] grid = {};
                    for (int i = 0; i + 1 < gp.length; i += 2) grid += Point (gp[i], gp[i + 1]);
                    ev.grid = grid;
                    var qp = numbers_in (o, "quad");
                    Point[] quad = {};
                    for (int i = 0; i + 1 < qp.length; i += 2) quad += Point (qp[i], qp[i + 1]);
                    ev.quad = quad;
                }
                var lp = n as LivePaintNode;
                if (lp != null) {
                    foreach (var e in arr (o, "fills").get_elements ()) {
                        var fo = e.get_object ();
                        lp.fills.add (new LivePaintFill (Point (num (fo, "x", 0), num (fo, "y", 0)), paint_in (child (fo, "paint"))));
                    }
                }
                var ch = n as ChartNode;
                if (ch != null) ch.read_json (o);
                var s3 = n as Shape3DNode;
                if (s3 != null) s3.read_json (o);
            }
            var tn = n as TextNode;
            if (tn != null) {
                tn.text = str (o, "text", "");
                tn.mode = str (o, "mode", "point");
                tn.matrix = matrix_in (o, "matrix");
                tn.style = char_in (child (o, "char"));
                var po = child (o, "para");
                if (po != null) {
                    tn.para.align = str (po, "align", "left");
                    var v = numbers_in (po, "v");
                    if (v.length >= 6) {
                        tn.para.indent_first = v[0];
                        tn.para.indent_left = v[1];
                        tn.para.indent_right = v[2];
                        tn.para.space_before = v[3];
                        tn.para.space_after = v[4];
                        tn.para.hyphenate = v[5] != 0;
                    }
                }
                foreach (var e in arr (o, "runs").get_elements ()) {
                    var ro = e.get_object ();
                    tn.runs.add (new TextRun ((int) num (ro, "start", 0), (int) num (ro, "end", 0), char_in (child (ro, "style"))));
                }
                if (o.has_member ("area")) tn.area = PathData.parse_svg (str (o, "area", ""));
                if (o.has_member ("on_path")) tn.on_path = PathData.parse_svg (str (o, "on_path", ""));
                tn.path_offset = num (o, "path_offset", 0);
                tn.path_flip = flag (o, "path_flip", false);
                tn.thread_next = str (o, "thread_next", "");
                var cols = numbers_in (o, "cols");
                if (cols.length >= 3) {
                    tn.columns = int.max (1, (int) cols[0]);
                    tn.gutter = cols[1];
                    tn.inset = cols[2];
                }
            }
            var im = n as ImageNode;
            if (im != null) {
                im.asset = str (o, "asset", "");
                im.link = str (o, "link", "");
                im.mime = str (o, "mime", "image/png");
                im.pixel_width = (int) num (o, "pw", 1);
                im.pixel_height = (int) num (o, "ph", 1);
                im.matrix = matrix_in (o, "matrix");
            }
            var sy = n as SymbolNode;
            if (sy != null) {
                sy.symbol = str (o, "symbol", "");
                sy.matrix = matrix_in (o, "matrix");
                var ov = child (o, "overrides");
                if (ov != null) foreach (var k in ov.get_members ()) sy.overrides[k] = str (ov, k, "");
            }
            var me = n as MeshNode;
            if (me != null) {
                me.rows = (int) num (o, "rows", 1);
                me.cols = (int) num (o, "cols", 1);
                foreach (var e in arr (o, "vertices").get_elements ()) {
                    var vo = e.get_object ();
                    var v = new MeshVertex (num (vo, "x", 0), num (vo, "y", 0), ink_in (child (vo, "color")));
                    v.opacity = num (vo, "opacity", 1);
                    me.vertices.add (v);
                }
                me.hcontrols = numbers_in (o, "h");
                me.vcontrols = numbers_in (o, "vc");
                if (me.vertices.size != (me.rows + 1) * (me.cols + 1)) return null;
                if (me.hcontrols.length != (me.rows + 1) * me.cols * 4 || me.vcontrols.length != (me.cols + 1) * me.rows * 4) me.reset_controls ();
            }
            return n;
        }

        public static Json.Object document_out (VectorDocument d, bool with_assets) {
            var o = obj ();
            o.set_string_member ("format", "singularity-vector");
            o.set_int_member ("version", VERSION);
            o.set_string_member ("title", d.title);
            o.set_string_member ("units", d.units);
            o.set_string_member ("color_mode", d.color_mode);
            o.set_boolean_member ("proof", d.proof);
            o.set_boolean_member ("overprint_preview", d.overprint_preview);
            o.set_double_member ("grid_size", d.grid_size);
            o.set_int_member ("grid_sub", d.grid_sub);
            o.set_boolean_member ("pixel_grid", d.pixel_grid);
            o.set_int_member ("active_artboard", d.active_artboard);
            o.set_int_member ("next_id", d.next_id);
            if (d.active_layer != null) o.set_string_member ("active_layer", d.active_layer.id);
            var abs = new Json.Array ();
            foreach (var a in d.artboards) {
                var ao = obj ();
                ao.set_string_member ("id", a.id);
                ao.set_string_member ("name", a.name);
                ao.set_array_member ("rect", numbers_out ({ a.x, a.y, a.w, a.h, a.bleed }));
                ao.set_string_member ("background", a.background);
                abs.add_object_element (ao);
            }
            o.set_array_member ("artboards", abs);
            var ls = new Json.Array ();
            foreach (var l in d.layers) ls.add_object_element (node_out (l));
            o.set_array_member ("layers", ls);
            var sws = new Json.Array ();
            foreach (var s in d.swatches) {
                var so = obj ();
                so.set_string_member ("id", s.id);
                so.set_string_member ("name", s.name);
                so.set_boolean_member ("global", s.is_global);
                so.set_string_member ("group", s.group);
                so.set_object_member ("paint", paint_out (s.paint));
                sws.add_object_element (so);
            }
            o.set_array_member ("swatches", sws);
            var sts = new Json.Array ();
            foreach (var s in d.styles) {
                var so = obj ();
                so.set_string_member ("id", s.id);
                so.set_string_member ("name", s.name);
                var app = new Json.Array ();
                foreach (var l in s.appearance) app.add_object_element (layer_out (l));
                so.set_array_member ("appearance", app);
                so.set_array_member ("effects", effects_out (s.effects));
                so.set_double_member ("opacity", s.opacity);
                so.set_string_member ("blend", s.blend.to_id ());
                sts.add_object_element (so);
            }
            o.set_array_member ("styles", sts);
            var sys = new Json.Array ();
            foreach (var s in d.symbols) {
                var so = obj ();
                so.set_string_member ("id", s.id);
                so.set_string_member ("name", s.name);
                so.set_boolean_member ("is_dynamic", s.is_dynamic);
                so.set_object_member ("art", node_out (s.art));
                sys.add_object_element (so);
            }
            o.set_array_member ("symbols", sys);
            var brs = new Json.Array ();
            foreach (var b in d.brushes) {
                var bo = obj ();
                bo.set_string_member ("id", b.id);
                bo.set_string_member ("name", b.name);
                bo.set_string_member ("kind", b.kind);
                bo.set_array_member ("v", numbers_out ({ b.angle, b.roundness, b.size, b.spacing, b.scatter, b.size_jitter, b.rotation_jitter, b.rotate_with_path ? 1 : 0, b.stretch ? 1 : 0 }));
                bo.set_string_member ("colorize", b.colorize);
                if (b.art != null) bo.set_object_member ("art", node_out (b.art));
                brs.add_object_element (bo);
            }
            o.set_array_member ("brushes", brs);
            var pts = new Json.Array ();
            foreach (var p in d.patterns) {
                var po = obj ();
                po.set_string_member ("id", p.id);
                po.set_string_member ("name", p.name);
                po.set_string_member ("tiling", p.tiling);
                po.set_array_member ("v", numbers_out ({ p.w, p.h, p.hspace, p.vspace, p.offset }));
                po.set_object_member ("tile", node_out (p.tile));
                pts.add_object_element (po);
            }
            o.set_array_member ("patterns", pts);
            var gds = new Json.Array ();
            foreach (var g in d.guides) gds.add_array_element (numbers_out ({ g.vertical ? 1 : 0, g.pos }));
            o.set_array_member ("guides", gds);
            var pg = d.perspective;
            o.set_array_member ("perspective", numbers_out ({ pg.visible ? 1 : 0, pg.points, pg.horizon, pg.vp1x, pg.vp2x, pg.vp3y, pg.center_x, pg.ground, pg.cell }));
            var acts = new Json.Array ();
            foreach (var a in d.actions) {
                var ao = obj ();
                ao.set_string_member ("name", a.name);
                var steps = new Json.Array ();
                foreach (var s in a.steps) steps.add_string_element (s);
                ao.set_array_member ("steps", steps);
                acts.add_object_element (ao);
            }
            o.set_array_member ("actions", acts);
            if (with_assets) {
                var assets = new Json.Array ();
                foreach (var a in d.assets.values) {
                    if (!asset_used (d, a.id)) continue;
                    var ao = obj ();
                    ao.set_string_member ("id", a.id);
                    ao.set_string_member ("mime", a.mime);
                    ao.set_string_member ("data", Base64.encode (a.data.get_data ()));
                    assets.add_object_element (ao);
                }
                o.set_array_member ("assets", assets);
            }
            return o;
        }

        private static bool asset_used (VectorDocument d, string id) {
            bool used = false;
            foreach (var l in d.layers) {
                l.walk ((n) => {
                    var im = n as ImageNode;
                    if (im != null && im.asset == id) used = true;
                    return !used;
                });
            }
            foreach (var s in d.symbols) s.art.walk ((n) => {
                var im = n as ImageNode;
                if (im != null && im.asset == id) used = true;
                return !used;
            });
            foreach (var p in d.patterns) p.tile.walk ((n) => {
                var im = n as ImageNode;
                if (im != null && im.asset == id) used = true;
                return !used;
            });
            return used;
        }

        public static void document_in (VectorDocument d, Json.Object o, bool with_assets) throws Error {
            if (str (o, "format", "") != "singularity-vector") throw new IOError.INVALID_DATA (_("This is not a Vector document."));
            if (num (o, "version", 0) > VERSION) throw new IOError.NOT_SUPPORTED (_("This Vector document was made by a newer version."));
            d.title = str (o, "title", d.title);
            d.units = str (o, "units", "px");
            d.color_mode = str (o, "color_mode", "rgb");
            d.proof = flag (o, "proof", false);
            d.overprint_preview = flag (o, "overprint_preview", false);
            d.grid_size = num (o, "grid_size", 20);
            d.grid_sub = (int) num (o, "grid_sub", 4);
            d.pixel_grid = flag (o, "pixel_grid", false);
            d.active_artboard = (int) num (o, "active_artboard", 0);
            d.next_id = int.max (d.next_id, (int) num (o, "next_id", 1));
            d.artboards.clear ();
            foreach (var e in arr (o, "artboards").get_elements ()) {
                var ao = e.get_object ();
                var r = numbers_in (ao, "rect");
                if (r.length < 4 || !(r[2] > 0) || !(r[3] > 0) || !r[0].is_finite () || !r[1].is_finite ()) throw new IOError.INVALID_DATA (_("An artboard has invalid dimensions."));
                var a = new Artboard (str (ao, "name", ""), r[0], r[1], r[2], r[3]);
                a.id = str (ao, "id", "");
                if (r.length > 4) a.bleed = r[4];
                a.background = str (ao, "background", "");
                d.artboards.add (a);
            }
            if (d.artboards.size == 0) throw new IOError.INVALID_DATA (_("The document has no artboards."));
            d.layers.clear ();
            foreach (var e in arr (o, "layers").get_elements ()) {
                var n = node_in (e.get_object ()) as GroupNode;
                if (n == null) continue;
                n.is_layer = true;
                d.layers.add (n);
            }
            d.swatches.clear ();
            foreach (var e in arr (o, "swatches").get_elements ()) {
                var so = e.get_object ();
                var s = new Swatch (str (so, "name", ""), paint_in (child (so, "paint")));
                s.id = str (so, "id", "");
                s.is_global = flag (so, "global", false);
                s.group = str (so, "group", "");
                d.swatches.add (s);
            }
            d.styles.clear ();
            foreach (var e in arr (o, "styles").get_elements ()) {
                var so = e.get_object ();
                var s = new GraphicStyle ();
                s.id = str (so, "id", "");
                s.name = str (so, "name", "");
                foreach (var l in arr (so, "appearance").get_elements ()) s.appearance.add (layer_in (l.get_object ()));
                effects_in (so, "effects", s.effects);
                s.opacity = num (so, "opacity", 1);
                s.blend = BlendMode.from_id (str (so, "blend", "normal"));
                d.styles.add (s);
            }
            d.symbols.clear ();
            foreach (var e in arr (o, "symbols").get_elements ()) {
                var so = e.get_object ();
                var s = new SymbolDef ();
                s.id = str (so, "id", "");
                s.name = str (so, "name", "");
                s.is_dynamic = flag (so, "is_dynamic", false);
                var art = child (so, "art");
                var node = art != null ? node_in (art) as GroupNode : null;
                if (node != null) s.art = node;
                d.symbols.add (s);
            }
            d.brushes.clear ();
            foreach (var e in arr (o, "brushes").get_elements ()) {
                var bo = e.get_object ();
                var b = new BrushDef ();
                b.id = str (bo, "id", "");
                b.name = str (bo, "name", "");
                b.kind = str (bo, "kind", "calligraphic");
                var v = numbers_in (bo, "v");
                if (v.length >= 9) {
                    b.angle = v[0];
                    b.roundness = v[1];
                    b.size = v[2];
                    b.spacing = v[3];
                    b.scatter = v[4];
                    b.size_jitter = v[5];
                    b.rotation_jitter = v[6];
                    b.rotate_with_path = v[7] != 0;
                    b.stretch = v[8] != 0;
                }
                b.colorize = str (bo, "colorize", "none");
                var art = child (bo, "art");
                if (art != null) b.art = node_in (art) as GroupNode;
                d.brushes.add (b);
            }
            d.patterns.clear ();
            foreach (var e in arr (o, "patterns").get_elements ()) {
                var po = e.get_object ();
                var p = new PatternDef ();
                p.id = str (po, "id", "");
                p.name = str (po, "name", "");
                p.tiling = str (po, "tiling", "grid");
                var v = numbers_in (po, "v");
                if (v.length >= 5) {
                    p.w = v[0];
                    p.h = v[1];
                    p.hspace = v[2];
                    p.vspace = v[3];
                    p.offset = v[4];
                }
                var tile = child (po, "tile");
                if (tile != null) {
                    var t = node_in (tile) as GroupNode;
                    if (t != null) p.tile = t;
                }
                d.patterns.add (p);
            }
            d.guides.clear ();
            foreach (var e in arr (o, "guides").get_elements ()) {
                var a = e.get_array ();
                if (a.get_length () == 2) d.guides.add (new Guide (a.get_double_element (0) != 0, a.get_double_element (1)));
            }
            var pg = numbers_in (o, "perspective");
            if (pg.length >= 9) {
                d.perspective.visible = pg[0] != 0;
                d.perspective.points = (int) pg[1];
                d.perspective.horizon = pg[2];
                d.perspective.vp1x = pg[3];
                d.perspective.vp2x = pg[4];
                d.perspective.vp3y = pg[5];
                d.perspective.center_x = pg[6];
                d.perspective.ground = pg[7];
                d.perspective.cell = pg[8];
            }
            d.actions.clear ();
            foreach (var e in arr (o, "actions").get_elements ()) {
                var ao = e.get_object ();
                var a = new RecordedAction ();
                a.name = str (ao, "name", "");
                foreach (var s in arr (ao, "steps").get_elements ()) a.steps.add (s.get_string ());
                d.actions.add (a);
            }
            if (with_assets) {
                foreach (var e in arr (o, "assets").get_elements ()) {
                    var ao = e.get_object ();
                    string id = str (ao, "id", "");
                    if (id == "") continue;
                    d.assets[id] = new Asset (id, str (ao, "mime", "image/png"), new Bytes (Base64.decode (str (ao, "data", ""))));
                }
            }
            d.relink ();
            string layer_id = str (o, "active_layer", "");
            foreach (var l in d.layers) if (l.id == layer_id) d.active_layer = l;
            d.ensure_ids ();
        }

        public static string to_string (VectorDocument d, bool with_assets = true, bool pretty = false) {
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (document_out (d, with_assets));
            var gen = new Json.Generator ();
            gen.pretty = pretty;
            gen.set_root (root);
            return gen.to_data (null);
        }

        public static VectorDocument parse (string text) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA (_("The document root is invalid."));
            var d = new VectorDocument ();
            document_in (d, root.get_object (), true);
            return d;
        }

        public static string snapshot (VectorDocument d) {
            return to_string (d, false, false);
        }

        public static void restore (VectorDocument d, string state) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (state);
            document_in (d, parser.get_root ().get_object (), false);
        }

        public static string nodes_to_string (Gee.List<Node> nodes, VectorDocument d) {
            var o = obj ();
            o.set_string_member ("format", "singularity-vector-clip");
            var list = new Json.Array ();
            foreach (var n in nodes) list.add_object_element (node_out (n));
            o.set_array_member ("nodes", list);
            var assets = new Json.Array ();
            var used = new Gee.HashSet<string> ();
            foreach (var n in nodes) collect_assets (n, used);
            foreach (var id in used) {
                if (!d.assets.has_key (id)) continue;
                var a = d.assets[id];
                var ao = obj ();
                ao.set_string_member ("id", a.id);
                ao.set_string_member ("mime", a.mime);
                ao.set_string_member ("data", Base64.encode (a.data.get_data ()));
                assets.add_object_element (ao);
            }
            o.set_array_member ("assets", assets);
            var syms = new Json.Array ();
            var sym_ids = new Gee.HashSet<string> ();
            foreach (var n in nodes) collect_symbols (n, sym_ids);
            foreach (var sid in sym_ids) {
                var s = d.find_symbol (sid);
                if (s == null) continue;
                var so = obj ();
                so.set_string_member ("id", s.id);
                so.set_string_member ("name", s.name);
                so.set_object_member ("art", node_out (s.art));
                syms.add_object_element (so);
            }
            o.set_array_member ("symbols", syms);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (o);
            var gen = new Json.Generator ();
            gen.set_root (root);
            return gen.to_data (null);
        }

        private static void collect_assets (Node n, Gee.HashSet<string> used) {
            var im = n as ImageNode;
            if (im != null && im.asset != "") used.add (im.asset);
            var g = n as GroupNode;
            if (g != null) foreach (var c in g.children) collect_assets (c, used);
        }

        private static void collect_symbols (Node n, Gee.HashSet<string> used) {
            var s = n as SymbolNode;
            if (s != null) used.add (s.symbol);
            var g = n as GroupNode;
            if (g != null) foreach (var c in g.children) collect_symbols (c, used);
        }

        public static Gee.ArrayList<Node> nodes_from_string (string text, VectorDocument d) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ().get_object ();
            if (str (root, "format", "") != "singularity-vector-clip") throw new IOError.INVALID_DATA (_("The clipboard does not contain Vector artwork."));
            foreach (var e in arr (root, "assets").get_elements ()) {
                var ao = e.get_object ();
                string id = str (ao, "id", "");
                if (id != "" && !d.assets.has_key (id)) d.assets[id] = new Asset (id, str (ao, "mime", "image/png"), new Bytes (Base64.decode (str (ao, "data", ""))));
            }
            foreach (var e in arr (root, "symbols").get_elements ()) {
                var so = e.get_object ();
                string id = str (so, "id", "");
                if (d.find_symbol (id) != null) continue;
                var s = new SymbolDef ();
                s.id = id;
                s.name = str (so, "name", "");
                var art = child (so, "art");
                var node = art != null ? node_in (art) as GroupNode : null;
                if (node != null) s.art = node;
                d.symbols.add (s);
            }
            var list = new Gee.ArrayList<Node> ();
            foreach (var e in arr (root, "nodes").get_elements ()) {
                var n = node_in (e.get_object ());
                if (n != null) list.add (n);
            }
            return list;
        }
    }
}
