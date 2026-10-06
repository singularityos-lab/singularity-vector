using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class Artboard : Object {
        public string id = "";
        public string name = "";
        public double x = 0;
        public double y = 0;
        public double w = 800;
        public double h = 600;
        public double bleed = 0;
        public string background = "";

        public Artboard (string name, double x, double y, double w, double h) {
            this.name = name;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }

        public Rect rect () {
            return Rect (x, y, w, h);
        }

        public Artboard copy () {
            var a = new Artboard (name, x, y, w, h);
            a.id = id;
            a.bleed = bleed;
            a.background = background;
            return a;
        }
    }

    public class Swatch : Object {
        public string id = "";
        public string name = "";
        public Paint paint;
        public bool is_global = false;
        public string group = "";

        public Swatch (string name, Paint paint) {
            this.name = name;
            this.paint = paint;
        }

        public Swatch copy () {
            var s = new Swatch (name, paint.copy ());
            s.id = id;
            s.is_global = is_global;
            s.group = group;
            return s;
        }
    }

    public class GraphicStyle : Object {
        public string id = "";
        public string name = "";
        public Gee.ArrayList<PaintLayer> appearance = new Gee.ArrayList<PaintLayer> ();
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();
        public double opacity = 1;
        public BlendMode blend = BlendMode.NORMAL;

        public GraphicStyle copy () {
            var s = new GraphicStyle ();
            s.id = id;
            s.name = name;
            foreach (var l in appearance) s.appearance.add (l.copy ());
            foreach (var e in effects) s.effects.add (e.copy ());
            s.opacity = opacity;
            s.blend = blend;
            return s;
        }

        public void capture (Node n) {
            appearance.clear ();
            foreach (var l in n.appearance) appearance.add (l.copy ());
            effects.clear ();
            foreach (var e in n.effects) effects.add (e.copy ());
            opacity = n.opacity;
            blend = n.blend;
        }

        public void apply (Node n) {
            var box = n.geometric_bounds ();
            n.appearance.clear ();
            foreach (var l in appearance) {
                var c = l.copy ();
                if ((c.paint.kind == PaintKind.LINEAR || c.paint.kind == PaintKind.RADIAL) && box.w >= 0) Transforms.fit_gradient (c.paint, box);
                n.appearance.add (c);
            }
            n.effects.clear ();
            foreach (var e in effects) n.effects.add (e.copy ());
            n.opacity = opacity;
            n.blend = blend;
            n.style_id = id;
        }
    }

    public class SymbolDef : Object {
        public string id = "";
        public string name = "";
        public GroupNode art = new GroupNode ();
        public bool is_dynamic = false;

        public SymbolDef copy () {
            var s = new SymbolDef ();
            s.id = id;
            s.name = name;
            s.art = art.clone () as GroupNode;
            s.is_dynamic = is_dynamic;
            return s;
        }
    }

    public class BrushDef : Object {
        public string id = "";
        public string name = "";
        public string kind = "calligraphic";
        public double angle = 30;
        public double roundness = 0.4;
        public double size = 8;
        public double spacing = 1.0;
        public double scatter = 0;
        public double size_jitter = 0;
        public double rotation_jitter = 0;
        public bool rotate_with_path = true;
        public bool stretch = true;
        public string colorize = "none";
        public GroupNode? art = null;

        public BrushDef copy () {
            var b = new BrushDef ();
            b.id = id;
            b.name = name;
            b.kind = kind;
            b.angle = angle;
            b.roundness = roundness;
            b.size = size;
            b.spacing = spacing;
            b.scatter = scatter;
            b.size_jitter = size_jitter;
            b.rotation_jitter = rotation_jitter;
            b.rotate_with_path = rotate_with_path;
            b.stretch = stretch;
            b.colorize = colorize;
            b.art = art != null ? art.clone () as GroupNode : null;
            return b;
        }
    }

    public class PatternDef : Object {
        public string id = "";
        public string name = "";
        public GroupNode tile = new GroupNode ();
        public double w = 40;
        public double h = 40;
        public string tiling = "grid";
        public double hspace = 0;
        public double vspace = 0;
        public double offset = 0.5;

        public PatternDef copy () {
            var p = new PatternDef ();
            p.id = id;
            p.name = name;
            p.tile = tile.clone () as GroupNode;
            p.w = w;
            p.h = h;
            p.tiling = tiling;
            p.hspace = hspace;
            p.vspace = vspace;
            p.offset = offset;
            return p;
        }
    }

    public class Guide : Object {
        public bool vertical;
        public double pos;

        public Guide (bool vertical, double pos) {
            this.vertical = vertical;
            this.pos = pos;
        }
    }

    public class PerspectiveGrid : Object {
        public bool visible = false;
        public int points = 2;
        public double horizon = 300;
        public double vp1x = -200;
        public double vp2x = 1400;
        public double vp3y = -1600;
        public double center_x = 600;
        public double ground = 700;
        public double cell = 40;

        public PerspectiveGrid copy () {
            var p = new PerspectiveGrid ();
            p.visible = visible;
            p.points = points;
            p.horizon = horizon;
            p.vp1x = vp1x;
            p.vp2x = vp2x;
            p.vp3y = vp3y;
            p.center_x = center_x;
            p.ground = ground;
            p.cell = cell;
            return p;
        }
    }

    public class Asset : Object {
        public string id;
        public string mime;
        public Bytes data;
        public Object? cache = null;

        public Asset (string id, string mime, Bytes data) {
            this.id = id;
            this.mime = mime;
            this.data = data;
        }
    }

    public class RecordedAction : Object {
        public string name = "";
        public Gee.ArrayList<string> steps = new Gee.ArrayList<string> ();
    }

    public class VectorDocument : Object {
        public string title = "";
        public string? path = null;
        public bool modified { get; set; default = false; }
        public string units = "px";
        public string color_mode = "rgb";
        public bool proof = false;
        public bool overprint_preview = false;
        public double grid_size = 20;
        public int grid_sub = 4;
        public bool pixel_grid = false;
        public Gee.ArrayList<Artboard> artboards = new Gee.ArrayList<Artboard> ();
        public Gee.ArrayList<GroupNode> layers = new Gee.ArrayList<GroupNode> ();
        public Gee.ArrayList<Swatch> swatches = new Gee.ArrayList<Swatch> ();
        public Gee.ArrayList<GraphicStyle> styles = new Gee.ArrayList<GraphicStyle> ();
        public Gee.ArrayList<SymbolDef> symbols = new Gee.ArrayList<SymbolDef> ();
        public Gee.ArrayList<BrushDef> brushes = new Gee.ArrayList<BrushDef> ();
        public Gee.ArrayList<PatternDef> patterns = new Gee.ArrayList<PatternDef> ();
        public Gee.ArrayList<Guide> guides = new Gee.ArrayList<Guide> ();
        public Gee.ArrayList<RecordedAction> actions = new Gee.ArrayList<RecordedAction> ();
        public PerspectiveGrid perspective = new PerspectiveGrid ();
        public Gee.HashMap<string, Asset> assets = new Gee.HashMap<string, Asset> ();
        public int active_artboard = 0;
        public GroupNode? active_layer = null;
        public int next_id = 1;

        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> undo_labels = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_labels = new Gee.ArrayList<string> ();
        private string? pending = null;
        private string pending_label = "";
        private int depth = 0;
        public int history_limit = 0;

        public signal void changed ();
        public signal void structure_changed ();
        public signal void history_changed ();

        public VectorDocument () {
            changed.connect (() => threads = -1);
            structure_changed.connect (() => threads = -1);
        }

        public static VectorDocument blank (double width = 800, double height = 600) {
            var d = new VectorDocument ();
            d.title = _("Untitled Illustration");
            var a = new Artboard (_("Artboard 1"), 0, 0, width, height);
            d.add_artboard (a);
            var layer = d.new_layer (_("Layer 1"));
            d.layers.add (layer);
            d.active_layer = layer;
            d.default_swatches ();
            d.default_brushes ();
            d.default_styles ();
            d.modified = false;
            return d;
        }

        public void add_artboard (Artboard a) {
            if (a.id == "") a.id = new_id ("ab");
            artboards.add (a);
        }

        public GroupNode new_layer (string name) {
            var l = new GroupNode ();
            l.is_layer = true;
            l.name = name;
            l.id = new_id ();
            string[] colors = { "#4a90d9", "#d94a4a", "#4ad97a", "#d9a64a", "#9a4ad9", "#4ad9d0", "#d94ab8" };
            l.color = colors[layers.size % colors.length];
            return l;
        }

        private int threads = -1;

        public bool has_threads () {
            if (threads >= 0) return threads == 1;
            threads = 0;
            foreach (var n in all_nodes ()) {
                var t = n as TextNode;
                if (t != null && t.thread_next != "") threads = 1;
            }
            return threads == 1;
        }

        public string new_id (string prefix = "n") {
            return "%s%d".printf (prefix, next_id++);
        }

        public void ensure_ids () {
            var seen = new Gee.HashSet<string> ();
            foreach (var l in layers) ensure_node_ids (l, seen);
            foreach (var s in symbols) ensure_node_ids (s.art, seen);
            foreach (var a in artboards) if (a.id == "") a.id = new_id ("ab");
        }

        private void ensure_node_ids (Node n, Gee.HashSet<string> seen) {
            if (n.id == "" || seen.contains (n.id)) n.id = new_id ();
            seen.add (n.id);
            n.set_document (this);
            var g = n as GroupNode;
            if (g != null) foreach (var c in g.children) {
                c.parent = g;
                ensure_node_ids (c, seen);
            }
        }

        public void relink () {
            foreach (var l in layers) {
                l.parent = null;
                relink_node (l);
            }
            foreach (var s in symbols) relink_node (s.art);
            if (active_layer == null || !has_layer (active_layer)) active_layer = layers.size > 0 ? layers[layers.size - 1] : null;
        }

        public bool has_layer (GroupNode g) {
            if (!g.is_layer) return false;
            Node? n = g;
            while (n.parent != null) n = n.parent;
            var top = n as GroupNode;
            return top != null && layers.contains (top);
        }

        private void relink_node (Node n) {
            n.set_document (this);
            var g = n as GroupNode;
            if (g != null) foreach (var c in g.children) {
                c.parent = g;
                relink_node (c);
            }
        }

        public Node? find (string id) {
            Node? found = null;
            foreach (var l in layers) {
                if (l.id == id) return l;
                l.walk ((n) => {
                    if (found != null) return false;
                    if (n.id == id) {
                        found = n;
                        return false;
                    }
                    return true;
                });
                if (found != null) return found;
            }
            return null;
        }

        public SymbolDef? find_symbol (string id) {
            foreach (var s in symbols) if (s.id == id) return s;
            return null;
        }

        public BrushDef? find_brush (string id) {
            foreach (var b in brushes) if (b.id == id) return b;
            return null;
        }

        public PatternDef? find_pattern (string id) {
            foreach (var p in patterns) if (p.id == id) return p;
            return null;
        }

        public Swatch? find_swatch (string id) {
            foreach (var s in swatches) if (s.id == id) return s;
            return null;
        }

        public GraphicStyle? find_style (string id) {
            foreach (var s in styles) if (s.id == id) return s;
            return null;
        }

        public Artboard? current_artboard () {
            if (artboards.size == 0) return null;
            return artboards[active_artboard.clamp (0, artboards.size - 1)];
        }

        public Gee.ArrayList<Node> all_nodes () {
            var list = new Gee.ArrayList<Node> ();
            foreach (var l in layers) l.walk ((n) => {
                list.add (n);
                return true;
            });
            return list;
        }

        public Rect content_bounds () {
            var box = Rect.empty ();
            bool first = true;
            foreach (var l in layers) {
                if (l.hidden) continue;
                var b = l.visual_bounds ();
                if (b.w < 0) continue;
                box = first ? b : box.union (b);
                first = false;
            }
            return first ? Rect (0, 0, -1, -1) : box;
        }

        public void add_asset (Asset a) {
            assets[a.id] = a;
        }

        public string store_asset (Bytes data, string mime) {
            string id = Checksum.compute_for_bytes (ChecksumType.SHA1, data);
            if (!assets.has_key (id)) assets[id] = new Asset (id, mime, data);
            return id;
        }

        public void begin (string label) {
            if (depth++ > 0) return;
            pending = NativeFormat.snapshot (this);
            pending_label = label;
        }

        public void commit () {
            if (depth == 0) return;
            if (--depth > 0) return;
            if (pending == null) return;
            undo_stack.add (pending);
            undo_labels.add (pending_label);
            if (history_limit > 0 && undo_stack.size > history_limit) {
                undo_stack.remove_at (0);
                undo_labels.remove_at (0);
            }
            redo_stack.clear ();
            redo_labels.clear ();
            pending = null;
            modified = true;
            changed ();
            history_changed ();
        }

        public void cancel () {
            if (depth == 0) return;
            depth = 0;
            if (pending != null) restore (pending);
            pending = null;
            changed ();
        }

        public bool in_edit () {
            return depth > 0;
        }

        public bool can_undo () {
            return undo_stack.size > 0;
        }

        public bool can_redo () {
            return redo_stack.size > 0;
        }

        public string undo_label () {
            return undo_labels.size > 0 ? undo_labels[undo_labels.size - 1] : "";
        }

        public string redo_label () {
            return redo_labels.size > 0 ? redo_labels[redo_labels.size - 1] : "";
        }

        public string[] history_labels () {
            return undo_labels.to_array ();
        }

        public int history_size () {
            return undo_stack.size;
        }

        public bool undo () {
            if (undo_stack.size == 0) return false;
            redo_stack.add (NativeFormat.snapshot (this));
            redo_labels.add (undo_labels[undo_labels.size - 1]);
            string state = undo_stack.remove_at (undo_stack.size - 1);
            undo_labels.remove_at (undo_labels.size - 1);
            restore (state);
            modified = true;
            structure_changed ();
            changed ();
            history_changed ();
            return true;
        }

        public bool redo () {
            if (redo_stack.size == 0) return false;
            undo_stack.add (NativeFormat.snapshot (this));
            undo_labels.add (redo_labels[redo_labels.size - 1]);
            string state = redo_stack.remove_at (redo_stack.size - 1);
            redo_labels.remove_at (redo_labels.size - 1);
            restore (state);
            modified = true;
            structure_changed ();
            changed ();
            history_changed ();
            return true;
        }

        public void clear_history () {
            undo_stack.clear ();
            undo_labels.clear ();
            redo_stack.clear ();
            redo_labels.clear ();
            history_changed ();
        }

        private void restore (string state) {
            try {
                string? layer_id = active_layer != null ? active_layer.id : null;
                NativeFormat.restore (this, state);
                relink ();
                if (layer_id != null) {
                    var found = find (layer_id) as GroupNode;
                    if (found != null && found.is_layer) active_layer = found;
                }
            } catch (Error e) {
                warning ("Vector: could not restore history state: %s", e.message);
            }
        }

        public void notify_changed () {
            modified = true;
            changed ();
        }

        public void default_swatches () {
            string[,] list = {
                { _("White"), "#ffffff" }, { _("Black"), "#000000" }, { _("Graphite"), "#4d4d4d" }, { _("Silver"), "#b3b3b3" },
                { _("Red"), "#e5322d" }, { _("Orange"), "#f39200" }, { _("Yellow"), "#ffed00" }, { _("Green"), "#3aaa35" },
                { _("Teal"), "#009fa0" }, { _("Blue"), "#1d71b8" }, { _("Indigo"), "#3c3c8f" }, { _("Purple"), "#951b81" },
                { _("Pink"), "#e6007e" }, { _("Brown"), "#8b5a2b" }
            };
            for (int i = 0; i < list.length[0]; i++) {
                var s = new Swatch (list[i, 0], new Paint.hex (list[i, 1]));
                s.id = new_id ("sw");
                s.group = _("Basic");
                swatches.add (s);
            }
            var grad = new Paint ();
            grad.kind = PaintKind.LINEAR;
            grad.gradient = new Gradient.two (Ink.hex ("#ffffff"), Ink.hex ("#000000"));
            var gs = new Swatch (_("White, Black"), grad);
            gs.id = new_id ("sw");
            gs.group = _("Gradients");
            swatches.add (gs);
            var rad = new Paint ();
            rad.kind = PaintKind.RADIAL;
            rad.gradient = new Gradient.two (Ink.hex ("#ffed00"), Ink.hex ("#e5322d"));
            var rs = new Swatch (_("Sunset Radial"), rad);
            rs.id = new_id ("sw");
            rs.group = _("Gradients");
            swatches.add (rs);
        }

        public void default_brushes () {
            var cal = new BrushDef ();
            cal.id = new_id ("br");
            cal.name = _("Calligraphic 8 pt");
            cal.kind = "calligraphic";
            brushes.add (cal);
            var art = new BrushDef ();
            art.id = new_id ("br");
            art.name = _("Tapered Stroke");
            art.kind = "art";
            var shape = new PathNode ();
            shape.path = new PathData ();
            shape.path.move_to (0, 5);
            shape.path.curve_to (30, 0, 70, 0, 100, 5);
            shape.path.curve_to (70, 10, 30, 10, 0, 5);
            shape.path.close ();
            shape.appearance.add (new PaintLayer.fill (new Paint.hex ("#000000")));
            art.art = new GroupNode ();
            art.art.add (shape);
            art.colorize = "tints";
            brushes.add (art);
            var scatter = new BrushDef ();
            scatter.id = new_id ("br");
            scatter.name = _("Dots Scatter");
            scatter.kind = "scatter";
            scatter.spacing = 1.5;
            scatter.scatter = 0.4;
            scatter.size_jitter = 0.4;
            var dot = new PathNode.with_path (new PathData.ellipse (5, 5, 5, 5));
            dot.appearance.add (new PaintLayer.fill (new Paint.hex ("#000000")));
            scatter.art = new GroupNode ();
            scatter.art.add (dot);
            scatter.colorize = "tints";
            brushes.add (scatter);
            var pattern = new BrushDef ();
            pattern.id = new_id ("br");
            pattern.name = _("Chain Pattern");
            pattern.kind = "pattern";
            var link = new PathNode.with_path (new PathData.round_rect (0, 0, 16, 8, 4));
            link.appearance.add (new PaintLayer.line (new Paint.hex ("#000000"), 1.5));
            pattern.art = new GroupNode ();
            pattern.art.add (link);
            pattern.spacing = 0.1;
            pattern.colorize = "tints";
            brushes.add (pattern);
        }

        public void default_styles () {
            var s = new GraphicStyle ();
            s.id = new_id ("gs");
            s.name = _("Soft Shadow");
            s.appearance.add (new PaintLayer.fill (new Paint.hex ("#1d71b8")));
            s.effects.add (new Effect ("drop-shadow").set_num ("dx", 4).set_num ("dy", 6).set_num ("blur", 6).set_num ("opacity", 0.35));
            styles.add (s);
            var o = new GraphicStyle ();
            o.id = new_id ("gs");
            o.name = _("Double Outline");
            o.appearance.add (new PaintLayer.fill (new Paint.hex ("#ffed00")));
            o.appearance.add (new PaintLayer.line (new Paint.hex ("#000000"), 8));
            o.appearance.add (new PaintLayer.line (new Paint.hex ("#ffffff"), 3));
            styles.add (o);
        }
    }
}
