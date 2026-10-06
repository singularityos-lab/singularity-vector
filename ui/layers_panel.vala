using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class LayerList : Box {
        private weak VectorWindow win;
        private ListBox list;
        private Gee.HashSet<string> expanded = new Gee.HashSet<string> ();
        private Gee.HashMap<Node, ListBoxRow> rows = new Gee.HashMap<Node, ListBoxRow> ();
        private Gee.HashMap<string, Node> by_id = new Gee.HashMap<string, Node> ();
        private ListBoxRow? drop_row = null;
        private string? editing = null;
        private Gdk.ModifierType list_mods = 0;
        private bool dragging = false;
        private Drop drop_zone = Drop.BEFORE;
        private ListBoxRow? press_row = null;
        private ListBoxRow? last_press_row = null;
        private uint32 last_press_time = 0;
        private double press_x = 0;
        private double press_y = 0;
        private Button up_button;
        private Button down_button;
        private Button delete_button;
        private Button duplicate_button;

        private enum Drop {
            BEFORE,
            AFTER,
            INTO
        }

        public LayerList (VectorWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("sx-layer-list-panel");
            vexpand = true;
            apply_titlebar_inset (this);
            append (new SidebarSectionLabel (_("Layers")));
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.margin_top = 4;
            list = new ListBox ();
            list.add_css_class ("sx-layer-list");
            list.selection_mode = SelectionMode.NONE;
            list.activate_on_single_click = true;
            list.row_activated.connect ((r) => {
                if (editing != null || dragging) return;
                var n = node_of (r);
                if (n != null) pick (n);
            });
            var raw = new EventControllerLegacy ();
            raw.propagation_phase = PropagationPhase.CAPTURE;
            raw.event.connect ((ev) => on_raw (ev));
            list.add_controller (raw);
            var mods = new GestureClick ();
            mods.propagation_phase = PropagationPhase.CAPTURE;
            mods.pressed.connect (() => list_mods = mods.get_current_event_state ());
            list.add_controller (mods);
            scroll.child = list;
            append (scroll);
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.add_css_class ("sx-layer-list-bar");
            bar.append (bar_button ("list-add-symbolic", _("New Layer"), () => win.activate_named ("layer-new")));
            duplicate_button = bar_button ("edit-copy-symbolic", _("Duplicate"), () => duplicate_current ());
            bar.append (duplicate_button);
            up_button = bar_button ("go-up-symbolic", _("Move Up"), () => move_current (1));
            bar.append (up_button);
            down_button = bar_button ("go-down-symbolic", _("Move Down"), () => move_current (-1));
            bar.append (down_button);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            delete_button = bar_button ("user-trash-symbolic", _("Delete"), () => delete_current ());
            bar.append (delete_button);
            append (bar);
        }

        private Button bar_button (string icon, string tooltip, owned Forms.Done action) {
            var b = new Button.from_icon_name (icon);
            b.tooltip_text = tooltip;
            b.update_property (AccessibleProperty.LABEL, tooltip, -1);
            b.clicked.connect (() => action ());
            return b;
        }

        private Node? node_of (ListBoxRow r) {
            string? id = r.get_data<string> ("sx-node");
            return id != null && by_id.has_key (id) ? by_id[id] : null;
        }

        private VectorDocument? doc {
            get {
                return win.doc;
            }
        }

        private void pick (Node n) {
            var g = n as GroupNode;
            var c = win.canvas;
            if (c == null) return;
            if (g != null && g.is_layer) {
                doc.active_layer = g;
                if ((list_mods & Gdk.ModifierType.SHIFT_MASK) == 0) c.clear_selection ();
                sync_selection ();
                return;
            }
            var layer = n.layer ();
            if (layer != null && doc.active_layer != layer) doc.active_layer = layer;
            if ((list_mods & Gdk.ModifierType.SHIFT_MASK) != 0) c.toggle_selection (n);
            else c.select_only (n);
            sync_selection ();
        }

        private Gee.List<Node> siblings_of (Node n) {
            if (n.parent != null) return n.parent.children;
            var list = new Gee.ArrayList<Node> ();
            foreach (var l in doc.layers) list.add (l);
            return list;
        }

        private Gee.ArrayList<Node> current () {
            var out_list = new Gee.ArrayList<Node> ();
            var c = win.canvas;
            if (c != null && c.selection.size > 0) {
                foreach (var n in c.selection) out_list.add (n);
            } else if (doc.active_layer != null) {
                out_list.add (doc.active_layer);
            }
            return out_list;
        }

        private void move_current (int dir) {
            var nodes = current ();
            if (nodes.size == 0) return;
            doc.begin (_("Move"));
            foreach (var n in nodes) shift (n, dir);
            doc.commit ();
            rebuild ();
        }

        private void shift (Node n, int dir) {
            var g = n as GroupNode;
            if (n.parent == null && g != null) {
                int i = doc.layers.index_of (g);
                int j = (i + dir).clamp (0, doc.layers.size - 1);
                if (i < 0 || i == j) return;
                doc.layers.remove_at (i);
                doc.layers.insert (j, g);
                return;
            }
            if (n.parent == null) return;
            var sib = n.parent.children;
            int i = sib.index_of (n);
            int j = (i + dir).clamp (0, sib.size - 1);
            if (i < 0 || i == j) return;
            sib.remove_at (i);
            sib.insert (j, n);
        }

        private void duplicate_current () {
            var c = win.canvas;
            if (c != null && c.selection.size > 0) {
                Commands.duplicate (c, 0, 0);
                return;
            }
            var l = doc.active_layer;
            if (l == null) return;
            doc.begin (_("Duplicate Layer"));
            var copy = (GroupNode) l.clone ();
            Commands.clear_ids (copy);
            copy.name = _("%s Copy").printf (l.display_name ());
            if (l.parent != null) {
                l.parent.add (copy, l.parent.children.index_of (l) + 1);
            } else {
                doc.layers.insert (doc.layers.index_of (l) + 1, copy);
            }
            doc.ensure_ids ();
            doc.active_layer = copy;
            doc.commit ();
            rebuild ();
        }

        private void delete_current () {
            var c = win.canvas;
            if (c != null && c.selection.size > 0) {
                Commands.delete_selection (c);
                return;
            }
            win.activate_named ("layer-delete");
        }

        private bool contains (Node outer, Node inner) {
            Node? n = inner;
            while (n != null) {
                if (n == outer) return true;
                n = n.parent;
            }
            return false;
        }

        private void move_node (Node n, Node target, Drop where) {
            if (n == target || contains (n, target)) return;
            var tg = target as GroupNode;
            var ng = n as GroupNode;
            bool n_layer = ng != null && ng.is_layer;
            if (target.parent == null && !n_layer) where = Drop.INTO;
            if (where == Drop.INTO && tg == null) where = Drop.BEFORE;
            doc.begin (_("Reorder"));
            if (n.parent != null) n.parent.remove (n);
            else if (ng != null) doc.layers.remove (ng);
            if (where == Drop.INTO) {
                tg.add (n);
                if (tg.is_layer) expanded.add (tg.id);
            } else if (target.parent == null) {
                int i = doc.layers.index_of (tg);
                doc.layers.insert (where == Drop.BEFORE ? i + 1 : i, ng);
            } else {
                var p = target.parent;
                int i = p.children.index_of (target);
                p.add (n, where == Drop.BEFORE ? i + 1 : i);
            }
            doc.ensure_ids ();
            doc.commit ();
            rebuild ();
        }

        public void rebuild () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            rows.clear ();
            by_id.clear ();
            drop_row = null;
            if (doc == null) return;
            for (int i = doc.layers.size - 1; i >= 0; i--) add_row (doc.layers[i], 0);
            sync_selection ();
        }

        private ToggleButton row_toggle (string on_icon, string off_icon, bool on, bool dim_when_off, string tooltip) {
            var t = new ToggleButton ();
            t.icon_name = on ? on_icon : off_icon;
            t.active = on;
            t.add_css_class ("flat");
            t.add_css_class ("sx-layer-toggle");
            t.valign = Align.CENTER;
            t.tooltip_text = tooltip;
            t.update_property (AccessibleProperty.LABEL, tooltip, -1);
            if (dim_when_off && !on) t.add_css_class ("sx-off");
            return t;
        }

        private void add_row (Node n, int depth) {
            var g = n as GroupNode;
            bool is_layer = g != null && g.is_layer;
            bool has_children = g != null && g.children.size > 0;
            if (n.id != "") by_id[n.id] = n;
            var row = new ListBoxRow ();
            row.set_data<string> ("sx-node", n.id);
            var box = new Box (Orientation.HORIZONTAL, 4);
            box.margin_start = 4 + depth * 14;
            box.margin_end = 4;
            box.margin_top = 3;
            box.margin_bottom = 3;
            if (has_children) {
                bool open = expanded.contains (n.id);
                var exp = new Button.from_icon_name (open ? "pan-down-symbolic" : "pan-end-symbolic");
                exp.add_css_class ("flat");
                exp.add_css_class ("sx-layer-toggle");
                exp.valign = Align.CENTER;
                exp.tooltip_text = open ? _("Hide Contents") : _("Show Contents");
                exp.clicked.connect (() => {
                    if (expanded.contains (n.id)) expanded.remove (n.id);
                    else expanded.add (n.id);
                    rebuild ();
                });
                box.append (exp);
            } else {
                var pad = new Box (Orientation.HORIZONTAL, 0);
                pad.set_size_request (24, -1);
                box.append (pad);
            }
            var tag = new DrawingArea ();
            tag.set_size_request (3, 20);
            tag.valign = Align.CENTER;
            tag.set_draw_func ((a, cr, w, h) => {
                var layer = n.layer ();
                var ink = Ink.hex (layer != null ? layer.color : "#888888");
                cr.set_source_rgb (ink.r, ink.g, ink.b);
                cr.arc (w / 2.0, w / 2.0, w / 2.0, Math.PI, 0);
                cr.arc (w / 2.0, h - w / 2.0, w / 2.0, 0, Math.PI);
                cr.close_path ();
                cr.fill ();
            });
            box.append (tag);
            var thumb = new DrawingArea ();
            thumb.set_size_request (24, 24);
            thumb.valign = Align.CENTER;
            thumb.margin_start = 2;
            thumb.add_css_class ("sx-layer-thumb");
            thumb.overflow = Overflow.HIDDEN;
            thumb.set_draw_func ((a, cr, w, h) => {
                var b = n.visual_bounds ();
                if (b.w <= 0 && b.h <= 0) return;
                double s = double.min ((w - 4) / double.max (b.w, 0.01), (h - 4) / double.max (b.h, 0.01));
                cr.translate (w / 2.0, h / 2.0);
                cr.scale (s, s);
                cr.translate (-b.cx (), -b.cy ());
                bool was_hidden = n.hidden;
                n.hidden = false;
                Renderer.draw_node (cr, n, new RenderContext (doc));
                n.hidden = was_hidden;
            });
            box.append (thumb);
            var name_stack = new Stack ();
            name_stack.hexpand = true;
            name_stack.margin_start = 4;
            var label = new Label (n.display_name ());
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.add_css_class ("sx-layer-name");
            if (is_layer) label.add_css_class ("sx-layer-is-layer");
            if (n.hidden) label.add_css_class ("dim-label");
            name_stack.add_named (label, "label");
            var entry = new Entry ();
            entry.text = n.name != "" ? n.name : n.display_name ();
            entry.add_css_class ("sx-layer-edit");
            name_stack.add_named (entry, "entry");
            name_stack.visible_child_name = "label";
            bool done = false;
            entry.activate.connect (() => finish_rename (n, entry, ref done));
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((kv, code, state) => {
                if (kv == Gdk.Key.Escape) {
                    done = true;
                    editing = null;
                    rebuild ();
                    return true;
                }
                return false;
            });
            entry.add_controller (keys);
            var focus = new EventControllerFocus ();
            focus.leave.connect (() => {
                if (!done) Timeout.add (150, () => {
                    if (done) return Source.REMOVE;
                    var root = entry.get_root () as Gtk.Window;
                    bool inside = (entry.get_state_flags () & StateFlags.FOCUS_WITHIN) != 0;
                    if (root != null && root.is_active && !inside) finish_rename (n, entry, ref done);
                    return Source.REMOVE;
                });
            });
            entry.add_controller (focus);
            box.append (name_stack);
            var vis = row_toggle ("view-reveal-symbolic", "view-conceal-symbolic", !n.hidden, false, n.hidden ? _("Show") : _("Hide"));
            vis.toggled.connect (() => {
                if (n.hidden == !vis.active) return;
                doc.begin (vis.active ? _("Show") : _("Hide"));
                n.hidden = !vis.active;
                doc.commit ();
            });
            box.append (vis);
            var lock = row_toggle ("changes-prevent-symbolic", "changes-allow-symbolic", n.locked, true, n.locked ? _("Unlock") : _("Lock"));
            lock.toggled.connect (() => {
                if (n.locked == lock.active) return;
                doc.begin (lock.active ? _("Lock") : _("Unlock"));
                n.locked = lock.active;
                doc.commit ();
            });
            box.append (lock);
            row.child = box;
            var right = new GestureClick ();
            right.button = 3;
            right.pressed.connect ((count, x, y) => {
                right.set_state (EventSequenceState.CLAIMED);
                show_menu (n, row, x, y, name_stack, entry);
            });
            row.add_controller (right);
            row.set_data<Stack> ("sx-name-stack", name_stack);
            row.set_data<Entry> ("sx-name-entry", entry);
            list.append (row);
            rows[n] = row;
            if (editing != null && editing == n.id) start_rename (n, name_stack, entry);
            if (has_children && expanded.contains (n.id)) {
                for (int i = g.children.size - 1; i >= 0; i--) add_row (g.children[i], depth + 1);
            }
        }

        private bool point_in_list (Gdk.Event ev, out double lx, out double ly) {
            lx = ly = 0;
            double ex, ey;
            if (!ev.get_position (out ex, out ey)) return false;
            var native = list.get_native ();
            if (native == null) return false;
            double nx, ny;
            native.get_surface_transform (out nx, out ny);
            Graphene.Point p;
            if (!((Widget) native).compute_point (list, Graphene.Point () { x = (float) (ex - nx), y = (float) (ey - ny) }, out p)) return false;
            lx = p.x;
            ly = p.y;
            return true;
        }

        private bool on_raw (Gdk.Event ev) {
            var type = ev.get_event_type ();
            double x, y;
            if (type == Gdk.EventType.BUTTON_PRESS) {
                if (((Gdk.ButtonEvent) ev).get_button () != 1 || editing != null) return false;
                if (!point_in_list (ev, out x, out y)) return false;
                var row = list.get_row_at_y ((int) y);
                press_row = row;
                press_x = x;
                press_y = y;
                dragging = false;
                uint32 now = ev.get_time ();
                if (row != null && row == last_press_row && now - last_press_time < 450) {
                    last_press_row = null;
                    var n = node_of (row);
                    var st = row.get_data<Stack> ("sx-name-stack");
                    var en = row.get_data<Entry> ("sx-name-entry");
                    if (n != null && st != null && en != null) {
                        press_row = null;
                        start_rename (n, st, en);
                        return true;
                    }
                }
                last_press_row = row;
                last_press_time = now;
                return false;
            }
            if (type == Gdk.EventType.MOTION_NOTIFY) {
                if (press_row == null) return false;
                if ((ev.get_modifier_state () & Gdk.ModifierType.BUTTON1_MASK) == 0) {
                    press_row = null;
                    return false;
                }
                if (!point_in_list (ev, out x, out y)) return false;
                if (!dragging) {
                    if (Math.hypot (x - press_x, y - press_y) < 8) return false;
                    dragging = true;
                    last_press_row = null;
                    press_row.add_css_class ("sx-dragging");
                }
                var target = list.get_row_at_y ((int) y);
                var tn = target != null ? node_of (target) : null;
                var src = node_of (press_row);
                if (target == null || tn == null || src == null || target == press_row || contains (src, tn)) {
                    mark_drop (null, Drop.BEFORE);
                    return true;
                }
                Graphene.Rect bounds;
                if (!target.compute_bounds (list, out bounds)) return true;
                drop_zone = zone_at (tn, y - bounds.origin.y, bounds.size.height);
                mark_drop (target, drop_zone);
                return true;
            }
            if (type == Gdk.EventType.BUTTON_RELEASE) {
                if (!dragging || press_row == null) {
                    press_row = null;
                    return false;
                }
                var src_row = press_row;
                var target = drop_row;
                var where = drop_zone;
                mark_drop (null, Drop.BEFORE);
                src_row.remove_css_class ("sx-dragging");
                press_row = null;
                Idle.add (() => {
                    dragging = false;
                    var src = node_of (src_row);
                    var tn = target != null ? node_of (target) : null;
                    if (src != null && tn != null) move_node (src, tn, where);
                    return Source.REMOVE;
                });
                return true;
            }
            return false;
        }

        private Drop zone_at (Node n, double y, double h) {
            var g = n as GroupNode;
            if (g != null && y > h * 0.3 && y < h * 0.7) return Drop.INTO;
            return y < h / 2 ? Drop.BEFORE : Drop.AFTER;
        }

        private void mark_drop (ListBoxRow? row, Drop where) {
            if (drop_row != null) {
                drop_row.remove_css_class ("sx-drop-before");
                drop_row.remove_css_class ("sx-drop-after");
                drop_row.remove_css_class ("sx-drop-into");
            }
            drop_row = row;
            if (row == null) return;
            row.add_css_class (where == Drop.BEFORE ? "sx-drop-before" : (where == Drop.AFTER ? "sx-drop-after" : "sx-drop-into"));
        }

        private void start_rename (Node n, Stack name_stack, Entry entry) {
            editing = n.id;
            name_stack.visible_child_name = "entry";
            Timeout.add (60, () => {
                if (editing == n.id && entry.get_root () != null) {
                    entry.grab_focus ();
                    entry.select_region (0, -1);
                }
                return Source.REMOVE;
            });
        }

        private void finish_rename (Node n, Entry entry, ref bool done) {
            if (done) return;
            done = true;
            editing = null;
            string text = entry.text.strip ();
            if (text != "" && text != n.display_name ()) {
                doc.begin (_("Rename"));
                n.name = text;
                doc.commit ();
            }
            rebuild ();
        }

        public void rename (Node n) {
            if (!rows.has_key (n)) {
                var l = n.parent;
                while (l != null) {
                    expanded.add (l.id);
                    l = l.parent;
                }
            }
            editing = n.id;
            rebuild ();
        }

        private void show_menu (Node n, ListBoxRow row, double x, double y, Stack name_stack, Entry entry) {
            var g = n as GroupNode;
            bool is_layer = g != null && g.is_layer;
            var menu = new ContextMenu (row);
            menu.add_item (_("Rename"), "document-edit-symbolic", () => start_rename (n, name_stack, entry));
            if (is_layer) {
                menu.add_item (_("Layer Options…"), "document-properties-symbolic", () => Dialogs.layer_options (win, g));
                menu.add_item (_("New Sublayer"), "list-add-symbolic", () => {
                    doc.active_layer = g;
                    expanded.add (g.id);
                    win.activate_named ("layer-sublayer");
                });
                menu.add_item (_("Select Objects"), "edit-select-all-symbolic", () => {
                    var all = new Gee.ArrayList<Node> ();
                    foreach (var ch in g.children) if (!ch.locked && !ch.hidden) all.add (ch);
                    doc.active_layer = g;
                    win.canvas.set_selection (all);
                });
                if (win.canvas.selection.size > 0) menu.add_item (_("Move Selection Here"), "mail-send-symbolic", () => Commands.move_to_layer (win.canvas, g));
            }
            menu.add_separator ();
            menu.add_item (_("Delete"), "user-trash-symbolic", () => {
                if (is_layer) {
                    doc.active_layer = g;
                    win.canvas.clear_selection ();
                    win.activate_named ("layer-delete");
                } else {
                    win.canvas.select_only (n);
                    Commands.delete_selection (win.canvas);
                }
            }, "destructive-action");
            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = rect.height = 1;
            menu.set_pointing_to (rect);
            menu.closed.connect (() => Idle.add (() => {
                if (menu.get_parent () != null) menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        public void sync_selection () {
            var c = win.canvas;
            if (c == null || doc == null) return;
            bool reveal = false;
            foreach (var n in c.selection) {
                if (rows.has_key (n)) continue;
                var p = n.parent;
                while (p != null) {
                    if (p.id != "" && !expanded.contains (p.id)) {
                        expanded.add (p.id);
                        reveal = true;
                    }
                    p = p.parent;
                }
            }
            if (reveal) {
                rebuild ();
                return;
            }
            foreach (var e in rows.entries) {
                var g = e.key as GroupNode;
                bool active = g != null && g.is_layer && doc.active_layer == g && c.selection.size == 0;
                bool selected = c.selection.contains (e.key);
                if (active) e.value.add_css_class ("sx-layer-active");
                else e.value.remove_css_class ("sx-layer-active");
                if (selected) e.value.add_css_class ("sx-layer-selected");
                else e.value.remove_css_class ("sx-layer-selected");
            }
            bool any = c.selection.size > 0 || doc.active_layer != null;
            up_button.sensitive = any;
            down_button.sensitive = any;
            duplicate_button.sensitive = any;
            delete_button.sensitive = c.selection.size > 0 || (doc.active_layer != null && (doc.active_layer.parent != null || doc.layers.size > 1));
        }
    }
}
