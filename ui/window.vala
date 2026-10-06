using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class VectorWindow : Singularity.Widgets.Window {
        public VectorApp app;
        private Stack content_stack;
        private AppSidebar sidebar;
        public VectorDocument? doc { get; private set; }
        public VectorCanvas? canvas { get; private set; }
        private Box canvas_host;
        private Overlay canvas_overlay;
        private ChipBar artboard_bar;
        private Label status;
        private InspectorPanel inspector;
        private ToggleButton layers_toggle;
        private ToggleButton inspector_toggle;
        public PropertiesPanel properties;
        public AppearancePanel appearance;
        public LibrariesPanel libraries;
        public LayerList layers;
        private Singularity.Widgets.ToolPalette tool_palette;
        private Gee.ArrayList<Widget> document_bubbles = new Gee.ArrayList<Widget> ();
        public VectorRibbon ribbon;
        public TextEditor? text_editor = null;
        private bool close_confirmed = false;
        private string[] artboard_ids = {};
        public Gee.HashMap<string, SimpleAction> actions = new Gee.HashMap<string, SimpleAction> ();
        public ActionRecorder recorder;
        public GLib.Settings? settings = null;

        public VectorWindow (VectorApp app) {
            Object (application: app);
            this.app = app;
            recorder = new ActionRecorder (this);
            set_default_size (1440, 900);
            set_title (_("Vector"));
            try {
                var source = SettingsSchemaSource.get_default ();
                if (source != null && source.lookup ("dev.sinty.vector", true) != null) settings = new GLib.Settings ("dev.sinty.vector");
            } catch (Error e) {
                settings = null;
            }
            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            content_stack.add_named (build_workspace (), "document");
            set_content (content_stack);
            sidebar = new AppSidebar (264);
            layers = new LayerList (this);
            sidebar.box.append (layers);
            set_sidebar (sidebar);
            set_sidebar_visible (false);
            build_bubbles ();
            WindowActions.install (this);
            ribbon.watch_actions ();
            close_request.connect (on_close_request);
            show_welcome ();
        }

        private Widget build_welcome () {
            var welcome = new WelcomePage ();
            welcome.app_icon_name = "dev.sinty.vector";
            welcome.title = _("Vector");
            welcome.subtitle = _("Illustrations, logos, icons and print graphics with precise paths");
            welcome.add_action ("x-office-drawing", _("New Illustration"), _("Start from an empty artboard"), () => new_document ());
            welcome.add_action ("folder-open", _("Open"), _("SVG, PDF, Illustrator files saved with PDF content, EPS, DXF and more"), () => choose_open ());
            return welcome;
        }

        private Widget build_workspace () {
            var workspace = new Box (Orientation.HORIZONTAL, 0);
            var center = new Box (Orientation.VERTICAL, 0);
            center.hexpand = true;
            center.vexpand = true;
            canvas_host = new Box (Orientation.VERTICAL, 0);
            canvas_host.hexpand = true;
            canvas_host.vexpand = true;
            ribbon = new VectorRibbon (this);
            apply_view_edge (ribbon);
            center.append (ribbon);
            canvas_overlay = new Overlay ();
            canvas_overlay.child = canvas_host;
            canvas_overlay.add_overlay (build_tools ());
            center.append (canvas_overlay);
            var bottom = new Box (Orientation.HORIZONTAL, 6);
            var add_board = Forms.icon_button ("list-add-symbolic", _("New Artboard"), () => activate_named ("artboard-new"));
            add_board.margin_start = 6;
            bottom.append (add_board);
            artboard_bar = new ChipBar ();
            artboard_bar.hexpand = true;
            artboard_bar.reorderable = true;
            artboard_bar.close_tooltip = _("Delete Artboard");
            artboard_bar.chip_activated.connect ((id) => {
                for (int i = 0; i < doc.artboards.size; i++) {
                    if (doc.artboards[i].id == id) {
                        doc.active_artboard = i;
                        canvas.fit_artboard ();
                        properties.refresh ();
                    }
                }
            });
            artboard_bar.chip_closed.connect ((id) => {
                if (doc.artboards.size <= 1) {
                    rebuild_artboards ();
                    return;
                }
                doc.begin (_("Delete Artboard"));
                for (int i = doc.artboards.size - 1; i >= 0; i--) if (doc.artboards[i].id == id) doc.artboards.remove_at (i);
                doc.active_artboard = 0;
                doc.commit ();
                doc.structure_changed ();
            });
            artboard_bar.chips_reordered.connect ((ids) => {
                doc.begin (_("Reorder Artboards"));
                var list = new Gee.ArrayList<Artboard> ();
                foreach (var id in ids) foreach (var a in doc.artboards) if (a.id == id) list.add (a);
                if (list.size == doc.artboards.size) {
                    doc.artboards.clear ();
                    doc.artboards.add_all (list);
                }
                doc.commit ();
            });
            artboard_bar.chip_renamed.connect ((id, label) => {
                doc.begin (_("Rename Artboard"));
                foreach (var a in doc.artboards) if (a.id == id) a.name = label;
                doc.commit ();
            });
            bottom.append (artboard_bar);
            status = new Label ("");
            status.add_css_class ("dim-label");
            status.margin_end = 12;
            status.xalign = 1;
            status.ellipsize = Pango.EllipsizeMode.START;
            status.width_chars = 12;
            bottom.append (status);
            center.append (bottom);
            workspace.append (center);
            properties = new PropertiesPanel (this);
            appearance = new AppearancePanel (this);
            libraries = new LibrariesPanel (this);
            inspector = new InspectorPanel (320);
            inspector.add_page ("properties", _("Properties"), properties);
            inspector.add_page ("appearance", _("Appearance"), appearance);
            inspector.add_page ("libraries", _("Libraries"), libraries);
            inspector.stack.notify["visible-child-name"].connect (() => {
                if (!inspector.visible) set_inspector_visible (true);
            });
            workspace.append (inspector);
            return workspace;
        }

        public Widget inspector_frame {
            get {
                return inspector;
            }
        }

        public void show_inspector_page (string name) {
            inspector.page = name;
            set_inspector_visible (true);
        }

        public void set_inspector_visible (bool visible) {
            inspector_frame.visible = visible;
            if (inspector_toggle != null && inspector_toggle.active != visible) inspector_toggle.active = visible;
        }

        public void set_layers_visible (bool visible) {
            set_sidebar_visible (visible);
            sync_layers_toggle ();
        }

        private void sync_layers_toggle () {
            if (layers_toggle != null && layers_toggle.active != get_sidebar_visible ()) layers_toggle.active = get_sidebar_visible ();
        }

        private Widget build_tools () {
            tool_palette = new Singularity.Widgets.ToolPalette ();
            tool_palette.valign = Align.START;
            tool_palette.margin_start = VectorCanvas.RULER + 10;
            tool_palette.margin_top = 8;
            foreach (var id in Tools.order ()) tool_palette.add_tool_id (id, "vector-%s-symbolic".printf (id == "paintbrush" ? "brush" : id), id);
            tool_palette.tool_selected.connect ((id) => {
                if (canvas != null && canvas.tool.id != id) canvas.set_tool (id);
            });
            fill_stroke = new FillStrokeWidget (this);
            fill_stroke.halign = Align.CENTER;
            fill_stroke.margin_bottom = 2;
            tool_palette.append_footer (fill_stroke);
            return tool_palette;
        }

        private void fit_tools (int height) {
            int avail = height - tool_palette.margin_top - VectorCanvas.RULER - 8 - 70;
            tool_palette.set_columns (tool_palette.rows_for (2) * 34 <= avail ? 2 : 3);
        }

        public FillStrokeWidget fill_stroke;

        private void update_tool_tooltips () {
            if (canvas == null) return;
            foreach (var id in Tools.order ()) {
                var t = canvas.tools[id];
                if (t == null) continue;
                string tip = t.label;
                if (t.shortcut != "") {
                    string key = t.shortcut;
                    bool shift = key.has_prefix ("shift+");
                    if (shift) key = key.substring (6);
                    key = key.replace ("backslash", "\\").replace ("asciitilde", "~").up ();
                    tip = "%s (%s%s)".printf (t.label, shift ? "Shift+" : "", key);
                }
                tool_palette.set_tooltip (id, tip, t.label);
            }
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Illustration (Ctrl+W)"), () => close_document ()));
            layers_toggle = new ToggleButton ();
            layers_toggle.icon_name = "sidebar-show-symbolic";
            layers_toggle.tooltip_text = _("Layers (F7)");
            layers_toggle.toggled.connect (() => {
                if (layers_toggle.active != get_sidebar_visible ()) set_sidebar_visible (layers_toggle.active);
            });
            add_bubble_widget (layers_toggle);
            track (layers_toggle);
            ribbon.attach (this);
            track (ribbon.tabs);
            track (add_bubble_icon ("document-save-symbolic", _("Save (Ctrl+S)"), () => save.begin (false)));
            inspector_toggle = new ToggleButton ();
            inspector_toggle.icon_name = "view-dual-symbolic";
            inspector_toggle.tooltip_text = _("Inspector (F4)");
            inspector_toggle.active = true;
            inspector_toggle.toggled.connect (() => {
                if (inspector_toggle.active != inspector_frame.visible) set_inspector_visible (inspector_toggle.active);
            });
            add_bubble_widget (inspector_toggle);
            track (inspector_toggle);
            track (add_bubble_suggested (_("Export"), () => activate_named ("export-screens")));
        }

        private Widget track (Widget w) {
            document_bubbles.add (w);
            return w;
        }

        public void activate_named (string name, Variant? param = null) {
            if (actions.has_key (name)) actions[name].activate (param);
        }

        private void show_welcome () {
            content_stack.visible_child_name = "welcome";
            foreach (var w in document_bubbles) w.visible = false;
            set_layers_visible (false);
            set_title (_("Vector"));
        }

        public void new_document () {
            if (doc != null && doc.modified) {
                confirm_discard (() => load_document (blank ()));
                return;
            }
            load_document (blank ());
        }

        private VectorDocument blank () {
            string preset = settings != null ? settings.get_string ("artboard-preset") : "screen";
            double w = 1920, h = 1080;
            switch (preset) {
                case "a4":
                    w = 210 * 96 / 25.4;
                    h = 297 * 96 / 25.4;
                    break;
                case "letter":
                    w = 816;
                    h = 1056;
                    break;
                case "icon":
                    w = h = 256;
                    break;
                case "square":
                    w = h = 1080;
                    break;
            }
            var d = VectorDocument.blank (w, h);
            if (settings != null) d.units = settings.get_string ("units");
            return d;
        }

        public void load_document (VectorDocument d) {
            if (text_editor != null) text_editor.finish ();
            if (doc != null) {
                doc.changed.disconnect (on_changed);
                doc.structure_changed.disconnect (on_structure);
                doc.history_changed.disconnect (update_history);
            }
            doc = d;
            TextLayout.invalidate ();
            Renderer.clear_images ();
            if (settings != null) doc.history_limit = settings.get_int ("history-limit");
            doc.changed.connect (on_changed);
            doc.structure_changed.connect (on_structure);
            doc.history_changed.connect (update_history);
            doc.notify["modified"].connect (update_title);
            Widget? child;
            while ((child = canvas_host.get_first_child ()) != null) canvas_host.remove (child);
            canvas = new VectorCanvas (doc);
            apply_settings ();
            canvas.selection_changed.connect (on_selection);
            canvas.tool_changed.connect (sync_tools);
            canvas.view_changed.connect (update_status);
            canvas.pointer_moved.connect (update_status);
            canvas.text_edit_requested.connect ((t, fresh) => edit_text (t, fresh));
            canvas.context_requested.connect (show_context_menu);
            canvas.key_command.connect ((name) => activate_named (name));
            foreach (var t in canvas.tools.values) {
                var shape = t as ShapeTool;
                if (shape != null) shape.exact_requested.connect ((kind, at) => Dialogs.shape_size (this, shape, at));
            }
            canvas.resize.connect ((cw, ch) => fit_tools (ch));
            canvas_host.append (canvas);
            update_tool_tooltips ();
            content_stack.visible_child_name = "document";
            foreach (var w in document_bubbles) w.visible = true;
            set_layers_visible (true);
            set_inspector_visible (true);
            on_structure ();
            on_selection ();
            update_history ();
            update_title ();
            sync_tools ();
            var current = canvas;
            Idle.add (() => {
                if (canvas != current) return Source.REMOVE;
                current.fit_artboard ();
                current.grab_focus ();
                return Source.REMOVE;
            });
        }

        public void apply_settings () {
            if (canvas == null || settings == null) return;
            canvas.show_grid = settings.get_boolean ("show-grid");
            canvas.snap_grid = settings.get_boolean ("snap-to-grid");
            canvas.snap_pixel = settings.get_boolean ("snap-to-pixel");
            canvas.smart_guides = settings.get_boolean ("smart-guides");
            canvas.snap_points = settings.get_boolean ("snap-to-point");
            canvas.show_rulers = settings.get_boolean ("show-rulers");
            canvas.scale_strokes = settings.get_boolean ("scale-strokes");
            canvas.nudge = settings.get_int ("keyboard-increment");
        }

        private void on_changed () {
            watch_links ();
            if (properties != null) properties.refresh_values ();
            if (appearance != null) appearance.refresh ();
            update_status ();
        }

        private Gee.HashMap<string, FileMonitor> link_monitors = new Gee.HashMap<string, FileMonitor> ();

        public void watch_links () {
            if (doc == null) return;
            var wanted = new Gee.HashSet<string> ();
            foreach (var n in doc.all_nodes ()) {
                var im = n as ImageNode;
                if (im != null && im.link != "") wanted.add (im.link);
            }
            foreach (var key in link_monitors.keys.to_array ()) {
                if (!wanted.contains (key)) {
                    link_monitors[key].cancel ();
                    link_monitors.unset (key);
                }
            }
            foreach (var path in wanted) {
                if (link_monitors.has_key (path)) continue;
                try {
                    var mon = File.new_for_path (path).monitor_file (FileMonitorFlags.NONE, null);
                    string p = path;
                    mon.changed.connect ((f, other, ev) => {
                        if (ev != FileMonitorEvent.CHANGES_DONE_HINT && ev != FileMonitorEvent.CREATED && ev != FileMonitorEvent.DELETED) return;
                        Renderer.forget_image ("link:" + p);
                        if (ev != FileMonitorEvent.DELETED) refresh_link (p);
                        if (canvas != null) canvas.queue_draw ();
                        toast (ev == FileMonitorEvent.DELETED ? _("A linked image is missing: %s").printf (Path.get_basename (p)) : _("Linked image updated: %s").printf (Path.get_basename (p)));
                    });
                    link_monitors[path] = mon;
                } catch (Error e) {
                }
            }
        }

        private void refresh_link (string path) {
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                var pix = new Gdk.Pixbuf.from_file (path);
                foreach (var n in doc.all_nodes ()) {
                    var im = n as ImageNode;
                    if (im == null || im.link != path) continue;
                    if (pix.width != im.pixel_width || pix.height != im.pixel_height) {
                        double sx = im.pixel_width / (double) pix.width, sy = im.pixel_height / (double) pix.height;
                        im.matrix = Transforms.multiply (Cairo.Matrix (sx, 0, 0, sy, 0, 0), im.matrix);
                        im.pixel_width = pix.width;
                        im.pixel_height = pix.height;
                    }
                    im.asset = doc.store_asset (new Bytes (data), Formats.mime_for (path));
                    im.missing = false;
                }
            } catch (Error e) {
            }
        }

        private void on_structure () {
            watch_links ();
            rebuild_artboards ();
            layers.rebuild ();
            libraries.refresh ();
            properties.refresh ();
        }

        private void on_selection () {
            properties.refresh ();
            appearance.refresh ();
            layers.sync_selection ();
            fill_stroke.queue_draw ();
            update_status ();
        }

        private void update_history () {
            if (doc == null) return;
            ribbon.undo_item.button.sensitive = doc.can_undo ();
            ribbon.redo_item.button.sensitive = doc.can_redo ();
            ribbon.undo_item.tooltip = doc.can_undo () ? _("Undo %s").printf (doc.undo_label ()) : _("Undo");
            ribbon.redo_item.tooltip = doc.can_redo () ? _("Redo %s").printf (doc.redo_label ()) : _("Redo");
            if (actions.has_key ("undo")) actions["undo"].set_enabled (doc.can_undo ());
            if (actions.has_key ("redo")) actions["redo"].set_enabled (doc.can_redo ());
            layers.rebuild ();
        }

        private void sync_tools () {
            if (canvas == null) return;
            tool_palette.set_active (canvas.tool.id);
            properties.refresh ();
        }

        public void update_title () {
            if (doc == null) return;
            string name = doc.path != null ? Path.get_basename (doc.path) : doc.title;
            set_title ((doc.modified ? "• " : "") + name);
        }

        private void update_status () {
            if (canvas == null) return;
            double f = Units.factor (doc.units);
            string pos = "%s, %s %s".printf (Units.format (canvas.pointer.x / f), Units.format (canvas.pointer.y / f), Units.label (doc.units));
            string sel = "";
            if (canvas.selection.size == 1) sel = canvas.selection[0].display_name ();
            else if (canvas.selection.size > 1) sel = ngettext ("%d object", "%d objects", canvas.selection.size).printf (canvas.selection.size);
            status.label = "%s   %s   %d%%   %s".printf (sel, pos, (int) Math.round (canvas.zoom * 100), doc.color_mode == "cmyk" ? _("CMYK") : _("RGB"));
        }

        private void rebuild_artboards () {
            foreach (var id in artboard_ids) artboard_bar.remove_chip (id);
            artboard_ids = {};
            if (doc == null) return;
            foreach (var a in doc.artboards) {
                artboard_bar.add_chip (a.id, a.name);
                artboard_ids += a.id;
            }
            var cur = doc.current_artboard ();
            if (cur != null) artboard_bar.set_active (cur.id);
        }

        public void edit_text (TextNode t, bool fresh) {
            if (text_editor != null) text_editor.finish ();
            text_editor = new TextEditor (this, t, fresh);
            canvas_overlay.add_overlay (text_editor);
            text_editor.finished.connect (() => {
                canvas_overlay.remove_overlay (text_editor);
                text_editor = null;
                canvas.grab_focus ();
            });
            text_editor.focus_editor ();
        }

        private void show_context_menu (double x, double y) {
            var menu = new GLib.Menu ();
            var s1 = new GLib.Menu ();
            s1.append (_("Cut"), "win.cut");
            s1.append (_("Copy"), "win.copy");
            s1.append (_("Paste"), "win.paste");
            s1.append (_("Duplicate"), "win.duplicate");
            s1.append (_("Delete"), "win.delete");
            menu.append_section (null, s1);
            var s2 = new GLib.Menu ();
            s2.append (_("Group"), "win.group");
            s2.append (_("Ungroup"), "win.ungroup");
            s2.append (_("Make Clipping Mask"), "win.clip-make");
            s2.append (_("Release Clipping Mask"), "win.clip-release");
            menu.append_section (null, s2);
            var s3 = new GLib.Menu ();
            s3.append (_("Bring to Front"), "win.arrange-front");
            s3.append (_("Send to Back"), "win.arrange-back");
            s3.append (_("Lock"), "win.lock");
            s3.append (_("Hide"), "win.hide");
            menu.append_section (null, s3);
            var pop = new PopoverMenu.from_model (menu);
            pop.set_parent (canvas);
            pop.has_arrow = false;
            Gdk.Rectangle r = { (int) x, (int) y, 1, 1 };
            pop.pointing_to = r;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        public void choose_open () {
            var dialog = new FileDialog ();
            dialog.title = _("Open Illustration");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (Formats.open_filter ());
            dialog.filters = filters;
            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) open_file (file);
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) Forms.message (this, _("Could Not Open Illustration"), e.message);
                }
            });
        }

        public void open_file (File file) {
            if (doc != null && doc.modified) {
                confirm_discard (() => load_file (file));
                return;
            }
            load_file (file);
        }

        private void load_file (File file) {
            try {
                var path = file.get_path ();
                if (path == null) throw new IOError.NOT_SUPPORTED (_("Choose a local file."));
                var loaded = Formats.open (path);
                loaded.modified = false;
                loaded.clear_history ();
                if (Formats.is_native (path)) loaded.path = path;
                else loaded.title = Path.get_basename (path);
                load_document (loaded);
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (file.get_uri ());
            } catch (Error e) {
                Forms.message (this, _("Could Not Open Illustration"), e.message);
            }
        }

        public async bool save (bool save_as) {
            if (doc == null) return false;
            if (text_editor != null) text_editor.finish ();
            string? target = save_as ? null : doc.path;
            if (target == null) {
                var dialog = new FileDialog ();
                dialog.title = _("Save Illustration");
                dialog.initial_name = base_name () + ".svg";
                var filters = new GLib.ListStore (typeof (FileFilter));
                var f = new FileFilter ();
                f.name = _("Vector Illustration (SVG)");
                f.add_suffix ("svg");
                filters.append (f);
                var z = new FileFilter ();
                z.name = _("Compressed SVG");
                z.add_suffix ("svgz");
                filters.append (z);
                dialog.filters = filters;
                try {
                    var file = yield dialog.save (this, null);
                    if (file == null) return false;
                    target = file.get_path ();
                    if (!target.down ().has_suffix (".svg") && !target.down ().has_suffix (".svgz")) target += ".svg";
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) Forms.message (this, _("Could Not Save Illustration"), e.message);
                    return false;
                }
            }
            try {
                Formats.save_native (doc, target, settings != null ? settings.get_int ("svg-decimals") : 3);
                doc.path = target;
                doc.title = Path.get_basename (target);
                doc.modified = false;
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (File.new_for_path (target).get_uri ());
                add_toast (new Toast (_("Saved as %s").printf (Path.get_basename (target))));
                update_title ();
                return true;
            } catch (Error e) {
                Forms.message (this, _("Could Not Save Illustration"), e.message);
                return false;
            }
        }

        public string base_name () {
            string name = doc.path != null ? Path.get_basename (doc.path) : doc.title;
            int dot = name.last_index_of (".");
            return dot > 0 ? name.substring (0, dot) : name;
        }

        public delegate void Then ();

        public void confirm_discard (owned Then then) {
            var dlg = new ConfirmDialog (application, _("Save Changes?"), null, _("The illustration has unsaved changes."), _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.set_secondary (_("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) {
                    save.begin (false, (obj, res) => {
                        if (save.end (res)) then ();
                    });
                } else if (r == ConfirmDialog.Response.SECONDARY) {
                    then ();
                }
            });
            dlg.present ();
        }

        public void close_document () {
            if (doc == null) return;
            if (doc.modified) {
                confirm_discard (() => {
                    doc.modified = false;
                    close_document ();
                });
                return;
            }
            doc = null;
            canvas = null;
            Widget? child;
            while ((child = canvas_host.get_first_child ()) != null) canvas_host.remove (child);
            show_welcome ();
        }

        private bool on_close_request () {
            if (close_confirmed || doc == null || !doc.modified) return false;
            confirm_discard (() => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        public bool dark () {
            return canvas != null && canvas.dark;
        }

        public void toast (string text) {
            add_toast (new Toast (text));
        }
    }

    public class FillStrokeWidget : DrawingArea {
        private weak VectorWindow win;

        public FillStrokeWidget (VectorWindow win) {
            this.win = win;
            set_size_request (56, 52);
            set_draw_func (draw);
            var click = new GestureClick ();
            click.pressed.connect ((n, x, y) => {
                if (x > 44 && y < 16) {
                    win.activate_named ("swap-fill-stroke");
                    return;
                }
                bool stroke = x > 22 && y > 18;
                win.show_inspector_page ("properties");
                win.properties.focus_paint (stroke);
            });
            add_controller (click);
            tooltip_text = _("Fill and Stroke. Click the arrow to swap them.");
        }

        private Paint current (bool stroke) {
            var c = win.canvas;
            if (c == null) return new Paint ();
            if (c.selection.size > 0) {
                var l = stroke ? c.selection[0].first_stroke () : c.selection[0].first_fill ();
                return l != null ? l.paint : new Paint ();
            }
            return stroke ? c.style.stroke : c.style.fill;
        }

        private void swatch (Cairo.Context cr, Paint p, double x, double y, double s, bool stroke) {
            cr.save ();
            cr.rectangle (x, y, s, s);
            if (stroke) {
                cr.rectangle (x + s - 6, y + 6, -(s - 12), s - 12);
                cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            }
            if (p.kind == PaintKind.NONE) {
                cr.set_source_rgb (1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgb (0.85, 0.1, 0.1);
                cr.set_line_width (2);
                cr.move_to (x + s, y);
                cr.line_to (x, y + s);
                cr.stroke ();
            } else {
                if (p.kind == PaintKind.LINEAR || p.kind == PaintKind.RADIAL) {
                    var pat = new Cairo.Pattern.linear (x, y, x + s, y);
                    foreach (var st in p.gradient.stops) pat.add_color_stop_rgb (st.offset, st.color.r, st.color.g, st.color.b);
                    cr.set_source (pat);
                } else {
                    var c = p.representative ();
                    cr.set_source_rgb (c.r, c.g, c.b);
                }
                cr.fill ();
            }
            cr.restore ();
            cr.rectangle (x + 0.5, y + 0.5, s - 1, s - 1);
            var fg = get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.75);
            cr.set_line_width (1);
            cr.stroke ();
        }

        private void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            swatch (cr, current (true), 22, 18, 30, true);
            swatch (cr, current (false), 4, 2, 30, false);
            var arrow = get_color ();
            cr.set_source_rgba (arrow.red, arrow.green, arrow.blue, 0.9);
            cr.set_line_width (1.2);
            cr.move_to (44, 4);
            cr.curve_to (50, 4, 52, 6, 52, 12);
            cr.stroke ();
        }
    }
}
