namespace Singularity.Apps.Vector {

    public class Palettes {
        public static string[] names () {
            return { _("Earth Tones"), _("Pastels"), _("Grays"), _("Brights"), _("Process CMYK"), _("Spot Inks") };
        }

        private static string[] colors (int index) {
            switch (index) {
                case 0: return { "#5b3a29", "#8b5a2b", "#a0522d", "#c19a6b", "#d2b48c", "#6b8e23", "#556b2f", "#8f9779" };
                case 1: return { "#ffd1dc", "#ffb7c5", "#c1e1c1", "#aec6cf", "#cfcfc4", "#fdfd96", "#b39eb5", "#ffdab9" };
                case 2: return { "#111111", "#333333", "#555555", "#777777", "#999999", "#bbbbbb", "#dddddd", "#f4f4f4" };
                case 3: return { "#ff0055", "#ff7a00", "#ffe600", "#00d26a", "#00b3ff", "#5b4bff", "#c200ff", "#ff00b8" };
                default: return {};
            }
        }

        public static void add_library (VectorDocument doc, int index) {
            string group = names ()[index];
            if (index == 4) {
                double[,] cmyk = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 }, { 1, 1, 0, 0 }, { 0, 1, 1, 0 }, { 1, 0, 1, 0 }, { 0.6, 0.4, 0.4, 1 } };
                string[] labels = { "C", "M", "Y", "K", "C+M", "M+Y", "C+Y", _("Rich Black") };
                for (int i = 0; i < labels.length; i++) {
                    var s = new Swatch (labels[i], new Paint.solid (new Ink.cmyk (cmyk[i, 0], cmyk[i, 1], cmyk[i, 2], cmyk[i, 3])));
                    s.id = doc.new_id ("sw");
                    s.group = group;
                    doc.swatches.add (s);
                }
                return;
            }
            if (index == 5) {
                string[,] inks = { { "Signal Red", "#d7282f", "0,0.95,0.85,0.05" }, { "Warm Yellow", "#ffcd00", "0,0.15,1,0" }, { "Process Blue", "#0085ca", "1,0.2,0,0" }, { "Deep Green", "#00843d", "0.9,0,0.95,0.2" }, { "Metallic Gold", "#b39b62", "0.3,0.35,0.7,0.05" }, { "Cool Gray", "#8a8d8f", "0,0,0,0.55" } };
                for (int i = 0; i < inks.length[0]; i++) {
                    var v = inks[i, 2].split (",");
                    var ink = new Ink.cmyk (double.parse (v[0]), double.parse (v[1]), double.parse (v[2]), double.parse (v[3]));
                    ink.set_hex (inks[i, 1]);
                    ink.has_cmyk = true;
                    ink.c = double.parse (v[0]);
                    ink.m = double.parse (v[1]);
                    ink.y = double.parse (v[2]);
                    ink.k = double.parse (v[3]);
                    ink.spot = inks[i, 0];
                    var s = new Swatch (inks[i, 0], new Paint.solid (ink));
                    s.id = doc.new_id ("sw");
                    s.group = group;
                    s.is_global = true;
                    doc.swatches.add (s);
                }
                return;
            }
            foreach (var hex in colors (index)) {
                var s = new Swatch (hex, new Paint.hex (hex));
                s.id = doc.new_id ("sw");
                s.group = group;
                doc.swatches.add (s);
            }
        }

        public static int import_gpl (VectorDocument doc, string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            if (!text.has_prefix ("GIMP Palette")) throw new IOError.INVALID_DATA (_("This is not a GIMP palette file."));
            string group = Path.get_basename (path);
            int count = 0;
            foreach (var line in text.split ("\n")) {
                string l = line.strip ();
                if (l.has_prefix ("Name:")) {
                    group = l.substring (5).strip ();
                    continue;
                }
                if (l == "" || l.has_prefix ("#") || l.has_prefix ("GIMP") || l.has_prefix ("Columns:")) continue;
                var parts = l.replace ("\t", " ").split (" ");
                int[] v = {};
                string name = "";
                foreach (var p in parts) {
                    if (p == "") continue;
                    if (v.length < 3) v += int.parse (p);
                    else name += (name == "" ? "" : " ") + p;
                }
                if (v.length < 3) continue;
                var ink = new Ink.rgb (v[0] / 255.0, v[1] / 255.0, v[2] / 255.0);
                var s = new Swatch (name != "" ? name : ink.to_hex (), new Paint.solid (ink));
                s.id = doc.new_id ("sw");
                s.group = group;
                doc.swatches.add (s);
                count++;
            }
            return count;
        }

        public static void export_gpl (VectorDocument doc, string path) throws Error {
            var b = new StringBuilder ("GIMP Palette\nName: %s\nColumns: 8\n#\n".printf (doc.title));
            foreach (var s in doc.swatches) {
                if (s.paint.kind != PaintKind.SOLID) continue;
                var c = s.paint.color;
                b.append ("%3d %3d %3d\t%s\n".printf ((int) Math.round (c.r * 255), (int) Math.round (c.g * 255), (int) Math.round (c.b * 255), s.name));
            }
            FileUtils.set_contents (path, b.str);
        }
    }
}
