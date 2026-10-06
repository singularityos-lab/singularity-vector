using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Dxf {
        private class Entity {
            public string type;
            public Gee.ArrayList<int> codes = new Gee.ArrayList<int> ();
            public Gee.ArrayList<string> values = new Gee.ArrayList<string> ();

            public Entity (string type) {
                this.type = type;
            }

            public double num (int code, double fallback = 0) {
                for (int i = 0; i < codes.size; i++) if (codes[i] == code) return double.parse (values[i]);
                return fallback;
            }

            public string str (int code, string fallback = "") {
                for (int i = 0; i < codes.size; i++) if (codes[i] == code) return values[i];
                return fallback;
            }

            public double[] all (int code) {
                double[] r = {};
                for (int i = 0; i < codes.size; i++) if (codes[i] == code) r += double.parse (values[i]);
                return r;
            }
        }

        public static VectorDocument read (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            var lines = text.replace ("\r", "").split ("\n");
            var entities = new Gee.ArrayList<Entity> ();
            bool in_entities = false;
            Entity? cur = null;
            for (int i = 0; i + 1 < lines.length; i += 2) {
                int code = int.parse (lines[i].strip ());
                string value = lines[i + 1].strip ();
                if (code == 2 && value == "ENTITIES") in_entities = true;
                if (code == 0 && value == "ENDSEC") {
                    in_entities = false;
                    cur = null;
                    continue;
                }
                if (!in_entities) continue;
                if (code == 0) {
                    cur = new Entity (value);
                    entities.add (cur);
                    continue;
                }
                if (cur != null) {
                    cur.codes.add (code);
                    cur.values.add (value);
                }
            }
            var doc = new VectorDocument ();
            doc.title = Path.get_basename (path);
            var layers = new Gee.HashMap<string, GroupNode> ();
            var nodes = new Gee.ArrayList<Node> ();
            var layer_of = new Gee.HashMap<Node, string> ();
            for (int i = 0; i < entities.size; i++) {
                var e = entities[i];
                PathData? p = null;
                switch (e.type) {
                    case "LINE":
                        p = new PathData ();
                        p.move_to (e.num (10), e.num (20));
                        p.line_to (e.num (11), e.num (21));
                        break;
                    case "CIRCLE":
                        p = new PathData.ellipse (e.num (10), e.num (20), e.num (40), e.num (40));
                        break;
                    case "ARC":
                        p = arc_path (e.num (10), e.num (20), e.num (40), e.num (50), e.num (51));
                        break;
                    case "ELLIPSE":
                        double mx = e.num (11), my = e.num (21), ratio = e.num (40, 1);
                        double r = Math.hypot (mx, my);
                        var ell = new PathData.ellipse (0, 0, r, r * ratio);
                        var m = Cairo.Matrix.identity ();
                        m.translate (e.num (10), e.num (20));
                        m.rotate (Math.atan2 (my, mx));
                        ell.transform (m);
                        p = ell;
                        break;
                    case "LWPOLYLINE":
                        var xs = e.all (10);
                        var ys = e.all (20);
                        var bulges = new double[xs.length];
                        int vi = -1;
                        for (int k = 0; k < e.codes.size; k++) {
                            if (e.codes[k] == 10) vi++;
                            if (e.codes[k] == 42 && vi >= 0 && vi < bulges.length) bulges[vi] = double.parse (e.values[k]);
                        }
                        bool closed = ((int) e.num (70)) % 2 == 1;
                        p = poly_with_bulges (xs, ys, bulges, closed);
                        break;
                    case "POLYLINE":
                        double[] xs = {}, ys = {}, bs = {};
                        bool closed = ((int) e.num (70)) % 2 == 1;
                        int j = i + 1;
                        while (j < entities.size && entities[j].type == "VERTEX") {
                            xs += entities[j].num (10);
                            ys += entities[j].num (20);
                            bs += entities[j].num (42);
                            j++;
                        }
                        p = poly_with_bulges (xs, ys, bs, closed);
                        i = j;
                        break;
                    case "SPLINE":
                        var cx = e.all (10);
                        var cy = e.all (20);
                        var fx = e.all (11);
                        var fy = e.all (21);
                        int degree = (int) e.num (71, 3);
                        Point[] pts = {};
                        if (fx.length >= 2) {
                            for (int k = 0; k < fx.length && k < fy.length; k++) pts += Point (fx[k], fy[k]);
                            p = PolyOps.catmull (pts, false);
                        } else {
                            for (int k = 0; k < cx.length && k < cy.length; k++) pts += Point (cx[k], cy[k]);
                            p = bspline (pts, degree, e.all (40));
                        }
                        break;
                    case "TEXT":
                    case "MTEXT":
                        var t = new TextNode ();
                        t.text = e.str (1).replace ("\\P", "\n");
                        t.style.size = e.num (40, 10);
                        t.matrix = Transforms.translate (e.num (10), e.num (20));
                        t.appearance.add (new PaintLayer.fill (new Paint.solid (color_of (e))));
                        nodes.add (t);
                        layer_of[t] = e.str (8, "0");
                        break;
                }
                if (p == null) continue;
                var pn = new PathNode.with_path (p);
                pn.appearance.add (new PaintLayer.line (new Paint.solid (color_of (e)), double.max (e.num (370, 25) / 100.0 * 96 / 25.4, 0.5)));
                nodes.add (pn);
                layer_of[pn] = e.str (8, "0");
            }
            var box = Rect (0, 0, -1, -1);
            bool first = true;
            foreach (var n in nodes) {
                var b = (n is TextNode) ? Rect (((TextNode) n).matrix.x0, ((TextNode) n).matrix.y0, 1, 1) : n.geometric_bounds ();
                box = first ? b : box.union (b);
                first = false;
            }
            if (first) box = Rect (0, 0, 100, 100);
            double k = text.contains ("$INSUNITS") && !text.contains ("$INSUNITS\n70\n4") && !text.contains ("$INSUNITS\r\n70\r\n4") ? 1 : 96 / 25.4;
            var flip = Cairo.Matrix (k, 0, 0, -k, -box.x * k + 20, (box.y + box.h) * k + 20);
            box = Rect (0, 0, box.w * k, box.h * k);
            foreach (var n in nodes) {
                var t = n as TextNode;
                if (t != null) {
                    double x = t.matrix.x0, y = t.matrix.y0;
                    flip.transform_point (ref x, ref y);
                    t.matrix = Transforms.translate (x, y);
                    t.style.size *= k;
                } else {
                    ((PathNode) n).path.transform (flip);
                }
                string ln = layer_of[n];
                if (!layers.has_key (ln)) {
                    var l = doc.new_layer (ln);
                    layers[ln] = l;
                    doc.layers.add (l);
                }
                layers[ln].add (n);
            }
            if (doc.layers.size == 0) doc.layers.add (doc.new_layer (_("Layer 1")));
            doc.active_layer = doc.layers[0];
            doc.add_artboard (new Artboard (_("Artboard 1"), 0, 0, box.w + 40, box.h + 40));
            doc.default_swatches ();
            doc.default_brushes ();
            doc.relink ();
            doc.ensure_ids ();
            doc.modified = false;
            return doc;
        }

        private static Ink color_of (Entity e) {
            if (e.codes.contains (420)) {
                int v = (int) e.num (420);
                return new Ink.rgb (((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0);
            }
            int aci = (int) e.num (62, 7);
            switch (aci) {
                case 1: return Ink.hex ("#ff0000");
                case 2: return Ink.hex ("#ffff00");
                case 3: return Ink.hex ("#00ff00");
                case 4: return Ink.hex ("#00ffff");
                case 5: return Ink.hex ("#0000ff");
                case 6: return Ink.hex ("#ff00ff");
                case 8: return Ink.hex ("#808080");
                case 9: return Ink.hex ("#c0c0c0");
                default: return Ink.hex ("#000000");
            }
        }

        private static PathData arc_path (double cx, double cy, double r, double a1, double a2) {
            var p = new PathData ();
            double s = a1 * Math.PI / 180, e = a2 * Math.PI / 180;
            while (e <= s) e += 2 * Math.PI;
            var from = Point (cx + r * Math.cos (s), cy + r * Math.sin (s));
            var to = Point (cx + r * Math.cos (e), cy + r * Math.sin (e));
            p.move_to (from.x, from.y);
            PathOps.arc (p, Point (cx, cy), from, to, e - s);
            return p;
        }

        private static PathData poly_with_bulges (double[] xs, double[] ys, double[] bulges, bool closed) {
            var p = new PathData ();
            int n = int.min (xs.length, ys.length);
            if (n == 0) return p;
            p.move_to (xs[0], ys[0]);
            int count = closed ? n : n - 1;
            for (int i = 0; i < count; i++) {
                int j = (i + 1) % n;
                double b = i < bulges.length ? bulges[i] : 0;
                if (b.abs () < 1e-9) {
                    p.line_to (xs[j], ys[j]);
                    continue;
                }
                var a = Point (xs[i], ys[i]);
                var c = Point (xs[j], ys[j]);
                double theta = 4 * Math.atan (b);
                double chord = a.distance (c);
                double r = chord / (2 * Math.sin (theta / 2));
                var mid = PathOps.mix (a, c, 0.5);
                double h = Math.sqrt (double.max (r * r - chord * chord / 4, 0));
                double nx = -(c.y - a.y) / chord, ny = (c.x - a.x) / chord;
                double sign = (b > 0) == (theta.abs () < Math.PI) ? 1 : -1;
                var center = Point (mid.x + nx * h * sign, mid.y + ny * h * sign);
                PathOps.arc (p, center, a, c, theta);
            }
            if (closed) p.close ();
            return p;
        }

        private static PathData bspline (Point[] ctrl, int degree, double[] knots_in) {
            double[] knots = knots_in;
            var p = new PathData ();
            int n = ctrl.length;
            if (n < 2) return p;
            if (knots.length != n + degree + 1) {
                knots = new double[n + degree + 1];
                for (int i = 0; i < knots.length; i++) knots[i] = i <= degree ? 0 : (i >= n ? 1 : (i - degree) / (double) (n - degree));
            }
            double t0 = knots[degree], t1 = knots[n];
            int samples = int.max (16, n * 12);
            for (int s = 0; s <= samples; s++) {
                double t = t0 + (t1 - t0) * s / samples;
                if (s == samples) t = t1 - 1e-9;
                var pt = de_boor (ctrl, degree, knots, t);
                if (s == 0) p.move_to (pt.x, pt.y);
                else p.line_to (pt.x, pt.y);
            }
            return PathSimplify.simplify (p, 0.05, 30);
        }

        private static Point de_boor (Point[] c, int k, double[] t, double x) {
            int s = k;
            while (s < c.length - 1 && !(x >= t[s] && x < t[s + 1])) s++;
            Point[] d = new Point[k + 1];
            for (int j = 0; j <= k; j++) d[j] = c[(j + s - k).clamp (0, c.length - 1)];
            for (int r = 1; r <= k; r++) {
                for (int j = k; j >= r; j--) {
                    int i = j + s - k;
                    double den = t[i + k - r + 1] - t[i];
                    double a = den.abs () < 1e-12 ? 0 : (x - t[i]) / den;
                    d[j] = Point ((1 - a) * d[j - 1].x + a * d[j].x, (1 - a) * d[j - 1].y + a * d[j].y);
                }
            }
            return d[k];
        }

        public static void write (VectorDocument doc, string path, Rect area) throws Error {
            var b = new StringBuilder ();
            b.append ("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n");
            b.append ("0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n");
            foreach (var l in doc.layers) b.append ("0\nLAYER\n2\n%s\n70\n0\n62\n7\n6\nCONTINUOUS\n".printf (clean (l.name)));
            b.append ("0\nENDTAB\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n");
            double mm = 25.4 / 96;
            foreach (var l in doc.layers) {
                if (l.hidden) continue;
                l.walk ((n) => {
                    if (n.hidden) return false;
                    var g = n as GroupNode;
                    if (g != null && g.generated (doc) != null) {
                        foreach (var c in g.generated (doc).children) entity (b, c, l.name, area, mm);
                        return false;
                    }
                    if (g == null) entity (b, n, l.name, area, mm);
                    return true;
                });
            }
            b.append ("0\nENDSEC\n0\nEOF\n");
            FileUtils.set_contents (path, b.str);
        }

        private static string clean (string s) {
            return s.replace ("\n", " ").replace (" ", "_");
        }

        private static string num (double v) {
            return PathData.fmt (v, 4);
        }

        private static void entity (StringBuilder b, Node n, string layer, Rect area, double mm) {
            var outline = n.outline ();
            if (outline == null) return;
            var s = n.first_stroke ();
            var f = n.first_fill ();
            var ink = s != null && s.paint.visible () ? s.paint.representative () : (f != null ? f.paint.representative () : new Ink ());
            int rgb = ((int) (ink.r * 255) << 16) | ((int) (ink.g * 255) << 8) | (int) (ink.b * 255);
            var pn = n as PathNode;
            if (pn != null && pn.live != null && pn.live.kind == "ellipse" && (pn.live.w - pn.live.h).abs () < 1e-6) {
                b.append ("0\nCIRCLE\n8\n%s\n420\n%d\n10\n%s\n20\n%s\n30\n0\n40\n%s\n".printf (clean (layer), rgb, num ((pn.live.cx - area.x) * mm), num ((area.y + area.h - pn.live.cy) * mm), num (pn.live.w / 2 * mm)));
                return;
            }
            foreach (var poly in outline.flatten (0.1)) {
                if (poly.pts.length < 2) continue;
                if (poly.pts.length == 2) {
                    b.append ("0\nLINE\n8\n%s\n420\n%d\n10\n%s\n20\n%s\n30\n0\n11\n%s\n21\n%s\n31\n0\n".printf (clean (layer), rgb, num ((poly.pts[0].x - area.x) * mm), num ((area.y + area.h - poly.pts[0].y) * mm), num ((poly.pts[1].x - area.x) * mm), num ((area.y + area.h - poly.pts[1].y) * mm)));
                    continue;
                }
                b.append ("0\nLWPOLYLINE\n8\n%s\n420\n%d\n90\n%d\n70\n%d\n".printf (clean (layer), rgb, poly.pts.length, poly.closed ? 1 : 0));
                foreach (var p in poly.pts) b.append ("10\n%s\n20\n%s\n".printf (num ((p.x - area.x) * mm), num ((area.y + area.h - p.y) * mm)));
            }
        }
    }
}
