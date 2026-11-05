using Singularity.Vector;

namespace Singularity.Apps.Vector {

    internal class VectorIntents : Object {
        private const string[] SHAPES = { "rectangle", "rounded", "ellipse", "polygon", "star", "line", "text" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static double num (Json.Object args, string key, double fallback) {
            return args.has_member (key) ? args.get_double_member (key) : fallback;
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static VectorWindow window (VectorApp app) {
            VectorWindow? found = app.get_active_window () as VectorWindow;
            if (found == null || found.doc == null) {
                foreach (var w in app.get_windows ()) {
                    var vw = w as VectorWindow;
                    if (vw != null && vw.doc != null) {
                        found = vw;
                        break;
                    }
                }
            }
            if (found == null) {
                app.activate ();
                found = app.get_active_window () as VectorWindow;
                if (found == null) found = new VectorWindow (app);
            }
            if (found.doc == null) found.new_document ();
            found.present ();
            return found;
        }

        private static string paint_hex (PaintLayer? l) {
            if (l == null || l.paint.kind == PaintKind.NONE) return "none";
            return l.paint.color.to_hex ();
        }

        private static Json.Object describe (Node n) {
            var o = new Json.Object ();
            var b = n.geometric_bounds ();
            o.set_string_member ("id", n.id);
            o.set_string_member ("kind", n.kind_name ());
            o.set_string_member ("name", n.display_name ());
            o.set_double_member ("x", Math.round (b.x * 100) / 100);
            o.set_double_member ("y", Math.round (b.y * 100) / 100);
            o.set_double_member ("w", Math.round (b.w * 100) / 100);
            o.set_double_member ("h", Math.round (b.h * 100) / 100);
            o.set_string_member ("fill", paint_hex (n.first_fill ()));
            var st = n.first_stroke ();
            o.set_string_member ("stroke", paint_hex (st));
            if (st != null) o.set_double_member ("stroke_width", st.width);
            if (n.opacity < 1) o.set_double_member ("opacity", n.opacity);
            if (n.hidden) o.set_boolean_member ("hidden", true);
            var t = n as TextNode;
            if (t != null) {
                o.set_string_member ("text", t.text);
                o.set_string_member ("font", t.style.family);
                o.set_double_member ("size", t.style.size);
            }
            var g = n as GroupNode;
            if (g != null && g.children.size > 0) {
                var kids = new Json.Array ();
                foreach (var c in g.children) kids.add_object_element (describe (c));
                o.set_array_member ("children", kids);
            }
            return o;
        }

        private static Json.Node context (VectorWindow w) {
            var doc = w.doc;
            var o = new Json.Object ();
            o.set_string_member ("title", doc.title);
            o.set_string_member ("file", doc.path ?? "");
            var boards = new Json.Array ();
            foreach (var a in doc.artboards) {
                var r = a.rect ();
                var ao = new Json.Object ();
                ao.set_string_member ("name", a.name);
                ao.set_double_member ("x", r.x);
                ao.set_double_member ("y", r.y);
                ao.set_double_member ("w", r.w);
                ao.set_double_member ("h", r.h);
                boards.add_object_element (ao);
            }
            o.set_array_member ("artboards", boards);
            var layers = new Json.Array ();
            foreach (var l in doc.layers) {
                var lo = new Json.Object ();
                lo.set_string_member ("id", l.id);
                lo.set_string_member ("name", l.display_name ());
                var items = new Json.Array ();
                foreach (var c in l.children) items.add_object_element (describe (c));
                lo.set_array_member ("objects", items);
                layers.add_object_element (lo);
            }
            o.set_array_member ("layers", layers);
            var sel = new Json.Array ();
            foreach (var n in w.canvas.selection) sel.add_string_element (n.id);
            o.set_array_member ("selection", sel);
            return obj (o);
        }

        private static GroupNode layer (VectorWindow w, string name) {
            var doc = w.doc;
            if (name != "") {
                foreach (var l in doc.layers) if (l.name == name || l.id == name) return l;
                var fresh = doc.new_layer (name);
                doc.layers.add (fresh);
                return fresh;
            }
            if (doc.active_layer != null && doc.has_layer (doc.active_layer)) return doc.active_layer;
            if (doc.layers.size == 0) doc.layers.add (doc.new_layer (_("Layer 1")));
            doc.active_layer = doc.layers[doc.layers.size - 1];
            return doc.active_layer;
        }

        private static Node find (VectorWindow w, Json.Object args) throws Error {
            string id = text (args, "id");
            var n = w.doc.find (id);
            if (n == null) {
                foreach (var m in w.doc.all_nodes ()) if (m.name == id) return m;
                throw new IOError.NOT_FOUND ("no object %s; call vector_context for the ids", id);
            }
            return n;
        }

        private static Paint paint (string hex) throws Error {
            if (hex == "none") return new Paint ();
            Gdk.RGBA rgba = Gdk.RGBA ();
            if (!rgba.parse (hex)) throw new IOError.INVALID_ARGUMENT ("%s is not a colour", hex);
            return new Paint.hex ("#%02x%02x%02x".printf ((uint) (rgba.red * 255), (uint) (rgba.green * 255), (uint) (rgba.blue * 255)));
        }

        private static void style (Node n, Json.Object args) throws Error {
            if (args.has_member ("fill")) Commands.apply_paint_node (n, paint (text (args, "fill")), false);
            if (args.has_member ("stroke")) Commands.apply_paint_node (n, paint (text (args, "stroke")), true);
            if (args.has_member ("stroke_width")) n.ensure_stroke ().width = num (args, "stroke_width", 1).clamp (0, 1000);
            if (args.has_member ("opacity")) n.opacity = num (args, "opacity", 1).clamp (0, 1);
            if (args.has_member ("name")) n.name = text (args, "name");
            if (args.has_member ("hidden")) n.hidden = args.get_boolean_member ("hidden");
            var t = n as TextNode;
            if (t != null) {
                if (args.has_member ("text")) t.text = text (args, "text");
                if (args.has_member ("font")) t.style.family = text (args, "font");
                if (args.has_member ("size")) t.style.size = num (args, "size", 24).clamp (1, 2000);
                TextLayout.invalidate ();
            }
        }

        private static Node build (VectorWindow w, Json.Object args) throws Error {
            string shape = text (args, "shape");
            if (!(shape in SHAPES)) throw new IOError.INVALID_ARGUMENT ("unknown shape %s, use one of %s", shape, string.joinv (", ", SHAPES));
            double x = num (args, "x", 100), y = num (args, "y", 100);
            double wd = num (args, "w", 200), ht = num (args, "h", shape == "line" ? 0 : 200);
            var c = w.canvas;
            if (shape == "text") {
                var t = new TextNode ();
                t.style.family = c.style.text.family;
                t.style.size = num (args, "size", c.style.text.size);
                t.text = text (args, "text") != "" ? text (args, "text") : _("Text");
                t.matrix = Transforms.translate (x, y);
                c.style.apply (t, true);
                if (!args.has_member ("stroke")) Commands.apply_paint_node (t, new Paint (), true);
                return t;
            }
            if (wd <= 0 || (ht <= 0 && shape != "line")) throw new IOError.INVALID_ARGUMENT ("w and h must be positive");
            var n = new PathNode ();
            n.live = new LiveShape ();
            n.live.kind = shape == "rounded" ? "rectangle" : shape;
            n.live.radius = shape == "rounded" ? num (args, "radius", 16) : num (args, "radius", 0);
            n.live.sides = (int) num (args, "sides", shape == "star" ? 5 : 6);
            n.live.inner = num (args, "inner", 0.5);
            if (shape == "line") {
                n.live.cx = x;
                n.live.cy = y;
                n.live.x2 = x + wd;
                n.live.y2 = y + ht;
            } else {
                n.live.cx = x + wd / 2;
                n.live.cy = y + ht / 2;
                n.live.w = wd;
                n.live.h = ht;
            }
            n.rebuild_live ();
            c.style.apply (n, shape != "line");
            return n;
        }

        private static void refresh (VectorWindow w, Node? select) {
            if (select != null) w.canvas.select_only (select);
            w.canvas.queue_draw ();
            w.update_title ();
        }

        internal static void install (VectorApp app) {
            var agent = app.agent;

            agent.add_intent ("vector_context", "Describe the illustration: artboards, layers and every object with id, kind, bounds, fill, stroke and text, plus the selection.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => context (window (app)));

            agent.add_intent ("vector_add", "Add a shape (rectangle, rounded, ellipse, polygon, star, line) or a text at x, y with size w, h, colours as #rrggbb or none, stroke width, opacity, sides for polygons and stars, radius for rounded corners, font and size for text, and an optional layer name.",
                "{\"type\":\"object\",\"properties\":{\"shape\":{\"type\":\"string\",\"enum\":[\"rectangle\",\"rounded\",\"ellipse\",\"polygon\",\"star\",\"line\",\"text\"]},\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"},\"w\":{\"type\":\"number\"},\"h\":{\"type\":\"number\"},\"fill\":{\"type\":\"string\"},\"stroke\":{\"type\":\"string\"},\"stroke_width\":{\"type\":\"number\"},\"opacity\":{\"type\":\"number\"},\"sides\":{\"type\":\"integer\"},\"radius\":{\"type\":\"number\"},\"text\":{\"type\":\"string\"},\"font\":{\"type\":\"string\"},\"size\":{\"type\":\"number\"},\"name\":{\"type\":\"string\"},\"layer\":{\"type\":\"string\"}},\"required\":[\"shape\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var n = build (w, args);
                    var doc = w.doc;
                    doc.begin (_("Add Object"));
                    try {
                        style (n, args);
                        layer (w, text (args, "layer")).add (n);
                        doc.ensure_ids ();
                    } catch (Error e) {
                        doc.commit ();
                        doc.undo ();
                        throw e;
                    }
                    doc.commit ();
                    refresh (w, n);
                    return obj (describe (n));
                });

            agent.add_intent ("vector_update", "Change an object by id or name: move it so its top-left is at x, y, resize it to w, h, rotate by degrees, change fill, stroke, stroke width, opacity, name, hidden, text, font or size.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"},\"w\":{\"type\":\"number\"},\"h\":{\"type\":\"number\"},\"rotate\":{\"type\":\"number\"},\"fill\":{\"type\":\"string\"},\"stroke\":{\"type\":\"string\"},\"stroke_width\":{\"type\":\"number\"},\"opacity\":{\"type\":\"number\"},\"name\":{\"type\":\"string\"},\"hidden\":{\"type\":\"boolean\"},\"text\":{\"type\":\"string\"},\"font\":{\"type\":\"string\"},\"size\":{\"type\":\"number\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var n = find (w, args);
                    if (n.locked) throw new IOError.PERMISSION_DENIED ("%s is locked", n.display_name ());
                    var doc = w.doc;
                    doc.begin (_("Edit Object"));
                    try {
                        style (n, args);
                        var b = n.geometric_bounds ();
                        if (args.has_member ("w") || args.has_member ("h")) {
                            double sx = args.has_member ("w") && b.w > 0 ? num (args, "w", b.w) / b.w : 1;
                            double sy = args.has_member ("h") && b.h > 0 ? num (args, "h", b.h) / b.h : 1;
                            if (sx <= 0 || sy <= 0) throw new IOError.INVALID_ARGUMENT ("w and h must be positive");
                            n.apply_transform (Transforms.scale (sx, sy, Point (b.x, b.y)), false);
                            b = n.geometric_bounds ();
                        }
                        if (args.has_member ("rotate")) {
                            n.apply_transform (Transforms.rotate (num (args, "rotate", 0) * Math.PI / 180, Point (b.x + b.w / 2, b.y + b.h / 2)));
                            b = n.geometric_bounds ();
                        }
                        if (args.has_member ("x") || args.has_member ("y")) {
                            n.apply_transform (Transforms.translate (num (args, "x", b.x) - b.x, num (args, "y", b.y) - b.y));
                        }
                    } catch (Error e) {
                        doc.commit ();
                        doc.undo ();
                        throw e;
                    }
                    doc.commit ();
                    refresh (w, n);
                    return obj (describe (n));
                });

