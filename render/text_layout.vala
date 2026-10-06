using Singularity.Vector;

namespace Singularity.Apps.Vector {

    [CCode (cname = "vector_cairo_path", cheader_filename = "vector_cms.h", array_length_pos = 1.1, array_length_type = "int")]
    extern double[] cairo_path_values (Cairo.Context cr);

    public class TextPart : Object {
        public PathData path;
        public Ink? color;

        public TextPart (PathData path, Ink? color) {
            this.path = path;
            this.color = color;
        }
    }

    public class TextLine : Object {
        public int start;
        public int length;
        public double x;
        public double y;
        public double width;

        public TextLine (int start, int length, double x, double y, double width) {
            this.start = start;
            this.length = length;
            this.x = x;
            this.y = y;
            this.width = width;
        }
    }

    public class TextFrame : Object {
        public int start;
        public int end;
        public bool overflow;
    }

    public class TextLayout {
        private static Gee.HashMap<string, Gee.ArrayList<TextPart>>? cache = null;
        private static Cairo.Context? scratch = null;

        private static Cairo.Context context () {
            if (scratch == null) {
                var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 4, 4);
                scratch = new Cairo.Context (surface);
            }
            return scratch;
        }

        public static Pango.FontDescription font (CharStyle s) {
            var d = new Pango.FontDescription ();
            d.set_family (s.family);
            d.set_absolute_size (double.max (s.size, 0.5) * Pango.SCALE);
            d.set_weight ((Pango.Weight) s.weight.clamp (100, 1000));
            d.set_style (s.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            return d;
        }

        private static void put (Pango.AttrList list, owned Pango.Attribute a, uint start, uint end) {
            a.start_index = start;
            a.end_index = end;
            list.insert ((owned) a);
        }

        private static void style_attrs (Pango.AttrList list, CharStyle s, uint start, uint end, bool base_style) {
            if (!base_style) put (list, new Pango.AttrFontDesc (font (s)), start, end);
            if (s.tracking != 0) put (list, Pango.attr_letter_spacing_new ((int) (s.tracking / 1000.0 * s.size * Pango.SCALE)), start, end);
            if (s.baseline != 0) put (list, Pango.attr_rise_new ((int) (s.baseline * Pango.SCALE)), start, end);
            if (s.underline) put (list, Pango.attr_underline_new (Pango.Underline.SINGLE), start, end);
            if (s.strike) put (list, Pango.attr_strikethrough_new (true), start, end);
            if (s.features != "") put (list, new Pango.AttrFontFeatures (s.features), start, end);
            if (s.caps == "small") put (list, Pango.attr_variant_new (Pango.Variant.SMALL_CAPS), start, end);
            if (s.caps == "all") put (list, Pango.attr_text_transform_new (Pango.TextTransform.UPPERCASE), start, end);
            if (s.language != "") put (list, new Pango.AttrLanguage (Pango.Language.from_string (s.language)), start, end);
        }

        public static Pango.Layout make_layout (Cairo.Context cr, TextNode node, string text, int offset) {
            var layout = Pango.cairo_create_layout (cr);
            var options = new Cairo.FontOptions ();
            options.set_hint_style (Cairo.HintStyle.NONE);
            options.set_hint_metrics (Cairo.HintMetrics.OFF);
            Pango.cairo_context_set_font_options (layout.get_context (), options);
            layout.context_changed ();
            layout.set_font_description (font (node.style));
            layout.set_text (text, -1);
            var list = new Pango.AttrList ();
            style_attrs (list, node.style, 0, uint.MAX, true);
            if (node.para.hyphenate) {
                var h = Pango.attr_insert_hyphens_new (true);
                list.insert ((owned) h);
            }
            foreach (var r in node.runs) {
                int s = r.start - offset, e = r.end - offset;
                if (e <= 0 || s >= text.length) continue;
                style_attrs (list, r.style, (uint) int.max (0, s), (uint) int.min (e, text.length), false);
            }
            layout.set_attributes (list);
            return layout;
        }

        private static Ink? color_at (TextNode node, int index) {
            Ink? c = node.style.color;
            foreach (var r in node.runs) if (index >= r.start && index < r.end && r.style.color != null) c = r.style.color;
            return c;
        }

        private static double line_height (TextNode node, Pango.LayoutLine line) {
            Pango.Rectangle ink, logical;
            line.get_extents (out ink, out logical);
            double natural = logical.height / (double) Pango.SCALE;
            if (node.style.leading > 0) return node.style.leading;
            return double.max (natural, node.style.size * 1.2);
        }

        private static string key (TextNode node) {
            var b = new StringBuilder ();
            b.append (node.text);
            b.append_printf ("|%s|%s|%g|%d|%d|%g|%g|%g|%g|%g|%d|%d|%s|%s|%s|", node.mode, node.style.family, node.style.size, node.style.weight, node.style.italic ? 1 : 0,
                node.style.tracking, node.style.leading, node.style.baseline, node.style.hscale, node.style.vscale, node.style.underline ? 1 : 0, node.style.strike ? 1 : 0, node.style.caps, node.style.features, node.style.language);
            b.append_printf ("%s|%g|%g|%g|%g|%g|%d|", node.para.align, node.para.indent_first, node.para.indent_left, node.para.indent_right, node.para.space_before, node.para.space_after, node.para.hyphenate ? 1 : 0);
            b.append_printf ("%g,%g,%g,%g,%g,%g|", node.matrix.xx, node.matrix.yx, node.matrix.xy, node.matrix.yy, node.matrix.x0, node.matrix.y0);
            foreach (var r in node.runs) b.append_printf ("%d-%d:%s,%g,%d,%d,%g,%g,%s,%s;", r.start, r.end, r.style.family, r.style.size, r.style.weight, r.style.italic ? 1 : 0, r.style.tracking, r.style.baseline, r.style.color != null ? r.style.color.to_hex () : "", r.style.features);
            if (node.area != null) b.append (node.area.to_svg (3));
            if (node.on_path != null) b.append (node.on_path.to_svg (3));
            b.append_printf ("|%g|%d|%s|%d|%g|%g", node.path_offset, node.path_flip ? 1 : 0, node.thread_next, node.columns, node.gutter, node.inset);
            if (node.style.color != null) b.append (node.style.color.to_hex ());
            return b.str;
        }

        public static void invalidate () {
            if (cache != null) cache.clear ();
        }

        public static Gee.ArrayList<TextPart> parts (TextNode node) {
            if (cache == null) cache = new Gee.HashMap<string, Gee.ArrayList<TextPart>> ();
            string k = key (node) + "#" + chain_key (node);
            if (cache.has_key (k)) return cache[k];
            var result = build (node);
            if (cache.size > 400) cache.clear ();
            cache[k] = result;
            return result;
        }

        private static string chain_key (TextNode node) {
            var head = chain_head (node);
            if (head == node && node.thread_next == "") return "";
            var b = new StringBuilder ();
            TextNode? cur = head;
            int guard = 0;
            while (cur != null && guard++ < 64) {
                b.append (key (cur));
                cur = next_in_chain (cur);
            }
            return Checksum.compute_for_string (ChecksumType.MD5, b.str);
        }

        public static TextNode? next_in_chain (TextNode node) {
            var document = node.document ();
            if (node.thread_next == "" || document == null) return null;
            return document.find (node.thread_next) as TextNode;
        }

        public static TextNode chain_head (TextNode node) {
            var document = node.document ();
            if (document == null || !document.has_threads ()) return node;
            TextNode cur = node;
            int guard = 0;
            bool moved = true;
            while (moved && guard++ < 64) {
                moved = false;
                foreach (var n in document.all_nodes ()) {
                    var t = n as TextNode;
                    if (t != null && t.thread_next == cur.id && t != node) {
                        cur = t;
                        moved = true;
                        break;
                    }
                }
            }
            return cur;
        }

        private static PathData capture (Cairo.Context cr) {
            var p = new PathData ();
            double[] d = cairo_path_values (cr);
            for (int i = 0; i + 6 < d.length; i += 7) {
                switch ((int) d[i]) {
                    case 0:
                        p.move_to (d[i + 1], d[i + 2]);
                        break;
                    case 1:
                        p.line_to (d[i + 1], d[i + 2]);
                        break;
                    case 2:
                        p.curve_to (d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6]);
                        break;
                    case 3:
                        p.close ();
                        break;
                }
            }
            cr.new_path ();
            return p;
        }

