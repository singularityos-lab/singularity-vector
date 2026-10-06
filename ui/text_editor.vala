using Gtk;

namespace Singularity.Apps.Vector {

    public class TextEditor : Box {
        private weak VectorWindow win;
        public TextNode node;
        private TextView view;
        private bool fresh;
        private bool done = false;
        public signal void finished ();

        public TextEditor (VectorWindow win, TextNode node, bool fresh) {
            Object (orientation: Orientation.VERTICAL, spacing: 4);
            this.win = win;
            this.node = node;
            this.fresh = fresh;
            add_css_class ("vector-floating-panel");
            halign = Align.START;
            valign = Align.START;
            var head = new Box (Orientation.HORIZONTAL, 6);
            var title = new Label (_("Edit Text"));
            title.add_css_class ("heading");
            title.hexpand = true;
            title.xalign = 0;
            head.append (title);
            var ok = new Button.with_label (_("Done"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => finish ());
            head.append (ok);
            append (head);
            view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.set_size_request (300, 90);
            view.buffer.text = node.text;
            view.top_margin = 6;
            view.bottom_margin = 6;
            view.left_margin = 6;
            view.right_margin = 6;
            var scroll = new ScrolledWindow ();
            scroll.child = view;
            scroll.min_content_height = 90;
            scroll.max_content_height = 260;
            scroll.propagate_natural_height = true;
            append (scroll);
            append (Forms.hint (_("Select characters here to style them in the Character group. Escape or Done finishes.")));
            win.doc.begin (_("Edit Text"));
            view.buffer.changed.connect (() => {
                string old_text = node.text;
                node.text = view.buffer.text;
                shift_runs (old_text, node.text);
                TextLayout.invalidate ();
                win.doc.changed ();
            });
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Escape) {
                    finish ();
                    return true;
                }
                return false;
            });
            view.add_controller (keys);
            place ();
        }

        private void shift_runs (string before, string after) {
            if (node.runs.size == 0) return;
            int prefix = 0;
            int max = int.min (before.length, after.length);
            while (prefix < max && before[prefix] == after[prefix]) prefix++;
            int delta = after.length - before.length;
            foreach (var r in node.runs) {
                if (r.start >= prefix) r.start = int.max (prefix, r.start + delta);
                if (r.end > prefix) r.end = int.max (prefix, r.end + delta);
            }
            for (int i = node.runs.size - 1; i >= 0; i--) if (node.runs[i].end <= node.runs[i].start) node.runs.remove_at (i);
        }

        private void place () {
            var c = win.canvas;
            var b = node.geometric_bounds ();
            var s = c.to_screen (Singularity.Vector.Point (b.x, b.y + b.h));
            margin_start = (int) double.max (64, s.x);
            margin_top = (int) double.max (30, s.y + 10);
            if (margin_top > c.get_height () - 200) margin_top = (int) double.max (30, c.to_screen (Singularity.Vector.Point (b.x, b.y)).y - 200);
        }

        public void focus_editor () {
            view.grab_focus ();
            if (fresh) {
                TextIter start, end;
                view.buffer.get_bounds (out start, out end);
                view.buffer.select_range (start, end);
            }
        }

        public bool has_range () {
            TextIter a, b;
            return view.buffer.get_selection_bounds (out a, out b);
        }

        public delegate void CharEdit (CharStyle s);

        public void apply_run (CharEdit edit) {
            TextIter a, b;
            if (!view.buffer.get_selection_bounds (out a, out b)) return;
            string text = node.text;
            int start = text.index_of_nth_char (a.get_offset ());
            int end = text.index_of_nth_char (b.get_offset ());
            if (end <= start) return;
            var base_style = node.style.copy ();
            foreach (var r in node.runs) if (start >= r.start && start < r.end) base_style = r.style.copy ();
            var kept = new Gee.ArrayList<TextRun> ();
            foreach (var r in node.runs) {
                if (r.end <= start || r.start >= end) {
                    kept.add (r);
                    continue;
                }
                if (r.start < start) kept.add (new TextRun (r.start, start, r.style.copy ()));
                if (r.end > end) kept.add (new TextRun (end, r.end, r.style.copy ()));
            }
            edit (base_style);
            kept.add (new TextRun (start, end, base_style));
            kept.sort ((x, y) => x.start - y.start);
            node.runs.clear ();
            node.runs.add_all (kept);
            TextLayout.invalidate ();
            win.doc.changed ();
        }

        public void finish () {
            if (done) return;
            done = true;
            if (node.text.strip () == "" && node.thread_next == "" && TextLayout.chain_head (node) == node) {
                if (node.parent != null) node.parent.remove (node);
                win.canvas.clear_selection ();
            }
            if (fresh || node.parent == null) win.doc.commit ();
            else win.doc.commit ();
            TextLayout.invalidate ();
            finished ();
        }
    }
}
