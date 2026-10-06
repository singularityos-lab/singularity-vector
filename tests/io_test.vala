using Singularity.Vector;
using Singularity.Apps.Vector;

namespace VectorIoTests {

    string tmp (string name) {
        return Path.build_filename (Environment.get_tmp_dir (), "vector-io-" + name);
    }

    void check (bool ok, string what) {
        if (!ok) {
            printerr ("FAIL %s\n", what);
            assert_not_reached ();
        }
    }

    VectorDocument rich () {
        var d = VectorDocument.blank (400, 300);
        d.add_artboard (new Artboard ("Second", 460, 0, 200, 200));
        var l = d.active_layer;
        var r = new PathNode ();
        r.name = "Card";
        r.live = new LiveShape ();
        r.live.kind = "rectangle";
        r.live.cx = 120;
        r.live.cy = 100;
        r.live.w = 160;
        r.live.h = 100;
        r.live.radius = 12;
        r.rebuild_live ();
        var fill = new Paint ();
        fill.kind = PaintKind.LINEAR;
        fill.gradient = new Gradient.two (Ink.hex ("#ff0000"), Ink.hex ("#0000ff"));
        Transforms.fit_gradient (fill, r.geometric_bounds ());
        r.appearance.add (new PaintLayer.fill (fill));
        var stroke = new PaintLayer.line (new Paint.hex ("#000000"), 3);
        stroke.dashes = { 6, 3 };
        r.appearance.add (stroke);
        r.effects.add (new Effect ("drop-shadow").set_num ("dx", 4).set_num ("dy", 4).set_num ("blur", 4).set_num ("opacity", 0.5).set_str ("color", "#000000"));
        l.add (r);
        var c = new PathNode.with_path (new PathData.ellipse (300, 150, 50, 50));
        c.name = "Dot";
        c.appearance.add (new PaintLayer.fill (new Paint.hex ("#00aa00")));
        c.opacity = 0.5;
        c.blend = BlendMode.MULTIPLY;
        l.add (c);
        var clip = new GroupNode ();
        clip.clip = true;
        clip.add (new PathNode.with_path (new PathData.rect (40, 180, 60, 60)));
        var big = new PathNode.with_path (new PathData.ellipse (70, 210, 50, 50));
        big.appearance.add (new PaintLayer.fill (new Paint.hex ("#ff8800")));
        clip.add (big);
        l.add (clip);
        var t = new TextNode ();
        t.text = "Hello SVG";
        t.style.size = 20;
        t.matrix = Transforms.translate (200, 260);
        t.appearance.add (new PaintLayer.fill (new Paint.hex ("#222222")));
        l.add (t);
        var sym = new SymbolDef ();
        sym.id = "sym1";
        sym.name = "Badge";
        var sp = new PathNode.with_path (new PathData.rect (0, 0, 20, 20));
        sp.appearance.add (new PaintLayer.fill (new Paint.hex ("#123456")));
        sym.art.add (sp);
        d.symbols.add (sym);
        var inst = new SymbolNode ();
        inst.symbol = "sym1";
        inst.matrix = Transforms.translate (500, 50);
        l.add (inst);
        var spot = new Ink.cmyk (0, 0.8, 1, 0);
        spot.spot = "Brand Orange";
        var sn = new PathNode.with_path (new PathData.rect (500, 120, 60, 40));
        sn.appearance.add (new PaintLayer.fill (new Paint.solid (spot)));
        var over = new Paint.hex ("#00ffff");
        over.overprint = true;
        var on = new PathNode.with_path (new PathData.rect (530, 140, 60, 40));
        on.appearance.add (new PaintLayer.fill (over));
        l.add (sn);
        l.add (on);
        d.ensure_ids ();
        return d;
    }

