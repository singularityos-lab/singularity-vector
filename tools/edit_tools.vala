using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class ScissorsTool : Tool {
        public ScissorsTool () {
            base ("scissors", _("Scissors"), "vector-scissors-symbolic", "c");
        }

        public override bool shows_anchors () {
            return true;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var pn = canvas.hit_leaf (p) as PathNode;
            if (pn == null) return;
            var h = PathOps.nearest (pn.render_path (), p, canvas.px (6));
            if (h == null) return;
            PathEdit.detach_live (pn);
            var cuts = new Gee.ArrayList<PathHit> ();
            cuts.add (h);
            var pieces = PathOps.split (pn.path, cuts, false);
            doc.begin (_("Split Path"));
            var parent = pn.parent;
            int index = parent.children.index_of (pn);
            var made = new Gee.ArrayList<Node> ();
            if (pieces.size == 1) {
                pn.path = pieces[0];
                made.add (pn);
            } else {
                parent.remove (pn);
                for (int i = 0; i < pieces.size; i++) {
                    var c = pn.clone () as PathNode;
                    c.id = "";
                    c.path = pieces[i];
                    c.modes.clear ();
                    parent.add (c, index + i);
                    made.add (c);
                }
            }
            doc.ensure_ids ();
            doc.commit ();
            canvas.set_selection (made);
        }
    }

    public class KnifeTool : Tool {
        private Point[] trail = {};

        public KnifeTool () {
            base ("knife", _("Knife"), "vector-knife-symbolic", "");
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            trail = { p };
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            trail += alt (mods) && trail.length > 0 ? constrain (trail[0], p) : p;
            if (alt (mods)) trail = { trail[0], trail[trail.length - 1] };
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (trail.length < 2) return;
            var cut = PathOps.polygon_path (trail, false);
            var targets = new Gee.ArrayList<PathNode> ();
            var pool = canvas.selection.size > 0 ? canvas.selection : canvas.selectable_roots ();
            foreach (var n in pool) PathEdit.collect (n, targets);
            doc.begin (_("Knife"));
            var made = new Gee.ArrayList<Node> ();
            foreach (var pn in targets) {
                if (pn.effectively_locked () || !PathOps.all_closed (pn.path)) continue;
                if (!pn.geometric_bounds ().intersects (cut.bounds ())) continue;
                var list = new Gee.ArrayList<PathData> ();
                list.add (pn.render_path ());
                list.add (cut);
                var faces = PlanarFaces.compute (list);
                var inside = new Gee.ArrayList<PlanarFace> ();
                foreach (var f in faces) if (PathOps.contains (pn.render_path (), f.sample, pn.even_odd)) inside.add (f);
                if (inside.size < 2) continue;
                var parent = pn.parent;
                int index = parent.children.index_of (pn);
                parent.remove (pn);
                for (int i = 0; i < inside.size; i++) {
                    var c = pn.clone () as PathNode;
                    c.id = "";
                    c.live = null;
                    c.corners.clear ();
                    c.modes.clear ();
                    c.path = inside[i].path;
                    parent.add (c, index + i);
                    made.add (c);
                }
            }
            doc.ensure_ids ();
            if (made.size == 0) doc.cancel ();
            else {
                doc.commit ();
                canvas.set_selection (made);
            }
            trail = {};
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (trail.length < 2) return;
            cr.move_to (trail[0].x, trail[0].y);
            foreach (var p in trail) cr.line_to (p.x, p.y);
            cr.set_source_rgba (0.9, 0.2, 0.2, 0.9);
            cr.set_line_width (canvas.px (1.5));
            cr.stroke ();
        }
    }

    public class EraserTool : Tool {
        private Point[] trail = {};
        public double size = 16;

        public EraserTool () {
            base ("eraser", _("Eraser"), "vector-eraser-symbolic", "shift+e");
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            trail = { p };
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            trail += p;
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (trail.length < 1) return;
            double[] widths = new double[trail.length];
            for (int i = 0; i < trail.length; i++) widths[i] = size;
            var eraser = StrokeOutline.to_path (StrokeOutline.build (trail, widths, true));
            var targets = new Gee.ArrayList<PathNode> ();
            var pool = canvas.selection.size > 0 ? canvas.selection : canvas.selectable_roots ();
            foreach (var n in pool) PathEdit.collect (n, targets);
            doc.begin (_("Erase"));
            bool any = false;
            var box = eraser.bounds ();
            foreach (var pn in targets) {
                if (pn.effectively_locked () || !pn.geometric_bounds ().intersects (box)) continue;
                if (PathOps.all_closed (pn.path)) {
                    var result = CurveBoolean.apply (pn.render_path (), eraser, BoolOp.SUBTRACT, pn.even_odd);
                    pn.live = null;
                    pn.corners.clear ();
                    pn.modes.clear ();
                    pn.path = result;
                    if (result.is_empty () && pn.parent != null) pn.parent.remove (pn);
                } else {
                    var pieces = new Gee.ArrayList<PathData> ();
                    var cuts = new Gee.ArrayList<PathHit> ();
                    var src = pn.render_path ();
                    foreach (var e in PathOps.edges (eraser, true)) foreach (var h in PathOps.line_hits (src, e.start, e.end ())) cuts.add (h);
                    if (cuts.size == 0) continue;
                    foreach (var piece in PathOps.split (src, cuts, false)) {
                        var mid = PathOps.edges (piece)[0].at (0.5);
                        if (!PathOps.contains (eraser, mid)) pieces.add (piece);
                    }
                    var parent = pn.parent;
                    int index = parent.children.index_of (pn);
                    parent.remove (pn);
                    for (int i = 0; i < pieces.size; i++) {
                        var c = pn.clone () as PathNode;
                        c.id = "";
                        c.live = null;
                        c.path = pieces[i];
                        parent.add (c, index + i);
                    }
                }
                any = true;
            }
            doc.ensure_ids ();
            if (any) doc.commit ();
            else doc.cancel ();
            trail = {};
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (trail.length < 1) return;
            cr.move_to (trail[0].x, trail[0].y);
            foreach (var p in trail) cr.line_to (p.x, p.y);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
            cr.set_line_width (size);
            cr.stroke ();
        }
    }

    public class ShapeBuilderTool : Tool {
        private Gee.ArrayList<PlanarFace>? faces = null;
        private Gee.ArrayList<PlanarFace> picked = new Gee.ArrayList<PlanarFace> ();
        private PlanarFace? hover = null;
        private Gee.ArrayList<PathNode> sources = new Gee.ArrayList<PathNode> ();

        public ShapeBuilderTool () {
            base ("shape-builder", _("Shape Builder"), "vector-shape-builder-symbolic", "shift+m");
        }

        public override bool wants_hover () {
            return true;
        }

        private void prepare () {
            sources.clear ();
            foreach (var n in canvas.selection) PathEdit.collect (n, sources);
            var paths = new Gee.ArrayList<PathData> ();
            foreach (var s in sources) paths.add (s.render_path ());
            faces = sources.size > 0 ? PlanarFaces.compute (paths) : new Gee.ArrayList<PlanarFace> ();
        }

        public override void activate () {
            faces = null;
        }

        public override void motion (Point p, Gdk.ModifierType mods) {
            if (faces == null) prepare ();
            hover = PlanarFaces.face_at (faces, p);
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            if (faces == null) prepare ();
            picked.clear ();
            var f = PlanarFaces.face_at (faces, p);
            if (f != null) picked.add (f);
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            var f = PlanarFaces.face_at (faces, p);
            if (f != null && !picked.contains (f)) picked.add (f);
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (picked.size == 0) return;
            var removal = alt (mods);
            var parts = new Gee.ArrayList<PathData> ();
            foreach (var f in picked) parts.add (f.path);
            var united = picked.size == 1 ? picked[0].path.copy () : CurveBoolean.unite_all (parts);
            PathNode? style_source = null;
            foreach (var s in sources) if (PathOps.contains (s.render_path (), picked[0].sample, s.even_odd)) style_source = s;
            if (style_source == null && sources.size > 0) style_source = sources[sources.size - 1];
            doc.begin (removal ? _("Delete Region") : _("Shape Builder"));
            var parent = style_source != null ? style_source.parent : target_group ();
            int index = style_source != null ? parent.children.index_of (style_source) : parent.children.size;
            var remaining = new Gee.ArrayList<PlanarFace> ();
            foreach (var f in faces) if (!picked.contains (f)) remaining.add (f);
            var made = new Gee.ArrayList<Node> ();
            foreach (var f in remaining) {
                PathNode? owner = null;
                foreach (var s in sources) if (PathOps.contains (s.render_path (), f.sample, s.even_odd)) owner = s;
                if (owner == null) continue;
                var c = owner.clone () as PathNode;
                c.id = "";
                c.live = null;
                c.corners.clear ();
                c.modes.clear ();
                c.path = f.path.copy ();
                made.add (c);
            }
            if (!removal && style_source != null) {
                var merged = style_source.clone () as PathNode;
                merged.id = "";
                merged.live = null;
                merged.corners.clear ();
                merged.modes.clear ();
                merged.path = united;
                made.add (merged);
            }
            foreach (var s in sources) if (s.parent != null) s.parent.remove (s);
            index = int.min (index, parent.children.size);
            for (int i = 0; i < made.size; i++) parent.add (made[i], index + i);
            doc.ensure_ids ();
            doc.commit ();
            canvas.set_selection (made);
            picked.clear ();
            faces = null;
            prepare ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (hover != null) {
                cr.new_path ();
                hover.path.to_cairo (cr);
                cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                cr.set_source_rgba (0.2, 0.5, 0.95, 0.25);
                cr.fill ();
            }
            foreach (var f in picked) {
                cr.new_path ();
                f.path.to_cairo (cr);
                cr.set_source_rgba (0.95, 0.4, 0.2, 0.35);
                cr.fill ();
            }
        }
    }

    public class LivePaintTool : Tool {
        private PlanarFace? hover = null;

        public LivePaintTool () {
            base ("live-paint", _("Live Paint Bucket"), "vector-live-paint-symbolic", "k");
        }

        public override bool wants_hover () {
            return true;
        }

        private LivePaintNode? group_at (Point p) {
            foreach (var n in canvas.selectable_roots ()) {
                var lp = n as LivePaintNode;
                if (lp != null && lp.geometric_bounds ().inflate (canvas.px (4)).contains (p.x, p.y)) return lp;
            }
            return null;
        }

        public override void motion (Point p, Gdk.ModifierType mods) {
            var g = group_at (p);
            hover = g != null ? PlanarFaces.face_at (g.faces (), p) : null;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var g = group_at (p);
            if (g == null) {
                if (canvas.selection.size == 0) return;
                g = Commands.make_live_paint (canvas);
                if (g == null) return;
            }
            doc.begin (_("Live Paint"));
            g.paint_at (p, alt (mods) ? new Paint () : canvas.style.fill.copy ());
            doc.commit ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (hover == null) return;
            cr.new_path ();
            hover.path.to_cairo (cr);
            cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            cr.set_source_rgba (0.95, 0.4, 0.2, 0.3);
            cr.fill_preserve ();
            cr.set_source_rgba (0.95, 0.4, 0.2, 0.9);
            cr.set_line_width (canvas.px (2));
            cr.stroke ();
        }
    }

    public class GradientTool : Tool {
        private Point start;
        private int dragging = -1;
        private Paint? target = null;

        public GradientTool () {
            base ("gradient", _("Gradient"), "vector-gradient-symbolic", "g");
        }

        private PaintLayer? layer () {
            if (canvas.selection.size == 0) return null;
            var n = canvas.selection[0];
            var f = n.first_fill ();
            return f;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            var l = layer ();
            if (l == null) return;
            if (l.paint.kind == PaintKind.FREEFORM) {
                doc.begin (_("Edit Freeform Gradient"));
                for (int i = 0; i < l.paint.freeform.size; i++) {
                    var f = l.paint.freeform[i];
                    if (Point (f.x, f.y).distance (p) < canvas.px (7)) {
                        if (alt (mods)) {
                            l.paint.freeform.remove_at (i);
                            dragging = -1;
                            doc.commit ();
                            return;
                        }
                        dragging = 100 + i;
                        return;
                    }
                }
                l.paint.freeform.add (new FreeformPoint (p.x, p.y, canvas.style.fill.representative ().copy ()));
                dragging = 100 + l.paint.freeform.size - 1;
                return;
            }
            var g = l.paint.gradient;
            bool is_grad = l.paint.kind == PaintKind.LINEAR || l.paint.kind == PaintKind.RADIAL;
            doc.begin (_("Edit Gradient"));
            if (is_grad) {
                if (Point (g.x1, g.y1).distance (p) < canvas.px (6)) {
                    dragging = 0;
                    return;
                }
                if (Point (g.x2, g.y2).distance (p) < canvas.px (6)) {
                    dragging = 1;
                    return;
                }
                for (int i = 0; i < g.stops.size; i++) {
                    var sp = PathOps.mix (Point (g.x1, g.y1), Point (g.x2, g.y2), g.stops[i].offset);
                    if (sp.distance (p) < canvas.px (6)) {
                        dragging = 10 + i;
                        return;
                    }
                }
                double len = Point (g.x1, g.y1).distance (Point (g.x2, g.y2));
                if (len > 0) {
                    double t = ((p.x - g.x1) * (g.x2 - g.x1) + (p.y - g.y1) * (g.y2 - g.y1)) / (len * len);
                    var on = PathOps.mix (Point (g.x1, g.y1), Point (g.x2, g.y2), t);
                    if (t > 0 && t < 1 && on.distance (p) < canvas.px (5)) {
                        var c = Interpolate.ink (stop_color (g, t), stop_color (g, t), 0);
                        g.stops.add (new GradientStop (t, c));
                        g.sort ();
                        doc.commit ();
                        dragging = -1;
                        return;
                    }
                }
            }
            if (!is_grad) {
                var old = l.paint.representative ();
                l.paint.kind = PaintKind.LINEAR;
                l.paint.gradient = new Gradient.two (old.copy (), Ink.hex ("#000000"));
            }
            g = l.paint.gradient;
            g.x1 = p.x;
            g.y1 = p.y;
            g.x2 = p.x;
            g.y2 = p.y;
            g.fx = p.x;
            g.fy = p.y;
            dragging = 1;
        }

        private static Ink stop_color (Gradient g, double t) {
            if (g.stops.size == 0) return new Ink ();
            GradientStop a = g.stops[0], b = g.stops[g.stops.size - 1];
            foreach (var s in g.stops) {
                if (s.offset <= t) a = s;
                if (s.offset >= t) {
                    b = s;
                    break;
                }
            }
            double span = b.offset - a.offset;
            return Interpolate.ink (a.color, b.color, span > 0 ? (t - a.offset) / span : 0);
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            var l = layer ();
            if (l == null || dragging < 0) return;
            if (dragging >= 100) {
                var f = l.paint.freeform[dragging - 100];
                f.x = p.x;
                f.y = p.y;
                doc.changed ();
                return;
            }
            var g = l.paint.gradient;
            var q = shift (mods) ? constrain (Point (g.x1, g.y1), p) : p;
            if (dragging == 0) {
                double dx = q.x - g.x1, dy = q.y - g.y1;
                g.x1 = q.x;
                g.y1 = q.y;
                g.fx += dx;
                g.fy += dy;
            } else if (dragging == 1) {
                g.x2 = q.x;
                g.y2 = q.y;
            } else if (dragging >= 10) {
                double len = Point (g.x1, g.y1).distance (Point (g.x2, g.y2));
                if (len > 0) g.stops[dragging - 10].offset = (((p.x - g.x1) * (g.x2 - g.x1) + (p.y - g.y1) * (g.y2 - g.y1)) / (len * len)).clamp (0, 1);
            }
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (dragging >= 0) {
                var l = layer ();
                if (l != null) l.paint.gradient.sort ();
                doc.commit ();
            }
            dragging = -1;
            canvas.selection_changed ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            var l = layer ();
            if (l != null && l.paint.kind == PaintKind.FREEFORM) {
                foreach (var f in l.paint.freeform) {
                    cr.arc (f.x, f.y, canvas.px (6), 0, 2 * Math.PI);
                    cr.set_source_rgb (f.color.r, f.color.g, f.color.b);
                    cr.fill_preserve ();
                    cr.set_source_rgb (1, 1, 1);
                    cr.set_line_width (canvas.px (2));
                    cr.stroke ();
                    cr.arc (f.x, f.y, canvas.px (6) + f.spread * 40, 0, 2 * Math.PI);
                    cr.set_source_rgba (0, 0, 0, 0.3);
                    cr.set_line_width (canvas.px (1));
                    cr.set_dash ({ canvas.px (3), canvas.px (3) }, 0);
                    cr.stroke ();
                    cr.set_dash (null, 0);
                }
                return;
            }
            if (l == null || (l.paint.kind != PaintKind.LINEAR && l.paint.kind != PaintKind.RADIAL)) return;
            var g = l.paint.gradient;
            cr.set_line_width (canvas.px (1.5));
            cr.set_source_rgba (0, 0, 0, 0.7);
            cr.move_to (g.x1, g.y1);
            cr.line_to (g.x2, g.y2);
            cr.stroke ();
            if (l.paint.kind == PaintKind.RADIAL) {
                double r = Point (g.x1, g.y1).distance (Point (g.x2, g.y2));
                cr.save ();
                cr.translate (g.x1, g.y1);
                cr.rotate (Math.atan2 (g.y2 - g.y1, g.x2 - g.x1));
                cr.scale (1, double.max (g.aspect, 0.01));
                cr.arc (0, 0, r, 0, 2 * Math.PI);
                cr.restore ();
                cr.set_dash ({ canvas.px (4), canvas.px (3) }, 0);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            foreach (var s in g.stops) {
                var sp = PathOps.mix (Point (g.x1, g.y1), Point (g.x2, g.y2), s.offset);
                cr.arc (sp.x, sp.y, canvas.px (5), 0, 2 * Math.PI);
                cr.set_source_rgb (s.color.r, s.color.g, s.color.b);
                cr.fill_preserve ();
                cr.set_source_rgb (1, 1, 1);
                cr.set_line_width (canvas.px (1.5));
                cr.stroke ();
            }
        }
    }

    public class MeshTool : Tool {
        private MeshNode? active = null;
        private int vr = -1;
        private int vc = -1;
        private Point last;

        public MeshTool () {
            base ("mesh", _("Mesh"), "vector-mesh-symbolic", "u");
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            last = p;
            MeshNode? mesh = null;
            foreach (var n in canvas.selection) {
                mesh = n as MeshNode;
                if (mesh != null) break;
                var g = n as GroupNode;
                if (g != null && g.clip && g.children.size > 1) mesh = g.children[1] as MeshNode;
                if (mesh != null) break;
            }
            if (mesh == null) {
                var pn = canvas.hit_root (p) as PathNode;
                if (pn == null) return;
                Commands.make_mesh (canvas, pn, 1, 1);
                return;
            }
            active = mesh;
            vr = vc = -1;
            for (int r = 0; r <= mesh.rows; r++) {
                for (int c = 0; c <= mesh.cols; c++) {
                    var v = mesh.at (r, c);
                    if (Point (v.x, v.y).distance (p) < canvas.px (6)) {
                        vr = r;
                        vc = c;
                    }
                }
            }
            if (vr >= 0) {
                doc.begin (_("Edit Mesh"));
                if (!alt (mods)) {
                    var ink = canvas.style.fill.representative ();
                    if (shift (mods)) mesh.at (vr, vc).color = ink.copy ();
                }
                canvas.selection_changed ();
                return;
            }
            var box = mesh.geometric_bounds ();
            if (!box.contains (p.x, p.y)) return;
            doc.begin (_("Add Mesh Line"));
            Commands.mesh_add_lines (mesh, p, canvas.style.fill.representative ());
            doc.commit ();
        }

        public MeshVertex? selected_vertex () {
            if (active == null || vr < 0) return null;
            return active.at (vr, vc);
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (active == null || vr < 0) return;
            active.move_vertex (vr, vc, p.x - last.x, p.y - last.y);
            last = p;
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (active != null && vr >= 0) doc.commit ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            MeshNode? mesh = active;
            if (mesh == null) return;
            cr.set_line_width (canvas.px (1));
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            for (int r = 0; r <= mesh.rows; r++) {
                for (int c = 0; c <= mesh.cols; c++) {
                    var v = mesh.at (r, c);
                    cr.rectangle (v.x - canvas.px (3), v.y - canvas.px (3), canvas.px (6), canvas.px (6));
                    if (r == vr && c == vc) cr.fill ();
                    else cr.stroke ();
                }
            }
        }
    }

    public class WidthTool : Tool {
        private PathNode? target = null;
        private int point_index = -1;
        private double t0;

        public WidthTool () {
            base ("width", _("Width"), "vector-width-symbolic", "shift+w");
        }

        private PaintLayer? stroke_of (PathNode pn) {
            return pn.first_stroke ();
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var pn = canvas.hit_leaf (p) as PathNode;
            if (pn == null) return;
            var s = stroke_of (pn);
            if (s == null) return;
            var path = pn.render_path ();
            double total = PathOps.length (path);
            var h = PathOps.nearest (path, p, canvas.px (8) + s.width);
            if (h == null || total <= 0) return;
            double along = 0;
            var edges = PathOps.edges (path);
            int seg_index = 0;
            for (int i = 0; i < path.segs.size && i < h.segment; i++) if (path.segs[i].kind != SegKind.MOVE) seg_index++;
            for (int i = 0; i < edges.size && i < seg_index - 1; i++) along += edges[i].length ();
            if (seg_index - 1 >= 0 && seg_index - 1 < edges.size) {
                var e = edges[seg_index - 1];
                var bz = e.is_curve () ? Bezier (e.start, Point (e.segment.x1, e.segment.y1), Point (e.segment.x2, e.segment.y2), e.end ()) : Bezier.line (e.start, e.end ());
                along += bz.length_to (h.t);
            }
            t0 = (along / total).clamp (0, 1);
            target = pn;
            doc.begin (_("Width Point"));
            if (s.profile.size == 0) {
                s.profile.add (new WidthPoint (0, 1, 1));
                s.profile.add (new WidthPoint (1, 1, 1));
            }
            point_index = -1;
            for (int i = 0; i < s.profile.size; i++) if ((s.profile[i].t - t0).abs () < 0.03) point_index = i;
            if (point_index < 0) {
                double v = CurveOffset.profile_at (s.profile, t0, true);
                s.profile.add (new WidthPoint (t0, v, v));
                s.profile.sort ((a, b) => a.t < b.t ? -1 : a.t > b.t ? 1 : 0);
                for (int i = 0; i < s.profile.size; i++) if (s.profile[i].t == t0) point_index = i;
            }
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (target == null || point_index < 0) return;
            var s = stroke_of (target);
            var path = target.render_path ();
            Point c;
            double angle;
            PathOps.point_at (path, s.profile[point_index].t * PathOps.length (path), out c, out angle);
            double nx = -Math.sin (angle), ny = Math.cos (angle);
            double d = (p.x - c.x) * nx + (p.y - c.y) * ny;
            double f = (d.abs () * 2 / double.max (s.width, 0.01)).clamp (0, 50);
            if (alt (mods)) {
                if (d > 0) s.profile[point_index].right = f;
                else s.profile[point_index].left = f;
            } else {
                s.profile[point_index].left = f;
                s.profile[point_index].right = f;
            }
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (target != null) doc.commit ();
            target = null;
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            return false;
        }
    }

    public class EyedropperTool : Tool {
        public EyedropperTool () {
            base ("eyedropper", _("Eyedropper"), "vector-eyedropper-symbolic", "i");
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var hit = canvas.hit_leaf (p);
            if (hit == null) return;
            if (canvas.selection.size == 0 || shift (mods)) {
                var f = hit.first_fill ();
                if (f != null) canvas.style.fill = f.paint.copy ();
                var s = hit.first_stroke ();
                if (s != null) {
                    canvas.style.stroke = s.paint.copy ();
                    canvas.style.width = s.width;
                }
                canvas.selection_changed ();
                return;
            }
            doc.begin (_("Eyedropper"));
            foreach (var n in canvas.selection) {
                if (n == hit) continue;
                n.appearance.clear ();
                foreach (var l in hit.appearance) n.appearance.add (l.copy ());
                n.effects.clear ();
                foreach (var e in hit.effects) n.effects.add (e.copy ());
                n.opacity = hit.opacity;
                n.blend = hit.blend;
                var src = hit as TextNode;
                var dst = n as TextNode;
                if (src != null && dst != null) {
                    dst.style = src.style.copy ();
                    dst.para = src.para.copy ();
                }
            }
            doc.commit ();
        }
    }

    public class BlendTool : Tool {
        private Node? first = null;

        public BlendTool () {
            base ("blend", _("Blend"), "vector-blend-symbolic", "w");
        }

        public override void activate () {
            first = null;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            var hit = canvas.hit_root (p);
            if (hit == null) {
                first = null;
                return;
            }
            if (first == null || first == hit) {
                first = hit;
                canvas.select_only (hit);
                return;
            }
            var list = new Gee.ArrayList<Node> ();
            list.add (first);
            list.add (hit);
            canvas.set_selection (list);
            Commands.make_blend (canvas);
            first = null;
        }
    }

    public class TransformTool : Tool {
        private Point? origin = null;
        private Point start;
        private bool active = false;
        private Gee.ArrayList<Node> originals = new Gee.ArrayList<Node> ();

        public TransformTool (string id, string label, string icon, string key) {
            base (id, label, icon, key);
        }

        public override void activate () {
            origin = null;
        }

        private Point center () {
            if (origin != null) return origin;
            var b = canvas.selection_bounds ();
            return Point (b.cx (), b.cy ());
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            if (canvas.selection.size == 0) {
                var hit = canvas.hit_root (p);
                if (hit != null) canvas.select_only (hit);
                return;
            }
            start = p;
            active = true;
            originals.clear ();
            foreach (var n in canvas.selection) originals.add (n.clone ());
            doc.begin (label);
        }

        public override void double_click (Point p, Gdk.ModifierType mods) {
            origin = p;
        }

        private Cairo.Matrix matrix (Point p, Gdk.ModifierType mods) {
            var c = center ();
            switch (id) {
                case "rotate":
                    double a = Math.atan2 (p.y - c.y, p.x - c.x) - Math.atan2 (start.y - c.y, start.x - c.x);
                    if (shift (mods)) a = Math.round (a / (Math.PI / 4)) * (Math.PI / 4);
                    return Transforms.rotate (a, c);
                case "scale":
                    double sx = (start.x - c.x).abs () > 1e-6 ? (p.x - c.x) / (start.x - c.x) : 1;
                    double sy = (start.y - c.y).abs () > 1e-6 ? (p.y - c.y) / (start.y - c.y) : 1;
                    if (shift (mods)) sx = sy = Math.sqrt ((sx * sy).abs ());
                    return Transforms.scale (sx, sy, c);
                default:
                    double ang = Math.atan2 (p.y - c.y, p.x - c.x) * 180 / Math.PI;
                    if (shift (mods)) ang = Math.round (ang / 45) * 45;
                    return Transforms.reflect (ang, c);
            }
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (!active) return;
            var m = matrix (p, mods);
            for (int i = 0; i < canvas.selection.size; i++) {
                originals[i].clone ().copy_into (canvas.selection[i]);
                canvas.selection[i].apply_transform (m, canvas.scale_strokes);
            }
            doc.relink ();
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (!active) return;
            active = false;
            if (start.distance (p) < canvas.px (2)) {
                for (int i = 0; i < canvas.selection.size; i++) originals[i].clone ().copy_into (canvas.selection[i]);
                doc.relink ();
                doc.cancel ();
                origin = p;
                return;
            }
            if (alt (mods)) {
                var m = matrix (p, mods);
                for (int i = 0; i < canvas.selection.size; i++) originals[i].clone ().copy_into (canvas.selection[i]);
                var copies = new Gee.ArrayList<Node> ();
                foreach (var n in canvas.selection) {
                    var c = n.clone ();
                    c.id = "";
                    c.apply_transform (m, canvas.scale_strokes);
                    n.parent.add (c, n.parent.children.index_of (n) + 1);
                    copies.add (c);
                }
                doc.ensure_ids ();
                doc.commit ();
                canvas.set_selection (copies);
                return;
            }
            doc.commit ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (canvas.selection.size == 0) return;
            var c = center ();
            cr.set_source_rgba (0.2, 0.5, 0.95, 1);
            cr.set_line_width (canvas.px (1.2));
            cr.arc (c.x, c.y, canvas.px (5), 0, 2 * Math.PI);
            cr.move_to (c.x - canvas.px (9), c.y);
            cr.line_to (c.x + canvas.px (9), c.y);
            cr.move_to (c.x, c.y - canvas.px (9));
            cr.line_to (c.x, c.y + canvas.px (9));
            cr.stroke ();
        }
    }

    public class ArtboardTool : Tool {
        private Point start;
        private Point current;
        private Artboard? moving = null;
        private int handle = -1;
        private Rect start_rect;
        private bool creating = false;

        public ArtboardTool () {
            base ("artboard", _("Artboard"), "vector-artboard-symbolic", "shift+o");
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            current = p;
            for (int i = doc.artboards.size - 1; i >= 0; i--) {
                var a = doc.artboards[i];
                var hp = SelectTool.handle_points (a.rect ());
                for (int k = 0; k < hp.length; k++) {
                    if (hp[k].distance (p) < canvas.px (6)) {
                        moving = a;
                        handle = k;
                        start_rect = a.rect ();
                        doc.active_artboard = i;
                        doc.begin (_("Resize Artboard"));
                        return;
                    }
                }
                if (a.rect ().contains (p.x, p.y)) {
                    moving = a;
                    handle = -1;
                    start_rect = a.rect ();
                    doc.active_artboard = i;
                    doc.begin (alt (mods) ? _("Duplicate Artboard") : _("Move Artboard"));
                    if (alt (mods)) {
                        var copy = a.copy ();
                        copy.id = "";
                        copy.name = _("%s Copy").printf (a.name);
                        doc.add_artboard (copy);
                        moving = copy;
                        doc.active_artboard = doc.artboards.size - 1;
                    }
                    doc.structure_changed ();
                    return;
                }
            }
            creating = true;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = canvas.snap (p, null);
            if (moving == null) return;
            var r = start_rect;
            double dx = current.x - start.x, dy = current.y - start.y;
            if (handle < 0) {
                moving.x = r.x + dx;
                moving.y = r.y + dy;
            } else {
                double x1 = r.x, y1 = r.y, x2 = r.x + r.w, y2 = r.y + r.h;
                if (handle == 0 || handle == 6 || handle == 7) x1 = current.x;
                if (handle == 2 || handle == 3 || handle == 4) x2 = current.x;
                if (handle == 0 || handle == 1 || handle == 2) y1 = current.y;
                if (handle == 4 || handle == 5 || handle == 6) y2 = current.y;
                var nr = Rect.from_points (x1, y1, x2, y2);
                moving.x = nr.x;
                moving.y = nr.y;
                moving.w = double.max (nr.w, 1);
                moving.h = double.max (nr.h, 1);
            }
            doc.changed ();
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (moving != null) {
                doc.commit ();
                doc.structure_changed ();
                moving = null;
                return;
            }
            if (creating) {
                creating = false;
                var r = Rect.from_points (start.x, start.y, current.x, current.y);
                if (r.w < 4 || r.h < 4) return;
                doc.begin (_("New Artboard"));
                var a = new Artboard (_("Artboard %d").printf (doc.artboards.size + 1), r.x, r.y, r.w, r.h);
                doc.add_artboard (a);
                doc.active_artboard = doc.artboards.size - 1;
                doc.commit ();
                doc.structure_changed ();
            }
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            if ((keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) && doc.artboards.size > 1) {
                doc.begin (_("Delete Artboard"));
                doc.artboards.remove_at (doc.active_artboard.clamp (0, doc.artboards.size - 1));
                doc.active_artboard = 0;
                doc.commit ();
                doc.structure_changed ();
                return true;
            }
            return false;
        }

        public override void draw_overlay (Cairo.Context cr) {
            var a = doc.current_artboard ();
            if (a != null) {
                cr.set_source_rgba (0.2, 0.5, 0.95, 1);
                cr.set_line_width (canvas.px (1));
                foreach (var h in SelectTool.handle_points (a.rect ())) {
                    cr.rectangle (h.x - canvas.px (4), h.y - canvas.px (4), canvas.px (8), canvas.px (8));
                    cr.stroke ();
                }
            }
            if (creating) draw_rubber (cr, Rect.from_points (start.x, start.y, current.x, current.y));
        }
    }

    public class PerspectivePlane {
        public double[] h;
        public double[] inv;
        public double r;
        public double g;
        public double b;
        public string name;
    }

    public class Perspective {
        public static Point[] vanishing_points (PerspectiveGrid pg) {
            if (pg.points == 1) return { Point (pg.center_x, pg.horizon) };
            if (pg.points == 3) return { Point (pg.vp1x, pg.horizon), Point (pg.vp2x, pg.horizon), Point (pg.center_x, pg.vp3y) };
            return { Point (pg.vp1x, pg.horizon), Point (pg.vp2x, pg.horizon) };
        }

        private static PerspectivePlane plane (Point a, Point b, Point c, Point d, double r, double g, double bl, string name) {
            var p = new PerspectivePlane ();
            Point[] unit = { Point (0, 0), Point (1, 0), Point (1, 1), Point (0, 1) };
            Point[] quad = { a, b, c, d };
            p.h = Warp.homography (unit, quad);
            p.inv = Warp.homography (quad, unit);
            p.r = r;
            p.g = g;
            p.b = bl;
            p.name = name;
            return p;
        }

        private static Point toward (Point a, Point vp, double f) {
            return Point (a.x + (vp.x - a.x) * f, a.y + (vp.y - a.y) * f);
        }

        public static Gee.ArrayList<PerspectivePlane> planes (PerspectiveGrid pg) {
            var list = new Gee.ArrayList<PerspectivePlane> ();
            var base_pt = Point (pg.center_x, pg.ground);
            double height = (pg.ground - pg.horizon) * 1.4;
            var top = Point (pg.center_x, pg.ground - height);
            if (pg.points == 3) top = toward (base_pt, Point (pg.center_x, pg.vp3y), height / double.max ((pg.ground - pg.vp3y).abs (), 1));
            var vps = vanishing_points (pg);
            if (pg.points == 1) {
                var vp = vps[0];
                var bl = Point (pg.center_x - height, pg.ground);
                var br = Point (pg.center_x + height, pg.ground);
                list.add (plane (bl, br, toward (br, vp, 0.6), toward (bl, vp, 0.6), 0.2, 0.6, 0.2, "floor"));
                list.add (plane (bl, toward (bl, vp, 0.6), toward (Point (bl.x, top.y), vp, 0.6), Point (bl.x, top.y), 0.2, 0.3, 0.9, "left"));
                list.add (plane (br, toward (br, vp, 0.6), toward (Point (br.x, top.y), vp, 0.6), Point (br.x, top.y), 0.9, 0.4, 0.2, "right"));
                return list;
            }
            var vl = vps[0];
            var vr = vps[1];
            list.add (plane (base_pt, toward (base_pt, vl, 0.55), toward (top, vl, 0.55), top, 0.2, 0.3, 0.9, "left"));
            list.add (plane (base_pt, toward (base_pt, vr, 0.55), toward (top, vr, 0.55), top, 0.9, 0.4, 0.2, "right"));
            var fl = toward (base_pt, vl, 0.55);
            var fr = toward (base_pt, vr, 0.55);
            var far = intersect (fl, vr, fr, vl);
            list.add (plane (base_pt, fr, far, fl, 0.2, 0.6, 0.2, "floor"));
            return list;
        }

        private static Point intersect (Point a, Point b, Point c, Point d) {
            double den = (a.x - b.x) * (c.y - d.y) - (a.y - b.y) * (c.x - d.x);
            if (den.abs () < 1e-9) return PathOps.mix (b, d, 0.5);
            double t = ((a.x - c.x) * (c.y - d.y) - (a.y - c.y) * (c.x - d.x)) / den;
            return Point (a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
        }

        public static PerspectivePlane? plane_at (PerspectiveGrid pg, Point p) {
            foreach (var pl in planes (pg)) {
                var u = Warp.project (pl.inv, p);
                if (u.x >= -0.01 && u.x <= 1.01 && u.y >= -0.01 && u.y <= 1.01) return pl;
            }
            return null;
        }
    }

    public class PerspectiveTool : Tool {
        private PerspectivePlane? plane = null;
        private Point start_u;
        private Point current_u;
        private int vp_drag = -1;
        private Point start;

        public PerspectiveTool () {
            base ("perspective", _("Perspective Grid"), "vector-perspective-symbolic", "shift+p");
        }

        public override void activate () {
            if (!doc.perspective.visible) {
                doc.perspective.visible = true;
                var a = doc.current_artboard ();
                if (a != null) {
                    doc.perspective.horizon = a.y + a.h * 0.4;
                    doc.perspective.ground = a.y + a.h * 0.85;
                    doc.perspective.center_x = a.x + a.w / 2;
                    doc.perspective.vp1x = a.x - a.w * 0.3;
                    doc.perspective.vp2x = a.x + a.w * 1.3;
                    doc.perspective.vp3y = a.y - a.h * 1.5;
                }
                doc.changed ();
            }
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            var vps = Perspective.vanishing_points (doc.perspective);
            for (int i = 0; i < vps.length; i++) {
                if (vps[i].distance (p) < canvas.px (8)) {
                    vp_drag = i;
                    doc.begin (_("Move Vanishing Point"));
                    return;
                }
            }
            plane = Perspective.plane_at (doc.perspective, p);
            if (plane == null) return;
            start_u = Warp.project (plane.inv, p);
            current_u = start_u;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (vp_drag >= 0) {
                var pg = doc.perspective;
                if (pg.points == 1) {
                    pg.center_x = p.x;
                    pg.horizon = p.y;
                } else if (vp_drag == 0) {
                    pg.vp1x = p.x;
                    pg.horizon = p.y;
                } else if (vp_drag == 1) {
                    pg.vp2x = p.x;
                    pg.horizon = p.y;
                } else {
                    pg.vp3y = p.y;
                }
                doc.changed ();
                return;
            }
            if (plane != null) current_u = Warp.project (plane.inv, p);
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (vp_drag >= 0) {
                vp_drag = -1;
                doc.commit ();
                return;
            }
            if (plane == null) return;
            var r = Rect.from_points (start_u.x, start_u.y, current_u.x, current_u.y);
            if (r.w < 0.002 || r.h < 0.002) {
                plane = null;
                return;
            }
            var path = new PathData ();
            Point[] corners = { Point (r.x, r.y), Point (r.x + r.w, r.y), Point (r.x + r.w, r.y + r.h), Point (r.x, r.y + r.h) };
            for (int i = 0; i < 4; i++) {
                var q = Warp.project (plane.h, corners[i]);
                if (i == 0) path.move_to (q.x, q.y);
                else path.line_to (q.x, q.y);
            }
            path.close ();
            var node = new PathNode.with_path (path);
            canvas.style.apply (node);
            node.note = "perspective:" + plane.name;
            add_node (node, _("Perspective Rectangle"));
            plane = null;
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (plane == null) return;
            var r = Rect.from_points (start_u.x, start_u.y, current_u.x, current_u.y);
            Point[] corners = { Point (r.x, r.y), Point (r.x + r.w, r.y), Point (r.x + r.w, r.y + r.h), Point (r.x, r.y + r.h) };
            for (int i = 0; i < 4; i++) {
                var q = Warp.project (plane.h, corners[i]);
                if (i == 0) cr.move_to (q.x, q.y);
                else cr.line_to (q.x, q.y);
            }
            cr.close_path ();
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            cr.set_line_width (canvas.px (1.5));
            cr.stroke ();
        }
    }

    public class SymbolSprayerTool : Tool {
        public string symbol = "";
        private Point last;
        private Gee.ArrayList<Node> made = new Gee.ArrayList<Node> ();
        private GLib.Rand rand = new GLib.Rand.with_seed (5);
        public double density = 40;

        public SymbolSprayerTool () {
            base ("symbol-sprayer", _("Symbol Sprayer"), "vector-symbol-sprayer-symbolic", "shift+s");
        }

        private string current_symbol () {
            if (symbol != "" && doc.find_symbol (symbol) != null) return symbol;
            return doc.symbols.size > 0 ? doc.symbols[0].id : "";
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            made.clear ();
            if (current_symbol () == "") return;
            doc.begin (_("Spray Symbols"));
            last = p;
            spray (p);
        }

        private void spray (Point p) {
            var def = doc.find_symbol (current_symbol ());
            if (def == null) return;
            var box = def.art.geometric_bounds ();
            var s = new SymbolNode ();
            s.symbol = def.id;
            s.doc = doc;
            double jitter = density * 0.5;
            double scale = 0.7 + rand.next_double () * 0.6;
            var m = Transforms.translate (-box.cx (), -box.cy ());
            var sc = Cairo.Matrix.identity ();
            sc.scale (scale, scale);
            m = Transforms.multiply (m, sc);
            m = Transforms.multiply (m, Transforms.translate (p.x + (rand.next_double () * 2 - 1) * jitter, p.y + (rand.next_double () * 2 - 1) * jitter));
            s.matrix = m;
            target_group ().add (s);
            made.add (s);
            doc.ensure_ids ();
            doc.changed ();
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            if (made.size == 0) return;
            if (p.distance (last) > density) {
                spray (p);
                last = p;
            }
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (made.size == 0) return;
            {
                var group = new GroupNode ();
                group.name = _("Symbol Set");
                var parent = target_group ();
                int index = parent.children.index_of (made[0]);
                foreach (var n in made) parent.remove (n);
                foreach (var n in made) group.add (n);
                parent.add (group, index);
                doc.ensure_ids ();
                doc.commit ();
                canvas.select_only (group);
            }
            made.clear ();
        }
    }
}
