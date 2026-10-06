using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class WindowActions {
        public delegate void Handler (VectorWindow w);

        private static void add (VectorWindow win, string name, owned Handler h, bool needs_doc = true) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => {
                if (needs_doc && win.doc == null) return;
                win.recorder.record (name);
                h (win);
                if (win.canvas != null) win.canvas.grab_focus ();
            });
            win.add_action (a);
            win.actions[name] = a;
        }

        public static void install (VectorWindow win) {
            add (win, "new-document", (w) => w.new_document (), false);
            add (win, "open", (w) => w.choose_open (), false);
            add (win, "save", (w) => w.save.begin (false));
            add (win, "save-as", (w) => w.save.begin (true));
            add (win, "close-document", (w) => w.close_document ());
            add (win, "export-svg", (w) => ExportDialogs.svg (w));
            add (win, "export-screens", (w) => ExportDialogs.screens (w));
            add (win, "export-pdf", (w) => ExportDialogs.pdf (w));
            add (win, "export-image", (w) => ExportDialogs.raster (w));
            add (win, "export-dxf", (w) => ExportDialogs.other (w, "dxf"));
            add (win, "export-eps", (w) => ExportDialogs.other (w, "eps"));
            add (win, "export-odg", (w) => ExportDialogs.other (w, "odg"));
            add (win, "print", (w) => ExportDialogs.print (w));
            add (win, "place-image", (w) => place_image (w, false));
            add (win, "place-linked-image", (w) => place_image (w, true));
            add (win, "undo", (w) => {
                if (w.text_editor != null) w.text_editor.finish ();
                w.doc.undo ();
            });
            add (win, "redo", (w) => w.doc.redo ());
            add (win, "cut", (w) => Commands.copy (w.canvas, true));
            add (win, "copy", (w) => Commands.copy (w.canvas, false));
            add (win, "paste", (w) => Commands.paste (w.canvas, "center"));
            add (win, "paste-front", (w) => Commands.paste (w.canvas, "front"));
            add (win, "paste-back", (w) => Commands.paste (w.canvas, "back"));
            add (win, "paste-in-place", (w) => Commands.paste (w.canvas, "place"));
            add (win, "duplicate", (w) => Commands.duplicate (w.canvas));
            add (win, "delete", (w) => {
                if (w.canvas.tool.key (Gdk.Key.Delete, 0)) return;
                Commands.delete_selection (w.canvas);
            });
            add (win, "select-all", (w) => Commands.select_all (w.canvas));
            add (win, "deselect", (w) => w.canvas.clear_selection ());
            add (win, "select-inverse", (w) => Commands.select_inverse (w.canvas));
            string[] same = { "fill", "stroke", "width", "opacity", "blend", "style", "symbol", "kind" };
            foreach (var s in same) {
                string what = s;
                add (win, "select-same-" + what, (w) => Commands.select_same (w.canvas, what));
            }
            add (win, "group", (w) => Commands.group (w.canvas));
            add (win, "ungroup", (w) => Commands.ungroup (w.canvas));
            add (win, "lock", (w) => Commands.set_locked (w.canvas, true));
            add (win, "unlock-all", (w) => Commands.set_locked (w.canvas, false));
            add (win, "hide", (w) => Commands.set_hidden (w.canvas, true));
            add (win, "show-all", (w) => Commands.set_hidden (w.canvas, false));
            foreach (var how in new string[] { "front", "forward", "backward", "back" }) {
                string h = how;
                add (win, "arrange-" + h, (w) => Commands.arrange (w.canvas, h));
            }
            foreach (var kind in new string[] { "move", "rotate", "scale", "reflect", "shear" }) {
                string k = kind;
                add (win, "transform-" + k, (w) => Dialogs.transform (w, k));
            }
            add (win, "transform-each", (w) => Dialogs.transform_each (w));
            add (win, "transform-again", (w) => w.recorder.repeat_last ());
            add (win, "flip-horizontal", (w) => Commands.flip (w.canvas, true));
            add (win, "flip-vertical", (w) => Commands.flip (w.canvas, false));
            add (win, "rotate-90", (w) => Commands.rotate (w.canvas, 90));
            foreach (var how in new string[] { "left", "hcenter", "right", "top", "vcenter", "bottom" }) {
                string h = how;
                add (win, "align-" + h, (w) => Commands.align (w.canvas, h, "selection"));
            }
            add (win, "distribute-h", (w) => Commands.distribute (w.canvas, "h"));
            add (win, "distribute-v", (w) => Commands.distribute (w.canvas, "v"));
            add (win, "expand", (w) => Commands.expand (w.canvas));
            add (win, "expand-appearance", (w) => Commands.expand_appearance (w.canvas));
            add (win, "path-join", (w) => Commands.join_paths (w.canvas));
            add (win, "path-average", (w) => Commands.average_points (w.canvas, true, true));
            add (win, "path-outline-stroke", (w) => Commands.outline_stroke (w.canvas));
            add (win, "path-offset", (w) => Dialogs.offset (w));
            add (win, "path-simplify", (w) => Dialogs.simplify (w));
            add (win, "path-add-anchors", (w) => Commands.add_anchor_points (w.canvas));
            add (win, "path-reverse", (w) => Commands.reverse_direction (w.canvas));
            add (win, "path-convert-anchor", (w) => {
                w.doc.begin (_("Convert Anchor Point"));
                foreach (var e in w.canvas.anchors.entries) foreach (int a in e.value) PathEdit.convert_anchor (e.key, a);
                w.doc.commit ();
            });
            add (win, "fill-evenodd", (w) => Commands.even_odd (w.canvas, true));
            add (win, "fill-nonzero", (w) => Commands.even_odd (w.canvas, false));
            add (win, "compound-make", (w) => Commands.compound (w.canvas, true));
            add (win, "compound-release", (w) => Commands.compound (w.canvas, false));
            add (win, "clip-make", (w) => Commands.clipping_mask (w.canvas, true));
            add (win, "clip-release", (w) => Commands.clipping_mask (w.canvas, false));
            add (win, "mask-make", (w) => Commands.opacity_mask (w.canvas, true));
            add (win, "mask-release", (w) => Commands.opacity_mask (w.canvas, false));
            add (win, "blend-make", (w) => Commands.make_blend (w.canvas));
            add (win, "blend-release", (w) => Commands.release_group_like (w.canvas));
            add (win, "blend-spine", (w) => Commands.replace_spine (w.canvas));
            add (win, "envelope-warp", (w) => Dialogs.envelope_warp (w));
            add (win, "envelope-mesh", (w) => Dialogs.envelope_mesh (w));
            add (win, "envelope-top", (w) => Commands.make_envelope (w.canvas, "object"));
            add (win, "envelope-distort", (w) => {
                Commands.make_envelope (w.canvas, "distort");
                w.canvas.set_tool ("direct");
            });
            add (win, "envelope-release", (w) => Commands.release_group_like (w.canvas));
            add (win, "live-paint-make", (w) => {
                Commands.make_live_paint (w.canvas);
                w.canvas.set_tool ("live-paint");
            });
            add (win, "repeat-radial", (w) => Commands.make_repeat (w.canvas, "radial"));
            add (win, "repeat-grid", (w) => Commands.make_repeat (w.canvas, "grid"));
            add (win, "repeat-mirror", (w) => Commands.make_repeat (w.canvas, "mirror"));
            add (win, "image-trace", (w) => {
                foreach (var n in w.canvas.selection) {
                    var im = n as ImageNode;
                    if (im != null) {
                        Dialogs.image_trace (w, im);
                        return;
                    }
                }
                w.toast (_("Select an image to trace."));
            });
            add (win, "image-embed", (w) => Commands.embed_images (w.canvas, true));
            add (win, "mesh-create", (w) => Dialogs.mesh_create (w));
            add (win, "3d-extrude", (w) => Commands.make_3d (w.canvas, "extrude"));
            add (win, "3d-revolve", (w) => Commands.make_3d (w.canvas, "revolve"));
            add (win, "graph-create", (w) => Dialogs.graph_create (w));
            add (win, "symbol-new", (w) => Commands.new_symbol (w.canvas, _("Symbol %d").printf (w.doc.symbols.size + 1)));
            add (win, "symbol-break", (w) => Commands.break_symbol_link (w.canvas));
            add (win, "pattern-make", (w) => {
                var p = Commands.new_pattern (w.canvas, _("Pattern %d").printf (w.doc.patterns.size + 1));
                if (p != null) Dialogs.pattern_options (w, p);
            });
            add (win, "recolor", (w) => Dialogs.recolor (w));
            add (win, "swap-fill-stroke", (w) => Commands.swap_fill_stroke (w.canvas));
            add (win, "fill-none", (w) => Commands.apply_paint (w.canvas, new Paint (), false));
            add (win, "stroke-none", (w) => Commands.apply_paint (w.canvas, new Paint (), true));
            add (win, "default-colors", (w) => {
                Commands.apply_paint (w.canvas, new Paint.hex ("#ffffff"), false);
                Commands.apply_paint (w.canvas, new Paint.hex ("#000000"), true);
            });
            add (win, "text-outlines", (w) => Commands.text_outlines (w.canvas));
            add (win, "text-thread", (w) => Commands.thread_text (w.canvas));
            add (win, "text-unthread", (w) => Commands.unthread_text (w.canvas));
            add (win, "artboard-new", (w) => {
                var d = w.doc;
                var cur = d.current_artboard ();
                d.begin (_("New Artboard"));
                double x = 0;
                foreach (var a in d.artboards) x = double.max (x, a.x + a.w);
                var a = new Artboard (_("Artboard %d").printf (d.artboards.size + 1), x + 60, cur != null ? cur.y : 0, cur != null ? cur.w : 800, cur != null ? cur.h : 600);
                d.add_artboard (a);
                d.active_artboard = d.artboards.size - 1;
                d.commit ();
                d.structure_changed ();
                w.canvas.fit_artboard ();
            });
            add (win, "artboard-duplicate", (w) => {
                var d = w.doc;
                var cur = d.current_artboard ();
                if (cur == null) return;
                d.begin (_("Duplicate Artboard"));
                double x = 0;
                foreach (var a in d.artboards) x = double.max (x, a.x + a.w);
                var copy = cur.copy ();
                copy.id = "";
                copy.name = _("%s Copy").printf (cur.name);
                copy.x = x + 60;
                d.add_artboard (copy);
                var m = Transforms.translate (copy.x - cur.x, copy.y - cur.y);
                var target = d.active_layer;
                foreach (var n in d.all_nodes ()) {
                    if (n.parent == null || !(n.parent.is_layer) || n.hidden) continue;
                    var b = n.geometric_bounds ();
                    if (b.w < 0 || !cur.rect ().contains (b.cx (), b.cy ())) continue;
                    var c = n.clone ();
                    Commands.clear_ids (c);
                    c.apply_transform (m, false);
                    n.parent.add (c);
                }
                d.active_artboard = d.artboards.size - 1;
                d.ensure_ids ();
                d.commit ();
                d.structure_changed ();
                w.canvas.fit_artboard ();
            });
            add (win, "artboard-delete", (w) => {
                var d = w.doc;
                if (d.artboards.size <= 1) return;
                d.begin (_("Delete Artboard"));
                d.artboards.remove_at (d.active_artboard.clamp (0, d.artboards.size - 1));
                d.active_artboard = 0;
                d.commit ();
                d.structure_changed ();
            });
            add (win, "artboard-fit", (w) => Commands.artboard_fit (w.canvas));
            add (win, "layer-new", (w) => {
                var d = w.doc;
                d.begin (_("New Layer"));
                var l = d.new_layer (_("Layer %d").printf (d.layers.size + 1));
                d.layers.add (l);
                d.active_layer = l;
                d.commit ();
                w.layers.rebuild ();
            });
            add (win, "layer-sublayer", (w) => {
                var d = w.doc;
                if (d.active_layer == null) return;
                d.begin (_("New Sublayer"));
                var l = d.new_layer (_("Sublayer %d").printf (d.active_layer.children.size + 1));
                d.active_layer.add (l);
                d.active_layer = l;
                d.ensure_ids ();
                d.commit ();
                w.layers.rebuild ();
            });
            add (win, "layer-delete", (w) => {
                var d = w.doc;
                var l = d.active_layer;
                if (l == null) return;
                if (l.parent == null && d.layers.size <= 1) return;
                d.begin (_("Delete Layer"));
                if (l.parent != null) l.parent.remove (l);
                else d.layers.remove (l);
                d.active_layer = d.layers.size > 0 ? d.layers[d.layers.size - 1] : null;
                d.commit ();
                w.canvas.clear_selection ();
                w.layers.rebuild ();
            });
            add (win, "zoom-in", (w) => w.canvas.zoom_at (w.canvas.to_doc (w.canvas.get_width () / 2.0, w.canvas.get_height () / 2.0), 1.25));
            add (win, "zoom-out", (w) => w.canvas.zoom_at (w.canvas.to_doc (w.canvas.get_width () / 2.0, w.canvas.get_height () / 2.0), 0.8));
            add (win, "zoom-fit", (w) => w.canvas.fit_artboard ());
            add (win, "zoom-all", (w) => w.canvas.fit_all ());
            add (win, "zoom-actual", (w) => w.canvas.set_zoom (1));
            add (win, "zoom-selection", (w) => {
                var b = w.canvas.selection_bounds (true);
                if (b.w > 0) w.canvas.fit_rect (b);
            });
            add (win, "view-outline", (w) => {
                w.canvas.outline_mode = !w.canvas.outline_mode;
                w.canvas.queue_draw ();
            });
            add (win, "view-proof", (w) => {
                w.doc.proof = !w.doc.proof;
                w.canvas.queue_draw ();
            });
            add (win, "view-overprint", (w) => {
                w.doc.overprint_preview = !w.doc.overprint_preview;
                w.canvas.queue_draw ();
            });
            add (win, "view-grid", (w) => {
                w.canvas.show_grid = !w.canvas.show_grid;
                w.canvas.queue_draw ();
            });
            add (win, "view-snap-grid", (w) => w.canvas.snap_grid = !w.canvas.snap_grid);
            add (win, "view-snap-pixel", (w) => {
                w.canvas.snap_pixel = !w.canvas.snap_pixel;
                w.canvas.queue_draw ();
            });
            add (win, "view-smart-guides", (w) => w.canvas.smart_guides = !w.canvas.smart_guides);
            add (win, "view-snap-points", (w) => w.canvas.snap_points = !w.canvas.snap_points);
            add (win, "view-rulers", (w) => {
                w.canvas.show_rulers = !w.canvas.show_rulers;
                w.canvas.queue_draw ();
            });
            add (win, "view-edges", (w) => {
                w.canvas.show_edges = !w.canvas.show_edges;
                w.canvas.queue_draw ();
            });
            add (win, "view-perspective", (w) => {
                w.doc.perspective.visible = !w.doc.perspective.visible;
                w.canvas.queue_draw ();
            });
            add (win, "view-perspective-1", (w) => perspective (w, 1));
            add (win, "view-perspective-2", (w) => perspective (w, 2));
            add (win, "view-perspective-3", (w) => perspective (w, 3));
            add (win, "guides-clear", (w) => {
                w.doc.begin (_("Clear Guides"));
                w.doc.guides.clear ();
                w.doc.commit ();
            });
            add (win, "guides-make", (w) => {
                w.doc.begin (_("Make Guides"));
                foreach (var n in w.canvas.selection) {
                    var b = n.geometric_bounds ();
                    w.doc.guides.add (new Guide (true, b.x));
                    w.doc.guides.add (new Guide (true, b.x + b.w));
                    w.doc.guides.add (new Guide (false, b.y));
                    w.doc.guides.add (new Guide (false, b.y + b.h));
                }
                w.doc.commit ();
            });
            add (win, "fullscreen", (w) => {
                if (w.fullscreened) w.unfullscreen ();
                else w.fullscreen ();
            });
            add (win, "toggle-layers", (w) => w.set_layers_visible (!w.get_sidebar_visible ()));
            add (win, "toggle-inspector", (w) => w.set_inspector_visible (!w.inspector_frame.visible));
            add (win, "panel-properties", (w) => w.show_inspector_page ("properties"));
            add (win, "panel-appearance", (w) => w.show_inspector_page ("appearance"));
            add (win, "panel-libraries", (w) => w.show_inspector_page ("libraries"));
            add (win, "document-setup", (w) => Dialogs.document_setup (w));
            add (win, "history", (w) => {
                Gtk.Box body;
                var dlg = Forms.form (w, _("History"), _("Close"), out body, () => {});
                var g = new Singularity.Widgets.PreferencesGroup (_("Undo Steps"));
                var labels = w.doc.history_labels ();
                for (int i = labels.length - 1; i >= 0 && i >= labels.length - 60; i--) {
                    int steps = labels.length - i;
                    var row = new Singularity.Widgets.ActionRow (labels[i], ngettext ("Undo %d step", "Undo %d steps", steps).printf (steps));
                    row.add_suffix (Forms.text_button (_("Go Back"), () => {
                        for (int k = 0; k < steps; k++) w.doc.undo ();
                        dlg.close_dialog ();
                    }));
                    g.add_row (row);
                }
                if (labels.length == 0) g.description = _("Nothing to undo yet.");
                body.append (g);
                dlg.present ();
            });
            add (win, "actions-record", (w) => w.recorder.start ());
            add (win, "actions-stop", (w) => w.recorder.stop ());
            add (win, "actions-panel", (w) => w.recorder.show_panel ());
            add (win, "plugins", (w) => Plugins.show (w));
            add (win, "vectorize", (w) => Vectorizer.run (w));
            foreach (var kind in AppearancePanel.effect_kinds ()) {
                string k = kind;
                add (win, "effect-" + k, (w) => {
                    if (w.canvas.selection.size == 0) return;
                    var e = AppearancePanel.default_effect (k);
                    w.doc.begin (e.label ());
                    foreach (var n in w.canvas.selection) n.effects.add (n == w.canvas.selection[0] ? e : e.copy ());
                    w.doc.commit ();
                    Dialogs.effect (w, w.canvas.selection[0], e);
                });
            }
            foreach (PathfinderOp op in new PathfinderOp[] { PathfinderOp.UNION, PathfinderOp.SUBTRACT, PathfinderOp.INTERSECT, PathfinderOp.EXCLUDE, PathfinderOp.DIVIDE, PathfinderOp.TRIM, PathfinderOp.MERGE, PathfinderOp.CROP, PathfinderOp.OUTLINE, PathfinderOp.MINUS_BACK }) {
                var o = op;
                string[] names = { "unite", "minus-front", "intersect", "exclude", "divide", "trim", "merge", "crop", "outline", "minus-back" };
                add (win, "pf-" + names[(int) o], (w) => Commands.pathfinder (w.canvas, o));
            }
            var tool = new SimpleAction.stateful ("tool", VariantType.STRING, new Variant.string ("select"));
            tool.activate.connect ((p) => {
                if (win.canvas == null || p == null) return;
                if (win.text_editor != null) return;
                win.canvas.set_tool (p.get_string ());
                tool.set_state (p);
            });
            win.add_action (tool);
        }

        private static void perspective (VectorWindow w, int points) {
            w.doc.perspective.points = points;
            w.doc.perspective.visible = true;
            w.canvas.set_tool ("perspective");
            w.canvas.queue_draw ();
        }

        private static void place_image (VectorWindow w, bool linked) {
            var dialog = new FileDialog ();
            dialog.title = linked ? _("Place Linked Image") : _("Place Image");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Images");
            foreach (var s in new string[] { "png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff" }) f.add_suffix (s);
            filters.append (f);
            dialog.filters = filters;
            dialog.open.begin (w, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null || file.get_path () == null) return;
                    place_file (w, file.get_path (), linked);
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) Forms.message (w, _("Could Not Place Image"), e.message);
                }
            });
        }

        public static ImageNode? place_file (VectorWindow w, string path, bool linked) throws Error {
            var pix = new Gdk.Pixbuf.from_file (path);
            uint8[] data;
            string mime = Formats.mime_for (path);
            if (mime == "image/tiff" || mime == "image/bmp") {
                pix.save_to_buffer (out data, "png");
                mime = "image/png";
            } else {
                FileUtils.get_data (path, out data);
            }
            var im = new ImageNode ();
            im.asset = w.doc.store_asset (new Bytes (data), mime);
            im.mime = mime;
            im.pixel_width = pix.width;
            im.pixel_height = pix.height;
            if (linked) im.link = path;
            var c = w.canvas;
            var center = c.to_doc (c.get_width () / 2.0, c.get_height () / 2.0);
            double scale = 1;
            var a = w.doc.current_artboard ();
            if (a != null && (pix.width > a.w || pix.height > a.h)) scale = double.min (a.w / pix.width, a.h / pix.height) * 0.8;
            im.matrix = Cairo.Matrix (scale, 0, 0, scale, center.x - pix.width * scale / 2, center.y - pix.height * scale / 2);
            w.doc.begin (linked ? _("Place Linked Image") : _("Place Image"));
            (c.isolation ?? w.doc.active_layer).add (im);
            w.doc.ensure_ids ();
            w.doc.commit ();
            c.select_only (im);
            return im;
        }
    }

    public class ActionRecorder : Object {
        private weak VectorWindow win;
        private RecordedAction? current = null;
        private string? last = null;
        private bool playing = false;
        private static string[] skip = { "undo", "redo", "actions-record", "actions-stop", "actions-panel", "save", "save-as", "open", "new-document", "close-document", "transform-again" };

        public ActionRecorder (VectorWindow win) {
            this.win = win;
        }

        public bool recording {
            get {
                return current != null;
            }
        }

        public void record (string name) {
            foreach (var s in skip) if (s == name) return;
            if (!playing && (name.has_prefix ("transform-") || name.has_prefix ("arrange-") || name.has_prefix ("align-") || name.has_prefix ("effect-") || name.has_prefix ("pf-") || name.has_prefix ("flip-") || name == "rotate-90" || name == "duplicate")) last = name;
            if (current != null && !playing) current.steps.add (name);
        }

        public void repeat_last () {
            if (last != null) win.activate_named (last);
        }

        public void start () {
            current = new RecordedAction ();
            current.name = _("Action %d").printf (win.doc.actions.size + 1);
            win.toast (_("Recording. Choose Stop Recording when done."));
        }

        public void stop () {
            if (current == null) return;
            if (current.steps.size > 0) {
                win.doc.actions.add (current);
                win.doc.notify_changed ();
                win.toast (ngettext ("Recorded %d step", "Recorded %d steps", current.steps.size).printf (current.steps.size));
            }
            current = null;
        }

        public void play (RecordedAction a) {
            playing = true;
            foreach (var step in a.steps) {
                if (step.has_prefix ("tool:")) {
                    win.canvas.set_tool (step.substring (5));
                    continue;
                }
                win.activate_named (step);
            }
            playing = false;
        }

        public void show_panel () {
            Gtk.Box body;
            var dlg = Forms.form (win, _("Actions"), _("Close"), out body, () => {});
            var g = new Singularity.Widgets.PreferencesGroup (_("Recorded Actions"));
            foreach (var a in win.doc.actions) {
                var act = a;
                var row = new Singularity.Widgets.ActionRow (a.name, string.joinv (", ", a.steps.to_array ()));
                row.add_suffix (Forms.text_button (_("Play"), () => play (act)));
                row.add_suffix (Forms.icon_button ("list-remove-symbolic", _("Delete"), () => {
                    win.doc.actions.remove (act);
                    win.doc.notify_changed ();
                    dlg.close_dialog ();
                }));
                g.add_row (row);
            }
            if (win.doc.actions.size == 0) g.description = _("Choose Record Action, apply commands from the menus, then Stop Recording.");
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            buttons.append (Forms.text_button (recording ? _("Stop Recording") : _("Record Action"), () => {
                if (recording) stop ();
                else start ();
                dlg.close_dialog ();
            }));
            g.add_row (buttons);
            body.append (g);
            dlg.present ();
        }
    }
}
