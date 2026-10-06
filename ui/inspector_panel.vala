using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Vector {

    public class InspectorPanel : Widget {
        public SidebarTabs switcher { get; private set; }
        public Stack stack { get; private set; }
        private Box box;
        private int target;

        public InspectorPanel (int width) {
            target = width;
            add_css_class ("sx-inspector");
            hexpand = false;
            overflow = Overflow.HIDDEN;
            box = new Box (Orientation.VERTICAL, 0);
            box.add_css_class ("sx-inspector-body");
            box.set_parent (this);
            stack = new Stack ();
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.transition_duration = 150;
            switcher = new SidebarTabs ();
            switcher.margin_bottom = 0;
            var header = new Box (Orientation.HORIZONTAL, 6);
            header.add_css_class ("sx-inspector-header");
            apply_bubble_inset (header);
            header.append (switcher);
            box.append (header);
            box.append (stack);
            switcher.selected.connect ((name) => {
                if (stack.visible_child_name != name) stack.visible_child_name = name;
            });
            stack.notify["visible-child-name"].connect (() => {
                if (stack.visible_child_name != null && switcher.active_option != stack.visible_child_name) switcher.set_active (stack.visible_child_name);
            });
        }

        public void add_page (string name, string title, Widget content) {
            var s = new ScrolledWindow ();
            s.hscrollbar_policy = PolicyType.NEVER;
            s.vexpand = true;
            content.margin_start = 14;
            content.margin_end = 14;
            content.margin_top = 4;
            content.margin_bottom = 24;
            s.child = content;
            stack.add_titled (s, name, title);
            switcher.add_option (name, title);
        }

        public string page {
            owned get {
                return stack.visible_child_name;
            }
            set {
                stack.visible_child_name = value;
            }
        }

        public override void dispose () {
            if (box != null) box.unparent ();
            box = null;
            base.dispose ();
        }

        public override SizeRequestMode get_request_mode () {
            return SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (o == Orientation.HORIZONTAL) {
                minimum = natural = target;
                return;
            }
            box.measure (o, target, out minimum, out natural, null, null);
        }

        public override void size_allocate (int width, int height, int baseline) {
            box.allocate (int.max (width, 0), height, baseline, null);
        }
    }
}
