using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class ChartNode : GroupNode {
        public string chart = "bar";
        public double x = 0;
        public double y = 0;
        public double w = 360;
        public double h = 240;
        public Gee.ArrayList<string> rows = new Gee.ArrayList<string> ();
        public bool legend = true;
        public string[] palette = { "#1d71b8", "#f39200", "#3aaa35", "#e5322d", "#951b81", "#009fa0", "#8b5a2b" };

        public ChartNode () {
            rows.add ("\t" + _("Series A") + "\t" + _("Series B"));
            rows.add ("2024\t12\t8");
            rows.add ("2025\t18\t11");
            rows.add ("2026\t24\t15");
        }

        public override string kind_name () {
            return "chart";
        }

        public override string kind_label () {
            return _("Graph");
        }

        public override Node make_empty () {
            return new ChartNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (ChartNode) target;
            t.chart = chart;
            t.x = x;
            t.y = y;
            t.w = w;
            t.h = h;
            t.rows.clear ();
            t.rows.add_all (rows);
            t.legend = legend;
            t.palette = palette;
        }

        public void write_json (Json.Object o) {
            o.set_string_member ("chart", chart);
            var r = new Json.Array ();
            foreach (var row in rows) r.add_string_element (row);
            o.set_array_member ("rows", r);
            var v = new Json.Array ();
            foreach (double d in new double[] { x, y, w, h, legend ? 1 : 0 }) v.add_double_element (d);
            o.set_array_member ("box", v);
            var p = new Json.Array ();
            foreach (var c in palette) p.add_string_element (c);
            o.set_array_member ("palette", p);
        }

        public void read_json (Json.Object o) {
            if (o.has_member ("chart")) chart = o.get_string_member ("chart");
            if (o.has_member ("rows")) {
                rows.clear ();
                foreach (var e in o.get_array_member ("rows").get_elements ()) rows.add (e.get_string ());
            }
            if (o.has_member ("box")) {
                var a = o.get_array_member ("box");
                if (a.get_length () >= 5) {
                    x = a.get_double_element (0);
                    y = a.get_double_element (1);
                    w = a.get_double_element (2);
                    h = a.get_double_element (3);
                    legend = a.get_double_element (4) != 0;
                }
            }
            if (o.has_member ("palette")) {
                string[] p = {};
                foreach (var e in o.get_array_member ("palette").get_elements ()) p += e.get_string ();
                if (p.length > 0) palette = p;
            }
        }

        public string[] series () {
            if (rows.size == 0) return {};
            var head = rows[0].split ("\t");
            return head.length > 1 ? head[1:head.length] : new string[0];
        }

        public string[] categories () {
            string[] c = {};
            for (int i = 1; i < rows.size; i++) c += rows[i].split ("\t")[0];
            return c;
        }

        public double value (int row, int series) {
            if (row + 1 >= rows.size) return 0;
            var cells = rows[row + 1].split ("\t");
            if (series + 1 >= cells.length) return 0;
            return double.parse (cells[series + 1].strip ().replace (",", "."));
        }

        public override Rect geometric_bounds () {
            return Rect (x, y, w, h);
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            var r = Transforms.rect_bounds (Rect (x, y, w, h), m);
            x = r.x;
            y = r.y;
            w = double.max (r.w, 10);
            h = double.max (r.h, 10);
        }

        private PathNode box_node (Rect r, string color) {
            var p = new PathNode.with_path (new PathData.rect (r.x, r.y, r.w, r.h));
            p.appearance.add (new PaintLayer.fill (new Paint.hex (color)));
            return p;
        }

        private PathNode line_node (PathData path, string color, double width) {
            var p = new PathNode.with_path (path);
            p.appearance.add (new PaintLayer.line (new Paint.hex (color), width));
            return p;
        }

        private TextNode label (string text, double lx, double ly, double size, string align = "left") {
            var t = new TextNode ();
            t.text = text;
            t.style.size = size;
            t.para.align = align;
            t.matrix = Transforms.translate (lx, ly);
            t.appearance.add (new PaintLayer.fill (new Paint.hex ("#333333")));
            return t;
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var g = new GroupNode ();
            var ser = series ();
            var cats = categories ();
            int ns = ser.length, nc = cats.length;
            double legend_w = legend && ns > 0 ? 110 : 0;
            var plot = Rect (x + 36, y + 10, w - 46 - legend_w, h - 36);
            if (plot.w < 20 || plot.h < 20 || nc == 0 || ns == 0) return g;
            if (chart == "pie") {
                double total = 0;
                for (int r = 0; r < nc; r++) total += double.max (0, value (r, 0));
                double cx = plot.cx (), cy = plot.cy (), rad = double.min (plot.w, plot.h) / 2;
                double a = -Math.PI / 2;
                for (int r = 0; r < nc; r++) {
                    double v = double.max (0, value (r, 0));
                    if (total <= 0) break;
                    double sweep = v / total * 2 * Math.PI;
                    var p = new PathData ();
                    p.move_to (cx, cy);
                    p.line_to (cx + rad * Math.cos (a), cy + rad * Math.sin (a));
                    PathOps.arc (p, Point (cx, cy), Point (cx + rad * Math.cos (a), cy + rad * Math.sin (a)), Point (cx + rad * Math.cos (a + sweep), cy + rad * Math.sin (a + sweep)), sweep);
                    p.close ();
                    var slice = new PathNode.with_path (p);
                    slice.appearance.add (new PaintLayer.fill (new Paint.hex (palette[r % palette.length])));
                    slice.appearance.add (new PaintLayer.line (new Paint.hex ("#ffffff"), 1.5));
                    g.add (slice);
                    a += sweep;
                }
                if (legend) for (int r = 0; r < nc; r++) {
                    g.add (box_node (Rect (x + w - legend_w + 8, y + 12 + r * 20, 12, 12), palette[r % palette.length]));
                    g.add (label (cats[r], x + w - legend_w + 26, y + 22 + r * 20, 11));
                }
                return g;
            }
            double maxv = 0, minv = 0;
            for (int r = 0; r < nc; r++) {
                double stack = 0;
                for (int s = 0; s < ns; s++) {
                    double v = value (r, s);
                    if (chart == "stacked") stack += v;
                    else maxv = double.max (maxv, v);
                    minv = double.min (minv, v);
                }
                if (chart == "stacked") maxv = double.max (maxv, stack);
            }
            if (maxv - minv <= 0) maxv = minv + 1;
            double step = nice_step ((maxv - minv) / 5);
            double top = Math.ceil (maxv / step) * step;
            double bottom = Math.floor (minv / step) * step;
            for (double v = bottom; v <= top + step * 0.01; v += step) {
                double yy = plot.y + plot.h - (v - bottom) / (top - bottom) * plot.h;
                var gl = new PathData ();
                gl.move_to (plot.x, yy);
                gl.line_to (plot.x + plot.w, yy);
                g.add (line_node (gl, "#d0d0d0", 0.75));
                g.add (label (fmt (v), x, yy + 4, 10));
            }
            var axis = new PathData ();
            axis.move_to (plot.x, plot.y);
            axis.line_to (plot.x, plot.y + plot.h);
            axis.line_to (plot.x + plot.w, plot.y + plot.h);
            g.add (line_node (axis, "#555555", 1));
            double band = plot.w / nc;
            for (int r = 0; r < nc; r++) {
                g.add (label (cats[r], plot.x + band * r + band / 2 - cats[r].length * 3, plot.y + plot.h + 16, 10));
            }
            double zero = plot.y + plot.h - (0 - bottom) / (top - bottom) * plot.h;
            if (chart == "line" || chart == "area" || chart == "scatter") {
                for (int s = 0; s < ns; s++) {
                    var p = new PathData ();
                    for (int r = 0; r < nc; r++) {
                        double px = plot.x + band * r + band / 2;
                        double py = plot.y + plot.h - (value (r, s) - bottom) / (top - bottom) * plot.h;
                        if (r == 0) p.move_to (px, py);
                        else p.line_to (px, py);
                        if (chart != "area") {
                            var dot = new PathNode.with_path (new PathData.ellipse (px, py, 3.5, 3.5));
                            dot.appearance.add (new PaintLayer.fill (new Paint.hex (palette[s % palette.length])));
                            g.add (dot);
                        }
                    }
                    if (chart == "area") {
                        p.line_to (plot.x + band * (nc - 1) + band / 2, zero);
                        p.line_to (plot.x + band / 2, zero);
                        p.close ();
                        var area = new PathNode.with_path (p);
                        var fl = new PaintLayer.fill (new Paint.hex (palette[s % palette.length]));
                        fl.opacity = 0.6;
                        area.appearance.add (fl);
                        g.add (area);
                    } else if (chart == "line") {
                        g.add (line_node (p, palette[s % palette.length], 2));
                    }
                }
            } else {
                for (int r = 0; r < nc; r++) {
                    double stack = 0;
                    for (int s = 0; s < ns; s++) {
                        double v = value (r, s);
                        Rect bar;
                        if (chart == "stacked") {
                            double y0 = plot.y + plot.h - (stack - bottom) / (top - bottom) * plot.h;
                            double y1 = plot.y + plot.h - (stack + v - bottom) / (top - bottom) * plot.h;
                            bar = Rect (plot.x + band * r + band * 0.2, y1, band * 0.6, y0 - y1);
                            stack += v;
                        } else {
                            double bw = band * 0.7 / ns;
                            double yv = plot.y + plot.h - (v - bottom) / (top - bottom) * plot.h;
                            bar = Rect (plot.x + band * r + band * 0.15 + bw * s, double.min (yv, zero), bw, (zero - yv).abs ());
                        }
                        g.add (box_node (bar, palette[s % palette.length]));
                    }
                }
            }
            if (legend) for (int s = 0; s < ns; s++) {
                g.add (box_node (Rect (x + w - legend_w + 8, y + 12 + s * 20, 12, 12), palette[s % palette.length]));
                g.add (label (ser[s], x + w - legend_w + 26, y + 22 + s * 20, 11));
            }
            return g;
        }

        private static double nice_step (double raw) {
            if (raw <= 0) return 1;
            double mag = Math.pow (10, Math.floor (Math.log10 (raw)));
            double f = raw / mag;
            if (f < 1.5) return mag;
            if (f < 3) return 2 * mag;
            if (f < 7) return 5 * mag;
            return 10 * mag;
        }

        private static string fmt (double v) {
            if ((v - Math.round (v)).abs () < 1e-9) return "%.0f".printf (v);
            return "%.1f".printf (v);
        }
    }

    public class Shape3DNode : GroupNode {
        public string mode = "extrude";
        public PathData profile = new PathData ();
        public double depth = 50;
        public double rx = -18;
        public double ry = -26;
        public double rz = 8;
        public double perspective = 0;
        public double light = 0.75;
        public int segments = 32;
        public double revolve_angle = 360;

        public override string kind_name () {
            return "shape3d";
        }

        public override string kind_label () {
            return mode == "revolve" ? _("3D Revolve") : _("3D Extrude");
        }

        public override Node make_empty () {
            return new Shape3DNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (Shape3DNode) target;
            t.mode = mode;
            t.profile = profile.copy ();
            t.depth = depth;
            t.rx = rx;
            t.ry = ry;
            t.rz = rz;
            t.perspective = perspective;
            t.light = light;
            t.segments = segments;
            t.revolve_angle = revolve_angle;
        }

        public void write_json (Json.Object o) {
            o.set_string_member ("mode", mode);
            o.set_string_member ("profile", profile.to_svg (4));
            var v = new Json.Array ();
            foreach (double d in new double[] { depth, rx, ry, rz, perspective, light, segments, revolve_angle }) v.add_double_element (d);
            o.set_array_member ("v", v);
        }

        public void read_json (Json.Object o) {
            if (o.has_member ("mode")) mode = o.get_string_member ("mode");
            if (o.has_member ("profile")) profile = PathData.parse_svg (o.get_string_member ("profile"));
            if (o.has_member ("v")) {
                var a = o.get_array_member ("v");
                if (a.get_length () >= 8) {
                    depth = a.get_double_element (0);
                    rx = a.get_double_element (1);
                    ry = a.get_double_element (2);
                    rz = a.get_double_element (3);
                    perspective = a.get_double_element (4);
                    light = a.get_double_element (5);
                    segments = (int) a.get_double_element (6);
                    revolve_angle = a.get_double_element (7);
                }
            }
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            profile.transform (m);
            Transforms.after_transform (this, Rect (0, 0, -1, -1), m, scale_strokes, false);
        }

        public override Rect geometric_bounds () {
            var g = generated (null);
            return g.geometric_bounds ();
        }

        private struct V3 {
            double x;
            double y;
            double z;
        }

        private V3 rotate (V3 p) {
            double ax = rx * Math.PI / 180, ay = ry * Math.PI / 180, az = rz * Math.PI / 180;
            double y1 = p.y * Math.cos (ax) - p.z * Math.sin (ax);
            double z1 = p.y * Math.sin (ax) + p.z * Math.cos (ax);
            double x2 = p.x * Math.cos (ay) + z1 * Math.sin (ay);
            double z2 = -p.x * Math.sin (ay) + z1 * Math.cos (ay);
            double x3 = x2 * Math.cos (az) - y1 * Math.sin (az);
            double y3 = x2 * Math.sin (az) + y1 * Math.cos (az);
            return { x3, y3, z2 };
        }

        private Point project (V3 p, Point center, double focal) {
            if (focal <= 0) return Point (center.x + p.x, center.y + p.y);
            double s = focal / (focal + p.z);
            return Point (center.x + p.x * s, center.y + p.y * s);
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var g = new GroupNode ();
            var box = profile.bounds ();
            var center = Point (box.cx (), box.cy ());
            Ink base_color = new Ink.rgb (0.6, 0.6, 0.65);
            var f = first_fill ();
            if (f != null && f.paint.visible ()) base_color = f.paint.representative ();
            double focal = perspective > 0 ? 1000 / Math.tan (perspective * Math.PI / 360) : 0;
            var faces = new Gee.ArrayList<Gee.ArrayList<V3?>> ();
            foreach (var poly in profile.flatten (1.0)) {
                var pts = poly.pts;
                if (pts.length < 2) continue;
                if (mode == "revolve") {
                    int n = segments.clamp (6, 96);
                    double sweep = revolve_angle * Math.PI / 180;
                    for (int s = 0; s < n; s++) {
                        double a0 = sweep * s / n, a1 = sweep * (s + 1) / n;
                        for (int i = 0; i + 1 < pts.length; i++) {
                            double r0 = pts[i].x - box.x, r1 = pts[i + 1].x - box.x;
                            var q = new Gee.ArrayList<V3?> ();
                            q.add (V3 () { x = r0 * Math.cos (a0), y = pts[i].y - center.y, z = r0 * Math.sin (a0) });
                            q.add (V3 () { x = r1 * Math.cos (a0), y = pts[i + 1].y - center.y, z = r1 * Math.sin (a0) });
                            q.add (V3 () { x = r1 * Math.cos (a1), y = pts[i + 1].y - center.y, z = r1 * Math.sin (a1) });
                            q.add (V3 () { x = r0 * Math.cos (a1), y = pts[i].y - center.y, z = r0 * Math.sin (a1) });
                            faces.add (q);
                        }
                    }
                } else {
                    double hz = depth / 2;
                    var front = new Gee.ArrayList<V3?> ();
                    var back = new Gee.ArrayList<V3?> ();
                    foreach (var p in pts) {
                        front.add (V3 () { x = p.x - center.x, y = p.y - center.y, z = -hz });
                        back.add (V3 () { x = p.x - center.x, y = p.y - center.y, z = hz });
                    }
                    faces.add (front);
                    faces.add (back);
                    int m = pts.length;
                    int count = poly.closed ? m : m - 1;
                    for (int i = 0; i < count; i++) {
                        var a = pts[i];
                        var b = pts[(i + 1) % m];
                        var q = new Gee.ArrayList<V3?> ();
                        q.add (V3 () { x = a.x - center.x, y = a.y - center.y, z = -hz });
                        q.add (V3 () { x = b.x - center.x, y = b.y - center.y, z = -hz });
                        q.add (V3 () { x = b.x - center.x, y = b.y - center.y, z = hz });
                        q.add (V3 () { x = a.x - center.x, y = a.y - center.y, z = hz });
                        faces.add (q);
                    }
                }
            }
            var shaded = new Gee.ArrayList<PathNode> ();
            var depths = new Gee.ArrayList<double?> ();
            foreach (var face in faces) {
                var rot = new Gee.ArrayList<V3?> ();
                double zsum = 0;
                foreach (var p in face) {
                    var r = rotate (p);
                    rot.add (r);
                    zsum += r.z;
                }
                if (rot.size < 3) continue;
                var a = rot[0];
                var b = rot[1];
                var c = rot[rot.size - 1];
                double ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
                double vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
                double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
                double nl = Math.sqrt (nx * nx + ny * ny + nz * nz);
                if (nl < 1e-9) continue;
                nx /= nl;
                ny /= nl;
                nz /= nl;
                double lx = -0.4, ly = -0.6, lz = -0.7;
                double ll = Math.sqrt (lx * lx + ly * ly + lz * lz);
                double diffuse = (nx * lx + ny * ly + nz * lz).abs () / ll;
                double shade = (1 - light) * 0.35 + light * diffuse + 0.15;
                var path = new PathData ();
                for (int i = 0; i < rot.size; i++) {
                    var p = project (rot[i], center, focal);
                    if (i == 0) path.move_to (p.x, p.y);
                    else path.line_to (p.x, p.y);
                }
                path.close ();
                var node = new PathNode.with_path (path);
                var color = new Ink.rgb (base_color.r * shade, base_color.g * shade, base_color.b * shade);
                node.appearance.add (new PaintLayer.fill (new Paint.solid (color)));
                var edge = new PaintLayer.line (new Paint.solid (color), 0.5);
                node.appearance.add (edge);
                shaded.add (node);
                depths.add (zsum / rot.size);
            }
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < shaded.size; i++) order.add (i);
            order.sort ((i, j) => depths[i] > depths[j] ? -1 : depths[i] < depths[j] ? 1 : 0);
            foreach (int i in order) g.add (shaded[i]);
            return g;
        }
    }
}
