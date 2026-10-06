using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Commands {
        public static Gee.ArrayList<Node> ordered (VectorCanvas c) {
            var all = c.doc.all_nodes ();
            var list = new Gee.ArrayList<Node> ();
            foreach (var n in all) if (c.selection.contains (n)) list.add (n);
            foreach (var n in c.selection) if (!list.contains (n)) list.add (n);
            return list;
        }

        public static void select_all (VectorCanvas c) {
            c.set_selection (c.selectable_roots ());
        }

        public static void select_inverse (VectorCanvas c) {
            var list = new Gee.ArrayList<Node> ();
            foreach (var n in c.selectable_roots ()) if (!c.selection.contains (n) && !n.hidden && !n.locked) list.add (n);
            c.set_selection (list);
        }

        public static void select_same (VectorCanvas c, string what) {
            if (c.selection.size == 0) return;
            var ref_node = c.selection[0];
            var list = new Gee.ArrayList<Node> ();
            foreach (var n in c.doc.all_nodes ()) {
                if (n is GroupNode || n.effectively_locked () || n.effectively_hidden ()) continue;
                bool match = false;
                var rf = ref_node.first_fill ();
                var nf = n.first_fill ();
                var rs = ref_node.first_stroke ();
                var ns = n.first_stroke ();
                switch (what) {
                    case "fill":
                        match = rf != null && nf != null && rf.paint.kind == nf.paint.kind && rf.paint.representative ().same (nf.paint.representative ());
                        break;
                    case "stroke":
                        match = rs != null && ns != null && rs.paint.representative ().same (ns.paint.representative ());
                        break;
                    case "width":
                        match = rs != null && ns != null && (rs.width - ns.width).abs () < 0.01;
                        break;
                    case "opacity":
                        match = (n.opacity - ref_node.opacity).abs () < 0.001;
                        break;
                    case "blend":
                        match = n.blend == ref_node.blend;
                        break;
                    case "style":
                        match = ref_node.style_id != "" && n.style_id == ref_node.style_id;
                        break;
                    case "symbol":
                        var a = ref_node as SymbolNode;
                        var b = n as SymbolNode;
                        match = a != null && b != null && a.symbol == b.symbol;
                        break;
                    default:
                        match = n.kind_name () == ref_node.kind_name ();
                        break;
                }
                if (match) list.add (n);
            }
            c.set_selection (list);
        }

        public static void delete_selection (VectorCanvas c) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Delete"));
            foreach (var n in c.selection) if (n.parent != null) n.parent.remove (n);
            c.doc.commit ();
            c.clear_selection ();
        }

        public static void duplicate (VectorCanvas c, double dx = 10, double dy = 10) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Duplicate"));
            var copies = new Gee.ArrayList<Node> ();
            foreach (var n in ordered (c)) {
                var copy = n.clone ();
                copy.id = "";
                clear_ids (copy);
                copy.apply_transform (Transforms.translate (dx, dy), false);
                n.parent.add (copy, n.parent.children.index_of (n) + 1);
                copies.add (copy);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (copies);
        }

        public static void clear_ids (Node n) {
            n.id = "";
            var g = n as GroupNode;
            if (g != null) foreach (var ch in g.children) clear_ids (ch);
        }

        public static void copy (VectorCanvas c, bool cut) {
            if (c.selection.size == 0) return;
            string data = NativeFormat.nodes_to_string (ordered (c), c.doc);
            var provider = new Gdk.ContentProvider.union ({
                new Gdk.ContentProvider.for_bytes ("application/x-singularity-vector", new Bytes (data.data)),
                new Gdk.ContentProvider.for_bytes ("image/svg+xml", new Bytes (SvgWriter.selection_svg (c.doc, ordered (c)).data)),
                new Gdk.ContentProvider.for_value (data)
            });
            c.get_clipboard ().set_content (provider);
            if (cut) delete_selection (c);
        }

        public static void paste (VectorCanvas c, string mode) {
            var clip = c.get_clipboard ();
            var formats = clip.get_formats ();
            string mime = "text/plain";
            foreach (var candidate in new string[] { "application/x-singularity-vector", DrawExchange.DRAW_MIME, "image/svg+xml", "image/png", "image/jpeg", "image/webp" }) {
                if (formats.contain_mime_type (candidate)) {
                    mime = candidate;
                    break;
                }
            }
            clip.read_async.begin ({ mime }, Priority.DEFAULT, null, (obj, res) => {
                try {
                    string out_mime;
                    var stream = clip.read_async.end (res, out out_mime);
                    var mem = new MemoryOutputStream.resizable ();
                    mem.splice (stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
                    var bytes = mem.steal_as_bytes ();
                    if (mime.has_prefix ("image/") && mime != "image/svg+xml") {
                        paste_image (c, bytes, mime);
                        return;
                    }
                    string text = ((string) bytes.get_data ()).substring (0, (long) bytes.get_size ());
                    if (mime == DrawExchange.DRAW_MIME) {
                        var nodes = DrawExchange.nodes_from_draw (text, c.doc);
                        if (nodes != null) insert_nodes (c, nodes, mode);
                        return;
                    }
                    paste_text (c, text, mode);
                } catch (Error e) {
                    warning ("Vector: paste failed: %s", e.message);
                }
            });
        }

        public static void paste_image (VectorCanvas c, Bytes data, string mime) {
            try {
                var pix = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_bytes (data));
                var im = new ImageNode ();
                im.asset = c.doc.store_asset (data, mime);
                im.mime = mime;
                im.pixel_width = pix.width;
                im.pixel_height = pix.height;
                var center = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
                im.matrix = Transforms.translate (center.x - pix.width / 2.0, center.y - pix.height / 2.0);
                var list = new Gee.ArrayList<Node> ();
                list.add (im);
                insert_nodes (c, list, "place");
            } catch (Error e) {
                warning ("Vector: paste image failed: %s", e.message);
            }
        }

        public static void insert_nodes (VectorCanvas c, Gee.ArrayList<Node> nodes, string mode) {
            if (nodes.size == 0) return;
            c.doc.begin (_("Paste"));
            var target = c.isolation ?? c.doc.active_layer;
            if (target == null) {
                target = c.doc.new_layer (_("Layer 1"));
                c.doc.layers.add (target);
                c.doc.active_layer = target;
            }
            if (mode == "center") {
                var box = Rect (0, 0, -1, -1);
                bool first = true;
                foreach (var n in nodes) {
                    var b = n.geometric_bounds ();
                    if (b.w < 0) continue;
                    box = first ? b : box.union (b);
                    first = false;
                }
                if (!first) {
                    var view = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
                    var m = Transforms.translate (view.x - box.cx (), view.y - box.cy ());
                    foreach (var n in nodes) n.apply_transform (m, false);
                }
            }
            foreach (var n in nodes) {
                clear_ids (n);
                target.add (n);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (nodes);
        }

        public static void paste_text (VectorCanvas c, string text, string mode) {
            Gee.ArrayList<Node> nodes;
            try {
                if (text.strip ().has_prefix ("<")) {
                    var imported = SvgReader.parse (text);
                    nodes = new Gee.ArrayList<Node> ();
                    foreach (var l in imported.layers) {
                        foreach (var n in l.children.to_array ()) {
                            l.remove (n);
                            nodes.add (n);
                        }
                    }
                    foreach (var a in imported.assets.values) c.doc.assets[a.id] = a;
                } else {
                    nodes = NativeFormat.nodes_from_string (text, c.doc);
                }
            } catch (Error e) {
                return;
            }
            if (nodes.size == 0) return;
            c.doc.begin (_("Paste"));
            var target = c.isolation ?? c.doc.active_layer;
            if (target == null) {
                target = c.doc.new_layer (_("Layer 1"));
                c.doc.layers.add (target);
                c.doc.active_layer = target;
            }
            int index = target.children.size;
            if ((mode == "front" || mode == "back") && c.selection.size > 0) {
                var ref_node = mode == "front" ? c.selection[c.selection.size - 1] : c.selection[0];
                if (ref_node.parent != null) {
                    target = ref_node.parent;
                    index = target.children.index_of (ref_node) + (mode == "front" ? 1 : 0);
                }
            }
            var box = Rect (0, 0, -1, -1);
            bool first = true;
            foreach (var n in nodes) {
                var b = n.geometric_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            if (mode == "center" && box.w >= 0) {
                var view = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
                var m = Transforms.translate (view.x - box.cx (), view.y - box.cy ());
                foreach (var n in nodes) n.apply_transform (m, false);
            }
            foreach (var n in nodes) {
                clear_ids (n);
                target.add (n, index++);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (nodes);
        }

        public static void group (VectorCanvas c) {
            var list = ordered (c);
            if (list.size == 0) return;
            c.doc.begin (_("Group"));
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var g = new GroupNode ();
            foreach (var n in list) {
                if (n.parent == parent && parent.children.index_of (n) < index) index--;
            }
            foreach (var n in list) n.parent.remove (n);
            foreach (var n in list) g.add (n);
            parent.add (g, int.max (0, int.min (index + 1, parent.children.size)));
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (g);
        }

        public static void ungroup (VectorCanvas c) {
            var result = new Gee.ArrayList<Node> ();
            c.doc.begin (_("Ungroup"));
            bool any = false;
            foreach (var n in ordered (c)) {
                var g = n as GroupNode;
                if (g == null || g.is_layer || g.parent == null || g.generated (null) != null) {
                    result.add (n);
                    continue;
                }
                if (g.clip && g.children.size > 0) g.children[0].hidden = false;
                var parent = g.parent;
                int index = parent.children.index_of (g);
                parent.remove (g);
                var kids = new Gee.ArrayList<Node> ();
                kids.add_all (g.children);
                foreach (var k in kids) {
                    g.remove (k);
                    if (g.opacity < 1) k.opacity *= g.opacity;
                    parent.add (k, index++);
                    result.add (k);
                }
                any = true;
            }
            if (any) c.doc.commit ();
            else c.doc.cancel ();
            c.set_selection (result);
        }

        public static void arrange (VectorCanvas c, string how) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Arrange"));
            var list = ordered (c);
            if (how == "front" || how == "backward") {
                var rev = new Gee.ArrayList<Node> ();
                for (int i = list.size - 1; i >= 0; i--) rev.add (list[i]);
                list = rev;
            }
            foreach (var n in list) {
                var p = n.parent;
                if (p == null) continue;
                int i = p.children.index_of (n);
                p.children.remove_at (i);
                int target;
                switch (how) {
                    case "front": target = p.children.size; break;
                    case "back": target = 0; break;
                    case "forward": target = int.min (i + 1, p.children.size); break;
                    default: target = int.max (i - 1, 0); break;
                }
                p.children.insert (target, n);
            }
            if (how == "back") {
                foreach (var n in ordered (c)) {
                    var p = n.parent;
                    if (p == null) continue;
                    p.children.remove (n);
                    p.children.insert (0, n);
                }
            }
            c.doc.commit ();
        }

        public static void move_to_layer (VectorCanvas c, GroupNode layer) {
            c.doc.begin (_("Move to Layer"));
            foreach (var n in ordered (c)) {
                if (n.parent != null) n.parent.remove (n);
                layer.add (n);
            }
            c.doc.commit ();
        }

        public static void set_locked (VectorCanvas c, bool locked) {
            c.doc.begin (locked ? _("Lock") : _("Unlock All"));
            if (locked) foreach (var n in c.selection) n.locked = true;
            else foreach (var n in c.doc.all_nodes ()) n.locked = false;
            c.doc.commit ();
            if (locked) c.clear_selection ();
        }

        public static void set_hidden (VectorCanvas c, bool hidden) {
            c.doc.begin (hidden ? _("Hide") : _("Show All"));
            if (hidden) foreach (var n in c.selection) n.hidden = true;
            else foreach (var n in c.doc.all_nodes ()) n.hidden = false;
            c.doc.commit ();
            if (hidden) c.clear_selection ();
        }

        public static void transform (VectorCanvas c, Cairo.Matrix m, string label, bool each = false) {
            if (c.selection.size == 0) return;
            c.doc.begin (label);
            foreach (var n in c.selection) n.apply_transform (m, c.scale_strokes);
            c.doc.commit ();
        }

        public static void flip (VectorCanvas c, bool horizontal) {
            var b = c.selection_bounds ();
            if (b.w < 0) return;
            transform (c, Transforms.reflect (horizontal ? 90 : 0, Point (b.cx (), b.cy ())), horizontal ? _("Flip Horizontal") : _("Flip Vertical"));
        }

        public static void rotate (VectorCanvas c, double degrees) {
            var b = c.selection_bounds ();
            if (b.w < 0) return;
            transform (c, Transforms.rotate (degrees * Math.PI / 180, Point (b.cx (), b.cy ())), _("Rotate"));
        }

        public static void transform_each (VectorCanvas c, double sx, double sy, double dx, double dy, double angle, bool flip_h, bool flip_v, int origin, bool random, int copies) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Transform Each"));
            var rand = new GLib.Rand.with_seed (11);
            var made = new Gee.ArrayList<Node> ();
            foreach (var n in ordered (c)) {
                Node target = n;
                for (int k = 0; k <= copies; k++) {
                    if (k > 0) {
                        target = target.clone ();
                        clear_ids (target);
                        n.parent.add (target, n.parent.children.index_of (n) + k);
                        made.add (target);
                    }
                    var b = target.geometric_bounds ();
                    var pts = SelectTool.handle_points (b);
                    var o = origin >= 0 && origin < 8 ? pts[origin] : Point (b.cx (), b.cy ());
                    double f = random ? rand.next_double () : 1;
                    var m = Transforms.scale (1 + (sx - 1) * f, 1 + (sy - 1) * f, o);
                    if (flip_h) m = Transforms.multiply (m, Transforms.reflect (90, o));
                    if (flip_v) m = Transforms.multiply (m, Transforms.reflect (0, o));
                    m = Transforms.multiply (m, Transforms.rotate (angle * f * Math.PI / 180, o));
                    m = Transforms.multiply (m, Transforms.translate (dx * f, dy * f));
                    target.apply_transform (m, c.scale_strokes);
                }
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            if (made.size > 0) c.set_selection (made);
        }

        public static void align (VectorCanvas c, string how, string relative) {
            var list = ordered (c);
            if (list.size == 0) return;
            Rect target;
            Node? key = null;
            if (relative == "artboard") {
                var a = c.doc.current_artboard ();
                if (a == null) return;
                target = a.rect ();
            } else if (relative == "key") {
                key = c.selection[c.selection.size - 1];
                target = key.geometric_bounds ();
            } else {
                if (list.size < 2) {
                    var a = c.doc.current_artboard ();
                    if (a == null) return;
                    target = a.rect ();
                } else {
                    target = c.selection_bounds ();
                }
            }
            c.doc.begin (_("Align"));
            foreach (var n in list) {
                if (n == key) continue;
                var b = n.geometric_bounds ();
                double dx = 0, dy = 0;
                switch (how) {
                    case "left": dx = target.x - b.x; break;
                    case "hcenter": dx = target.cx () - b.cx (); break;
                    case "right": dx = target.x + target.w - b.x - b.w; break;
                    case "top": dy = target.y - b.y; break;
                    case "vcenter": dy = target.cy () - b.cy (); break;
                    case "bottom": dy = target.y + target.h - b.y - b.h; break;
                }
                n.apply_transform (Transforms.translate (dx, dy), false);
            }
            c.doc.commit ();
        }

        public static void distribute (VectorCanvas c, string how, double spacing = double.NAN) {
            var list = ordered (c);
            if (list.size < 3 && spacing.is_nan ()) return;
            if (list.size < 2) return;
            bool horizontal = how.has_prefix ("h");
            list.sort ((a, b) => {
                var ba = a.geometric_bounds ();
                var bb = b.geometric_bounds ();
                double va = horizontal ? ba.cx () : ba.cy (), vb = horizontal ? bb.cx () : bb.cy ();
                return va < vb ? -1 : va > vb ? 1 : 0;
            });
            c.doc.begin (_("Distribute"));
            var first = list[0].geometric_bounds ();
            var last = list[list.size - 1].geometric_bounds ();
            if (how.has_suffix ("space")) {
                double total = 0;
                foreach (var n in list) total += horizontal ? n.geometric_bounds ().w : n.geometric_bounds ().h;
                double span = horizontal ? last.x + last.w - first.x : last.y + last.h - first.y;
                double gap = spacing.is_nan () ? (span - total) / (list.size - 1) : spacing;
                double pos = horizontal ? first.x : first.y;
                foreach (var n in list) {
                    var b = n.geometric_bounds ();
                    double d = pos - (horizontal ? b.x : b.y);
                    n.apply_transform (horizontal ? Transforms.translate (d, 0) : Transforms.translate (0, d), false);
                    pos += (horizontal ? b.w : b.h) + gap;
                }
            } else {
                double a = horizontal ? first.cx () : first.cy ();
                double z = horizontal ? last.cx () : last.cy ();
                for (int i = 1; i < list.size - 1; i++) {
                    var b = list[i].geometric_bounds ();
                    double target = a + (z - a) * i / (list.size - 1);
                    double d = target - (horizontal ? b.cx () : b.cy ());
                    list[i].apply_transform (horizontal ? Transforms.translate (d, 0) : Transforms.translate (0, d), false);
                }
            }
            c.doc.commit ();
        }

        public static Gee.ArrayList<PathNode> selected_paths (VectorCanvas c) {
            var list = new Gee.ArrayList<PathNode> ();
            foreach (var n in ordered (c)) PathEdit.collect (n, list);
            return list;
        }

        public static PathNode as_path (Node n) {
            var pn = n as PathNode;
            if (pn != null) return pn;
            var r = new PathNode ();
            n.copy_common (r);
            r.mask = null;
            var o = n.outline ();
            r.path = o != null ? o : new PathData ();
            if (r.appearance.size == 0) r.appearance.add (new PaintLayer.fill (new Paint.hex ("#000000")));
            return r;
        }

        public static void pathfinder (VectorCanvas c, PathfinderOp op) {
            var list = ordered (c);
            if (list.size < 1) return;
            if (list.size < 2 && op != PathfinderOp.DIVIDE && op != PathfinderOp.OUTLINE) return;
            var nodes = new Gee.ArrayList<PathNode> ();
            foreach (var n in list) nodes.add (as_path (n));
            var paths = new Gee.ArrayList<PathData> ();
            var rules = new bool[nodes.size];
            for (int i = 0; i < nodes.size; i++) {
                paths.add (nodes[i].render_path ());
                rules[i] = nodes[i].even_odd;
            }
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var made = new Gee.ArrayList<Node> ();
            var arr = new Arrangement (paths, rules);
            int n = nodes.size;
            switch (op) {
                case PathfinderOp.UNION:
                case PathfinderOp.INTERSECT:
                case PathfinderOp.EXCLUDE:
                case PathfinderOp.SUBTRACT:
                case PathfinderOp.MINUS_BACK: {
                    PathData result;
                    PathNode style;
                    if (op == PathfinderOp.UNION) {
                        result = arr.region ((s) => {
                            foreach (bool v in s) if (v) return true;
                            return false;
                        });
                        style = nodes[n - 1];
                    } else if (op == PathfinderOp.INTERSECT) {
                        result = arr.region ((s) => {
                            foreach (bool v in s) if (!v) return false;
                            return true;
                        });
                        style = nodes[n - 1];
                    } else if (op == PathfinderOp.EXCLUDE) {
                        result = arr.region ((s) => {
                            int k = 0;
                            foreach (bool v in s) if (v) k++;
                            return k % 2 == 1;
                        });
                        style = nodes[n - 1];
                    } else if (op == PathfinderOp.SUBTRACT) {
                        result = arr.region ((s) => {
                            if (!s[0]) return false;
                            for (int i = 1; i < s.length; i++) if (s[i]) return false;
                            return true;
                        });
                        style = nodes[0];
                    } else {
                        result = arr.region ((s) => {
                            if (!s[s.length - 1]) return false;
                            for (int i = 0; i < s.length - 1; i++) if (s[i]) return false;
                            return true;
                        });
                        style = nodes[n - 1];
                    }
                    var r = style.clone () as PathNode;
                    r.id = "";
                    r.live = null;
                    r.corners.clear ();
                    r.modes.clear ();
                    r.even_odd = false;
                    r.path = result;
                    if (!result.is_empty ()) made.add (r);
                    break;
                }
                case PathfinderOp.DIVIDE:
                case PathfinderOp.TRIM:
                case PathfinderOp.MERGE:
                case PathfinderOp.CROP: {
                    var faces = arr.faces ();
                    var groups = new Gee.HashMap<string, Gee.ArrayList<PathData>> ();
                    var owners = new Gee.HashMap<string, PathNode> ();
                    foreach (var f in faces) {
                        int top = f.topmost ();
                        if (top < 0) continue;
                        if (op == PathfinderOp.CROP) {
                            if (top == n - 1 && !f.inside[n - 1]) continue;
                            if (!f.inside[n - 1]) continue;
                            int below = -1;
                            for (int i = n - 2; i >= 0; i--) if (f.inside[i]) {
                                below = i;
                                break;
                            }
                            if (below < 0) continue;
                            top = below;
                        }
                        var owner = nodes[top];
                        string key;
                        if (op == PathfinderOp.DIVIDE) key = "f%d".printf (made.size + groups.size);
                        else if (op == PathfinderOp.MERGE) key = merge_key (owner);
                        else key = "o%d".printf (top);
                        if (!groups.has_key (key)) {
                            groups[key] = new Gee.ArrayList<PathData> ();
                            owners[key] = owner;
                        }
                        groups[key].add (f.path);
                    }
                    var g = new GroupNode ();
                    var keys = new Gee.ArrayList<string> ();
                    keys.add_all (groups.keys);
                    keys.sort ((a, b) => nodes.index_of (owners[a]) - nodes.index_of (owners[b]));
                    foreach (var key in keys) {
                        var owner = owners[key];
                        var r = owner.clone () as PathNode;
                        r.id = "";
                        r.live = null;
                        r.corners.clear ();
                        r.modes.clear ();
                        r.even_odd = false;
                        if (op != PathfinderOp.DIVIDE) {
                            r.appearance.clear ();
                            var f = owner.first_fill ();
                            if (f != null) r.appearance.add (f.copy ());
                        }
                        r.path = groups[key].size == 1 ? groups[key][0] : CurveBoolean.unite_all (groups[key]);
                        g.add (r);
                    }
                    made.add (g);
                    break;
                }
                case PathfinderOp.OUTLINE: {
                    var g = new GroupNode ();
                    for (int i = 0; i < n; i++) {
                        var f = nodes[i].first_fill ();
                        var color = f != null ? f.paint.copy () : new Paint.hex ("#000000");
                        foreach (var piece in arr.open_pieces (i)) {
                            var r = new PathNode.with_path (piece);
                            r.appearance.add (new PaintLayer.line (color.copy (), 0.5));
                            g.add (r);
                        }
                    }
                    made.add (g);
                    break;
                }
            }
            c.doc.begin (_("Pathfinder"));
            foreach (var node in list) if (node.parent != null) {
                if (node.parent == parent && parent.children.index_of (node) <= index) index--;
                node.parent.remove (node);
            }
            index = int.max (-1, index);
            foreach (var m in made) parent.add (m, ++index);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (made);
        }

        private static string merge_key (PathNode n) {
            var f = n.first_fill ();
            if (f == null) return "none";
            return f.paint.kind.to_id () + f.paint.representative ().to_hex ();
        }

        public static void compound (VectorCanvas c, bool make) {
            c.doc.begin (make ? _("Make Compound Path") : _("Release Compound Path"));
            var made = new Gee.ArrayList<Node> ();
            if (make) {
                var list = selected_paths (c);
                if (list.size < 2) {
                    c.doc.cancel ();
                    return;
                }
                var top = list[list.size - 1];
                var r = top.clone () as PathNode;
                r.id = "";
                r.live = null;
                r.corners.clear ();
                r.path = new PathData ();
                foreach (var pn in list) r.path.append (pn.render_path ());
                var parent = top.parent;
                int index = parent.children.index_of (top);
                foreach (var pn in list) if (pn.parent != null) pn.parent.remove (pn);
                parent.add (r, int.min (index, parent.children.size));
                made.add (r);
            } else {
                foreach (var pn in selected_paths (c)) {
                    var contours = PathOps.contours (pn.path);
                    if (contours.size < 2) continue;
                    var parent = pn.parent;
                    int index = parent.children.index_of (pn);
                    parent.remove (pn);
                    foreach (var contour in contours) {
                        var r = pn.clone () as PathNode;
                        r.id = "";
                        r.path = contour;
                        r.modes.clear ();
                        parent.add (r, index++);
                        made.add (r);
                    }
                }
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (made);
        }

        public static void reverse_direction (VectorCanvas c) {
            c.doc.begin (_("Reverse Path Direction"));
            foreach (var pn in selected_paths (c)) {
                PathEdit.detach_live (pn);
                pn.path = PathOps.reversed (pn.path);
                pn.modes.clear ();
            }
            c.doc.commit ();
        }

        public static void even_odd (VectorCanvas c, bool value) {
            c.doc.begin (_("Fill Rule"));
            foreach (var pn in selected_paths (c)) pn.even_odd = value;
            c.doc.commit ();
        }

        public static void offset_path (VectorCanvas c, double distance, JoinKind join, double miter) {
            var list = selected_paths (c);
            if (list.size == 0) return;
            c.doc.begin (_("Offset Path"));
            var made = new Gee.ArrayList<Node> ();
            foreach (var pn in list) {
                var r = pn.clone () as PathNode;
                r.id = "";
                r.live = null;
                r.corners.clear ();
                r.modes.clear ();
                r.path = CurveOffset.offset (pn.render_path (), distance, join, miter);
                pn.parent.add (r, pn.parent.children.index_of (pn) + (distance > 0 ? 0 : 1));
                made.add (r);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (made);
        }

        public static GroupNode? outline_node (PathNode pn) {
            var group = new GroupNode ();
            var path = Renderer.vector_effects (pn.render_path (), pn.effects);
            foreach (var l in pn.appearance) {
                if (!l.visible || !l.paint.visible ()) continue;
                var geo = Renderer.vector_effects (path, l.effects);
                var r = new PathNode ();
                if (l.stroke) {
                    PathData outline;
                    if (l.profile.size > 0) outline = CurveOffset.variable (geo, l.width, l.profile, l.cap);
                    else {
                        var src = l.dashes.length > 0 ? CurveOffset.dash (geo, l.dashes, l.dash_offset) : geo;
                        outline = CurveOffset.stroke (src, l.width, l.join, l.cap, l.miter, l.align);
                    }
                    r.path = outline;
                } else {
                    r.path = geo.copy ();
                    r.even_odd = pn.even_odd;
                }
                var fill = new PaintLayer.fill (l.paint.copy ());
                fill.opacity = l.opacity;
                fill.blend = l.blend;
                r.appearance.add (fill);
                group.add (r);
            }
            return group;
        }

        public static void outline_stroke (VectorCanvas c) {
            var list = selected_paths (c);
            if (list.size == 0) return;
            c.doc.begin (_("Outline Stroke"));
            var made = new Gee.ArrayList<Node> ();
            foreach (var pn in list) {
                if (pn.first_stroke () == null) continue;
                var g = outline_node (pn);
                Node result = g.children.size == 1 ? g.children[0] : g;
                if (result == g.children[0]) g.remove (result);
                result.opacity = pn.opacity;
                result.blend = pn.blend;
                result.name = pn.name;
                var parent = pn.parent;
                int index = parent.children.index_of (pn);
                parent.remove (pn);
                parent.add (result, index);
                made.add (result);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (made);
        }

        public static int simplify (VectorCanvas c, double tolerance, double corner_angle, bool straight) {
            int before = 0, after = 0;
            c.doc.begin (_("Simplify"));
            foreach (var pn in selected_paths (c)) {
                PathEdit.detach_live (pn);
                before += PathSimplify.anchor_count (pn.path);
                pn.path = PathSimplify.simplify (pn.path, tolerance, corner_angle, straight);
                pn.modes.clear ();
                after += PathSimplify.anchor_count (pn.path);
            }
            c.doc.commit ();
            return before - after;
        }

        public static void add_anchor_points (VectorCanvas c) {
            c.doc.begin (_("Add Anchor Points"));
            foreach (var pn in selected_paths (c)) {
                PathEdit.detach_live (pn);
                var p = pn.path;
                for (int i = p.segs.size - 1; i >= 1; i--) {
                    if (p.segs[i].kind == SegKind.LINE || p.segs[i].kind == SegKind.CURVE) p = PathOps.insert_point (p, i, 0.5);
                }
                pn.path = p;
                pn.modes.clear ();
            }
            c.doc.commit ();
        }

        public static void join_paths (VectorCanvas c) {
            var list = selected_paths (c);
            if (list.size == 1 && !PathOps.all_closed (list[0].path)) {
                c.doc.begin (_("Join"));
                PathEdit.detach_live (list[0]);
                list[0].path.close ();
                c.doc.commit ();
                return;
            }
            if (list.size < 2) return;
            c.doc.begin (_("Join"));
            var base_node = list[0];
            PathEdit.detach_live (base_node);
            var joined = base_node.path;
            for (int i = 1; i < list.size; i++) {
                joined = PathOps.join (joined, list[i].render_path ());
                list[i].parent.remove (list[i]);
            }
            base_node.path = joined;
            base_node.modes.clear ();
            c.doc.commit ();
            c.select_only (base_node);
        }

        public static void average_points (VectorCanvas c, bool horizontal, bool vertical) {
            double sx = 0, sy = 0;
            int n = 0;
            foreach (var e in c.anchors.entries) foreach (int a in e.value) {
                sx += e.key.path.segs[a].x;
                sy += e.key.path.segs[a].y;
                n++;
            }
            if (n < 2) return;
            sx /= n;
            sy /= n;
            c.doc.begin (_("Average"));
            foreach (var e in c.anchors.entries) foreach (int a in e.value) {
                var s = e.key.path.segs[a];
                var set = new Gee.ArrayList<int> ();
                set.add (a);
                PathEdit.move_anchors (e.key, set, horizontal ? sx - s.x : 0, vertical ? sy - s.y : 0);
            }
            c.doc.commit ();
        }

        public static void clipping_mask (VectorCanvas c, bool make) {
            if (make) {
                var list = ordered (c);
                if (list.size < 2) return;
                c.doc.begin (_("Make Clipping Mask"));
                var top = list[list.size - 1];
                var parent = top.parent;
                int index = parent.children.index_of (top);
                var g = new GroupNode ();
                g.clip = true;
                foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
                foreach (var n in list) n.parent.remove (n);
                var clip_node = top;
                clip_node.appearance.clear ();
                g.add (clip_node);
                for (int i = 0; i < list.size - 1; i++) g.add (list[i]);
                parent.add (g, int.max (0, int.min (index + 1, parent.children.size)));
                c.doc.ensure_ids ();
                c.doc.commit ();
                c.select_only (g);
            } else {
                c.doc.begin (_("Release Clipping Mask"));
                var result = new Gee.ArrayList<Node> ();
                foreach (var n in ordered (c)) {
                    var g = n as GroupNode;
                    if (g == null || !g.clip) continue;
                    g.clip = false;
                    if (g.children.size > 0) {
                        var cp = g.children[0];
                        if (cp.appearance.size == 0) cp.appearance.add (new PaintLayer.line (new Paint (), 1));
                    }
                    result.add (g);
                }
                c.doc.commit ();
                c.set_selection (result);
            }
        }

        public static void opacity_mask (VectorCanvas c, bool make, bool clip = true, bool invert = false) {
            if (make) {
                var list = ordered (c);
                if (list.size < 2) return;
                c.doc.begin (_("Make Opacity Mask"));
                var mask = list[list.size - 1];
                mask.parent.remove (mask);
                Node target;
                if (list.size == 2) {
                    target = list[0];
                } else {
                    var parent = list[0].parent;
                    int index = parent.children.index_of (list[0]);
                    var g = new GroupNode ();
                    for (int i = 0; i < list.size - 1; i++) {
                        list[i].parent.remove (list[i]);
                        g.add (list[i]);
                    }
                    parent.add (g, index);
                    target = g;
                }
                target.mask = mask;
                target.mask_clip = clip;
                target.mask_invert = invert;
                mask.parent = null;
                c.doc.ensure_ids ();
                c.doc.commit ();
                c.select_only (target);
            } else {
                c.doc.begin (_("Release Opacity Mask"));
                var result = new Gee.ArrayList<Node> ();
                foreach (var n in ordered (c)) {
                    result.add (n);
                    if (n.mask == null) continue;
                    var m = n.mask;
                    n.mask = null;
                    n.parent.add (m, n.parent.children.index_of (n) + 1);
                    result.add (m);
                }
                c.doc.ensure_ids ();
                c.doc.commit ();
                c.set_selection (result);
            }
        }

        public static BlendNode? make_blend (VectorCanvas c) {
            var list = ordered (c);
            if (list.size < 2) return null;
            c.doc.begin (_("Make Blend"));
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var b = new BlendNode ();
            b.spacing = "smooth";
            foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
            foreach (var n in list) n.parent.remove (n);
            foreach (var n in list) b.add (n);
            parent.add (b, int.max (0, int.min (index + 1, parent.children.size)));
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (b);
            return b;
        }

        public static void replace_spine (VectorCanvas c) {
            var list = ordered (c);
            BlendNode? blend = null;
            PathNode? spine = null;
            foreach (var n in list) {
                if (n is BlendNode) blend = (BlendNode) n;
                else if (n is PathNode) spine = (PathNode) n;
            }
            if (blend == null || spine == null) return;
            c.doc.begin (_("Replace Spine"));
            blend.spine = spine.render_path ().copy ();
            spine.parent.remove (spine);
            c.doc.commit ();
            c.select_only (blend);
        }

        public static void release_group_like (VectorCanvas c) {
            var result = new Gee.ArrayList<Node> ();
            c.doc.begin (_("Release"));
            foreach (var n in ordered (c)) {
                var g = n as GroupNode;
                if (g == null || g.parent == null || g.is_layer) continue;
                if (g is ChartNode || g is Shape3DNode) continue;
                var parent = g.parent;
                int index = parent.children.index_of (g);
                parent.remove (g);
                var kids = new Gee.ArrayList<Node> ();
                kids.add_all (g.children);
                foreach (var k in kids) {
                    g.remove (k);
                    parent.add (k, index++);
                    result.add (k);
                }
                var lp = g as LivePaintNode;
                if (lp != null) foreach (var k in kids) {
                    var s = k.first_stroke ();
                    if (s == null) k.appearance.add (new PaintLayer.line (new Paint.hex ("#000000"), 0.5));
                }
            }
            c.doc.commit ();
            c.set_selection (result);
        }

        public static Node expand_node (Node n, VectorDocument doc) {
            var g = n as GroupNode;
            if (g != null) {
                var gen = g.generated (doc);
                if (gen != null) {
                    var out_group = new GroupNode ();
                    out_group.name = g.name;
                    out_group.opacity = g.opacity;
                    out_group.blend = g.blend;
                    foreach (var e in g.effects) out_group.effects.add (e.copy ());
                    foreach (var ch in gen.children) out_group.add (ch.clone ());
                    return out_group;
                }
            }
            var sym = n as SymbolNode;
            if (sym != null) {
                var art = sym.resolve (doc);
                if (art != null) {
                    art.opacity = sym.opacity;
                    return art;
                }
            }
            return n.clone ();
        }

        public static void expand (VectorCanvas c) {
            var result = new Gee.ArrayList<Node> ();
            c.doc.begin (_("Expand"));
            foreach (var n in ordered (c)) {
                var parent = n.parent;
                if (parent == null) continue;
                int index = parent.children.index_of (n);
                var e = expand_node (n, c.doc);
                clear_ids (e);
                parent.remove (n);
                parent.add (e, index);
                result.add (e);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (result);
        }

        public static Node expand_appearance_node (Node n, VectorDocument doc) {
            var pn = n as PathNode;
            var tn = n as TextNode;
            if (pn != null || tn != null) {
                var base_path = pn != null ? pn.render_path () : TextLayout.to_path (tn);
                var geo = Renderer.vector_effects (base_path, n.effects);
                var group = new GroupNode ();
                group.opacity = n.opacity;
                group.blend = n.blend;
                group.mask = n.mask != null ? n.mask.clone () : null;
                foreach (var e in n.effects) if (e.is_raster ()) group.effects.add (e.copy ());
                foreach (var l in n.appearance) {
                    if (!l.visible || !l.paint.visible ()) continue;
                    var lg = Renderer.vector_effects (geo, l.effects);
                    if (l.stroke && l.brush != "") {
                        var brush = doc.find_brush (l.brush);
                        if (brush != null) {
                            var ctx = new RenderContext (doc);
                            var expanded = Brushes.expand (lg, l, brush, ctx);
                            foreach (var ch in expanded.children) group.add (ch);
                            continue;
                        }
                    }
                    var piece = new PathNode.with_path (lg);
                    var copy = l.copy ();
                    copy.effects.clear ();
                    piece.appearance.add (copy);
                    piece.even_odd = pn != null && pn.even_odd;
                    group.add (piece);
                }
                return group.children.size == 1 && group.effects.size == 0 && group.mask == null && group.opacity >= 1 ? group.children[0] : group;
            }
            var g = n as GroupNode;
            if (g != null && g.generated (doc) == null) {
                var out_group = g.clone () as GroupNode;
                out_group.children.clear ();
                foreach (var ch in g.children) out_group.add (expand_appearance_node (ch, doc));
                return out_group;
            }
            return expand_node (n, doc);
        }

        public static void expand_appearance (VectorCanvas c) {
            var result = new Gee.ArrayList<Node> ();
            c.doc.begin (_("Expand Appearance"));
            foreach (var n in ordered (c)) {
                var parent = n.parent;
                if (parent == null) continue;
                int index = parent.children.index_of (n);
                var e = expand_appearance_node (n, c.doc);
                if (e.parent != null) e.parent.remove (e);
                clear_ids (e);
                parent.remove (n);
                parent.add (e, index);
                result.add (e);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (result);
        }

        public static void text_outlines (VectorCanvas c) {
            var result = new Gee.ArrayList<Node> ();
            c.doc.begin (_("Create Outlines"));
            foreach (var n in ordered (c)) {
                var tn = n as TextNode;
                if (tn == null) {
                    result.add (n);
                    continue;
                }
                var group = new GroupNode ();
                group.name = tn.display_name ();
                foreach (var part in TextLayout.parts (tn)) {
                    var pn = new PathNode.with_path (part.path.copy ());
                    foreach (var l in tn.appearance) {
                        var copy = l.copy ();
                        if (part.color != null && !copy.stroke && copy.paint.kind == PaintKind.SOLID) copy.paint = new Paint.solid (part.color.copy ());
                        pn.appearance.add (copy);
                    }
                    foreach (var e in tn.effects) pn.effects.add (e.copy ());
                    group.add (pn);
                }
                group.opacity = tn.opacity;
                group.blend = tn.blend;
                Node result_node = group.children.size == 1 ? group.children[0] : group;
                if (result_node != group) {
                    group.remove (result_node);
                    result_node.opacity = tn.opacity;
                    result_node.blend = tn.blend;
                }
                var parent = tn.parent;
                int index = parent.children.index_of (tn);
                parent.remove (tn);
                parent.add (result_node, index);
                result.add (result_node);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (result);
        }

        public static void thread_text (VectorCanvas c) {
            var texts = new Gee.ArrayList<TextNode> ();
            foreach (var n in ordered (c)) {
                var t = n as TextNode;
                if (t != null && t.mode == "area") texts.add (t);
            }
            if (texts.size < 2) return;
            c.doc.begin (_("Thread Text"));
            var head = texts[0];
            var builder = new StringBuilder (head.text);
            for (int i = 1; i < texts.size; i++) {
                if (texts[i].text != "") {
                    if (builder.len > 0) builder.append ("\n");
                    builder.append (texts[i].text);
                    texts[i].text = "";
                }
                texts[i - 1].thread_next = texts[i].id;
                texts[i].style = head.style.copy ();
                texts[i].para = head.para.copy ();
            }
            head.text = builder.str;
            c.doc.commit ();
            TextLayout.invalidate ();
        }

        public static void unthread_text (VectorCanvas c) {
            c.doc.begin (_("Remove Threading"));
            foreach (var n in c.selection) {
                var t = n as TextNode;
                if (t == null) continue;
                TextNode? cur = TextLayout.chain_head (t);
                while (cur != null) {
                    var info = TextLayout.frame_info (cur);
                    var head = TextLayout.chain_head (cur);
                    var next = TextLayout.next_in_chain (cur);
                    if (cur != head) cur.text = head.text.substring (info.start, info.end - info.start);
                    cur.thread_next = "";
                    cur = next;
                }
                var h = TextLayout.chain_head (t);
                var hi = TextLayout.frame_info (h);
                h.text = h.text.substring (0, hi.end);
            }
            c.doc.commit ();
            TextLayout.invalidate ();
        }

        public static LivePaintNode? make_live_paint (VectorCanvas c) {
            var list = ordered (c);
            if (list.size == 0) return null;
            c.doc.begin (_("Make Live Paint"));
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var lp = new LivePaintNode ();
            foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
            foreach (var n in list) n.parent.remove (n);
            foreach (var n in list) {
                var pn = as_path (n);
                lp.add (pn);
                var f = n.first_fill ();
                if (f != null && f.paint.visible () && PathOps.all_closed (pn.path)) lp.fills.add (new LivePaintFill (Arrangement.interior_point (pn.path), f.paint.copy ()));
            }
            parent.add (lp, int.max (0, int.min (index + 1, parent.children.size)));
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (lp);
            return lp;
        }

        public static void make_repeat (VectorCanvas c, string mode) {
            var list = ordered (c);
            if (list.size == 0) return;
            c.doc.begin (_("Make Repeat"));
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var r = new RepeatNode ();
            r.mode = mode;
            var box = c.selection_bounds ();
            r.radius = double.max (box.w, box.h) * 1.2;
            r.hspace = box.w * 0.2;
            r.vspace = box.h * 0.2;
            r.axis_offset = box.w * 0.1;
            foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
            foreach (var n in list) n.parent.remove (n);
            foreach (var n in list) r.add (n);
            parent.add (r, int.max (0, int.min (index + 1, parent.children.size)));
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (r);
        }

        public static EnvelopeNode? make_envelope (VectorCanvas c, string mode, string style = "arc", double bend = 0.5, int rows = 2, int cols = 2) {
            var list = ordered (c);
            if (list.size == 0) return null;
            Node? top_shape = null;
            if (mode == "object") {
                if (list.size < 2) return null;
                top_shape = list[list.size - 1];
                list.remove (top_shape);
            }
            c.doc.begin (_("Make Envelope"));
            var parent = list[list.size - 1].parent;
            int index = parent.children.index_of (list[list.size - 1]);
            var env = new EnvelopeNode ();
            foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
            foreach (var n in list) n.parent.remove (n);
            foreach (var n in list) env.add (n);
            env.style = style;
            env.bend = bend;
            if (mode == "mesh") {
                env.mode = "mesh";
                env.init_mesh (rows, cols);
            } else if (mode == "object" && top_shape != null) {
                env.mode = "mesh";
                env.init_mesh (8, 8);
                var shape = top_shape.outline ();
                if (shape != null) fit_mesh_to_shape (env, shape);
                if (top_shape.parent != null) top_shape.parent.remove (top_shape);
            } else if (mode == "distort") {
                env.mode = "distort";
                env.init_quad ();
            } else {
                env.mode = "warp";
            }
            parent.add (env, int.max (0, int.min (index + 1, parent.children.size)));
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (env);
            return env;
        }

        private static void fit_mesh_to_shape (EnvelopeNode env, PathData shape) {
            var box = shape.bounds ();
            int rows = env.mesh_rows, cols = env.mesh_cols;
            double len = PathOps.length (shape);
            Point[] boundary = {};
            int count = 400;
            for (int i = 0; i < count; i++) {
                Point p;
                double a;
                PathOps.point_at (shape, len * i / count, out p, out a);
                boundary += p;
            }
            Point[] top = {}, bottom = {}, left = {}, right = {};
            for (int c = 0; c <= cols; c++) {
                double x = box.x + box.w * c / cols;
                top += extreme (boundary, x, true, true);
                bottom += extreme (boundary, x, true, false);
            }
            for (int r = 0; r <= rows; r++) {
                double y = box.y + box.h * r / rows;
                left += extreme (boundary, y, false, true);
                right += extreme (boundary, y, false, false);
            }
            Point[] grid = new Point[(rows + 1) * (cols + 1)];
            for (int r = 0; r <= rows; r++) {
                double v = r / (double) rows;
                for (int c = 0; c <= cols; c++) {
                    double u = c / (double) cols;
                    var t = top[c];
                    var b = bottom[c];
                    var l = left[r];
                    var rr = right[r];
                    double x = (1 - v) * t.x + v * b.x + (1 - u) * l.x + u * rr.x - ((1 - u) * (1 - v) * top[0].x + u * (1 - v) * top[cols].x + (1 - u) * v * bottom[0].x + u * v * bottom[cols].x);
                    double y = (1 - v) * t.y + v * b.y + (1 - u) * l.y + u * rr.y - ((1 - u) * (1 - v) * top[0].y + u * (1 - v) * top[cols].y + (1 - u) * v * bottom[0].y + u * v * bottom[cols].y);
                    grid[r * (cols + 1) + c] = Point (x, y);
                }
            }
            env.grid = grid;
        }

        private static Point extreme (Point[] pts, double at, bool by_x, bool minimum) {
            Point best = pts[0];
            double best_d = double.INFINITY;
            double best_v = minimum ? double.INFINITY : -double.INFINITY;
            foreach (var p in pts) {
                double d = by_x ? (p.x - at).abs () : (p.y - at).abs ();
                if (d > 2) continue;
                double v = by_x ? p.y : p.x;
                if ((minimum && v < best_v) || (!minimum && v > best_v)) {
                    best_v = v;
                    best = p;
                    best_d = d;
                }
            }
            if (best_d == double.INFINITY) {
                foreach (var p in pts) {
                    double d = by_x ? (p.x - at).abs () : (p.y - at).abs ();
                    if (d < best_d) {
                        best_d = d;
                        best = p;
                    }
                }
            }
            return best;
        }

        public static void make_mesh (VectorCanvas c, PathNode pn, int rows, int cols) {
            c.doc.begin (_("Create Gradient Mesh"));
            var box = pn.geometric_bounds ();
            var mesh = new MeshNode ();
            var f = pn.first_fill ();
            var ink = f != null ? f.paint.representative () : new Ink.rgb (0.8, 0.8, 0.8);
            mesh.init_grid (box, rows, cols, ink);
            var parent = pn.parent;
            int index = parent.children.index_of (pn);
            parent.remove (pn);
            bool rectangular = pn.live != null && pn.live.kind == "rectangle" && pn.live.radius == 0 && pn.live.angle.abs () < 1e-9;
            Node result = mesh;
            if (!rectangular) {
                var g = new GroupNode ();
                g.clip = true;
                var clip = pn.clone () as PathNode;
                clip.appearance.clear ();
                g.add (clip);
                g.add (mesh);
                result = g;
            }
            parent.add (result, index);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (result);
            c.set_tool ("mesh");
        }

        public static void mesh_add_lines (MeshNode mesh, Point p, Ink color) {
            var box = mesh.geometric_bounds ();
            double u = ((p.x - box.x) / box.w).clamp (0.001, 0.999);
            double v = ((p.y - box.y) / box.h).clamp (0.001, 0.999);
            int rows = mesh.rows + 1, cols = mesh.cols + 1;
            var old = mesh.clone () as MeshNode;
            double[] us = {}, vs = {};
            for (int c = 0; c <= mesh.cols; c++) us += c / (double) mesh.cols;
            for (int r = 0; r <= mesh.rows; r++) vs += r / (double) mesh.rows;
            double[] nu = {}, nv = {};
            bool added = false;
            foreach (double x in us) {
                if (!added && u < x) {
                    nu += u;
                    added = true;
                }
                nu += x;
            }
            added = false;
            foreach (double y in vs) {
                if (!added && v < y) {
                    nv += v;
                    added = true;
                }
                nv += y;
            }
            mesh.rows = rows;
            mesh.cols = cols;
            mesh.vertices.clear ();
            for (int r = 0; r <= rows; r++) {
                for (int c = 0; c <= cols; c++) {
                    double uu = nu[c], vv = nv[r];
                    var pos = sample_mesh (old, uu, vv);
                    var col = sample_color (old, uu, vv);
                    bool is_new = (uu - u).abs () < 1e-9 && (vv - v).abs () < 1e-9;
                    mesh.vertices.add (new MeshVertex (pos.x, pos.y, is_new ? color.copy () : col));
                }
            }
            mesh.reset_controls ();
        }

        private static Point sample_mesh (MeshNode m, double u, double v) {
            double fu = u * m.cols, fv = v * m.rows;
            int c = int.min ((int) fu, m.cols - 1), r = int.min ((int) fv, m.rows - 1);
            double a = fu - c, b = fv - r;
            var p00 = m.at (r, c);
            var p01 = m.at (r, c + 1);
            var p10 = m.at (r + 1, c);
            var p11 = m.at (r + 1, c + 1);
            return Point (p00.x * (1 - a) * (1 - b) + p01.x * a * (1 - b) + p10.x * (1 - a) * b + p11.x * a * b, p00.y * (1 - a) * (1 - b) + p01.y * a * (1 - b) + p10.y * (1 - a) * b + p11.y * a * b);
        }

        private static Ink sample_color (MeshNode m, double u, double v) {
            double fu = u * m.cols, fv = v * m.rows;
            int c = int.min ((int) fu, m.cols - 1), r = int.min ((int) fv, m.rows - 1);
            double a = fu - c, b = fv - r;
            var top = Interpolate.ink (m.at (r, c).color, m.at (r, c + 1).color, a);
            var bottom = Interpolate.ink (m.at (r + 1, c).color, m.at (r + 1, c + 1).color, a);
            return Interpolate.ink (top, bottom, b);
        }

        public static SymbolDef? new_symbol (VectorCanvas c, string name, bool replace_with_instance = true) {
            var list = ordered (c);
            if (list.size == 0) return null;
            c.doc.begin (_("New Symbol"));
            var def = new SymbolDef ();
            def.id = c.doc.new_id ("sym");
            def.name = name;
            var box = c.selection_bounds ();
            foreach (var n in list) {
                var copy = n.clone ();
                clear_ids (copy);
                copy.apply_transform (Transforms.translate (-box.x, -box.y), false);
                def.art.add (copy);
            }
            c.doc.symbols.add (def);
            if (replace_with_instance) {
                var parent = list[list.size - 1].parent;
                int index = parent.children.index_of (list[list.size - 1]);
                foreach (var n in list) if (n.parent == parent && parent.children.index_of (n) < index) index--;
                foreach (var n in list) n.parent.remove (n);
                var inst = new SymbolNode ();
                inst.symbol = def.id;
                inst.doc = c.doc;
                inst.matrix = Transforms.translate (box.x, box.y);
                parent.add (inst, int.max (0, int.min (index + 1, parent.children.size)));
                c.doc.ensure_ids ();
                c.doc.commit ();
                c.select_only (inst);
            } else {
                c.doc.ensure_ids ();
                c.doc.commit ();
            }
            return def;
        }

        public static SymbolNode? place_symbol (VectorCanvas c, SymbolDef def, Point at) {
            var inst = new SymbolNode ();
            inst.symbol = def.id;
            inst.doc = c.doc;
            var box = def.art.geometric_bounds ();
            inst.matrix = Transforms.translate (at.x - box.cx (), at.y - box.cy ());
            c.doc.begin (_("Place Symbol"));
            var target = c.isolation ?? c.doc.active_layer;
            target.add (inst);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (inst);
            return inst;
        }

        public static void break_symbol_link (VectorCanvas c) {
            expand (c);
        }

        public static void replace_symbol (VectorCanvas c, SymbolDef def) {
            c.doc.begin (_("Replace Symbol"));
            foreach (var n in c.selection) {
                var s = n as SymbolNode;
                if (s != null) {
                    s.symbol = def.id;
                    s.overrides.clear ();
                }
            }
            c.doc.commit ();
        }

        public static void redefine_symbol (VectorCanvas c, SymbolDef def) {
            var list = ordered (c);
            if (list.size == 0) return;
            c.doc.begin (_("Redefine Symbol"));
            var box = c.selection_bounds ();
            def.art = new GroupNode ();
            foreach (var n in list) {
                var copy = n.clone ();
                clear_ids (copy);
                copy.apply_transform (Transforms.translate (-box.x, -box.y), false);
                def.art.add (copy);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
        }

        public static GraphicStyle? new_style (VectorCanvas c, string name) {
            if (c.selection.size == 0) return null;
            c.doc.begin (_("New Graphic Style"));
            var s = new GraphicStyle ();
            s.id = c.doc.new_id ("gs");
            s.name = name;
            s.capture (c.selection[0]);
            c.doc.styles.add (s);
            c.selection[0].style_id = s.id;
            c.doc.commit ();
            return s;
        }

        public static void apply_style (VectorCanvas c, GraphicStyle s) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Apply Graphic Style"));
            foreach (var n in c.selection) s.apply (n);
            c.doc.commit ();
        }

        public static void redefine_style (VectorCanvas c, GraphicStyle s) {
            if (c.selection.size == 0) return;
            c.doc.begin (_("Redefine Graphic Style"));
            s.capture (c.selection[0]);
            foreach (var n in c.doc.all_nodes ()) if (n.style_id == s.id) s.apply (n);
            c.doc.commit ();
        }

        public static void apply_brush (VectorCanvas c, string brush_id) {
            c.doc.begin (_("Apply Brush"));
            foreach (var n in c.selection) {
                var s = n.ensure_stroke ();
                if (!s.paint.visible ()) s.paint = new Paint.hex ("#000000");
                s.brush = brush_id;
            }
            c.doc.commit ();
        }

        public static BrushDef? new_brush (VectorCanvas c, string kind, string name) {
            var list = ordered (c);
            if (list.size == 0 && kind != "calligraphic") return null;
            c.doc.begin (_("New Brush"));
            var b = new BrushDef ();
            b.id = c.doc.new_id ("br");
            b.name = name;
            b.kind = kind;
            b.colorize = "tints";
            if (kind != "calligraphic") {
                var box = c.selection_bounds ();
                b.art = new GroupNode ();
                foreach (var n in list) {
                    var copy = n.clone ();
                    clear_ids (copy);
                    copy.apply_transform (Transforms.translate (-box.x, -box.y), false);
                    b.art.add (copy);
                }
            }
            c.doc.brushes.add (b);
            c.doc.ensure_ids ();
            c.doc.commit ();
            return b;
        }

        public static PatternDef? new_pattern (VectorCanvas c, string name, string tiling = "grid") {
            var list = ordered (c);
            if (list.size == 0) return null;
            c.doc.begin (_("New Pattern"));
            var p = new PatternDef ();
            p.id = c.doc.new_id ("pt");
            p.name = name;
            p.tiling = tiling;
            var box = c.selection_bounds ();
            p.w = double.max (box.w, 1);
            p.h = double.max (box.h, 1);
            foreach (var n in list) {
                var copy = n.clone ();
                clear_ids (copy);
                copy.apply_transform (Transforms.translate (-box.x, -box.y), false);
                p.tile.add (copy);
            }
            c.doc.patterns.add (p);
            var sw = new Swatch (name, new Paint ());
            sw.id = c.doc.new_id ("sw");
            sw.paint.kind = PaintKind.PATTERN;
            sw.paint.pattern = p.id;
            sw.group = _("Patterns");
            c.doc.swatches.add (sw);
            c.doc.ensure_ids ();
            c.doc.commit ();
            return p;
        }

        public static GroupNode edit_pattern_tile (VectorCanvas c, PatternDef p) {
            var g = p.tile.clone () as GroupNode;
            clear_ids (g);
            g.name = _("Pattern Tile %s").printf (p.name);
            var frame = new PathNode.with_path (new PathData.rect (0, 0, p.w, p.h));
            frame.appearance.add (new PaintLayer.line (new Paint.hex ("#4a90d9"), 0.5));
            frame.guide = false;
            frame.name = _("Tile Bounds");
            frame.locked = true;
            g.add (frame, 0);
            var center = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
            g.apply_transform (Transforms.translate (center.x - p.w / 2, center.y - p.h / 2), false);
            c.doc.begin (_("Edit Pattern"));
            (c.doc.active_layer ?? c.doc.layers[0]).add (g);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.isolation = g;
            c.clear_selection ();
            c.queue_draw ();
            return g;
        }

        public static void save_pattern_tile (VectorCanvas c, PatternDef p, GroupNode g) {
            c.doc.begin (_("Update Pattern"));
            var tile = new GroupNode ();
            Rect bounds = Rect (0, 0, p.w, p.h);
            foreach (var ch in g.children) if (ch.name == _("Tile Bounds")) bounds = ch.geometric_bounds ();
            foreach (var ch in g.children) {
                if (ch.name == _("Tile Bounds")) continue;
                var copy = ch.clone ();
                clear_ids (copy);
                copy.apply_transform (Transforms.translate (-bounds.x, -bounds.y), false);
                tile.add (copy);
            }
            p.tile = tile;
            p.w = double.max (bounds.w, 1);
            p.h = double.max (bounds.h, 1);
            if (g.parent != null) g.parent.remove (g);
            c.isolation = null;
            c.doc.ensure_ids ();
            c.doc.commit ();
        }

        public static void apply_paint (VectorCanvas c, Paint paint, bool stroke) {
            if (c.selection.size == 0) {
                if (stroke) c.style.stroke = paint.copy ();
                else c.style.fill = paint.copy ();
                c.selection_changed ();
                return;
            }
            c.doc.begin (stroke ? _("Stroke Color") : _("Fill Color"));
            foreach (var n in c.selection) apply_paint_node (n, paint, stroke);
            c.doc.commit ();
        }

        public static void apply_paint_node (Node n, Paint paint, bool stroke) {
            var g = n as GroupNode;
            if (g != null && !(g is LivePaintNode) && g.generated (null) == null && n.appearance.size == 0) {
                for (int i = (g.clip ? 1 : 0); i < g.children.size; i++) apply_paint_node (g.children[i], paint, stroke);
                return;
            }
            var me = n as MeshNode;
            if (me != null && !stroke) {
                foreach (var v in me.vertices) v.color = paint.representative ().copy ();
                return;
            }
            var layer = stroke ? n.ensure_stroke () : n.ensure_fill ();
            var p = paint.copy ();
            if (p.kind == PaintKind.LINEAR || p.kind == PaintKind.RADIAL) {
                var b = n.geometric_bounds ();
                if (b.w >= 0) Transforms.fit_gradient (p, b);
            } else if (p.kind == PaintKind.FREEFORM) {
                var b = n.geometric_bounds ();
                if (b.w >= 0 && p.freeform.size == 0) init_freeform (p, b);
            }
            layer.paint = p;
        }

        public static void init_freeform (Paint p, Rect b) {
            p.kind = PaintKind.FREEFORM;
            p.freeform.clear ();
            p.freeform.add (new FreeformPoint (b.x + b.w * 0.2, b.y + b.h * 0.25, Ink.hex ("#1d71b8")));
            p.freeform.add (new FreeformPoint (b.x + b.w * 0.8, b.y + b.h * 0.3, Ink.hex ("#ffed00")));
            p.freeform.add (new FreeformPoint (b.x + b.w * 0.5, b.y + b.h * 0.8, Ink.hex ("#e5322d")));
        }

        public static void swap_fill_stroke (VectorCanvas c) {
            if (c.selection.size == 0) {
                var t = c.style.fill;
                c.style.fill = c.style.stroke;
                c.style.stroke = t;
                c.selection_changed ();
                return;
            }
            c.doc.begin (_("Swap Fill and Stroke"));
            foreach (var n in c.selection) {
                var f = n.ensure_fill ();
                var s = n.ensure_stroke ();
                var t = f.paint;
                f.paint = s.paint;
                s.paint = t;
            }
            c.doc.commit ();
        }

        public static void make_3d (VectorCanvas c, string mode) {
            var list = selected_paths (c);
            if (list.size == 0) return;
            c.doc.begin (mode == "revolve" ? _("3D Revolve") : _("3D Extrude"));
            var made = new Gee.ArrayList<Node> ();
            foreach (var pn in list) {
                var s = new Shape3DNode ();
                s.mode = mode;
                s.profile = pn.render_path ().copy ();
                var f = pn.first_fill ();
                var s2 = pn.first_stroke ();
                var color = f != null && f.paint.visible () ? f.paint.copy () : (s2 != null ? s2.paint.copy () : new Paint.hex ("#999999"));
                s.appearance.add (new PaintLayer.fill (color));
                if (mode == "revolve") {
                    s.rx = -20;
                    s.ry = 0;
                    s.rz = 0;
                }
                var parent = pn.parent;
                int index = parent.children.index_of (pn);
                parent.remove (pn);
                parent.add (s, index);
                made.add (s);
            }
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.set_selection (made);
        }

        public static ChartNode make_chart (VectorCanvas c, string kind, Rect r) {
            var ch = new ChartNode ();
            ch.chart = kind;
            ch.x = r.x;
            ch.y = r.y;
            ch.w = double.max (r.w, 120);
            ch.h = double.max (r.h, 90);
            c.doc.begin (_("Graph"));
            (c.isolation ?? c.doc.active_layer).add (ch);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (ch);
            return ch;
        }

        public static void embed_images (VectorCanvas c, bool embed) {
            c.doc.begin (embed ? _("Embed Image") : _("Unembed Image"));
            foreach (var n in c.selection) {
                var im = n as ImageNode;
                if (im == null) continue;
                if (embed && im.link != "") {
                    try {
                        uint8[] data;
                        FileUtils.get_data (im.link, out data);
                        im.asset = c.doc.store_asset (new Bytes (data), im.mime);
                        Renderer.forget_image ("link:" + im.link);
                        im.link = "";
                    } catch (Error e) {
                        warning ("Vector: %s", e.message);
                    }
                }
            }
            c.doc.commit ();
        }

        public static void artboard_fit (VectorCanvas c) {
            var a = c.doc.current_artboard ();
            if (a == null) return;
            var b = c.selection.size > 0 ? c.selection_bounds (true) : c.doc.content_bounds ();
            if (b.w <= 0) return;
            c.doc.begin (_("Fit Artboard"));
            a.x = b.x;
            a.y = b.y;
            a.w = b.w;
            a.h = b.h;
            c.doc.commit ();
            c.doc.structure_changed ();
        }

        public static void recolor (VectorCanvas c, Gee.Map<string, Ink> mapping) {
            c.doc.begin (_("Recolor Artwork"));
            foreach (var n in c.selection) recolor_node (n, mapping);
            c.doc.commit ();
        }

        private static void recolor_ink (Ink ink, Gee.Map<string, Ink> mapping) {
            string key = ink.to_hex ();
            if (!mapping.has_key (key)) return;
            var t = mapping[key];
            ink.r = t.r;
            ink.g = t.g;
            ink.b = t.b;
            ink.has_cmyk = false;
        }

        public static void recolor_node (Node n, Gee.Map<string, Ink> mapping) {
            foreach (var l in n.appearance) {
                recolor_ink (l.paint.color, mapping);
                foreach (var s in l.paint.gradient.stops) recolor_ink (s.color, mapping);
                foreach (var f in l.paint.freeform) recolor_ink (f.color, mapping);
            }
            var me = n as MeshNode;
            if (me != null) foreach (var v in me.vertices) recolor_ink (v.color, mapping);
            var lp = n as LivePaintNode;
            if (lp != null) foreach (var f in lp.fills) recolor_ink (f.paint.color, mapping);
            var t = n as TextNode;
            if (t != null) foreach (var r in t.runs) if (r.style.color != null) recolor_ink (r.style.color, mapping);
            var g = n as GroupNode;
            if (g != null) foreach (var ch in g.children) recolor_node (ch, mapping);
        }

        public static Gee.ArrayList<Ink> artwork_colors (Gee.List<Node> nodes) {
            var seen = new Gee.HashMap<string, Ink> ();
            foreach (var n in nodes) collect_colors (n, seen);
            var list = new Gee.ArrayList<Ink> ();
            list.add_all (seen.values);
            list.sort ((a, b) => {
                double ha, sa, la, hb, sb, lb;
                a.to_hsl (out ha, out sa, out la);
                b.to_hsl (out hb, out sb, out lb);
                return ha < hb ? -1 : ha > hb ? 1 : 0;
            });
            return list;
        }

        private static void collect_colors (Node n, Gee.HashMap<string, Ink> seen) {
            foreach (var l in n.appearance) {
                if (!l.paint.visible ()) continue;
                if (l.paint.kind == PaintKind.SOLID) seen[l.paint.color.to_hex ()] = l.paint.color;
                foreach (var s in l.paint.gradient.stops) if (l.paint.kind == PaintKind.LINEAR || l.paint.kind == PaintKind.RADIAL) seen[s.color.to_hex ()] = s.color;
                foreach (var f in l.paint.freeform) seen[f.color.to_hex ()] = f.color;
            }
            var me = n as MeshNode;
            if (me != null) foreach (var v in me.vertices) seen[v.color.to_hex ()] = v.color;
            var g = n as GroupNode;
            if (g != null) foreach (var ch in g.children) collect_colors (ch, seen);
        }
    }
}
