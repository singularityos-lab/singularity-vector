using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class PenTool : Tool {
        private PathNode? current = null;
        private Point press_point;
        private Point? pending_out = null;
        private bool closing = false;
        private Point hover;
        private bool pressed = false;

        public PenTool () {
            base ("pen", _("Pen"), "vector-pen-symbolic", "p");
        }

        public override bool shows_anchors () {
            return true;
        }

        public override bool wants_hover () {
            return current != null;
        }

        public override void deactivate () {
            finish ();
        }

        public void finish () {
            if (current != null && PathOps.anchors (current.path).size < 2) {
                doc.begin (_("Remove Point"));
                if (current.parent != null) current.parent.remove (current);
                doc.commit ();
            }
            current = null;
            pending_out = null;
            canvas.queue_draw ();
        }

        private Point last_anchor () {
            var s = current.path.segs[current.path.segs.size - 1];
            return Point (s.x, s.y);
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            pressed = true;
            var q = canvas.snap (p, current != null ? new Gee.ArrayList<Node>.wrap ({ current }) : null);
            if (current != null && shift (mods)) q = constrain (last_anchor (), q);
            press_point = q;
            closing = false;
            if (current == null) {
                foreach (var pn in PathEdit.editable_paths (canvas)) {
                    if (PathOps.all_closed (pn.path)) continue;
                    var c = PathOps.contours (pn.path);
                    if (c.size != 1) continue;
                    var first = pn.path.segs[0];
                    var last = pn.path.segs[pn.path.segs.size - 1];
                    if (Point (last.x, last.y).distance (p) < canvas.px (6) || Point (first.x, first.y).distance (p) < canvas.px (6)) {
                        doc.begin (_("Continue Path"));
                        PathEdit.detach_live (pn);
                        if (Point (first.x, first.y).distance (p) < canvas.px (6) && Point (last.x, last.y).distance (p) >= canvas.px (6)) pn.path = PathOps.reversed (pn.path);
                        doc.commit ();
                        current = pn;
                        pending_out = null;
                        canvas.select_only (pn);
                        return;
                    }
                }
                foreach (var pn in PathEdit.editable_paths (canvas)) {
                    PathNode? hit_node;
                    int idx;
                    var single = new Gee.ArrayList<PathNode> ();
                    single.add (pn);
                    if (PathEdit.hit_anchor (canvas, single, p, out hit_node, out idx)) {
                        doc.begin (_("Delete Anchor Point"));
                        PathEdit.detach_live (pn);
                        pn.path = PathOps.remove_anchor (pn.path, idx);
                        doc.commit ();
                        return;
                    }
                    var h = PathOps.nearest (pn.render_path (), p, canvas.px (5));
                    if (h != null && pn.path.segs[h.segment].kind != SegKind.MOVE) {
                        doc.begin (_("Add Anchor Point"));
                        PathEdit.detach_live (pn);
                        pn.path = PathOps.insert_point (pn.path, h.segment, h.t);
                        pn.modes.clear ();
                        doc.commit ();
                        return;
                    }
                }
                var node = new PathNode ();
                node.path.move_to (q.x, q.y);
                canvas.style.apply (node);
                add_node (node, _("Pen"));
                current = node;
                pending_out = null;
                doc.begin (_("Pen"));
                return;
            }
            var path = current.path;
            var first = Point (path.segs[0].x, path.segs[0].y);
            doc.begin (_("Add Point"));
            if (PathOps.anchors (path).size >= 2 && first.distance (p) < canvas.px (6)) {
                q = first;
                closing = true;
            }
            var prev = last_anchor ();
            if (pending_out != null) {
                path.curve_to (pending_out.x, pending_out.y, q.x, q.y, q.x, q.y);
            } else {
                path.line_to (q.x, q.y);
            }
            pending_out = null;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (current == null) return;
            var path = current.path;
            var s = path.segs[path.segs.size - 1];
            var d = shift (mods) ? constrain (press_point, p) : p;
            if (path.segs.size == 1) {
                pending_out = d;
                doc.changed ();
                return;
            }
            if (alt (mods)) {
                pending_out = d;
                doc.changed ();
                return;
            }
            if (s.kind == SegKind.LINE) {
                var start = Point (path.segs[path.segs.size - 2].x, path.segs[path.segs.size - 2].y);
                s.kind = SegKind.CURVE;
                s.x1 = start.x;
                s.y1 = start.y;
            }
            s.x2 = 2 * press_point.x - d.x;
            s.y2 = 2 * press_point.y - d.y;
            pending_out = d;
            current.modes[path.segs.size - 1] = (int) HandleMode.SYMMETRIC;
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            pressed = false;
            if (current == null) return;
            if (closing) {
                var path = current.path;
                var first = path.segs[0];
                if (pending_out != null) {
                    var second = path.segs.size > 1 ? path.segs[1] : null;
                    if (second != null && second.kind == SegKind.LINE) {
                        second.kind = SegKind.CURVE;
                        second.x1 = pending_out.x;
                        second.y1 = pending_out.y;
                        second.x2 = second.x;
                        second.y2 = second.y;
                    } else if (second != null && second.kind == SegKind.CURVE) {
                        second.x1 = pending_out.x;
                        second.y1 = pending_out.y;
                    }
                    first.x = first.x;
                }
                path.close ();
                doc.commit ();
                current = null;
                pending_out = null;
                return;
            }
            doc.commit ();
        }

        public override void motion (Point p, Gdk.ModifierType mods) {
            hover = p;
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            if (keyval == Gdk.Key.Escape || keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                bool had = current != null;
                finish ();
                return had;
            }
            return false;
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (current == null) return;
            var a = last_anchor ();
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            cr.set_line_width (canvas.px (1));
            if (pending_out != null) {
                cr.move_to (a.x, a.y);
                cr.line_to (pending_out.x, pending_out.y);
                cr.stroke ();
                cr.arc (pending_out.x, pending_out.y, canvas.px (3), 0, 2 * Math.PI);
                cr.fill ();
            }
            if (!pressed) {
                cr.move_to (a.x, a.y);
                if (pending_out != null) cr.curve_to (pending_out.x, pending_out.y, hover.x, hover.y, hover.x, hover.y);
                else cr.line_to (hover.x, hover.y);
                cr.stroke ();
            }
        }
    }

    public class CurvatureTool : Tool {
        private PathNode? current = null;
        private Point[] points = {};
        private Gee.ArrayList<bool> corners = new Gee.ArrayList<bool> ();
        private int dragging = -1;

        public CurvatureTool () {
            base ("curvature", _("Curvature"), "vector-curvature-symbolic", "shift+asciitilde");
        }

        public override void deactivate () {
            current = null;
            points = {};
            corners.clear ();
        }

        public static PathData build (Point[] pts, Gee.List<bool> corner, bool closed) {
            var p = new PathData ();
            int n = pts.length;
            if (n == 0) return p;
            p.move_to (pts[0].x, pts[0].y);
            int count = closed ? n : n - 1;
            for (int i = 0; i < count; i++) {
                var p0 = pts[closed ? (i - 1 + n) % n : int.max (i - 1, 0)];
                var p1 = pts[i];
                var p2 = pts[(i + 1) % n];
                var p3 = pts[closed ? (i + 2) % n : int.min (i + 2, n - 1)];
                double k1 = corner[i] ? 0 : 1.0 / 6;
                double k2 = corner[(i + 1) % n] ? 0 : 1.0 / 6;
                p.curve_to (p1.x + (p2.x - p0.x) * k1, p1.y + (p2.y - p0.y) * k1, p2.x - (p3.x - p1.x) * k2, p2.y - (p3.y - p1.y) * k2, p2.x, p2.y);
            }
            if (closed) p.close ();
            return p;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var q = canvas.snap (p, null);
            for (int i = 0; i < points.length; i++) {
                if (points[i].distance (p) < canvas.px (6)) {
                    if (i == 0 && points.length > 2 && current != null) {
                        doc.begin (_("Close Path"));
                        current.path = build (points, corners, true);
                        doc.commit ();
                        current = null;
                        points = {};
                        corners.clear ();
                        return;
                    }
                    dragging = i;
                    doc.begin (_("Move Point"));
                    return;
                }
            }
            if (current == null) {
                var node = new PathNode ();
                canvas.style.apply (node);
                points = { q };
                corners.clear ();
                corners.add (alt (mods));
                node.path = build (points, corners, false);
                add_node (node, _("Curvature"));
                current = node;
                return;
            }
            doc.begin (_("Add Point"));
            points += q;
            corners.add (alt (mods));
            current.path = build (points, corners, false);
            doc.commit ();
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (dragging < 0 || current == null) return;
            points[dragging] = p;
            current.path = build (points, corners, false);
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (dragging >= 0) doc.commit ();
            dragging = -1;
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            if (keyval == Gdk.Key.Escape || keyval == Gdk.Key.Return) {
                bool had = current != null;
                current = null;
                points = {};
                corners.clear ();
                return had;
            }
            return false;
        }

        public override void draw_overlay (Cairo.Context cr) {
            cr.set_source_rgba (0.2, 0.5, 0.95, 1);
            foreach (var p in points) {
                cr.arc (p.x, p.y, canvas.px (4), 0, 2 * Math.PI);
                cr.fill ();
            }
        }
    }

    public class PencilTool : Tool {
        protected Gee.ArrayList<Point?> samples = new Gee.ArrayList<Point?> ();

        protected Point[] sample_array () {
            Point[] r = new Point[samples.size];
            for (int i = 0; i < samples.size; i++) r[i] = samples[i];
            return r;
        }
        public double fidelity = 2.5;
        public bool close_near = true;

        public PencilTool () {
            base ("pencil", _("Pencil"), "vector-pencil-symbolic", "n");
        }

        protected PencilTool.named (string id, string label, string icon, string key) {
            base (id, label, icon, key);
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            samples.clear ();
            samples.add (p);
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (samples.size == 0 || samples[samples.size - 1].distance (p) > canvas.px (0.75)) samples.add (p);
        }

        protected PathData fitted () {
            var pts = sample_array ();
            bool closed = close_near && pts.length > 4 && pts[0].distance (pts[pts.length - 1]) < canvas.px (12);
            var reduced = PolyOps.simplify (pts, canvas.px (0.3));
            var curves = CurveFit.fit (reduced, canvas.px (fidelity));
            var path = PathOps.from_beziers (curves, closed);
            return path;
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (samples.size < 2) {
                samples.clear ();
                return;
            }
            var node = new PathNode.with_path (fitted ());
            make (node);
            samples.clear ();
        }

        protected virtual void make (PathNode node) {
            canvas.style.apply (node, PathOps.all_closed (node.path));
            if (!PathOps.all_closed (node.path)) {
                node.appearance.clear ();
                node.appearance.add (new PaintLayer.line (canvas.style.stroke.copy (), canvas.style.width));
            }
            add_node (node, _("Pencil"));
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (samples.size < 2) return;
            cr.move_to (samples[0].x, samples[0].y);
            foreach (var p in samples) cr.line_to (p.x, p.y);
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            cr.set_line_width (canvas.px (1.5));
            cr.stroke ();
        }
    }

    public class PaintbrushTool : PencilTool {
        public PaintbrushTool () {
            base.named ("paintbrush", _("Paintbrush"), "vector-brush-symbolic", "b");
            close_near = false;
        }

        protected override void make (PathNode node) {
            var layer = new PaintLayer.line (canvas.style.stroke.copy (), double.max (canvas.style.width, 1));
            layer.brush = canvas.style.brush != "" ? canvas.style.brush : (doc.brushes.size > 0 ? doc.brushes[0].id : "");
            node.appearance.add (layer);
            add_node (node, _("Paintbrush"));
        }
    }

    public class BlobBrushTool : PencilTool {
        public double size = 12;

        public BlobBrushTool () {
            base.named ("blob", _("Blob Brush"), "vector-blob-symbolic", "shift+b");
        }

        protected override void make (PathNode node) {
            var pts = PolyOps.simplify (sample_array (), 0.3);
            double[] widths = new double[pts.length];
            for (int i = 0; i < pts.length; i++) widths[i] = size;
            var outline = StrokeOutline.to_path (StrokeOutline.build (pts, widths, true));
            var color = canvas.style.stroke.copy ();
            if (color.kind != PaintKind.SOLID) color = new Paint.hex ("#000000");
            var merge = new Gee.ArrayList<PathNode> ();
            var target = target_group ();
            var blob_box = outline.bounds ();
            foreach (var c in target.children) {
                var pn = c as PathNode;
                if (pn == null || pn.locked || pn.hidden) continue;
                var f = pn.first_fill ();
                if (pn.appearance.size != 1 || f == null || f.paint.kind != PaintKind.SOLID || !f.paint.color.same (color.color)) continue;
                if (!pn.geometric_bounds ().intersects (blob_box)) continue;
                merge.add (pn);
            }
            var paths = new Gee.ArrayList<PathData> ();
            paths.add (outline);
            foreach (var m in merge) paths.add (m.path);
            var united = CurveBoolean.unite_all (paths);
            var smooth = PathSimplify.simplify (united, 0.4, 50);
            doc.begin (_("Blob Brush"));
            int index = target.children.size;
            foreach (var m in merge) {
                index = int.min (index, target.children.index_of (m));
                target.remove (m);
            }
            var blob = new PathNode.with_path (smooth.is_empty () ? united : smooth);
            blob.appearance.add (new PaintLayer.fill (color));
            target.add (blob, index);
            doc.ensure_ids ();
            doc.commit ();
            canvas.select_only (blob);
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (samples.size < 2) return;
            cr.move_to (samples[0].x, samples[0].y);
            foreach (var p in samples) cr.line_to (p.x, p.y);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            var c = canvas.style.stroke.representative ();
            cr.set_source_rgba (c.r, c.g, c.b, 0.6);
            cr.set_line_width (size);
            cr.stroke ();
        }
    }

    public class ShapeTool : Tool {
        private Point start;
        private Point current;
        private PathNode? node = null;
        public int sides = 6;
        public int points = 5;
        public double inner = 0.45;
        public double radius = 12;
        public signal void exact_requested (string kind, Point at);

        public ShapeTool (string kind, string label, string icon, string key) {
            base (kind, label, icon, key);
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = canvas.snap (p, null);
            current = start;
            node = null;
        }

        private void update (Gdk.ModifierType mods) {
            if (node == null) {
                node = new PathNode ();
                node.live = new LiveShape ();
                node.live.kind = id == "rounded" ? "rectangle" : id;
                if (id == "rounded") node.live.radius = radius;
                node.live.sides = id == "star" ? points : sides;
                node.live.inner = inner;
                canvas.style.apply (node, id != "line");
                doc.begin (label);
                target_group ().add (node);
                doc.ensure_ids ();
            }
            var live = node.live;
            var q = current;
            if (id == "line") {
                if (shift (mods)) q = constrain (start, q);
                live.cx = start.x;
                live.cy = start.y;
                live.x2 = q.x;
                live.y2 = q.y;
            } else if (id == "polygon" || id == "star") {
                double r = start.distance (q);
                double a = Math.atan2 (q.y - start.y, q.x - start.x) + Math.PI / 2;
                if (shift (mods)) a = 0;
                live.cx = start.x;
                live.cy = start.y;
                live.w = live.h = r * 2;
                live.angle = a;
            } else {
                double dx = q.x - start.x, dy = q.y - start.y;
                if (shift (mods)) {
                    double s = double.max (dx.abs (), dy.abs ());
                    dx = s * (dx < 0 ? -1 : 1);
                    dy = s * (dy < 0 ? -1 : 1);
                }
                if (alt (mods)) {
                    live.cx = start.x;
                    live.cy = start.y;
                    live.w = dx.abs () * 2;
                    live.h = dy.abs () * 2;
                } else {
                    live.cx = start.x + dx / 2;
                    live.cy = start.y + dy / 2;
                    live.w = dx.abs ();
                    live.h = dy.abs ();
                }
            }
            node.rebuild_live ();
            doc.changed ();
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = canvas.snap (p, node != null ? new Gee.ArrayList<Node>.wrap ({ node }) : null);
            if (node == null && start.distance (current) < canvas.px (3)) return;
            update (mods);
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (node == null) {
                exact_requested (id, start);
                return;
            }
            doc.commit ();
            canvas.select_only (node);
            node = null;
        }

        public PathNode create_exact (Point at, double w, double h) {
            var n = new PathNode ();
            n.live = new LiveShape ();
            n.live.kind = id == "rounded" ? "rectangle" : id;
            n.live.radius = id == "rounded" ? radius : 0;
            n.live.sides = id == "star" ? points : sides;
            n.live.inner = inner;
            if (id == "line") {
                n.live.cx = at.x;
                n.live.cy = at.y;
                n.live.x2 = at.x + w;
                n.live.y2 = at.y + h;
            } else {
                n.live.cx = at.x + w / 2;
                n.live.cy = at.y + h / 2;
                n.live.w = w;
                n.live.h = h;
            }
            n.rebuild_live ();
            canvas.style.apply (n, id != "line");
            add_node (n, label);
            return n;
        }
    }

    public class TextTool : Tool {
        private Point start;
        private Point current;
        private bool dragging = false;
        public bool editing = false;

        public TextTool () {
            base ("text", _("Type"), "vector-text-symbolic", "t");
        }

        public override string? cursor_name () {
            return "text";
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            current = p;
            dragging = true;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = p;
        }

        private TextNode base_text () {
            var t = new TextNode ();
            t.style = canvas.style.text.copy ();
            var fill = canvas.style.fill.visible () ? canvas.style.fill.copy () : new Paint.hex ("#000000");
            if (fill.kind == PaintKind.SOLID && fill.color.to_hex () == "#ffffff") fill = new Paint.hex ("#000000");
            t.appearance.add (new PaintLayer.fill (fill));
            return t;
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            dragging = false;
            var r = Rect.from_points (start.x, start.y, p.x, p.y);
            if (r.w > canvas.px (8) && r.h > canvas.px (8)) {
                var t = base_text ();
                t.mode = "area";
                t.area = new PathData.rect (r.x, r.y, r.w, r.h);
                add_node (t, _("Area Type"));
                canvas.text_edit_requested (t, true);
                return;
            }
            var hit = canvas.hit_leaf (p);
            var existing = hit as TextNode;
            if (existing != null) {
                canvas.select_only (existing);
                canvas.text_edit_requested (existing, false);
                return;
            }
            var pn = hit as PathNode;
            if (pn != null && PathOps.nearest (pn.render_path (), p, canvas.px (6)) != null) {
                var t = base_text ();
                doc.begin (_("Type on a Path"));
                if (PathOps.all_closed (pn.path) && !alt (mods)) {
                    t.mode = "area";
                    t.area = pn.render_path ().copy ();
                } else {
                    t.mode = "path";
                    t.on_path = pn.render_path ().copy ();
                }
                var parent = pn.parent;
                int index = parent.children.index_of (pn);
                parent.remove (pn);
                parent.add (t, index);
                doc.ensure_ids ();
                doc.commit ();
                canvas.select_only (t);
                canvas.text_edit_requested (t, true);
                return;
            }
            var t = base_text ();
            t.matrix = Transforms.translate (p.x, p.y);
            add_node (t, _("Type"));
            canvas.text_edit_requested (t, true);
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (dragging) draw_rubber (cr, Rect.from_points (start.x, start.y, current.x, current.y));
        }
    }
}
