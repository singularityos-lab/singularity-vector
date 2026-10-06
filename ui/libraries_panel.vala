using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class LibrariesPanel : Box {
        private weak VectorWindow win;

        public LibrariesPanel (VectorWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.win = win;
        }

        private VectorDocument doc {
            get {
                return win.doc;
            }
        }

        public void refresh () {
            Widget? c;
            while ((c = get_first_child ()) != null) remove (c);
            if (win.doc == null) return;
            build_swatches ();
            build_symbols ();
            build_brushes ();
            build_patterns ();
        }

        private Widget chip (Paint p, string tip, bool global, bool spot) {
            var da = new DrawingArea ();
            da.set_size_request (22, 22);
            da.tooltip_text = tip;
            da.set_draw_func ((a, cr, w, h) => {
                cr.rectangle (1, 1, w - 2, h - 2);
                if (p.kind == PaintKind.LINEAR || p.kind == PaintKind.RADIAL) {
                    var pat = p.kind == PaintKind.RADIAL ? new Cairo.Pattern.radial (w / 2.0, h / 2.0, 0, w / 2.0, h / 2.0, w / 2.0) : new Cairo.Pattern.linear (0, 0, w, 0);
                    foreach (var s in p.gradient.stops) pat.add_color_stop_rgb (s.offset, s.color.r, s.color.g, s.color.b);
                    cr.set_source (pat);
                } else if (p.kind == PaintKind.PATTERN) {
                    var ctx = new RenderContext (win.doc);
                    var src = Renderer.pattern_source (p, ctx);
                    if (src != null) cr.set_source (src);
                    else cr.set_source_rgb (0.7, 0.7, 0.7);
                } else if (p.kind == PaintKind.NONE) {
                    cr.set_source_rgb (1, 1, 1);
                } else {
                    var c = p.representative ();
                    cr.set_source_rgb (c.r, c.g, c.b);
                }
                cr.fill ();
                if (p.kind == PaintKind.NONE) {
                    cr.move_to (w - 1, 1);
                    cr.line_to (1, h - 1);
                    cr.set_source_rgb (0.85, 0.1, 0.1);
                    cr.set_line_width (2);
                    cr.stroke ();
                }
                cr.rectangle (0.5, 0.5, w - 1, h - 1);
                var fgc = a.get_color ();
                cr.set_source_rgba (fgc.red, fgc.green, fgc.blue, 0.55);
                cr.set_line_width (1);
                cr.stroke ();
                if (global) {
                    cr.move_to (w - 8, h - 1);
                    cr.line_to (w - 1, h - 1);
                    cr.line_to (w - 1, h - 8);
                    cr.close_path ();
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill_preserve ();
                    cr.set_source_rgba (0, 0, 0, 0.5);
                    cr.stroke ();
                }
                if (spot) {
                    cr.arc (w - 6, 6, 3, 0, 2 * Math.PI);
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill ();
                }
            });
            return da;
        }

        private void build_swatches () {
            var g = new PreferencesGroup (_("Swatches"), _("Click to fill, middle click to stroke, right click to edit."));
            var groups = new Gee.ArrayList<string> ();
            foreach (var s in doc.swatches) if (!groups.contains (s.group)) groups.add (s.group);
            foreach (var group in groups) {
                var box = new Box (Orientation.VERTICAL, 6);
                box.margin_start = 12;
                box.margin_end = 12;
                box.margin_top = 8;
                box.margin_bottom = 10;
                var title = new Label (group != "" ? group : _("Ungrouped"));
                title.xalign = 0;
                title.add_css_class ("caption");
                title.add_css_class ("dim-label");
                box.append (title);
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.min_children_per_line = 6;
                flow.max_children_per_line = 10;
                flow.column_spacing = 4;
                flow.row_spacing = 4;
                flow.homogeneous = true;
                foreach (var s in doc.swatches) {
                    if (s.group != group) continue;
                    var sw = s;
                    var b = new Button ();
                    b.add_css_class ("flat");
                    b.add_css_class ("vector-swatch");
                    b.tooltip_text = s.name;
                    b.child = chip (s.paint, s.name, s.is_global, s.paint.color.spot != "");
                    b.clicked.connect (() => apply_swatch (sw, false));
                    var right = new GestureClick ();
                    right.button = 3;
                    right.pressed.connect (() => Dialogs.swatch_options (win, sw));
                    b.add_controller (right);
                    var middle = new GestureClick ();
                    middle.button = 2;
                    middle.pressed.connect (() => apply_swatch (sw, true));
                    b.add_controller (middle);
                    flow.append (b);
                }
                box.append (flow);
                var row = new ListBoxRow ();
                row.activatable = false;
                row.child = box;
                g.add_row (row);
            }
            Forms.header_menu (g, _("Add"), (m) => {
                m.add_item (_("New Swatch…"), "list-add-symbolic", () => Dialogs.new_swatch (win));
                m.add_item (_("Add Used Colors"), "color-select-symbolic", () => add_used_colors ());
                var libs = m.add_submenu (_("Swatch Library"), "view-grid-symbolic");
                string[] names = Palettes.names ();
                for (int i = 0; i < names.length; i++) {
                    int index = i;
                    libs.add_item (names[i], null, () => {
                        doc.begin (_("Add Swatch Library"));
                        Palettes.add_library (doc, index);
                        doc.commit ();
                        refresh ();
                    });
                }
                m.add_separator ();
                m.add_item (_("Import Palette…"), "document-open-symbolic", () => import_palette ());
                m.add_item (_("Export Palette…"), "document-save-symbolic", () => export_palette ());
                m.add_separator ();
                m.add_item (_("Recolor Artwork…"), "applications-graphics-symbolic", () => Dialogs.recolor (win));
            });
            append (g);
        }

        private void add_used_colors () {
            doc.begin (_("Add Used Colors"));
            var list = new Gee.ArrayList<Node> ();
            foreach (var l in doc.layers) list.add (l);
            foreach (var ink in Commands.artwork_colors (list)) {
                bool exists = false;
                foreach (var s in doc.swatches) if (s.paint.kind == PaintKind.SOLID && s.paint.color.same (ink)) exists = true;
                if (exists) continue;
                var s = new Swatch (ink.to_hex (), new Paint.solid (ink.copy ()));
                s.id = doc.new_id ("sw");
                s.group = _("Document Colors");
                doc.swatches.add (s);
            }
            doc.commit ();
            refresh ();
        }

        private void import_palette () {
            var dialog = new FileDialog ();
            dialog.title = _("Import Palette");
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    doc.begin (_("Import Palette"));
                    int n = Palettes.import_gpl (doc, file.get_path ());
                    doc.commit ();
                    win.toast (ngettext ("%d swatch imported", "%d swatches imported", n).printf (n));
                    refresh ();
                } catch (Error e) {
                    doc.cancel ();
                    if (!(e is DialogError.DISMISSED)) Forms.message (win, _("Could Not Import"), e.message);
                }
            });
        }

        private void export_palette () {
            var dialog = new FileDialog ();
            dialog.title = _("Export Palette");
            dialog.initial_name = win.base_name () + ".gpl";
            dialog.save.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    if (file == null) return;
                    Palettes.export_gpl (doc, file.get_path ());
                    win.toast (_("Exported %s").printf (file.get_basename ()));
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) Forms.message (win, _("Could Not Export"), e.message);
                }
            });
        }

        private void apply_swatch (Swatch sw, bool stroke) {
            var p = sw.paint.copy ();
            if (sw.is_global && p.kind == PaintKind.SOLID) p.color.swatch = sw.id;
            Commands.apply_paint (win.canvas, p, stroke);
            win.fill_stroke.queue_draw ();
            win.properties.refresh ();
        }

        private Widget art_preview (GroupNode art, int size = 36) {
            var da = new DrawingArea ();
            da.set_size_request (size, size);
            da.valign = Align.CENTER;
            da.set_draw_func ((a, cr, w, h) => {
                var b = art.visual_bounds ();
                if (b.w <= 0 || b.h <= 0) return;
                double s = double.min ((w - 4) / b.w, (h - 4) / b.h);
                cr.translate (w / 2.0, h / 2.0);
                cr.scale (s, s);
                cr.translate (-b.cx (), -b.cy ());
                Renderer.draw_node (cr, art, new RenderContext (win.doc));
            });
            return da;
        }

        private void build_symbols () {
            var g = new PreferencesGroup (_("Symbols"));
            if (doc.symbols.size == 0) g.description = _("Select artwork and choose New to reuse it as a symbol.");
            foreach (var s in doc.symbols) {
                var def = s;
                int uses = 0;
                foreach (var n in doc.all_nodes ()) {
                    var sy = n as SymbolNode;
                    if (sy != null && sy.symbol == def.id) uses++;
                }
                var row = new ActionRow (def.name, ngettext ("%d instance", "%d instances", uses).printf (uses) + (def.is_dynamic ? ", " + _("dynamic") : ""));
                var preview = art_preview (def.art);
                preview.margin_end = 10;
                row.add_prefix (preview);
                row.activated.connect (() => place (def));
                Button more = null;
                more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                    m.add_item (_("Place Instance"), "list-add-symbolic", () => place (def));
                    m.add_item (_("Spray This Symbol"), "vector-symbol-sprayer-symbolic", () => {
                        var t = win.canvas.tools["symbol-sprayer"] as SymbolSprayerTool;
                        t.symbol = def.id;
                        win.canvas.set_tool ("symbol-sprayer");
                    });
                    m.add_item (_("Symbol Options…"), "document-edit-symbolic", () => Dialogs.symbol_options (win, def));
                }));
                row.add_suffix (more);
                g.add_row (row);
            }
            Forms.header_button (g, _("New"), () => win.activate_named ("symbol-new")).tooltip_text = _("New Symbol from Selection");
            append (g);
        }

        private void place (SymbolDef def) {
            var c = win.canvas;
            Commands.place_symbol (c, def, c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0));
        }

        public void edit_symbol (SymbolDef? def) {
            if (def == null) return;
            Dialogs.symbol_options (win, def);
        }

        private void build_brushes () {
            var g = new PreferencesGroup (_("Brushes"));
            foreach (var b in doc.brushes) {
                var brush = b;
                string kind = brush.kind == "calligraphic" ? _("Calligraphic") : (brush.kind == "scatter" ? _("Scatter") : (brush.kind == "art" ? _("Art") : _("Pattern")));
                var row = new ActionRow (brush.name, kind);
                var preview = new DrawingArea ();
                preview.set_size_request (56, 24);
                preview.valign = Align.CENTER;
                preview.margin_end = 10;
                preview.set_draw_func ((a, cr, w, h) => {
                    var path = new Singularity.Vector.PathData ();
                    path.move_to (4, h / 2.0 + 4);
                    path.curve_to (w * 0.3, 0, w * 0.6, h, w - 4, h / 2.0 - 2);
                    var fg = a.get_color ();
                    var l = new PaintLayer.line (new Paint.solid (new Ink.rgb (fg.red, fg.green, fg.blue)), 1.5);
                    l.brush = brush.id;
                    var n = new PathNode.with_path (path);
                    n.appearance.add (l);
                    Renderer.draw_node (cr, n, new RenderContext (win.doc));
                });
                row.add_prefix (preview);
                row.activated.connect (() => Commands.apply_brush (win.canvas, brush.id));
                Button more = null;
                more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                    m.add_item (_("Apply to Selection"), "object-select-symbolic", () => Commands.apply_brush (win.canvas, brush.id));
                    m.add_item (_("Brush Options…"), "document-edit-symbolic", () => Dialogs.brush_options (win, brush));
                }));
                row.add_suffix (more);
                g.add_row (row);
            }
            Forms.header_menu (g, _("New"), (m) => {
                string[] ids = { "calligraphic", "scatter", "art", "pattern" };
                string[] labels = { _("Calligraphic Brush"), _("Scatter Brush"), _("Art Brush"), _("Pattern Brush") };
                for (int i = 0; i < ids.length; i++) {
                    string id = ids[i];
                    m.add_item (labels[i], null, () => {
                        var nb = Commands.new_brush (win.canvas, id, _("Brush %d").printf (doc.brushes.size + 1));
                        if (nb == null) win.toast (_("Select the artwork to use for this brush."));
                        else Dialogs.brush_options (win, nb);
                    });
                }
            });
            append (g);
        }

        private void build_patterns () {
            var g = new PreferencesGroup (_("Patterns"));
            if (doc.patterns.size == 0) g.description = _("Select artwork and choose New to tile it as a pattern.");
            foreach (var p in doc.patterns) {
                var pat = p;
                var row = new ActionRow (pat.name, tiling_label (pat.tiling));
                var preview = new DrawingArea ();
                preview.set_size_request (28, 28);
                preview.valign = Align.CENTER;
                preview.margin_end = 10;
                preview.set_draw_func ((a, cr, w, h) => {
                    var paint = new Paint ();
                    paint.kind = PaintKind.PATTERN;
                    paint.pattern = pat.id;
                    var src = Renderer.pattern_source (paint, new RenderContext (win.doc));
                    if (src == null) return;
                    cr.rectangle (0, 0, w, h);
                    cr.set_source (src);
                    cr.fill ();
                });
                row.add_prefix (preview);
                row.activated.connect (() => apply_pattern (pat));
                Button more = null;
                more = Forms.flat_icon ("view-more-symbolic", _("More"), () => Forms.popup (more, (m) => {
                    m.add_item (_("Apply to Fill"), "object-select-symbolic", () => apply_pattern (pat));
                    m.add_item (_("Pattern Options…"), "document-edit-symbolic", () => Dialogs.pattern_options (win, pat));
                }));
                row.add_suffix (more);
                g.add_row (row);
            }
            Forms.header_button (g, _("New"), () => win.activate_named ("pattern-make")).tooltip_text = _("New Pattern from Selection");
            append (g);
        }

        private static string tiling_label (string id) {
            switch (id) {
                case "brick-row": return _("Brick by Row");
                case "brick-col": return _("Brick by Column");
                case "hex-col": return _("Hex by Column");
                case "hex-row": return _("Hex by Row");
                default: return _("Grid");
            }
        }

        private void apply_pattern (PatternDef pat) {
            var paint = new Paint ();
            paint.kind = PaintKind.PATTERN;
            paint.pattern = pat.id;
            Commands.apply_paint (win.canvas, paint, false);
        }
    }
}
