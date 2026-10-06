using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class RenderContext : Object {
        public VectorDocument doc;
        public bool outline = false;
        public bool print = false;
        public bool overprint = false;
        public bool hide_templates = false;
        public Gee.HashSet<Node>? skip = null;
        public Node? isolated = null;

        public RenderContext (VectorDocument doc) {
            this.doc = doc;
        }
    }

    public class Renderer {
        private static Gee.HashMap<string, Cairo.Surface>? image_cache = null;

        public static void draw_document (Cairo.Context cr, RenderContext ctx) {
            foreach (var l in ctx.doc.layers) {
                if (ctx.print && !l.printable) continue;
                if (ctx.hide_templates && l.template) continue;
                draw_node (cr, l, ctx);
            }
        }

        public static void draw_artboard (Cairo.Context cr, RenderContext ctx, Artboard a, bool background = true) {
            cr.save ();
            cr.rectangle (a.x - a.bleed, a.y - a.bleed, a.w + a.bleed * 2, a.h + a.bleed * 2);
            cr.clip ();
            if (background && a.background != "") {
                var ink = Ink.hex (a.background);
                cr.set_source_rgb (ink.r, ink.g, ink.b);
                cr.paint ();
            }
            draw_document (cr, ctx);
            cr.restore ();
        }

        private static bool raster_effects (Node n) {
            foreach (var e in n.effects) if (e.enabled && e.is_raster ()) return true;
            return false;
        }

        public static void draw_node (Cairo.Context cr, Node n, RenderContext ctx) {
            if (n.hidden) return;
            if (ctx.skip != null && ctx.skip.contains (n)) return;
            if (ctx.outline) {
                draw_outline (cr, n, ctx);
                return;
            }
            bool group = n.opacity < 0.999 || n.blend != BlendMode.NORMAL || n.mask != null || raster_effects (n) || n.isolate || n.knockout;
            if (!group) {
                draw_content (cr, n, ctx);
                return;
            }
            cr.save ();
            cr.push_group ();
            if (n.knockout) cr.set_operator (Cairo.Operator.SOURCE);
            draw_content (cr, n, ctx);
            var content = cr.pop_group ();
            Cairo.Pattern result = content;
            if (raster_effects (n)) result = apply_raster_effects (cr, n, content, ctx);
            if (n.mask != null) {
                cr.push_group ();
                cr.set_source (result);
                cr.paint ();
                apply_mask (cr, n, ctx);
                result = cr.pop_group ();
            }
            cr.set_source (result);
            cr.set_operator (n.blend.to_operator ());
            cr.paint_with_alpha (n.opacity.clamp (0, 1));
            cr.restore ();
        }

        private static void device_bounds (Cairo.Context cr, Rect user, out int x, out int y, out int w, out int h) {
            double x1 = user.x, y1 = user.y, x2 = user.x + user.w, y2 = user.y + user.h;
            double[] xs = { x1, x2, x2, x1 };
            double[] ys = { y1, y1, y2, y2 };
            double minx = double.INFINITY, miny = double.INFINITY, maxx = -double.INFINITY, maxy = -double.INFINITY;
            for (int i = 0; i < 4; i++) {
                double px = xs[i], py = ys[i];
                cr.user_to_device (ref px, ref py);
                minx = double.min (minx, px);
                miny = double.min (miny, py);
                maxx = double.max (maxx, px);
                maxy = double.max (maxy, py);
            }
            double cx1, cy1, cx2, cy2;
            cr.save ();
            cr.identity_matrix ();
            cr.clip_extents (out cx1, out cy1, out cx2, out cy2);
            cr.restore ();
            if (cx2 - cx1 > 1 && cy2 - cy1 > 1 && (cx2 - cx1) < 1e7) {
                minx = double.max (minx, cx1 - 64);
                miny = double.max (miny, cy1 - 64);
                maxx = double.min (maxx, cx2 + 64);
                maxy = double.min (maxy, cy2 + 64);
            }
            x = (int) Math.floor (minx);
            y = (int) Math.floor (miny);
            w = int.max (1, int.min (8192, (int) Math.ceil (maxx) - x));
            h = int.max (1, int.min (8192, (int) Math.ceil (maxy) - y));
        }

        private static Cairo.ImageSurface rasterize (Cairo.Context cr, Cairo.Pattern p, int x, int y, int w, int h) {
            var img = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var ic = new Cairo.Context (img);
            var shift = Cairo.Matrix.identity ();
            shift.translate (-x, -y);
            var m = Cairo.Matrix.identity ();
            m.multiply (cr.get_matrix (), shift);
            ic.set_matrix (m);
            ic.set_source (p);
            ic.paint ();
            return img;
        }

        private static double device_scale (Cairo.Context cr) {
            double dx = 1, dy = 0;
            cr.user_to_device_distance (ref dx, ref dy);
            return Math.hypot (dx, dy);
        }

        private static Cairo.Pattern apply_raster_effects (Cairo.Context cr, Node n, Cairo.Pattern content, RenderContext ctx) {
            var box = n.visual_bounds ();
            int x, y, w, h;
            device_bounds (cr, box, out x, out y, out w, out h);
            double scale = device_scale (cr);
            var base_img = rasterize (cr, content, x, y, w, h);
            var out_img = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var oc = new Cairo.Context (out_img);
            var after = new Gee.ArrayList<Effect> ();
            foreach (var e in n.effects) {
                if (!e.enabled || !e.is_raster ()) continue;
                if (e.kind == "drop-shadow" || e.kind == "outer-glow") {
                    var sh = rasterize (cr, content, x, y, w, h);
                    var c = Ink.hex (e.get_str ("color", "#000000"));
                    Raster.colorize_alpha (sh, c.r, c.g, c.b, e.get_num ("opacity", e.kind == "drop-shadow" ? 0.6 : 0.75));
                    double blur = e.get_num ("blur", 5) * scale;
                    if (e.kind == "outer-glow") {
                        Raster.box_blur (sh, blur);
                        Raster.box_blur (sh, blur * 0.5);
                        oc.set_source_surface (sh, 0, 0);
                    } else {
                        Raster.box_blur (sh, blur);
                        double dx = e.get_num ("dx", 7), dy = e.get_num ("dy", 7);
                        cr.user_to_device_distance (ref dx, ref dy);
                        oc.set_source_surface (sh, dx, dy);
                    }
                    oc.set_operator (BlendMode.from_id (e.get_str ("blend", "normal")).to_operator ());
                    oc.paint ();
                    oc.set_operator (Cairo.Operator.OVER);
                } else {
                    after.add (e);
                }
            }
            foreach (var e in after) {
                if (e.kind == "blur") {
                    Raster.box_blur (base_img, e.get_num ("blur", 5) * scale);
                } else if (e.kind == "feather") {
                    var alpha = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
                    var ac = new Cairo.Context (alpha);
                    ac.set_source_surface (base_img, 0, 0);
                    ac.paint ();
                    Raster.colorize_alpha (alpha, 1, 1, 1, 1);
                    var shrink = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
                    var sc = new Cairo.Context (shrink);
                    sc.set_source_surface (alpha, 0, 0);
                    sc.paint ();
                    Raster.box_blur (shrink, e.get_num ("blur", 5) * scale);
                    Raster.mask_with (base_img, shrink);
                } else if (e.kind == "inner-glow") {
                    var glow = rasterize (cr, content, x, y, w, h);
                    var c = Ink.hex (e.get_str ("color", "#ffffff"));
                    Raster.colorize_alpha (glow, c.r, c.g, c.b, 1, true);
                    Raster.box_blur (glow, e.get_num ("blur", 5) * scale);
                    var bc = new Cairo.Context (base_img);
                    bc.set_operator (Cairo.Operator.ATOP);
                    bc.set_source_surface (glow, 0, 0);
                    bc.paint_with_alpha (e.get_num ("opacity", 0.75));
                }
            }
            oc.set_source_surface (base_img, 0, 0);
            oc.paint ();
            var pattern = new Cairo.Pattern.for_surface (out_img);
            var pm = Cairo.Matrix.identity ();
            pm.translate (-x, -y);
            var ctm = cr.get_matrix ();
            Cairo.Matrix result;
            result = Cairo.Matrix.identity ();
            result.multiply (ctm, pm);
            pattern.set_matrix (result);
            return pattern;
        }

        private static void apply_mask (Cairo.Context cr, Node n, RenderContext ctx) {
            var box = n.mask.visual_bounds ().union (n.visual_bounds ());
            int x, y, w, h;
            device_bounds (cr, box, out x, out y, out w, out h);
            cr.push_group ();
            draw_node (cr, n.mask, ctx);
            var mp = cr.pop_group ();
            var img = rasterize (cr, mp, x, y, w, h);
            Raster.luminance_to_alpha (img, n.mask_invert, n.mask_clip);
            var pattern = new Cairo.Pattern.for_surface (img);
            var pm = Cairo.Matrix.identity ();
            pm.translate (-x, -y);
            var ctm = cr.get_matrix ();
            Cairo.Matrix result;
            result = Cairo.Matrix.identity ();
            result.multiply (ctm, pm);
            pattern.set_matrix (result);
            cr.save ();
            cr.set_operator (Cairo.Operator.DEST_IN);
            cr.set_source (pattern);
            cr.paint ();
            cr.restore ();
        }

        private static void draw_outline (Cairo.Context cr, Node n, RenderContext ctx) {
            var g = n as GroupNode;
            if (g != null) {
                var gen = g.generated (ctx.doc);
                foreach (var c in (gen != null ? gen.children : g.children)) draw_outline (cr, c, ctx);
                return;
            }
            var o = n.outline ();
            if (o == null) return;
            cr.save ();
            cr.new_path ();
            o.to_cairo (cr);
            double lw = 1, ly = 0;
            cr.device_to_user_distance (ref lw, ref ly);
            cr.set_line_width (Math.hypot (lw, ly));
            cr.set_source_rgb (0.1, 0.1, 0.1);
            cr.stroke ();
            cr.restore ();
        }

        public static void draw_content (Cairo.Context cr, Node n, RenderContext ctx) {
            var g = n as GroupNode;
            if (g != null) {
                var gen = g.generated (ctx.doc);
                if (gen != null) {
                    foreach (var c in gen.children) draw_node (cr, c, ctx);
                    return;
                }
                if (g.clip && g.children.size > 0) {
                    var cp = g.children[0].outline ();
                    cr.save ();
                    if (cp != null) {
                        cr.new_path ();
                        cp.to_cairo (cr);
                        var pn = g.children[0] as PathNode;
                        cr.set_fill_rule (pn != null && pn.even_odd ? Cairo.FillRule.EVEN_ODD : Cairo.FillRule.WINDING);
                        cr.clip ();
                    }
                    for (int i = 1; i < g.children.size; i++) draw_node (cr, g.children[i], ctx);
                    cr.restore ();
                    draw_paint_layers (cr, g.children[0], cp, ctx, null, true);
                    return;
                }
                foreach (var c in g.children) draw_node (cr, c, ctx);
                return;
            }
            var pn = n as PathNode;
            if (pn != null) {
                if (pn.guide) return;
                draw_paint_layers (cr, n, vector_effects (pn.render_path (), n.effects), ctx, null, pn.even_odd);
                return;
            }
            var tn = n as TextNode;
            if (tn != null) {
                foreach (var part in TextLayout.parts (tn)) draw_paint_layers (cr, n, vector_effects (part.path, n.effects), ctx, part.color, false);
                return;
            }
            var im = n as ImageNode;
            if (im != null) {
                draw_image (cr, im, ctx);
                return;
            }
            var sy = n as SymbolNode;
            if (sy != null) {
                var art = sy.resolve (ctx.doc);
                if (art != null) draw_node (cr, art, ctx);
                return;
            }
            var me = n as MeshNode;
            if (me != null) {
                draw_mesh (cr, me);
                return;
            }
        }

        public static PathData vector_effects (PathData source, Gee.List<Effect> effects) {
            var p = source;
            foreach (var e in effects) {
                if (!e.enabled || e.is_raster ()) continue;
                p = apply_vector_effect (p, e);
            }
            return p;
        }

        public static PathData apply_vector_effect (PathData p, Effect e) {
            switch (e.kind) {
                case "round-corners":
                    return LiveCorners.apply (p, new Gee.HashMap<int, double?> (), null, e.get_num ("radius", 10));
                case "offset":
                    return CurveOffset.offset (p, e.get_num ("distance", 10), (JoinKind) (int) e.get_num ("join", 0), e.get_num ("miter", 4));
                case "roughen":
                    return Warp.roughen (p, e.get_num ("size", 5), (int) e.get_num ("detail", 10), e.get_num ("smooth", 1) != 0, (uint32) e.get_num ("seed", 1));
                case "zigzag":
                    return Warp.zigzag (p, e.get_num ("size", 5), (int) e.get_num ("ridges", 4), e.get_num ("smooth", 0) != 0);
                case "pucker":
                    return Warp.pucker_bloat (p, e.get_num ("amount", 0.3));
                case "twist":
                    return Warp.twist (p, e.get_num ("angle", 45));
                case "warp":
                    var box = p.bounds ();
                    var style = WarpStyle.from_id (e.get_str ("style", "arc"));
                    double bend = e.get_num ("bend", 0.5), h = e.get_num ("h", 0), v = e.get_num ("v", 0);
                    bool vert = e.get_num ("vertical", 0) != 0;
                    return PathOps.map_points (p, (q) => Warp.preset (style, box, q, bend, h, v, vert));
                case "free-distort":
                    var box = p.bounds ();
                    Point[] src = { Point (box.x, box.y), Point (box.x + box.w, box.y), Point (box.x + box.w, box.y + box.h), Point (box.x, box.y + box.h) };
                    Point[] dst = {};
                    for (int i = 0; i < 4; i++) dst += Point (box.x + box.w * e.get_num ("u%d".printf (i), i == 1 || i == 2 ? 1 : 0), box.y + box.h * e.get_num ("v%d".printf (i), i >= 2 ? 1 : 0));
                    var hm = Warp.homography (src, dst);
                    return PathOps.map_points (p, (q) => Warp.project (hm, q));
                case "transform":
                    var result = p.copy ();
                    int copies = (int) e.get_num ("copies", 0);
                    var box = p.bounds ();
                    var m = Transforms.multiply (Transforms.scale (e.get_num ("sx", 1), e.get_num ("sy", 1), Point (box.cx (), box.cy ())), Transforms.rotate (e.get_num ("angle", 0) * Math.PI / 180, Point (box.cx (), box.cy ())));
                    m = Transforms.multiply (m, Transforms.translate (e.get_num ("dx", 0), e.get_num ("dy", 0)));
                    var cur = p.copy ();
                    if (copies == 0) {
                        cur.transform (m);
                        return cur;
                    }
                    for (int i = 0; i < copies.clamp (0, 500); i++) {
                        cur.transform (m);
                        result.append (cur.copy ());
                    }
                    return result;
                default:
                    return p;
            }
        }

        public static void draw_paint_layers (Cairo.Context cr, Node n, PathData? geometry, RenderContext ctx, Ink? color_override, bool even_odd) {
            if (geometry == null) return;
            var box = geometry.bounds ();
            foreach (var l in n.appearance) {
                if (!l.visible || !l.paint.visible ()) continue;
                var geo = vector_effects (geometry, l.effects);
                bool grouped = l.opacity < 0.999 || l.blend != BlendMode.NORMAL || (ctx.overprint && l.paint.overprint);
                if (grouped) cr.push_group ();
                if (l.stroke) draw_stroke (cr, n, geo, l, box, ctx, color_override);
                else {
                    cr.new_path ();
                    geo.to_cairo (cr);
                    cr.set_fill_rule (even_odd ? Cairo.FillRule.EVEN_ODD : Cairo.FillRule.WINDING);
                    set_paint (cr, l.paint, box, ctx, color_override);
                    cr.fill ();
                }
                if (grouped) {
                    cr.pop_group_to_source ();
                    cr.save ();
                    var op = l.blend.to_operator ();
                    if (ctx.overprint && l.paint.overprint) op = Cairo.Operator.MULTIPLY;
                    cr.set_operator (op);
                    cr.paint_with_alpha (l.opacity.clamp (0, 1));
                    cr.restore ();
                }
            }
        }

        private static void draw_stroke (Cairo.Context cr, Node n, PathData geo, PaintLayer l, Rect box, RenderContext ctx, Ink? color_override) {
            if (l.width <= 0) return;
            if (l.brush != "") {
                var brush = ctx.doc.find_brush (l.brush);
                if (brush != null) {
                    Brushes.draw (cr, geo, l, brush, box, ctx, color_override);
                    return;
                }
            }
            var path = geo;
            if (l.arrow_start != "" || l.arrow_end != "") path = Arrows.trim (geo, l);
            if (l.profile.size > 0) {
                var outline = CurveOffset.variable (l.dashes.length > 0 ? CurveOffset.dash (path, l.dashes, l.dash_offset) : path, l.width, l.profile, l.cap);
                cr.new_path ();
                outline.to_cairo (cr);
                cr.set_fill_rule (Cairo.FillRule.WINDING);
                set_paint (cr, l.paint, box, ctx, color_override);
                cr.fill ();
            } else if (l.align != StrokeAlign.CENTER && PathOps.all_closed (path)) {
                cr.save ();
                cr.new_path ();
                path.to_cairo (cr);
                if (l.align == StrokeAlign.INSIDE) {
                    cr.clip ();
                } else {
                    double x1, y1, x2, y2;
                    cr.clip_extents (out x1, out y1, out x2, out y2);
                    cr.rectangle (x1, y1, x2 - x1, y2 - y1);
                    cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                    cr.clip ();
                    cr.set_fill_rule (Cairo.FillRule.WINDING);
                }
                cr.new_path ();
                path.to_cairo (cr);
                apply_stroke_style (cr, l, 2);
                set_paint (cr, l.paint, box.inflate (l.width), ctx, color_override);
                cr.stroke ();
                cr.restore ();
            } else {
                cr.new_path ();
                path.to_cairo (cr);
                apply_stroke_style (cr, l, 1);
                set_paint (cr, l.paint, box.inflate (l.width / 2), ctx, color_override);
                cr.stroke ();
            }
            if (l.arrow_start != "" || l.arrow_end != "") Arrows.draw (cr, geo, l, box, ctx, color_override);
        }

        public static void apply_stroke_style (Cairo.Context cr, PaintLayer l, double factor) {
            cr.set_line_width (l.width * factor);
            switch (l.cap) {
                case CapKind.ROUND: cr.set_line_cap (Cairo.LineCap.ROUND); break;
                case CapKind.SQUARE: cr.set_line_cap (Cairo.LineCap.SQUARE); break;
                default: cr.set_line_cap (Cairo.LineCap.BUTT); break;
            }
            switch (l.join) {
                case JoinKind.ROUND: cr.set_line_join (Cairo.LineJoin.ROUND); break;
                case JoinKind.BEVEL: cr.set_line_join (Cairo.LineJoin.BEVEL); break;
                default: cr.set_line_join (Cairo.LineJoin.MITER); break;
            }
            cr.set_miter_limit (l.miter);
            if (l.dashes.length > 0) {
                double total = 0;
                foreach (double d in l.dashes) total += d;
                if (total > 0) cr.set_dash (l.dashes, l.dash_offset);
                else cr.set_dash (null, 0);
            } else {
                cr.set_dash (null, 0);
            }
        }

        public static Ink resolve_ink (Ink ink, RenderContext ctx) {
            if (ink.swatch != "") {
                var sw = ctx.doc.find_swatch (ink.swatch);
                if (sw != null && sw.is_global && sw.paint.kind == PaintKind.SOLID) {
                    var base_ink = sw.paint.color;
                    if (ink.tint < 1) return new Ink.rgb (1 - (1 - base_ink.r) * ink.tint, 1 - (1 - base_ink.g) * ink.tint, 1 - (1 - base_ink.b) * ink.tint);
                    return base_ink;
                }
            }
            if (ink.tint < 1) return new Ink.rgb (1 - (1 - ink.r) * ink.tint, 1 - (1 - ink.g) * ink.tint, 1 - (1 - ink.b) * ink.tint);
            return ink;
        }

        public static void set_paint (Cairo.Context cr, Paint paint, Rect box, RenderContext ctx, Ink? color_override = null) {
            if (color_override != null && paint.kind == PaintKind.SOLID) {
                var c = resolve_ink (color_override, ctx);
                cr.set_source_rgb (c.r, c.g, c.b);
                return;
            }
            switch (paint.kind) {
                case PaintKind.LINEAR:
                case PaintKind.RADIAL:
                    cr.set_source (gradient_pattern (paint, ctx));
                    return;
                case PaintKind.FREEFORM:
                    cr.set_source (freeform_pattern (paint, box, ctx));
                    return;
                case PaintKind.PATTERN:
                    var p = pattern_source (paint, ctx);
                    if (p != null) {
                        cr.set_source (p);
                        return;
                    }
                    cr.set_source_rgba (0.5, 0.5, 0.5, 0.5);
                    return;
                default:
                    var c = resolve_ink (paint.color, ctx);
                    cr.set_source_rgb (c.r, c.g, c.b);
                    return;
            }
        }

        public static Cairo.Pattern gradient_pattern (Paint paint, RenderContext? ctx) {
            var g = paint.gradient;
            Cairo.Pattern pat;
            if (paint.kind == PaintKind.RADIAL) {
                double r = Math.hypot (g.x2 - g.x1, g.y2 - g.y1);
                double angle = Math.atan2 (g.y2 - g.y1, g.x2 - g.x1);
                var m = Cairo.Matrix.identity ();
                m.translate (g.x1, g.y1);
                m.rotate (angle);
                m.scale (1, double.max (g.aspect, 0.01));
                m.rotate (-angle);
                m.translate (-g.x1, -g.y1);
                var inv = m;
                double fx = g.fx, fy = g.fy;
                if (inv.invert () == Cairo.Status.SUCCESS) inv.transform_point (ref fx, ref fy);
                else inv = Cairo.Matrix.identity ();
                if (Math.hypot (fx - g.x1, fy - g.y1) > r * 0.98) {
                    fx = g.x1;
                    fy = g.y1;
                }
                pat = new Cairo.Pattern.radial (fx, fy, 0, g.x1, g.y1, double.max (r, 0.001));
                pat.set_matrix (inv);
            } else {
                pat = new Cairo.Pattern.linear (g.x1, g.y1, g.x2, g.y2);
            }
            var stops = new Gee.ArrayList<GradientStop> ();
            stops.add_all (g.stops);
            stops.sort ((a, b) => a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
            for (int i = 0; i < stops.size; i++) {
                var s = stops[i];
                var c = ctx != null ? resolve_ink (s.color, ctx) : s.color;
                pat.add_color_stop_rgba (s.offset.clamp (0, 1), c.r, c.g, c.b, s.opacity);
                if (i + 1 < stops.size && (s.midpoint - 0.5).abs () > 0.01) {
                    var n = stops[i + 1];
                    var nc = ctx != null ? resolve_ink (n.color, ctx) : n.color;
                    double off = s.offset + (n.offset - s.offset) * s.midpoint.clamp (0.05, 0.95);
                    pat.add_color_stop_rgba (off, (c.r + nc.r) / 2, (c.g + nc.g) / 2, (c.b + nc.b) / 2, (s.opacity + n.opacity) / 2);
                }
            }
            switch (g.spread) {
                case "reflect": pat.set_extend (Cairo.Extend.REFLECT); break;
                case "repeat": pat.set_extend (Cairo.Extend.REPEAT); break;
                default: pat.set_extend (Cairo.Extend.PAD); break;
            }
            return pat;
        }

        public static Cairo.Pattern freeform_pattern (Paint paint, Rect box, RenderContext? ctx) {
            var pts = new Gee.ArrayList<FreeformPoint> ();
            pts.add_all (paint.freeform);
            if (pts.size == 0) return new Cairo.Pattern.rgb (0.5, 0.5, 0.5);
            var all = new Gee.ArrayList<Point?> ();
            var colors = new Gee.ArrayList<Ink> ();
            foreach (var f in pts) {
                all.add (Point (f.x, f.y));
                colors.add (ctx != null ? resolve_ink (f.color, ctx) : f.color);
            }
            var b = box.inflate (2);
            Point[] corners = { Point (b.x, b.y), Point (b.x + b.w, b.y), Point (b.x + b.w, b.y + b.h), Point (b.x, b.y + b.h), Point (b.cx (), b.y), Point (b.x + b.w, b.cy ()), Point (b.cx (), b.y + b.h), Point (b.x, b.cy ()) };
            foreach (var c in corners) {
                all.add (c);
                colors.add (idw (pts, c, ctx));
            }
            var tris = Delaunay.triangulate (all);
            var mesh = new Cairo.MeshPattern ();
            for (int i = 0; i + 2 < tris.size; i += 3) {
                int a = tris[i], bb = tris[i + 1], c = tris[i + 2];
                mesh.begin_patch ();
                mesh.move_to (all[a].x, all[a].y);
                mesh.line_to (all[bb].x, all[bb].y);
                mesh.line_to (all[c].x, all[c].y);
                mesh.set_corner_color_rgb (0, colors[a].r, colors[a].g, colors[a].b);
                mesh.set_corner_color_rgb (1, colors[bb].r, colors[bb].g, colors[bb].b);
                mesh.set_corner_color_rgb (2, colors[c].r, colors[c].g, colors[c].b);
                mesh.end_patch ();
            }
            return mesh;
        }

        private static Ink idw (Gee.List<FreeformPoint> pts, Point p, RenderContext? ctx) {
            double wr = 0, wg = 0, wb = 0, wsum = 0;
            foreach (var f in pts) {
                double d = Math.hypot (f.x - p.x, f.y - p.y) / double.max (f.spread, 0.05);
                double w = 1 / double.max (d * d, 1e-6);
                var c = ctx != null ? resolve_ink (f.color, ctx) : f.color;
                wr += c.r * w;
                wg += c.g * w;
                wb += c.b * w;
                wsum += w;
            }
            return new Ink.rgb (wr / wsum, wg / wsum, wb / wsum);
        }

        public static Cairo.Pattern? pattern_source (Paint paint, RenderContext ctx) {
            var def = ctx.doc.find_pattern (paint.pattern);
            if (def == null) return null;
            double tw = def.w + def.hspace, th = def.h + def.vspace;
            double pw = tw, ph = th;
            if (def.tiling == "brick-row" || def.tiling == "hex-row") ph = th * 2;
            if (def.tiling == "brick-col" || def.tiling == "hex-col") pw = tw * 2;
            if (def.tiling == "hex-row") ph = th * 1.5;
            if (def.tiling == "hex-col") pw = tw * 1.5;
            var rec = new Cairo.RecordingSurface (Cairo.Content.COLOR_ALPHA, Cairo.Rectangle () { x = 0, y = 0, width = pw, height = ph });
            var rc = new Cairo.Context (rec);
            var tile_box = def.tile.geometric_bounds ();
            double ox = tile_box.w >= 0 ? -tile_box.x : 0, oy = tile_box.w >= 0 ? -tile_box.y : 0;
            double[] dx = { 0 }, dy = { 0 };
            switch (def.tiling) {
                case "brick-row":
                    dx = { 0, def.offset * tw, def.offset * tw - tw };
                    dy = { 0, th, th };
                    break;
                case "brick-col":
                    dx = { 0, tw, tw };
                    dy = { 0, def.offset * th, def.offset * th - th };
                    break;
                case "hex-row":
                    dx = { 0, tw / 2, -tw / 2 };
                    dy = { 0, th * 0.75, th * 0.75 };
                    break;
                case "hex-col":
                    dx = { 0, tw * 0.75, tw * 0.75 };
                    dy = { 0, th / 2, -th / 2 };
                    break;
            }
            for (int i = 0; i < dx.length; i++) {
                foreach (double wx in new double[] { 0, pw, -pw }) {
                    foreach (double wy in new double[] { 0, ph, -ph }) {
                        rc.save ();
                        rc.translate (ox + dx[i] + wx, oy + dy[i] + wy);
                        draw_node (rc, def.tile, ctx);
                        rc.restore ();
                    }
                }
            }
            var pat = new Cairo.Pattern.for_surface (rec);
            pat.set_extend (Cairo.Extend.REPEAT);
            var inv = paint.pattern_matrix;
            if (inv.invert () == Cairo.Status.SUCCESS) pat.set_matrix (inv);
            return pat;
        }

        public static Cairo.Surface? image_surface (ImageNode im, VectorDocument doc) {
            if (image_cache == null) image_cache = new Gee.HashMap<string, Cairo.Surface> ();
            string key = im.link != "" ? "link:" + im.link : "asset:" + im.asset;
            if (image_cache.has_key (key)) return image_cache[key];
            Gdk.Pixbuf? pix = null;
            try {
                if (im.link != "" && FileUtils.test (im.link, FileTest.EXISTS)) {
                    pix = new Gdk.Pixbuf.from_file (im.link);
                    im.missing = false;
                } else if (doc.assets.has_key (im.asset)) {
                    var stream = new MemoryInputStream.from_bytes (doc.assets[im.asset].data);
                    pix = new Gdk.Pixbuf.from_stream (stream);
                    if (im.link != "") im.missing = true;
                }
            } catch (Error e) {
                pix = null;
            }
            if (pix == null) return null;
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pix.width, pix.height);
            var c = new Cairo.Context (surface);
            Gdk.cairo_set_source_pixbuf (c, pix, 0, 0);
            c.paint ();
            image_cache[key] = surface;
            return surface;
        }

        public static void forget_image (string key) {
            if (image_cache != null) image_cache.unset (key);
        }

        public static void clear_images () {
            if (image_cache != null) image_cache.clear ();
        }

        private static void draw_image (Cairo.Context cr, ImageNode im, RenderContext ctx) {
            var surface = image_surface (im, ctx.doc);
            cr.save ();
            cr.transform (im.matrix);
            if (surface == null) {
                cr.rectangle (0, 0, im.pixel_width, im.pixel_height);
                cr.set_source_rgba (0.85, 0.2, 0.2, 0.25);
                cr.fill_preserve ();
                cr.set_source_rgb (0.85, 0.2, 0.2);
                cr.set_line_width (2);
                cr.stroke ();
                cr.restore ();
                return;
            }
            var img = (Cairo.ImageSurface) surface;
            cr.scale (im.pixel_width / (double) img.get_width (), im.pixel_height / (double) img.get_height ());
            cr.set_source_surface (surface, 0, 0);
            cr.get_source ().set_filter (Cairo.Filter.GOOD);
            cr.rectangle (0, 0, img.get_width (), img.get_height ());
            cr.fill ();
            cr.restore ();
        }

        public static void draw_mesh (Cairo.Context cr, MeshNode me) {
            var mesh = new Cairo.MeshPattern ();
            for (int r = 0; r < me.rows; r++) {
                for (int c = 0; c < me.cols; c++) {
                    var p00 = me.at (r, c);
                    var p01 = me.at (r, c + 1);
                    var p11 = me.at (r + 1, c + 1);
                    var p10 = me.at (r + 1, c);
                    int top = (r * me.cols + c) * 4;
                    int bottom = ((r + 1) * me.cols + c) * 4;
                    int left = (r * (me.cols + 1) + c) * 4;
                    int right = (r * (me.cols + 1) + c + 1) * 4;
                    mesh.begin_patch ();
                    mesh.move_to (p00.x, p00.y);
                    mesh.curve_to (me.hcontrols[top], me.hcontrols[top + 1], me.hcontrols[top + 2], me.hcontrols[top + 3], p01.x, p01.y);
                    mesh.curve_to (me.vcontrols[right], me.vcontrols[right + 1], me.vcontrols[right + 2], me.vcontrols[right + 3], p11.x, p11.y);
                    mesh.curve_to (me.hcontrols[bottom + 2], me.hcontrols[bottom + 3], me.hcontrols[bottom], me.hcontrols[bottom + 1], p10.x, p10.y);
                    mesh.curve_to (me.vcontrols[left + 2], me.vcontrols[left + 3], me.vcontrols[left], me.vcontrols[left + 1], p00.x, p00.y);
                    MeshVertex[] corners = { p00, p01, p11, p10 };
                    for (uint k = 0; k < 4; k++) mesh.set_corner_color_rgba (k, corners[k].color.r, corners[k].color.g, corners[k].color.b, corners[k].opacity);
                    mesh.end_patch ();
                }
            }
            cr.save ();
            cr.set_source (mesh);
            var o = me.outline ();
            cr.new_path ();
            o.to_cairo (cr);
            cr.fill ();
            cr.restore ();
        }

        public static Cairo.ImageSurface render_image (VectorDocument doc, Rect area, double scale, bool transparent = true, bool proof = false) {
            int w = int.max (1, (int) Math.ceil (area.w * scale));
            int h = int.max (1, (int) Math.ceil (area.h * scale));
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            if (!transparent) {
                cr.set_source_rgb (1, 1, 1);
                cr.paint ();
            }
            cr.scale (scale, scale);
            cr.translate (-area.x, -area.y);
            var ctx = new RenderContext (doc);
            ctx.print = true;
            ctx.hide_templates = true;
            draw_document (cr, ctx);
            surface.flush ();
            if (proof) ColorManager.get_default ().proof (surface);
            return surface;
        }
    }

    public class Delaunay {
        public static Gee.ArrayList<int> triangulate (Gee.List<Point?> pts) {
            var tris = new Gee.ArrayList<int> ();
            int n = pts.size;
            if (n < 3) return tris;
            double minx = double.INFINITY, miny = double.INFINITY, maxx = -double.INFINITY, maxy = -double.INFINITY;
            foreach (var p in pts) {
                minx = double.min (minx, p.x);
                miny = double.min (miny, p.y);
                maxx = double.max (maxx, p.x);
                maxy = double.max (maxy, p.y);
            }
            double d = double.max (maxx - minx, maxy - miny) * 20 + 1;
            var all = new Gee.ArrayList<Point?> ();
            all.add_all (pts);
            all.add (Point (minx - d, miny - d));
            all.add (Point (minx + d * 2, miny - d));
            all.add (Point (minx - d, miny + d * 2));
            var list = new Gee.ArrayList<int> ();
            list.add (n);
            list.add (n + 1);
            list.add (n + 2);
            for (int i = 0; i < n; i++) {
                var p = all[i];
                var bad = new Gee.ArrayList<int> ();
                for (int t = 0; t < list.size; t += 3) {
                    if (in_circle (all[list[t]], all[list[t + 1]], all[list[t + 2]], p)) bad.add (t);
                }
                var edges = new Gee.ArrayList<int> ();
                foreach (int t in bad) {
                    for (int e = 0; e < 3; e++) {
                        int a = list[t + e], b = list[t + (e + 1) % 3];
                        bool shared = false;
                        foreach (int u in bad) {
                            if (u == t) continue;
                            for (int f = 0; f < 3; f++) {
                                int c = list[u + f], dd = list[u + (f + 1) % 3];
                                if ((a == c && b == dd) || (a == dd && b == c)) shared = true;
                            }
                        }
                        if (!shared) {
                            edges.add (a);
                            edges.add (b);
                        }
                    }
                }
                var next = new Gee.ArrayList<int> ();
                for (int t = 0; t < list.size; t += 3) {
                    if (bad.contains (t)) continue;
                    next.add (list[t]);
                    next.add (list[t + 1]);
                    next.add (list[t + 2]);
                }
                for (int e = 0; e < edges.size; e += 2) {
                    next.add (edges[e]);
                    next.add (edges[e + 1]);
                    next.add (i);
                }
                list = next;
            }
            for (int t = 0; t < list.size; t += 3) {
                if (list[t] >= n || list[t + 1] >= n || list[t + 2] >= n) continue;
                tris.add (list[t]);
                tris.add (list[t + 1]);
                tris.add (list[t + 2]);
            }
            return tris;
        }

        private static bool in_circle (Point a, Point b, Point c, Point p) {
            double ax = a.x - p.x, ay = a.y - p.y;
            double bx = b.x - p.x, by = b.y - p.y;
            double cx = c.x - p.x, cy = c.y - p.y;
            double det = (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay);
            double orient = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
            return orient > 0 ? det > 0 : det < 0;
        }
    }
}
