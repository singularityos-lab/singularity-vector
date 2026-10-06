using Gtk;

namespace Singularity.Apps.Vector {

    public class VectorApp : Singularity.Application {
        public VectorApp () {
            Object (application_id: "dev.sinty.vector", flags: ApplicationFlags.HANDLES_OPEN);
        }

        protected override void startup () {
            base.startup ();
            about_version = "0.2.0";
            about_license = _("GNU General Public License, version 3 only");
            var theme = IconTheme.get_for_display (Gdk.Display.get_default ());
            theme.add_resource_path ("/dev/sinty/vector/icons");
            Singularity.Application.add_app_css (CSS);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ().copy ()) w.close ();
            });
            add_action (quit);
            var new_window = new SimpleAction ("new-window", null);
            new_window.activate.connect (() => new VectorWindow (this).present ());
            add_action (new_window);
            build_menu ();
            install_accels ();
        }

        public override void activate () {
            var w = get_active_window () as VectorWindow;
            if (w == null) {
                w = new VectorWindow (this);
                TestScript.maybe_run (w);
            }
            w.present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var file in files) {
                var w = get_active_window () as VectorWindow;
                if (w == null || w.doc != null) w = new VectorWindow (this);
                w.open_file (file);
                w.present ();
                TestScript.maybe_run (w);
            }
        }

        private const string CSS = """
.sx-tool-palette {
    background-color: @surface_raised;
    border-radius: 14px;
    padding: 4px;
    box-shadow: 0 2px 10px alpha(black, 0.18), 0 0 0 1px alpha(@window_fg_color, 0.08);
}

.vector-floating-panel {
    background-color: @surface_raised;
    border-radius: 14px;
    padding: 10px;
    box-shadow: 0 2px 10px alpha(black, 0.18), 0 0 0 1px alpha(@window_fg_color, 0.08);
}

.sx-tool-palette button.sx-tool {
    min-width: 32px;
    min-height: 32px;
    padding: 0;
    border-radius: 10px;
}

.sx-tool-palette button.sx-tool:checked {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.sx-tool-palette-separator {
    margin: 2px 6px;
    background-color: alpha(@window_fg_color, 0.12);
    min-height: 1px;
}

.sx-inspector {
    border-left: 1px solid alpha(@window_fg_color, 0.08);
}

.sx-inspector-header {
    margin: 0 14px 10px 14px;
}

.sx-layer-list {
    background: transparent;
}

.sx-layer-list row {
    padding: 0;
    margin: 0 0 1px 0;
    border-radius: 8px;
    min-height: 0;
}

.sx-layer-list row:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.sx-layer-list row.sx-layer-active {
    background-color: alpha(@accent_bg_color, 0.12);
}

.sx-layer-list row.sx-layer-selected {
    background-color: alpha(@accent_bg_color, 0.22);
}

.sx-layer-list row.sx-dragging {
    opacity: 0.5;
}

.sx-layer-list row.sx-drop-before {
    box-shadow: inset 0 2px 0 @accent_bg_color;
}

.sx-layer-list row.sx-drop-after {
    box-shadow: inset 0 -2px 0 @accent_bg_color;
}

.sx-layer-list row.sx-drop-into {
    box-shadow: inset 0 0 0 2px @accent_bg_color;
}

.sx-layer-toggle {
    min-width: 24px;
    min-height: 24px;
    padding: 0;
    border-radius: 6px;
}

.sx-layer-toggle:checked,
.sx-layer-toggle:checked:hover {
    background: none;
    box-shadow: none;
}

.sx-layer-toggle:hover {
    background-color: alpha(@window_fg_color, 0.08);
}

.sx-layer-toggle.sx-off {
    opacity: 0.45;
}

.sx-layer-thumb {
    border-radius: 4px;
    background-color: @view_bg_color;
    box-shadow: 0 0 0 1px alpha(@window_fg_color, 0.12);
}

.sx-layer-name.sx-layer-is-layer {
    font-weight: 600;
}

.sx-layer-edit {
    min-height: 0;
    padding: 2px 6px;
}

.sx-layer-list-bar {
    padding-top: 8px;
    border-top: 1px solid alpha(@window_fg_color, 0.08);
}

.vector-swatch {
    padding: 2px;
    min-width: 0;
    min-height: 0;
    border-radius: 6px;
}
""";

        private void install_accels () {
            string[,] accels = {
                { "win.new-document", "<Control>n" }, { "win.open", "<Control>o" }, { "app.quit", "<Control>q" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.close-document", "<Control>w" },
                { "win.export-screens", "<Control><Alt>e" }, { "win.export-svg", "<Control><Shift>e" }, { "win.print", "<Control>p" },
                { "win.place-image", "<Control><Shift>p" }, { "win.undo", "<Control>z" }, { "win.redo", "<Control><Shift>z" },
                { "win.cut", "<Control>x" }, { "win.copy", "<Control>c" }, { "win.paste", "<Control>v" },
                { "win.paste-front", "<Control>f" }, { "win.paste-back", "<Control>b" }, { "win.paste-in-place", "<Control><Shift>v" },
                { "win.duplicate", "<Control>j" }, { "win.select-all", "<Control>a" },
                { "win.deselect", "<Control><Shift>a" }, { "win.group", "<Control>g" }, { "win.ungroup", "<Control><Shift>g" },
                { "win.lock", "<Control>2" }, { "win.unlock-all", "<Control><Alt>2" }, { "win.hide", "<Control>3" }, { "win.show-all", "<Control><Alt>3" },
                { "win.arrange-front", "<Control><Shift>bracketright" }, { "win.arrange-forward", "<Control>bracketright" },
                { "win.arrange-backward", "<Control>bracketleft" }, { "win.arrange-back", "<Control><Shift>bracketleft" },
                { "win.transform-move", "<Control><Shift>m" }, { "win.transform-each", "<Control><Alt><Shift>d" }, { "win.transform-again", "<Control>d" },
                { "win.path-join", "<Control><Shift>j" }, { "win.path-average", "<Control><Alt>j" },
                { "win.compound-make", "<Control>8" }, { "win.compound-release", "<Control><Alt><Shift>8" },
                { "win.clip-make", "<Control>7" }, { "win.clip-release", "<Control><Alt>7" },
                { "win.blend-make", "<Control><Alt>b" }, { "win.blend-release", "<Control><Alt><Shift>b" },
                { "win.envelope-warp", "<Control><Alt><Shift>w" }, { "win.envelope-mesh", "<Control><Alt>m" }, { "win.envelope-top", "<Control><Alt>c" },
                { "win.live-paint-make", "<Control><Alt>x" }, { "win.text-outlines", "<Control><Shift>o" },
                { "win.zoom-in", "<Control>plus" }, { "win.zoom-out", "<Control>minus" }, { "win.zoom-fit", "<Control>0" }, { "win.zoom-all", "<Control><Alt>0" }, { "win.zoom-actual", "<Control>1" },
                { "win.view-outline", "<Control>y" }, { "win.view-proof", "<Control><Alt>y" }, { "win.view-grid", "<Control>apostrophe" },
                { "win.view-snap-grid", "<Control><Shift>apostrophe" }, { "win.view-smart-guides", "<Control>u" }, { "win.view-rulers", "<Control>r" },
                { "win.view-edges", "<Control>h" }, { "win.view-perspective", "<Control><Shift>i" }, { "win.toggle-layers", "F7" },
                { "win.toggle-inspector", "F4" },
                { "win.document-setup", "<Control><Alt>p" }, { "win.pf-unite", "<Control><Alt>u" }, { "win.symbol-new", "F8" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.toggle-layers", { "F7", "F9" });
            set_accels_for_action ("win.fullscreen", { "F11" });
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            file.append_section (null, section ({ { _("New"), "win.new-document" }, { _("New Window"), "app.new-window" }, { _("Open…"), "win.open" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" } }));
            file.append_section (null, section ({ { _("Place Image…"), "win.place-image" }, { _("Place Linked Image…"), "win.place-linked-image" } }));
            var export = new GLib.Menu ();
            export.append_section (null, section ({ { _("Export for Screens…"), "win.export-screens" }, { _("Export Image…"), "win.export-image" } }));
            export.append_section (null, section ({ { _("SVG…"), "win.export-svg" }, { _("PDF…"), "win.export-pdf" }, { _("EPS…"), "win.export-eps" }, { _("DXF…"), "win.export-dxf" }, { _("OpenDocument Drawing…"), "win.export-odg" } }));
            file.append_submenu (_("Export"), export);
            file.append_section (null, section ({ { _("Print…"), "win.print" }, { _("Document Setup"), "win.document-setup" } }));
            file.append_section (null, section ({ { _("Close"), "win.close-document" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Cut"), "win.cut" }, { _("Copy"), "win.copy" }, { _("Paste"), "win.paste" }, { _("Paste in Front"), "win.paste-front" }, { _("Paste in Back"), "win.paste-back" }, { _("Paste in Place"), "win.paste-in-place" }, { _("Duplicate"), "win.duplicate" }, { _("Delete"), "win.delete" } }));
            edit.append_section (null, section ({ { _("Recolor Artwork…"), "win.recolor" }, { _("Swap Fill and Stroke"), "win.swap-fill-stroke" } }));
            edit.append_section (null, section ({ { _("Record Action"), "win.actions-record" }, { _("Stop Recording"), "win.actions-stop" }, { _("Actions…"), "win.actions-panel" }, { _("Plugins…"), "win.plugins" } }));
            menu.append_submenu (_("Edit"), edit);
            var object = new GLib.Menu ();
            var transform = new GLib.Menu ();
            transform.append_section (null, section ({ { _("Transform Again"), "win.transform-again" }, { _("Move…"), "win.transform-move" }, { _("Rotate…"), "win.transform-rotate" }, { _("Reflect…"), "win.transform-reflect" }, { _("Scale…"), "win.transform-scale" }, { _("Shear…"), "win.transform-shear" }, { _("Transform Each…"), "win.transform-each" } }));
            transform.append_section (null, section ({ { _("Flip Horizontal"), "win.flip-horizontal" }, { _("Flip Vertical"), "win.flip-vertical" }, { _("Rotate 90 Degrees"), "win.rotate-90" } }));
            object.append_submenu (_("Transform"), transform);
            var arrange = new GLib.Menu ();
            arrange.append_section (null, section ({ { _("Bring to Front"), "win.arrange-front" }, { _("Bring Forward"), "win.arrange-forward" }, { _("Send Backward"), "win.arrange-backward" }, { _("Send to Back"), "win.arrange-back" } }));
            object.append_submenu (_("Arrange"), arrange);
            var align = new GLib.Menu ();
            align.append_section (null, section ({ { _("Left"), "win.align-left" }, { _("Horizontal Center"), "win.align-hcenter" }, { _("Right"), "win.align-right" }, { _("Top"), "win.align-top" }, { _("Vertical Center"), "win.align-vcenter" }, { _("Bottom"), "win.align-bottom" } }));
            align.append_section (null, section ({ { _("Distribute Horizontally"), "win.distribute-h" }, { _("Distribute Vertically"), "win.distribute-v" } }));
            object.append_submenu (_("Align"), align);
            object.append_section (null, section ({ { _("Group"), "win.group" }, { _("Ungroup"), "win.ungroup" }, { _("Lock Selection"), "win.lock" }, { _("Unlock All"), "win.unlock-all" }, { _("Hide Selection"), "win.hide" }, { _("Show All"), "win.show-all" } }));
            object.append_section (null, section ({ { _("Expand"), "win.expand" }, { _("Expand Appearance"), "win.expand-appearance" } }));
            var path = new GLib.Menu ();
            path.append_section (null, section ({ { _("Join"), "win.path-join" }, { _("Average"), "win.path-average" }, { _("Outline Stroke"), "win.path-outline-stroke" }, { _("Offset Path…"), "win.path-offset" }, { _("Simplify…"), "win.path-simplify" }, { _("Add Anchor Points"), "win.path-add-anchors" }, { _("Convert Anchor Points"), "win.path-convert-anchor" }, { _("Reverse Path Direction"), "win.path-reverse" } }));
            path.append_section (null, section ({ { _("Even-Odd Fill Rule"), "win.fill-evenodd" }, { _("Non-Zero Fill Rule"), "win.fill-nonzero" } }));
            object.append_submenu (_("Path"), path);
            var pathfinder = new GLib.Menu ();
            pathfinder.append_section (null, section ({ { _("Unite"), "win.pf-unite" }, { _("Minus Front"), "win.pf-minus-front" }, { _("Intersect"), "win.pf-intersect" }, { _("Exclude"), "win.pf-exclude" } }));
            pathfinder.append_section (null, section ({ { _("Divide"), "win.pf-divide" }, { _("Trim"), "win.pf-trim" }, { _("Merge"), "win.pf-merge" }, { _("Crop"), "win.pf-crop" }, { _("Outline"), "win.pf-outline" }, { _("Minus Back"), "win.pf-minus-back" } }));
            object.append_submenu (_("Pathfinder"), pathfinder);
            var masks = new GLib.Menu ();
            masks.append_section (null, section ({ { _("Make Clipping Mask"), "win.clip-make" }, { _("Release Clipping Mask"), "win.clip-release" }, { _("Make Opacity Mask"), "win.mask-make" }, { _("Release Opacity Mask"), "win.mask-release" } }));
            masks.append_section (null, section ({ { _("Make Compound Path"), "win.compound-make" }, { _("Release Compound Path"), "win.compound-release" } }));
            object.append_submenu (_("Masks and Compounds"), masks);
            var live = new GLib.Menu ();
            live.append_section (null, section ({ { _("Make Blend"), "win.blend-make" }, { _("Release Blend"), "win.blend-release" }, { _("Replace Spine"), "win.blend-spine" } }));
            live.append_section (null, section ({ { _("Envelope with Warp…"), "win.envelope-warp" }, { _("Envelope with Mesh…"), "win.envelope-mesh" }, { _("Envelope with Top Object"), "win.envelope-top" }, { _("Free Distort Envelope"), "win.envelope-distort" }, { _("Release Envelope"), "win.envelope-release" } }));
            live.append_section (null, section ({ { _("Radial Repeat"), "win.repeat-radial" }, { _("Grid Repeat"), "win.repeat-grid" }, { _("Mirror Repeat"), "win.repeat-mirror" } }));
            live.append_section (null, section ({ { _("Make Live Paint"), "win.live-paint-make" }, { _("Create Gradient Mesh…"), "win.mesh-create" } }));
            live.append_section (null, section ({ { _("3D Extrude"), "win.3d-extrude" }, { _("3D Revolve"), "win.3d-revolve" }, { _("New Graph…"), "win.graph-create" } }));
            object.append_submenu (_("Live Objects"), live);
            object.append_section (null, section ({ { _("Image Trace…"), "win.image-trace" }, { _("Vectorize Image"), "win.vectorize" }, { _("Embed Image"), "win.image-embed" } }));
            object.append_section (null, section ({ { _("New Symbol"), "win.symbol-new" }, { _("Break Symbol Link"), "win.symbol-break" }, { _("Make Pattern"), "win.pattern-make" } }));
            var boards = new GLib.Menu ();
            boards.append_section (null, section ({ { _("New Artboard"), "win.artboard-new" }, { _("Duplicate Artboard"), "win.artboard-duplicate" }, { _("Delete Artboard"), "win.artboard-delete" }, { _("Fit to Artwork Bounds"), "win.artboard-fit" } }));
            object.append_submenu (_("Artboards"), boards);
            menu.append_submenu (_("Object"), object);
            var type = new GLib.Menu ();
            type.append_section (null, section ({ { _("Create Outlines"), "win.text-outlines" }, { _("Thread Selected Text Areas"), "win.text-thread" }, { _("Remove Threading"), "win.text-unthread" } }));
            menu.append_submenu (_("Type"), type);
            var select = new GLib.Menu ();
            select.append_section (null, section ({ { _("All"), "win.select-all" }, { _("Deselect"), "win.deselect" }, { _("Inverse"), "win.select-inverse" } }));
            select.append_section (null, section ({ { _("Same Fill Color"), "win.select-same-fill" }, { _("Same Stroke Color"), "win.select-same-stroke" }, { _("Same Stroke Weight"), "win.select-same-width" }, { _("Same Opacity"), "win.select-same-opacity" }, { _("Same Blending Mode"), "win.select-same-blend" }, { _("Same Graphic Style"), "win.select-same-style" }, { _("Same Symbol"), "win.select-same-symbol" }, { _("Same Object Type"), "win.select-same-kind" } }));
            menu.append_submenu (_("Select"), select);
            var effect = new GLib.Menu ();
            effect.append_section (null, section ({ { _("Drop Shadow…"), "win.effect-drop-shadow" }, { _("Outer Glow…"), "win.effect-outer-glow" }, { _("Inner Glow…"), "win.effect-inner-glow" }, { _("Gaussian Blur…"), "win.effect-blur" }, { _("Feather…"), "win.effect-feather" } }));
            effect.append_section (null, section ({ { _("Round Corners…"), "win.effect-round-corners" }, { _("Offset Path…"), "win.effect-offset" }, { _("Roughen…"), "win.effect-roughen" }, { _("Zig Zag…"), "win.effect-zigzag" }, { _("Pucker and Bloat…"), "win.effect-pucker" }, { _("Twist…"), "win.effect-twist" }, { _("Transform…"), "win.effect-transform" }, { _("Warp…"), "win.effect-warp" }, { _("Free Distort…"), "win.effect-free-distort" } }));
            menu.append_submenu (_("Effect"), effect);
            var view = new GLib.Menu ();
            view.append_section (null, section ({ { _("Outline"), "win.view-outline" }, { _("Proof Colors"), "win.view-proof" }, { _("Overprint Preview"), "win.view-overprint" } }));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Fit Artboard"), "win.zoom-fit" }, { _("Fit All"), "win.zoom-all" }, { _("Actual Size"), "win.zoom-actual" }, { _("Zoom to Selection"), "win.zoom-selection" } }));
            view.append_section (null, section ({ { _("Rulers"), "win.view-rulers" }, { _("Grid"), "win.view-grid" }, { _("Snap to Grid"), "win.view-snap-grid" }, { _("Snap to Pixel"), "win.view-snap-pixel" }, { _("Smart Guides"), "win.view-smart-guides" }, { _("Snap to Points"), "win.view-snap-points" }, { _("Edges"), "win.view-edges" } }));
            view.append_section (null, section ({ { _("Make Guides from Selection"), "win.guides-make" }, { _("Clear Guides"), "win.guides-clear" } }));
            view.append_section (null, section ({ { _("Perspective Grid"), "win.view-perspective" }, { _("One Point Perspective"), "win.view-perspective-1" }, { _("Two Point Perspective"), "win.view-perspective-2" }, { _("Three Point Perspective"), "win.view-perspective-3" } }));
            view.append_section (null, section ({ { _("Layers"), "win.toggle-layers" }, { _("Inspector"), "win.toggle-inspector" }, { _("Full Screen"), "win.fullscreen" }, { _("History"), "win.history" }, { _("Properties"), "win.panel-properties" }, { _("Appearance"), "win.panel-appearance" }, { _("Libraries"), "win.panel-libraries" } }));
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
        }
    }
}
