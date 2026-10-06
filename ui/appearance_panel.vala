using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class AppearancePanel : Box {
        private weak VectorWindow win;
        private bool building = false;

        public AppearancePanel (VectorWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.win = win;
        }

        public static string[] effect_kinds () {
            return { "drop-shadow", "outer-glow", "inner-glow", "blur", "feather", "round-corners", "offset", "roughen", "zigzag", "pucker", "twist", "transform", "warp", "free-distort" };
        }

        public static Effect default_effect (string kind) {
            var e = new Effect (kind);
            switch (kind) {
                case "drop-shadow": e.set_num ("dx", 7).set_num ("dy", 7).set_num ("blur", 5).set_num ("opacity", 0.6).set_str ("color", "#000000"); break;
                case "outer-glow": e.set_num ("blur", 8).set_num ("opacity", 0.75).set_str ("color", "#ffed00"); break;
                case "inner-glow": e.set_num ("blur", 8).set_num ("opacity", 0.75).set_str ("color", "#ffffff"); break;
                case "blur": e.set_num ("blur", 6); break;
                case "feather": e.set_num ("blur", 8); break;
                case "round-corners": e.set_num ("radius", 10); break;
                case "offset": e.set_num ("distance", 10).set_num ("join", 1).set_num ("miter", 4); break;
                case "roughen": e.set_num ("size", 5).set_num ("detail", 10).set_num ("smooth", 1).set_num ("seed", 1); break;
                case "zigzag": e.set_num ("size", 6).set_num ("ridges", 6).set_num ("smooth", 0); break;
                case "pucker": e.set_num ("amount", 0.3); break;
                case "twist": e.set_num ("angle", 45); break;
                case "transform": e.set_num ("sx", 1).set_num ("sy", 1).set_num ("dx", 20).set_num ("dy", 0).set_num ("angle", 0).set_num ("copies", 3); break;
                case "warp": e.set_str ("style", "arc").set_num ("bend", 0.5).set_num ("h", 0).set_num ("v", 0).set_num ("vertical", 0); break;
                case "free-distort": e.set_num ("u0", 0).set_num ("v0", 0).set_num ("u1", 1).set_num ("v1", 0.1).set_num ("u2", 0.9).set_num ("v2", 1).set_num ("u3", 0.1).set_num ("v3", 0.9); break;
            }
            return e;
        }

        public void refresh () {
            if (building) return;
            var root = get_root () as Gtk.Window;
            if (root != null) {
                var f = root.get_focus ();
                if (f != null && f.is_ancestor (this)) return;
            }
            building = true;
            Widget? c;
            while ((c = get_first_child ()) != null) remove (c);
            var canvas = win.canvas;
            if (canvas == null) {
                building = false;
                return;
            }
            if (canvas.selection.size == 0) {
                var empty = new WelcomePage ();
                empty.is_section = true;
                empty.embedded = true;
                empty.compact = true;
                empty.app_icon_name = "dev.sinty.vector";
                empty.title = _("No Selection");
                empty.subtitle = _("Select an object to see its fills, strokes and effects.");
                empty.add_action ("dev.sinty.vector", _("Select All"), _("Every unlocked object"), () => win.activate_named ("select-all"));
                empty.add_action ("image-x-generic", _("Place Image…"), _("Add a picture"), () => win.activate_named ("place-image"));
                append (empty);
                build_styles (null);
                building = false;
                return;
            }
            var n = canvas.selection[0];
            var g = new PreferencesGroup (_("Fills and Strokes"));
            g.description = n.display_name ();
            for (int i = n.appearance.size - 1; i >= 0; i--) g.add_row (layer_row (n, i));
            Forms.header_menu (g, _("Add"), (m) => {
                m.add_item (_("Fill"), null, () => edit (n, () => n.appearance.insert (0, new PaintLayer.fill (new Paint.hex ("#cccccc")))));
                m.add_item (_("Stroke"), null, () => edit (n, () => n.appearance.add (new PaintLayer.line (new Paint.hex ("#000000"), 2))));
                m.add_separator ();
                m.add_item (_("Clear Appearance"), null, () => edit (n, () => {
                    n.appearance.clear ();
                    n.effects.clear ();
                    n.appearance.add (new PaintLayer.fill (new Paint ()));
                    n.appearance.add (new PaintLayer.line (new Paint (), 1));
                }), "destructive-action");
            });
            append (g);
            var fx = new PreferencesGroup (_("Effects"));
            for (int i = 0; i < n.effects.size; i++) fx.add_row (effect_row (n, n.effects, i));
            if (n.effects.size == 0) fx.description = _("Effects change how the object looks without editing its paths.");
            Forms.header_menu (fx, _("Add"), (m) => {
                foreach (var k in effect_kinds ()) {
                    string kind = k;
                    m.add_item (new Effect (kind).label (), null, () => {
                        var e = default_effect (kind);
                        edit (n, () => n.effects.add (e));
                        Dialogs.effect (win, n, e);
                    });
                }
            });
            append (fx);
            build_styles (n);
            building = false;
        }

        public delegate void Change ();

        private void edit (Node n, Change change) {
            var doc = win.doc;
            doc.begin (_("Appearance"));
            change ();
            foreach (var other in win.canvas.selection) {
                if (other == n) continue;
                other.appearance.clear ();
                foreach (var l in n.appearance) other.appearance.add (l.copy ());
                other.effects.clear ();
                foreach (var e in n.effects) other.effects.add (e.copy ());
            }
            doc.commit ();
            refresh ();
        }

        private Widget layer_row (Node n, int index) {
            var l = n.appearance[index];
            string name = l.stroke ? _("Stroke %s px").printf (Units.format (l.width)) : _("Fill");
            string sub = _("Opacity %d%%").printf ((int) Math.round (l.opacity * 100));
            if (l.effects.size > 0) sub += ", " + ngettext ("%d effect", "%d effects", l.effects.size).printf (l.effects.size);
            var row = new ActionRow (name, sub);
            var swatch = new DrawingArea ();
            swatch.set_size_request (22, 22);
            swatch.valign = Align.CENTER;
            swatch.margin_end = 12;
            swatch.set_draw_func ((a, cr, w, h) => {
                var c = l.paint.representative ();
                if (l.paint.visible ()) {
                    cr.set_source_rgb (c.r, c.g, c.b);
                    cr.rectangle (1, 1, w - 2, h - 2);
                    cr.fill ();
                }
                cr.rectangle (0.5, 0.5, w - 1, h - 1);
                var fgc = a.get_color ();
                cr.set_source_rgba (fgc.red, fgc.green, fgc.blue, 0.55);
                cr.set_line_width (1);
                cr.stroke ();
            });
            row.add_prefix (swatch);
            row.activated.connect (() => Dialogs.paint_layer (win, n, l));
            var vis = new ToggleButton ();
            vis.icon_name = l.visible ? "view-reveal-symbolic" : "view-conceal-symbolic";
            vis.active = l.visible;
            vis.add_css_class ("flat");
            vis.add_css_class ("sx-layer-toggle");
            vis.valign = Align.CENTER;
            vis.tooltip_text = l.visible ? _("Hide") : _("Show");
            vis.toggled.connect (() => edit (n, () => l.visible = vis.active));
            row.add_suffix (vis);
            Button more = null;
            more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                m.add_item (_("Edit…"), "document-edit-symbolic", () => Dialogs.paint_layer (win, n, l));
                m.add_item (_("Duplicate"), "edit-copy-symbolic", () => edit (n, () => n.appearance.insert (index + 1, l.copy ())));
                if (index + 1 < n.appearance.size) m.add_item (_("Move Up"), "go-up-symbolic", () => edit (n, () => {
                    n.appearance.remove_at (index);
                    n.appearance.insert (index + 1, l);
                }));
                if (index > 0) m.add_item (_("Move Down"), "go-down-symbolic", () => edit (n, () => {
                    n.appearance.remove_at (index);
                    n.appearance.insert (index - 1, l);
                }));
                m.add_separator ();
                m.add_item (_("Remove"), "list-remove-symbolic", () => edit (n, () => n.appearance.remove_at (index)), "destructive-action");
            }));
            row.add_suffix (more);
            return row;
        }

        private Widget effect_row (Node n, Gee.List<Effect> list, int index) {
            var e = list[index];
            var row = new ActionRow (e.label ());
            var on = new Switch ();
            on.active = e.enabled;
            on.valign = Align.CENTER;
            on.notify["active"].connect (() => edit (n, () => e.enabled = on.active));
            row.add_suffix (on);
            row.activated.connect (() => Dialogs.effect (win, n, e));
            Button more = null;
            more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                m.add_item (_("Options…"), "document-edit-symbolic", () => Dialogs.effect (win, n, e));
                m.add_separator ();
                m.add_item (_("Remove"), "list-remove-symbolic", () => edit (n, () => list.remove_at (index)), "destructive-action");
            }));
            row.add_suffix (more);
            return row;
        }

        private void build_styles (Node? n) {
            var g = new PreferencesGroup (_("Graphic Styles"));
            var doc = win.doc;
            if (doc.styles.size == 0) g.description = _("Save the look of an object to apply it to others.");
            foreach (var s in doc.styles) {
                var row = new ActionRow (s.name, ngettext ("%d fill or stroke", "%d fills and strokes", s.appearance.size).printf (s.appearance.size));
                var preview = new DrawingArea ();
                preview.set_size_request (28, 28);
                preview.valign = Align.CENTER;
                preview.margin_end = 10;
                var style = s;
                preview.set_draw_func ((a, cr, w, h) => {
                    var pn = new PathNode.with_path (new Singularity.Vector.PathData.round_rect (5, 5, w - 10, h - 10, 4));
                    style.apply (pn);
                    var ctx = new RenderContext (doc);
                    Renderer.draw_node (cr, pn, ctx);
                });
                row.add_prefix (preview);
                if (n != null) row.activated.connect (() => Commands.apply_style (win.canvas, style));
                Button more = null;
                more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                    if (n != null) {
                        m.add_item (_("Apply"), "object-select-symbolic", () => Commands.apply_style (win.canvas, style));
                        m.add_item (_("Redefine from Selection"), "view-refresh-symbolic", () => Commands.redefine_style (win.canvas, style));
                        m.add_separator ();
                    }
                    m.add_item (_("Delete"), "user-trash-symbolic", () => {
                        doc.begin (_("Delete Graphic Style"));
                        doc.styles.remove (style);
                        doc.commit ();
                        refresh ();
                    }, "destructive-action");
                }));
                row.add_suffix (more);
                g.add_row (row);
            }
            if (n != null) Forms.header_button (g, _("New…"), () => Dialogs.new_style (win));
            append (g);
        }
    }
}
