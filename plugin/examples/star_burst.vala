namespace VectorStarBurst {

    public class StarBurst : Object, VectorPlugin.Command {
        public string id {
            owned get {
                return "star-burst";
            }
        }

        public string title {
            owned get {
                return "Star Burst";
            }
        }

        public void run (VectorPlugin.Host host) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (host.document_json);
            var root = parser.get_root ().get_object ();
            var layers = root.get_array_member ("layers");
            if (layers.get_length () == 0) return;
            var layer = layers.get_object_element (layers.get_length () - 1);
            var children = layer.get_array_member ("children");
            var boards = root.get_array_member ("artboards");
            var rect = boards.get_object_element (0).get_array_member ("rect");
            double cx = rect.get_double_element (0) + rect.get_double_element (2) / 2;
            double cy = rect.get_double_element (1) + rect.get_double_element (3) / 2;
            double r = double.min (rect.get_double_element (2), rect.get_double_element (3)) * 0.3;
            for (int i = 0; i < 12; i++) {
                double a = i * Math.PI / 6;
                var node = new Json.Object ();
                node.set_string_member ("t", "path");
                node.set_string_member ("id", "");
                node.set_string_member ("d", "M%g %g L%g %g".printf (cx, cy, cx + Math.cos (a) * r, cy + Math.sin (a) * r));
                var app = new Json.Array ();
                var stroke = new Json.Object ();
                stroke.set_boolean_member ("stroke", true);
                var paint = new Json.Object ();
                paint.set_string_member ("kind", "solid");
                var color = new Json.Object ();
                color.set_string_member ("hex", i % 2 == 0 ? "#e5322d" : "#f39200");
                paint.set_object_member ("color", color);
                stroke.set_object_member ("paint", paint);
                stroke.set_double_member ("width", 4);
                stroke.set_int_member ("cap", 1);
                app.add_object_element (stroke);
                node.set_array_member ("appearance", app);
                children.add_object_element (node);
            }
            var gen = new Json.Generator ();
            gen.set_root (parser.get_root ());
            host.document_json = gen.to_data (null);
            host.message ("Star Burst added");
        }
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (VectorPlugin.Command), typeof (VectorStarBurst.StarBurst));
}
