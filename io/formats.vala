using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Formats {
        public static string[] open_suffixes () {
            return { "svg", "svgz", "pdf", "ai", "eps", "ps", "dxf", "odg", "fodg", "sdraw", "vsdx", "png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff" };
        }

        public static Gtk.FileFilter open_filter () {
            var f = new Gtk.FileFilter ();
            f.name = _("Supported Files");
            foreach (var s in open_suffixes ()) f.add_suffix (s);
            return f;
        }

        public static bool is_native (string path) {
            string l = path.down ();
            return l.has_suffix (".svg") || l.has_suffix (".svgz");
        }

        public static string mime_for (string path) {
            string l = path.down ();
            if (l.has_suffix (".jpg") || l.has_suffix (".jpeg")) return "image/jpeg";
            if (l.has_suffix (".webp")) return "image/webp";
            if (l.has_suffix (".gif")) return "image/gif";
            if (l.has_suffix (".bmp")) return "image/bmp";
            if (l.has_suffix (".tif") || l.has_suffix (".tiff")) return "image/tiff";
            return "image/png";
        }

        public static VectorDocument open (string path) throws Error {
            string l = path.down ();
            string dir = Path.get_dirname (path);
            if (l.has_suffix (".svg")) {
                string text;
                FileUtils.get_contents (path, out text);
                return SvgReader.parse (text, dir);
            }
            if (l.has_suffix (".svgz")) {
                uint8[] data;
                FileUtils.get_data (path, out data);
                var raw = Gzip.decompress (data);
                return SvgReader.parse (((string) raw).substring (0, raw.length), dir);
            }
            if (l.has_suffix (".pdf")) return PdfImport.load (path);
            if (l.has_suffix (".ai")) return PdfImport.load_ai (path);
            if (l.has_suffix (".eps") || l.has_suffix (".ps")) return PdfImport.load_postscript (path);
            if (l.has_suffix (".dxf")) return Dxf.read (path);
            if (l.has_suffix (".odg") || l.has_suffix (".fodg") || l.has_suffix (".sdraw") || l.has_suffix (".vsdx")) return DrawExchange.open (path);
            return image_document (path);
        }

        public static VectorDocument image_document (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var pix = new Gdk.Pixbuf.from_file (path);
            var d = VectorDocument.blank (pix.width, pix.height);
            var im = new ImageNode ();
            string mime = mime_for (path);
            if (mime == "image/tiff" || mime == "image/bmp" || mime == "image/gif") {
                uint8[] png;
                pix.save_to_buffer (out png, "png");
                data = png;
                mime = "image/png";
            }
            im.asset = d.store_asset (new Bytes (data), mime);
            im.mime = mime;
            im.pixel_width = pix.width;
            im.pixel_height = pix.height;
            d.active_layer.add (im);
            d.ensure_ids ();
            d.title = Path.get_basename (path);
            d.modified = false;
            return d;
        }

        public static void save_native (VectorDocument d, string path, int decimals = 3) throws Error {
            var o = new SvgOptions ();
            o.decimals = int.max (decimals, 3);
            o.native = true;
            string svg = SvgWriter.write (d, o);
            if (path.down ().has_suffix (".svgz")) {
                FileUtils.set_data (path, Gzip.compress (svg.data));
            } else {
                FileUtils.set_contents (path, svg);
            }
        }

        public static void export_svg (VectorDocument d, string path, SvgOptions o) throws Error {
            string svg = SvgWriter.write (d, o);
            if (path.down ().has_suffix (".svgz")) FileUtils.set_data (path, Gzip.compress (svg.data));
            else FileUtils.set_contents (path, svg);
        }
    }

    public class ColorConvert {
        public static void document_to_cmyk (VectorDocument d) {
            foreach (var s in d.swatches) convert_paint (s.paint);
            foreach (var n in d.all_nodes ()) convert_node (n);
            foreach (var s in d.symbols) s.art.walk ((n) => {
                convert_node (n);
                return true;
            });
        }

        private static void convert_node (Node n) {
            foreach (var l in n.appearance) convert_paint (l.paint);
            var me = n as MeshNode;
            if (me != null) foreach (var v in me.vertices) cmyk (v.color);
        }

        private static void convert_paint (Paint p) {
            cmyk (p.color);
            foreach (var s in p.gradient.stops) cmyk (s.color);
            foreach (var f in p.freeform) cmyk (f.color);
        }

        private static void cmyk (Ink ink) {
            if (ink.has_cmyk) return;
            ink.ensure_cmyk ();
            var r = new Ink.cmyk (ink.c, ink.m, ink.y, ink.k);
            ink.has_cmyk = true;
            ink.r = r.r;
            ink.g = r.g;
            ink.b = r.b;
        }
    }

    public class ImageTrace {
        public static Node? trace_node (VectorDocument doc, ImageNode im, TraceOptions opts) {
            var raw_surface = Renderer.image_surface (im, doc);
            if (raw_surface == null) return null;
            var surface = (Cairo.ImageSurface) raw_surface;
            int w = surface.get_width (), h = surface.get_height ();
            double scale = 1;
            if (w * h > 1600 * 1600) scale = Math.sqrt (1600.0 * 1600 / (w * h));
            int sw = int.max (1, (int) (w * scale)), sh = int.max (1, (int) (h * scale));
            var small = new Cairo.ImageSurface (Cairo.Format.ARGB32, sw, sh);
            var cr = new Cairo.Context (small);
            cr.scale (scale, scale);
            cr.set_source_surface (surface, 0, 0);
            cr.paint ();
            small.flush ();
            int stride = small.get_stride ();
            unowned uint8[] raw = small.get_data ();
            var rgba = new uint8[sw * sh * 4];
            for (int y = 0; y < sh; y++) {
                for (int x = 0; x < sw; x++) {
                    int o = y * stride + x * 4;
                    int t = (y * sw + x) * 4;
                    int a = raw[o + 3];
                    rgba[t] = (uint8) (a > 0 ? (raw[o + 2] * 255 / a).clamp (0, 255) : 0);
                    rgba[t + 1] = (uint8) (a > 0 ? (raw[o + 1] * 255 / a).clamp (0, 255) : 0);
                    rgba[t + 2] = (uint8) (a > 0 ? (raw[o] * 255 / a).clamp (0, 255) : 0);
                    rgba[t + 3] = (uint8) a;
                }
            }
            var layers = BitmapTrace.trace (rgba, sw, sh, sw * 4, opts);
            var g = new GroupNode ();
            g.name = _("Image Tracing");
            var to_doc = Cairo.Matrix (1 / scale * im.pixel_width / (double) w, 0, 0, 1 / scale * im.pixel_height / (double) h, 0, 0);
            to_doc = Transforms.multiply (to_doc, im.matrix);
            foreach (var l in layers) {
                var pn = new PathNode.with_path (l.path);
                pn.path.transform (to_doc);
                pn.appearance.add (new PaintLayer.fill (new Paint.solid (new Ink.rgb (l.r, l.g, l.b))));
                g.add (pn);
            }
            return g;
        }

        public static void run (VectorCanvas c, ImageNode im, TraceOptions opts) {
            var node = trace_node (c.doc, im, opts);
            if (node == null) return;
            c.doc.begin (_("Image Trace"));
            var parent = im.parent;
            int index = parent.children.index_of (im);
            parent.remove (im);
            parent.add (node, index);
            c.doc.ensure_ids ();
            c.doc.commit ();
            c.select_only (node);
        }
    }
}
