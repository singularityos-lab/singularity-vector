using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Transforms {
        public static Cairo.Matrix multiply (Cairo.Matrix first, Cairo.Matrix then) {
            Cairo.Matrix r;
            r = Cairo.Matrix.identity ();
            r.multiply (first, then);
            return r;
        }

        public static Cairo.Matrix translate (double dx, double dy) {
            var m = Cairo.Matrix.identity ();
            m.translate (dx, dy);
            return m;
        }

        public static Cairo.Matrix about (Point origin, Cairo.Matrix inner) {
            var a = translate (-origin.x, -origin.y);
            var b = translate (origin.x, origin.y);
            return multiply (multiply (a, inner), b);
        }

        public static Cairo.Matrix rotate (double radians, Point origin) {
            var m = Cairo.Matrix.identity ();
            m.rotate (radians);
            return about (origin, m);
        }

        public static Cairo.Matrix scale (double sx, double sy, Point origin) {
            var m = Cairo.Matrix.identity ();
            m.scale (sx, sy);
            return about (origin, m);
        }

        public static Cairo.Matrix shear (double angle_deg, bool horizontal, Point origin) {
            double t = Math.tan (angle_deg * Math.PI / 180);
            var m = horizontal ? Cairo.Matrix (1, 0, t, 1, 0, 0) : Cairo.Matrix (1, t, 0, 1, 0, 0);
            return about (origin, m);
        }

        public static Cairo.Matrix reflect (double axis_deg, Point origin) {
            double a = axis_deg * Math.PI / 180;
            double c = Math.cos (2 * a), s = Math.sin (2 * a);
            var m = Cairo.Matrix (c, s, s, -c, 0, 0);
            return about (origin, m);
        }

        public static Rect rect_bounds (Rect r, Cairo.Matrix m) {
            double[] xs = { r.x, r.x + r.w, r.x + r.w, r.x };
            double[] ys = { r.y, r.y, r.y + r.h, r.y + r.h };
            var box = Rect.empty ();
            for (int i = 0; i < 4; i++) {
                double x = xs[i], y = ys[i];
                m.transform_point (ref x, ref y);
                box = i == 0 ? Rect (x, y, 0, 0) : box.include (x, y);
            }
            return box;
        }

        public static double scale_factor (Cairo.Matrix m) {
            return Math.sqrt ((m.xx * m.yy - m.xy * m.yx).abs ());
        }

        public static void transform_paint (Paint p, Cairo.Matrix m) {
            var g = p.gradient;
            m.transform_point (ref g.x1, ref g.y1);
            m.transform_point (ref g.x2, ref g.y2);
            m.transform_point (ref g.fx, ref g.fy);
            foreach (var f in p.freeform) m.transform_point (ref f.x, ref f.y);
            p.pattern_matrix = multiply (p.pattern_matrix, m);
        }

        public static void after_transform (Node n, Rect before, Cairo.Matrix m, bool scale_strokes, bool paints = true) {
            double s = scale_factor (m);
            foreach (var l in n.appearance) {
                transform_paint (l.paint, m);
                if (l.stroke && scale_strokes) l.width *= s;
            }
            if (scale_strokes && s != 1) {
                foreach (var e in n.effects) {
                    foreach (var key in new string[] { "dx", "dy", "blur", "distance", "radius", "size" }) {
                        if (e.num.has_key (key)) e.num[key] = e.num[key] * s;
                    }
                }
            }
            var pn = n as PathNode;
            if (pn != null && scale_strokes && s != 1) {
                var keys = new Gee.ArrayList<int> ();
                keys.add_all (pn.corners.keys);
                foreach (int k in keys) pn.corners[k] = pn.corners[k] * s;
            }
        }

        public static void fit_gradient (Paint p, Rect box, double angle_deg = 0) {
            var g = p.gradient;
            double a = angle_deg * Math.PI / 180;
            double cx = box.cx (), cy = box.cy ();
            if (p.kind == PaintKind.RADIAL) {
                double r = double.max (box.w, box.h) / 2;
                g.x1 = cx;
                g.y1 = cy;
                g.x2 = cx + r * Math.cos (a);
                g.y2 = cy + r * Math.sin (a);
                g.fx = cx;
                g.fy = cy;
                g.aspect = box.w > 0 && box.h > 0 ? double.min (box.w, box.h) / double.max (box.w, box.h) : 1;
                if (box.w >= box.h) g.aspect = box.h / double.max (box.w, 1e-9);
                else {
                    g.x2 = cx;
                    g.y2 = cy - r;
                    g.aspect = box.w / double.max (box.h, 1e-9);
                }
                return;
            }
            double half = (box.w * Math.cos (a)).abs () / 2 + (box.h * Math.sin (a)).abs () / 2;
            g.x1 = cx - Math.cos (a) * half;
            g.y1 = cy - Math.sin (a) * half;
            g.x2 = cx + Math.cos (a) * half;
            g.y2 = cy + Math.sin (a) * half;
            g.fx = cx;
            g.fy = cy;
        }
    }
}