        private static void add_part (Gee.ArrayList<TextPart> parts, PathData p, Ink? color) {
            if (p.is_empty ()) return;
            foreach (var part in parts) {
                if ((part.color == null && color == null) || (part.color != null && color != null && part.color.same (color))) {
                    part.path.append (p);
                    return;
                }
            }
            parts.add (new TextPart (p, color));
        }

        private static void line_paths (Cairo.Context cr, TextNode node, Pango.LayoutLine line, double x, double y, int offset, Gee.ArrayList<TextPart> parts, Cairo.Matrix m) {
            bool colored = node.runs.size > 0;
            foreach (var r in node.runs) if (r.style.color != null) colored = true;
            if (!colored) {
                cr.save ();
                cr.set_matrix (m);
                cr.move_to (x, y);
                Pango.cairo_layout_line_path (cr, line);
                cr.restore ();
                add_part (parts, capture_transformed (cr), node.style.color);
                return;
            }
            unowned SList<Pango.GlyphItem> runs = line.runs;
            double rx = x;
            foreach (unowned Pango.GlyphItem run in runs) {
                int width = run.glyphs.get_width ();
                int index = offset + run.item.offset;
                var c = color_at (node, index);
                cr.save ();
                cr.set_matrix (m);
                cr.move_to (rx, y);
                Pango.cairo_glyph_string_path (cr, run.item.analysis.font, run.glyphs);
                cr.restore ();
                add_part (parts, capture_transformed (cr), c);
                rx += width / (double) Pango.SCALE;
            }
            Pango.Rectangle ink, logical;
            line.get_extents (out ink, out logical);
            foreach (var r in node.runs) {
                if (!r.style.underline && !r.style.strike) continue;
            }
            if (node.style.underline || node.style.strike) {
                var fm = line.layout.get_context ().get_metrics (font (node.style), null);
                double w = logical.width / (double) Pango.SCALE;
                if (node.style.underline) {
                    double pos = fm.get_underline_position () / (double) Pango.SCALE;
                    double th = double.max (fm.get_underline_thickness () / (double) Pango.SCALE, 0.5);
                    var p = new PathData.rect (x, y - pos, w, th);
                    p.transform (m);
                    add_part (parts, p, node.style.color);
                }
                if (node.style.strike) {
                    double pos = fm.get_strikethrough_position () / (double) Pango.SCALE;
                    double th = double.max (fm.get_strikethrough_thickness () / (double) Pango.SCALE, 0.5);
                    var p = new PathData.rect (x, y - pos, w, th);
                    p.transform (m);
                    add_part (parts, p, node.style.color);
                }
            }
        }

