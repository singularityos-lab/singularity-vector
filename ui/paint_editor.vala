using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class GradientBar : DrawingArea {
        public Gradient gradient;
        public int selected = 0;
        public signal void changed ();
        public signal void stop_selected (int index);
        private int dragging = -1;

        public GradientBar (Gradient g) {
            gradient = g;
            set_size_request (-1, 34);
            hexpand = true;
            set_draw_func (draw);
            var drag = new GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                int w = get_width ();
                double t = ((x - 8) / (w - 16)).clamp (0, 1);
                dragging = -1;
                for (int i = 0; i < gradient.stops.size; i++) {
                    double sx = 8 + gradient.stops[i].offset * (w - 16);
                    if ((sx - x).abs () < 7) dragging = i;
                }
                if (dragging < 0) {
                    var c = color_at (t);
                    gradient.stops.add (new GradientStop (t, c));
                    dragging = gradient.stops.size - 1;
                    changed ();
                }
                selected = dragging;
                stop_selected (selected);
                queue_draw ();
            });
            drag.drag_update.connect ((dx, dy) => {
                if (dragging < 0) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                int w = get_width ();
                gradient.stops[dragging].offset = ((sx + dx - 8) / (w - 16)).clamp (0, 1);
                queue_draw ();
                changed ();
            });
            drag.drag_end.connect (() => {
                dragging = -1;
            });
            add_controller (drag);
        }

        private Ink color_at (double t) {
            GradientStop? a = null, b = null;
            foreach (var s in gradient.stops) {
                if (s.offset <= t && (a == null || s.offset > a.offset)) a = s;
                if (s.offset >= t && (b == null || s.offset < b.offset)) b = s;
            }
            if (a == null) return b.color.copy ();
            if (b == null) return a.color.copy ();
            double span = b.offset - a.offset;
            return Interpolate.ink (a.color, b.color, span > 0 ? (t - a.offset) / span : 0);
        }

        private void draw (DrawingArea area, Cairo.Context cr, int w, int h) {
            for (int y = 0; y < 10; y++) {
                for (int x = 0; x < (w - 16) / 5 + 1; x++) {
                    cr.rectangle (8 + x * 5, 4 + y * 2, 5, 2);
                    double v = (x + y / 2) % 2 == 0 ? 0.85 : 1;
                    cr.set_source_rgb (v, v, v);
                    cr.fill ();
                }
            }
            var pat = new Cairo.Pattern.linear (8, 0, w - 8, 0);
            var stops = new Gee.ArrayList<GradientStop> ();
            stops.add_all (gradient.stops);
            stops.sort ((a, b) => a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
            foreach (var s in stops) pat.add_color_stop_rgba (s.offset, s.color.r, s.color.g, s.color.b, s.opacity);
            cr.rectangle (8, 4, w - 16, 18);
            cr.set_source (pat);
            cr.fill ();
            for (int i = 0; i < gradient.stops.size; i++) {
                var s = gradient.stops[i];
                double x = 8 + s.offset * (w - 16);
                cr.move_to (x, 22);
                cr.line_to (x - 6, 32);
                cr.line_to (x + 6, 32);
                cr.close_path ();
                cr.set_source_rgb (s.color.r, s.color.g, s.color.b);
                cr.fill_preserve ();
                cr.set_line_width (i == selected ? 2 : 1);
                cr.set_source_rgb (i == selected ? 0.2 : 0.5, i == selected ? 0.5 : 0.5, i == selected ? 0.95 : 0.5);
                cr.stroke ();
            }
        }
    }

    public class PaintEditor : PreferencesGroup {
        public Paint paint;
        public signal void changed (Paint paint);
        private weak VectorWindow win;
        private bool stroke;
        private int selected_stop = 0;
        private Gee.ArrayList<Widget> extra = new Gee.ArrayList<Widget> ();

        public PaintEditor (VectorWindow win, Paint paint, bool stroke, string? title = null) {
            Object ();
            this.title = title ?? (stroke ? _("Stroke") : _("Fill"));
            this.win = win;
            this.paint = paint.copy ();
            this.stroke = stroke;
            rebuild ();
        }

        public void add_extra (Widget row) {
            extra.add (row);
            add_row (row);
        }

        private void emit () {
            changed (paint.copy ());
        }

        private SpinButton spin (string title, double min, double max, double step, double value) {
            var row = new SpinRow (title, null, min, max, step, value);
            row.spin_btn.digits = 0;
            row.spin_btn.width_chars = 6;
            add_row (row);
            return row.spin_btn;
        }

        private DropDown choice (string title, string[] labels, int selected) {
            var holder = new PreferencesGroup ();
            var d = Forms.choice (holder, title, labels, selected);
            var row = holder.get_rows ()[0];
            holder.remove_row (row);
            add_row (row);
            return d;
        }

        private void rebuild () {
            foreach (var w in extra) if (w.get_parent () != null) remove_row (w);
            clear ();
            description = "";
            string[] kinds = { _("None"), _("Color"), _("Linear Gradient"), _("Radial Gradient"), _("Freeform Gradient"), _("Pattern") };
            var kind = choice (_("Type"), kinds, (int) paint.kind);
            kind.notify["selected"].connect (() => {
                var k = (PaintKind) kind.selected;
                if (k == paint.kind) return;
                var rep = paint.representative ().copy ();
                paint.kind = k;
                if ((k == PaintKind.LINEAR || k == PaintKind.RADIAL) && paint.gradient.stops.size < 2) paint.gradient = new Gradient.two (rep, Ink.hex ("#000000"));
                if (k == PaintKind.SOLID) paint.color = rep;
                if (k == PaintKind.PATTERN && paint.pattern == "" && win.doc.patterns.size > 0) paint.pattern = win.doc.patterns[0].id;
                if (k == PaintKind.FREEFORM) paint.freeform.clear ();
                emit ();
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            switch (paint.kind) {
                case PaintKind.SOLID:
                    color_rows (_("Color"), paint.color, (ink) => {
                        paint.color = ink;
                        emit ();
                    });
                    break;
                case PaintKind.LINEAR:
                case PaintKind.RADIAL:
                    description = _("Drag on the canvas with the Gradient tool to set direction and length.");
                    var bar = new GradientBar (paint.gradient);
                    bar.selected = selected_stop.clamp (0, paint.gradient.stops.size - 1);
                    bar.changed.connect (() => emit ());
                    bar.stop_selected.connect ((i) => {
                        selected_stop = i;
                        Idle.add (() => {
                            rebuild ();
                            return Source.REMOVE;
                        });
                    });
                    var bar_row = new ListBoxRow ();
                    bar_row.activatable = false;
                    bar.margin_start = 8;
                    bar.margin_end = 8;
                    bar.margin_top = 6;
                    bar.margin_bottom = 4;
                    bar_row.child = bar;
                    add_row (bar_row);
                    if (paint.gradient.stops.size > 0) {
                        int i = selected_stop.clamp (0, paint.gradient.stops.size - 1);
                        var s = paint.gradient.stops[i];
                        color_rows (_("Stop Color"), s.color, (ink) => {
                            s.color = ink;
                            bar.queue_draw ();
                            emit ();
                        }, false);
                        var loc = spin (_("Location (%)"), 0, 100, 1, Math.round (s.offset * 100));
                        loc.value_changed.connect (() => {
                            s.offset = loc.value / 100;
                            bar.queue_draw ();
                            emit ();
                        });
                        var op = spin (_("Opacity (%)"), 0, 100, 1, Math.round (s.opacity * 100));
                        op.value_changed.connect (() => {
                            s.opacity = op.value / 100;
                            bar.queue_draw ();
                            emit ();
                        });
                        var mid = spin (_("Midpoint (%)"), 5, 95, 1, Math.round (s.midpoint * 100));
                        mid.value_changed.connect (() => {
                            s.midpoint = mid.value / 100;
                            emit ();
                        });
                        var stop_row = new ActionRow (_("Color Stop"));
                        stop_row.add_suffix (Forms.flat_icon ("object-flip-horizontal-symbolic", _("Reverse Gradient"), () => {
                            paint.gradient.reverse ();
                            emit ();
                            rebuild ();
                        }));
                        var del = Forms.flat_icon ("list-remove-symbolic", _("Remove Color Stop"), () => {
                            if (paint.gradient.stops.size <= 2) return;
                            paint.gradient.stops.remove_at (i);
                            selected_stop = 0;
                            emit ();
                            rebuild ();
                        });
                        del.sensitive = paint.gradient.stops.size > 2;
                        stop_row.add_suffix (del);
                        add_row (stop_row);
                    }
                    if (paint.kind == PaintKind.RADIAL) {
                        var asp = spin (_("Aspect Ratio (%)"), 1, 1000, 1, Math.round (paint.gradient.aspect * 100));
                        asp.value_changed.connect (() => {
                            paint.gradient.aspect = asp.value / 100;
                            emit ();
                        });
                    }
                    var spread = choice (_("Spread"), { _("Pad"), _("Reflect"), _("Repeat") }, paint.gradient.spread == "reflect" ? 1 : (paint.gradient.spread == "repeat" ? 2 : 0));
                    spread.notify["selected"].connect (() => {
                        paint.gradient.spread = spread.selected == 1 ? "reflect" : (spread.selected == 2 ? "repeat" : "pad");
                        emit ();
                    });
                    break;
                case PaintKind.FREEFORM:
                    if (paint.freeform.size == 0) description = _("Add color points, then drag them on the canvas with the Gradient tool.");
                    for (int i = 0; i < paint.freeform.size; i++) {
                        var f = paint.freeform[i];
                        int idx = i;
                        var row = new ActionRow (_("Point %d").printf (i + 1));
                        var picker = new ColorPickerButton (Forms.rgba (f.color));
                        picker.valign = Align.CENTER;
                        picker.color_changed.connect ((c) => {
                            f.color = Forms.ink_of (c);
                            emit ();
                        });
                        row.add_suffix (picker);
                        var spread = new SpinButton.with_range (5, 300, 5);
                        spread.value = f.spread * 100;
                        spread.valign = Align.CENTER;
                        spread.tooltip_text = _("Spread");
                        spread.value_changed.connect (() => {
                            f.spread = spread.value / 100;
                            emit ();
                        });
                        row.add_suffix (spread);
                        row.add_suffix (Forms.flat_icon ("list-remove-symbolic", _("Remove Point"), () => {
                            paint.freeform.remove_at (idx);
                            emit ();
                            rebuild ();
                        }));
                        add_row (row);
                    }
                    Forms.action (this, _("Color Points"), null, _("Add"), () => {
                        var cv = win.canvas;
                        var b = cv != null ? cv.selection_bounds () : Rect (0, 0, 100, 100);
                        paint.freeform.add (new FreeformPoint (b.cx () + Random.double_range (-b.w / 4, b.w / 4), b.cy () + Random.double_range (-b.h / 4, b.h / 4), Ink.hex ("#3aaa35")));
                        emit ();
                        rebuild ();
                    });
                    break;
                case PaintKind.PATTERN:
                    string[] names = {};
                    int sel = 0;
                    for (int i = 0; i < win.doc.patterns.size; i++) {
                        names += win.doc.patterns[i].name;
                        if (win.doc.patterns[i].id == paint.pattern) sel = i;
                    }
                    if (names.length == 0) {
                        description = _("Select artwork and choose Object, Make Pattern to create one.");
                        break;
                    }
                    var dd = choice (_("Pattern"), names, sel);
                    dd.notify["selected"].connect (() => {
                        paint.pattern = win.doc.patterns[(int) dd.selected].id;
                        emit ();
                    });
                    double cur = Math.sqrt ((paint.pattern_matrix.xx * paint.pattern_matrix.yy - paint.pattern_matrix.xy * paint.pattern_matrix.yx).abs ());
                    var sc = spin (_("Scale (%)"), 1, 2000, 5, Math.round (cur * 100));
                    var an = spin (_("Angle"), -360, 360, 5, Math.round (Math.atan2 (paint.pattern_matrix.yx, paint.pattern_matrix.xx) * 180 / Math.PI));
                    sc.value_changed.connect (() => {
                        var m = Cairo.Matrix.identity ();
                        m.rotate (an.value * Math.PI / 180);
                        m.scale (sc.value / 100, sc.value / 100);
                        m.x0 = paint.pattern_matrix.x0;
                        m.y0 = paint.pattern_matrix.y0;
                        paint.pattern_matrix = m;
                        emit ();
                    });
                    an.value_changed.connect (() => sc.value_changed ());
                    break;
                default:
                    break;
            }
            if (paint.kind != PaintKind.NONE) {
                var over = new SwitchRow (_("Overprint"), null, paint.overprint);
                over.notify["active"].connect (() => {
                    paint.overprint = over.active;
                    emit ();
                });
                add_row (over);
            }
            foreach (var w in extra) add_row (w);
        }

        public delegate void InkFunc (Ink ink);

        private void color_rows (string title, Ink ink, owned InkFunc set_ink, bool with_swatches = true) {
            var row = new ActionRow (title);
            var picker = new ColorPickerButton (Forms.rgba (ink));
            picker.valign = Align.CENTER;
            var hex = new Entry ();
            hex.text = ink.to_hex ();
            hex.width_chars = 8;
            hex.max_width_chars = 8;
            hex.valign = Align.CENTER;
            picker.color_changed.connect ((c) => {
                var n = Forms.ink_of (c);
                n.spot = ink.spot;
                hex.text = n.to_hex ();
                set_ink (n);
            });
            hex.activate.connect (() => {
                var n = Ink.hex (hex.text);
                n.spot = ink.spot;
                picker.color = Forms.rgba (n);
                set_ink (n);
            });
            row.add_suffix (hex);
            row.add_suffix (picker);
            add_row (row);
            if (win.doc.color_mode == "cmyk") {
                ink.ensure_cmyk ();
                SpinButton[] spins = {};
                double[] vals = { ink.c, ink.m, ink.y, ink.k };
                string[] names = { _("Cyan (%)"), _("Magenta (%)"), _("Yellow (%)"), _("Black (%)") };
                for (int i = 0; i < 4; i++) spins += spin (names[i], 0, 100, 1, Math.round (vals[i] * 100));
                foreach (var s in spins) {
                    s.value_changed.connect (() => {
                        var n = new Ink.cmyk (spins[0].value / 100, spins[1].value / 100, spins[2].value / 100, spins[3].value / 100);
                        n.spot = ink.spot;
                        picker.color = Forms.rgba (n);
                        hex.text = n.to_hex ();
                        set_ink (n);
                    });
                }
            }
            if (!with_swatches) return;
            var swatches = new FlowBox ();
            swatches.min_children_per_line = 8;
            swatches.max_children_per_line = 12;
            swatches.selection_mode = SelectionMode.NONE;
            swatches.homogeneous = true;
            swatches.column_spacing = 2;
            swatches.row_spacing = 2;
            int count = 0;
            foreach (var sw in win.doc.swatches) {
                if (sw.paint.kind != PaintKind.SOLID) continue;
                var b = new Button ();
                b.add_css_class ("flat");
                b.add_css_class ("vector-swatch");
                b.tooltip_text = sw.name + (sw.is_global ? " " + _("(global)") : "") + (sw.paint.color.spot != "" ? " " + _("(spot)") : "");
                var da = new DrawingArea ();
                da.set_size_request (18, 18);
                var swc = sw.paint.color;
                bool global = sw.is_global;
                da.set_draw_func ((a, cr, w, h) => {
                    cr.rectangle (1, 1, w - 2, h - 2);
                    cr.set_source_rgb (swc.r, swc.g, swc.b);
                    cr.fill_preserve ();
                    var fgc = a.get_color ();
                    cr.set_source_rgba (fgc.red, fgc.green, fgc.blue, 0.55);
                    cr.set_line_width (1);
                    cr.stroke ();
                    if (global) {
                        cr.move_to (w - 7, h - 1);
                        cr.line_to (w - 1, h - 1);
                        cr.line_to (w - 1, h - 7);
                        cr.close_path ();
                        cr.set_source_rgb (1, 1, 1);
                        cr.fill ();
                    }
                });
                b.child = da;
                var sid = sw.id;
                b.clicked.connect (() => {
                    var n = swc.copy ();
                    if (global) n.swatch = sid;
                    picker.color = Forms.rgba (n);
                    hex.text = n.to_hex ();
                    set_ink (n);
                });
                swatches.append (b);
                count++;
            }
            if (count == 0) return;
            var srow = new ListBoxRow ();
            srow.activatable = false;
            swatches.margin_start = 10;
            swatches.margin_end = 10;
            swatches.margin_top = 6;
            swatches.margin_bottom = 8;
            srow.child = swatches;
            add_row (srow);
        }
    }
}
