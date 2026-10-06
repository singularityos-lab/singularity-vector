using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Brushes {
        public static void draw (Cairo.Context cr, PathData path, PaintLayer l, BrushDef brush, Rect box, RenderContext ctx, Ink? color_override) {
            var group = expand (path, l, brush, ctx);
            foreach (var c in group.children) Renderer.draw_node (cr, c, ctx);
        }

        private static void tint (Node n, Paint stroke_paint, string mode) {
            if (mode == "none") return;
            var base_ink = stroke_paint.representative ();
            foreach (var layer in n.appearance) {
                if (!layer.paint.visible ()) continue;
                if (mode == "tints") {
                    var src = layer.paint.representative ();
                    double t = 1 - src.luminance ();
                    layer.paint = new Paint.solid (new Ink.rgb (1 - (1 - base_ink.r) * t, 1 - (1 - base_ink.g) * t, 1 - (1 - base_ink.b) * t));
                } else {
                    layer.paint = stroke_paint.copy ();
                }
            }
            var g = n as GroupNode;
            if (g != null) foreach (var c in g.children) tint (c, stroke_paint, mode);
        }

        public static GroupNode expand (PathData path, PaintLayer l, BrushDef brush, RenderContext ctx) {
            var out_group = new GroupNode ();
            double scale = l.width * l.brush_scale;
            switch (brush.kind) {
                case "calligraphic": {
                    var outline = calligraphic (path, brush, scale);
                    var node = new PathNode.with_path (outline);
                    node.appearance.add (new PaintLayer.fill (l.paint.copy ()));
                    out_group.add (node);
                    break;
                }
                case "scatter": {
                    if (brush.art == null) break;
                    var art_box = brush.art.geometric_bounds ();
                    if (art_box.w <= 0 && art_box.h <= 0) break;
                    double size = double.max (art_box.w, art_box.h);
                    double k = scale / size * 4;
                    double step = double.max (size * k * brush.spacing, 1);
                    var rand = new GLib.Rand.with_seed (17);
                    foreach (var contour in PathOps.contours (path)) {
                        double len = PathOps.length (contour);
                        for (double d = 0; d <= len; d += step) {
                            Point p;
                            double angle;
                            PathOps.point_at (contour, d, out p, out angle);
                            double jitter = 1 + (rand.next_double () * 2 - 1) * brush.size_jitter;
                            double off = (rand.next_double () * 2 - 1) * brush.scatter * size * k;
                            double rot = (brush.rotate_with_path ? angle : 0) + (rand.next_double () * 2 - 1) * brush.rotation_jitter * Math.PI;
                            var copy = brush.art.clone ();
                            tint (copy, l.paint, brush.colorize);
                            var m = Transforms.translate (-art_box.cx (), -art_box.cy ());
                            var s = Cairo.Matrix.identity ();
                            s.scale (k * jitter, k * jitter);
                            m = Transforms.multiply (m, s);
                            var r = Cairo.Matrix.identity ();
                            r.rotate (rot);
                            m = Transforms.multiply (m, r);
                            m = Transforms.multiply (m, Transforms.translate (p.x - Math.sin (angle) * off, p.y + Math.cos (angle) * off));
                            copy.apply_transform (m, true);
                            out_group.add (copy);
                        }
                    }
                    break;
                }
                case "art": {
                    if (brush.art == null) break;
                    var art_box = brush.art.geometric_bounds ();
                    if (art_box.w <= 0) break;
                    foreach (var contour in PathOps.contours (path)) {
                        double len = PathOps.length (contour);
                        double k = scale / double.max (art_box.h, 0.01) * 2;
                        var copy = brush.art.clone ();
                        tint (copy, l.paint, brush.colorize);
                        bend (copy, contour, art_box, 0, len, k);
                        out_group.add (copy);
                    }
                    break;
                }
                case "pattern": {
                    if (brush.art == null) break;
                    var art_box = brush.art.geometric_bounds ();
                    if (art_box.w <= 0) break;
                    double k = scale / double.max (art_box.h, 0.01) * 2;
                    double tile = art_box.w * k * (1 + brush.spacing);
                    foreach (var contour in PathOps.contours (path)) {
                        double len = PathOps.length (contour);
                        int count = int.max (1, (int) Math.round (len / double.max (tile, 0.5)));
                        double each = len / count;
                        for (int i = 0; i < count; i++) {
                            var copy = brush.art.clone ();
                            tint (copy, l.paint, brush.colorize);
                            double gap = each * brush.spacing / (1 + brush.spacing);
                            bend (copy, contour, art_box, i * each, i * each + each - gap, k);
                            out_group.add (copy);
                        }
                    }
                    break;
                }
            }
            return out_group;
        }

        private static void bend (Node n, PathData contour, Rect art_box, double from, double to, double k) {
            var g = n as GroupNode;
            if (g != null) {
                foreach (var c in g.children) bend (c, contour, art_box, from, to, k);
                return;
            }
            var pn = n as PathNode;
            if (pn == null) return;
            double span = to - from;
            pn.live = null;
            pn.path = PathOps.map_points (pn.render_path (), (q) => {
                double s = from + (q.x - art_box.x) / art_box.w * span;
                double off = (q.y - art_box.cy ()) * k;
                Point p;
                double angle;
                PathOps.point_at (contour, s, out p, out angle);
                return Point (p.x - Math.sin (angle) * off, p.y + Math.cos (angle) * off);
            }, 0.2);
            foreach (var layer in pn.appearance) if (layer.stroke) layer.width *= k;
        }

        public static PathData calligraphic (PathData path, BrushDef brush, double scale) {
            var result = new PathData ();
            double a = brush.angle * Math.PI / 180;
            double major = scale * brush.size / 8 * 4, minor = major * brush.roundness.clamp (0.02, 1);
            foreach (var contour in PathOps.contours (path)) {
                var samples = PathOps.sample (contour, 0.75);
                if (samples.size < 2) continue;
                Point[] centers = {};
                double[] widths = {};
                foreach (var s in samples) {
                    double rel = s.angle - a;
                    double w = Math.sqrt (Math.pow (major * Math.sin (rel), 2) + Math.pow (minor * Math.cos (rel), 2));
                    centers += s.point;
                    widths += double.max (w, 0.2);
                }
                var outline = StrokeOutline.build (centers, widths, true);
                if (outline.length > 2) result.append (StrokeOutline.to_path (outline));
            }
            return CurveOffset.clean (result);
        }
    }

    public class Arrows {
        public static string[] ids () {
            return { "", "triangle", "open", "circle", "square", "bar", "diamond" };
        }

        public static string[] labels () {
            return { _("None"), _("Triangle"), _("Open Arrow"), _("Circle"), _("Square"), _("Bar"), _("Diamond") };
        }

        public static PathData trim (PathData path, PaintLayer l) {
            double len = PathOps.length (path);
            double cut = l.width * 3;
            double from = l.arrow_start == "triangle" || l.arrow_start == "diamond" ? cut : 0;
            double to = l.arrow_end == "triangle" || l.arrow_end == "diamond" ? len - cut : len;
            if (to <= from || PathOps.contours (path).size != 1) return path;
            return CurveOffset.sub_path (path, from, to);
        }

        public static void draw (Cairo.Context cr, PathData path, PaintLayer l, Rect box, RenderContext ctx, Ink? override_color) {
            if (PathOps.contours (path).size != 1 || PathOps.all_closed (path)) return;
            double len = PathOps.length (path);
            Point p;
            double angle;
            if (l.arrow_start != "") {
                PathOps.point_at (path, 0, out p, out angle);
                head (cr, l.arrow_start, p, angle + Math.PI, l, box, ctx, override_color);
            }
            if (l.arrow_end != "") {
                PathOps.point_at (path, len, out p, out angle);
                head (cr, l.arrow_end, p, angle, l, box, ctx, override_color);
            }
        }

        private static void head (Cairo.Context cr, string kind, Point tip, double angle, PaintLayer l, Rect box, RenderContext ctx, Ink? override_color) {
            double s = l.width * 3;
            cr.save ();
            cr.translate (tip.x, tip.y);
            cr.rotate (angle);
            cr.new_path ();
            bool fill = true;
            switch (kind) {
                case "open":
                    cr.move_to (-s, -s * 0.6);
                    cr.line_to (0, 0);
                    cr.line_to (-s, s * 0.6);
                    fill = false;
                    break;
                case "circle":
                    cr.arc (0, 0, s * 0.45, 0, 2 * Math.PI);
                    break;
                case "square":
                    cr.rectangle (-s * 0.4, -s * 0.4, s * 0.8, s * 0.8);
                    break;
                case "bar":
                    cr.rectangle (-l.width / 2, -s * 0.6, l.width, s * 1.2);
                    break;
                case "diamond":
                    cr.move_to (0, 0);
                    cr.line_to (-s * 0.5, -s * 0.4);
                    cr.line_to (-s, 0);
                    cr.line_to (-s * 0.5, s * 0.4);
                    cr.close_path ();
                    break;
                default:
                    cr.move_to (0, 0);
                    cr.line_to (-s, -s * 0.5);
                    cr.line_to (-s, s * 0.5);
                    cr.close_path ();
                    break;
            }
            cr.restore ();
            Renderer.set_paint (cr, l.paint, box, ctx, override_color);
            if (fill) {
                cr.fill ();
            } else {
                cr.set_line_width (l.width);
                cr.set_line_join (Cairo.LineJoin.MITER);
                cr.stroke ();
            }
        }
    }
}