        private static PathData capture_transformed (Cairo.Context cr) {
            return capture (cr);
        }

        private static Cairo.Matrix local_matrix (TextNode node) {
            var m = Cairo.Matrix.identity ();
            m.scale (node.style.hscale, node.style.vscale);
            return Transforms.multiply (m, node.matrix);
        }

        private static Gee.ArrayList<TextPart> build (TextNode node) {
            var cr = context ();
            cr.identity_matrix ();
            cr.new_path ();
            var parts = new Gee.ArrayList<TextPart> ();
            if (node.mode == "path" && node.on_path != null) {
                build_on_path (cr, node, parts);
                return parts;
            }
            if (node.mode == "area" && node.area != null) {
                var head = chain_head (node);
                int start = 0;
                TextNode? cur = head;
                int guard = 0;
                while (cur != null && guard++ < 64) {
                    var frame_parts = new Gee.ArrayList<TextPart> ();
                    int end = layout_area (cr, cur, head, start, cur == node ? parts : frame_parts);
                    if (cur == node) break;
                    start = end;
                    cur = next_in_chain (cur);
                }
                return parts;
            }
            var layout = make_layout (cr, node, node.text, 0);
            var m = local_matrix (node);
            double y = 0;
            bool first = true;
            int lines = layout.get_line_count ();
            Pango.Rectangle full_ink, full_logical;
            layout.get_extents (out full_ink, out full_logical);
            for (int i = 0; i < lines; i++) {
                var line = layout.get_line_readonly (i);
                Pango.Rectangle ink, logical;
                line.get_extents (out ink, out logical);
                double lw = logical.width / (double) Pango.SCALE;
                if (!first) y += line_height (node, line);
                first = false;
                double x = 0;
                if (node.para.align == "center") x = -lw / 2;
                else if (node.para.align == "right") x = -lw;
                line_paths (cr, node, line, x, y, 0, parts, m);
            }
            return parts;
        }

        public static Gee.ArrayList<double?> spans (PathData area, double y0, double y1) {
            var result = new Gee.ArrayList<double?> ();
            var a = scan (area, y0 + (y1 - y0) * 0.15);
            var b = scan (area, y0 + (y1 - y0) * 0.85);
            for (int i = 0; i + 1 < a.size; i += 2) {
                for (int j = 0; j + 1 < b.size; j += 2) {
                    double l = double.max (a[i], b[j]), r = double.min (a[i + 1], b[j + 1]);
                    if (r - l > 1) {
                        result.add (l);
                        result.add (r);
                    }
                }
            }
            return result;
        }

