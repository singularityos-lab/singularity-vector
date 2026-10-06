namespace Singularity.Apps.Vector {

    [CCode (cname = "vector_cms_open", cheader_filename = "vector_cms.h")]
    extern void* cms_open (string? cmyk_path);
    [CCode (cname = "vector_cms_close", cheader_filename = "vector_cms.h")]
    extern void cms_close (void* handle);
    [CCode (cname = "vector_cms_rgb_to_cmyk", cheader_filename = "vector_cms.h")]
    extern void cms_rgb_to_cmyk (void* handle, double r, double g, double b, out double c, out double m, out double y, out double k);
    [CCode (cname = "vector_cms_cmyk_to_rgb", cheader_filename = "vector_cms.h")]
    extern void cms_cmyk_to_rgb (void* handle, double c, double m, double y, double k, out double r, out double g, out double b);
    [CCode (cname = "vector_cms_proof", cheader_filename = "vector_cms.h")]
    extern void cms_proof (void* handle, uint8* data, int width, int height, int stride);
    [CCode (cname = "vector_cms_has_profile", cheader_filename = "vector_cms.h")]
    extern bool cms_has_profile (void* handle);
    [CCode (cname = "vector_cms_profile_data", cheader_filename = "vector_cms.h")]
    extern uint8* cms_profile_data (void* handle, out int length);

    public class ColorManager : Object {
        private static ColorManager? instance = null;
        private void* handle;
        public string? profile_path { get; private set; }

        public static ColorManager get_default () {
            if (instance == null) instance = new ColorManager ();
            return instance;
        }

        private ColorManager () {
            profile_path = find_profile ();
            handle = cms_open (profile_path);
        }

        ~ColorManager () {
            if (handle != null) cms_close (handle);
        }

        public bool has_profile () {
            return handle != null && cms_has_profile (handle);
        }

        public string profile_name () {
            return profile_path != null ? Path.get_basename (profile_path) : _("Built-in conversion");
        }

        public uint8[]? profile_bytes () {
            if (!has_profile ()) return null;
            int len;
            uint8* data = cms_profile_data (handle, out len);
            if (data == null || len <= 0) return null;
            var copy = new uint8[len];
            Memory.copy (copy, data, len);
            return copy;
        }

        public static string? find_profile () {
            string? env = Environment.get_variable ("SINGULARITY_VECTOR_CMYK_PROFILE");
            if (env != null && FileUtils.test (env, FileTest.EXISTS)) return env;
            string[] dirs = {};
            dirs += Path.build_filename (Environment.get_user_data_dir (), "color", "icc");
            foreach (var d in Environment.get_system_data_dirs ()) dirs += Path.build_filename (d, "color", "icc");
            string? fallback = null;
            foreach (var d in dirs) {
                var found = search (d, 0, ref fallback);
                if (found != null) return found;
            }
            return fallback;
        }

        private static string? search (string dir, int depth, ref string? fallback) {
            if (depth > 3) return null;
            try {
                var e = Dir.open (dir);
                string? name;
                while ((name = e.read_name ()) != null) {
                    string path = Path.build_filename (dir, name);
                    if (FileUtils.test (path, FileTest.IS_DIR)) {
                        var r = search (path, depth + 1, ref fallback);
                        if (r != null) return r;
                        continue;
                    }
                    string l = name.down ();
                    if (!l.has_suffix (".icc") && !l.has_suffix (".icm")) continue;
                    if (!l.contains ("cmyk") && !l.contains ("fogra") && !l.contains ("swop") && !l.contains ("coated") && !l.contains ("gracol")) continue;
                    if (l.contains ("fogra39") || l.contains ("coated")) return path;
                    if (fallback == null) fallback = path;
                }
            } catch (Error err) {
            }
            return null;
        }

        public void rgb_to_cmyk (double r, double g, double b, out double c, out double m, out double y, out double k) {
            cms_rgb_to_cmyk (handle, r, g, b, out c, out m, out y, out k);
        }

        public void cmyk_to_rgb (double c, double m, double y, double k, out double r, out double g, out double b) {
            cms_cmyk_to_rgb (handle, c, m, y, k, out r, out g, out b);
        }

        public void proof (Cairo.ImageSurface surface) {
            surface.flush ();
            cms_proof (handle, surface.get_data (), surface.get_width (), surface.get_height (), surface.get_stride ());
            surface.mark_dirty ();
        }
    }
}
