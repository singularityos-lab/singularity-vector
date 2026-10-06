using Singularity.Vector;
using Singularity.Apps.Vector;

namespace VectorTests {

    void near (double a, double b, double tol, string what) {
        if ((a - b).abs () > tol) {
            printerr ("FAIL %s: %g vs %g\n", what, a, b);
            assert_not_reached ();
        }
    }

    double area (PathData p) {
        return PathOps.signed_area (p).abs ();
    }

    void test_booleans () {
        var a = new PathData.rect (0, 0, 100, 100);
        var b = new PathData.rect (50, 50, 100, 100);
        near (area (CurveBoolean.apply (a, b, BoolOp.UNION)), 17500, 1, "union");
        near (area (CurveBoolean.apply (a, b, BoolOp.INTERSECT)), 2500, 1, "intersect");
        near (area (CurveBoolean.apply (a, b, BoolOp.SUBTRACT)), 7500, 1, "subtract");
        near (PathOps.signed_area (CurveBoolean.apply (a, b, BoolOp.EXCLUDE)), 15000, 1, "exclude");
        var c1 = new PathData.ellipse (0, 0, 50, 50);
        var c2 = new PathData.ellipse (50, 0, 50, 50);
        var u = CurveBoolean.apply (c1, c2, BoolOp.UNION);
        int curves = 0;
        foreach (var s in u.segs) if (s.kind == SegKind.CURVE) curves++;
        assert (curves >= 6);
        double r = 50;
        double lens = 2 * r * r * Math.acos (50 / (2 * r)) - 25 * Math.sqrt (4 * r * r - 2500);
        near (area (CurveBoolean.apply (c1, c2, BoolOp.INTERSECT)), lens, 8, "lens");
        near (area (u), 2 * Math.PI * r * r - lens, 12, "circle union");
    }

    void test_arrangement () {
        var paths = new Gee.ArrayList<PathData> ();
        paths.add (new PathData.rect (0, 0, 100, 100));
        paths.add (new PathData.rect (50, 0, 100, 100));
        var faces = new Arrangement (paths).faces ();
        assert (faces.size == 3);
        double total = 0;
        foreach (var f in faces) total += area (f.path);
        near (total, 15000, 2, "divide total");
        var lines = new Gee.ArrayList<PathData> ();
        lines.add (new PathData.rect (0, 0, 100, 100));
        var cut = new PathData ();
        cut.move_to (50, -10);
        cut.line_to (50, 110);
        lines.add (cut);
        var planar = PlanarFaces.compute (lines);
        assert (planar.size == 2);
        foreach (var f in planar) near (f.area, 5000, 2, "planar half");
    }

    void test_offsets () {
        var sq = new PathData.rect (0, 0, 100, 100);
        var grown = CurveOffset.offset (sq, 10, JoinKind.MITER);
        var b = grown.bounds ();
        near (b.w, 120, 0.5, "offset width");
        var shrunk = CurveOffset.offset (sq, -10, JoinKind.MITER);
        near (shrunk.bounds ().w, 80, 0.5, "inset width");
        var line = new PathData ();
        line.move_to (0, 0);
        line.line_to (100, 0);
        var stroke = CurveOffset.stroke (line, 10, JoinKind.MITER, CapKind.BUTT);
        near (area (stroke), 1000, 2, "butt stroke area");
        var sq_cap = CurveOffset.stroke (line, 10, JoinKind.MITER, CapKind.SQUARE);
        near (area (sq_cap), 1100, 2, "square stroke area");
        var round_cap = CurveOffset.stroke (line, 10, JoinKind.MITER, CapKind.ROUND);
        near (area (round_cap), 1000 + Math.PI * 25, 3, "round stroke area");
        var inside = CurveOffset.stroke (sq, 10, JoinKind.MITER, CapKind.BUTT, 4, StrokeAlign.INSIDE);
        near (area (inside), 10000 - 6400, 4, "inside stroke");
        var dashed = CurveOffset.dash (line, { 10, 10 });
        assert (PathOps.contours (dashed).size == 5);
        var profile = new Gee.ArrayList<WidthPoint> ();
        profile.add (new WidthPoint (0, 0.2, 0.2));
        profile.add (new WidthPoint (0.5, 1, 1));
        profile.add (new WidthPoint (1, 0.2, 0.2));
        var vw = CurveOffset.variable (line, 20, profile, CapKind.BUTT);
        assert (vw.bounds ().h > 18 && vw.bounds ().h < 22);
    }

    void test_shapes () {
        var sq = new PathData.rect (0, 0, 100, 100);
        var rounded = LiveCorners.apply (sq, new Gee.HashMap<int, double?> (), null, 20);
        near (area (rounded), 10000 - 4 * (400 - Math.PI * 100), 6, "rounded corners");
        var chamfer = LiveCorners.apply (sq, new Gee.HashMap<int, double?> (), null, 20, CornerKind.CHAMFER);
        near (area (chamfer), 10000 - 4 * 200, 2, "chamfer");
        var noisy = new PathData ();
        noisy.move_to (0, 0);
        for (int i = 1; i <= 100; i++) noisy.line_to (i * 2, Math.sin (i * 0.1) * 30);
        var simple = PathSimplify.simplify (noisy, 1.0);
        assert (PathSimplify.anchor_count (simple) < 20);
        var cut = PathOps.line_hits (sq, Point (50, -10), Point (50, 110));
        assert (cut.size == 2);
        var pieces = PathOps.split (sq, cut, true);
        assert (pieces.size == 2);
        var inserted = PathOps.insert_point (sq, 1, 0.5);
        assert (PathOps.anchors (inserted).size == 5);
    }

