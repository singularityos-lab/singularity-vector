using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class PluginHostImpl : Object, VectorPlugin.Host {
        private weak VectorWindow win;

        public PluginHostImpl (VectorWindow win) {
            this.win = win;
        }

        public string document_json {
            owned get {
                return NativeFormat.to_string (win.doc, false);
            }
            set {
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (value);
                    win.doc.begin (_("Plugin"));
                    NativeFormat.document_in (win.doc, parser.get_root ().get_object (), false);
                    win.doc.ensure_ids ();
                    win.doc.commit ();
                    win.doc.structure_changed ();
                } catch (Error e) {
                    win.doc.cancel ();
                    warning ("Vector: plugin document update failed: %s", e.message);
                }
            }
        }

        public string[] selection_ids {
            owned get {
                string[] ids = {};
                foreach (var n in win.canvas.selection) ids += n.id;
                return ids;
            }
        }

        public void run_action (string name) {
            win.activate_named (name);
        }

        public void select_ids (string[] ids) {
            var list = new Gee.ArrayList<Node> ();
            foreach (var id in ids) {
                var n = win.doc.find (id);
                if (n != null) list.add (n);
            }
            win.canvas.set_selection (list);
        }

        public void message (string text) {
            win.toast (text);
        }
    }

    public class Plugins : Object {
        private static Plugins? instance = null;
        private Peas.Engine engine;
        public Gee.ArrayList<VectorPlugin.Command> commands = new Gee.ArrayList<VectorPlugin.Command> ();
        public Gee.ArrayList<VectorPlugin.Exporter> exporters = new Gee.ArrayList<VectorPlugin.Exporter> ();
        public Gee.ArrayList<string> modules = new Gee.ArrayList<string> ();

        public static Plugins get_default () {
            if (instance == null) instance = new Plugins ();
            return instance;
        }

        public static string[] search_dirs () {
            string[] dirs = {};
            string? env = Environment.get_variable ("SINGULARITY_VECTOR_PLUGIN_PATH");
            if (env != null) foreach (var p in env.split (":")) if (p != "") dirs += p;
            try {
                string exe = FileUtils.read_link ("/proc/self/exe");
                string prefix = Path.get_dirname (Path.get_dirname (exe));
                foreach (string libdir in new string[] { "lib", "lib64", "lib/x86_64-linux-gnu", "lib/aarch64-linux-gnu" }) dirs += Path.build_filename (prefix, libdir, "singularity-vector", "plugins");
            } catch (Error e) {
            }
            dirs += Path.build_filename (Environment.get_user_data_dir (), "singularity-vector", "plugins");
            return dirs;
        }

        private Plugins () {
            engine = new Peas.Engine ();
            foreach (var d in search_dirs ()) {
                if (!FileUtils.test (d, FileTest.IS_DIR)) continue;
                engine.add_search_path (d, d);
                try {
                    var dir = Dir.open (d);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        string sub = Path.build_filename (d, name);
                        if (FileUtils.test (sub, FileTest.IS_DIR)) engine.add_search_path (sub, sub);
                    }
                } catch (Error e) {
                }
            }
            engine.rescan_plugins ();
            var model = (ListModel) engine;
            for (uint i = 0; i < model.get_n_items (); i++) {
                var info = (Peas.PluginInfo) model.get_item (i);
                engine.load_plugin (info);
                if (!info.is_loaded ()) continue;
                modules.add (info.get_module_name ());
                if (engine.provides_extension (info, typeof (VectorPlugin.Command))) {
                    var ext = engine.create_extension_with_properties (info, typeof (VectorPlugin.Command), {}, {});
                    if (ext is VectorPlugin.Command) commands.add ((VectorPlugin.Command) ext);
                }
                if (engine.provides_extension (info, typeof (VectorPlugin.Exporter))) {
                    var ext = engine.create_extension_with_properties (info, typeof (VectorPlugin.Exporter), {}, {});
                    if (ext is VectorPlugin.Exporter) exporters.add ((VectorPlugin.Exporter) ext);
                }
            }
        }

        public static void run_command (VectorWindow win, VectorPlugin.Command cmd) {
            try {
                cmd.run (new PluginHostImpl (win));
            } catch (Error e) {
                Forms.message (win, _("Plugin Failed"), e.message);
            }
        }

        public static void show (VectorWindow win) {
            var p = get_default ();
            Box body;
            var dlg = Forms.form (win, _("Plugins"), _("Close"), out body, () => {});
            var g = new Singularity.Widgets.PreferencesGroup (_("Installed Plugins"));
            foreach (var cmd in p.commands) {
                var c = cmd;
                var row = new Singularity.Widgets.ActionRow (c.title, _("Command"));
                row.add_suffix (Forms.text_button (_("Run"), () => {
                    run_command (win, c);
                    dlg.close_dialog ();
                }));
                g.add_row (row);
            }
            foreach (var ex in p.exporters) {
                var e = ex;
                var row = new Singularity.Widgets.ActionRow (e.title, _("Exporter, .%s").printf (e.suffix));
                row.add_suffix (Forms.text_button (_("Export"), () => {
                    var dialog = new FileDialog ();
                    dialog.initial_name = win.base_name () + "." + e.suffix;
                    dialog.save.begin (win, null, (obj, res) => {
                        try {
                            var file = dialog.save.end (res);
                            if (file == null) return;
                            FileUtils.set_data (file.get_path (), e.export (NativeFormat.to_string (win.doc, true)));
                            win.toast (_("Exported %s").printf (file.get_basename ()));
                        } catch (Error err) {
                            if (!(err is DialogError.DISMISSED)) Forms.message (win, _("Plugin Failed"), err.message);
                        }
                    });
                }));
                g.add_row (row);
            }
            if (p.commands.size == 0 && p.exporters.size == 0) g.description = _("No plugins are installed. Plugins are loaded from the singularity-vector/plugins folder in your data directory.");
            body.append (g);
            dlg.present ();
        }
    }

    public class Vectorizer {
        public static void run (VectorWindow win) {
            ImageNode? im = null;
            foreach (var n in win.canvas.selection) if (n is ImageNode) im = (ImageNode) n;
            if (im == null) {
                win.toast (_("Select an image to vectorize."));
                return;
            }
            string command = win.settings != null ? win.settings.get_string ("vectorizer-command") : "";
            if (command.strip () == "") {
                var opts = new TraceOptions ();
                opts.mode = "color";
                opts.colors = 12;
                opts.noise = 4;
                opts.ignore_white = true;
                ImageTrace.run (win.canvas, im, opts);
                win.toast (_("Vectorized with the built-in tracer. Set a local vectorizer command in Settings to use your own model."));
                return;
            }
            try {
                var node = run_command (win.doc, im, command);
                win.doc.begin (_("Vectorize"));
                var parent = im.parent;
                int index = parent.children.index_of (im);
                parent.remove (im);
                parent.add (node, index);
                win.doc.ensure_ids ();
                win.doc.commit ();
                win.canvas.select_only (node);
            } catch (Error e) {
                Forms.message (win, _("Could Not Vectorize"), e.message);
            }
        }

        public static Node run_command (VectorDocument doc, ImageNode im, string command) throws Error {
            string tmp = Path.build_filename (Environment.get_tmp_dir (), "vector-vectorize-%u.png".printf (Random.next_int ()));
            try {
                var raw_surface = Renderer.image_surface (im, doc);
                var surface = (Cairo.ImageSurface) raw_surface;
                if (raw_surface == null) throw new IOError.NOT_FOUND (_("The image data is not available."));
                surface.write_to_png (tmp);
                string[] argv;
                GLib.Shell.parse_argv (command, out argv);
                string[] full = argv;
                full += tmp;
                string stdout_text, stderr_text;
                int status;
                Process.spawn_sync (null, full, null, SpawnFlags.SEARCH_PATH, null, out stdout_text, out stderr_text, out status);
                if (status != 0 || !stdout_text.contains ("<svg")) throw new IOError.FAILED (_("The vectorizer did not return SVG: %s").printf (stderr_text.strip ()));
                var part = SvgReader.parse (stdout_text.substring (stdout_text.index_of ("<")));
                var g = new GroupNode ();
                g.name = _("Vectorized Image");
                var board = part.artboards.size > 0 ? part.artboards[0].rect () : Rect (0, 0, im.pixel_width, im.pixel_height);
                var m = Cairo.Matrix (im.pixel_width / board.w, 0, 0, im.pixel_height / board.h, -board.x * im.pixel_width / board.w, -board.y * im.pixel_height / board.h);
                m = Transforms.multiply (m, im.matrix);
                foreach (var l in part.layers) foreach (var n in l.children.to_array ()) {
                    l.remove (n);
                    n.apply_transform (m, true);
                    g.add (n);
                }
                foreach (var a in part.assets.values) doc.assets[a.id] = a;
                return g;
            } finally {
                FileUtils.unlink (tmp);
            }
        }
    }
}
