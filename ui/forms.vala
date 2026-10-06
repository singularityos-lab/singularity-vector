using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class FieldRow : EntryRow {
        public FieldRow (string title) {
            base (title);
        }

        public Entry field {
            get {
                return entry;
            }
        }
    }

    public class Forms {
        public delegate void Done ();

        public static AppDialog form (Gtk.Window parent, string title, string action, out Box body, owned Done done, int width = 440) {
            var dlg = new AppDialog (parent.application, true, false);
            dlg.set_title (title);
            dlg.transient_for = parent;
            dlg.set_default_size (width, -1);
            body = new Box (Orientation.VERTICAL, 12);
            body.margin_start = 18;
            body.margin_end = 18;
            body.margin_top = 6;
            body.margin_bottom = 12;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 620;
            scroll.child = body;
            dlg.content_box.append (scroll);
            var buttons = new Box (Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            buttons.margin_end = 18;
            buttons.margin_bottom = 18;
            if (action == _("Close")) {
                buttons.append (dlg.add_cancel_button (_("Close")));
            } else {
                buttons.append (dlg.add_cancel_button (_("Cancel")));
                var ok = new Button.with_label (action);
                ok.add_css_class ("suggested-action");
                ok.clicked.connect (() => {
                    done ();
                    dlg.close_dialog ();
                });
                buttons.append (ok);
            }
            dlg.content_box.append (buttons);
            return dlg;
        }

        public static void confirm (Gtk.Window parent, string title, string body, string action, owned Done done, bool destructive = false) {
            var dlg = new ConfirmDialog (parent.application, title, null, body, action, destructive ? ConfirmDialog.ActionStyle.DESTRUCTIVE : ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = parent;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) done ();
            });
            dlg.present ();
        }

        public static void message (Gtk.Window parent, string title, string body) {
            var dlg = new ConfirmDialog.message (parent.application, title, null, body);
            dlg.transient_for = parent;
            dlg.present ();
        }

        public static SpinButton spin (PreferencesGroup g, string title, double min, double max, double step, double value, int digits = 1, string? subtitle = null) {
            bool unit = subtitle != null && is_unit (subtitle);
            bool percent = subtitle != null && subtitle == _("percent");
            var row = new SpinRow (percent ? "%s (%%)".printf (title) : title, unit || percent ? null : subtitle, min, max, step, value);
            row.spin_btn.digits = digits;
            row.spin_btn.value = value;
            row.spin_btn.width_chars = 6;
            if (unit && g.description == "") g.description = _("Lengths in %s").printf (subtitle);
            g.add_row (row);
            return row.spin_btn;
        }

        private static bool is_unit (string s) {
            foreach (var u in new string[] { "px", "pt", "mm", "cm", "in" }) if (s == Units.label (u)) return true;
            return false;
        }

        public static Entry entry (PreferencesGroup g, string title, string value) {
            var row = new FieldRow (title);
            row.text = value;
            g.add_row (row);
            return row.field;
        }

        public static Switch toggle (PreferencesGroup g, string title, bool value, string? subtitle = null) {
            var row = new SwitchRow (title, subtitle, value);
            g.add_row (row);
            return row.switch_btn;
        }

        public static DropDown choice (PreferencesGroup g, string title, string[] labels, int selected) {
            var d = new DropDown.from_strings (labels);
            d.selected = selected.clamp (0, labels.length - 1);
            var row = new SelectionRow (title, labels, labels[d.selected]);
            string[] items = labels;
            row.selected.connect ((item) => {
                for (int i = 0; i < items.length; i++) {
                    if (items[i] == item) {
                        row.expanded = false;
                        if (d.selected != i) d.selected = i;
                        return;
                    }
                }
            });
            d.notify["selected"].connect (() => {
                if (d.selected < items.length) row.current_value = items[d.selected];
            });
            row.set_data<DropDown> ("vector-choice", d);
            g.add_row (row);
            return d;
        }

        public static ColorPickerButton color (PreferencesGroup g, string title, Ink ink) {
            var row = new ActionRow (title);
            var rgba = Gdk.RGBA ();
            rgba.red = (float) ink.r;
            rgba.green = (float) ink.g;
            rgba.blue = (float) ink.b;
            rgba.alpha = 1;
            var b = new ColorPickerButton (rgba);
            b.valign = Align.CENTER;
            row.add_suffix (b);
            g.add_row (row);
            return b;
        }

        public static Ink ink_of (Gdk.RGBA c) {
            return new Ink.rgb (c.red, c.green, c.blue);
        }

        public static Gdk.RGBA rgba (Ink ink) {
            var c = Gdk.RGBA ();
            c.red = (float) ink.r;
            c.green = (float) ink.g;
            c.blue = (float) ink.b;
            c.alpha = 1;
            return c;
        }

        public static Button icon_button (string icon, string tooltip, owned Done action) {
            var b = new Button.from_icon_name (icon);
            b.tooltip_text = tooltip;
            b.add_css_class ("flat");
            b.update_property (AccessibleProperty.LABEL, tooltip, -1);
            b.clicked.connect (() => action ());
            return b;
        }

        public delegate void MenuFill (ContextMenu menu);

        public static Button pill (string label, owned Done action) {
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            b.clicked.connect (() => action ());
            return b;
        }

        public static Button header_button (PreferencesGroup g, string label, owned Done action) {
            var b = pill (label, (owned) action);
            g.add_header_suffix (b);
            return b;
        }

        public static Button menu_pill (string label, owned MenuFill fill) {
            var b = new Button ();
            var box = new Box (Orientation.HORIZONTAL, 4);
            box.append (new Label (label));
            var arrow = new Image.from_icon_name ("pan-down-symbolic");
            arrow.pixel_size = 12;
            box.append (arrow);
            b.child = box;
            b.valign = Align.CENTER;
            b.clicked.connect (() => popup (b, fill));
            return b;
        }

        public static Button header_menu (PreferencesGroup g, string label, owned MenuFill fill) {
            var b = menu_pill (label, (owned) fill);
            g.add_header_suffix (b);
            return b;
        }

        public static ActionRow menu_row (PreferencesGroup g, string title, string? subtitle, string label, owned MenuFill fill) {
            var row = new ActionRow (title, subtitle);
            row.add_suffix (menu_pill (label, (owned) fill));
            g.add_row (row);
            return row;
        }

        public static void popup (Widget anchor, MenuFill fill) {
            var menu = new ContextMenu (anchor);
            fill (menu);
            menu.closed.connect (() => Idle.add (() => {
                if (menu.get_parent () != null) menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        public static ActionRow action (PreferencesGroup g, string title, string? subtitle, string label, owned Done action) {
            var row = new ActionRow (title, subtitle);
            row.add_suffix (pill (label, (owned) action));
            g.add_row (row);
            return row;
        }

        public static Button flat_icon (string icon, string tooltip, owned Done action) {
            var b = icon_button (icon, tooltip, (owned) action);
            b.valign = Align.CENTER;
            return b;
        }

        public static Button text_button (string label, owned Done action) {
            var b = new Button.with_label (label);
            b.clicked.connect (() => action ());
            return b;
        }

        public static Widget empty (string title, string description) {
            var page = new StatusPage ();
            page.icon_name = "dev.sinty.vector";
            page.title = title;
            page.description = description;
            page.vexpand = true;
            return page;
        }

        public static Label hint (string text) {
            var l = new Label (text);
            l.add_css_class ("dim-label");
            l.wrap = true;
            l.xalign = 0;
            return l;
        }
    }
}
