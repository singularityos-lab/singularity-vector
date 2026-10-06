namespace Singularity.Apps.Vector {

    public class Raster {
        public static void box_blur (Cairo.ImageSurface surface, double radius) {
            if (radius < 0.5) return;
            surface.flush ();
            int w = surface.get_width (), h = surface.get_height (), stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            data.length = stride * h;
            int r = (int) Math.ceil (radius / 1.73);
            var tmp = new uint8[stride * h];
            for (int pass = 0; pass < 3; pass++) {
                blur_h (data, tmp, w, h, stride, r);
                blur_v (tmp, data, w, h, stride, r);
            }
            surface.mark_dirty ();
        }

        private static void blur_h (uint8[] src, uint8[] dst, int w, int h, int stride, int r) {
            int win = r * 2 + 1;
            for (int y = 0; y < h; y++) {
                int row = y * stride;
                for (int c = 0; c < 4; c++) {
                    int sum = 0;
                    for (int i = 0; i <= r && i < w; i++) sum += src[row + i * 4 + c];
                    for (int x = 0; x < w; x++) {
                        dst[row + x * 4 + c] = (uint8) (sum / win);
                        int add = x + r + 1, rem = x - r;
                        if (add < w) sum += src[row + add * 4 + c];
                        if (rem >= 0) sum -= src[row + rem * 4 + c];
                    }
                }
            }
        }

        private static void blur_v (uint8[] src, uint8[] dst, int w, int h, int stride, int r) {
            int win = r * 2 + 1;
            for (int x = 0; x < w; x++) {
                for (int c = 0; c < 4; c++) {
                    int sum = 0;
                    for (int i = 0; i <= r && i < h; i++) sum += src[i * stride + x * 4 + c];
                    for (int y = 0; y < h; y++) {
                        dst[y * stride + x * 4 + c] = (uint8) (sum / win);
                        int add = y + r + 1, rem = y - r;
                        if (add < h) sum += src[add * stride + x * 4 + c];
                        if (rem >= 0) sum -= src[rem * stride + x * 4 + c];
                    }
                }
            }
        }

        public static void colorize_alpha (Cairo.ImageSurface surface, double r, double g, double b, double opacity, bool invert = false) {
            surface.flush ();
            int w = surface.get_width (), h = surface.get_height (), stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            data.length = stride * h;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int o = y * stride + x * 4;
                    double a = data[o + 3] / 255.0;
                    if (invert) a = 1 - a;
                    a *= opacity;
                    data[o] = (uint8) (b * a * 255);
                    data[o + 1] = (uint8) (g * a * 255);
                    data[o + 2] = (uint8) (r * a * 255);
                    data[o + 3] = (uint8) (a * 255);
                }
            }
            surface.mark_dirty ();
        }

        public static void luminance_to_alpha (Cairo.ImageSurface surface, bool invert, bool clip) {
            surface.flush ();
            int w = surface.get_width (), h = surface.get_height (), stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            data.length = stride * h;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int o = y * stride + x * 4;
                    double a = data[o + 3] / 255.0;
                    double lum;
                    if (a > 0) lum = (0.0722 * data[o] + 0.7152 * data[o + 1] + 0.2126 * data[o + 2]) / 255.0 / a;
                    else lum = 0;
                    double v = lum * a + (clip ? 0 : 1) * (1 - a);
                    if (invert) v = 1 - v;
                    uint8 va = (uint8) (v.clamp (0, 1) * 255);
                    data[o] = data[o + 1] = data[o + 2] = data[o + 3] = va;
                }
            }
            surface.mark_dirty ();
        }

        public static void mask_with (Cairo.ImageSurface target, Cairo.ImageSurface mask) {
            target.flush ();
            mask.flush ();
            int w = int.min (target.get_width (), mask.get_width ()), h = int.min (target.get_height (), mask.get_height ());
            int ts = target.get_stride (), ms = mask.get_stride ();
            unowned uint8[] t = target.get_data ();
            t.length = ts * target.get_height ();
            unowned uint8[] m = mask.get_data ();
            m.length = ms * mask.get_height ();
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    double a = m[y * ms + x * 4 + 3] / 255.0;
                    int o = y * ts + x * 4;
                    for (int c = 0; c < 4; c++) t[o + c] = (uint8) (t[o + c] * a);
                }
            }
            target.mark_dirty ();
        }
    }
}
