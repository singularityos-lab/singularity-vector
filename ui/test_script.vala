using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class TestScript : Object {
        private static bool started = false;
        private VectorWindow win;
        private string[] lines;
        private int index = 0;

        public static void maybe_run (VectorWindow win) {
            string? path = Environment.get_variable ("SINGULARITY_VECTOR_TEST_SCRIPT");
            if (path == null || started) return;
            started = true;
            string text;
            try {
                FileUtils.get_contents (path, out text);
            } catch (Error e) {
                printerr ("script: %s\n", e.message);
                return;
            }
            var s = new TestScript ();
            s.win = win;
            s.lines = text.split ("\n");
            s.ref ();
            Timeout.add (1200, () => {
                s.step ();
                return Source.REMOVE;
            });
        }

        private void step () {
            while (index < lines.length) {
                string line = lines[index++].strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                uint wait = 250;
                try {
                    wait = run (line);
                    printerr ("script: ok %s\n", line);
                } catch (Error e) {
                    printerr ("script: FAIL %s: %s\n", line, e.message);
                }
                Timeout.add (wait, () => {
                    step ();
                    return Source.REMOVE;
                });
                return;
            }
            printerr ("script: finished\n");
            unref ();
        }

        private static Point pt (string s) {
            var v = s.split (",");
            return Point (double.parse (v[0]), double.parse (v.length > 1 ? v[1] : "0"));
        }

        private static Gdk.ModifierType mods (string[] a, int from) {
            Gdk.ModifierType m = 0;
            for (int i = from; i < a.length; i++) {
                if (a[i] == "shift") m |= Gdk.ModifierType.SHIFT_MASK;
                if (a[i] == "alt") m |= Gdk.ModifierType.ALT_MASK;
                if (a[i] == "ctrl") m |= Gdk.ModifierType.CONTROL_MASK;
            }
            return m;
        }

        public void shot (string name) {
            string dir = Environment.get_variable ("VECTOR_SHOTS") ?? Environment.get_tmp_dir ();
            var paintable = new Gtk.WidgetPaintable (win);
            int w = win.get_width (), h = win.get_height ();
            var snap = new Gtk.Snapshot ();
            paintable.snapshot (snap, w, h);
            var node = snap.to_node ();
            if (node == null) return;
            var renderer = win.get_native ().get_renderer ();
            var tex = renderer.render_texture (node, { { 0, 0 }, { w, h } });
            tex.save_to_png (Path.build_filename (dir, name + ".png"));
        }

        private void measure_tree (Gtk.Widget w, int depth) {
            int min, nat, mb, nb;
            w.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, out mb, out nb);
            if (min > 290) {
                string label = "";
                var l = w as Gtk.Label;
                if (l != null) label = l.label;
                var b = w as Gtk.Button;
                if (b != null && b.label != null) label = b.label;
                printerr ("measure: %s%s min=%d %s\n", string.nfill (depth, ' '), w.get_type ().name (), min, label);
            }
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) measure_tree (c, depth + 1);
        }

        private uint run (string line) throws Error {
            string[] a = line.split (" ");
            string rest = line.length > a[0].length ? line.substring (a[0].length + 1) : "";
            var c = win.canvas;
            switch (a[0]) {
                case "wait":
                    return (uint) int.parse (a[1]);
                case "new":
                    win.new_document ();
                    return 800;
                case "open":
                    win.open_file (File.new_for_path (rest));
                    return 1500;
                case "tool":
                    c.set_tool (a[1]);
                    return 150;
                case "press":
                    c.tool.press (pt (a[1]), mods (a, 2));
                    return 60;
                case "drag":
                    c.tool.drag (pt (a[1]), mods (a, 2));
                    c.queue_draw ();
                    return 40;
                case "release":
                    c.tool.release (pt (a[1]), mods (a, 2));
                    c.hints.clear ();
                    c.queue_draw ();
                    return 150;
                case "stroke-path":
                    var pts = new Gee.ArrayList<Point?> ();
                    for (int i = 1; i < a.length; i++) pts.add (pt (a[i]));
                    c.tool.press (pts[0], 0);
                    for (int i = 1; i < pts.size; i++) c.tool.drag (pts[i], 0);
                    c.tool.release (pts[pts.size - 1], 0);
                    return 200;
                case "dblclick":
                    c.tool.double_click (pt (a[1]), mods (a, 2));
                    return 300;
                case "key":
                    uint keyval = Gdk.keyval_from_name (a[1]);
                    c.tool.key (keyval, mods (a, 2));
                    return 150;
                case "action":
                    win.activate_named (a[1]);
                    return 600;
                case "select-all":
                    Commands.select_all (c);
                    return 150;
                case "select-at":
                    var n = c.hit_root (pt (a[1]));
                    if (a.length > 2 && a[2] == "add" && n != null) c.toggle_selection (n);
                    else c.select_only (n);
                    return 150;
                case "select-name":
                    var list = new Gee.ArrayList<Node> ();
                    foreach (var n in c.doc.all_nodes ()) if (n.name == rest) list.add (n);
                    c.set_selection (list);
                    return 150;
                case "deselect":
                    c.clear_selection ();
                    return 100;
                case "fill":
                    Commands.apply_paint (c, rest == "none" ? new Paint () : new Paint.hex (rest), false);
                    return 150;
                case "stroke":
                    Commands.apply_paint (c, a[1] == "none" ? new Paint () : new Paint.hex (a[1]), true);
                    if (a.length > 2) {
                        c.doc.begin ("width");
                        foreach (var n in c.selection) n.ensure_stroke ().width = double.parse (a[2]);
                        c.doc.commit ();
                    }
                    return 150;
                case "style-fill":
                    c.style.fill = rest == "none" ? new Paint () : new Paint.hex (rest);
                    return 50;
                case "style-stroke":
                    c.style.stroke = a[1] == "none" ? new Paint () : new Paint.hex (a[1]);
                    if (a.length > 2) c.style.width = double.parse (a[2]);
                    return 50;
                case "text":
                    foreach (var n in c.selection) {
                        var t = n as TextNode;
                        if (t == null) continue;
                        c.doc.begin ("text");
                        t.text = rest.replace ("\\n", "\n");
                        c.doc.commit ();
                    }
                    if (win.text_editor != null) win.text_editor.finish ();
                    TextLayout.invalidate ();
                    return 300;
                case "text-style":
                    foreach (var n in c.selection) {
                        var t = n as TextNode;
                        if (t == null) continue;
                        c.doc.begin ("style");
                        if (a.length > 1) t.style.family = a[1].replace ("_", " ");
                        if (a.length > 2) t.style.size = double.parse (a[2]);
                        if (a.length > 3) t.style.weight = int.parse (a[3]);
                        c.doc.commit ();
                    }
                    TextLayout.invalidate ();
                    return 200;
                case "finish-text":
                    if (win.text_editor != null) win.text_editor.finish ();
                    return 200;
                case "effect":
                    var e = AppearancePanel.default_effect (a[1]);
                    for (int i = 2; i + 1 < a.length; i += 2) e.set_num (a[i], double.parse (a[i + 1]));
                    c.doc.begin ("effect");
                    foreach (var n in c.selection) n.effects.add (e.copy ());
                    c.doc.commit ();
                    return 300;
                case "opacity":
                    c.doc.begin ("opacity");
                    foreach (var n in c.selection) n.opacity = double.parse (a[1]);
                    c.doc.commit ();
                    return 150;
                case "blend-mode":
                    c.doc.begin ("blend");
                    foreach (var n in c.selection) n.blend = BlendMode.from_id (a[1]);
                    c.doc.commit ();
                    return 150;
                case "gradient":
                    var p = new Paint ();
                    p.kind = a[1] == "radial" ? PaintKind.RADIAL : (a[1] == "freeform" ? PaintKind.FREEFORM : PaintKind.LINEAR);
                    if (p.kind != PaintKind.FREEFORM) {
                        p.gradient = new Gradient ();
                        for (int i = 2; i < a.length; i++) p.gradient.stops.add (new GradientStop ((i - 2) / (double) double.max (a.length - 3, 1), Ink.hex (a[i])));
                    }
                    Commands.apply_paint (c, p, false);
                    return 200;
                case "zoom":
                    if (a[1] == "fit") c.fit_artboard ();
                    else if (a[1] == "all") c.fit_all ();
                    else c.set_zoom (double.parse (a[1]));
                    return 300;
                case "panel":
                    win.show_inspector_page (a[1]);
                    return 300;
                case "sidebar":
                    win.set_layers_visible (a[1] == "on");
                    return 300;
                case "shot":
                    shot (a[1]);
                    return 200;
                case "measure":
                    measure_tree (win.properties, 0);
                    measure_tree (win.appearance, 0);
                    measure_tree (win.libraries, 0);
                    return 100;
                case "run":
                    printerr ("script: run %s\n", a[1]);
                    return (uint) (a.length > 2 ? int.parse (a[2]) : 6000);
                case "dump":
                    var builder = new StringBuilder ();
                    foreach (var n in c.doc.all_nodes ()) {
                        var pn = n as PathNode;
                        builder.append_printf ("%s %s %s\n", n.kind_name (), n.display_name (), pn != null ? pn.path.to_svg (1) : "");
                    }
                    printerr ("script: dump\n%s", builder.str);
                    return 100;
                case "view":
                    c.ox = double.parse (a[1]);
                    c.oy = double.parse (a[2]);
                    c.zoom = double.parse (a[3]);
                    c.queue_draw ();
                    c.view_changed ();
                    return 200;
                case "where":
                    Graphene.Point origin;
                    c.compute_point (win, { 0, 0 }, out origin);
                    printerr ("script: where canvas=%g,%g window=%dx%d zoom=%g o=%g,%g\n", origin.x, origin.y, win.get_width (), win.get_height (), c.zoom, c.ox, c.oy);
                    return 100;
                case "mesh":
                    var target = c.selection.size > 0 ? c.selection[0] as PathNode : null;
                    if (target != null) Commands.make_mesh (c, target, int.parse (a[1]), int.parse (a[2]));
                    return 400;
                case "mesh-color":
                    foreach (var n in c.selection) {
                        MeshNode? m = n as MeshNode;
                        var g = n as GroupNode;
                        if (m == null && g != null && g.children.size > 1) m = g.children[1] as MeshNode;
                        if (m == null) continue;
                        c.doc.begin ("mesh color");
                        m.at (int.parse (a[1]), int.parse (a[2])).color = Ink.hex (a[3]);
                        c.doc.commit ();
                    }
                    return 200;
                case "envelope-warp":
                    Commands.make_envelope (c, "warp", a[1], double.parse (a[2]));
                    return 400;
                case "envelope-mesh":
                    var env = Commands.make_envelope (c, "mesh", "arc", 0, 2, 2);
                    if (env != null && a.length > 3) {
                        c.doc.begin ("move");
                        env.grid[int.parse (a[1])] = Point (env.grid[int.parse (a[1])].x + double.parse (a[2]), env.grid[int.parse (a[1])].y + double.parse (a[3]));
                        c.doc.commit ();
                    }
                    return 400;
                case "chart":
                    Commands.make_chart (c, a[1], Rect (double.parse (a[2]), double.parse (a[3]), double.parse (a[4]), double.parse (a[5])));
                    return 400;
                case "trace":
                    foreach (var n in c.selection) {
                        var im = n as ImageNode;
                        if (im == null) continue;
                        var opts = new TraceOptions ();
                        opts.mode = a[1];
                        opts.colors = a.length > 2 ? int.parse (a[2]) : 6;
                        opts.ignore_white = true;
                        ImageTrace.run (c, im, opts);
                        break;
                    }
                    return 1500;
                case "symbol-new":
                    Commands.new_symbol (c, rest);
                    return 300;
                case "symbol-place":
                    if (c.doc.symbols.size > 0) Commands.place_symbol (c, c.doc.symbols[c.doc.symbols.size - 1], pt (a[1]));
                    return 300;
                case "brush":
                    Commands.apply_brush (c, c.doc.brushes[int.parse (a[1])].id);
                    return 300;
                case "offset":
                    Commands.offset_path (c, double.parse (a[1]), JoinKind.ROUND, 4);
                    return 300;
                case "simplify":
                    Commands.simplify (c, double.parse (a[1]), 40, false);
                    return 300;
                case "outline-stroke":
                    Commands.outline_stroke (c);
                    return 300;
                case "repeat":
                    Commands.make_repeat (c, a[1]);
                    return 300;
                case "pattern-new":
                    Commands.new_pattern (c, rest);
                    return 300;
                case "pattern-fill":
                    var pp = new Paint ();
                    pp.kind = PaintKind.PATTERN;
                    pp.pattern = c.doc.patterns[c.doc.patterns.size - 1].id;
                    Commands.apply_paint (c, pp, false);
                    return 300;
                case "style-new":
                    Commands.new_style (c, rest);
                    return 200;
                case "style-apply":
                    Commands.apply_style (c, c.doc.styles[int.parse (a[1])]);
                    return 200;
                case "width-profile":
                    c.doc.begin ("profile");
                    foreach (var n in c.selection) {
                        var st = n.ensure_stroke ();
                        st.profile.clear ();
                        st.profile.add (new WidthPoint (0, 0.1, 0.1));
                        st.profile.add (new WidthPoint (0.5, 1.5, 1.5));
                        st.profile.add (new WidthPoint (1, 0.1, 0.1));
                    }
                    c.doc.commit ();
                    return 200;
                case "corners":
                    c.doc.begin ("corners");
                    foreach (var n in c.selection) {
                        var pn = n as PathNode;
                        if (pn == null) continue;
                        PathEdit.detach_live (pn);
                        foreach (int i in PathOps.anchors (pn.path)) {
                            pn.corners[i] = double.parse (a[1]);
                            pn.corner_kinds[i] = a.length > 2 ? int.parse (a[2]) : 0;
                        }
                    }
                    c.doc.commit ();
                    return 200;
                case "recolor":
                    var map = new Gee.HashMap<string, Ink> ();
                    map[a[1]] = Ink.hex (a[2]);
                    Commands.recolor (c, map);
                    return 200;
                case "export-screens":
                    int count = ScreenExport.run (c.doc, c, a[1], "", 0, { 1, 2 }, { "png", "svg", "pdf", "webp", "jpeg" }, true);
                    printerr ("script: exported %d\n", count);
                    return 1500;
                case "export-dxf":
                    Dxf.write (c.doc, rest, c.doc.current_artboard ().rect ());
                    return 300;
                case "export-odg":
                    DrawExchange.export_odg (c.doc, rest, -1);
                    return 500;
                case "add-artboard":
                    var ab = new Artboard (a[1], double.parse (a[2]), double.parse (a[3]), double.parse (a[4]), double.parse (a[5]));
                    c.doc.begin ("artboard");
                    c.doc.add_artboard (ab);
                    c.doc.commit ();
                    c.doc.structure_changed ();
                    return 300;
                case "perspective-rect":
                    var plane = Perspective.planes (c.doc.perspective)[int.parse (a[1])];
                    var path = new PathData ();
                    Point[] uv = { Point (double.parse (a[2]), double.parse (a[3])), Point (double.parse (a[4]), double.parse (a[3])), Point (double.parse (a[4]), double.parse (a[5])), Point (double.parse (a[2]), double.parse (a[5])) };
                    for (int i = 0; i < 4; i++) {
                        var q = Warp.project (plane.h, uv[i]);
                        if (i == 0) path.move_to (q.x, q.y);
                        else path.line_to (q.x, q.y);
                    }
                    path.close ();
                    var node = new PathNode.with_path (path);
                    c.style.apply (node);
                    c.tool.add_node (node, "perspective");
                    return 300;
                case "layer-new":
                    win.activate_named ("layer-new");
                    return 300;
                case "expand-layers":
                    win.set_layers_visible (true);
                    return 300;
                case "select-last":
                    var layer = c.doc.active_layer;
                    var last = new Gee.ArrayList<Node> ();
                    int k = int.parse (a[1]);
                    for (int i = int.max (0, layer.children.size - k); i < layer.children.size; i++) last.add (layer.children[i]);
                    c.set_selection (last);
                    return 150;
                case "color-mode":
                    c.doc.begin ("mode");
                    c.doc.color_mode = a[1];
                    if (a[1] == "cmyk") ColorConvert.document_to_cmyk (c.doc);
                    c.doc.commit ();
                    return 300;
                case "proof":
                    c.doc.proof = a[1] == "on";
                    c.queue_draw ();
                    return 300;
                case "overprint":
                    foreach (var n in c.selection) {
                        var f = n.first_fill ();
                        if (f != null) f.paint.overprint = true;
                    }
                    c.doc.overprint_preview = true;
                    c.doc.changed ();
                    return 300;
                case "plugin":
                    Plugins.run_command (win, Plugins.get_default ().commands[0]);
                    return 600;
                case "record":
                    win.recorder.start ();
                    return 100;
                case "stop":
                    win.recorder.stop ();
                    return 100;
                case "play":
                    win.recorder.play (c.doc.actions[c.doc.actions.size - 1]);
                    return 600;
                case "transform-each":
                    Commands.transform_each (c, 1, 1, 0, 0, double.parse (a[1]), false, false, -1, false, int.parse (a[2]));
                    return 400;
                case "mask":
                    Commands.opacity_mask (c, true);
                    return 300;
                case "perspective":
                    c.doc.perspective.points = int.parse (a[1]);
                    c.set_tool ("perspective");
                    return 300;
                case "count":
                    int total = 0;
                    foreach (var n in c.doc.all_nodes ()) if (n.kind_name () == a[1]) total++;
                    printerr ("script: count %s %d\n", a[1], total);
                    return 50;
                case "grim":
                    printerr ("script: grim %s\n", a[1]);
                    return 1500;
                case "save":
                    Formats.save_native (c.doc, rest);
                    c.doc.path = rest;
                    c.doc.modified = false;
                    return 300;
                case "export-svg":
                    var o = new SvgOptions ();
                    o.native = false;
                    Formats.export_svg (c.doc, rest, o);
                    return 300;
                case "export-pdf":
                    var o = new PdfOptions ();
                    if (a.length > 2) o.standard = a[2];
                    Export.save_pdf (c.doc, a[1], o);
                    return 500;
                case "export-png":
                    Export.save_raster (c.doc, a[1], c.doc.current_artboard ().rect (), a.length > 2 ? double.parse (a[2]) : 1, "png", true);
                    return 400;
                case "place":
                    WindowActions.place_file (win, rest, false);
                    return 400;
                case "place-linked":
                    WindowActions.place_file (win, rest, true);
                    return 400;
                case "artboard":
                    c.doc.active_artboard = int.parse (a[1]);
                    c.fit_artboard ();
                    return 300;
                case "isolate":
                    c.isolation = c.selection.size > 0 ? c.selection[0] as GroupNode : null;
                    c.queue_draw ();
                    return 200;
                case "anchors-all":
                    foreach (var n in c.selection) {
                        var pn = n as PathNode;
                        if (pn == null) continue;
                        var set = new Gee.TreeSet<int> ();
                        foreach (int i in PathOps.anchors (pn.path)) set.add (i);
                        c.anchors[pn] = set;
                    }
                    c.queue_draw ();
                    return 100;
                case "paste-svg":
                    string svg;
                    FileUtils.get_contents (rest, out svg);
                    Commands.paste_text (c, svg, "center");
                    return 300;
                case "close-dialogs":
                    foreach (var w in win.application.get_windows ().copy ()) if (w != win) w.close ();
                    return 300;
                case "quit":
                    c.doc.modified = false;
                    win.application.quit ();
                    return 100;
                case "print":
                    ExportDialogs.print (win);
                    return 2500;
                case "dark":
                    var iface = new GLib.Settings ("org.gnome.desktop.interface");
                    iface.set_string ("color-scheme", a[1] == "on" ? "prefer-dark" : "default");
                    return 900;
                default:
                    throw new IOError.INVALID_ARGUMENT ("unknown command");
            }
        }
    }
}