        private static Gee.ArrayList<double?> scan (PathData area, double y) {
            var hits = new Gee.ArrayList<double?> ();
            foreach (var poly in area.flatten (0.5)) {
                var pts = poly.pts;
                for (int i = 0; i < pts.length; i++) {
                    var p = pts[i];
                    var q = pts[(i + 1) % pts.length];
                    if ((p.y <= y && q.y > y) || (q.y <= y && p.y > y)) hits.add (p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y));
                }
            }
            hits.sort ((x, z) => x < z ? -1 : x > z ? 1 : 0);
            return hits;
        }

        public static int layout_area (Cairo.Context cr, TextNode frame, TextNode head, int start, Gee.ArrayList<TextPart>? parts, Gee.ArrayList<TextLine>? lines = null) {
            string text = head.text;
            if (start >= text.length) return text.length;
            var box = frame.area.bounds ();
            int cols = int.max (1, frame.columns);
            double colw = (box.w - frame.gutter * (cols - 1)) / cols;
            int pos = start;
            bool para_start = start == 0 || text[start - 1] == '\n';
            var m = Cairo.Matrix.identity ();
            for (int c = 0; c < cols && pos < text.length; c++) {
                double cx0 = box.x + c * (colw + frame.gutter) + frame.inset;
                double cx1 = cx0 + colw - frame.inset * 2;
                double y = box.y + frame.inset;
                if (para_start) y += head.para.space_before;
                int guard = 0;
                while (pos < text.length && guard++ < 5000) {
                    double lh = head.style.leading > 0 ? head.style.leading : head.style.size * 1.2;
                    if (y + lh > box.y + box.h - frame.inset + 0.01) break;
                    var sp = spans (frame.area, y, y + lh);
                    double l = double.NAN, r = double.NAN;
                    for (int i = 0; i + 1 < sp.size; i += 2) {
                        double a = double.max (sp[i], cx0), b = double.min (sp[i + 1], cx1);
                        if (b - a > head.style.size) {
                            l = a;
                            r = b;
                            break;
                        }
                    }
                    if (l.is_nan ()) {
                        y += lh / 2;
                        continue;
                    }
                    double indent_l = head.para.indent_left + (para_start ? head.para.indent_first : 0);
                    double width = r - l - indent_l - head.para.indent_right;
                    if (width < 4) {
                        y += lh;
                        continue;
                    }
                    string rest = text.substring (pos);
                    var layout = make_layout (cr, head, rest, pos);
                    layout.set_width ((int) (width * Pango.SCALE));
                    layout.set_wrap (Pango.WrapMode.WORD_CHAR);
                    var line = layout.get_line_readonly (0);
                    int consumed = line.start_index + line.length;
                    bool ends_para = consumed < rest.length && rest[consumed] == '\n';
                    bool last_line = consumed >= rest.length || ends_para;
                    if (head.para.align == "justify" && !last_line) {
                        layout.set_justify (true);
                        line = layout.get_line_readonly (0);
                    }
                    double actual = line_height (head, line);
                    Pango.Rectangle ink, logical;
                    line.get_extents (out ink, out logical);
                    double lw = logical.width / (double) Pango.SCALE;
                    double x = l + indent_l;
                    if (head.para.align == "center") x += (width - lw) / 2;
                    else if (head.para.align == "right") x += width - lw;
                    double baseline = y + layout.get_baseline () / (double) Pango.SCALE;
                    if (parts != null) line_paths (cr, head, line, x, baseline, pos, parts, m);
                    if (lines != null) lines.add (new TextLine (pos, consumed, x, baseline, lw));
                    y += actual;
                    pos += consumed;
                    para_start = false;
                    if (ends_para) {
                        pos++;
                        y += head.para.space_after + head.para.space_before;
                        para_start = true;
                    }
                    if (consumed == 0 && !ends_para) break;
                }
            }
            return pos;
        }

        public static TextFrame frame_info (TextNode node) {
            var info = new TextFrame ();
            var cr = context ();
            if (node.mode != "area" || node.area == null) {
                info.start = 0;
                info.end = node.text.length;
                return info;
            }
            var head = chain_head (node);
            int start = 0;
            TextNode? cur = head;
            int guard = 0;
            while (cur != null && guard++ < 64) {
                int end = layout_area (cr, cur, head, start, null);
                if (cur == node) {
                    info.start = start;
                    info.end = end;
                    info.overflow = end < head.text.length && next_in_chain (cur) == null;
                    return info;
                }
                start = end;
                cur = next_in_chain (cur);
            }
            return info;
        }

        private static void build_on_path (Cairo.Context cr, TextNode node, Gee.ArrayList<TextPart> parts) {
            var path = node.path_flip ? PathOps.reversed (node.on_path) : node.on_path;
            double total = PathOps.length (path);
            var layout = make_layout (cr, node, node.text.replace ("\n", " "), 0);
            Pango.Rectangle ink, logical;
            layout.get_extents (out ink, out logical);
            double width = logical.width / (double) Pango.SCALE;
            double baseline = layout.get_baseline () / (double) Pango.SCALE;
            double start = node.path_offset;
            if (node.para.align == "center") start += (total - width) / 2;
            else if (node.para.align == "right") start += total - width;
            var iter = layout.get_iter ();
            string text = node.text.replace ("\n", " ");
            do {
                int idx = iter.get_index ();
                if (idx >= text.length) break;
                Pango.Rectangle ce = iter.get_char_extents ();
                double cx = ce.x / (double) Pango.SCALE;
                double cw = ce.width / (double) Pango.SCALE;
                unichar ch = text.get_char (idx);
                if (ch == ' ') continue;
                double d = start + cx + cw / 2;
                if (d < 0 || d > total) continue;
                Point p;
                double angle;
                PathOps.point_at (path, d, out p, out angle);
                int next = text.index_of_nth_char (text.substring (0, idx).char_count () + 1);
                var single = make_layout (cr, node, text.substring (idx, next - idx), idx);
                var m = Cairo.Matrix.identity ();
                m.translate (p.x, p.y);
                m.rotate (angle);
                cr.save ();
                cr.set_matrix (m);
                cr.move_to (-cw / 2, -baseline);
                Pango.cairo_layout_path (cr, single);
                cr.restore ();
                add_part (parts, capture (cr), color_at (node, idx));
            } while (iter.next_char ());
        }

        public static Gee.ArrayList<TextLine> lines (TextNode node) {
            var result = new Gee.ArrayList<TextLine> ();
            var cr = context ();
            if (node.mode == "area" && node.area != null) {
                var head = chain_head (node);
                int start = 0;
                TextNode? cur = head;
                int guard = 0;
                while (cur != null && guard++ < 64) {
                    int end = layout_area (cr, cur, head, start, null, cur == node ? result : null);
                    if (cur == node) break;
                    start = end;
                    cur = next_in_chain (cur);
                }
                return result;
            }
            var layout = make_layout (cr, node, node.text, 0);
            double y = 0;
            for (int i = 0; i < layout.get_line_count (); i++) {
                var line = layout.get_line_readonly (i);
                Pango.Rectangle ink, logical;
                line.get_extents (out ink, out logical);
                double lw = logical.width / (double) Pango.SCALE;
                if (i > 0) y += line_height (node, line);
                double x = 0;
                if (node.para.align == "center") x = -lw / 2;
                else if (node.para.align == "right") x = -lw;
                result.add (new TextLine (line.start_index, line.length, x, y, lw));
            }
            return result;
        }

        public static PathData to_path (TextNode node) {
            var all = new PathData ();
            foreach (var p in parts (node)) all.append (p.path);
            return all;
        }

        public static Rect bounds (TextNode node) {
            if (node.mode == "area" && node.area != null) return node.area.bounds ();
            var p = to_path (node);
            if (p.is_empty ()) {
                double x = node.matrix.x0, y = node.matrix.y0;
                return Rect (x, y - node.style.size, 1, node.style.size);
            }
            return p.bounds ();
        }

        public static Rect line_box (TextNode node) {
            var cr = context ();
            var layout = make_layout (cr, node, node.text == "" ? " " : node.text, 0);
            Pango.Rectangle ink, logical;
            layout.get_extents (out ink, out logical);
            double w = logical.width / (double) Pango.SCALE, h = logical.height / (double) Pango.SCALE;
            double baseline = layout.get_baseline () / (double) Pango.SCALE;
            double x = 0;
            if (node.para.align == "center") x = -w / 2;
            else if (node.para.align == "right") x = -w;
            return Transforms.rect_bounds (Rect (x, -baseline, double.max (w, 2), h), local_matrix (node));
        }
    }
}
