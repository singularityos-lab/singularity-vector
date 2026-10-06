using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class PropertiesPanel : Box {
        private weak VectorWindow win;
        private bool building = false;
        private bool focus_stroke = false;

        public PropertiesPanel (VectorWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.win = win;
        }

        private VectorCanvas? canvas {
            get {
                return win.canvas;
            }
        }

        private VectorDocument? doc {
            get {
                return win.doc;
            }
        }

        public void focus_paint (bool stroke) {
            focus_stroke = stroke;
            focus_paint_requested = true;
            refresh ();
            focus_stroke = false;
        }

        public void refresh_values () {
            var root = get_root () as Gtk.Window;
            if (root != null) {
                var f = root.get_focus ();
                if (f != null && f.is_ancestor (this)) return;
            }
            refresh ();
        }

        public void refresh () {
            if (building) return;
            building = true;
            Widget? c;
            while ((c = get_first_child ()) != null) remove (c);
            if (canvas == null || doc == null) {
                building = false;
                return;
            }
            var sel = canvas.selection;
            if (canvas.tool is ArtboardTool || sel.size == 0) {
                build_document ();
            } else {
                build_transform ();
                if (sel.size == 1) build_specific (sel[0]);
                build_paint ();
                build_opacity ();
                build_align ();
                build_pathfinder ();
                build_quick ();
            }
            building = false;
        }

        private void build_document () {
            var a = doc.current_artboard ();
            if (a != null) {
                var g = new PreferencesGroup (_("Artboard"));
                var name = Forms.entry (g, _("Name"), a.name);
                name.activate.connect (() => {
                    doc.begin (_("Rename Artboard"));
                    a.name = name.text;
                    doc.commit ();
                    doc.structure_changed ();
                });
                double f = Units.factor (doc.units);
                var x = Forms.spin (g, _("X"), -100000, 100000, 1, a.x / f, 2, Units.label (doc.units));
                var y = Forms.spin (g, _("Y"), -100000, 100000, 1, a.y / f, 2, Units.label (doc.units));
                var w = Forms.spin (g, _("Width"), 0.01, 100000, 1, a.w / f, 2, Units.label (doc.units));
                var h = Forms.spin (g, _("Height"), 0.01, 100000, 1, a.h / f, 2, Units.label (doc.units));
                var bleed = Forms.spin (g, _("Bleed"), 0, 1000, 1, a.bleed / f, 2, Units.label (doc.units));
                foreach (var s in new SpinButton[] { x, y, w, h, bleed }) {
                    s.value_changed.connect (() => {
                        if (building) return;
                        doc.begin (_("Artboard Options"));
                        a.x = x.value * f;
                        a.y = y.value * f;
                        a.w = w.value * f;
                        a.h = h.value * f;
                        a.bleed = bleed.value * f;
                        doc.commit ();
                    });
                }
                string[] presets = { _("Custom"), "A4", "A3", "A5", _("US Letter"), _("Icon 16"), _("Icon 32"), _("Icon 256"), "1920 x 1080", "1080 x 1080", "iPhone 390 x 844" };
                double[,] sizes = { { 0, 0 }, { 793.7, 1122.5 }, { 1122.5, 1587.4 }, { 559.4, 793.7 }, { 816, 1056 }, { 16, 16 }, { 32, 32 }, { 256, 256 }, { 1920, 1080 }, { 1080, 1080 }, { 390, 844 } };
                var preset = Forms.choice (g, _("Preset"), presets, 0);
                preset.notify["selected"].connect (() => {
                    int i = (int) preset.selected;
                    if (i == 0) return;
                    doc.begin (_("Artboard Preset"));
                    a.w = sizes[i, 0];
                    a.h = sizes[i, 1];
                    doc.commit ();
                    refresh ();
                });
                var transparent = Forms.toggle (g, _("Transparent Background"), a.background == "");
                transparent.notify["active"].connect (() => {
                    doc.begin (_("Artboard Background"));
                    a.background = transparent.active ? "" : "#ffffff";
                    doc.commit ();
                });
                Forms.action (g, _("Fit to Artwork"), _("Resize the artboard around its content."), _("Fit"), () => Commands.artboard_fit (canvas));
                Forms.header_button (g, _("Duplicate"), () => win.activate_named ("artboard-duplicate"));
                append (g);
            }
            var d = new PreferencesGroup (_("Document"));
            string[] units = { "px", "pt", "mm", "cm", "in" };
            int ui = 0;
            for (int i = 0; i < units.length; i++) if (units[i] == doc.units) ui = i;
            var unit = Forms.choice (d, _("Units"), { _("Pixels"), _("Points"), _("Millimeters"), _("Centimeters"), _("Inches") }, ui);
            unit.notify["selected"].connect (() => {
                doc.units = units[unit.selected];
                doc.notify_changed ();
                refresh ();
            });
            var mode = Forms.choice (d, _("Color Mode"), { _("RGB"), _("CMYK") }, doc.color_mode == "cmyk" ? 1 : 0);
            mode.notify["selected"].connect (() => {
                doc.begin (_("Document Color Mode"));
                doc.color_mode = mode.selected == 1 ? "cmyk" : "rgb";
                if (doc.color_mode == "cmyk") ColorConvert.document_to_cmyk (doc);
                doc.commit ();
                refresh ();
            });
            var grid = Forms.spin (d, _("Gridline Every"), 1, 10000, 1, doc.grid_size, 0, Units.label ("px"));
            grid.value_changed.connect (() => {
                doc.grid_size = grid.value;
                canvas.queue_draw ();
            });
            var sub = Forms.spin (d, _("Subdivisions"), 1, 64, 1, doc.grid_sub, 0);
            sub.value_changed.connect (() => {
                doc.grid_sub = (int) sub.value;
                canvas.queue_draw ();
            });
            append (d);
            var view = new PreferencesGroup (_("View"));
            add_view_switch (view, _("Show Grid"), canvas.show_grid, (v) => canvas.show_grid = v);
            add_view_switch (view, _("Snap to Grid"), canvas.snap_grid, (v) => canvas.snap_grid = v);
            add_view_switch (view, _("Snap to Pixel"), canvas.snap_pixel, (v) => canvas.snap_pixel = v);
            add_view_switch (view, _("Smart Guides"), canvas.smart_guides, (v) => canvas.smart_guides = v);
            add_view_switch (view, _("Snap to Points"), canvas.snap_points, (v) => canvas.snap_points = v);
            add_view_switch (view, _("Rulers"), canvas.show_rulers, (v) => canvas.show_rulers = v);
            add_view_switch (view, _("Outline Mode"), canvas.outline_mode, (v) => canvas.outline_mode = v);
            add_view_switch (view, _("Proof Colors"), doc.proof, (v) => doc.proof = v);
            add_view_switch (view, _("Overprint Preview"), doc.overprint_preview, (v) => doc.overprint_preview = v);
            append (view);
            var fill_box = new PaintEditor (win, canvas.style.fill, false, _("New Object Fill"));
            fill_box.changed.connect ((p) => {
                canvas.style.fill = p;
                win.fill_stroke.queue_draw ();
            });
            append (fill_box);
            var stroke_box = new PaintEditor (win, canvas.style.stroke, true, _("New Object Stroke"));
            stroke_box.changed.connect ((p) => {
                canvas.style.stroke = p;
                win.fill_stroke.queue_draw ();
            });
            var width_row = new SpinRow (_("Weight"), null, 0, 1000, 0.5, canvas.style.width);
            width_row.spin_btn.digits = 2;
            width_row.spin_btn.width_chars = 6;
            width_row.spin_btn.value_changed.connect (() => canvas.style.width = width_row.spin_btn.value);
            stroke_box.add_extra (width_row);
            append (stroke_box);
            if (focus_stroke) Idle.add (() => {
                focus_group (stroke_box);
                return Source.REMOVE;
            });
            else if (focus_paint_requested) Idle.add (() => {
                focus_group (fill_box);
                return Source.REMOVE;
            });
            focus_paint_requested = false;
        }

        private bool focus_paint_requested = false;

        private void focus_group (Widget w) {
            var scroll = get_ancestor (typeof (ScrolledWindow)) as ScrolledWindow;
            if (scroll == null) return;
            Graphene.Point p;
            if (w.compute_point (this, Graphene.Point () { x = 0, y = 0 }, out p)) scroll.vadjustment.value = double.max (0, p.y - 8);
        }

        public delegate void BoolSet (bool v);

        private void add_view_switch (PreferencesGroup g, string title, bool value, owned BoolSet set) {
            var s = Forms.toggle (g, title, value);
            s.notify["active"].connect (() => {
                set (s.active);
                canvas.queue_draw ();
            });
        }

        private void build_transform () {
            var g = new PreferencesGroup (_("Transform"));
            var b = canvas.selection_bounds ();
            if (b.w < 0) return;
            double f = Units.factor (doc.units);
            g.description = _("Lengths in %s, angles in degrees. Rotate and Shear apply when you press Enter.").printf (Units.label (doc.units));
            var x = Forms.spin (g, _("X"), -100000, 100000, 1, b.x / f, 2, Units.label (doc.units));
            var y = Forms.spin (g, _("Y"), -100000, 100000, 1, b.y / f, 2, Units.label (doc.units));
            var w = Forms.spin (g, _("Width"), 0.001, 100000, 1, b.w / f, 2, Units.label (doc.units));
            var h = Forms.spin (g, _("Height"), 0.001, 100000, 1, b.h / f, 2, Units.label (doc.units));
            var lock = Forms.toggle (g, _("Constrain Proportions"), false);
            var rot = Forms.spin (g, _("Rotate"), -360, 360, 1, 0, 1);
            var shear = Forms.spin (g, _("Shear"), -89, 89, 1, 0, 1);
            x.value_changed.connect (() => {
                if (building) return;
                Commands.transform (canvas, Transforms.translate (x.value * f - canvas.selection_bounds ().x, 0), _("Move"));
            });
            y.value_changed.connect (() => {
                if (building) return;
                Commands.transform (canvas, Transforms.translate (0, y.value * f - canvas.selection_bounds ().y), _("Move"));
            });
            w.value_changed.connect (() => {
                if (building) return;
                var cb = canvas.selection_bounds ();
                double sx = w.value * f / cb.w;
                double sy = lock.active ? sx : 1;
                Commands.transform (canvas, Transforms.scale (sx, sy, Point (cb.x, cb.y)), _("Scale"));
                if (lock.active) {
                    building = true;
                    h.value = canvas.selection_bounds ().h / f;
                    building = false;
                }
            });
            h.value_changed.connect (() => {
                if (building) return;
                var cb = canvas.selection_bounds ();
                double sy = h.value * f / cb.h;
                double sx = lock.active ? sy : 1;
                Commands.transform (canvas, Transforms.scale (sx, sy, Point (cb.x, cb.y)), _("Scale"));
                if (lock.active) {
                    building = true;
                    w.value = canvas.selection_bounds ().w / f;
                    building = false;
                }
            });
            rot.activate.connect (() => {
                Commands.rotate (canvas, rot.value);
                rot.value = 0;
            });
            shear.activate.connect (() => {
                var cb = canvas.selection_bounds ();
                Commands.transform (canvas, Transforms.shear (shear.value, true, Point (cb.cx (), cb.cy ())), _("Shear"));
                shear.value = 0;
            });
            var flip = new ActionRow (_("Flip"));
            flip.add_suffix (Forms.pill (_("Horizontal"), () => Commands.flip (canvas, true)));
            flip.add_suffix (Forms.pill (_("Vertical"), () => Commands.flip (canvas, false)));
            g.add_row (flip);
            append (g);
        }

        private void build_specific (Node n) {
            var pn = n as PathNode;
            if (pn != null && pn.live != null) build_live (pn);
            if (pn != null && pn.live == null && PathOps.anchors (pn.path).size > 1) build_corners (pn);
            var tn = n as TextNode;
            if (tn != null) build_text (tn);
            var bl = n as BlendNode;
            if (bl != null) build_blend (bl);
            var rp = n as RepeatNode;
            if (rp != null) build_repeat (rp);
            var ev = n as EnvelopeNode;
            if (ev != null) build_envelope (ev);
            var ch = n as ChartNode;
            if (ch != null) build_chart (ch);
            var s3 = n as Shape3DNode;
            if (s3 != null) build_3d (s3);
            var im = n as ImageNode;
            if (im != null) build_image (im);
            var sy = n as SymbolNode;
            if (sy != null) build_symbol (sy);
            var me = n as MeshNode;
            if (me != null) build_mesh (me);
            var g = n as GroupNode;
            if (g != null && g.clip) {
                var cg = new PreferencesGroup (_("Clipping Mask"));
                var row = new ActionRow (_("Clip Group"), _("The first object clips the rest."));
                row.add_suffix (Forms.text_button (_("Release"), () => Commands.clipping_mask (canvas, false)));
                cg.add_row (row);
                append (cg);
            }
            if (n.mask != null) {
                var mg = new PreferencesGroup (_("Opacity Mask"));
                var clip = Forms.toggle (mg, _("Clip"), n.mask_clip, _("Hide the artwork outside the mask"));
                clip.notify["active"].connect (() => {
                    doc.begin (_("Opacity Mask"));
                    n.mask_clip = clip.active;
                    doc.commit ();
                });
                var inv = Forms.toggle (mg, _("Invert Mask"), n.mask_invert);
                inv.notify["active"].connect (() => {
                    doc.begin (_("Opacity Mask"));
                    n.mask_invert = inv.active;
                    doc.commit ();
                });
                var row = new ActionRow (_("Mask Artwork"));
                row.add_suffix (Forms.text_button (_("Release"), () => Commands.opacity_mask (canvas, false)));
                mg.add_row (row);
                append (mg);
            }
        }

        private void build_live (PathNode pn) {
            var live = pn.live;
            var g = new PreferencesGroup (pn.kind_label ());
            double f = Units.factor (doc.units);
            if (live.kind == "line") {
                var len = Forms.spin (g, _("Length"), 0, 100000, 1, Math.hypot (live.x2 - live.cx, live.y2 - live.cy) / f, 2, Units.label (doc.units));
                var ang = Forms.spin (g, _("Angle"), -360, 360, 1, Math.atan2 (-(live.y2 - live.cy), live.x2 - live.cx) * 180 / Math.PI, 1);
                len.value_changed.connect (() => update_line (pn, len.value * f, ang.value));
                ang.value_changed.connect (() => update_line (pn, len.value * f, ang.value));
                append (g);
                return;
            }
            var w = Forms.spin (g, _("Width"), 0.01, 100000, 1, live.w / f, 2, Units.label (doc.units));
            var h = Forms.spin (g, _("Height"), 0.01, 100000, 1, live.h / f, 2, Units.label (doc.units));
            var ang = Forms.spin (g, _("Angle"), -360, 360, 1, live.angle * 180 / Math.PI, 1);
            SpinButton? radius = null, sides = null, inner = null;
            if (live.kind != "ellipse") radius = Forms.spin (g, _("Corner Radius"), 0, 100000, 1, live.radius / f, 2, Units.label (doc.units));
            if (live.kind == "polygon" || live.kind == "star") sides = Forms.spin (g, live.kind == "star" ? _("Points") : _("Sides"), 3, 100, 1, live.sides, 0);
            if (live.kind == "star") inner = Forms.spin (g, _("Inner Radius"), 1, 99, 1, live.inner * 100, 0, _("percent"));
            SpinButton[] all = { w, h, ang };
            if (radius != null) all += radius;
            if (sides != null) all += sides;
            if (inner != null) all += inner;
            foreach (var s in all) {
                s.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Shape Options"));
                    live.w = w.value * f;
                    live.h = h.value * f;
                    live.angle = ang.value * Math.PI / 180;
                    if (radius != null) live.radius = radius.value * f;
                    if (sides != null) live.sides = (int) sides.value;
                    if (inner != null) live.inner = inner.value / 100;
                    pn.rebuild_live ();
                    doc.commit ();
                });
            }
            Forms.action (g, _("Live Shape"), _("Expand to edit its points."), _("Expand"), () => {
                doc.begin (_("Expand Shape"));
                pn.live = null;
                doc.commit ();
                refresh ();
            });
            append (g);
        }

        private void update_line (PathNode pn, double len, double angle_deg) {
            if (building) return;
            doc.begin (_("Line Options"));
            double a = -angle_deg * Math.PI / 180;
            pn.live.x2 = pn.live.cx + Math.cos (a) * len;
            pn.live.y2 = pn.live.cy + Math.sin (a) * len;
            pn.rebuild_live ();
            doc.commit ();
        }

        private void build_corners (PathNode pn) {
            var g = new PreferencesGroup (_("Corners"));
            double cur = 0;
            int kind = 0;
            var sel = canvas.anchors.has_key (pn) ? canvas.anchors[pn] : null;
            foreach (var e in pn.corners.entries) {
                if (sel == null || sel.contains (e.key)) {
                    cur = e.value;
                    if (pn.corner_kinds.has_key (e.key)) kind = pn.corner_kinds[e.key];
                }
            }
            var r = Forms.spin (g, sel != null && sel.size > 0 ? _("Selected Corner Radius") : _("Corner Radius"), 0, 10000, 1, cur, 1);
            var k = Forms.choice (g, _("Corner Type"), { _("Round"), _("Inverted Round"), _("Chamfer") }, kind);
            r.value_changed.connect (() => apply_corners (pn, r.value, (int) k.selected));
            k.notify["selected"].connect (() => apply_corners (pn, r.value, (int) k.selected));
            append (g);
        }

        private void apply_corners (PathNode pn, double radius, int kind) {
            if (building) return;
            doc.begin (_("Live Corners"));
            var sel = canvas.anchors.has_key (pn) ? canvas.anchors[pn] : null;
            foreach (int a in PathOps.anchors (pn.path)) {
                if (sel != null && sel.size > 0 && !sel.contains (a)) continue;
                if (radius <= 0) {
                    pn.corners.unset (a);
                    pn.corner_kinds.unset (a);
                } else {
                    pn.corners[a] = radius;
                    pn.corner_kinds[a] = kind;
                }
            }
            doc.commit ();
        }

        private void build_text (TextNode tn) {
            var g = new PreferencesGroup (_("Character"));
            var fam = new ActionRow (_("Font"));
            var fb = new FontDialogButton (new FontDialog ());
            var desc = Pango.FontDescription.from_string (tn.style.family);
            fb.font_desc = desc;
            fb.level = FontLevel.FAMILY;
            fb.use_size = false;
            fb.valign = Align.CENTER;
            fb.notify["font-desc"].connect (() => {
                if (building || fb.font_desc == null) return;
                apply_char ((s) => s.family = fb.font_desc.get_family ());
            });
            fam.add_suffix (fb);
            g.add_row (fam);
            var size = Forms.spin (g, _("Size"), 1, 2000, 1, tn.style.size, 1, _("px"));
            size.value_changed.connect (() => apply_char ((s) => s.size = size.value));
            string[] weights = { "100", "200", "300", "400", "500", "600", "700", "800", "900" };
            var weight = Forms.choice (g, _("Weight"), { _("Thin"), _("Extra Light"), _("Light"), _("Regular"), _("Medium"), _("Semibold"), _("Bold"), _("Extra Bold"), _("Black") }, (tn.style.weight / 100 - 1).clamp (0, 8));
            weight.notify["selected"].connect (() => apply_char ((s) => s.weight = int.parse (weights[weight.selected])));
            var italic = Forms.toggle (g, _("Italic"), tn.style.italic);
            italic.notify["active"].connect (() => apply_char ((s) => s.italic = italic.active));
            var tracking = Forms.spin (g, _("Tracking (1/1000 em)"), -500, 2000, 5, tn.style.tracking, 0);
            tracking.value_changed.connect (() => apply_char ((s) => s.tracking = tracking.value));
            var leading = Forms.spin (g, _("Leading (0 = Auto)"), 0, 2000, 1, tn.style.leading, 1);
            leading.value_changed.connect (() => apply_char ((s) => s.leading = leading.value));
            var baseline = Forms.spin (g, _("Baseline Shift"), -500, 500, 1, tn.style.baseline, 1);
            baseline.value_changed.connect (() => apply_char ((s) => s.baseline = baseline.value));
            var hscale = Forms.spin (g, _("Horizontal Scale"), 1, 1000, 1, tn.style.hscale * 100, 0, _("percent"));
            hscale.value_changed.connect (() => apply_char ((s) => s.hscale = hscale.value / 100));
            var vscale = Forms.spin (g, _("Vertical Scale"), 1, 1000, 1, tn.style.vscale * 100, 0, _("percent"));
            vscale.value_changed.connect (() => apply_char ((s) => s.vscale = vscale.value / 100));
            var caps = Forms.choice (g, _("Capitals"), { _("Normal"), _("Small Caps"), _("All Caps") }, tn.style.caps == "small" ? 1 : (tn.style.caps == "all" ? 2 : 0));
            caps.notify["selected"].connect (() => apply_char ((s) => s.caps = caps.selected == 1 ? "small" : (caps.selected == 2 ? "all" : "none")));
            var under = Forms.toggle (g, _("Underline"), tn.style.underline);
            under.notify["active"].connect (() => apply_char ((s) => s.underline = under.active));
            var strike = Forms.toggle (g, _("Strikethrough"), tn.style.strike);
            strike.notify["active"].connect (() => apply_char ((s) => s.strike = strike.active));
            append (g);
            var ot = new PreferencesGroup (_("OpenType"));
            string[,] feats = { { "liga", _("Standard Ligatures") }, { "dlig", _("Discretionary Ligatures") }, { "swsh", _("Swashes") }, { "onum", _("Oldstyle Figures") }, { "tnum", _("Tabular Figures") }, { "frac", _("Fractions") }, { "ordn", _("Ordinals") }, { "zero", _("Slashed Zero") } };
            for (int i = 0; i < feats.length[0]; i++) {
                string tag = feats[i, 0];
                bool on = feature_on (tn.style.features, tag, tag == "liga");
                var sw = Forms.toggle (ot, feats[i, 1], on);
                sw.notify["active"].connect (() => apply_char ((s) => s.features = set_feature (s.features, tag, sw.active, tag == "liga")));
            }
            append (ot);
            var p = new PreferencesGroup (_("Paragraph"));
            string[] aligns = { "left", "center", "right", "justify" };
            int ai = 0;
            for (int i = 0; i < 4; i++) if (aligns[i] == tn.para.align) ai = i;
            var align = Forms.choice (p, _("Alignment"), { _("Left"), _("Center"), _("Right"), _("Justify") }, ai);
            align.notify["selected"].connect (() => apply_para ((pa) => pa.align = aligns[align.selected]));
            var first = Forms.spin (p, _("First Line Indent"), -1000, 1000, 1, tn.para.indent_first, 1);
            first.value_changed.connect (() => apply_para ((pa) => pa.indent_first = first.value));
            var left = Forms.spin (p, _("Left Indent"), 0, 1000, 1, tn.para.indent_left, 1);
            left.value_changed.connect (() => apply_para ((pa) => pa.indent_left = left.value));
            var right = Forms.spin (p, _("Right Indent"), 0, 1000, 1, tn.para.indent_right, 1);
            right.value_changed.connect (() => apply_para ((pa) => pa.indent_right = right.value));
            var before = Forms.spin (p, _("Space Before"), 0, 1000, 1, tn.para.space_before, 1);
            before.value_changed.connect (() => apply_para ((pa) => pa.space_before = before.value));
            var after = Forms.spin (p, _("Space After"), 0, 1000, 1, tn.para.space_after, 1);
            after.value_changed.connect (() => apply_para ((pa) => pa.space_after = after.value));
            var hyph = Forms.toggle (p, _("Hyphenate"), tn.para.hyphenate);
            hyph.notify["active"].connect (() => apply_para ((pa) => pa.hyphenate = hyph.active));
            append (p);
            if (tn.mode == "area") {
                var a = new PreferencesGroup (_("Area Type"));
                var cols = Forms.spin (a, _("Columns"), 1, 20, 1, tn.columns, 0);
                var gutter = Forms.spin (a, _("Gutter"), 0, 1000, 1, tn.gutter, 1);
                var inset = Forms.spin (a, _("Inset Spacing"), 0, 1000, 1, tn.inset, 1);
                foreach (var s in new SpinButton[] { cols, gutter, inset }) s.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Area Type Options"));
                    tn.columns = (int) cols.value;
                    tn.gutter = gutter.value;
                    tn.inset = inset.value;
                    doc.commit ();
                });
                var info = TextLayout.frame_info (tn);
                if (info.overflow) a.add_row (new ActionRow (_("Overset Text"), _("Some text does not fit. Select another text area too and choose Type, Threaded Text, Create.")));
                append (a);
            }
            if (tn.mode == "path") {
                var a = new PreferencesGroup (_("Type on a Path"));
                var off = Forms.spin (a, _("Start Offset"), -10000, 10000, 1, tn.path_offset, 1);
                off.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Type on a Path Options"));
                    tn.path_offset = off.value;
                    doc.commit ();
                });
                var flip = Forms.toggle (a, _("Flip"), tn.path_flip);
                flip.notify["active"].connect (() => {
                    doc.begin (_("Flip Type"));
                    tn.path_flip = flip.active;
                    doc.commit ();
                });
                append (a);
            }
        }

        private static bool feature_on (string features, string tag, bool default_on) {
            foreach (var f in features.split (",")) {
                var kv = f.strip ().split ("=");
                if (kv[0] == tag) return kv.length < 2 || kv[1] != "0";
            }
            return default_on;
        }

        private static string set_feature (string features, string tag, bool on, bool default_on) {
            string[] out_list = {};
            foreach (var f in features.split (",")) {
                var t = f.strip ();
                if (t == "" || t.split ("=")[0] == tag) continue;
                out_list += t;
            }
            if (on != default_on) out_list += "%s=%d".printf (tag, on ? 1 : 0);
            return string.joinv (",", out_list);
        }

        public delegate void CharEdit (CharStyle s);
        public delegate void ParaEdit (ParaStyle p);

        private void apply_char (CharEdit edit) {
            if (building) return;
            if (win.text_editor != null && win.text_editor.has_range ()) {
                win.text_editor.apply_run ((s) => edit (s));
                return;
            }
            doc.begin (_("Character"));
            foreach (var n in canvas.selection) {
                var t = n as TextNode;
                if (t == null) continue;
                edit (t.style);
                foreach (var r in t.runs) edit (r.style);
            }
            doc.commit ();
            TextLayout.invalidate ();
        }

        private void apply_para (ParaEdit edit) {
            if (building) return;
            doc.begin (_("Paragraph"));
            foreach (var n in canvas.selection) {
                var t = n as TextNode;
                if (t != null) edit (t.para);
            }
            doc.commit ();
            TextLayout.invalidate ();
        }

        private void build_blend (BlendNode bl) {
            var g = new PreferencesGroup (_("Blend Options"));
            var spacing = Forms.choice (g, _("Spacing"), { _("Smooth Color"), _("Specified Steps"), _("Specified Distance") }, bl.spacing == "smooth" ? 0 : (bl.spacing == "steps" ? 1 : 2));
            var steps = Forms.spin (g, _("Steps"), 1, 1000, 1, bl.steps, 0);
            var dist = Forms.spin (g, _("Distance"), 0.5, 10000, 1, bl.distance, 1);
            var orient = Forms.toggle (g, _("Align to Path"), bl.align_spine);
            spacing.notify["selected"].connect (() => edit_blend (bl, spacing, steps, dist, orient));
            steps.value_changed.connect (() => edit_blend (bl, spacing, steps, dist, orient));
            dist.value_changed.connect (() => edit_blend (bl, spacing, steps, dist, orient));
            orient.notify["active"].connect (() => edit_blend (bl, spacing, steps, dist, orient));
            Forms.action (g, _("Spine"), _("Select the blend and a path to use as its spine."), _("Replace"), () => Commands.replace_spine (canvas));
            Forms.header_button (g, _("Expand"), () => Commands.expand (canvas));
            Forms.header_button (g, _("Release"), () => Commands.release_group_like (canvas));
            append (g);
        }

        private void edit_blend (BlendNode bl, DropDown spacing, SpinButton steps, SpinButton dist, Switch orient) {
            if (building) return;
            doc.begin (_("Blend Options"));
            bl.spacing = spacing.selected == 0 ? "smooth" : (spacing.selected == 1 ? "steps" : "distance");
            bl.steps = (int) steps.value;
            bl.distance = dist.value;
            bl.align_spine = orient.active;
            doc.commit ();
        }

        private void build_repeat (RepeatNode rp) {
            var g = new PreferencesGroup (rp.kind_label ());
            SpinButton[] spins = {};
            if (rp.mode == "radial") {
                var count = Forms.spin (g, _("Instances"), 1, 360, 1, rp.count, 0);
                var radius = Forms.spin (g, _("Radius"), 0, 100000, 1, rp.radius, 1);
                var start = Forms.spin (g, _("Start Angle"), -360, 360, 1, rp.start_angle, 0);
                spins = { count, radius, start };
                foreach (var s in spins) s.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Repeat Options"));
                    rp.count = (int) count.value;
                    rp.radius = radius.value;
                    rp.start_angle = start.value;
                    doc.commit ();
                });
            } else if (rp.mode == "grid") {
                var rows = Forms.spin (g, _("Rows"), 1, 200, 1, rp.rows, 0);
                var cols = Forms.spin (g, _("Columns"), 1, 200, 1, rp.cols, 0);
                var hs = Forms.spin (g, _("Horizontal Spacing"), -10000, 10000, 1, rp.hspace, 1);
                var vs = Forms.spin (g, _("Vertical Spacing"), -10000, 10000, 1, rp.vspace, 1);
                spins = { rows, cols, hs, vs };
                foreach (var s in spins) s.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Repeat Options"));
                    rp.rows = (int) rows.value;
                    rp.cols = (int) cols.value;
                    rp.hspace = hs.value;
                    rp.vspace = vs.value;
                    doc.commit ();
                });
            } else {
                var axis = Forms.spin (g, _("Axis Angle"), -360, 360, 1, rp.axis_angle, 0);
                var off = Forms.spin (g, _("Axis Distance"), -10000, 10000, 1, rp.axis_offset, 1);
                spins = { axis, off };
                foreach (var s in spins) s.value_changed.connect (() => {
                    if (building) return;
                    doc.begin (_("Repeat Options"));
                    rp.axis_angle = axis.value;
                    rp.axis_offset = off.value;
                    doc.commit ();
                });
            }
            Forms.header_button (g, _("Expand"), () => Commands.expand (canvas));
            Forms.header_button (g, _("Release"), () => Commands.release_group_like (canvas));
            append (g);
        }

        private void build_envelope (EnvelopeNode ev) {
            var g = new PreferencesGroup (_("Envelope"));
            if (ev.mode == "warp") {
                string[] labels = { _("Arc"), _("Arc Lower"), _("Arc Upper"), _("Arch"), _("Bulge"), _("Shell Lower"), _("Shell Upper"), _("Flag"), _("Wave"), _("Fish"), _("Rise"), _("Fisheye"), _("Inflate"), _("Squeeze"), _("Twist") };
                var style = Forms.choice (g, _("Style"), labels, (int) WarpStyle.from_id (ev.style));
                var bend = Forms.spin (g, _("Bend"), -100, 100, 1, ev.bend * 100, 0, _("percent"));
                var hd = Forms.spin (g, _("Horizontal Distortion"), -100, 100, 1, ev.hdist * 100, 0, _("percent"));
                var vd = Forms.spin (g, _("Vertical Distortion"), -100, 100, 1, ev.vdist * 100, 0, _("percent"));
                var vertical = Forms.toggle (g, _("Vertical"), ev.vertical);
                style.notify["selected"].connect (() => edit_warp (ev, style, bend, hd, vd, vertical));
                foreach (var s in new SpinButton[] { bend, hd, vd }) s.value_changed.connect (() => edit_warp (ev, style, bend, hd, vd, vertical));
                vertical.notify["active"].connect (() => edit_warp (ev, style, bend, hd, vd, vertical));
            } else {
                g.add_row (new ActionRow (ev.mode == "mesh" ? _("Mesh Envelope") : _("Free Distort"), _("Drag the envelope points with the Direct Selection tool.")));
            }
            Forms.header_button (g, _("Expand"), () => Commands.expand (canvas));
            Forms.header_button (g, _("Release"), () => Commands.release_group_like (canvas));
            append (g);
        }

        private void edit_warp (EnvelopeNode ev, DropDown style, SpinButton bend, SpinButton hd, SpinButton vd, Switch vertical) {
            if (building) return;
            doc.begin (_("Warp Options"));
            ev.style = WarpStyle.ids ()[style.selected];
            ev.bend = bend.value / 100;
            ev.hdist = hd.value / 100;
            ev.vdist = vd.value / 100;
            ev.vertical = vertical.active;
            doc.commit ();
        }

        private void build_chart (ChartNode ch) {
            var g = new PreferencesGroup (_("Graph"));
            string[] kinds = { "bar", "stacked", "line", "area", "pie", "scatter" };
            int ki = 0;
            for (int i = 0; i < kinds.length; i++) if (kinds[i] == ch.chart) ki = i;
            var type = Forms.choice (g, _("Type"), { _("Column"), _("Stacked Column"), _("Line"), _("Area"), _("Pie"), _("Scatter") }, ki);
            type.notify["selected"].connect (() => {
                doc.begin (_("Graph Type"));
                ch.chart = kinds[type.selected];
                doc.commit ();
            });
            var legend = Forms.toggle (g, _("Legend"), ch.legend);
            legend.notify["active"].connect (() => {
                doc.begin (_("Graph Legend"));
                ch.legend = legend.active;
                doc.commit ();
            });
            Forms.action (g, _("Data"), null, _("Edit…"), () => Dialogs.chart_data (win, ch));
            Forms.header_button (g, _("Expand"), () => Commands.expand (canvas));
            append (g);
        }

        private void build_3d (Shape3DNode s3) {
            var g = new PreferencesGroup (s3.kind_label ());
            var depth = Forms.spin (g, s3.mode == "revolve" ? _("Angle") : _("Depth"), 0, 5000, 1, s3.mode == "revolve" ? s3.revolve_angle : s3.depth, 0);
            var rx = Forms.spin (g, _("Rotate X"), -180, 180, 1, s3.rx, 0);
            var ry = Forms.spin (g, _("Rotate Y"), -180, 180, 1, s3.ry, 0);
            var rz = Forms.spin (g, _("Rotate Z"), -180, 180, 1, s3.rz, 0);
            var persp = Forms.spin (g, _("Perspective"), 0, 160, 1, s3.perspective, 0);
            var light = Forms.spin (g, _("Light Intensity"), 0, 100, 1, s3.light * 100, 0);
            foreach (var s in new SpinButton[] { depth, rx, ry, rz, persp, light }) s.value_changed.connect (() => {
                if (building) return;
                doc.begin (_("3D Options"));
                if (s3.mode == "revolve") s3.revolve_angle = depth.value;
                else s3.depth = depth.value;
                s3.rx = rx.value;
                s3.ry = ry.value;
                s3.rz = rz.value;
                s3.perspective = persp.value;
                s3.light = light.value / 100;
                doc.commit ();
            });
            Forms.header_button (g, _("Expand"), () => Commands.expand (canvas));
            append (g);
        }

        private void build_image (ImageNode im) {
            var g = new PreferencesGroup (_("Image"));
            string state = im.link != "" ? (FileUtils.test (im.link, FileTest.EXISTS) ? _("Linked") : _("Missing link")) : _("Embedded");
            g.add_row (new ActionRow (state, im.link != "" ? im.link : "%d x %d px".printf (im.pixel_width, im.pixel_height)));
            if (im.link != "") {
                Forms.action (g, _("Reload Linked File"), null, _("Update"), () => {
                    Renderer.forget_image ("link:" + im.link);
                    doc.notify_changed ();
                });
                Forms.action (g, _("Link to Another File"), null, _("Relink…"), () => Dialogs.relink (win, im));
                Forms.action (g, _("Store in the Document"), null, _("Embed"), () => Commands.embed_images (canvas, true));
            }
            Forms.header_button (g, _("Trace…"), () => Dialogs.image_trace (win, im));
            append (g);
        }

        private void build_symbol (SymbolNode sy) {
            var def = doc.find_symbol (sy.symbol);
            var g = new PreferencesGroup (_("Symbol"));
            var info = new ActionRow (def != null ? def.name : _("Missing Symbol"), def != null && def.is_dynamic ? _("Dynamic symbol: colors can be changed per instance") : null);
            info.add_suffix (Forms.pill (_("Break Link"), () => Commands.break_symbol_link (canvas)));
            g.add_row (info);
            if (def != null) Forms.header_button (g, _("Edit…"), () => win.libraries.edit_symbol (def));
            if (def != null && def.is_dynamic) {
                foreach (var c in def.art.children) {
                    var f = c.first_fill ();
                    if (f == null || f.paint.kind != PaintKind.SOLID) continue;
                    string cid = c.id;
                    var ink = sy.overrides.has_key (cid) ? Ink.hex (sy.overrides[cid]) : f.paint.color;
                    var picker = Forms.color (g, c.display_name (), ink);
                    picker.color_changed.connect ((rgba) => {
                        doc.begin (_("Symbol Instance Color"));
                        sy.overrides[cid] = Forms.ink_of (rgba).to_hex ();
                        doc.commit ();
                    });
                }
            }
            append (g);
        }

        private void build_mesh (MeshNode me) {
            var g = new PreferencesGroup (_("Gradient Mesh"));
            var mt = canvas.tools["mesh"] as MeshTool;
            var v = mt != null ? mt.selected_vertex () : null;
            if (v != null) {
                var picker = Forms.color (g, _("Point Color"), v.color);
                picker.color_changed.connect ((rgba) => {
                    doc.begin (_("Mesh Color"));
                    v.color = Forms.ink_of (rgba);
                    doc.commit ();
                });
                var op = Forms.spin (g, _("Point Opacity"), 0, 100, 1, v.opacity * 100, 0);
                op.value_changed.connect (() => {
                    doc.begin (_("Mesh Opacity"));
                    v.opacity = op.value / 100;
                    doc.commit ();
                });
            } else {
                g.add_row (new ActionRow (_("%d x %d patches").printf (me.rows, me.cols), _("Click inside with the Mesh tool to add lines; click a point to color it.")));
            }
            append (g);
        }

        private void build_paint () {
            var n = canvas.selection[0];
            var fill_layer = n.first_fill ();
            var stroke_layer = n.first_stroke ();
            var fill = new PaintEditor (win, fill_layer != null ? fill_layer.paint : new Paint (), false);
            fill.changed.connect ((p) => {
                if (building) return;
                Commands.apply_paint (canvas, p, false);
                win.fill_stroke.queue_draw ();
            });
            append (fill);
            var stroke = new PaintEditor (win, stroke_layer != null ? stroke_layer.paint : new Paint (), true);
            stroke.changed.connect ((p) => {
                if (building) return;
                Commands.apply_paint (canvas, p, true);
                win.fill_stroke.queue_draw ();
            });
            append (stroke);
            if (focus_stroke) Idle.add (() => {
                focus_group (stroke);
                return Source.REMOVE;
            });
            else if (focus_paint_requested) Idle.add (() => {
                focus_group (fill);
                return Source.REMOVE;
            });
            focus_paint_requested = false;
            var s = new PreferencesGroup (_("Stroke Options"));
            var sl = stroke_layer ?? new PaintLayer.line (new Paint (), 1);
            var width = Forms.spin (s, _("Weight"), 0, 1000, 0.25, sl.width, 2, Units.label ("px"));
            width.value_changed.connect (() => edit_stroke ((l) => l.width = width.value));
            var cap = Forms.choice (s, _("Cap"), { _("Butt"), _("Round"), _("Projecting") }, (int) sl.cap);
            cap.notify["selected"].connect (() => edit_stroke ((l) => l.cap = (CapKind) cap.selected));
            var join = Forms.choice (s, _("Corner"), { _("Miter"), _("Round"), _("Bevel") }, (int) sl.join);
            join.notify["selected"].connect (() => edit_stroke ((l) => l.join = (JoinKind) join.selected));
            var miter = Forms.spin (s, _("Miter Limit"), 1, 500, 1, sl.miter, 0);
            miter.value_changed.connect (() => edit_stroke ((l) => l.miter = miter.value));
            var align = Forms.choice (s, _("Align Stroke"), { _("Center"), _("Inside"), _("Outside") }, (int) sl.align);
            align.notify["selected"].connect (() => edit_stroke ((l) => l.align = (StrokeAlign) align.selected));
            string dash_text = "";
            foreach (double d in sl.dashes) dash_text += (dash_text == "" ? "" : " ") + Units.format (d);
            var dash = Forms.entry (s, _("Dashes"), dash_text);
            dash.placeholder_text = _("for example 12 6");
            dash.activate.connect (() => edit_stroke ((l) => {
                double[] v = {};
                foreach (var part in dash.text.replace (",", " ").split (" ")) if (part.strip () != "") v += double.parse (part);
                l.dashes = v;
            }));
            string[] arrows = Arrows.ids ();
            int sa = 0, ea = 0;
            for (int i = 0; i < arrows.length; i++) {
                if (arrows[i] == sl.arrow_start) sa = i;
                if (arrows[i] == sl.arrow_end) ea = i;
            }
            var start = Forms.choice (s, _("Start Arrowhead"), Arrows.labels (), sa);
            start.notify["selected"].connect (() => edit_stroke ((l) => l.arrow_start = arrows[start.selected]));
            var end = Forms.choice (s, _("End Arrowhead"), Arrows.labels (), ea);
            end.notify["selected"].connect (() => edit_stroke ((l) => l.arrow_end = arrows[end.selected]));
            string[] profiles = { _("Uniform"), _("Taper Both Ends"), _("Taper Start"), _("Taper End"), _("Bulge"), _("Custom") };
            int pi = sl.profile.size == 0 ? 0 : 5;
            var profile = Forms.choice (s, _("Width Profile"), profiles, pi);
            profile.notify["selected"].connect (() => edit_stroke ((l) => {
                l.profile.clear ();
                switch (profile.selected) {
                    case 1:
                        l.profile.add (new WidthPoint (0, 0.05, 0.05));
                        l.profile.add (new WidthPoint (0.5, 1, 1));
                        l.profile.add (new WidthPoint (1, 0.05, 0.05));
                        break;
                    case 2:
                        l.profile.add (new WidthPoint (0, 0.05, 0.05));
                        l.profile.add (new WidthPoint (1, 1, 1));
                        break;
                    case 3:
                        l.profile.add (new WidthPoint (0, 1, 1));
                        l.profile.add (new WidthPoint (1, 0.05, 0.05));
                        break;
                    case 4:
                        l.profile.add (new WidthPoint (0, 0.4, 0.4));
                        l.profile.add (new WidthPoint (0.5, 1.4, 1.4));
                        l.profile.add (new WidthPoint (1, 0.4, 0.4));
                        break;
                }
            }));
            string[] brush_names = { _("None") };
            int bi = 0;
            for (int i = 0; i < doc.brushes.size; i++) {
                brush_names += doc.brushes[i].name;
                if (doc.brushes[i].id == sl.brush) bi = i + 1;
            }
            var brush = Forms.choice (s, _("Brush"), brush_names, bi);
            brush.notify["selected"].connect (() => edit_stroke ((l) => l.brush = brush.selected == 0 ? "" : doc.brushes[(int) brush.selected - 1].id));
            append (s);
        }

        public delegate void StrokeEdit (PaintLayer l);

        private void edit_stroke (StrokeEdit edit) {
            if (building) return;
            doc.begin (_("Stroke"));
            foreach (var n in canvas.selection) {
                var l = n.ensure_stroke ();
                if (!l.paint.visible ()) l.paint = canvas.style.stroke.visible () ? canvas.style.stroke.copy () : new Paint.hex ("#000000");
                edit (l);
            }
            doc.commit ();
        }

        private void build_opacity () {
            var n = canvas.selection[0];
            var g = new PreferencesGroup (_("Transparency"));
            var op = Forms.spin (g, _("Opacity"), 0, 100, 1, n.opacity * 100, 0, _("percent"));
            op.value_changed.connect (() => {
                if (building) return;
                doc.begin (_("Opacity"));
                foreach (var x in canvas.selection) x.opacity = op.value / 100;
                doc.commit ();
            });
            var blend = Forms.choice (g, _("Blending Mode"), BlendMode.labels (), (int) n.blend);
            blend.notify["selected"].connect (() => {
                if (building) return;
                doc.begin (_("Blending Mode"));
                foreach (var x in canvas.selection) x.blend = (BlendMode) blend.selected;
                doc.commit ();
            });
            var iso = Forms.toggle (g, _("Isolate Blending"), n.isolate);
            iso.notify["active"].connect (() => {
                doc.begin (_("Isolate Blending"));
                foreach (var x in canvas.selection) x.isolate = iso.active;
                doc.commit ();
            });
            var ko = Forms.toggle (g, _("Knockout Group"), n.knockout);
            ko.notify["active"].connect (() => {
                doc.begin (_("Knockout Group"));
                foreach (var x in canvas.selection) x.knockout = ko.active;
                doc.commit ();
            });
            if (canvas.selection.size >= 2) {
                Forms.action (g, _("Opacity Mask"), _("The top object masks the others."), _("Make"), () => Commands.opacity_mask (canvas, true));
            }
            append (g);
        }

        private string relative = "selection";

        private void build_align () {
            var g = new PreferencesGroup (_("Align"));
            var rel = Forms.choice (g, _("Align To"), { _("Selection"), _("Key Object"), _("Artboard") }, relative == "key" ? 1 : (relative == "artboard" ? 2 : 0));
            rel.notify["selected"].connect (() => relative = rel.selected == 1 ? "key" : (rel.selected == 2 ? "artboard" : "selection"));
            var hrow = new ActionRow (_("Horizontal"));
            hrow.add_suffix (Forms.flat_icon ("vector-align-left-symbolic", _("Align Left"), () => Commands.align (canvas, "left", relative)));
            hrow.add_suffix (Forms.flat_icon ("vector-align-center-symbolic", _("Align Horizontal Centers"), () => Commands.align (canvas, "hcenter", relative)));
            hrow.add_suffix (Forms.flat_icon ("vector-align-right-symbolic", _("Align Right"), () => Commands.align (canvas, "right", relative)));
            g.add_row (hrow);
            var vrow = new ActionRow (_("Vertical"));
            vrow.add_suffix (Forms.flat_icon ("vector-align-top-symbolic", _("Align Top"), () => Commands.align (canvas, "top", relative)));
            vrow.add_suffix (Forms.flat_icon ("vector-align-middle-symbolic", _("Align Vertical Centers"), () => Commands.align (canvas, "vcenter", relative)));
            vrow.add_suffix (Forms.flat_icon ("vector-align-bottom-symbolic", _("Align Bottom"), () => Commands.align (canvas, "bottom", relative)));
            g.add_row (vrow);
            var drow = new ActionRow (_("Distribute Centers"));
            drow.add_suffix (Forms.flat_icon ("vector-distribute-h-symbolic", _("Distribute Horizontally"), () => Commands.distribute (canvas, "h")));
            drow.add_suffix (Forms.flat_icon ("vector-distribute-v-symbolic", _("Distribute Vertically"), () => Commands.distribute (canvas, "v")));
            g.add_row (drow);
            var gap = Forms.spin (g, _("Spacing"), -10000, 10000, 1, 10, 1);
            var srow = new ActionRow (_("Distribute Spacing"));
            srow.add_suffix (Forms.flat_icon ("vector-distribute-h-symbolic", _("Space Horizontally"), () => Commands.distribute (canvas, "hspace", gap.value)));
            srow.add_suffix (Forms.flat_icon ("vector-distribute-v-symbolic", _("Space Vertically"), () => Commands.distribute (canvas, "vspace", gap.value)));
            g.add_row (srow);
            append (g);
        }

        private void build_pathfinder () {
            if (canvas.selection.size < 1) return;
            var g = new PreferencesGroup (_("Pathfinder"));
            string[] modes = { _("Unite"), _("Minus Front"), _("Intersect"), _("Exclude") };
            PathfinderOp[] mode_ops = { PathfinderOp.UNION, PathfinderOp.SUBTRACT, PathfinderOp.INTERSECT, PathfinderOp.EXCLUDE };
            Forms.menu_row (g, _("Shape Modes"), null, _("Apply"), (m) => {
                for (int i = 0; i < modes.length; i++) {
                    var op = mode_ops[i];
                    m.add_item (modes[i], null, () => Commands.pathfinder (canvas, op));
                }
            });
            string[] finders = { _("Divide"), _("Trim"), _("Merge"), _("Crop"), _("Outline"), _("Minus Back") };
            PathfinderOp[] finder_ops = { PathfinderOp.DIVIDE, PathfinderOp.TRIM, PathfinderOp.MERGE, PathfinderOp.CROP, PathfinderOp.OUTLINE, PathfinderOp.MINUS_BACK };
            Forms.menu_row (g, _("Pathfinders"), null, _("Apply"), (m) => {
                for (int i = 0; i < finders.length; i++) {
                    var op = finder_ops[i];
                    m.add_item (finders[i], null, () => Commands.pathfinder (canvas, op));
                }
            });
            append (g);
        }

        private void build_quick () {
            var g = new PreferencesGroup (_("Object"));
            string[,] objects = {
                { _("Group"), "group" }, { _("Ungroup"), "ungroup" }, { _("Make Clipping Mask"), "clip-make" }, { _("Make Compound Path"), "compound-make" },
                { _("Make Blend"), "blend-make" }, { _("Make Live Paint"), "live-paint-make" }, { _("New Symbol"), "symbol-new" }
            };
            string[,] paths = {
                { _("Offset Path…"), "path-offset" }, { _("Outline Stroke"), "path-outline-stroke" }, { _("Simplify…"), "path-simplify" },
                { _("Expand Appearance"), "expand-appearance" }, { _("Create Outlines"), "text-outlines" }
            };
            Forms.menu_row (g, _("Combine"), null, _("Choose"), (m) => {
                for (int i = 0; i < objects.length[0]; i++) {
                    string action = objects[i, 1];
                    m.add_item (objects[i, 0], null, () => win.activate_named (action));
                }
            });
            Forms.menu_row (g, _("Convert"), null, _("Choose"), (m) => {
                for (int i = 0; i < paths.length[0]; i++) {
                    string action = paths[i, 1];
                    m.add_item (paths[i, 0], null, () => win.activate_named (action));
                }
            });
            append (g);
        }
    }
}
