using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class BlendNode : GroupNode {
        public string spacing = "steps";
        public int steps = 5;
        public double distance = 20;
        public PathData? spine = null;
        public bool align_spine = false;

        public override string kind_name () {
            return "blend";
        }

        public override string kind_label () {
            return _("Blend");
        }

        public override Node make_empty () {
            return new BlendNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (BlendNode) target;
            t.spacing = spacing;
            t.steps = steps;
            t.distance = distance;
            t.spine = spine != null ? spine.copy () : null;
            t.align_spine = align_spine;
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            base.apply_transform (m, scale_strokes);
            if (spine != null) spine.transform (m);
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var g = new GroupNode ();
            var keys = new Gee.ArrayList<Node> ();
            foreach (var c in children) if (!c.hidden) keys.add (c);
            if (keys.size < 2) {
                foreach (var k in keys) g.add (k.clone ());
                return g;
            }
            var centers = new Gee.ArrayList<Point?> ();
            foreach (var k in keys) {
                var b = k.geometric_bounds ();
                centers.add (Point (b.cx (), b.cy ()));
            }
            double spine_len = spine != null ? PathOps.length (spine) : 0;
            double total_straight = 0;
            for (int i = 0; i + 1 < keys.size; i++) total_straight += centers[i].distance (centers[i + 1]);
            double travelled = 0;
            for (int i = 0; i + 1 < keys.size; i++) {
                var a = keys[i];
                var b = keys[i + 1];
                int n = count_for (a, b, centers[i].distance (centers[i + 1]));
                if (i == 0) g.add (place (a.clone (), centers[i], 0, spine_len, total_straight));
                double seg = centers[i].distance (centers[i + 1]);
                for (int s = 1; s <= n; s++) {
                    double t = s / (double) (n + 1);
                    var mid = Interpolate.nodes (a, b, t);
                    var c = PathOps.mix (centers[i], centers[i + 1], t);
                    g.add (place (mid, c, travelled + seg * t, spine_len, total_straight));
                }
                travelled += seg;
                g.add (place (b.clone (), centers[i + 1], travelled, spine_len, total_straight));
            }
            return g;
        }

        private Node place (Node n, Point center, double along, double spine_len, double total) {
            if (spine == null || spine_len <= 0 || total <= 0) return n;
            Point p;
            double angle;
            PathOps.point_at (spine, along / total * spine_len, out p, out angle);
            var m = Transforms.translate (p.x - center.x, p.y - center.y);
            if (align_spine) m = Transforms.multiply (m, Transforms.rotate (angle, p));
            n.apply_transform (m, false);
            return n;
        }

        private int count_for (Node a, Node b, double dist) {
            if (spacing == "distance") return int.max (0, (int) (dist / double.max (distance, 0.5)) - 1);
            if (spacing == "smooth") {
                var fa = a.first_fill ();
                var fb = b.first_fill ();
                if (fa == null || fb == null) return 10;
                var ca = fa.paint.representative ();
                var cb = fb.paint.representative ();
                double d = double.max ((ca.r - cb.r).abs (), double.max ((ca.g - cb.g).abs (), (ca.b - cb.b).abs ()));
                return ((int) (d * 255 / 4)).clamp (4, 256);
            }
            return steps.clamp (1, 1000);
        }
    }

    public class Interpolate {
        public static Ink ink (Ink a, Ink b, double t) {
            var r = new Ink.rgb (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t);
            if (a.has_cmyk && b.has_cmyk) {
                r.has_cmyk = true;
                r.c = a.c + (b.c - a.c) * t;
                r.m = a.m + (b.m - a.m) * t;
                r.y = a.y + (b.y - a.y) * t;
                r.k = a.k + (b.k - a.k) * t;
            }
            return r;
        }

        public static Paint paint (Paint a, Paint b, double t) {
            if (a.kind == PaintKind.NONE && b.kind == PaintKind.NONE) return new Paint ();
            if (a.kind == PaintKind.SOLID && b.kind == PaintKind.SOLID) return new Paint.solid (ink (a.color, b.color, t));
            if ((a.kind == PaintKind.LINEAR || a.kind == PaintKind.RADIAL) && a.kind == b.kind && a.gradient.stops.size == b.gradient.stops.size) {
                var p = a.copy ();
                for (int i = 0; i < p.gradient.stops.size; i++) {
                    var sa = a.gradient.stops[i];
                    var sb = b.gradient.stops[i];
                    p.gradient.stops[i].color = ink (sa.color, sb.color, t);
                    p.gradient.stops[i].offset = sa.offset + (sb.offset - sa.offset) * t;
                    p.gradient.stops[i].opacity = sa.opacity + (sb.opacity - sa.opacity) * t;
                }
                return p;
            }
            if (a.kind == PaintKind.NONE) return t < 0.5 ? new Paint () : b.copy ();
            if (b.kind == PaintKind.NONE) return t < 0.5 ? a.copy () : new Paint ();
            return new Paint.solid (ink (a.representative (), b.representative (), t));
        }

        public static Node nodes (Node a, Node b, double t) {
            var pa = a as PathNode;
            var pb = b as PathNode;
            Node result;
            if (pa != null && pb != null) {
                var r = new PathNode ();
                r.path = paths (pa.render_path (), pb.render_path (), t);
                r.even_odd = pa.even_odd;
                result = r;
            } else {
                result = (t < 0.5 ? a : b).clone ();
                var ba = a.geometric_bounds ();
                var bb = b.geometric_bounds ();
                var own = result.geometric_bounds ();
                double cx = ba.cx () + (bb.cx () - ba.cx ()) * t, cy = ba.cy () + (bb.cy () - ba.cy ()) * t;
                result.apply_transform (Transforms.translate (cx - own.cx (), cy - own.cy ()), false);
            }
            result.id = "";
            result.opacity = a.opacity + (b.opacity - a.opacity) * t;
            result.blend = a.blend;
            result.appearance.clear ();
            int n = int.max (a.appearance.size, b.appearance.size);
            for (int i = 0; i < n; i++) {
                var la = i < a.appearance.size ? a.appearance[i] : null;
                var lb = i < b.appearance.size ? b.appearance[i] : null;
                if (la == null) la = lb.copy ();
                if (lb == null) lb = la.copy ();
                var l = la.copy ();
                l.paint = paint (la.paint, lb.paint, t);
                l.width = la.width + (lb.width - la.width) * t;
                l.opacity = la.opacity + (lb.opacity - la.opacity) * t;
                result.appearance.add (l);
            }
            return result;
        }

        private static Gee.ArrayList<Bezier?> cubics (PathData contour) {
            var list = new Gee.ArrayList<Bezier?> ();
            foreach (var e in PathOps.edges (contour, false)) {
                if (e.is_curve ()) list.add (Bezier (e.start, Point (e.segment.x1, e.segment.y1), Point (e.segment.x2, e.segment.y2), e.end ()));
                else list.add (Bezier.line (e.start, e.end ()));
            }
            return list;
        }

        private static void equalize (Gee.ArrayList<Bezier?> list, int count) {
            while (list.size < count && list.size > 0) {
                int longest = 0;
                double best = -1;
                for (int i = 0; i < list.size; i++) {
                    double l = list[i].length (0.5);
                    if (l > best) {
                        best = l;
                        longest = i;
                    }
                }
                Bezier left, right;
                list[longest].split (0.5, out left, out right);
                list[longest] = left;
                list.insert (longest + 1, right);
            }
        }

        public static PathData paths (PathData a, PathData b, double t) {
            var ca = PathOps.contours (a);
            var cb = PathOps.contours (b);
            var result = new PathData ();
            int n = int.max (ca.size, cb.size);
            for (int i = 0; i < n; i++) {
                var x = i < ca.size ? ca[i] : ca[ca.size - 1];
                var y = i < cb.size ? cb[i] : cb[cb.size - 1];
                bool closed = PathOps.contour_closed (x) && PathOps.contour_closed (y);
                if ((PathOps.signed_area (x) > 0) != (PathOps.signed_area (y) > 0) && closed) y = PathOps.reversed (y);
                var lx = cubics (x);
                var ly = cubics (y);
                if (lx.size == 0 || ly.size == 0) continue;
                int count = int.max (lx.size, ly.size);
                equalize (lx, count);
                equalize (ly, count);
                if (closed) {
                    int shift = 0;
                    double best = double.INFINITY;
                    for (int s = 0; s < count; s++) {
                        double d = 0;
                        for (int k = 0; k < count; k++) d += lx[k].p0.distance (ly[(k + s) % count].p0);
                        if (d < best) {
                            best = d;
                            shift = s;
                        }
                    }
                    var rot = new Gee.ArrayList<Bezier?> ();
                    for (int k = 0; k < count; k++) rot.add (ly[(k + shift) % count]);
                    ly = rot;
                }
                var first = PathOps.mix (lx[0].p0, ly[0].p0, t);
                result.move_to (first.x, first.y);
                for (int k = 0; k < count; k++) {
                    var c1 = PathOps.mix (lx[k].p1, ly[k].p1, t);
                    var c2 = PathOps.mix (lx[k].p2, ly[k].p2, t);
                    var e = PathOps.mix (lx[k].p3, ly[k].p3, t);
                    result.curve_to (c1.x, c1.y, c2.x, c2.y, e.x, e.y);
                }
                if (closed) result.close ();
            }
            return result;
        }
    }

    public class RepeatNode : GroupNode {
        public string mode = "radial";
        public int count = 8;
        public double radius = 120;
        public double start_angle = 0;
        public int rows = 3;
        public int cols = 3;
        public double hspace = 10;
        public double vspace = 10;
        public double axis_angle = 90;
        public double axis_offset = 20;

        public override string kind_name () {
            return "repeat";
        }

        public override string kind_label () {
            switch (mode) {
                case "grid": return _("Grid Repeat");
                case "mirror": return _("Mirror Repeat");
                default: return _("Radial Repeat");
            }
        }

        public override Node make_empty () {
            return new RepeatNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (RepeatNode) target;
            t.mode = mode;
            t.count = count;
            t.radius = radius;
            t.start_angle = start_angle;
            t.rows = rows;
            t.cols = cols;
            t.hspace = hspace;
            t.vspace = vspace;
            t.axis_angle = axis_angle;
            t.axis_offset = axis_offset;
        }

        private Rect source_bounds () {
            var box = Rect.empty ();
            bool first = true;
            foreach (var c in children) {
                var b = c.geometric_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            return box;
        }

        public override Rect geometric_bounds () {
            var gen = generated (null);
            return gen.geometric_bounds ();
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var g = new GroupNode ();
            var box = source_bounds ();
            switch (mode) {
                case "grid":
                    for (int r = 0; r < rows; r++) {
                        for (int c = 0; c < cols; c++) {
                            var m = Transforms.translate (c * (box.w + hspace), r * (box.h + vspace));
                            foreach (var child in children) {
                                var copy = child.clone ();
                                copy.apply_transform (m, false);
                                g.add (copy);
                            }
                        }
                    }
                    break;
                case "mirror":
                    foreach (var child in children) g.add (child.clone ());
                    var origin = Point (box.x + box.w + axis_offset, box.cy ());
                    var m = Transforms.reflect (axis_angle, origin);
                    foreach (var child in children) {
                        var copy = child.clone ();
                        copy.apply_transform (m, false);
                        g.add (copy);
                    }
                    break;
                default:
                    var center = Point (box.cx (), box.cy () + radius);
                    int n = count.clamp (1, 360);
                    for (int i = 0; i < n; i++) {
                        var m = Transforms.rotate (start_angle * Math.PI / 180 + i * 2 * Math.PI / n, center);
                        foreach (var child in children) {
                            var copy = child.clone ();
                            copy.apply_transform (m, false);
                            g.add (copy);
                        }
                    }
                    break;
            }
            return g;
        }
    }

    public class EnvelopeNode : GroupNode {
        public string mode = "warp";
        public string style = "arc";
        public double bend = 0.5;
        public double hdist = 0;
        public double vdist = 0;
        public bool vertical = false;
        public int mesh_rows = 2;
        public int mesh_cols = 2;
        public Point[] grid = {};
        public Point[] quad = {};

        public override string kind_name () {
            return "envelope";
        }

        public override string kind_label () {
            return _("Envelope");
        }

        public override Node make_empty () {
            return new EnvelopeNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (EnvelopeNode) target;
            t.mode = mode;
            t.style = style;
            t.bend = bend;
            t.hdist = hdist;
            t.vdist = vdist;
            t.vertical = vertical;
            t.mesh_rows = mesh_rows;
            t.mesh_cols = mesh_cols;
            t.grid = grid;
            t.quad = quad;
        }

        public Rect source_bounds () {
            var box = Rect.empty ();
            bool first = true;
            foreach (var c in children) {
                var b = c.geometric_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            return box;
        }

        public void init_mesh (int rows, int cols) {
            var box = source_bounds ();
            mesh_rows = rows;
            mesh_cols = cols;
            Point[] g = {};
            for (int r = 0; r <= rows; r++) for (int c = 0; c <= cols; c++) g += Point (box.x + box.w * c / cols, box.y + box.h * r / rows);
            grid = g;
        }

        public void init_quad () {
            var b = source_bounds ();
            quad = { Point (b.x, b.y), Point (b.x + b.w, b.y), Point (b.x + b.w, b.y + b.h), Point (b.x, b.y + b.h) };
        }

        public Point map (Point p, Rect box) {
            switch (mode) {
                case "mesh":
                    return Warp.mesh (grid, mesh_rows, mesh_cols, box, p);
                case "distort":
                    if (quad.length != 4) return p;
                    Point[] src = { Point (box.x, box.y), Point (box.x + box.w, box.y), Point (box.x + box.w, box.y + box.h), Point (box.x, box.y + box.h) };
                    return Warp.project (Warp.homography (src, quad), p);
                default:
                    return Warp.preset (WarpStyle.from_id (style), box, p, bend, hdist, vdist, vertical);
            }
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            base.apply_transform (m, scale_strokes);
            for (int i = 0; i < grid.length; i++) m.transform_point (ref grid[i].x, ref grid[i].y);
            for (int i = 0; i < quad.length; i++) m.transform_point (ref quad[i].x, ref quad[i].y);
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var box = source_bounds ();
            var g = new GroupNode ();
            foreach (var c in children) g.add (warp_node (c, box));
            return g;
        }

        private Node warp_node (Node n, Rect box) {
            var grp = n as GroupNode;
            if (grp != null && grp.generated (null) == null) {
                var out_group = grp.make_empty () as GroupNode;
                grp.copy_into (out_group);
                out_group.children.clear ();
                foreach (var c in grp.children) out_group.add (warp_node (c, box));
                return out_group;
            }
            PathData? source = null;
            var pn = n as PathNode;
            if (pn != null) source = pn.render_path ();
            else source = n.outline ();
            if (source == null) return n.clone ();
            var r = new PathNode ();
            n.copy_common (r);
            r.mask = null;
            r.path = PathOps.map_points (source, (p) => map (p, box));
            if (!(n is PathNode)) {
                if (r.appearance.size == 0) r.appearance.add (new PaintLayer.fill (new Paint.hex ("#000000")));
            }
            return r;
        }
    }

    public class LivePaintFill : Object {
        public Point sample;
        public Paint paint;

        public LivePaintFill (Point sample, Paint paint) {
            this.sample = sample;
            this.paint = paint;
        }
    }

    public class LivePaintNode : GroupNode {
        public Gee.ArrayList<LivePaintFill> fills = new Gee.ArrayList<LivePaintFill> ();
        private Gee.ArrayList<PlanarFace>? cache = null;
        private string cache_key = "";

        public override string kind_name () {
            return "livepaint";
        }

        public override string kind_label () {
            return _("Live Paint Group");
        }

        public override Node make_empty () {
            return new LivePaintNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (LivePaintNode) target;
            t.fills.clear ();
            foreach (var f in fills) t.fills.add (new LivePaintFill (f.sample, f.paint.copy ()));
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            base.apply_transform (m, scale_strokes);
            foreach (var f in fills) {
                m.transform_point (ref f.sample.x, ref f.sample.y);
                Transforms.transform_paint (f.paint, m);
            }
        }

        public Gee.ArrayList<PlanarFace> faces () {
            var paths = new Gee.ArrayList<PathData> ();
            var key = new StringBuilder ();
            foreach (var c in children) {
                var o = c.outline ();
                if (o == null) continue;
                paths.add (o);
                key.append (o.to_svg (3));
                key.append ("|");
            }
            if (cache != null && cache_key == key.str) return cache;
            cache = PlanarFaces.compute (paths);
            cache_key = key.str;
            return cache;
        }

        public void paint_at (Point p, Paint paint) {
            var face = PlanarFaces.face_at (faces (), p);
            if (face == null) return;
            for (int i = fills.size - 1; i >= 0; i--) {
                if (PlanarFaces.face_at (faces (), fills[i].sample) == face) fills.remove_at (i);
            }
            if (paint.visible ()) fills.add (new LivePaintFill (face.sample, paint.copy ()));
        }

        public override GroupNode? generated (VectorDocument? doc) {
            var g = new GroupNode ();
            var list = faces ();
            foreach (var f in fills) {
                var face = PlanarFaces.face_at (list, f.sample);
                if (face == null) continue;
                var pn = new PathNode.with_path (face.path.copy ());
                pn.even_odd = true;
                pn.appearance.add (new PaintLayer.fill (f.paint.copy ()));
                g.add (pn);
            }
            foreach (var c in children) {
                var copy = c.clone ();
                copy.appearance.clear ();
                var s = c.first_stroke ();
                if (s != null) copy.appearance.add (s.copy ());
                g.add (copy);
            }
            return g;
        }
    }
}