    void test_trace () {
        int w = 64, h = 64, stride = w * 4;
        var data = new uint8[stride * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int o = y * stride + x * 4;
                bool inside = Math.hypot (x - 32 + 0.5, y - 32 + 0.5) < 20;
                uint8 v = inside ? 0 : 255;
                data[o] = data[o + 1] = data[o + 2] = v;
                data[o + 3] = 255;
            }
        }
        var opts = new TraceOptions ();
        var layers = BitmapTrace.trace (data, w, h, stride, opts);
        assert (layers.size == 1);
        near (area (layers[0].path), Math.PI * 400, 60, "traced circle");
        int w2 = 120, h2 = 120, stride2 = w2 * 4;
        var ring = new uint8[stride2 * h2];
        for (int y = 0; y < h2; y++) {
            for (int x = 0; x < w2; x++) {
                int o = y * stride2 + x * 4;
                double r = Math.hypot (x - 60, y - 60);
                bool on = (r > 30 && r < 50) || (x - y).abs () < 8;
                ring[o] = ring[o + 1] = ring[o + 2] = on ? 30 : 250;
                ring[o + 3] = 255;
            }
        }
        var traced = BitmapTrace.trace (ring, w2, h2, stride2, new TraceOptions ());
        foreach (var l in traced) {
            var b = l.path.bounds ();
            if (b.x < -2 || b.y < -2 || b.x + b.w > w2 + 2 || b.y + b.h > h2 + 2) {
                printerr ("trace bounds %g %g %g %g\n", b.x, b.y, b.w, b.h);
                assert_not_reached ();
            }
        }
        opts.mode = "color";
        opts.colors = 2;
        var color_layers = BitmapTrace.trace (data, w, h, stride, opts);
        assert (color_layers.size >= 1);
    }

    VectorDocument sample_doc () {
        var d = VectorDocument.blank (400, 300);
        var p = new PathNode ();
        p.live = new LiveShape ();
        p.live.kind = "rectangle";
        p.live.cx = 100;
        p.live.cy = 100;
        p.live.w = 80;
        p.live.h = 60;
        p.live.radius = 8;
        p.rebuild_live ();
        p.appearance.add (new PaintLayer.fill (new Paint.hex ("#ff0000")));
        p.appearance.add (new PaintLayer.line (new Paint.hex ("#0000ff"), 4));
        d.active_layer.add (p);
        var t = new TextNode ();
        t.text = "Vector";
        t.matrix = Transforms.translate (200, 200);
        t.appearance.add (new PaintLayer.fill (new Paint.hex ("#00aa00")));
        d.active_layer.add (t);
        d.ensure_ids ();
        return d;
    }

    void test_native () {
        var d = sample_doc ();
        string s = NativeFormat.to_string (d);
        VectorDocument back;
        try {
            back = NativeFormat.parse (s);
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
        assert (back.layers.size == 1);
        assert (back.layers[0].children.size == 2);
        var p = back.layers[0].children[0] as PathNode;
        assert (p != null && p.live != null && p.live.radius == 8);
        assert (NativeFormat.to_string (back) == s);
        d.begin ("move");
        d.layers[0].children[0].apply_transform (Transforms.translate (10, 0));
        d.commit ();
        near (d.layers[0].children[0].geometric_bounds ().x, 70, 0.01, "moved");
        assert (d.undo ());
        near (d.layers[0].children[0].geometric_bounds ().x, 60, 0.01, "undone");
        assert (d.redo ());
        near (d.layers[0].children[0].geometric_bounds ().x, 70, 0.01, "redone");
    }

    void test_render () {
        var d = sample_doc ();
        var img = Renderer.render_image (d, Rect (0, 0, 400, 300), 1, false);
        unowned uint8[] data = img.get_data ();
        int o = 100 * img.get_stride () + 100 * 4;
        assert (data[o + 2] > 200 && data[o + 1] < 40 && data[o] < 40);
        var t = d.layers[0].children[1] as TextNode;
        var outline = TextLayout.to_path (t);
        assert (!outline.is_empty ());
        var tb = t.geometric_bounds ();
        assert (tb.w > 40 && tb.x >= 199);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/vector/booleans", VectorTests.test_booleans);
    Test.add_func ("/vector/arrangement", VectorTests.test_arrangement);
    Test.add_func ("/vector/offsets", VectorTests.test_offsets);
    Test.add_func ("/vector/shapes", VectorTests.test_shapes);
    Test.add_func ("/vector/trace", VectorTests.test_trace);
    Test.add_func ("/vector/native", VectorTests.test_native);
    Test.add_func ("/vector/render", VectorTests.test_render);
    return Test.run ();
}
