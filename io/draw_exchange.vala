namespace Singularity.Apps.Vector {

    public class DrawExchange {
        public const string DRAW_MIME = "application/x-singularity-draw";

        public static VectorDocument open (string path) throws Error {
            var draw = Singularity.Apps.Draw.Formats.load (path);
            VectorDocument? result = null;
            double offset = 0;
            foreach (var page in draw.pages) {
                var area = Singularity.Apps.Draw.SvgWriter.page_area (page);
                string svg = Singularity.Apps.Draw.SvgWriter.write_page (page, area, true);
                var part = SvgReader.parse (svg, Path.get_dirname (path));
                if (result == null) {
                    result = part;
                    result.artboards[0].name = page.name != "" ? page.name : result.artboards[0].name;
                    offset = result.artboards[0].h + 60;
                    continue;
                }
                var a = part.artboards[0];
                var shift = Transforms.translate (0, offset);
                var board = new Artboard (page.name != "" ? page.name : _("Page %d").printf (result.artboards.size + 1), a.x, a.y + offset, a.w, a.h);
                result.add_artboard (board);
                foreach (var l in part.layers) {
                    l.apply_transform (shift, false);
                    l.name = "%s %s".printf (board.name, l.name);
                    Commands.clear_ids (l);
                    result.layers.add (l);
                }
                foreach (var asset in part.assets.values) result.assets[asset.id] = asset;
                offset += a.h + 60;
            }
            if (result == null) throw new IOError.INVALID_DATA (_("The drawing has no pages."));
            result.title = Path.get_basename (path);
            result.relink ();
            result.ensure_ids ();
            result.modified = false;
            return result;
        }

        public static void export_odg (VectorDocument doc, string path, int artboard) throws Error {
            var draw = new Singularity.Apps.Draw.Document ();
            bool first = true;
            for (int i = 0; i < doc.artboards.size; i++) {
                if (artboard >= 0 && i != artboard) continue;
                var o = new SvgOptions ();
                o.native = false;
                o.artboard = i;
                o.all_artboards = false;
                o.text_outlines = false;
                string svg = SvgWriter.write (doc, o);
                var part = Singularity.Apps.Draw.SvgReader.load (svg);
                if (first) {
                    draw = part;
                    draw.page.name = doc.artboards[i].name;
                    first = false;
                    continue;
                }
                var page = draw.add_page (-1, doc.artboards[i].name);
                page.width = part.page.width;
                page.height = part.page.height;
                foreach (var it in part.page.items) page.items.add (it);
                foreach (var layer in part.page.layers) {
                    bool exists = false;
                    foreach (var l in page.layers) if (l.id == layer.id) exists = true;
                    if (!exists) page.layers.add (layer);
                }
            }
            draw.ensure_ids ();
            Singularity.Apps.Draw.Formats.save (draw, path);
        }

        public static Gee.ArrayList<Node>? nodes_from_draw (string native, VectorDocument doc) {
            try {
                var items = Singularity.Apps.Draw.NativeFormat.parse_items (native);
                var temp = new Singularity.Apps.Draw.Document ();
                foreach (var it in items) temp.page.items.add (it);
                var area = Singularity.Apps.Draw.SvgWriter.content_area (temp.page, items, 0);
                string svg = Singularity.Apps.Draw.SvgWriter.write_page (temp.page, area, false, items);
                var part = SvgReader.parse (svg);
                var list = new Gee.ArrayList<Node> ();
                var shift = Transforms.translate (area.x, area.y);
                foreach (var l in part.layers) foreach (var n in l.children) list.add (n);
                foreach (var n in list) {
                    if (n.parent != null) n.parent.remove (n);
                    n.apply_transform (shift, false);
                }
                foreach (var a in part.assets.values) doc.assets[a.id] = a;
                return list;
            } catch (Error e) {
                return null;
            }
        }
    }
}
