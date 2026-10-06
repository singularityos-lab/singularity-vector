using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class SnapHint {
        public Point a;
        public Point b;
        public string label;

        public SnapHint (Point a, Point b, string label = "") {
            this.a = a;
            this.b = b;
            this.label = label;
        }
    }

    public class VectorCanvas : Gtk.DrawingArea {
        public const int RULER = CanvasRulers.SIZE;
        public CanvasRulers rulers;
        public VectorDocument doc;
        public double zoom = 1;
        public double ox = -40;
        public double oy = -40;
        public Gee.ArrayList<Node> selection = new Gee.ArrayList<Node> ();
        public Gee.HashMap<PathNode, Gee.TreeSet<int>> anchors = new Gee.HashMap<PathNode, Gee.TreeSet<int>> ();
        public GroupNode? isolation = null;
        public Tool tool;
        public Gee.HashMap<string, Tool> tools = new Gee.HashMap<string, Tool> ();
        public bool show_grid = false;
        public bool snap_grid = false;
        public bool snap_pixel = false;
        public bool smart_guides = true;
        public bool snap_points = true;
        public bool show_rulers = true;
        public bool outline_mode = false;
        public bool show_edges = true;
        public bool scale_strokes = true;
        public double nudge = 1;
        public DrawStyle style = new DrawStyle ();
        public Gee.ArrayList<SnapHint> hints = new Gee.ArrayList<SnapHint> ();
        public Point pointer = Point (0, 0);
        public Gdk.ModifierType mods = 0;
        private Tool? held_tool = null;
        private bool space_down = false;
        private double drag_start_x;
        private double drag_start_y;
        private bool dragging_guide = false;
        private Guide? moving_guide = null;
        public bool dark = false;

        public signal void selection_changed ();
        public signal void tool_changed ();
        public signal void view_changed ();
        public signal void pointer_moved ();
        public signal void text_edit_requested (TextNode node, bool fresh);
        public signal void context_requested (double x, double y);

        public VectorCanvas (VectorDocument doc) {
            this.doc = doc;
            rulers = new CanvasRulers (this);
            resize.connect ((w, h) => {
                if (fit_pending && w >= 200 && h >= 200) {
                    fit_pending = false;
                    fit_artboard ();
                }
            });
            hexpand = true;
            vexpand = true;
            focusable = true;
            can_focus = true;
            set_draw_func (draw);
            Tools.register_all (this);
            tool = tools["select"];
            var drag = new Gtk.GestureDrag ();
            drag.button = 0;
            drag.drag_begin.connect (on_drag_begin);
            drag.drag_update.connect (on_drag_update);
            drag.drag_end.connect (on_drag_end);
            add_controller (drag);
            var click = new Gtk.GestureClick ();
            click.button = 0;
            click.pressed.connect ((n, x, y) => {
                grab_focus ();
                if (click.get_current_button () == 3) {
                    context_requested (x, y);
                    return;
                }
                if (n >= 2) tool.double_click (to_doc (x, y), mods);
            });
            add_controller (click);
            var motion = new Gtk.EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                mods = motion.get_current_event_state ();
                pointer = to_doc (x, y);
                tool.motion (pointer, mods);
                pointer_moved ();
                if (tool.wants_hover ()) queue_draw ();
            });
            add_controller (motion);
            var scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
            scroll.scroll.connect ((dx, dy) => {
                var state = scroll.get_current_event_state ();
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    zoom_at (pointer, dy < 0 ? 1.15 : 1 / 1.15);
                } else if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    ox += dy * 30 / zoom;
                } else {
                    ox += dx * 30 / zoom;
                    oy += dy * 30 / zoom;
                }
                queue_draw ();
                view_changed ();
                return true;
            });
            add_controller (scroll);
            var zoom_gesture = new Gtk.GestureZoom ();
            double base_zoom = 1;
            zoom_gesture.begin.connect (() => base_zoom = zoom);
            zoom_gesture.scale_changed.connect ((s) => {
                double target = (base_zoom * s).clamp (0.02, 64);
                zoom_at (pointer, target / zoom);
            });
            add_controller (zoom_gesture);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect (on_key);
            keys.key_released.connect ((keyval, code, state) => {
                mods = state;
                if (keyval == Gdk.Key.space && space_down) {
                    space_down = false;
                    if (held_tool != null) {
                        set_tool_object (held_tool);
                        held_tool = null;
                    }
                }
            });
            add_controller (keys);
            doc.changed.connect (() => {
                prune_selection ();
                queue_draw ();
            });
        }

        public Point to_doc (double x, double y) {
            return Point (x / zoom + ox, y / zoom + oy);
        }

        public Point to_screen (Point p) {
            return Point ((p.x - ox) * zoom, (p.y - oy) * zoom);
        }

        public double px (double screen_pixels = 1) {
            return screen_pixels / zoom;
        }

        public void zoom_at (Point doc_point, double factor) {
            double nz = (zoom * factor).clamp (0.02, 64);
            var s = to_screen (doc_point);
            zoom = nz;
            ox = doc_point.x - s.x / zoom;
            oy = doc_point.y - s.y / zoom;
            queue_draw ();
            view_changed ();
        }

        public void set_zoom (double z) {
            var c = to_doc (get_width () / 2.0, get_height () / 2.0);
            zoom_at (c, z / zoom);
        }

        public void fit_rect (Rect r, double margin = 48) {
            double w = double.max (get_width () - margin * 2 - RULER, 50), h = double.max (get_height () - margin * 2 - RULER, 50);
            if (r.w <= 0 || r.h <= 0) return;
            w -= 120;
            zoom = double.min (w / r.w, h / r.h).clamp (0.02, 64);
            ox = r.cx () - (get_width () + RULER + 120) / 2.0 / zoom;
            oy = r.cy () - (get_height () - RULER) / 2.0 / zoom;
            queue_draw ();
            view_changed ();
        }

        private bool fit_pending = false;

        public void fit_artboard () {
            if (get_width () < 200 || get_height () < 200) {
                fit_pending = true;
                return;
            }
            var a = doc.current_artboard ();
            if (a != null) fit_rect (a.rect ());
        }

        public void fit_all () {
            Rect box = Rect (0, 0, -1, -1);
            bool first = true;
            foreach (var a in doc.artboards) {
                box = first ? a.rect () : box.union (a.rect ());
                first = false;
            }
            var c = doc.content_bounds ();
            if (c.w >= 0) box = first ? c : box.union (c);
            fit_rect (box);
        }

        public void set_tool (string id) {
            if (!tools.has_key (id)) return;
            set_tool_object (tools[id]);
        }

        private void set_tool_object (Tool t) {
            if (tool == t) return;
            tool.deactivate ();
            tool = t;
            tool.activate ();
            hints.clear ();
            update_cursor ();
            tool_changed ();
            queue_draw ();
        }

        public void update_cursor () {
            string? name = tool.cursor_name ();
            set_cursor_from_name (name ?? "default");
        }

        public void select_only (Node? n) {
            selection.clear ();
            anchors.clear ();
            if (n != null) selection.add (n);
            selection_changed ();
            queue_draw ();
        }

        public void set_selection (Gee.Collection<Node> nodes) {
            selection.clear ();
            anchors.clear ();
            selection.add_all (nodes);
            selection_changed ();
            queue_draw ();
        }

        public void toggle_selection (Node n) {
            if (selection.contains (n)) selection.remove (n);
            else selection.add (n);
            selection_changed ();
            queue_draw ();
        }

        public void clear_selection () {
            if (selection.size == 0 && anchors.size == 0) return;
            selection.clear ();
            anchors.clear ();
            selection_changed ();
            queue_draw ();
        }

        private void prune_selection () {
            bool changed = false;
            var all = new Gee.HashSet<Node> ();
            foreach (var n in doc.all_nodes ()) all.add (n);
            foreach (var l in doc.layers) all.add (l);
            for (int i = selection.size - 1; i >= 0; i--) {
                if (!all.contains (selection[i])) {
                    var replacement = doc.find (selection[i].id);
                    if (replacement != null) selection[i] = replacement;
                    else selection.remove_at (i);
                    changed = true;
                }
            }
            var stale = new Gee.ArrayList<PathNode> ();
            foreach (var k in anchors.keys) if (!all.contains (k)) stale.add (k);
            if (stale.size > 0) {
                var moved = new Gee.HashMap<PathNode, Gee.TreeSet<int>> ();
                foreach (var k in stale) {
                    var r = doc.find (k.id) as PathNode;
                    if (r != null) moved[r] = anchors[k];
                    anchors.unset (k);
                }
                foreach (var e in moved.entries) anchors[e.key] = e.value;
                changed = true;
            }
            if (isolation != null && !all.contains (isolation)) isolation = doc.find (isolation.id) as GroupNode;
            if (changed) selection_changed ();
        }

        public Rect selection_bounds (bool visual = false) {
            var box = Rect (0, 0, -1, -1);
            bool first = true;
            foreach (var n in selection) {
                var b = visual ? n.visual_bounds () : n.geometric_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            return box;
        }

        public Gee.ArrayList<Node> selectable_roots () {
            var list = new Gee.ArrayList<Node> ();
            if (isolation != null) {
                list.add_all (isolation.children);
                return list;
            }
            foreach (var l in doc.layers) {
                if (l.hidden || l.locked) continue;
                foreach (var c in l.children) {
                    var g = c as GroupNode;
                    if (g != null && g.is_layer) {
                        if (g.hidden || g.locked) continue;
                        list.add_all (g.children);
                    } else {
                        list.add (c);
                    }
                }
            }
            return list;
        }

        public bool hit (Node n, Point p, double tol) {
            if (n.hidden || n.locked) return false;
            if (!n.visual_bounds ().inflate (tol).contains (p.x, p.y)) return false;
            var g = n as GroupNode;
            if (g != null) {
                if (g.clip && g.children.size > 0) {
                    var cp = g.children[0].outline ();
                    if (cp != null && !PathOps.contains (cp, p) && (PathOps.nearest (cp, p, tol) == null)) return false;
                }
                var gen = g.generated (doc);
                var list = gen != null ? gen.children : g.children;
                for (int i = list.size - 1; i >= (g.clip && gen == null ? 1 : 0); i--) if (hit (list[i], p, tol)) return true;
                if (g.clip && gen == null && g.children.size > 0) return hit (g.children[0], p, tol);
                return false;
            }
            var tn = n as TextNode;
            if (tn != null) {
                if (tn.mode == "area" && tn.area != null) return PathOps.contains (tn.area, p) || PathOps.nearest (tn.area, p, tol) != null;
                if (tn.mode == "path" && tn.on_path != null && PathOps.nearest (tn.on_path, p, tol + tn.style.size / 2) != null) return true;
                return tn.geometric_bounds ().inflate (tol).contains (p.x, p.y);
            }
            if (n is ImageNode || n is SymbolNode || n is MeshNode) {
                var o = n.outline ();
                return o != null && (PathOps.contains (o, p) || PathOps.nearest (o, p, tol) != null);
            }
            var pn = n as PathNode;
            if (pn == null) return false;
            var path = pn.render_path ();
            bool filled = false;
            double stroke = 0;
            foreach (var l in pn.appearance) {
                if (!l.visible || !l.paint.visible ()) continue;
                if (l.stroke) stroke = double.max (stroke, l.width / 2);
                else filled = true;
            }
            if (outline_mode) filled = false;
            if (filled && PathOps.contains (path, p, pn.even_odd)) return true;
            return PathOps.nearest (path, p, tol + stroke) != null;
        }

        public Node? hit_root (Point p) {
            double tol = px (4);
            var roots = selectable_roots ();
            for (int i = roots.size - 1; i >= 0; i--) if (hit (roots[i], p, tol)) return roots[i];
            return null;
        }

        public Node? hit_leaf (Point p, bool groups_as_leaf = false) {
            double tol = px (4);
            var roots = selectable_roots ();
            for (int i = roots.size - 1; i >= 0; i--) {
                var r = leaf_in (roots[i], p, tol, groups_as_leaf);
                if (r != null) return r;
            }
            return null;
        }

        private Node? leaf_in (Node n, Point p, double tol, bool groups_as_leaf) {
            if (n.hidden || n.locked) return null;
            var g = n as GroupNode;
            if (g != null && g.generated (null) == null && !groups_as_leaf) {
                for (int i = g.children.size - 1; i >= 0; i--) {
                    var r = leaf_in (g.children[i], p, tol, groups_as_leaf);
                    if (r != null) return r;
                }
                return null;
            }
            return hit (n, p, tol) ? n : null;
        }

        public Gee.ArrayList<Node> nodes_in_rect (Rect r, bool touching = true) {
            var list = new Gee.ArrayList<Node> ();
            foreach (var n in selectable_roots ()) {
                if (n.hidden || n.locked) continue;
                var b = n.geometric_bounds ();
                if (b.w < 0) continue;
                if (touching ? r.intersects (b) : r.contains_rect (b)) list.add (n);
            }
            return list;
        }

        public Point snap (Point p, Gee.Collection<Node>? exclude = null, bool record = true) {
            if (record) hints.clear ();
            double tol = px (6);
            double best_x = tol, best_y = tol;
            double sx = p.x, sy = p.y;
            bool snapped_x = false, snapped_y = false;
            if (snap_points) {
                double best = tol;
                Point? target = null;
                foreach (var n in candidate_nodes (exclude)) {
                    var pn = n as PathNode;
                    if (pn == null) continue;
                    foreach (int i in PathOps.anchors (pn.path)) {
                        var a = Point (pn.path.segs[i].x, pn.path.segs[i].y);
                        double d = a.distance (p);
                        if (d < best) {
                            best = d;
                            target = a;
                        }
                    }
                }
                if (target != null) {
                    if (record) hints.add (new SnapHint (target, target, _("anchor")));
                    return target;
                }
                PathHit? on_path = null;
                foreach (var n in candidate_nodes (exclude)) {
                    var pn = n as PathNode;
                    if (pn == null) continue;
                    var h = PathOps.nearest (pn.render_path (), p, best);
                    if (h != null && (on_path == null || h.distance < on_path.distance)) on_path = h;
                }
                if (on_path != null) {
                    if (record) hints.add (new SnapHint (on_path.point, on_path.point, _("path")));
                    return on_path.point;
                }
            }
            if (smart_guides) {
                foreach (var n in candidate_nodes (exclude)) {
                    var b = n.geometric_bounds ();
                    if (b.w < 0) continue;
                    double[] xs = { b.x, b.cx (), b.x + b.w };
                    double[] ys = { b.y, b.cy (), b.y + b.h };
                    foreach (double x in xs) {
                        double d = (x - p.x).abs ();
                        if (d < best_x) {
                            best_x = d;
                            sx = x;
                            snapped_x = true;
                        }
                    }
                    foreach (double y in ys) {
                        double d = (y - p.y).abs ();
                        if (d < best_y) {
                            best_y = d;
                            sy = y;
                            snapped_y = true;
                        }
                    }
                }
                foreach (var a in doc.artboards) {
                    foreach (double x in new double[] { a.x, a.x + a.w / 2, a.x + a.w }) {
                        double d = (x - p.x).abs ();
                        if (d < best_x) {
                            best_x = d;
                            sx = x;
                            snapped_x = true;
                        }
                    }
                    foreach (double y in new double[] { a.y, a.y + a.h / 2, a.y + a.h }) {
                        double d = (y - p.y).abs ();
                        if (d < best_y) {
                            best_y = d;
                            sy = y;
                            snapped_y = true;
                        }
                    }
                }
            }
            foreach (var g in doc.guides) {
                if (g.vertical && (g.pos - p.x).abs () < best_x) {
                    best_x = (g.pos - p.x).abs ();
                    sx = g.pos;
                    snapped_x = true;
                } else if (!g.vertical && (g.pos - p.y).abs () < best_y) {
                    best_y = (g.pos - p.y).abs ();
                    sy = g.pos;
                    snapped_y = true;
                }
            }
            if (!snapped_x && snap_grid) sx = Math.round (p.x / (doc.grid_size / doc.grid_sub)) * (doc.grid_size / doc.grid_sub);
            if (!snapped_y && snap_grid) sy = Math.round (p.y / (doc.grid_size / doc.grid_sub)) * (doc.grid_size / doc.grid_sub);
            if (!snapped_x && snap_pixel) sx = Math.round (p.x);
            if (!snapped_y && snap_pixel) sy = Math.round (p.y);
            if (record && smart_guides) {
                if (snapped_x) hints.add (new SnapHint (Point (sx, sy - px (4000)), Point (sx, sy + px (4000))));
                if (snapped_y) hints.add (new SnapHint (Point (sx - px (4000), sy), Point (sx + px (4000), sy)));
            }
            return Point (sx, sy);
        }

        public Gee.ArrayList<Node> candidate_nodes (Gee.Collection<Node>? exclude) {
            var list = new Gee.ArrayList<Node> ();
            var view = to_doc (get_width (), get_height ());
            var vis = Rect.from_points (ox, oy, view.x, view.y);
            foreach (var n in doc.all_nodes ()) {
                if (n is GroupNode) continue;
                if (exclude != null && (exclude.contains (n) || ancestor_in (n, exclude))) continue;
                if (n.effectively_hidden ()) continue;
                var b = n.geometric_bounds ();
                if (b.w < 0 || !vis.intersects (b)) continue;
                list.add (n);
                if (list.size > 400) break;
            }
            return list;
        }

        private bool ancestor_in (Node n, Gee.Collection<Node> set) {
            Node? cur = n.parent;
            while (cur != null) {
                if (set.contains (cur)) return true;
                cur = cur.parent;
            }
            return false;
        }

        private void on_drag_begin (Gtk.GestureDrag g, double x, double y) {
            grab_focus ();
            drag_start_x = x;
            drag_start_y = y;
            mods = g.get_current_event_state ();
            uint button = g.get_current_button ();
            if (button == 2 || (button == 1 && space_down)) {
                held_drag = true;
                pan_ox = ox;
                pan_oy = oy;
                return;
            }
            held_drag = false;
            if (button != 1) return;
            if (show_rulers && rulers.on_ruler (x, y, get_height ())) {
                dragging_guide = true;
                bool vertical = rulers.vertical_at (x);
                moving_guide = new Guide (vertical, vertical ? to_doc (x, y).x : to_doc (x, y).y);
                return;
            }
            var p = to_doc (x, y);
            if (!(tool is SelectTool) && !(tool is DirectTool)) {
                foreach (var gd in doc.guides) {
                    double d = gd.vertical ? (gd.pos - p.x).abs () : (gd.pos - p.y).abs ();
                    if (d < px (3) && tool is HandTool == false && (mods & Gdk.ModifierType.ALT_MASK) != 0) {
                        moving_guide = gd;
                        dragging_guide = true;
                        return;
                    }
                }
            }
            tool.press (p, mods);
            queue_draw ();
        }

        private bool held_drag = false;
        private double pan_ox;
        private double pan_oy;

        private void on_drag_update (Gtk.GestureDrag g, double dx, double dy) {
            mods = g.get_current_event_state ();
            if (held_drag) {
                ox = pan_ox - dx / zoom;
                oy = pan_oy - dy / zoom;
                queue_draw ();
                view_changed ();
                return;
            }
            var p = to_doc (drag_start_x + dx, drag_start_y + dy);
            pointer = p;
            if (dragging_guide && moving_guide != null) {
                moving_guide.pos = moving_guide.vertical ? p.x : p.y;
                queue_draw ();
                return;
            }
            tool.drag (p, mods);
            pointer_moved ();
            queue_draw ();
        }

        private void on_drag_end (Gtk.GestureDrag g, double dx, double dy) {
            mods = g.get_current_event_state ();
            if (held_drag) {
                held_drag = false;
                return;
            }
            var p = to_doc (drag_start_x + dx, drag_start_y + dy);
            if (dragging_guide && moving_guide != null) {
                dragging_guide = false;
                bool inside = rulers.inside_view (drag_start_x + dx, drag_start_y + dy, get_height ());
                doc.begin (_("Move Guide"));
                if (!doc.guides.contains (moving_guide)) {
                    if (inside) doc.guides.add (moving_guide);
                } else if (!inside) {
                    doc.guides.remove (moving_guide);
                }
                doc.commit ();
                moving_guide = null;
                queue_draw ();
                return;
            }
            tool.release (p, mods);
            hints.clear ();
            queue_draw ();
        }

        private bool on_key (uint keyval, uint code, Gdk.ModifierType state) {
            mods = state;
            if (keyval == Gdk.Key.space && !space_down && !(tool is TextTool && ((TextTool) tool).editing)) {
                space_down = true;
                if (!(tool is HandTool)) {
                    held_tool = tool;
                    set_tool_object (tools["hand"]);
                }
                return true;
            }
            if (tool.key (keyval, state)) {
                queue_draw ();
                return true;
            }
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt_key = (state & Gdk.ModifierType.ALT_MASK) != 0;
            if (!ctrl && !alt_key) {
                string? id = tool_for_key (keyval, shift);
                if (id != null) {
                    set_tool (id);
                    return true;
                }
                switch (keyval) {
                    case Gdk.Key.Delete:
                    case Gdk.Key.BackSpace:
                        key_command ("delete");
                        return true;
                    case Gdk.Key.d:
                        key_command ("default-colors");
                        return true;
                    case Gdk.Key.slash:
                        key_command ("fill-none");
                        return true;
                    case Gdk.Key.X:
                        key_command ("swap-fill-stroke");
                        return true;
                }
            }
            double step = nudge * (shift ? 10 : 1);
            double dx = 0, dy = 0;
            switch (keyval) {
                case Gdk.Key.Left: dx = -step; break;
                case Gdk.Key.Right: dx = step; break;
                case Gdk.Key.Up: dy = -step; break;
                case Gdk.Key.Down: dy = step; break;
                case Gdk.Key.Escape:
                    if (isolation != null) {
                        isolation = null;
                        queue_draw ();
                        return true;
                    }
                    clear_selection ();
                    return true;
                default:
                    break;
            }
            if ((dx != 0 || dy != 0) && !ctrl) {
                if (anchors.size > 0 && tool is DirectTool) {
                    doc.begin (_("Move Points"));
                    foreach (var e in anchors.entries) PathEdit.move_anchors (e.key, e.value, dx, dy);
                    doc.commit ();
                } else if (selection.size > 0) {
                    doc.begin (_("Move"));
                    var m = Transforms.translate (dx, dy);
                    foreach (var n in selection) n.apply_transform (m, scale_strokes);
                    doc.commit ();
                }
                return true;
            }
            return false;
        }

        public signal void key_command (string action);

        private static string? tool_for_key (uint keyval, bool shift) {
            string key = Gdk.keyval_name (Gdk.keyval_to_lower (keyval)) ?? "";
            if (keyval == Gdk.Key.asciitilde) return "curvature";
            if (keyval == Gdk.Key.backslash) return "line";
            if (shift) {
                switch (key) {
                    case "b": return "blob";
                    case "e": return "eraser";
                    case "m": return "shape-builder";
                    case "w": return "width";
                    case "o": return "artboard";
                    case "p": return "perspective";
                    case "s": return "symbol-sprayer";
                    default: return null;
                }
            }
            switch (key) {
                case "v": return "select";
                case "a": return "direct";
                case "q": return "lasso";
                case "p": return "pen";
                case "n": return "pencil";
                case "b": return "paintbrush";
                case "m": return "rectangle";
                case "l": return "ellipse";
                case "t": return "text";
                case "c": return "scissors";
                case "k": return "live-paint";
                case "g": return "gradient";
                case "u": return "mesh";
                case "i": return "eyedropper";
                case "w": return "blend";
                case "r": return "rotate";
                case "s": return "scale";
                case "o": return "reflect";
                case "h": return "hand";
                case "z": return "zoom";
                default: return null;
            }
        }

        private void draw (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            var fg = get_color ();
            dark = fg.red + fg.green + fg.blue > 1.5;
            if (dark) cr.set_source_rgb (0.13, 0.13, 0.14);
            else cr.set_source_rgb (0.86, 0.865, 0.875);
            cr.paint ();
            if (doc.proof) {
                var img = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, width), int.max (1, height));
                var ic = new Cairo.Context (img);
                draw_artwork (ic);
                ColorManager.get_default ().proof (img);
                cr.set_source_surface (img, 0, 0);
                cr.paint ();
            } else {
                draw_artwork (cr);
            }
            cr.save ();
            cr.scale (zoom, zoom);
            cr.translate (-ox, -oy);
            foreach (var a in doc.artboards) {
                bool active = doc.current_artboard () == a;
                cr.rectangle (a.x, a.y, a.w, a.h);
                cr.set_line_width (px (active ? 1.5 : 1));
                cr.set_source_rgba (0, 0, 0, active ? 0.55 : 0.25);
                cr.stroke ();
                if (a.bleed > 0) {
                    cr.rectangle (a.x - a.bleed, a.y - a.bleed, a.w + a.bleed * 2, a.h + a.bleed * 2);
                    cr.set_source_rgba (0.9, 0.2, 0.2, 0.6);
                    cr.set_line_width (px (1));
                    cr.stroke ();
                }
                cr.move_to (a.x, a.y - px (6));
                cr.set_source_rgba (dark ? 1 : 0, dark ? 1 : 0, dark ? 1 : 0, 0.6);
                cr.set_font_size (px (11));
                cr.show_text (a.name);
            }
            draw_pixel_grid (cr);
            draw_perspective (cr);
            foreach (var g in doc.guides) draw_guide (cr, g);
            if (moving_guide != null) draw_guide (cr, moving_guide);
            draw_selection (cr);
            tool.draw_overlay (cr);
            foreach (var h in hints) {
                cr.set_source_rgba (0.9, 0.15, 0.55, 0.9);
                cr.set_line_width (px (1));
                if (h.a.distance (h.b) < 1e-9) {
                    cr.arc (h.a.x, h.a.y, px (4), 0, 2 * Math.PI);
                    cr.stroke ();
                    if (h.label != "") {
                        cr.move_to (h.a.x + px (6), h.a.y - px (6));
                        cr.set_font_size (px (10));
                        cr.show_text (h.label);
                    }
                } else {
                    cr.move_to (h.a.x, h.a.y);
                    cr.line_to (h.b.x, h.b.y);
                    cr.stroke ();
                }
            }
            cr.restore ();
            if (show_rulers) rulers.draw (cr, width, height);
        }

        private void draw_artwork (Cairo.Context cr) {
            cr.save ();
            cr.scale (zoom, zoom);
            cr.translate (-ox, -oy);
            foreach (var a in doc.artboards) {
                cr.save ();
                cr.rectangle (a.x + px (3), a.y + px (4), a.w, a.h);
                cr.set_source_rgba (0, 0, 0, dark ? 0.5 : 0.15);
                cr.fill ();
                cr.restore ();
                if (a.background != "") {
                    var bg = Ink.hex (a.background);
                    cr.set_source_rgb (bg.r, bg.g, bg.b);
                } else {
                    cr.set_source_rgb (1, 1, 1);
                }
                cr.rectangle (a.x, a.y, a.w, a.h);
                cr.fill ();
            }
            if (show_grid) draw_grid (cr);
            var ctx = new RenderContext (doc);
            ctx.outline = outline_mode;
            ctx.overprint = doc.overprint_preview;
            if (isolation != null) {
                cr.push_group ();
                Renderer.draw_document (cr, ctx);
                cr.pop_group_to_source ();
                cr.paint_with_alpha (0.35);
                Renderer.draw_node (cr, isolation, ctx);
            } else {
                Renderer.draw_document (cr, ctx);
            }
            cr.restore ();
        }

        private void draw_grid (Cairo.Context cr) {
            var tl = to_doc (0, 0);
            var br = to_doc (get_width (), get_height ());
            double step = doc.grid_size;
            double sub = step / double.max (doc.grid_sub, 1);
            cr.set_line_width (px (1));
            if (sub * zoom > 6) {
                cr.set_source_rgba (0.3, 0.5, 0.9, 0.12);
                for (double x = Math.floor (tl.x / sub) * sub; x < br.x; x += sub) {
                    cr.move_to (x, tl.y);
                    cr.line_to (x, br.y);
                }
                for (double y = Math.floor (tl.y / sub) * sub; y < br.y; y += sub) {
                    cr.move_to (tl.x, y);
                    cr.line_to (br.x, y);
                }
                cr.stroke ();
            }
            if (step * zoom > 6) {
                cr.set_source_rgba (0.3, 0.5, 0.9, 0.3);
                for (double x = Math.floor (tl.x / step) * step; x < br.x; x += step) {
                    cr.move_to (x, tl.y);
                    cr.line_to (x, br.y);
                }
                for (double y = Math.floor (tl.y / step) * step; y < br.y; y += step) {
                    cr.move_to (tl.x, y);
                    cr.line_to (br.x, y);
                }
                cr.stroke ();
            }
        }

        private void draw_pixel_grid (Cairo.Context cr) {
            var tl = to_doc (0, 0);
            var br = to_doc (get_width (), get_height ());
            cr.set_line_width (px (1));
            if (snap_pixel && zoom >= 8) {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.25);
                for (double x = Math.floor (tl.x); x < br.x; x += 1) {
                    cr.move_to (x, tl.y);
                    cr.line_to (x, br.y);
                }
                for (double y = Math.floor (tl.y); y < br.y; y += 1) {
                    cr.move_to (tl.x, y);
                    cr.line_to (br.x, y);
                }
                cr.stroke ();
            }
        }

        private void draw_guide (Cairo.Context cr, Guide g) {
            var tl = to_doc (0, 0);
            var br = to_doc (get_width (), get_height ());
            cr.set_source_rgba (0.0, 0.75, 0.85, 0.9);
            cr.set_line_width (px (1));
            if (g.vertical) {
                cr.move_to (g.pos, tl.y);
                cr.line_to (g.pos, br.y);
            } else {
                cr.move_to (tl.x, g.pos);
                cr.line_to (br.x, g.pos);
            }
            cr.stroke ();
        }

        private void draw_perspective (Cairo.Context cr) {
            var pg = doc.perspective;
            if (!pg.visible) return;
            var tl = to_doc (0, 0);
            var br = to_doc (get_width (), get_height ());
            cr.set_line_width (px (1));
            cr.set_source_rgba (0.2, 0.6, 0.2, 0.55);
            cr.move_to (tl.x, pg.horizon);
            cr.line_to (br.x, pg.horizon);
            cr.stroke ();
            foreach (var plane in Perspective.planes (pg)) {
                cr.set_source_rgba (plane.r, plane.g, plane.b, 0.4);
                for (int i = 0; i <= 10; i++) {
                    var a = Warp.project (plane.h, Point (i / 10.0, 0));
                    var b = Warp.project (plane.h, Point (i / 10.0, 1));
                    cr.move_to (a.x, a.y);
                    cr.line_to (b.x, b.y);
                    var c = Warp.project (plane.h, Point (0, i / 10.0));
                    var d = Warp.project (plane.h, Point (1, i / 10.0));
                    cr.move_to (c.x, c.y);
                    cr.line_to (d.x, d.y);
                }
                cr.stroke ();
            }
            cr.set_source_rgba (0.85, 0.2, 0.2, 0.9);
            foreach (var vp in Perspective.vanishing_points (pg)) {
                cr.arc (vp.x, vp.y, px (5), 0, 2 * Math.PI);
                cr.fill ();
            }
        }

        public void layer_color (Node n, Cairo.Context cr, double alpha = 1) {
            var layer = n.layer ();
            var c = Ink.hex (layer != null ? layer.color : "#4a90d9");
            cr.set_source_rgba (c.r, c.g, c.b, alpha);
        }

        private void draw_selection (Cairo.Context cr) {
            if (!show_edges) return;
            cr.set_line_width (px (1));
            foreach (var n in selection) {
                layer_color (n, cr);
                draw_node_outline (cr, n);
            }
            if (tool is SelectTool && selection.size > 0) {
                var b = selection_bounds ();
                if (b.w >= 0) {
                    cr.set_source_rgba (0.2, 0.5, 0.95, 1);
                    cr.rectangle (b.x, b.y, b.w, b.h);
                    cr.stroke ();
                    foreach (var h in SelectTool.handle_points (b)) {
                        cr.rectangle (h.x - px (3.5), h.y - px (3.5), px (7), px (7));
                        cr.set_source_rgb (1, 1, 1);
                        cr.fill_preserve ();
                        cr.set_source_rgba (0.2, 0.5, 0.95, 1);
                        cr.stroke ();
                    }
                    if (selection.size == 1) {
                        var pn = selection[0] as PathNode;
                        if (pn != null && pn.live != null && pn.live.kind != "line" && pn.live.kind != "ellipse") {
                            foreach (var w in SelectTool.corner_widgets (pn)) {
                                cr.arc (w.x, w.y, px (4), 0, 2 * Math.PI);
                                cr.set_source_rgb (1, 1, 1);
                                cr.fill_preserve ();
                                cr.set_source_rgba (0.2, 0.5, 0.95, 1);
                                cr.stroke ();
                            }
                        }
                    }
                }
            }
            if (tool.shows_anchors ()) {
                foreach (var n in selection) {
                    var pn = n as PathNode;
                    if (pn != null) draw_anchors (cr, pn);
                }
                foreach (var e in anchors.entries) if (!selection.contains (e.key)) draw_anchors (cr, e.key);
            }
        }

        public void draw_node_outline (Cairo.Context cr, Node n) {
            var tn = n as TextNode;
            if (tn != null) {
                if (tn.mode == "area" && tn.area != null) {
                    cr.new_path ();
                    tn.area.to_cairo (cr);
                    cr.stroke ();
                    var info = TextLayout.frame_info (tn);
                    if (info.overflow) {
                        var b = tn.area.bounds ();
                        cr.rectangle (b.x + b.w - px (8), b.y + b.h - px (8), px (8), px (8));
                        cr.set_source_rgb (0.9, 0.1, 0.1);
                        cr.fill ();
                    }
                    return;
                }
                if (tn.mode == "path" && tn.on_path != null) {
                    cr.new_path ();
                    tn.on_path.to_cairo (cr);
                    cr.stroke ();
                }
                var lb = TextLayout.line_box (tn);
                cr.rectangle (lb.x, lb.y, lb.w, lb.h);
                cr.stroke ();
                return;
            }
            var g = n as GroupNode;
            if (g != null && g.generated (null) == null && !g.clip) {
                foreach (var c in g.children) draw_node_outline (cr, c);
                return;
            }
            var o = n.outline ();
            if (o == null) return;
            cr.new_path ();
            o.to_cairo (cr);
            cr.stroke ();
        }

        public void draw_anchors (Cairo.Context cr, PathNode pn) {
            var path = pn.path;
            var selected = anchors.has_key (pn) ? anchors[pn] : null;
            layer_color (pn, cr);
            cr.set_line_width (px (1));
            foreach (int i in PathOps.anchors (path)) {
                var s = path.segs[i];
                bool sel = selected != null && selected.contains (i);
                if (sel) {
                    int inc, outg;
                    PathOps.prev_next (path, i, out inc, out outg);
                    if (inc >= 0 && path.segs[inc].kind == SegKind.CURVE) {
                        cr.move_to (s.x, s.y);
                        cr.line_to (path.segs[inc].x2, path.segs[inc].y2);
                        cr.stroke ();
                        cr.arc (path.segs[inc].x2, path.segs[inc].y2, px (3), 0, 2 * Math.PI);
                        cr.fill ();
                    }
                    if (outg >= 0 && path.segs[outg].kind == SegKind.CURVE) {
                        cr.move_to (s.x, s.y);
                        cr.line_to (path.segs[outg].x1, path.segs[outg].y1);
                        cr.stroke ();
                        cr.arc (path.segs[outg].x1, path.segs[outg].y1, px (3), 0, 2 * Math.PI);
                        cr.fill ();
                    }
                }
                cr.rectangle (s.x - px (3), s.y - px (3), px (6), px (6));
                if (sel) {
                    cr.fill ();
                } else {
                    cr.save ();
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill_preserve ();
                    cr.restore ();
                    cr.stroke ();
                }
            }
        }
    }

    public class Units {
        public static double factor (string unit) {
            switch (unit) {
                case "pt": return 96.0 / 72.0;
                case "mm": return 96.0 / 25.4;
                case "cm": return 96.0 / 2.54;
                case "in": return 96.0;
                default: return 1;
            }
        }

        public static string format (double v) {
            if ((v - Math.round (v)).abs () < 1e-6) return "%.0f".printf (v);
            return "%.1f".printf (v);
        }

        public static string label (string unit) {
            switch (unit) {
                case "pt": return _("pt");
                case "mm": return _("mm");
                case "cm": return _("cm");
                case "in": return _("in");
                default: return _("px");
            }
        }
    }
}
