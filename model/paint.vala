using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public enum BlendMode {
        NORMAL, DARKEN, MULTIPLY, COLOR_BURN, LIGHTEN, SCREEN, COLOR_DODGE, OVERLAY, SOFT_LIGHT, HARD_LIGHT, DIFFERENCE, EXCLUSION, HUE, SATURATION, COLOR, LUMINOSITY;

        public static string[] ids () {
            return { "normal", "darken", "multiply", "color-burn", "lighten", "screen", "color-dodge", "overlay", "soft-light", "hard-light", "difference", "exclusion", "hue", "saturation", "color", "luminosity" };
        }

        public static string[] labels () {
            return { _("Normal"), _("Darken"), _("Multiply"), _("Color Burn"), _("Lighten"), _("Screen"), _("Color Dodge"), _("Overlay"), _("Soft Light"), _("Hard Light"), _("Difference"), _("Exclusion"), _("Hue"), _("Saturation"), _("Color"), _("Luminosity") };
        }

        public string to_id () {
            return ids ()[(int) this];
        }

        public static BlendMode from_id (string? id) {
            var list = ids ();
            for (int i = 0; i < list.length; i++) if (list[i] == id) return (BlendMode) i;
            return NORMAL;
        }

        public Cairo.Operator to_operator () {
            switch (this) {
                case DARKEN: return Cairo.Operator.DARKEN;
                case MULTIPLY: return Cairo.Operator.MULTIPLY;
                case COLOR_BURN: return Cairo.Operator.COLOR_BURN;
                case LIGHTEN: return Cairo.Operator.LIGHTEN;
                case SCREEN: return Cairo.Operator.SCREEN;
                case COLOR_DODGE: return Cairo.Operator.COLOR_DODGE;
                case OVERLAY: return Cairo.Operator.OVERLAY;
                case SOFT_LIGHT: return Cairo.Operator.SOFT_LIGHT;
                case HARD_LIGHT: return Cairo.Operator.HARD_LIGHT;
                case DIFFERENCE: return Cairo.Operator.DIFFERENCE;
                case EXCLUSION: return Cairo.Operator.EXCLUSION;
                case HUE: return Cairo.Operator.HSL_HUE;
                case SATURATION: return Cairo.Operator.HSL_SATURATION;
                case COLOR: return Cairo.Operator.HSL_COLOR;
                case LUMINOSITY: return Cairo.Operator.HSL_LUMINOSITY;
                default: return Cairo.Operator.OVER;
            }
        }
    }

    public class Ink : Object {
        public double r = 0;
        public double g = 0;
        public double b = 0;
        public bool has_cmyk = false;
        public double c = 0;
        public double m = 0;
        public double y = 0;
        public double k = 1;
        public string spot = "";
        public double tint = 1;
        public string swatch = "";

        public Ink.rgb (double r, double g, double b) {
            this.r = r.clamp (0, 1);
            this.g = g.clamp (0, 1);
            this.b = b.clamp (0, 1);
        }

        public Ink.cmyk (double c, double m, double y, double k) {
            has_cmyk = true;
            this.c = c.clamp (0, 1);
            this.m = m.clamp (0, 1);
            this.y = y.clamp (0, 1);
            this.k = k.clamp (0, 1);
            ColorManager.get_default ().cmyk_to_rgb (this.c, this.m, this.y, this.k, out this.r, out this.g, out this.b);
        }

        public static Ink hex (string text) {
            var ink = new Ink ();
            ink.set_hex (text);
            return ink;
        }

        public bool set_hex (string text) {
            string s = text.strip ();
            if (s.has_prefix ("#")) s = s.substring (1);
            if (s.length == 3) s = "%c%c%c%c%c%c".printf (s[0], s[0], s[1], s[1], s[2], s[2]);
            if (s.length < 6) return false;
            int64 v;
            if (!int64.try_parse ("0x" + s.substring (0, 6), out v)) {
                uint64 u;
                if (!uint64.try_parse (s.substring (0, 6), out u, null, 16)) return false;
                v = (int64) u;
            }
            r = ((v >> 16) & 0xff) / 255.0;
            g = ((v >> 8) & 0xff) / 255.0;
            b = (v & 0xff) / 255.0;
            has_cmyk = false;
            return true;
        }

        public string to_hex () {
            return "#%02x%02x%02x".printf ((int) Math.round (r * 255), (int) Math.round (g * 255), (int) Math.round (b * 255));
        }

        public Ink copy () {
            var o = new Ink ();
            o.r = r;
            o.g = g;
            o.b = b;
            o.has_cmyk = has_cmyk;
            o.c = c;
            o.m = m;
            o.y = y;
            o.k = k;
            o.spot = spot;
            o.tint = tint;
            o.swatch = swatch;
            return o;
        }

        public bool same (Ink o) {
            return (r - o.r).abs () < 0.002 && (g - o.g).abs () < 0.002 && (b - o.b).abs () < 0.002 && spot == o.spot;
        }

        public void ensure_cmyk () {
            if (has_cmyk) return;
            ColorManager.get_default ().rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
        }

        public double luminance () {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        public void to_hsl (out double h, out double s, out double l) {
            double max = double.max (r, double.max (g, b)), min = double.min (r, double.min (g, b));
            l = (max + min) / 2;
            h = s = 0;
            if (max - min < 1e-9) return;
            double d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max == r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }

        public static Ink from_hsl (double h, double s, double l) {
            h = h - Math.floor (h);
            if (s <= 0) return new Ink.rgb (l, l, l);
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            double p = 2 * l - q;
            return new Ink.rgb (hue (p, q, h + 1.0 / 3), hue (p, q, h), hue (p, q, h - 1.0 / 3));
        }

        private static double hue (double p, double q, double t) {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6) return p + (q - p) * 6 * t;
            if (t < 0.5) return q;
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
            return p;
        }
    }

    public class GradientStop : Object {
        public double offset;
        public Ink color;
        public double opacity = 1;
        public double midpoint = 0.5;

        public GradientStop (double offset, Ink color, double opacity = 1) {
            this.offset = offset;
            this.color = color;
            this.opacity = opacity;
        }

        public GradientStop copy () {
            var s = new GradientStop (offset, color.copy (), opacity);
            s.midpoint = midpoint;
            return s;
        }
    }

    public class Gradient : Object {
        public Gee.ArrayList<GradientStop> stops = new Gee.ArrayList<GradientStop> ();
        public double x1 = 0;
        public double y1 = 0.5;
        public double x2 = 1;
        public double y2 = 0.5;
        public double radius = 0.5;
        public double fx = 0.5;
        public double fy = 0.5;
        public double aspect = 1;
        public string spread = "pad";

        public Gradient () {
        }

        public Gradient.two (Ink a, Ink b) {
            stops.add (new GradientStop (0, a));
            stops.add (new GradientStop (1, b));
        }

        public Gradient copy () {
            var g = new Gradient ();
            foreach (var s in stops) g.stops.add (s.copy ());
            g.x1 = x1;
            g.y1 = y1;
            g.x2 = x2;
            g.y2 = y2;
            g.radius = radius;
            g.fx = fx;
            g.fy = fy;
            g.aspect = aspect;
            g.spread = spread;
            return g;
        }

        public void sort () {
            stops.sort ((a, b) => a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
        }

        public void reverse () {
            foreach (var s in stops) s.offset = 1 - s.offset;
            sort ();
        }
    }

    public class FreeformPoint : Object {
        public double x;
        public double y;
        public Ink color;
        public double spread = 0.6;

        public FreeformPoint (double x, double y, Ink color) {
            this.x = x;
            this.y = y;
            this.color = color;
        }

        public FreeformPoint copy () {
            var p = new FreeformPoint (x, y, color.copy ());
            p.spread = spread;
            return p;
        }
    }

    public enum PaintKind {
        NONE, SOLID, LINEAR, RADIAL, FREEFORM, PATTERN;

        public string to_id () {
            string[] names = { "none", "solid", "linear", "radial", "freeform", "pattern" };
            return names[(int) this];
        }

        public static PaintKind from_id (string? id) {
            switch (id) {
                case "solid": return SOLID;
                case "linear": return LINEAR;
                case "radial": return RADIAL;
                case "freeform": return FREEFORM;
                case "pattern": return PATTERN;
                default: return NONE;
            }
        }
    }

    public class Paint : Object {
        public PaintKind kind = PaintKind.NONE;
        public Ink color = new Ink ();
        public Gradient gradient = new Gradient ();
        public Gee.ArrayList<FreeformPoint> freeform = new Gee.ArrayList<FreeformPoint> ();
        public string pattern = "";
        public Cairo.Matrix pattern_matrix;
        public bool overprint = false;

        public Paint () {
            pattern_matrix = Cairo.Matrix.identity ();
        }

        public Paint.none () {
            this ();
        }

        public Paint.solid (Ink ink) {
            this ();
            kind = PaintKind.SOLID;
            color = ink;
        }

        public Paint.hex (string hex) {
            this.solid (Ink.hex (hex));
        }

        public bool visible () {
            return kind != PaintKind.NONE;
        }

        public Paint copy () {
            var p = new Paint ();
            p.kind = kind;
            p.color = color.copy ();
            p.gradient = gradient.copy ();
            foreach (var f in freeform) p.freeform.add (f.copy ());
            p.pattern = pattern;
            p.pattern_matrix = pattern_matrix;
            p.overprint = overprint;
            return p;
        }

        public Ink representative () {
            if (kind == PaintKind.LINEAR || kind == PaintKind.RADIAL) {
                if (gradient.stops.size > 0) return gradient.stops[0].color;
            }
            if (kind == PaintKind.FREEFORM && freeform.size > 0) return freeform[0].color;
            return color;
        }
    }

    public class Effect : Object {
        public string kind;
        public bool enabled = true;
        public Gee.HashMap<string, double?> num = new Gee.HashMap<string, double?> ();
        public Gee.HashMap<string, string> str = new Gee.HashMap<string, string> ();

        public Effect (string kind) {
            this.kind = kind;
        }

        public double get_num (string key, double fallback) {
            return num.has_key (key) && num[key] != null ? num[key] : fallback;
        }

        public string get_str (string key, string fallback) {
            return str.has_key (key) ? str[key] : fallback;
        }

        public Effect set_num (string key, double value) {
            num[key] = value;
            return this;
        }

        public Effect set_str (string key, string value) {
            str[key] = value;
            return this;
        }

        public Effect copy () {
            var e = new Effect (kind);
            e.enabled = enabled;
            foreach (var kv in num.entries) e.num[kv.key] = kv.value;
            foreach (var kv in str.entries) e.str[kv.key] = kv.value;
            return e;
        }

        public bool is_raster () {
            return kind == "drop-shadow" || kind == "outer-glow" || kind == "inner-glow" || kind == "blur" || kind == "feather";
        }

        public string label () {
            switch (kind) {
                case "drop-shadow": return _("Drop Shadow");
                case "outer-glow": return _("Outer Glow");
                case "inner-glow": return _("Inner Glow");
                case "blur": return _("Gaussian Blur");
                case "feather": return _("Feather");
                case "round-corners": return _("Round Corners");
                case "offset": return _("Offset Path");
                case "roughen": return _("Roughen");
                case "zigzag": return _("Zig Zag");
                case "pucker": return _("Pucker and Bloat");
                case "twist": return _("Twist");
                case "transform": return _("Transform");
                case "warp": return _("Warp");
                case "free-distort": return _("Free Distort");
                case "outline-stroke": return _("Outline Stroke");
                default: return kind;
            }
        }
    }

    public class PaintLayer : Object {
        public bool stroke;
        public Paint paint = new Paint ();
        public double opacity = 1;
        public BlendMode blend = BlendMode.NORMAL;
        public bool visible = true;
        public double width = 1;
        public CapKind cap = CapKind.BUTT;
        public JoinKind join = JoinKind.MITER;
        public double miter = 10;
        public double[] dashes = {};
        public double dash_offset = 0;
        public StrokeAlign align = StrokeAlign.CENTER;
        public Gee.ArrayList<WidthPoint> profile = new Gee.ArrayList<WidthPoint> ();
        public string brush = "";
        public double brush_scale = 1;
        public string arrow_start = "";
        public string arrow_end = "";
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();

        public PaintLayer.fill (Paint paint) {
            stroke = false;
            this.paint = paint;
        }

        public PaintLayer.line (Paint paint, double width) {
            stroke = true;
            this.paint = paint;
            this.width = width;
        }

        public PaintLayer copy () {
            var o = new PaintLayer ();
            o.stroke = stroke;
            o.paint = paint.copy ();
            o.opacity = opacity;
            o.blend = blend;
            o.visible = visible;
            o.width = width;
            o.cap = cap;
            o.join = join;
            o.miter = miter;
            o.dashes = dashes;
            o.dash_offset = dash_offset;
            o.align = align;
            foreach (var w in profile) o.profile.add (w.copy ());
            o.brush = brush;
            o.brush_scale = brush_scale;
            o.arrow_start = arrow_start;
            o.arrow_end = arrow_end;
            foreach (var e in effects) o.effects.add (e.copy ());
            return o;
        }
    }
}