            agent.add_intent ("vector_delete", "Delete objects by id or name.",
                "{\"type\":\"object\",\"properties\":{\"ids\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"ids\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var doomed = new Gee.ArrayList<Node> ();
                    foreach (var id in args.get_array_member ("ids").get_elements ()) {
                        var o = new Json.Object ();
                        o.set_string_member ("id", id.get_string ());
                        doomed.add (find (w, o));
                    }
                    w.canvas.clear_selection ();
                    w.doc.begin (_("Delete"));
                    foreach (var n in doomed) if (n.parent != null) n.parent.remove (n);
                    w.doc.commit ();
                    refresh (w, null);
                    return context (w);
                });

            agent.add_intent ("vector_export", "Export the illustration or one artboard (0-based) to PNG, JPEG, SVG or PDF; the format follows the file extension.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"artboard\":{\"type\":\"integer\"},\"scale\":{\"type\":\"number\"},\"transparent\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    var doc = w.doc;
                    string path = text (args, "path");
                    string low = path.down ();
                    int board = args.has_member ("artboard") ? (int) args.get_int_member ("artboard") : (doc.artboards.size > 0 ? doc.active_artboard : -1);
                    if (low.has_suffix (".svg") || low.has_suffix (".svgz")) {
                        Formats.export_svg (doc, path, new SvgOptions ());
                    } else if (low.has_suffix (".pdf")) {
                        var opts = new PdfOptions ();
                        opts.all_artboards = !args.has_member ("artboard");
                        opts.artboard = int.max (board, 0);
                        Export.save_pdf (doc, path, opts);
                    } else if (low.has_suffix (".png") || low.has_suffix (".jpg") || low.has_suffix (".jpeg")) {
                        var area = Export.area_for (doc, board);
                        if (area.w <= 0 || area.h <= 0) throw new IOError.FAILED ("there is nothing to export");
                        Export.save_raster (doc, path, area, num (args, "scale", 1).clamp (0.05, 16), low.has_suffix (".png") ? "png" : "jpeg",
                            args.has_member ("transparent") && args.get_boolean_member ("transparent"));
                    } else {
                        throw new IOError.INVALID_ARGUMENT ("use a .png, .jpg, .svg or .pdf path");
                    }
                    var o = new Json.Object ();
                    o.set_string_member ("file", path);
                    o.set_boolean_member ("verified", FileUtils.test (path, FileTest.EXISTS));
                    return obj (o);
                });

            agent.add_intent ("vector_save", "Save the illustration as Singularity SVG, to its file, a given path, or the Pictures folder.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    var doc = w.doc;
                    string target = text (args, "path");
                    if (target == "") target = doc.path ?? "";
                    if (target == "") {
                        string dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
                        target = Path.build_filename (dir, w.base_name () + ".svg");
                    }
                    if (!target.down ().has_suffix (".svg") && !target.down ().has_suffix (".svgz")) target += ".svg";
                    Formats.save_native (doc, target);
                    doc.path = target;
                    doc.title = Path.get_basename (target);
                    doc.modified = false;
                    w.update_title ();
                    var o = new Json.Object ();
                    o.set_string_member ("file", target);
                    o.set_boolean_member ("verified", FileUtils.test (target, FileTest.EXISTS));
                    return obj (o);
                });
        }
    }
}
