using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Dialogs {
        public static void shape_size (VectorWindow win, ShapeTool tool, Point at) {
            Box body;
            SpinButton w = null, h = null;
            var dlg = Forms.form (win, tool.label, _("Create"), out body, () => {
                tool.create_exact (at, w.value, h.value);
            });
            var g = new PreferencesGroup (_("Size"));
            bool line = tool.id == "line";
            w = Forms.spin (g, line ? _("Length X") : _("Width"), line ? -100000 : 0.1, 100000, 1, 100, 1);
            h = Forms.spin (g, line ? _("Length Y") : _("Height"), line ? -100000 : 0.1, 100000, 1, line ? 0 : 100, 1);
            if (tool.id == "polygon" || tool.id == "star") {
                var sides = Forms.spin (g, tool.id == "star" ? _("Points") : _("Sides"), 3, 100, 1, tool.id == "star" ? tool.points : tool.sides, 0);
                sides.value_changed.connect (() => {
                    if (tool.id == "star") tool.points = (int) sides.value;
                    else tool.sides = (int) sides.value;
                });
            }
            if (tool.id == "star") {
                var inner = Forms.spin (g, _("Inner Radius"), 1, 99, 1, tool.inner * 100, 0, _("percent"));
                inner.value_changed.connect (() => tool.inner = inner.value / 100);
            }
            if (tool.id == "rounded") {
                var r = Forms.spin (g, _("Corner Radius"), 0, 10000, 1, tool.radius, 1);
                r.value_changed.connect (() => tool.radius = r.value);
            }
            body.append (g);
            dlg.present ();
        }

        public static void transform (VectorWindow win, string kind) {
            var c = win.canvas;
            if (c.selection.size == 0) return;
            Box body;
            var g = new PreferencesGroup (_("Options"));
            SpinButton a = null, b = null;
            Switch copy = null;
            Switch strokes = null;
            DropDown reference = null;
            string title = kind == "move" ? _("Move") : (kind == "rotate" ? _("Rotate") : (kind == "scale" ? _("Scale") : (kind == "reflect" ? _("Reflect") : _("Shear"))));
            var dlg = Forms.form (win, title, copy == null ? _("OK") : _("OK"), out body, () => {
                var box = c.selection_bounds ();
                var o = Point (box.cx (), box.cy ());
                int[] map = { -1, 0, 1, 2, 3, 4, 5, 6, 7 };
                int ref_index = map[reference.selected];
                if (ref_index >= 0) o = SelectTool.handle_points (box)[ref_index];
                Cairo.Matrix m;
                switch (kind) {
                    case "move": m = Transforms.translate (a.value, b.value); break;
                    case "rotate": m = Transforms.rotate (a.value * Math.PI / 180, o); break;
                    case "scale": m = Transforms.scale (a.value / 100, b.value / 100, o); break;
                    case "reflect": m = Transforms.reflect (a.value, o); break;
                    default: m = Transforms.shear (a.value, b.value < 0.5, o); break;
                }
                bool old = c.scale_strokes;
                c.scale_strokes = strokes.active;
                if (copy.active) {
                    c.doc.begin (title);
                    var made = new Gee.ArrayList<Node> ();
                    foreach (var n in Commands.ordered (c)) {
                        var cp = n.clone ();
                        Commands.clear_ids (cp);
                        cp.apply_transform (m, c.scale_strokes);
                        n.parent.add (cp, n.parent.children.index_of (n) + 1);
                        made.add (cp);
                    }
                    c.doc.ensure_ids ();
                    c.doc.commit ();
                    c.set_selection (made);
                } else {
                    Commands.transform (c, m, title);
                }
                c.scale_strokes = old;
            });
            switch (kind) {
                case "move":
                    a = Forms.spin (g, _("Horizontal"), -100000, 100000, 1, 10, 2);
                    b = Forms.spin (g, _("Vertical"), -100000, 100000, 1, 10, 2);
                    break;
                case "rotate":
                    a = Forms.spin (g, _("Angle"), -360, 360, 1, 45, 2);
                    break;
                case "scale":
                    a = Forms.spin (g, _("Horizontal"), 0.1, 10000, 1, 100, 1, _("percent"));
                    b = Forms.spin (g, _("Vertical"), 0.1, 10000, 1, 100, 1, _("percent"));
                    break;
                case "reflect":
                    a = Forms.spin (g, _("Axis Angle"), -360, 360, 1, 90, 1);
                    break;
                default:
                    a = Forms.spin (g, _("Shear Angle"), -89, 89, 1, 15, 1);
                    b = Forms.spin (g, _("Vertical Axis"), 0, 1, 1, 0, 0, _("0 horizontal, 1 vertical"));
                    break;
            }
            reference = Forms.choice (g, _("Reference Point"), { _("Center"), _("Top Left"), _("Top Center"), _("Top Right"), _("Right Center"), _("Bottom Right"), _("Bottom Center"), _("Bottom Left"), _("Left Center") }, 0);
            copy = Forms.toggle (g, _("Copy"), false);
            strokes = Forms.toggle (g, _("Scale Strokes and Effects"), c.scale_strokes);
            body.append (g);
            dlg.present ();
        }

        public static void transform_each (VectorWindow win) {
            var c = win.canvas;
            Box body;
            var g = new PreferencesGroup (_("Options"));
            SpinButton sx = null, sy = null, dx = null, dy = null, an = null, copies = null;
            Switch fh = null, fv = null, rnd = null;
            DropDown origin = null;
            var dlg = Forms.form (win, _("Transform Each"), _("OK"), out body, () => {
                int o = (int) origin.selected;
                int[] map = { 8, 0, 2, 4, 6 };
                Commands.transform_each (c, sx.value / 100, sy.value / 100, dx.value, dy.value, an.value, fh.active, fv.active, map[o], rnd.active, (int) copies.value);
            });
            sx = Forms.spin (g, _("Scale Horizontal"), 1, 10000, 1, 100, 0, _("percent"));
            sy = Forms.spin (g, _("Scale Vertical"), 1, 10000, 1, 100, 0, _("percent"));
            dx = Forms.spin (g, _("Move Horizontal"), -10000, 10000, 1, 0, 1);
            dy = Forms.spin (g, _("Move Vertical"), -10000, 10000, 1, 0, 1);
            an = Forms.spin (g, _("Rotate"), -360, 360, 1, 0, 1);
            fh = Forms.toggle (g, _("Reflect X"), false);
            fv = Forms.toggle (g, _("Reflect Y"), false);
            origin = Forms.choice (g, _("Reference Point"), { _("Center"), _("Top Left"), _("Top Right"), _("Bottom Right"), _("Bottom Left") }, 0);
            rnd = Forms.toggle (g, _("Random"), false);
            copies = Forms.spin (g, _("Copies"), 0, 500, 1, 0, 0);
            body.append (g);
            dlg.present ();
        }

        public static void offset (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Options"));
            SpinButton d = null, miter = null;
            DropDown join = null;
            var dlg = Forms.form (win, _("Offset Path"), _("OK"), out body, () => {
                Commands.offset_path (win.canvas, d.value, (JoinKind) join.selected, miter.value);
            });
            d = Forms.spin (g, _("Offset"), -10000, 10000, 1, 10, 2);
            join = Forms.choice (g, _("Joins"), { _("Miter"), _("Round"), _("Bevel") }, 0);
            miter = Forms.spin (g, _("Miter Limit"), 1, 100, 1, 4, 0);
            body.append (g);
            dlg.present ();
        }

        public static void simplify (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Options"));
            SpinButton tol = null, angle = null;
            Switch straight = null;
            var preview_paths = new Gee.ArrayList<PathNode> ();
            preview_paths.add_all (Commands.selected_paths (win.canvas));
            var originals = new Gee.ArrayList<PathData> ();
            var live = new Gee.ArrayList<LiveShape?> ();
            foreach (var pn in preview_paths) {
                originals.add (pn.path.copy ());
                live.add (pn.live);
            }
            int before = 0;
            foreach (var pn in preview_paths) before += PathSimplify.anchor_count (pn.render_path ());
            bool applied = false;
            Forms.Done restore = () => {
                for (int i = 0; i < preview_paths.size; i++) {
                    preview_paths[i].path = originals[i].copy ();
                    preview_paths[i].live = live[i];
                }
            };
            var dlg = Forms.form (win, _("Simplify"), _("OK"), out body, () => {
                restore ();
                applied = true;
                int removed = Commands.simplify (win.canvas, tol.value, angle.value, straight.active);
                win.toast (ngettext ("%d point removed", "%d points removed", removed).printf (removed));
            });
            g.add_row (new ActionRow (_("Current Points"), before.to_string ()));
            var result_row = new ActionRow (_("Points After"), "");
            g.add_row (result_row);
            tol = Forms.spin (g, _("Tolerance"), 0.05, 200, 0.25, 1.5, 2, _("pixels"));
            angle = Forms.spin (g, _("Corner Angle Threshold"), 0, 180, 1, 40, 0, _("degrees"));
            straight = Forms.toggle (g, _("Straight Lines"), false);
            Forms.Done update = () => {
                int after = 0;
                for (int i = 0; i < preview_paths.size; i++) {
                    var source = preview_paths[i];
                    source.path = originals[i].copy ();
                    source.live = live[i];
                    var simplified = PathSimplify.simplify (source.render_path (), tol.value, angle.value, straight.active);
                    after += PathSimplify.anchor_count (simplified);
                    source.live = null;
                    source.path = simplified;
                }
                result_row.subtitle = after.to_string ();
                win.doc.changed ();
            };
            tol.value_changed.connect (() => update ());
            angle.value_changed.connect (() => update ());
            straight.notify["active"].connect (() => update ());
            update ();
            dlg.close_request.connect (() => {
                if (!applied) {
                    restore ();
                    win.doc.changed ();
                }
                return false;
            });
            body.append (g);
            dlg.present ();
        }

        public static void envelope_warp (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Warp"));
            DropDown style = null;
            SpinButton bend = null;
            string[] labels = { _("Arc"), _("Arc Lower"), _("Arc Upper"), _("Arch"), _("Bulge"), _("Shell Lower"), _("Shell Upper"), _("Flag"), _("Wave"), _("Fish"), _("Rise"), _("Fisheye"), _("Inflate"), _("Squeeze"), _("Twist") };
            var dlg = Forms.form (win, _("Make with Warp"), _("OK"), out body, () => {
                Commands.make_envelope (win.canvas, "warp", WarpStyle.ids ()[style.selected], bend.value / 100);
            });
            style = Forms.choice (g, _("Style"), labels, 0);
            bend = Forms.spin (g, _("Bend"), -100, 100, 1, 50, 0, _("percent"));
            body.append (g);
            dlg.present ();
        }

        public static void envelope_mesh (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Mesh"));
            SpinButton rows = null, cols = null;
            var dlg = Forms.form (win, _("Make with Mesh"), _("OK"), out body, () => {
                Commands.make_envelope (win.canvas, "mesh", "arc", 0, (int) rows.value, (int) cols.value);
                win.canvas.set_tool ("direct");
            });
            rows = Forms.spin (g, _("Rows"), 1, 50, 1, 2, 0);
            cols = Forms.spin (g, _("Columns"), 1, 50, 1, 2, 0);
            body.append (g);
            dlg.present ();
        }

        public static void mesh_create (VectorWindow win) {
            var pn = win.canvas.selection.size > 0 ? win.canvas.selection[0] as PathNode : null;
            if (pn == null) return;
            Box body;
            var g = new PreferencesGroup (_("Mesh"));
            SpinButton rows = null, cols = null;
            var dlg = Forms.form (win, _("Create Gradient Mesh"), _("OK"), out body, () => {
                Commands.make_mesh (win.canvas, pn, (int) rows.value, (int) cols.value);
            });
            rows = Forms.spin (g, _("Rows"), 1, 50, 1, 2, 0);
            cols = Forms.spin (g, _("Columns"), 1, 50, 1, 2, 0);
            body.append (g);
            dlg.present ();
        }

        public static void effect (VectorWindow win, Node node, Effect e) {
            Box body;
            var g = new PreferencesGroup (_("Options"));
            var edits = new Gee.HashMap<string, SpinButton> ();
            ColorPickerButton? color = null;
            DropDown? warp_style = null;
            var backup = e.copy ();
            bool applied = false;
            var dlg = Forms.form (win, e.label (), _("OK"), out body, () => {
                applied = true;
                foreach (var kv in backup.num.entries) e.num[kv.key] = kv.value;
                win.doc.begin (e.label ());
                foreach (var kv in edits.entries) e.num[kv.key] = kv.value.value / (scaled (kv.key) ? 100.0 : 1.0);
                if (color != null) e.str["color"] = Forms.ink_of (color.color).to_hex ();
                if (warp_style != null) e.str["style"] = WarpStyle.ids ()[warp_style.selected];
                win.doc.commit ();
            });
            string[,] fields = fields_for (e.kind);
            for (int i = 0; i < fields.length[0]; i++) {
                string key = fields[i, 0];
                double v = e.get_num (key, 0) * (scaled (key) ? 100 : 1);
                double min = double.parse (fields[i, 2]), max = double.parse (fields[i, 3]);
                edits[key] = Forms.spin (g, fields[i, 1], min, max, 1, v, scaled (key) ? 0 : 1);
            }
            if (e.str.has_key ("color")) color = Forms.color (g, _("Color"), Ink.hex (e.get_str ("color", "#000000")));
            if (e.kind == "warp") {
                string[] labels = { _("Arc"), _("Arc Lower"), _("Arc Upper"), _("Arch"), _("Bulge"), _("Shell Lower"), _("Shell Upper"), _("Flag"), _("Wave"), _("Fish"), _("Rise"), _("Fisheye"), _("Inflate"), _("Squeeze"), _("Twist") };
                warp_style = Forms.choice (g, _("Style"), labels, (int) WarpStyle.from_id (e.get_str ("style", "arc")));
            }
            var preview = Forms.toggle (g, _("Preview"), true);
            foreach (var s in edits.values) {
                s.value_changed.connect (() => {
                    if (!preview.active) return;
                    foreach (var kv in edits.entries) e.num[kv.key] = kv.value.value / (scaled (kv.key) ? 100.0 : 1.0);
                    win.doc.changed ();
                });
            }
            dlg.close_request.connect (() => {
                if (!applied) {
                    foreach (var kv in backup.num.entries) e.num[kv.key] = kv.value;
                    win.doc.changed ();
                }
                return false;
            });
            body.append (g);
            dlg.present ();
        }

        private static bool scaled (string key) {
            return key == "opacity" || key == "bend" || key == "h" || key == "v" || key == "amount" || key == "sx" || key == "sy" || key.has_prefix ("u") || (key.length == 2 && key[0] == 'v' && key[1].isdigit ());
        }

        private static string[,] fields_for (string kind) {
            switch (kind) {
                case "drop-shadow": return { { "dx", _("X Offset"), "-1000", "1000" }, { "dy", _("Y Offset"), "-1000", "1000" }, { "blur", _("Blur"), "0", "500" }, { "opacity", _("Opacity"), "0", "100" } };
                case "outer-glow":
                case "inner-glow": return { { "blur", _("Blur"), "0", "500" }, { "opacity", _("Opacity"), "0", "100" } };
                case "blur":
                case "feather": return { { "blur", _("Radius"), "0", "500" } };
                case "round-corners": return { { "radius", _("Radius"), "0", "10000" } };
                case "offset": return { { "distance", _("Offset"), "-10000", "10000" }, { "join", _("Joins 0 Miter, 1 Round, 2 Bevel"), "0", "2" }, { "miter", _("Miter Limit"), "1", "100" } };
                case "roughen": return { { "size", _("Size"), "0", "1000" }, { "detail", _("Detail per 100 px"), "1", "200" }, { "smooth", _("Smooth 1 or Corner 0"), "0", "1" }, { "seed", _("Variation"), "1", "1000" } };
                case "zigzag": return { { "size", _("Size"), "0", "1000" }, { "ridges", _("Ridges per Segment"), "1", "100" }, { "smooth", _("Smooth 1 or Corner 0"), "0", "1" } };
                case "pucker": return { { "amount", _("Pucker or Bloat"), "-200", "200" } };
                case "twist": return { { "angle", _("Angle"), "-3600", "3600" } };
                case "transform": return { { "sx", _("Scale Horizontal"), "1", "1000" }, { "sy", _("Scale Vertical"), "1", "1000" }, { "dx", _("Move Horizontal"), "-10000", "10000" }, { "dy", _("Move Vertical"), "-10000", "10000" }, { "angle", _("Rotate"), "-360", "360" }, { "copies", _("Copies"), "0", "500" } };
                case "warp": return { { "bend", _("Bend"), "-100", "100" }, { "h", _("Horizontal Distortion"), "-100", "100" }, { "v", _("Vertical Distortion"), "-100", "100" } };
                case "free-distort": return { { "u0", _("Top Left X"), "-100", "200" }, { "v0", _("Top Left Y"), "-100", "200" }, { "u1", _("Top Right X"), "-100", "200" }, { "v1", _("Top Right Y"), "-100", "200" }, { "u2", _("Bottom Right X"), "-100", "200" }, { "v2", _("Bottom Right Y"), "-100", "200" }, { "u3", _("Bottom Left X"), "-100", "200" }, { "v3", _("Bottom Left Y"), "-100", "200" } };
                default: return new string[0, 4];
            }
        }

        public static void paint_layer (VectorWindow win, Node n, PaintLayer l) {
            Box body;
            var editor = new PaintEditor (win, l.paint, l.stroke);
            Paint result = l.paint.copy ();
            editor.changed.connect ((p) => result = p);
            var g = new PreferencesGroup (_("Blending"));
            var opacity = Forms.spin (g, _("Opacity"), 0, 100, 1, Math.round (l.opacity * 100), 0, _("percent"));
            var blend = Forms.choice (g, _("Blending Mode"), BlendMode.labels (), (int) l.blend);
            var dlg = Forms.form (win, l.stroke ? _("Stroke") : _("Fill"), _("OK"), out body, () => {
                win.doc.begin (_("Appearance"));
                l.paint = result;
                l.opacity = opacity.value / 100;
                l.blend = (BlendMode) blend.selected;
                if (l.paint.kind == PaintKind.LINEAR || l.paint.kind == PaintKind.RADIAL) {
                    var b = n.geometric_bounds ();
                    var gr = l.paint.gradient;
                    if (gr.x1 == gr.x2 && gr.y1 == gr.y2) Transforms.fit_gradient (l.paint, b);
                }
                win.doc.commit ();
            });
            body.append (editor);
            body.append (g);
            var fx = new PreferencesGroup (l.stroke ? _("Effects on This Stroke") : _("Effects on This Fill"));
            foreach (var e in l.effects) {
                var eff = e;
                var row = new ActionRow (eff.label ());
                row.activated.connect (() => effect (win, n, eff));
                row.add_suffix (Forms.flat_icon ("document-edit-symbolic", _("Options"), () => effect (win, n, eff)));
                row.add_suffix (Forms.flat_icon ("list-remove-symbolic", _("Remove"), () => {
                    win.doc.begin (_("Remove Effect"));
                    l.effects.remove (eff);
                    win.doc.commit ();
                    dlg.close_dialog ();
                }));
                fx.add_row (row);
            }
            if (l.effects.size == 0) fx.description = _("No effects yet.");
            Forms.header_menu (fx, _("Add"), (m) => {
                foreach (var k in AppearancePanel.effect_kinds ()) {
                    string kind = k;
                    m.add_item (new Effect (kind).label (), null, () => {
                        var e = AppearancePanel.default_effect (kind);
                        win.doc.begin (_("Add Effect"));
                        l.effects.add (e);
                        win.doc.commit ();
                        effect (win, n, e);
                        dlg.close_dialog ();
                    });
                }
            });
            body.append (fx);
            dlg.present ();
        }

        public static void new_style (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Graphic Style"));
            Entry name = null;
            var dlg = Forms.form (win, _("New Graphic Style"), _("Create"), out body, () => {
                string text = name.text.strip ();
                Commands.new_style (win.canvas, text != "" ? text : _("Style %d").printf (win.doc.styles.size + 1));
                win.appearance.refresh ();
            });
            name = Forms.entry (g, _("Name"), _("Style %d").printf (win.doc.styles.size + 1));
            body.append (g);
            dlg.present ();
        }

        public static void new_swatch (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Swatch"));
            Entry name = null, group = null, spot = null;
            ColorPickerButton color = null;
            Switch global = null;
            var current = win.canvas.selection.size > 0 && win.canvas.selection[0].first_fill () != null ? win.canvas.selection[0].first_fill ().paint.representative () : win.canvas.style.fill.representative ();
            var dlg = Forms.form (win, _("New Swatch"), _("Add"), out body, () => {
                var doc = win.doc;
                doc.begin (_("New Swatch"));
                var ink = Forms.ink_of (color.color);
                if (doc.color_mode == "cmyk") ink.ensure_cmyk ();
                ink.spot = spot.text.strip ();
                var s = new Swatch (name.text.strip () != "" ? name.text.strip () : ink.to_hex (), new Paint.solid (ink));
                s.id = doc.new_id ("sw");
                s.is_global = global.active || ink.spot != "";
                s.group = group.text.strip ();
                doc.swatches.add (s);
                doc.commit ();
                win.libraries.refresh ();
            });
            name = Forms.entry (g, _("Name"), "");
            color = Forms.color (g, _("Color"), current);
            group = Forms.entry (g, _("Group"), _("Custom"));
            global = Forms.toggle (g, _("Global"), false, _("Editing a global swatch updates every object that uses it"));
            spot = Forms.entry (g, _("Spot Color Name"), "");
            spot.placeholder_text = _("Leave empty for a process color");
            body.append (g);
            dlg.present ();
        }

        public static void swatch_options (VectorWindow win, Swatch sw) {
            Box body;
            var g = new PreferencesGroup (_("Swatch"));
            Entry name = null, group = null, spot = null;
            Switch global = null;
            Paint result = sw.paint.copy ();
            var editor = new PaintEditor (win, sw.paint, false, _("Swatch Color"));
            editor.changed.connect ((p) => result = p);
            var dlg = Forms.form (win, _("Swatch Options"), _("OK"), out body, () => {
                var doc = win.doc;
                doc.begin (_("Swatch Options"));
                sw.name = name.text;
                sw.group = group.text;
                sw.is_global = global.active;
                sw.paint = result;
                sw.paint.color.spot = spot.text.strip ();
                if (!sw.is_global) {
                    foreach (var n in doc.all_nodes ()) foreach (var l in n.appearance) if (l.paint.color.swatch == sw.id) l.paint.color = sw.paint.color.copy ();
                }
                doc.commit ();
                win.libraries.refresh ();
                win.canvas.queue_draw ();
            });
            name = Forms.entry (g, _("Name"), sw.name);
            group = Forms.entry (g, _("Group"), sw.group);
            global = Forms.toggle (g, _("Global"), sw.is_global);
            spot = Forms.entry (g, _("Spot Color Name"), sw.paint.color.spot);
            body.append (g);
            body.append (editor);
            var del = Forms.header_button (g, _("Delete"), () => {
                win.doc.begin (_("Delete Swatch"));
                win.doc.swatches.remove (sw);
                win.doc.commit ();
                win.libraries.refresh ();
                dlg.close_dialog ();
            });
            del.add_css_class ("destructive-action");
            dlg.present ();
        }

        public static void recolor (VectorWindow win) {
            var c = win.canvas;
            var nodes = c.selection.size > 0 ? c.selection : new Gee.ArrayList<Node> ();
            if (nodes.size == 0) foreach (var l in win.doc.layers) nodes.add (l);
            var colors = Commands.artwork_colors (nodes);
            if (colors.size == 0) return;
            Box body;
            var g = new PreferencesGroup (_("Colors"));
            var pickers = new Gee.ArrayList<ColorPickerButton> ();
            SpinButton hue = null, sat = null, light = null;
            DropDown harmony = null;
            var dlg = Forms.form (win, _("Recolor Artwork"), _("Apply"), out body, () => {
                var map = new Gee.HashMap<string, Ink> ();
                for (int i = 0; i < colors.size; i++) {
                    var target = Forms.ink_of (pickers[i].color);
                    double h, s, l;
                    target.to_hsl (out h, out s, out l);
                    var adjusted = Ink.from_hsl (h + hue.value / 360, (s + sat.value / 100).clamp (0, 1), (l + light.value / 100).clamp (0, 1));
                    map[colors[i].to_hex ()] = adjusted;
                }
                if (c.selection.size == 0) Commands.select_all (c);
                Commands.recolor (c, map);
            });
            harmony = Forms.choice (g, _("Harmony"), { _("Keep Current"), _("Complementary"), _("Analogous"), _("Triad"), _("Monochrome"), _("Grayscale") }, 0);
            hue = Forms.spin (g, _("Hue Shift"), -180, 180, 1, 0, 0, _("degrees"));
            sat = Forms.spin (g, _("Saturation"), -100, 100, 1, 0, 0);
            light = Forms.spin (g, _("Brightness"), -100, 100, 1, 0, 0);
            var map_group = new PreferencesGroup (_("Current to New"));
            foreach (var ink in colors) {
                var row = new ActionRow (ink.to_hex ());
                var from = new DrawingArea ();
                from.set_size_request (22, 22);
                var src = ink;
                from.set_draw_func ((a, cr, w, h) => {
                    cr.set_source_rgb (src.r, src.g, src.b);
                    cr.rectangle (0, 0, w, h);
                    cr.fill ();
                });
                row.add_prefix (from);
                var to = new ColorPickerButton (Forms.rgba (ink));
                to.valign = Align.CENTER;
                row.add_suffix (to);
                pickers.add (to);
                map_group.add_row (row);
            }
            harmony.notify["selected"].connect (() => {
                if (colors.size == 0) return;
                double bh, bs, bl;
                colors[0].to_hsl (out bh, out bs, out bl);
                for (int i = 0; i < colors.size; i++) {
                    double h, s, l;
                    colors[i].to_hsl (out h, out s, out l);
                    Ink result;
                    switch (harmony.selected) {
                        case 1: result = Ink.from_hsl (i % 2 == 0 ? bh : bh + 0.5, s, l); break;
                        case 2: result = Ink.from_hsl (bh + (i - colors.size / 2.0) * 0.06, s, l); break;
                        case 3: result = Ink.from_hsl (bh + (i % 3) / 3.0, s, l); break;
                        case 4: result = Ink.from_hsl (bh, bs, l); break;
                        case 5: result = Ink.from_hsl (0, 0, colors[i].luminance ()); break;
                        default: result = colors[i]; break;
                    }
                    pickers[i].color = Forms.rgba (result);
                }
            });
            body.append (g);
            body.append (map_group);
            dlg.present ();
        }

        public static void symbol_options (VectorWindow win, SymbolDef def) {
            Box body;
            var g = new PreferencesGroup (_("Symbol"));
            Entry name = null;
            Switch dyn = null;
            var dlg = Forms.form (win, _("Symbol Options"), _("OK"), out body, () => {
                win.doc.begin (_("Symbol Options"));
                def.name = name.text;
                def.is_dynamic = dyn.active;
                win.doc.commit ();
                win.libraries.refresh ();
            });
            name = Forms.entry (g, _("Name"), def.name);
            dyn = Forms.toggle (g, _("Dynamic Symbol"), def.is_dynamic, _("Instances can override colors"));
            body.append (g);
            var ig = new PreferencesGroup (_("Instances"));
            Forms.action (ig, _("Replace Selected Instances"), null, _("Replace"), () => {
                Commands.replace_symbol (win.canvas, def);
                dlg.close_dialog ();
            });
            Forms.action (ig, _("Redefine from Selection"), null, _("Redefine"), () => {
                Commands.redefine_symbol (win.canvas, def);
                dlg.close_dialog ();
            });
            var del_row = new ActionRow (_("Delete Symbol"), _("Instances become ordinary artwork."));
            var del = Forms.pill (_("Delete"), () => {
                var doc = win.doc;
                doc.begin (_("Delete Symbol"));
                foreach (var n in doc.all_nodes ()) {
                    var sy = n as SymbolNode;
                    if (sy == null || sy.symbol != def.id || sy.parent == null) continue;
                    var art = sy.resolve (doc);
                    var parent = sy.parent;
                    int idx = parent.children.index_of (sy);
                    parent.remove (sy);
                    if (art != null) {
                        Commands.clear_ids (art);
                        parent.add (art, idx);
                    }
                }
                doc.symbols.remove (def);
                doc.ensure_ids ();
                doc.commit ();
                win.libraries.refresh ();
                dlg.close_dialog ();
            });
            del.add_css_class ("destructive-action");
            del_row.add_suffix (del);
            ig.add_row (del_row);
            body.append (ig);
            dlg.present ();
        }

        public static void brush_options (VectorWindow win, BrushDef b) {
            Box body;
            var g = new PreferencesGroup (_("Brush"));
            Entry name = null;
            SpinButton angle = null, round = null, size = null, spacing = null, scatter = null, jitter = null, rot = null;
            DropDown colorize = null;
            Switch rotate = null;
            var dlg = Forms.form (win, _("Brush Options"), _("OK"), out body, () => {
                win.doc.begin (_("Brush Options"));
                b.name = name.text;
                if (angle != null) b.angle = angle.value;
                if (round != null) b.roundness = round.value / 100;
                if (size != null) b.size = size.value;
                if (spacing != null) b.spacing = spacing.value / 100;
                if (scatter != null) b.scatter = scatter.value / 100;
                if (jitter != null) b.size_jitter = jitter.value / 100;
                if (rot != null) b.rotation_jitter = rot.value / 100;
                if (rotate != null) b.rotate_with_path = rotate.active;
                if (colorize != null) b.colorize = colorize.selected == 0 ? "none" : (colorize.selected == 1 ? "tints" : "solid");
                win.doc.commit ();
                win.libraries.refresh ();
            });
            name = Forms.entry (g, _("Name"), b.name);
            if (b.kind == "calligraphic") {
                angle = Forms.spin (g, _("Angle"), -180, 180, 1, b.angle, 0);
                round = Forms.spin (g, _("Roundness"), 1, 100, 1, b.roundness * 100, 0, _("percent"));
                size = Forms.spin (g, _("Size"), 0.1, 500, 0.5, b.size, 1);
            } else {
                spacing = Forms.spin (g, _("Spacing"), 0, 1000, 5, b.spacing * 100, 0, _("percent"));
                if (b.kind == "scatter") {
                    scatter = Forms.spin (g, _("Scatter"), 0, 1000, 5, b.scatter * 100, 0, _("percent"));
                    jitter = Forms.spin (g, _("Size Variation"), 0, 100, 5, b.size_jitter * 100, 0, _("percent"));
                    rot = Forms.spin (g, _("Rotation Variation"), 0, 100, 5, b.rotation_jitter * 100, 0, _("percent"));
                    rotate = Forms.toggle (g, _("Rotate with Path"), b.rotate_with_path);
                }
                colorize = Forms.choice (g, _("Colorization"), { _("None"), _("Tints"), _("Stroke Color") }, b.colorize == "tints" ? 1 : (b.colorize == "solid" ? 2 : 0));
            }
            body.append (g);
            dlg.present ();
        }

        public static void pattern_options (VectorWindow win, PatternDef p) {
            Box body;
            var g = new PreferencesGroup (_("Pattern"));
            Entry name = null;
            DropDown tiling = null;
            SpinButton w = null, h = null, hs = null, vs = null, off = null;
            string[] tilings = { "grid", "brick-row", "brick-col", "hex-col", "hex-row" };
            int ti = 0;
            for (int i = 0; i < tilings.length; i++) if (tilings[i] == p.tiling) ti = i;
            var dlg = Forms.form (win, _("Pattern Options"), _("OK"), out body, () => {
                win.doc.begin (_("Pattern Options"));
                p.name = name.text;
                p.tiling = tilings[tiling.selected];
                p.w = w.value;
                p.h = h.value;
                p.hspace = hs.value;
                p.vspace = vs.value;
                p.offset = off.value / 100;
                win.doc.commit ();
                win.libraries.refresh ();
                win.canvas.queue_draw ();
            });
            name = Forms.entry (g, _("Name"), p.name);
            tiling = Forms.choice (g, _("Tile Type"), { _("Grid"), _("Brick by Row"), _("Brick by Column"), _("Hex by Column"), _("Hex by Row") }, ti);
            w = Forms.spin (g, _("Tile Width"), 0.1, 10000, 1, p.w, 1);
            h = Forms.spin (g, _("Tile Height"), 0.1, 10000, 1, p.h, 1);
            hs = Forms.spin (g, _("Horizontal Spacing"), -10000, 10000, 1, p.hspace, 1);
            vs = Forms.spin (g, _("Vertical Spacing"), -10000, 10000, 1, p.vspace, 1);
            off = Forms.spin (g, _("Brick Offset"), 0, 100, 5, p.offset * 100, 0, _("percent"));
            body.append (g);
            var tg = new PreferencesGroup (_("Tile Artwork"));
            GroupNode? editing = null;
            foreach (var n in win.doc.all_nodes ()) if (n is GroupNode && n.name == _("Pattern Tile %s").printf (p.name)) editing = (GroupNode) n;
            if (editing == null) {
                Forms.action (tg, _("Edit Tile on Canvas"), null, _("Edit"), () => {
                    Commands.edit_pattern_tile (win.canvas, p);
                    win.toast (_("Edit the tile, then open Pattern Options again and choose Save Tile."));
                    dlg.close_dialog ();
                });
            } else {
                var g2 = editing;
                Forms.action (tg, _("Save Edited Tile"), null, _("Save Tile"), () => {
                    Commands.save_pattern_tile (win.canvas, p, g2);
                    win.libraries.refresh ();
                    dlg.close_dialog ();
                });
            }
            body.append (tg);
            dlg.present ();
        }

        public static void rename_node (VectorWindow win, Node n, bool layer) {
            Box body;
            var g = new PreferencesGroup (_("Name"));
            Entry name = null;
            var dlg = Forms.form (win, layer ? _("Rename Layer") : _("Rename Object"), _("Rename"), out body, () => {
                win.doc.begin (_("Rename"));
                n.name = name.text;
                win.doc.commit ();
                win.layers.rebuild ();
            });
            name = Forms.entry (g, _("Name"), n.name);
            body.append (g);
            dlg.present ();
        }

        public static void layer_options (VectorWindow win, GroupNode layer) {
            Box body;
            var g = new PreferencesGroup (_("Layer"));
            Entry name = null;
            Switch template = null, printable = null;
            ColorPickerButton color = null;
            SpinButton opacity = null;
            var dlg = Forms.form (win, _("Layer Options"), _("OK"), out body, () => {
                win.doc.begin (_("Layer Options"));
                layer.name = name.text;
                layer.template = template.active;
                layer.printable = printable.active && !template.active;
                layer.color = Forms.ink_of (color.color).to_hex ();
                layer.opacity = opacity.value / 100;
                if (template.active) layer.locked = true;
                win.doc.commit ();
                win.layers.rebuild ();
            });
            name = Forms.entry (g, _("Name"), layer.name);
            color = Forms.color (g, _("Selection Color"), Ink.hex (layer.color));
            template = Forms.toggle (g, _("Template"), layer.template, _("Locked, dimmed and not printed"));
            printable = Forms.toggle (g, _("Print and Export"), layer.printable);
            opacity = Forms.spin (g, _("Opacity"), 0, 100, 1, layer.opacity * 100, 0);
            body.append (g);
            dlg.present ();
        }

        public static void chart_data (VectorWindow win, ChartNode ch) {
            Box body;
            var view = new TextView ();
            view.monospace = true;
            view.buffer.text = string.joinv ("\n", ch.rows.to_array ());
            view.set_size_request (420, 220);
            var dlg = Forms.form (win, _("Graph Data"), _("Apply"), out body, () => {
                win.doc.begin (_("Graph Data"));
                ch.rows.clear ();
                foreach (var line in view.buffer.text.split ("\n")) if (line.strip () != "") ch.rows.add (line.replace (";", "\t").replace (",", "\t"));
                win.doc.commit ();
            }, 520);
            var dg = new PreferencesGroup (_("Data"), _("First row: series names after a tab. Next rows: a label, then one value per series. Tabs, commas or semicolons separate cells."));
            var scroll = new ScrolledWindow ();
            scroll.child = view;
            scroll.min_content_height = 220;
            var drow = new ListBoxRow ();
            drow.activatable = false;
            drow.child = scroll;
            dg.add_row (drow);
            body.append (dg);
            dlg.present ();
        }

        public static void graph_create (VectorWindow win) {
            Box body;
            var g = new PreferencesGroup (_("Graph"));
            DropDown kind = null;
            SpinButton w = null, h = null;
            string[] kinds = { "bar", "stacked", "line", "area", "pie", "scatter" };
            var dlg = Forms.form (win, _("New Graph"), _("Create"), out body, () => {
                var c = win.canvas;
                var center = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
                var ch = Commands.make_chart (c, kinds[kind.selected], Rect (center.x - w.value / 2, center.y - h.value / 2, w.value, h.value));
                chart_data (win, ch);
            });
            kind = Forms.choice (g, _("Type"), { _("Column"), _("Stacked Column"), _("Line"), _("Area"), _("Pie"), _("Scatter") }, 0);
            w = Forms.spin (g, _("Width"), 50, 10000, 10, 400, 0);
            h = Forms.spin (g, _("Height"), 50, 10000, 10, 260, 0);
            body.append (g);
            dlg.present ();
        }

        public static void relink (VectorWindow win, ImageNode im) {
            var dialog = new FileDialog ();
            dialog.title = _("Relink Image");
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null || file.get_path () == null) return;
                    win.doc.begin (_("Relink"));
                    Renderer.forget_image ("link:" + im.link);
                    im.link = file.get_path ();
                    uint8[] data;
                    FileUtils.get_data (im.link, out data);
                    im.asset = win.doc.store_asset (new Bytes (data), Formats.mime_for (im.link));
                    var pix = new Gdk.Pixbuf.from_file (im.link);
                    double w = im.pixel_width * Math.hypot (im.matrix.xx, im.matrix.yx), h = im.pixel_height * Math.hypot (im.matrix.xy, im.matrix.yy);
                    im.matrix = Transforms.multiply (Cairo.Matrix (w / pix.width, 0, 0, h / pix.height, 0, 0), Cairo.Matrix (im.matrix.xx / Math.hypot (im.matrix.xx, im.matrix.yx), im.matrix.yx / Math.hypot (im.matrix.xx, im.matrix.yx), im.matrix.xy / Math.hypot (im.matrix.xy, im.matrix.yy), im.matrix.yy / Math.hypot (im.matrix.xy, im.matrix.yy), im.matrix.x0, im.matrix.y0));
                    im.pixel_width = pix.width;
                    im.pixel_height = pix.height;
                    win.doc.commit ();
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) Forms.message (win, _("Could Not Relink"), e.message);
                }
            });
        }

        public static void image_trace (VectorWindow win, ImageNode im) {
            Box body;
            var g = new PreferencesGroup (_("Trace"));
            DropDown mode = null;
            SpinButton colors = null, threshold = null, noise = null, accuracy = null, corner = null;
            Switch ignore = null, straight = null;
            var dlg = Forms.form (win, _("Image Trace"), _("Trace"), out body, () => {
                var opts = new TraceOptions ();
                opts.mode = mode.selected == 0 ? "bw" : (mode.selected == 1 ? "gray" : "color");
                opts.colors = (int) colors.value;
                opts.threshold = (int) threshold.value;
                opts.noise = noise.value;
                opts.accuracy = accuracy.value / 100;
                opts.corner = corner.value;
                opts.ignore_white = ignore.active;
                opts.straight = straight.active;
                ImageTrace.run (win.canvas, im, opts);
            });
            mode = Forms.choice (g, _("Mode"), { _("Black and White"), _("Grayscale"), _("Color") }, 2);
            colors = Forms.spin (g, _("Colors"), 2, 64, 1, 8, 0);
            threshold = Forms.spin (g, _("Threshold"), 1, 255, 1, 128, 0);
            noise = Forms.spin (g, _("Ignore Areas Smaller Than"), 0, 10000, 1, 6, 0, _("pixels"));
            accuracy = Forms.spin (g, _("Path Fitting"), 10, 400, 10, 100, 0, _("percent"));
            corner = Forms.spin (g, _("Corners Sharper Than"), 10, 170, 5, 60, 0, _("degrees"));
            ignore = Forms.toggle (g, _("Ignore White"), true);
            straight = Forms.toggle (g, _("Straight Lines Only"), false);
            body.append (g);
            dlg.present ();
        }

        public static void make_3d (VectorWindow win, string mode) {
            Commands.make_3d (win.canvas, mode);
        }

        public static void document_setup (VectorWindow win) {
            win.canvas.clear_selection ();
            win.show_inspector_page ("properties");
        }
    }
}
