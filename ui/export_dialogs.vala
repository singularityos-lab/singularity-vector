using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class ExportDialogs {
        private static async string? choose_save (VectorWindow win, string title, string name, string suffix, string label) {
            var dialog = new FileDialog ();
            dialog.title = title;
            dialog.initial_name = name + "." + suffix;
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = label;
            f.add_suffix (suffix);
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.save (win, null);
                if (file == null || file.get_path () == null) return null;
                string p = file.get_path ();
                if (!p.down ().has_suffix ("." + suffix)) p += "." + suffix;
                return p;
            } catch (Error e) {
                return null;
            }
        }

        private static async string? choose_folder (VectorWindow win) {
            var dialog = new FileDialog ();
            dialog.title = _("Choose Export Folder");
            try {
                var file = yield dialog.select_folder (win, null);
                return file != null ? file.get_path () : null;
            } catch (Error e) {
                return null;
            }
        }

        public static void svg (VectorWindow win) {
            var doc = win.doc;
            Box body;
            var g = new PreferencesGroup (_("SVG Options"));
            DropDown scope = null, styling = null;
            SpinButton decimals = null;
            Switch minify = null, responsive = null, outlines = null, link = null, native = null;
            var dlg = Forms.form (win, _("Export SVG"), _("Export"), out body, () => {
                var o = new SvgOptions ();
                o.decimals = (int) decimals.value;
                o.styling = styling.selected == 0 ? "attributes" : (styling.selected == 1 ? "inline" : "classes");
                o.minify = minify.active;
                o.responsive = responsive.active;
                o.text_outlines = outlines.active;
                o.link_images = link.active;
                o.native = native.active;
                if (scope.selected == 1) {
                    o.artboard = doc.active_artboard;
                    o.all_artboards = false;
                } else if (scope.selected == 2 && win.canvas.selection.size > 0) {
                    o.only = Commands.ordered (win.canvas);
                    o.area = Export.area_for (doc, -1, o.only);
                    o.native = false;
                }
                choose_save.begin (win, _("Export SVG"), win.base_name (), "svg", _("SVG"), (obj, res) => {
                    string? path = choose_save.end (res);
                    if (path == null) return;
                    try {
                        Formats.export_svg (doc, path, o);
                        win.toast (_("Exported %s").printf (Path.get_basename (path)));
                    } catch (Error e) {
                        Forms.message (win, _("Could Not Export"), e.message);
                    }
                });
            });
            scope = Forms.choice (g, _("Content"), { _("All Artboards"), _("Current Artboard"), _("Selection") }, 0);
            styling = Forms.choice (g, _("Styling"), { _("Presentation Attributes"), _("Inline CSS"), _("Internal CSS Classes") }, 0);
            decimals = Forms.spin (g, _("Decimal Places"), 0, 8, 1, win.settings != null ? win.settings.get_int ("svg-decimals") : 3, 0);
            minify = Forms.toggle (g, _("Minify"), false);
            responsive = Forms.toggle (g, _("Responsive"), false, _("Leave out width and height"));
            outlines = Forms.toggle (g, _("Text as Outlines"), false);
            link = Forms.toggle (g, _("Link Images"), false);
            native = Forms.toggle (g, _("Keep Vector Editing Data"), false, _("Lets Vector reopen live shapes, effects and symbols"));
            body.append (g);
            dlg.present ();
        }

        public static void screens (VectorWindow win) {
            var doc = win.doc;
            Box body;
            var g = new PreferencesGroup (_("Export for Screens"));
            DropDown scope = null;
            Switch png = null, jpg = null, webp = null, svg_f = null, pdf = null, transparent = null, s1 = null, s2 = null, s3 = null, s05 = null;
            Entry prefix = null;
            var dlg = Forms.form (win, _("Export for Screens"), _("Export"), out body, () => {
                choose_folder.begin (win, (obj, res) => {
                    string? dir = choose_folder.end (res);
                    if (dir == null) return;
                    double[] scales = {};
                    if (s05.active) scales += 0.5;
                    if (s1.active) scales += 1;
                    if (s2.active) scales += 2;
                    if (s3.active) scales += 3;
                    string[] formats = {};
                    if (png.active) formats += "png";
                    if (jpg.active) formats += "jpeg";
                    if (webp.active) formats += "webp";
                    if (svg_f.active) formats += "svg";
                    if (pdf.active) formats += "pdf";
                    try {
                        int count = ScreenExport.run (doc, win.canvas, dir, prefix.text, (int) scope.selected, scales, formats, transparent.active);
                        win.toast (ngettext ("%d file exported", "%d files exported", count).printf (count));
                    } catch (Error e) {
                        Forms.message (win, _("Could Not Export"), e.message);
                    }
                });
            });
            scope = Forms.choice (g, _("Export"), { _("All Artboards"), _("Current Artboard"), _("Selected Objects as Assets") }, 0);
            prefix = Forms.entry (g, _("File Name Prefix"), "");
            var sg = new PreferencesGroup (_("Scales"));
            s05 = Forms.toggle (sg, "0.5x", false);
            s1 = Forms.toggle (sg, "1x", true);
            s2 = Forms.toggle (sg, "2x", true);
            s3 = Forms.toggle (sg, "3x", false);
            var fg = new PreferencesGroup (_("Formats"));
            png = Forms.toggle (fg, "PNG", true);
            jpg = Forms.toggle (fg, "JPEG", false);
            webp = Forms.toggle (fg, "WebP", false);
            svg_f = Forms.toggle (fg, "SVG", true);
            pdf = Forms.toggle (fg, "PDF", false);
            transparent = Forms.toggle (fg, _("Transparent Background"), true);
            body.append (g);
            body.append (sg);
            body.append (fg);
            dlg.present ();
        }

        public static void pdf (VectorWindow win) {
            var doc = win.doc;
            Box body;
            var g = new PreferencesGroup (_("PDF Options"));
            DropDown scope = null, standard = null;
            SpinButton bleed = null;
            Switch marks = null, doc_bleed = null;
            var dlg = Forms.form (win, _("Export PDF"), _("Export"), out body, () => {
                var o = new PdfOptions ();
                o.all_artboards = scope.selected == 0;
                o.artboard = doc.active_artboard;
                o.crop_marks = marks.active;
                o.use_doc_bleed = doc_bleed.active;
                o.bleed = bleed.value * 96 / 25.4;
                string[] std = { "none", "PDF/X-1a", "PDF/X-3", "PDF/X-4" };
                o.standard = std[standard.selected];
                choose_save.begin (win, _("Export PDF"), win.base_name (), "pdf", _("PDF"), (obj, res) => {
                    string? path = choose_save.end (res);
                    if (path == null) return;
                    try {
                        Export.save_pdf (doc, path, o);
                        win.toast (_("Exported %s").printf (Path.get_basename (path)));
                    } catch (Error e) {
                        Forms.message (win, _("Could Not Export"), e.message);
                    }
                });
            });
            scope = Forms.choice (g, _("Artboards"), { _("All"), _("Current") }, 0);
            standard = Forms.choice (g, _("Standard"), { _("None"), "PDF/X-1a:2003", "PDF/X-3:2003", "PDF/X-4" }, 0);
            doc_bleed = Forms.toggle (g, _("Use Document Bleed"), true);
            bleed = Forms.spin (g, _("Bleed"), 0, 50, 0.5, 3, 1, _("mm"));
            marks = Forms.toggle (g, _("Crop Marks"), false);
            body.append (g);
            g.description = (_("Spot colors become separation colors and overprint settings are kept in the PDF. %s").printf (ColorManager.get_default ().has_profile () ? _("CMYK conversion uses %s.").printf (ColorManager.get_default ().profile_name ()) : _("No CMYK profile is installed, so a built-in conversion is used.")));
            dlg.present ();
        }

        public static void raster (VectorWindow win) {
            var doc = win.doc;
            Box body;
            var g = new PreferencesGroup (_("Image Options"));
            DropDown format = null, scope = null, color = null;
            SpinButton dpi = null, quality = null;
            Switch transparent = null, aa = null;
            string[] formats = { "png", "jpeg", "webp", "tiff" };
            var dlg = Forms.form (win, _("Export Image"), _("Export"), out body, () => {
                string fmt = formats[format.selected];
                string suffix = fmt == "jpeg" ? "jpg" : (fmt == "tiff" ? "tif" : fmt);
                choose_save.begin (win, _("Export Image"), win.base_name (), suffix, fmt.up (), (obj, res) => {
                    string? path = choose_save.end (res);
                    if (path == null) return;
                    try {
                        Gee.List<Node>? only = scope.selected == 2 ? Commands.ordered (win.canvas) : null;
                        var area = scope.selected == 0 ? doc.current_artboard ().rect () : (scope.selected == 1 ? doc.content_bounds () : Export.area_for (doc, -1, only));
                        Export.save_raster (doc, path, area, dpi.value / 96, fmt, transparent.active, only, (int) quality.value, color.selected == 1, aa.active);
                        win.toast (_("Exported %s").printf (Path.get_basename (path)));
                    } catch (Error e) {
                        Forms.message (win, _("Could Not Export"), e.message);
                    }
                });
            });
            format = Forms.choice (g, _("Format"), { "PNG", "JPEG", "WebP", "TIFF" }, 0);
            scope = Forms.choice (g, _("Area"), { _("Current Artboard"), _("All Artwork"), _("Selection") }, 0);
            dpi = Forms.spin (g, _("Resolution"), 10, 2400, 12, 144, 0, _("pixels per inch"));
            quality = Forms.spin (g, _("Quality"), 1, 100, 1, 92, 0);
            transparent = Forms.toggle (g, _("Transparent Background"), true);
            aa = Forms.toggle (g, _("Anti-aliasing"), true);
            color = Forms.choice (g, _("Color"), { _("RGB"), _("CMYK (TIFF only)") }, doc.color_mode == "cmyk" ? 1 : 0);
            body.append (g);
            dlg.present ();
        }

        public static void other (VectorWindow win, string kind) {
            var doc = win.doc;
            string suffix = kind;
            string label = kind.up ();
            choose_save.begin (win, _("Export %s").printf (label), win.base_name (), suffix, label, (obj, res) => {
                string? path = choose_save.end (res);
                if (path == null) return;
                try {
                    switch (kind) {
                        case "dxf":
                            Dxf.write (doc, path, doc.current_artboard ().rect ());
                            break;
                        case "eps":
                            Export.save_eps (doc, path, doc.active_artboard);
                            break;
                        case "odg":
                            DrawExchange.export_odg (doc, path, -1);
                            break;
                        case "svgz":
                            var o = new SvgOptions ();
                            o.native = false;
                            Formats.export_svg (doc, path, o);
                            break;
                    }
                    win.toast (_("Exported %s").printf (Path.get_basename (path)));
                } catch (Error e) {
                    Forms.message (win, _("Could Not Export"), e.message);
                }
            });
        }

        public static void print (VectorWindow win) {
            var doc = win.doc;
            var src = new Singularity.Print.CallbackSource (doc.title, (format) => doc.artboards.size, (cr, page, format) => {
                if (page < 0 || page >= doc.artboards.size) return;
                var a = doc.artboards[page];
                double pw = format.width, ph = format.height;
                double fit = double.min (1, double.min (pw / (a.w * 0.75), ph / (a.h * 0.75)));
                double s = 0.75 * fit;
                cr.save ();
                cr.translate ((pw - a.w * s) / 2, (ph - a.h * s) / 2);
                cr.scale (s, s);
                cr.translate (-a.x, -a.y);
                cr.rectangle (a.x, a.y, a.w, a.h);
                cr.clip ();
                var ctx = new RenderContext (doc);
                ctx.print = true;
                ctx.hide_templates = true;
                Renderer.draw_document (cr, ctx);
                cr.restore ();
            });
            src.current_page = doc.active_artboard;
            Singularity.Print.run_source.begin (win, src);
        }
    }

    public class ScreenExport {
        public static int run (VectorDocument doc, VectorCanvas canvas, string dir, string prefix, int scope, double[] scales, string[] formats, bool transparent) throws Error {
            int count = 0;
            var jobs = new Gee.ArrayList<string> ();
            var areas = new Gee.ArrayList<Rect?> ();
            var onlys = new Gee.ArrayList<Gee.List<Node>?> ();
            if (scope == 2) {
                foreach (var n in Commands.ordered (canvas)) {
                    var one = new Gee.ArrayList<Node> ();
                    one.add (n);
                    jobs.add (safe (n.display_name ()));
                    areas.add (n.visual_bounds ());
                    onlys.add (one);
                }
            } else {
                for (int i = 0; i < doc.artboards.size; i++) {
                    if (scope == 1 && i != doc.active_artboard) continue;
                    jobs.add (safe (doc.artboards[i].name));
                    areas.add (doc.artboards[i].rect ());
                    onlys.add (null);
                }
            }
            for (int j = 0; j < jobs.size; j++) {
                string base_name = prefix + jobs[j];
                var area = areas[j];
                foreach (var fmt in formats) {
                    if (fmt == "svg" || fmt == "pdf") {
                        string path = Path.build_filename (dir, base_name + "." + fmt);
                        if (fmt == "svg") {
                            var o = new SvgOptions ();
                            o.native = false;
                            o.area = area;
                            o.only = onlys[j];
                            Formats.export_svg (doc, path, o);
                        } else {
                            int ab = scope == 2 ? -1 : (scope == 1 ? doc.active_artboard : find (doc, area));
                            var o = new PdfOptions ();
                            o.all_artboards = false;
                            o.artboard = ab >= 0 ? ab : 0;
                            Export.save_pdf (doc, path, o);
                        }
                        count++;
                        continue;
                    }
                    foreach (double s in scales) {
                        string suffix = "";
                        if (s == 0.5) suffix = "@0.5x";
                        else if (s != 1) suffix = "@" + ((int) s).to_string () + "x";
                        string ext = fmt == "jpeg" ? "jpg" : fmt;
                        string path = Path.build_filename (dir, base_name + suffix + "." + ext);
                        Export.save_raster (doc, path, area, s, fmt, transparent, onlys[j]);
                        count++;
                    }
                }
            }
            return count;
        }

        private static int find (VectorDocument doc, Rect r) {
            for (int i = 0; i < doc.artboards.size; i++) {
                var a = doc.artboards[i];
                if (a.x == r.x && a.y == r.y && a.w == r.w && a.h == r.h) return i;
            }
            return -1;
        }

        public static string safe (string name) {
            var b = new StringBuilder ();
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) b.append_unichar (c.isalnum () || c == '-' || c == '_' ? c : '-');
            return b.str != "" ? b.str : "artboard";
        }
    }
}
