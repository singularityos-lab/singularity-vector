using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class DrawStyle : Object {
        public Paint fill = new Paint.hex ("#ffffff");
        public Paint stroke = new Paint.hex ("#000000");
        public double width = 1;
        public string brush = "";
        public CharStyle text = new CharStyle ();

        public void apply (Node n, bool with_fill = true) {
            n.appearance.clear ();
            if (with_fill) n.appearance.add (new PaintLayer.fill (fill.copy ()));
            var s = new PaintLayer.line (stroke.copy (), width);
            s.brush = brush;
            n.appearance.add (s);
        }
    }

    public abstract class Tool : Object {
        public weak VectorCanvas canvas;
        public string id;
        public string label;
        public string icon;
        public string shortcut;

        protected Tool (string id, string label, string icon, string shortcut) {
            this.id = id;
            this.label = label;
            this.icon = icon;
            this.shortcut = shortcut;
        }

        public VectorDocument doc {
            get {
                return canvas.doc;
            }
        }

        public virtual void activate () {
        }

        public virtual void deactivate () {
        }

        public virtual void press (Point p, Gdk.ModifierType mods) {
        }

        public virtual void drag (Point p, Gdk.ModifierType mods) {
        }

        public virtual void release (Point p, Gdk.ModifierType mods) {
        }

        public virtual void motion (Point p, Gdk.ModifierType mods) {
        }

        public virtual void double_click (Point p, Gdk.ModifierType mods) {
        }

        public virtual bool key (uint keyval, Gdk.ModifierType mods) {
            return false;
        }

        public virtual void draw_overlay (Cairo.Context cr) {
        }

        public virtual string? cursor_name () {
            return "crosshair";
        }

        public virtual bool shows_anchors () {
            return false;
        }

        public virtual bool wants_hover () {
            return false;
        }

        public virtual Gtk.Widget? options () {
            return null;
        }

        protected static bool shift (Gdk.ModifierType m) {
            return (m & Gdk.ModifierType.SHIFT_MASK) != 0;
        }

        protected static bool alt (Gdk.ModifierType m) {
            return (m & Gdk.ModifierType.ALT_MASK) != 0;
        }

        protected static bool ctrl (Gdk.ModifierType m) {
            return (m & Gdk.ModifierType.CONTROL_MASK) != 0;
        }

        public static Point constrain (Point origin, Point p) {
            double dx = p.x - origin.x, dy = p.y - origin.y;
            double a = Math.round (Math.atan2 (dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
            double len = Math.hypot (dx, dy) * Math.cos (Math.atan2 (dy, dx) - a);
            return Point (origin.x + Math.cos (a) * len, origin.y + Math.sin (a) * len);
        }

        public GroupNode target_group () {
            if (canvas.isolation != null) return canvas.isolation;
            if (doc.active_layer == null || !doc.has_layer (doc.active_layer)) {
                if (doc.layers.size == 0) {
                    var l = doc.new_layer (_("Layer 1"));
                    doc.layers.add (l);
                }
                doc.active_layer = doc.layers[doc.layers.size - 1];
            }
            return doc.active_layer;
        }

        public void add_node (Node n, string label, bool select = true) {
            doc.begin (label);
            target_group ().add (n);
            doc.ensure_ids ();
            doc.commit ();
            if (select) canvas.select_only (n);
        }

        protected void draw_rubber (Cairo.Context cr, Rect r) {
            cr.rectangle (r.x, r.y, r.w, r.h);
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.12);
            cr.fill_preserve ();
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            cr.set_line_width (canvas.px (1));
            cr.stroke ();
        }
    }

    public class Tools {
        public static void register_all (VectorCanvas c) {
            Tool[] list = {
                new SelectTool (), new DirectTool (), new LassoTool (), new PenTool (), new CurvatureTool (), new PencilTool (), new PaintbrushTool (), new BlobBrushTool (),
                new ShapeTool ("rectangle", _("Rectangle"), "vector-rectangle-symbolic", "m"), new ShapeTool ("rounded", _("Rounded Rectangle"), "vector-rounded-symbolic", ""),
                new ShapeTool ("ellipse", _("Ellipse"), "vector-ellipse-symbolic", "l"), new ShapeTool ("polygon", _("Polygon"), "vector-polygon-symbolic", ""),
                new ShapeTool ("star", _("Star"), "vector-star-symbolic", ""), new ShapeTool ("line", _("Line Segment"), "vector-line-symbolic", "backslash"),
                new TextTool (), new ScissorsTool (), new KnifeTool (), new EraserTool (), new ShapeBuilderTool (), new LivePaintTool (), new GradientTool (), new MeshTool (),
                new WidthTool (), new EyedropperTool (), new BlendTool (), new TransformTool ("rotate", _("Rotate"), "vector-rotate-symbolic", "r"),
                new TransformTool ("scale", _("Scale"), "vector-scale-symbolic", "s"), new TransformTool ("reflect", _("Reflect"), "vector-reflect-symbolic", "o"),
                new ArtboardTool (), new PerspectiveTool (), new SymbolSprayerTool (), new HandTool (), new ZoomTool ()
            };
            foreach (var t in list) {
                t.canvas = c;
                c.tools[t.id] = t;
            }
        }

        public static string[] order () {
            return { "select", "direct", "lasso", "pen", "curvature", "pencil", "paintbrush", "blob", "rectangle", "rounded", "ellipse", "polygon", "star", "line", "text",
                "scissors", "knife", "eraser", "shape-builder", "live-paint", "gradient", "mesh", "width", "eyedropper", "blend", "rotate", "scale", "reflect",
                "artboard", "perspective", "symbol-sprayer", "hand", "zoom" };
        }
    }

    public class SelectTool : Tool {
        private enum Mode { NONE, MOVE, SCALE, ROTATE, MARQUEE, CORNER }
        private Mode mode = Mode.NONE;
        private Point start;
        private Point current;
        private int handle = -1;
        private Rect start_box;
        private Gee.ArrayList<Node> originals = new Gee.ArrayList<Node> ();
        private double start_angle;

        public SelectTool () {
            base ("select", _("Selection"), "vector-select-symbolic", "v");
        }

        public override string? cursor_name () {
            return "default";
        }

        public static Point[] handle_points (Rect b) {
            return { Point (b.x, b.y), Point (b.cx (), b.y), Point (b.x + b.w, b.y), Point (b.x + b.w, b.cy ()),
                Point (b.x + b.w, b.y + b.h), Point (b.cx (), b.y + b.h), Point (b.x, b.y + b.h), Point (b.x, b.cy ()) };
        }

        public static Point[] corner_widgets (PathNode pn) {
            var b = pn.geometric_bounds ();
            double r = pn.live != null ? pn.live.radius : 0;
            double inset = double.max (r, double.min (b.w, b.h) * 0.12);
            inset = double.min (inset, double.min (b.w, b.h) / 2);
            return { Point (b.x + inset, b.y + inset) };
        }

        private void snapshot () {
            originals.clear ();
            foreach (var n in canvas.selection) originals.add (n.clone ());
        }

        private void restore () {
            for (int i = 0; i < canvas.selection.size && i < originals.size; i++) originals[i].clone ().copy_into (canvas.selection[i]);
            foreach (var n in canvas.selection) {
                var g = n as GroupNode;
                if (g != null) foreach (var c in g.children) c.parent = g;
            }
            doc.relink ();
        }

        private void apply_all (Cairo.Matrix m) {
            restore ();
            foreach (var n in canvas.selection) n.apply_transform (m, canvas.scale_strokes);
            doc.changed ();
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            current = p;
            var b = canvas.selection_bounds ();
            start_box = b;
            if (canvas.selection.size > 0 && b.w >= 0) {
                if (canvas.selection.size == 1) {
                    var pn = canvas.selection[0] as PathNode;
                    if (pn != null && pn.live != null && pn.live.kind != "line" && pn.live.kind != "ellipse") {
                        foreach (var w in corner_widgets (pn)) {
                            if (w.distance (p) < canvas.px (6)) {
                                mode = Mode.CORNER;
                                doc.begin (_("Round Corners"));
                                snapshot ();
                                return;
                            }
                        }
                    }
                }
                var hp = handle_points (b);
                for (int i = 0; i < hp.length; i++) {
                    if (hp[i].distance (p) < canvas.px (6)) {
                        mode = Mode.SCALE;
                        handle = i;
                        doc.begin (_("Scale"));
                        snapshot ();
                        return;
                    }
                }
                for (int i = 0; i < hp.length; i += 2) {
                    double d = hp[i].distance (p);
                    if (d < canvas.px (22) && !b.contains (p.x, p.y)) {
                        mode = Mode.ROTATE;
                        start_angle = Math.atan2 (p.y - b.cy (), p.x - b.cx ());
                        doc.begin (_("Rotate"));
                        snapshot ();
                        return;
                    }
                }
            }
            var hit = canvas.hit_root (p);
            if (hit != null) {
                if (shift (mods)) {
                    canvas.toggle_selection (hit);
                    mode = Mode.NONE;
                    return;
                }
                if (!canvas.selection.contains (hit)) canvas.select_only (hit);
                mode = Mode.MOVE;
                doc.begin (alt (mods) ? _("Duplicate") : _("Move"));
                if (alt (mods)) {
                    var copies = new Gee.ArrayList<Node> ();
                    foreach (var n in canvas.selection) {
                        var c = n.clone ();
                        c.id = "";
                        var parent = n.parent;
                        if (parent != null) parent.add (c, parent.children.index_of (n) + 1);
                        copies.add (c);
                    }
                    doc.ensure_ids ();
                    canvas.set_selection (copies);
                }
                start_box = canvas.selection_bounds ();
                snapshot ();
                return;
            }
            if (!shift (mods)) canvas.clear_selection ();
            mode = Mode.MARQUEE;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = p;
            switch (mode) {
                case Mode.MOVE: {
                    var target = shift (mods) ? constrain (start, p) : p;
                    var anchor = Point (start_box.x + (target.x - start.x), start_box.y + (target.y - start.y));
                    var snapped = canvas.snap (anchor, canvas.selection);
                    var center = Point (start_box.cx () + (target.x - start.x), start_box.cy () + (target.y - start.y));
                    var snapped_c = canvas.snap (center, canvas.selection, false);
                    double dx = snapped.x - start_box.x, dy = snapped.y - start_box.y;
                    if ((snapped_c.x - center.x).abs () > 1e-9 && (snapped.x - anchor.x).abs () < 1e-9) dx = snapped_c.x - start_box.cx ();
                    if ((snapped_c.y - center.y).abs () > 1e-9 && (snapped.y - anchor.y).abs () < 1e-9) dy = snapped_c.y - start_box.cy ();
                    apply_all (Transforms.translate (dx, dy));
                    break;
                }
                case Mode.SCALE: {
                    var b = start_box;
                    var hp = handle_points (b);
                    var opposite = hp[(handle + 4) % 8];
                    if (alt (mods)) opposite = Point (b.cx (), b.cy ());
                    var q = canvas.snap (p, canvas.selection);
                    double sx = 1, sy = 1;
                    var h = hp[handle];
                    if ((h.x - opposite.x).abs () > 1e-9 && handle != 1 && handle != 5) sx = (q.x - opposite.x) / (h.x - opposite.x);
                    if ((h.y - opposite.y).abs () > 1e-9 && handle != 3 && handle != 7) sy = (q.y - opposite.y) / (h.y - opposite.y);
                    if (shift (mods)) {
                        if (handle == 1 || handle == 5) sx = sy.abs () * (sx < 0 ? -1 : 1);
                        else if (handle == 3 || handle == 7) sy = sx.abs () * (sy < 0 ? -1 : 1);
                        else {
                            double s = double.max (sx.abs (), sy.abs ());
                            sx = s * (sx < 0 ? -1 : 1);
                            sy = s * (sy < 0 ? -1 : 1);
                        }
                    }
                    if (sx.abs () < 1e-4) sx = 1e-4;
                    if (sy.abs () < 1e-4) sy = 1e-4;
                    apply_all (Transforms.scale (sx, sy, opposite));
                    break;
                }
                case Mode.ROTATE: {
                    var c = Point (start_box.cx (), start_box.cy ());
                    double a = Math.atan2 (p.y - c.y, p.x - c.x) - start_angle;
                    if (shift (mods)) a = Math.round (a / (Math.PI / 4)) * (Math.PI / 4);
                    apply_all (Transforms.rotate (a, c));
                    break;
                }
                case Mode.CORNER: {
                    restore ();
                    var pn = canvas.selection[0] as PathNode;
                    var b = pn.geometric_bounds ();
                    double r = double.max (0, double.min (p.x - b.x, p.y - b.y));
                    r = double.min (r, double.min (b.w, b.h) / 2);
                    pn.live.radius = r;
                    pn.rebuild_live ();
                    doc.changed ();
                    break;
                }
                default:
                    break;
            }
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            switch (mode) {
                case Mode.MOVE:
                case Mode.SCALE:
                case Mode.ROTATE:
                case Mode.CORNER:
                    if (start.distance (p) < canvas.px (1) && mode == Mode.MOVE) {
                        restore ();
                        doc.cancel ();
                        if (alt (mods)) doc.changed ();
                    } else {
                        doc.commit ();
                    }
                    canvas.selection_changed ();
                    break;
                case Mode.MARQUEE:
                    var r = Rect.from_points (start.x, start.y, p.x, p.y);
                    if (r.w > canvas.px (2) || r.h > canvas.px (2)) {
                        var list = canvas.nodes_in_rect (r);
                        if (shift (mods)) {
                            foreach (var n in list) if (!canvas.selection.contains (n)) canvas.selection.add (n);
                            canvas.selection_changed ();
                        } else {
                            canvas.set_selection (list);
                        }
                    }
                    break;
                default:
                    break;
            }
            mode = Mode.NONE;
            originals.clear ();
        }

        public override void double_click (Point p, Gdk.ModifierType mods) {
            var hit = canvas.hit_root (p);
            var g = hit as GroupNode;
            if (g != null && !(g is ChartNode) && !(g is Shape3DNode)) {
                canvas.isolation = g;
                canvas.clear_selection ();
                canvas.queue_draw ();
                return;
            }
            var t = hit as TextNode;
            if (t != null) {
                canvas.select_only (t);
                canvas.text_edit_requested (t, false);
                return;
            }
            if (hit == null && canvas.isolation != null) {
                canvas.isolation = null;
                canvas.queue_draw ();
            }
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (mode == Mode.MARQUEE) draw_rubber (cr, Rect.from_points (start.x, start.y, current.x, current.y));
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            return false;
        }
    }

    public class DirectTool : Tool {
        private enum Mode { NONE, ANCHORS, HANDLE, MARQUEE, ENVELOPE }
        private EnvelopeNode? envelope = null;
        private int envelope_point = -1;
        private bool envelope_quad = false;
        private Mode mode = Mode.NONE;
        private Point start;
        private Point current;
        private Point last;
        private PathNode? handle_node;
        private int handle_seg;
        private int handle_which;

        public DirectTool () {
            base ("direct", _("Direct Selection"), "vector-direct-symbolic", "a");
        }

        public override string? cursor_name () {
            return "default";
        }

        public override bool shows_anchors () {
            return true;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            current = p;
            last = p;
            foreach (var n in canvas.selection) {
                var ev = n as EnvelopeNode;
                if (ev == null) continue;
                Point[] pts = ev.mode == "distort" ? ev.quad : ev.grid;
                for (int i = 0; i < pts.length; i++) {
                    if (pts[i].distance (p) < canvas.px (6)) {
                        envelope = ev;
                        envelope_point = i;
                        envelope_quad = ev.mode == "distort";
                        mode = Mode.ENVELOPE;
                        doc.begin (_("Edit Envelope"));
                        return;
                    }
                }
            }
            PathNode? node;
            int seg, which;
            if (PathEdit.hit_handle (canvas, p, out node, out seg, out which)) {
                mode = Mode.HANDLE;
                handle_node = node;
                handle_seg = seg;
                handle_which = which;
                doc.begin (_("Move Handle"));
                return;
            }
            int index;
            var candidates = PathEdit.editable_paths (canvas);
            var leaf = canvas.hit_leaf (p) as PathNode;
            if (leaf != null && !candidates.contains (leaf)) candidates.add (leaf);
            if (PathEdit.hit_anchor (canvas, candidates, p, out node, out index)) {
                if (!canvas.anchors.has_key (node)) canvas.anchors[node] = new Gee.TreeSet<int> ();
                if (shift (mods)) {
                    if (canvas.anchors[node].contains (index)) canvas.anchors[node].remove (index);
                    else canvas.anchors[node].add (index);
                } else if (!canvas.anchors[node].contains (index)) {
                    canvas.anchors.clear ();
                    canvas.anchors[node] = new Gee.TreeSet<int> ();
                    canvas.anchors[node].add (index);
                }
                if (!canvas.selection.contains (node)) {
                    if (!shift (mods)) canvas.selection.clear ();
                    canvas.selection.add (node);
                }
                canvas.selection_changed ();
                mode = Mode.ANCHORS;
                doc.begin (_("Move Points"));
                return;
            }
            var hit = canvas.hit_leaf (p);
            if (hit != null) {
                if (!shift (mods)) canvas.anchors.clear ();
                var pn = hit as PathNode;
                if (pn != null) {
                    var h = PathOps.nearest (pn.path, p, canvas.px (6));
                    var set = new Gee.TreeSet<int> ();
                    if (h != null && pn.path.segs[h.segment].kind != SegKind.MOVE) {
                        set.add (h.segment);
                        set.add (h.segment - 1);
                        canvas.anchors[pn] = set;
                    }
                }
                if (!shift (mods)) canvas.selection.clear ();
                if (!canvas.selection.contains (hit)) canvas.selection.add (hit);
                canvas.selection_changed ();
                mode = pn != null && canvas.anchors.has_key (pn) ? Mode.ANCHORS : Mode.NONE;
                if (mode == Mode.ANCHORS) doc.begin (_("Move Segment"));
                else {
                    mode = Mode.ANCHORS;
                    doc.begin (_("Move"));
                }
                return;
            }
            if (!shift (mods)) {
                canvas.anchors.clear ();
                canvas.clear_selection ();
            }
            mode = Mode.MARQUEE;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = p;
            if (mode == Mode.ENVELOPE && envelope != null) {
                var q = canvas.snap (p, null);
                if (envelope_quad) envelope.quad[envelope_point] = q;
                else envelope.grid[envelope_point] = q;
                doc.changed ();
                return;
            }
            if (mode == Mode.HANDLE) {
                var q = shift (mods) ? constrain (anchor_point (), p) : canvas.snap (p, null);
                PathEdit.move_handle (handle_node, handle_seg, handle_which, q, alt (mods));
                doc.changed ();
                return;
            }
            if (mode == Mode.ANCHORS) {
                var target = shift (mods) ? constrain (start, p) : p;
                var q = canvas.snap (target, null);
                double dx = q.x - last.x, dy = q.y - last.y;
                last = q;
                if (canvas.anchors.size > 0) {
                    foreach (var e in canvas.anchors.entries) PathEdit.move_anchors (e.key, e.value, dx, dy);
                } else {
                    var m = Transforms.translate (dx, dy);
                    foreach (var n in canvas.selection) n.apply_transform (m, canvas.scale_strokes);
                }
                doc.changed ();
            }
        }

        private Point anchor_point () {
            int a = handle_which == 1 ? handle_seg - 1 : handle_seg;
            var s = handle_node.path.segs[a];
            return Point (s.x, s.y);
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (mode == Mode.HANDLE || mode == Mode.ANCHORS || mode == Mode.ENVELOPE) {
                if (start.distance (p) < canvas.px (0.5)) doc.cancel ();
                else doc.commit ();
                envelope = null;
            } else if (mode == Mode.MARQUEE) {
                var r = Rect.from_points (start.x, start.y, p.x, p.y);
                select_anchors_in ((q) => r.contains (q.x, q.y), shift (mods));
            }
            mode = Mode.NONE;
        }

        public delegate bool PointTest (Point p);

        public void select_anchors_in (PointTest test, bool add) {
            if (!add) {
                canvas.anchors.clear ();
                canvas.selection.clear ();
            }
            foreach (var n in canvas.candidate_nodes (null)) {
                var pn = n as PathNode;
                if (pn == null || pn.effectively_locked ()) continue;
                foreach (int a in PathOps.anchors (pn.path)) {
                    if (!test (Point (pn.path.segs[a].x, pn.path.segs[a].y))) continue;
                    if (!canvas.anchors.has_key (pn)) canvas.anchors[pn] = new Gee.TreeSet<int> ();
                    canvas.anchors[pn].add (a);
                    if (!canvas.selection.contains (pn)) canvas.selection.add (pn);
                }
            }
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (mode == Mode.MARQUEE) draw_rubber (cr, Rect.from_points (start.x, start.y, current.x, current.y));
            foreach (var n in canvas.selection) {
                var ev = n as EnvelopeNode;
                if (ev == null) continue;
                cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
                cr.set_line_width (canvas.px (1));
                if (ev.mode == "distort" && ev.quad.length == 4) {
                    cr.move_to (ev.quad[0].x, ev.quad[0].y);
                    for (int i = 1; i < 4; i++) cr.line_to (ev.quad[i].x, ev.quad[i].y);
                    cr.close_path ();
                    cr.stroke ();
                    foreach (var q in ev.quad) {
                        cr.rectangle (q.x - canvas.px (4), q.y - canvas.px (4), canvas.px (8), canvas.px (8));
                        cr.fill ();
                    }
                } else if (ev.mode == "mesh" && ev.grid.length == (ev.mesh_rows + 1) * (ev.mesh_cols + 1)) {
                    for (int r = 0; r <= ev.mesh_rows; r++) {
                        for (int c = 0; c <= ev.mesh_cols; c++) {
                            var q = ev.grid[r * (ev.mesh_cols + 1) + c];
                            if (c < ev.mesh_cols) {
                                var q2 = ev.grid[r * (ev.mesh_cols + 1) + c + 1];
                                cr.move_to (q.x, q.y);
                                cr.line_to (q2.x, q2.y);
                            }
                            if (r < ev.mesh_rows) {
                                var q3 = ev.grid[(r + 1) * (ev.mesh_cols + 1) + c];
                                cr.move_to (q.x, q.y);
                                cr.line_to (q3.x, q3.y);
                            }
                        }
                    }
                    cr.stroke ();
                    foreach (var q in ev.grid) {
                        cr.rectangle (q.x - canvas.px (3.5), q.y - canvas.px (3.5), canvas.px (7), canvas.px (7));
                        cr.fill ();
                    }
                }
            }
        }

        public override bool key (uint keyval, Gdk.ModifierType mods) {
            if ((keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) && canvas.anchors.size > 0) {
                doc.begin (_("Delete Points"));
                foreach (var e in canvas.anchors.entries) {
                    PathEdit.detach_live (e.key);
                    var list = new Gee.ArrayList<int> ();
                    list.add_all (e.value);
                    list.sort ((a, b) => b - a);
                    foreach (int a in list) e.key.path = PathOps.remove_anchor (e.key.path, a);
                    if (e.key.path.is_empty () && e.key.parent != null) e.key.parent.remove (e.key);
                }
                canvas.anchors.clear ();
                doc.commit ();
                return true;
            }
            return false;
        }
    }

    public class LassoTool : Tool {
        private Point[] trail = {};

        public LassoTool () {
            base ("lasso", _("Lasso"), "vector-lasso-symbolic", "q");
        }

        public override bool shows_anchors () {
            return true;
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            trail = { p };
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            trail += p;
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            if (trail.length < 3) {
                trail = {};
                return;
            }
            var poly = PathOps.polygon_path (trail, true);
            var direct = canvas.tools["direct"] as DirectTool;
            direct.select_anchors_in ((q) => PathOps.contains (poly, q), shift (mods));
            trail = {};
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (trail.length < 2) return;
            cr.move_to (trail[0].x, trail[0].y);
            foreach (var p in trail) cr.line_to (p.x, p.y);
            cr.set_source_rgba (0.2, 0.5, 0.95, 0.9);
            cr.set_line_width (canvas.px (1));
            cr.set_dash ({ canvas.px (4), canvas.px (3) }, 0);
            cr.stroke ();
            cr.set_dash (null, 0);
        }
    }

    public class HandTool : Tool {
        private Point start;
        private double ox;
        private double oy;

        public HandTool () {
            base ("hand", _("Hand"), "vector-hand-symbolic", "h");
        }

        public override string? cursor_name () {
            return "grab";
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = canvas.to_screen (p);
            ox = canvas.ox;
            oy = canvas.oy;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            var s = Point ((p.x - canvas.ox) * canvas.zoom, (p.y - canvas.oy) * canvas.zoom);
            canvas.ox = ox - (s.x - start.x) / canvas.zoom;
            canvas.oy = oy - (s.y - start.y) / canvas.zoom;
            start = Point ((p.x - canvas.ox) * canvas.zoom, (p.y - canvas.oy) * canvas.zoom);
            ox = canvas.ox;
            oy = canvas.oy;
            canvas.view_changed ();
        }
    }

    public class ZoomTool : Tool {
        private Point start;
        private Point current;
        private bool dragging = false;

        public ZoomTool () {
            base ("zoom", _("Zoom"), "vector-zoom-symbolic", "z");
        }

        public override string? cursor_name () {
            return "zoom-in";
        }

        public override void press (Point p, Gdk.ModifierType mods) {
            start = p;
            current = p;
            dragging = true;
        }

        public override void drag (Point p, Gdk.ModifierType mods) {
            current = p;
        }

        public override void release (Point p, Gdk.ModifierType mods) {
            dragging = false;
            var r = Rect.from_points (start.x, start.y, p.x, p.y);
            if (r.w > canvas.px (6) && r.h > canvas.px (6) && !alt (mods)) {
                canvas.fit_rect (r, 8);
                return;
            }
            canvas.zoom_at (p, alt (mods) ? 1 / 1.5 : 1.5);
        }

        public override void draw_overlay (Cairo.Context cr) {
            if (dragging) draw_rubber (cr, Rect.from_points (start.x, start.y, current.x, current.y));
        }
    }
}
