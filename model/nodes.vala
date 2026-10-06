using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public enum HandleMode { AUTO, CORNER, SMOOTH, SYMMETRIC }

    public abstract class Node : Object {
        public string id = "";
        public string name = "";
        public bool hidden = false;
        public bool locked = false;
        public double opacity = 1;
        public BlendMode blend = BlendMode.NORMAL;
        public bool isolate = false;
        public bool knockout = false;
        public Gee.ArrayList<PaintLayer> appearance = new Gee.ArrayList<PaintLayer> ();
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();
        public Node? mask = null;
        public bool mask_clip = true;
        public bool mask_invert = false;
        public string style_id = "";
        public string note = "";
        public weak GroupNode? parent = null;
        private WeakRef owner;

        public void set_document (VectorDocument? d) {
            owner.set (d);
        }

        public VectorDocument? document () {
            var o = owner.get ();
            return o != null ? (VectorDocument) o : null;
        }

        public abstract string kind_name ();
        public abstract Node make_empty ();
        public abstract Rect geometric_bounds ();
        public abstract void apply_transform (Cairo.Matrix m, bool scale_strokes = true);

        public virtual PathData? outline () {
            return null;
        }

        public virtual void copy_into (Node target) {
            copy_common (target);
            target.set_document (document ());
        }

        public void copy_common (Node target) {
            target.id = id;
            target.name = name;
            target.hidden = hidden;
            target.locked = locked;
            target.opacity = opacity;
            target.blend = blend;
            target.isolate = isolate;
            target.knockout = knockout;
            target.appearance.clear ();
            foreach (var l in appearance) target.appearance.add (l.copy ());
            target.effects.clear ();
            foreach (var e in effects) target.effects.add (e.copy ());
            target.mask = mask != null ? mask.clone () : null;
            target.mask_clip = mask_clip;
            target.mask_invert = mask_invert;
            target.style_id = style_id;
            target.note = note;
        }

        public Node clone () {
            var n = make_empty ();
            copy_into (n);
            return n;
        }

        public PaintLayer? first_fill () {
            foreach (var l in appearance) if (!l.stroke) return l;
            return null;
        }

        public PaintLayer? first_stroke () {
            foreach (var l in appearance) if (l.stroke) return l;
            return null;
        }

        public PaintLayer ensure_fill () {
            var f = first_fill ();
            if (f == null) {
                f = new PaintLayer.fill (new Paint ());
                appearance.insert (0, f);
            }
            return f;
        }

        public PaintLayer ensure_stroke () {
            var s = first_stroke ();
            if (s == null) {
                s = new PaintLayer.line (new Paint (), 1);
                appearance.add (s);
            }
            return s;
        }

        public void set_basic (Paint fill, Paint stroke, double width) {
            appearance.clear ();
            appearance.add (new PaintLayer.fill (fill));
            appearance.add (new PaintLayer.line (stroke, width));
        }

        public double stroke_margin () {
            double m = 0;
            foreach (var l in appearance) {
                if (!l.stroke || !l.paint.visible ()) continue;
                double w = l.width * (l.align == StrokeAlign.OUTSIDE ? 1 : (l.align == StrokeAlign.INSIDE ? 0 : 0.5));
                if (l.join == JoinKind.MITER) w *= double.min (l.miter, 4);
                m = double.max (m, w);
            }
            foreach (var e in effects) {
                if (!e.enabled) continue;
                if (e.kind == "drop-shadow") m = double.max (m, e.get_num ("blur", 5) * 2 + double.max (e.get_num ("dx", 7).abs (), e.get_num ("dy", 7).abs ()));
                else if (e.kind == "outer-glow" || e.kind == "blur") m = double.max (m, e.get_num ("blur", 5) * 2);
                else if (e.kind == "offset") m = double.max (m, e.get_num ("distance", 10).abs ());
                else if (e.kind == "roughen" || e.kind == "zigzag") m = double.max (m, e.get_num ("size", 5));
            }
            return m;
        }

        public Rect visual_bounds () {
            var b = geometric_bounds ();
            if (b.w < 0) return b;
            return b.inflate (stroke_margin ());
        }

        public bool effectively_hidden () {
            Node? n = this;
            while (n != null) {
                if (n.hidden) return true;
                n = n.parent;
            }
            return false;
        }

        public bool effectively_locked () {
            Node? n = this;
            while (n != null) {
                if (n.locked) return true;
                n = n.parent;
            }
            return false;
        }

        public GroupNode? layer () {
            Node? n = this;
            while (n != null) {
                var g = n as GroupNode;
                if (g != null && g.is_layer && (g.parent == null || !(g.parent is GroupNode) || !((GroupNode) g.parent).is_layer)) return g;
                n = n.parent;
            }
            return null;
        }

        public virtual string display_name () {
            return name != "" ? name : kind_label ();
        }

        public virtual string kind_label () {
            return kind_name ();
        }
    }

    public class LiveShape : Object {
        public string kind = "rectangle";
        public double cx;
        public double cy;
        public double w;
        public double h;
        public double angle = 0;
        public double radius = 0;
        public int sides = 6;
        public double inner = 0.5;
        public double x2 = 0;
        public double y2 = 0;

        public LiveShape copy () {
            var o = new LiveShape ();
            o.kind = kind;
            o.cx = cx;
            o.cy = cy;
            o.w = w;
            o.h = h;
            o.angle = angle;
            o.radius = radius;
            o.sides = sides;
            o.inner = inner;
            o.x2 = x2;
            o.y2 = y2;
            return o;
        }

        public PathData build () {
            PathData p;
            switch (kind) {
                case "ellipse":
                    p = new PathData.ellipse (0, 0, w / 2, h / 2);
                    break;
                case "polygon":
                    p = new PathData ();
                    for (int i = 0; i < sides; i++) {
                        double a = -Math.PI / 2 + i * 2 * Math.PI / sides;
                        if (i == 0) p.move_to (Math.cos (a) * w / 2, Math.sin (a) * h / 2);
                        else p.line_to (Math.cos (a) * w / 2, Math.sin (a) * h / 2);
                    }
                    p.close ();
                    break;
                case "star":
                    p = new PathData ();
                    for (int i = 0; i < sides * 2; i++) {
                        double a = -Math.PI / 2 + i * Math.PI / sides;
                        double f = i % 2 == 0 ? 1 : inner;
                        if (i == 0) p.move_to (Math.cos (a) * w / 2 * f, Math.sin (a) * h / 2 * f);
                        else p.line_to (Math.cos (a) * w / 2 * f, Math.sin (a) * h / 2 * f);
                    }
                    p.close ();
                    break;
                case "line":
                    p = new PathData ();
                    p.move_to (cx, cy);
                    p.line_to (x2, y2);
                    return p;
                default:
                    if (radius > 0) p = new PathData.round_rect (-w / 2, -h / 2, w, h, double.min (radius, double.min (w, h) / 2));
                    else p = new PathData.rect (-w / 2, -h / 2, w, h);
                    break;
            }
            if (kind == "polygon" || kind == "star") {
                if (radius > 0) p = LiveCorners.apply (p, new Gee.HashMap<int, double?> (), null, radius);
            }
            var m = Cairo.Matrix.identity ();
            m.translate (cx, cy);
            m.rotate (angle);
            p.transform (m);
            return p;
        }

        public bool transform_live (Cairo.Matrix t) {
            if (kind == "line") {
                t.transform_point (ref cx, ref cy);
                t.transform_point (ref x2, ref y2);
                return true;
            }
            double ax = 1, ay = 0, bx = 0, by = 1;
            var r = Cairo.Matrix.identity ();
            r.rotate (angle);
            r.transform_distance (ref ax, ref ay);
            r.transform_distance (ref bx, ref by);
            t.transform_distance (ref ax, ref ay);
            t.transform_distance (ref bx, ref by);
            double dot = ax * bx + ay * by;
            if (dot.abs () > 1e-6 * Math.hypot (ax, ay) * Math.hypot (bx, by)) return false;
            double sa = Math.hypot (ax, ay), sb = Math.hypot (bx, by);
            double cross = ax * by - ay * bx;
            if (cross < 0) return false;
            t.transform_point (ref cx, ref cy);
            w *= sa;
            h *= sb;
            radius *= Math.sqrt (sa * sb);
            angle = Math.atan2 (ay, ax);
            return true;
        }
    }

    public class PathNode : Node {
        public PathData path = new PathData ();
        public bool even_odd = false;
        public LiveShape? live = null;
        public Gee.HashMap<int, int> modes = new Gee.HashMap<int, int> ();
        public Gee.HashMap<int, double?> corners = new Gee.HashMap<int, double?> ();
        public Gee.HashMap<int, int> corner_kinds = new Gee.HashMap<int, int> ();
        public bool guide = false;

        public PathNode () {
        }

        public PathNode.with_path (PathData path) {
            this.path = path;
        }

        public override string kind_name () {
            return "path";
        }

        public override string kind_label () {
            if (live != null) {
                switch (live.kind) {
                    case "ellipse": return _("Ellipse");
                    case "polygon": return _("Polygon");
                    case "star": return _("Star");
                    case "line": return _("Line");
                    default: return live.radius > 0 ? _("Rounded Rectangle") : _("Rectangle");
                }
            }
            if (PathOps.contours (path).size > 1) return _("Compound Path");
            return _("Path");
        }

        public override Node make_empty () {
            return new PathNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (PathNode) target;
            t.path = path.copy ();
            t.even_odd = even_odd;
            t.live = live != null ? live.copy () : null;
            t.modes.clear ();
            foreach (var kv in modes.entries) t.modes[kv.key] = kv.value;
            t.corners.clear ();
            foreach (var kv in corners.entries) t.corners[kv.key] = kv.value;
            t.corner_kinds.clear ();
            foreach (var kv in corner_kinds.entries) t.corner_kinds[kv.key] = kv.value;
            t.guide = guide;
        }

        public PathData render_path () {
            if (corners.size == 0) return path;
            return LiveCorners.apply (path, corners, corner_kinds);
        }

        public override PathData? outline () {
            return render_path ();
        }

        public override Rect geometric_bounds () {
            return PathOps.tight_bounds (render_path ());
        }

        public HandleMode mode_at (int index) {
            return modes.has_key (index) ? (HandleMode) modes[index] : HandleMode.AUTO;
        }

        public void rebuild_live () {
            if (live != null) path = live.build ();
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            var before = geometric_bounds ();
            if (live != null && !live.transform_live (m)) live = null;
            if (live != null) rebuild_live ();
            else path.transform (m);
            Transforms.after_transform (this, before, m, scale_strokes);
        }

        public bool closed () {
            return PathOps.all_closed (path);
        }
    }

    public class GroupNode : Node {
        public Gee.ArrayList<Node> children = new Gee.ArrayList<Node> ();
        public bool is_layer = false;
        public bool clip = false;
        public string color = "#4a90d9";
        public bool printable = true;
        public bool template = false;

        public override string kind_name () {
            return is_layer ? "layer" : "group";
        }

        public override string kind_label () {
            if (is_layer) return _("Layer");
            return clip ? _("Clip Group") : _("Group");
        }

        public override Node make_empty () {
            return new GroupNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (GroupNode) target;
            t.children.clear ();
            foreach (var c in children) {
                var cc = c.clone ();
                cc.parent = t;
                t.children.add (cc);
            }
            t.is_layer = is_layer;
            t.clip = clip;
            t.color = color;
            t.printable = printable;
            t.template = template;
        }

        public void add (Node n, int index = -1) {
            if (n.parent != null) n.parent.children.remove (n);
            n.parent = this;
            if (index < 0 || index > children.size) children.add (n);
            else children.insert (index, n);
        }

        public void remove (Node n) {
            children.remove (n);
            if (n.parent == this) n.parent = null;
        }

        public Node? clip_path () {
            if (!clip || children.size == 0) return null;
            return children[0];
        }

        public virtual GroupNode? generated (VectorDocument? doc) {
            return null;
        }

        public override Rect geometric_bounds () {
            var cp = clip_path ();
            if (cp != null) return cp.geometric_bounds ();
            var gen = generated (null);
            var list = gen != null ? gen.children : children;
            var box = Rect.empty ();
            bool first = true;
            foreach (var c in list) {
                if (c.hidden) continue;
                var b = c.geometric_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            if (first) return Rect (0, 0, -1, -1);
            return box;
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            foreach (var c in children) c.apply_transform (m, scale_strokes);
            if (mask != null) mask.apply_transform (m, scale_strokes);
            Transforms.after_transform (this, Rect (0, 0, -1, -1), m, scale_strokes, false);
        }

        public override PathData? outline () {
            var cp = clip_path ();
            if (cp != null) return cp.outline ();
            var all = new PathData ();
            foreach (var c in children) {
                var o = c.outline ();
                if (o != null) all.append (o);
            }
            return all;
        }

        public void walk (WalkFunc f) {
            foreach (var c in children) {
                if (!f (c)) continue;
                var g = c as GroupNode;
                if (g != null) g.walk (f);
            }
        }
    }

    public delegate bool WalkFunc (Node n);

    public class CharStyle : Object {
        public string family = "Sans";
        public double size = 24;
        public int weight = 400;
        public bool italic = false;
        public double tracking = 0;
        public double leading = 0;
        public double baseline = 0;
        public double hscale = 1;
        public double vscale = 1;
        public bool underline = false;
        public bool strike = false;
        public string caps = "none";
        public string features = "";
        public string language = "";
        public Ink? color = null;

        public CharStyle copy () {
            var o = new CharStyle ();
            o.family = family;
            o.size = size;
            o.weight = weight;
            o.italic = italic;
            o.tracking = tracking;
            o.leading = leading;
            o.baseline = baseline;
            o.hscale = hscale;
            o.vscale = vscale;
            o.underline = underline;
            o.strike = strike;
            o.caps = caps;
            o.features = features;
            o.language = language;
            o.color = color != null ? color.copy () : null;
            return o;
        }
    }

    public class ParaStyle : Object {
        public string align = "left";
        public double indent_first = 0;
        public double indent_left = 0;
        public double indent_right = 0;
        public double space_before = 0;
        public double space_after = 0;
        public bool hyphenate = false;

        public ParaStyle copy () {
            var o = new ParaStyle ();
            o.align = align;
            o.indent_first = indent_first;
            o.indent_left = indent_left;
            o.indent_right = indent_right;
            o.space_before = space_before;
            o.space_after = space_after;
            o.hyphenate = hyphenate;
            return o;
        }
    }

    public class TextRun : Object {
        public int start;
        public int end;
        public CharStyle style;

        public TextRun (int start, int end, CharStyle style) {
            this.start = start;
            this.end = end;
            this.style = style;
        }

        public TextRun copy () {
            return new TextRun (start, end, style.copy ());
        }
    }

    public class TextNode : Node {
        public string text = "";
        public string mode = "point";
        public Cairo.Matrix matrix;
        public CharStyle style = new CharStyle ();
        public ParaStyle para = new ParaStyle ();
        public Gee.ArrayList<TextRun> runs = new Gee.ArrayList<TextRun> ();
        public PathData? area = null;
        public PathData? on_path = null;
        public double path_offset = 0;
        public bool path_flip = false;
        public string thread_next = "";
        public int columns = 1;
        public double gutter = 12;
        public double inset = 0;

        public TextNode () {
            matrix = Cairo.Matrix.identity ();
        }

        public override string kind_name () {
            return "text";
        }

        public override string kind_label () {
            switch (mode) {
                case "area": return _("Area Text");
                case "path": return _("Text on Path");
                default: return _("Text");
            }
        }

        public override string display_name () {
            if (name != "") return name;
            string t = text.replace ("\n", " ").strip ();
            if (t.char_count () > 24) t = t.substring (0, t.index_of_nth_char (24)) + "...";
            return t != "" ? t : kind_label ();
        }

        public override Node make_empty () {
            return new TextNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (TextNode) target;
            t.text = text;
            t.mode = mode;
            t.matrix = matrix;
            t.style = style.copy ();
            t.para = para.copy ();
            t.runs.clear ();
            foreach (var r in runs) t.runs.add (r.copy ());
            t.area = area != null ? area.copy () : null;
            t.on_path = on_path != null ? on_path.copy () : null;
            t.path_offset = path_offset;
            t.path_flip = path_flip;
            t.thread_next = thread_next;
            t.columns = columns;
            t.gutter = gutter;
            t.inset = inset;
        }

        public override Rect geometric_bounds () {
            return TextLayout.bounds (this);
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            if (mode == "area" && area != null) {
                area.transform (m);
            } else if (mode == "path" && on_path != null) {
                on_path.transform (m);
            } else {
                Cairo.Matrix r;
                r = Transforms.multiply (matrix, m);
                matrix = r;
            }
            Transforms.after_transform (this, Rect (0, 0, -1, -1), m, scale_strokes, false);
        }

        public override PathData? outline () {
            return TextLayout.to_path (this);
        }
    }

    public class ImageNode : Node {
        public string asset = "";
        public string link = "";
        public string mime = "image/png";
        public int pixel_width = 1;
        public int pixel_height = 1;
        public Cairo.Matrix matrix;
        public bool missing = false;

        public ImageNode () {
            matrix = Cairo.Matrix.identity ();
        }

        public override string kind_name () {
            return "image";
        }

        public override string kind_label () {
            return link != "" ? _("Linked Image") : _("Image");
        }

        public override Node make_empty () {
            return new ImageNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (ImageNode) target;
            t.asset = asset;
            t.link = link;
            t.mime = mime;
            t.pixel_width = pixel_width;
            t.pixel_height = pixel_height;
            t.matrix = matrix;
            t.missing = missing;
        }

        public override Rect geometric_bounds () {
            return Transforms.rect_bounds (Rect (0, 0, pixel_width, pixel_height), matrix);
        }

        public override PathData? outline () {
            var p = new PathData.rect (0, 0, pixel_width, pixel_height);
            p.transform (matrix);
            return p;
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            matrix = Transforms.multiply (matrix, m);
            Transforms.after_transform (this, Rect (0, 0, -1, -1), m, scale_strokes, false);
        }
    }

    public class SymbolNode : Node {
        public string symbol = "";
        public Cairo.Matrix matrix;
        public Gee.HashMap<string, string> overrides = new Gee.HashMap<string, string> ();
        public VectorDocument? doc {
            owned get {
                return document ();
            }
            set {
                set_document (value);
            }
        }

        public SymbolNode () {
            matrix = Cairo.Matrix.identity ();
        }

        public override string kind_name () {
            return "symbol";
        }

        public override string kind_label () {
            return _("Symbol Instance");
        }

        public override Node make_empty () {
            return new SymbolNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (SymbolNode) target;
            t.symbol = symbol;
            t.matrix = matrix;
            t.set_document (document ());
            t.overrides.clear ();
            foreach (var kv in overrides.entries) t.overrides[kv.key] = kv.value;
        }

        public GroupNode? resolve (VectorDocument? d = null) {
            var document = d ?? doc;
            if (document == null) return null;
            var def = document.find_symbol (symbol);
            if (def == null) return null;
            var art = def.art.clone () as GroupNode;
            if (overrides.size > 0) {
                art.walk ((n) => {
                    if (overrides.has_key (n.id)) {
                        var f = n.first_fill ();
                        if (f != null) f.paint = new Paint.hex (overrides[n.id]);
                    }
                    return true;
                });
            }
            art.apply_transform (matrix, true);
            return art;
        }

        public override Rect geometric_bounds () {
            var art = resolve ();
            if (art == null) return Transforms.rect_bounds (Rect (0, 0, 10, 10), matrix);
            return art.geometric_bounds ();
        }

        public override PathData? outline () {
            var art = resolve ();
            return art != null ? art.outline () : null;
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            matrix = Transforms.multiply (matrix, m);
            Transforms.after_transform (this, Rect (0, 0, -1, -1), m, scale_strokes, false);
        }
    }

    public class MeshVertex : Object {
        public double x;
        public double y;
        public Ink color;
        public double opacity = 1;

        public MeshVertex (double x, double y, Ink color) {
            this.x = x;
            this.y = y;
            this.color = color;
        }

        public MeshVertex copy () {
            var v = new MeshVertex (x, y, color.copy ());
            v.opacity = opacity;
            return v;
        }
    }

    public class MeshNode : Node {
        public int rows = 2;
        public int cols = 2;
        public Gee.ArrayList<MeshVertex> vertices = new Gee.ArrayList<MeshVertex> ();
        public double[] hcontrols = {};
        public double[] vcontrols = {};

        public override string kind_name () {
            return "mesh";
        }

        public override string kind_label () {
            return _("Gradient Mesh");
        }

        public override Node make_empty () {
            return new MeshNode ();
        }

        public override void copy_into (Node target) {
            base.copy_into (target);
            var t = (MeshNode) target;
            t.rows = rows;
            t.cols = cols;
            t.vertices.clear ();
            foreach (var v in vertices) t.vertices.add (v.copy ());
            t.hcontrols = hcontrols;
            t.vcontrols = vcontrols;
        }

        public MeshVertex at (int r, int c) {
            return vertices[r * (cols + 1) + c];
        }

        public void init_grid (Rect box, int rows, int cols, Ink base_color) {
            this.rows = rows;
            this.cols = cols;
            vertices.clear ();
            for (int r = 0; r <= rows; r++) {
                for (int c = 0; c <= cols; c++) vertices.add (new MeshVertex (box.x + box.w * c / cols, box.y + box.h * r / rows, base_color.copy ()));
            }
            reset_controls ();
        }

        public void reset_controls () {
            hcontrols = new double[rows * 0 + (rows + 1) * cols * 4];
            vcontrols = new double[(cols + 1) * rows * 4];
            for (int r = 0; r <= rows; r++) {
                for (int c = 0; c < cols; c++) {
                    var a = at (r, c);
                    var b = at (r, c + 1);
                    int i = (r * cols + c) * 4;
                    hcontrols[i] = a.x + (b.x - a.x) / 3;
                    hcontrols[i + 1] = a.y + (b.y - a.y) / 3;
                    hcontrols[i + 2] = a.x + (b.x - a.x) * 2 / 3;
                    hcontrols[i + 3] = a.y + (b.y - a.y) * 2 / 3;
                }
            }
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c <= cols; c++) {
                    var a = at (r, c);
                    var b = at (r + 1, c);
                    int i = (r * (cols + 1) + c) * 4;
                    vcontrols[i] = a.x + (b.x - a.x) / 3;
                    vcontrols[i + 1] = a.y + (b.y - a.y) / 3;
                    vcontrols[i + 2] = a.x + (b.x - a.x) * 2 / 3;
                    vcontrols[i + 3] = a.y + (b.y - a.y) * 2 / 3;
                }
            }
        }

        public void move_vertex (int r, int c, double dx, double dy) {
            var v = at (r, c);
            v.x += dx;
            v.y += dy;
            if (c > 0) {
                int i = (r * cols + c - 1) * 4;
                hcontrols[i + 2] += dx;
                hcontrols[i + 3] += dy;
            }
            if (c < cols) {
                int i = (r * cols + c) * 4;
                hcontrols[i] += dx;
                hcontrols[i + 1] += dy;
            }
            if (r > 0) {
                int i = ((r - 1) * (cols + 1) + c) * 4;
                vcontrols[i + 2] += dx;
                vcontrols[i + 3] += dy;
            }
            if (r < rows) {
                int i = (r * (cols + 1) + c) * 4;
                vcontrols[i] += dx;
                vcontrols[i + 1] += dy;
            }
        }

        public override Rect geometric_bounds () {
            var box = Rect.empty ();
            bool first = true;
            foreach (var v in vertices) {
                box = first ? Rect (v.x, v.y, 0, 0) : box.include (v.x, v.y);
                first = false;
            }
            return box;
        }

        public override PathData? outline () {
            var p = new PathData ();
            if (vertices.size == 0) return p;
            var a = at (0, 0);
            p.move_to (a.x, a.y);
            for (int c = 0; c < cols; c++) {
                int i = c * 4;
                var b = at (0, c + 1);
                p.curve_to (hcontrols[i], hcontrols[i + 1], hcontrols[i + 2], hcontrols[i + 3], b.x, b.y);
            }
            for (int r = 0; r < rows; r++) {
                int i = (r * (cols + 1) + cols) * 4;
                var b = at (r + 1, cols);
                p.curve_to (vcontrols[i], vcontrols[i + 1], vcontrols[i + 2], vcontrols[i + 3], b.x, b.y);
            }
            for (int c = cols - 1; c >= 0; c--) {
                int i = (rows * cols + c) * 4;
                var b = at (rows, c);
                p.curve_to (hcontrols[i + 2], hcontrols[i + 3], hcontrols[i], hcontrols[i + 1], b.x, b.y);
            }
            for (int r = rows - 1; r >= 0; r--) {
                int i = (r * (cols + 1)) * 4;
                var b = at (r, 0);
                p.curve_to (vcontrols[i + 2], vcontrols[i + 3], vcontrols[i], vcontrols[i + 1], b.x, b.y);
            }
            p.close ();
            return p;
        }

        public override void apply_transform (Cairo.Matrix m, bool scale_strokes = true) {
            foreach (var v in vertices) m.transform_point (ref v.x, ref v.y);
            for (int i = 0; i + 1 < hcontrols.length; i += 2) m.transform_point (ref hcontrols[i], ref hcontrols[i + 1]);
            for (int i = 0; i + 1 < vcontrols.length; i += 2) m.transform_point (ref vcontrols[i], ref vcontrols[i + 1]);
        }
    }
}
