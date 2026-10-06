using Gtk;

namespace Singularity.Apps.Vector {

    public class CanvasRulers : Object {
        public const int SIZE = 20;
        private weak VectorCanvas canvas;

        public CanvasRulers (VectorCanvas canvas) {
            this.canvas = canvas;
            canvas.add_css_class ("sx-rulers");
        }

        public bool on_ruler (double x, double y, int height) {
            return x < SIZE || y > height - SIZE;
        }

        public bool vertical_at (double x) {
            return x < SIZE;
        }

        public bool inside_view (double x, double y, int height) {
            return x > SIZE && y < height - SIZE;
        }

        public void draw (Cairo.Context cr, int width, int height) {
            double bg = canvas.dark ? 0.17 : 0.95;
            double top = height - SIZE;
            cr.set_source_rgb (bg, bg, bg);
            cr.rectangle (0, top, width, SIZE);
            cr.rectangle (0, 0, SIZE, height);
            cr.fill ();
            var fg = canvas.get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
            cr.set_line_width (1);
            cr.move_to (SIZE, top + 0.5);
            cr.line_to (width, top + 0.5);
            cr.move_to (SIZE - 0.5, 0);
            cr.line_to (SIZE - 0.5, top);
            cr.stroke ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
            double unit = Units.factor (canvas.doc.units);
            double target = 80 / canvas.zoom / unit;
            double step = Math.pow (10, Math.floor (Math.log10 (target)));
            if (target / step > 5) step *= 5;
            else if (target / step > 2) step *= 2;
            double doc_step = step * unit;
            cr.set_font_size (9);
            var tl = canvas.to_doc (0, 0);
            var br = canvas.to_doc (width, height);
            for (double x = Math.floor (tl.x / doc_step) * doc_step; x < br.x; x += doc_step / 10) {
                double sx = (x - canvas.ox) * canvas.zoom;
                if (sx < SIZE) continue;
                bool major = (Math.round (x / doc_step * 10)).abs () % 10 == 0;
                cr.move_to (Math.round (sx) + 0.5, top);
                cr.line_to (Math.round (sx) + 0.5, major ? height - 4 : top + 5);
                if (major) {
                    cr.move_to (sx + 3, height - 5);
                    cr.show_text (Units.format (x / unit));
                }
            }
            for (double y = Math.floor (tl.y / doc_step) * doc_step; y < br.y; y += doc_step / 10) {
                double sy = (y - canvas.oy) * canvas.zoom;
                if (sy > top) continue;
                bool major = (Math.round (y / doc_step * 10)).abs () % 10 == 0;
                cr.move_to (SIZE, Math.round (sy) + 0.5);
                cr.line_to (major ? 4 : SIZE - 5, Math.round (sy) + 0.5);
                if (major) {
                    cr.save ();
                    cr.move_to (10, sy - 3);
                    cr.rotate (-Math.PI / 2);
                    cr.show_text (Units.format (y / unit));
                    cr.restore ();
                }
            }
            cr.stroke ();
            var s = canvas.to_screen (canvas.pointer);
            cr.set_source_rgb (0.9, 0.2, 0.3);
            if (s.x >= SIZE) {
                cr.move_to (s.x, top);
                cr.line_to (s.x, height);
            }
            if (s.y <= top) {
                cr.move_to (0, s.y);
                cr.line_to (SIZE, s.y);
            }
            cr.stroke ();
            cr.set_source_rgb (bg, bg, bg);
            cr.rectangle (0, top, SIZE, SIZE);
            cr.fill ();
        }
    }
}