    void test_native_svg () {
        var d = rich ();
        string path = tmp ("native.svg");
        try {
            Formats.save_native (d, path);
            var back = Formats.open (path);
            check (back.artboards.size == 2, "artboards kept");
            check (back.symbols.size == 1, "symbols kept");
            var card = back.layers[0].children[0] as PathNode;
            check (card != null && card.live != null && card.live.radius == 12, "live shape kept");
            check (card.effects.size == 1 && card.appearance[1].dashes.length == 2, "effects and dashes kept");
            check (back.layers[0].children[1].blend == BlendMode.MULTIPLY, "blend kept");
            string text;
            FileUtils.get_contents (path, out text);
            check (text.contains ("<linearGradient") && text.contains ("mix-blend-mode:multiply") && text.contains ("<clipPath") && text.contains ("<symbol") && text.contains ("<filter"), "plain svg content");
            text = text.replace ("Hello SVG", "Hello Edit");
            FileUtils.set_contents (path, text);
            var edited = Formats.open (path);
            bool found = false;
            foreach (var n in edited.all_nodes ()) {
                var t = n as TextNode;
                if (t != null && t.text.contains ("Hello Edit")) found = true;
            }
            check (found, "external edit imported");
            string z = tmp ("native.svgz");
            Formats.save_native (d, z);
            var zb = Formats.open (z);
            check (zb.symbols.size == 1, "svgz roundtrip");
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }

    void test_foreign_svg () {
        string svg = """<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="200mm" height="100mm" viewBox="0 0 200 100">
<style>.a{fill:#ff0000;stroke:blue;stroke-width:2}</style>
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="rgb(0,0,255)"/></linearGradient>
<clipPath id="c"><circle cx="150" cy="50" r="30"/></clipPath><symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="green"/></symbol></defs>
<g transform="translate(10 10)"><rect class="a" x="0" y="0" width="50" height="30"/><path d="M0 50 C 20 0 40 100 60 50" fill="none" stroke="#000"/></g>
<rect x="100" y="20" width="100" height="60" fill="url(#g)" clip-path="url(#c)"/>
<use xlink:href="#s" x="5" y="70" width="20" height="20"/>
<text x="10" y="95" font-family="Serif" font-size="8">Imported</text>
</svg>""";
        try {
            var d = SvgReader.parse (svg);
            var a = d.artboards[0];
            check ((a.w - 200 * 96 / 25.4).abs () < 0.5, "mm width");
            int paths = 0, clips = 0, syms = 0, texts = 0, grads = 0;
            foreach (var n in d.all_nodes ()) {
                if (n is PathNode) paths++;
                var g = n as GroupNode;
                if (g != null && g.clip) clips++;
                if (n is SymbolNode) syms++;
                if (n is TextNode) texts++;
                var f = n.first_fill ();
                if (f != null && f.paint.kind == PaintKind.LINEAR) grads++;
            }
            check (paths >= 3 && clips == 1 && syms == 1 && texts == 1 && grads == 1, "foreign svg structure %d %d %d %d %d".printf (paths, clips, syms, texts, grads));
            Singularity.Apps.Vector.Node? first = null;
            foreach (var n in d.all_nodes ()) if (first == null && n is PathNode) first = n;
            var f = first.first_fill ();
            check (f != null && f.paint.color.to_hex () == "#ff0000", "css class fill");
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }

    void test_pdf () {
        var d = rich ();
        string path = tmp ("out.pdf");
        try {
            var o = new PdfOptions ();
            Export.save_pdf (d, path, o);
            uint8[] data;
            FileUtils.get_data (path, out data);
            var pdf = Singularity.Pdf.Document.open_bytes (data);
            check (pdf.page_count () == 2, "two pages");
            var res = pdf.page_resources (1, false);
            var spaces = pdf.lookup (res, "ColorSpace");
            bool separation = false;
            if (spaces.is_dict ()) foreach (var k in spaces.dict.keys) {
                var cs = pdf.resolve (spaces.get (k));
                if (cs.is_array () && pdf.resolve (cs.at (0)).is_name ("Separation")) separation = true;
            }
            check (separation, "spot color as separation");
            var states = pdf.lookup (res, "ExtGState");
            check (states.is_dict () && states.get ("GSop") != null, "overprint state");
            string ai = tmp ("out.ai");
            FileUtils.set_data (ai, data);
            var aidoc = Formats.open (ai);
            check (aidoc.artboards.size == 2, "ai via pdf");
            var back = PdfImport.load (path);
            check (back.artboards.size == 2, "pdf import pages");
            int filled = 0;
            foreach (var n in back.all_nodes ()) if (n is PathNode && n.first_fill () != null) filled++;
            check (filled >= 4, "pdf import paths %d".printf (filled));
            string x4 = tmp ("x4.pdf");
            o.standard = "PDF/X-4";
            Export.save_pdf (d, x4, o);
            FileUtils.get_data (x4, out data);
            var xp = Singularity.Pdf.Document.open_bytes (data);
            check (xp.catalog ().get ("OutputIntents") != null, "pdfx output intent");
            check (xp.page (0).get ("TrimBox") != null, "trim box");
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }

    void test_raster () {
        var d = rich ();
        try {
            string png = tmp ("a.png");
            Export.save_raster (d, png, d.artboards[0].rect (), 2, "png", true);
            var p = new Gdk.Pixbuf.from_file (png);
            check (p.width == 800 && p.height == 600, "png 2x");
            string jpg = tmp ("a.jpg");
            Export.save_raster (d, jpg, d.artboards[0].rect (), 1, "jpeg", false);
            check (new Gdk.Pixbuf.from_file (jpg).width == 400, "jpeg");
            string webp = tmp ("a.webp");
            Export.save_raster (d, webp, d.artboards[0].rect (), 1, "webp", true);
            check (new Gdk.Pixbuf.from_file (webp).width == 400, "webp");
            string tif = tmp ("a.tif");
            Export.save_raster (d, tif, d.artboards[0].rect (), 1, "tiff", true);
            check (new Gdk.Pixbuf.from_file (tif).width == 400, "tiff");
            string cmyk = tmp ("cmyk.tif");
            Export.save_raster (d, cmyk, d.artboards[0].rect (), 1, "tiff", false, null, 90, true);
            uint8[] data;
            FileUtils.get_data (cmyk, out data);
            check (data.length > 1000 && data[0] == 'I' && data[1] == 'I', "cmyk tiff written");
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }

    void test_eps () {
        var d = VectorDocument.blank (300, 200);
        foreach (var col in new string[] { "#ff0000", "#00ff00", "#0000ff" }) {
            var pn = new PathNode.with_path (new PathData.ellipse (50 + d.active_layer.children.size * 80, 100, 30, 30));
            pn.appearance.add (new PaintLayer.fill (new Paint.hex (col)));
            d.active_layer.add (pn);
        }
        try {
            string eps = tmp ("a.eps");
            Export.save_eps (d, eps, 0);
            var back = PdfImport.load_postscript (eps);
            int filled = 0;
            foreach (var n in back.all_nodes ()) if (n is PathNode && n.first_fill () != null) filled++;
            check (filled >= 3, "eps paths %d".printf (filled));
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }

    void test_dxf_odg () {
        var d = rich ();
        try {
            string dxf = tmp ("a.dxf");
            Dxf.write (d, dxf, d.artboards[0].rect ());
            var back = Dxf.read (dxf);
            int paths = 0;
            foreach (var n in back.all_nodes ()) if (n is PathNode) paths++;
            check (paths >= 3, "dxf paths %d".printf (paths));
            string odg = tmp ("a.odg");
            DrawExchange.export_odg (d, odg, -1);
            var od = Formats.open (odg);
            check (od.artboards.size == 2, "odg pages");
            int items = 0;
            foreach (var n in od.all_nodes ()) if (!(n is GroupNode)) items++;
            check (items >= 4, "odg items %d".printf (items));
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }
}

namespace VectorIoTests {
    public class FakeHost : Object, VectorPlugin.Host {
        public string json;
        public string document_json {
            owned get {
                return json;
            }
            set {
                json = value;
            }
        }
        public string[] selection_ids {
            owned get {
                return {};
            }
        }
        public void run_action (string name) {
        }
        public void select_ids (string[] ids) {
        }
        public void message (string text) {
        }
    }

    void test_plugins () {
        var plugins = Plugins.get_default ();
        check (plugins.commands.size >= 1, "plugin loaded %d".printf (plugins.commands.size));
        var d = VectorDocument.blank (400, 300);
        var host = new FakeHost ();
        host.json = NativeFormat.to_string (d, false);
        try {
            plugins.commands[0].run (host);
            var parser = new Json.Parser ();
            parser.load_from_data (host.json);
            var back = new VectorDocument ();
            NativeFormat.document_in (back, parser.get_root ().get_object (), false);
            check (back.layers[0].children.size == 12, "plugin added rays");
        } catch (Error e) {
            printerr ("%s\n", e.message);
            assert_not_reached ();
        }
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/vector-io/native-svg", VectorIoTests.test_native_svg);
    Test.add_func ("/vector-io/foreign-svg", VectorIoTests.test_foreign_svg);
    Test.add_func ("/vector-io/pdf", VectorIoTests.test_pdf);
    Test.add_func ("/vector-io/raster", VectorIoTests.test_raster);
    Test.add_func ("/vector-io/dxf-odg", VectorIoTests.test_dxf_odg);
    Test.add_func ("/vector-io/eps", VectorIoTests.test_eps);
    Test.add_func ("/vector-io/plugins", VectorIoTests.test_plugins);
    return Test.run ();
}
