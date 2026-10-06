using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class VectorRibbon : ContextRibbon {
        private weak VectorWindow win;
        private bool syncing = false;
        private Gee.HashMap<string, RibbonToggle> view_toggles = new Gee.HashMap<string, RibbonToggle> ();
        public RibbonButton undo_item;
        public RibbonButton redo_item;

        public VectorRibbon (VectorWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("vector-ribbon");
            build_edit (add_context ("edit", _("Edit"), "edit-symbolic"));
            build_object (add_context ("object", _("Object"), "vector-select-symbolic"));
            build_path (add_context ("path", _("Path"), "vector-pen-symbolic"));
            build_insert (add_context ("insert", _("Insert"), "list-add-symbolic"));
            build_view (add_context ("view", _("View"), "view-reveal-symbolic"));
            context_changed.connect (() => sync ());
            map.connect (() => sync ());
        }

        private struct Entry {
            public string label;
            public string action;
        }

        private RibbonButton button (RibbonContext c, string? icon, string label, string action, bool with_label = false) {
            var b = c.add_button (icon, label, null, "win." + action);
            b.label_in_compact = with_label;
            return b;
        }

        private RibbonMenu menu (RibbonContext c, string? icon, string label, string tip, Entry[] entries, bool with_label = true) {
            var m = c.add_menu (icon, label, tip);
            m.label_in_compact = with_label;
            Entry[] copy = entries;
            m.set_builder ((menu) => {
                foreach (var e in copy) {
                    if (e.action == "") {
                        menu.add_separator ();
                        continue;
                    }
                    string name = e.action;
                    menu.add_item (e.label, null, () => win.activate_named (name));
                }
            });
            return m;
        }

        private void build_edit (RibbonContext c) {
            undo_item = button (c, "edit-undo-symbolic", _("Undo"), "undo");
            redo_item = button (c, "edit-redo-symbolic", _("Redo"), "redo");
            c.add_separator ();
            button (c, "edit-cut-symbolic", _("Cut"), "cut");
            button (c, "edit-copy-symbolic", _("Copy"), "copy");
            button (c, "edit-paste-symbolic", _("Paste"), "paste");
            menu (c, null, _("Paste Special"), _("Paste in front, in back or in place"), {
                { _("Paste in Front"), "paste-front" },
                { _("Paste in Back"), "paste-back" },
                { _("Paste in Place"), "paste-in-place" }
            });
            button (c, null, _("Duplicate"), "duplicate");
            button (c, "edit-delete-symbolic", _("Delete"), "delete");
            c.add_separator ();
            button (c, "edit-select-all-symbolic", _("Select All"), "select-all");
            button (c, "edit-clear-symbolic", _("Deselect"), "deselect");
            menu (c, "selection-mode-symbolic", _("Select"), _("Select by attribute"), {
                { _("Inverse"), "select-inverse" },
                { "", "" },
                { _("Same Fill Color"), "select-same-fill" },
                { _("Same Stroke Color"), "select-same-stroke" },
                { _("Same Stroke Weight"), "select-same-width" },
                { _("Same Opacity"), "select-same-opacity" },
                { _("Same Blending Mode"), "select-same-blend" },
                { _("Same Graphic Style"), "select-same-style" },
                { _("Same Symbol Instance"), "select-same-symbol" },
                { _("Same Object Type"), "select-same-kind" }
            });
            c.add_separator ();
            menu (c, "preferences-color-symbolic", _("Color"), _("Fill and stroke colors"), {
                { _("Recolor Artwork…"), "recolor" },
                { _("Swap Fill and Stroke"), "swap-fill-stroke" },
                { _("Default Fill and Stroke"), "default-colors" },
                { "", "" },
                { _("No Fill"), "fill-none" },
                { _("No Stroke"), "stroke-none" }
            });
            button (c, "document-open-recent-symbolic", _("History"), "history");
            menu (c, "media-record-symbolic", _("Actions"), _("Record and replay actions"), {
                { _("Record Action"), "actions-record" },
                { _("Stop Recording"), "actions-stop" },
                { _("Actions…"), "actions-panel" }
            });
            button (c, "extension-symbolic", _("Plugins"), "plugins");
        }

        private void build_object (RibbonContext c) {
            button (c, null, _("Group"), "group");
            button (c, null, _("Ungroup"), "ungroup");
            menu (c, null, _("Arrange"), _("Stacking order"), {
                { _("Bring to Front"), "arrange-front" },
                { _("Bring Forward"), "arrange-forward" },
                { _("Send Backward"), "arrange-backward" },
                { _("Send to Back"), "arrange-back" }
            });
            c.add_separator ();
            button (c, "vector-align-left-symbolic", _("Align Left"), "align-left");
            button (c, "vector-align-center-symbolic", _("Align Horizontal Centers"), "align-hcenter");
            button (c, "vector-align-right-symbolic", _("Align Right"), "align-right");
            button (c, "vector-align-top-symbolic", _("Align Top"), "align-top");
            button (c, "vector-align-middle-symbolic", _("Align Vertical Centers"), "align-vcenter");
            button (c, "vector-align-bottom-symbolic", _("Align Bottom"), "align-bottom");
            button (c, "vector-distribute-h-symbolic", _("Distribute Horizontally"), "distribute-h");
            button (c, "vector-distribute-v-symbolic", _("Distribute Vertically"), "distribute-v");
            c.add_separator ();
            menu (c, "vector-rotate-symbolic", _("Transform"), _("Move, rotate, reflect, scale or shear"), {
                { _("Transform Again"), "transform-again" },
                { "", "" },
                { _("Move…"), "transform-move" },
                { _("Rotate…"), "transform-rotate" },
                { _("Reflect…"), "transform-reflect" },
                { _("Scale…"), "transform-scale" },
                { _("Shear…"), "transform-shear" },
                { _("Transform Each…"), "transform-each" }
            });
            button (c, "vector-reflect-symbolic", _("Flip Horizontal"), "flip-horizontal");
            button (c, "vector-reflect-vertical-symbolic", _("Flip Vertical"), "flip-vertical");
            button (c, "object-rotate-right-symbolic", _("Rotate 90 Degrees"), "rotate-90");
            c.add_separator ();
            button (c, "changes-prevent-symbolic", _("Lock Selection"), "lock");
            button (c, "changes-allow-symbolic", _("Unlock All"), "unlock-all");
            button (c, "view-conceal-symbolic", _("Hide Selection"), "hide");
            button (c, "view-reveal-symbolic", _("Show All"), "show-all");
            c.add_separator ();
            menu (c, null, _("Expand"), _("Turn live objects and appearance into plain paths"), {
                { _("Expand"), "expand" },
                { _("Expand Appearance"), "expand-appearance" }
            });
            menu (c, "vector-artboard-symbolic", _("Artboards"), _("Artboards"), {
                { _("New Artboard"), "artboard-new" },
                { _("Duplicate Artboard"), "artboard-duplicate" },
                { _("Delete Artboard"), "artboard-delete" },
                { _("Fit to Artwork Bounds"), "artboard-fit" }
            });
        }

        private void build_path (RibbonContext c) {
            menu (c, "vector-shape-builder-symbolic", _("Pathfinder"), _("Combine shapes"), {
                { _("Unite"), "pf-unite" },
                { _("Minus Front"), "pf-minus-front" },
                { _("Intersect"), "pf-intersect" },
                { _("Exclude"), "pf-exclude" },
                { "", "" },
                { _("Divide"), "pf-divide" },
                { _("Trim"), "pf-trim" },
                { _("Merge"), "pf-merge" },
                { _("Crop"), "pf-crop" },
                { _("Outline"), "pf-outline" },
                { _("Minus Back"), "pf-minus-back" }
            });
            c.add_separator ();
            button (c, null, _("Join"), "path-join");
            button (c, null, _("Average"), "path-average");
            button (c, null, _("Outline Stroke"), "path-outline-stroke");
            button (c, null, _("Offset Path…"), "path-offset");
            button (c, null, _("Simplify…"), "path-simplify");
            menu (c, "vector-pen-symbolic", _("Anchors"), _("Anchor points and fill rule"), {
                { _("Add Anchor Points"), "path-add-anchors" },
                { _("Convert Anchor Points"), "path-convert-anchor" },
                { _("Reverse Path Direction"), "path-reverse" },
                { "", "" },
                { _("Even-Odd Fill Rule"), "fill-evenodd" },
                { _("Non-Zero Fill Rule"), "fill-nonzero" }
            });
            c.add_separator ();
            menu (c, null, _("Masks"), _("Clipping masks, opacity masks and compound paths"), {
                { _("Make Clipping Mask"), "clip-make" },
                { _("Release Clipping Mask"), "clip-release" },
                { _("Make Opacity Mask"), "mask-make" },
                { _("Release Opacity Mask"), "mask-release" },
                { "", "" },
                { _("Make Compound Path"), "compound-make" },
                { _("Release Compound Path"), "compound-release" }
            });
            menu (c, "vector-blend-symbolic", _("Blend"), _("Blends between objects"), {
                { _("Make Blend"), "blend-make" },
                { _("Release Blend"), "blend-release" },
                { _("Replace Spine"), "blend-spine" }
            });
            menu (c, "vector-envelope-symbolic", _("Envelope"), _("Distort with an envelope"), {
                { _("Envelope with Warp…"), "envelope-warp" },
                { _("Envelope with Mesh…"), "envelope-mesh" },
                { _("Envelope with Top Object"), "envelope-top" },
                { _("Free Distort Envelope"), "envelope-distort" },
                { _("Release Envelope"), "envelope-release" }
            });
            menu (c, "vector-repeat-symbolic", _("Repeat"), _("Repeat objects"), {
                { _("Radial Repeat"), "repeat-radial" },
                { _("Grid Repeat"), "repeat-grid" },
                { _("Mirror Repeat"), "repeat-mirror" }
            });
            menu (c, "vector-3d-symbolic", _("3D"), _("Extrude or revolve in 3D"), {
                { _("3D Extrude"), "3d-extrude" },
                { _("3D Revolve"), "3d-revolve" }
            });
            button (c, "vector-live-paint-symbolic", _("Make Live Paint"), "live-paint-make");
        }

        private void build_insert (RibbonContext c) {
            button (c, "image-x-generic-symbolic", _("Image"), "place-image", true);
            button (c, "insert-link-symbolic", _("Linked Image"), "place-linked-image");
            menu (c, null, _("Trace"), _("Turn images into paths"), {
                { _("Image Trace…"), "image-trace" },
                { _("Vectorize Image"), "vectorize" },
                { _("Embed Image"), "image-embed" }
            });
            c.add_separator ();
            menu (c, "vector-text-symbolic", _("Text"), _("Text areas and outlines"), {
                { _("Create Outlines"), "text-outlines" },
                { _("Thread Selected Text Areas"), "text-thread" },
                { _("Remove Threading"), "text-unthread" }
            });
            menu (c, null, _("Symbols"), _("Symbols and patterns"), {
                { _("New Symbol"), "symbol-new" },
                { _("Break Symbol Link"), "symbol-break" },
                { _("Make Pattern"), "pattern-make" }
            });
            button (c, "vector-mesh-symbolic", _("Gradient Mesh…"), "mesh-create");
            button (c, "vector-graph-symbolic", _("Graph…"), "graph-create");
            c.add_separator ();
            button (c, "list-add-symbolic", _("Layer"), "layer-new", true);
            button (c, null, _("Sublayer"), "layer-sublayer");
            button (c, "vector-artboard-symbolic", _("Artboard"), "artboard-new", true);
        }

        private void build_view (RibbonContext c) {
            button (c, "zoom-out-symbolic", _("Zoom Out"), "zoom-out");
            button (c, "zoom-in-symbolic", _("Zoom In"), "zoom-in");
            button (c, "zoom-fit-best-symbolic", _("Fit Artboard"), "zoom-fit");
            button (c, "zoom-original-symbolic", _("Actual Size"), "zoom-actual");
            menu (c, null, _("Zoom"), _("More zoom levels"), {
                { _("Fit All"), "zoom-all" },
                { _("Zoom to Selection"), "zoom-selection" }
            });
            c.add_separator ();
            toggle (c, "view-outline", null, _("Outline"));
            toggle (c, "view-proof", null, _("Proof Colors"));
            toggle (c, "view-overprint", null, _("Overprint"));
            c.add_separator ();
            toggle (c, "view-grid", "view-grid-symbolic", _("Grid"));
            toggle (c, "view-rulers", null, _("Rulers"));
            toggle (c, "view-edges", null, _("Edges"));
            toggle (c, "view-smart-guides", null, _("Smart Guides"));
            c.add_separator ();
            var snap = c.add_menu (null, _("Snap"), _("Snapping"));
            snap.label_in_compact = true;
            snap.set_builder ((m) => {
                snap_item (m, "view-snap-grid", _("Snap to Grid"));
                snap_item (m, "view-snap-pixel", _("Snap to Pixel"));
                snap_item (m, "view-snap-points", _("Snap to Point"));
            });
            c.add_separator ();
            toggle (c, "view-perspective", "vector-perspective-symbolic", _("Perspective Grid"));
            menu (c, null, _("Guides"), _("Guides and perspective presets"), {
                { _("Make Guides"), "guides-make" },
                { _("Clear Guides"), "guides-clear" },
                { "", "" },
                { _("One Point Perspective"), "view-perspective-1" },
                { _("Two Point Perspective"), "view-perspective-2" },
                { _("Three Point Perspective"), "view-perspective-3" }
            });
            c.add_separator ();
            button (c, "document-properties-symbolic", _("Document Setup"), "document-setup");
            button (c, "view-fullscreen-symbolic", _("Fullscreen"), "fullscreen");
        }

        private void snap_item (ContextMenu m, string action, string label) {
            bool on = state (action);
            m.add_item (label, on ? "object-select-symbolic" : null, () => {
                win.activate_named (action);
                if (win.properties != null) win.properties.refresh ();
            }, on ? "checked" : null);
        }

        private void toggle (RibbonContext c, string action, string? icon, string label) {
            var t = c.add_toggle (icon, label);
            t.label_in_compact = icon == null;
            t.shortcut = shortcut_for (action);
            t.toggled.connect ((active) => {
                if (syncing || win.canvas == null) return;
                if (state (action) != active) {
                    win.activate_named (action);
                    if (win.properties != null) win.properties.refresh ();
                }
                sync ();
            });
            view_toggles[action] = t;
        }

        private string? shortcut_for (string action) {
            var app = GLib.Application.get_default () as Gtk.Application;
            if (app == null) return null;
            string[] accels = app.get_accels_for_action ("win." + action);
            if (accels.length == 0) return null;
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse (accels[0], out key, out mods)) return null;
            return Gtk.accelerator_get_label (key, mods);
        }

        public void watch_actions () {
            foreach (var name in view_toggles.keys) {
                var a = win.actions[name];
                if (a != null) a.activate.connect_after (() => sync ());
            }
        }

        private bool state (string action) {
            var c = win.canvas;
            var d = win.doc;
            if (c == null || d == null) return false;
            switch (action) {
                case "view-outline": return c.outline_mode;
                case "view-proof": return d.proof;
                case "view-overprint": return d.overprint_preview;
                case "view-grid": return c.show_grid;
                case "view-rulers": return c.show_rulers;
                case "view-edges": return c.show_edges;
                case "view-smart-guides": return c.smart_guides;
                case "view-snap-grid": return c.snap_grid;
                case "view-snap-pixel": return c.snap_pixel;
                case "view-snap-points": return c.snap_points;
                case "view-perspective": return d.perspective.visible;
                default: return false;
            }
        }

        public void sync () {
            syncing = true;
            foreach (var e in view_toggles.entries) e.value.active = state (e.key);
            syncing = false;
        }
    }
}
