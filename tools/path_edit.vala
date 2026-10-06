using Singularity.Vector;

namespace Singularity.Apps.Vector {

    public class PathEdit {
        public static void detach_live (PathNode pn) {
            if (pn.live != null) {
                pn.live = null;
            }
            if (pn.corners.size > 0) {
                pn.path = pn.render_path ();
                pn.corners.clear ();
                pn.corner_kinds.clear ();
            }
        }

        private static int alias_of (PathData path, int anchor) {
            int first = anchor;
            while (first > 0 && path.segs[first].kind != SegKind.MOVE) first--;
            int end = first + 1;
            while (end < path.segs.size && path.segs[end].kind != SegKind.MOVE && path.segs[end].kind != SegKind.CLOSE) end++;
            if (end >= path.segs.size || path.segs[end].kind != SegKind.CLOSE) return -1;
            int last = end - 1;
            if (last == first) return -1;
            if (Point (path.segs[first].x, path.segs[first].y).distance (Point (path.segs[last].x, path.segs[last].y)) > 1e-6) return -1;
            if (anchor == first) return last;
            if (anchor == last) return first;
            return -1;
        }

        public static void move_anchors (PathNode pn, Gee.Collection<int> set, double dx, double dy) {
            detach_live (pn);
            var path = pn.path;
            var moved = new Gee.HashSet<int> ();
            foreach (int a in set) {
                moved.add (a);
                int al = alias_of (path, a);
                if (al >= 0) moved.add (al);
            }
            var handled = new Gee.HashSet<string> ();
            foreach (int a in moved) {
                if (a < 0 || a >= path.segs.size) continue;
                var s = path.segs[a];
                if (s.kind == SegKind.CLOSE) continue;
                s.x += dx;
                s.y += dy;
                if (s.kind == SegKind.CURVE && handled.add ("%d.2".printf (a))) {
                    s.x2 += dx;
                    s.y2 += dy;
                }
                if (a + 1 < path.segs.size && path.segs[a + 1].kind == SegKind.CURVE && handled.add ("%d.1".printf (a + 1))) {
                    path.segs[a + 1].x1 += dx;
                    path.segs[a + 1].y1 += dy;
                }
            }
        }

        public static void handle_point (PathData path, int seg, int which, out double x, out double y) {
            var s = path.segs[seg];
            if (which == 1) {
                x = s.x1;
                y = s.y1;
            } else {
                x = s.x2;
                y = s.y2;
            }
        }

        public static void move_handle (PathNode pn, int seg, int which, Point to, bool independent) {
            detach_live (pn);
            var path = pn.path;
            if (seg < 0 || seg >= path.segs.size || path.segs[seg].kind != SegKind.CURVE) return;
            var s = path.segs[seg];
            int anchor = which == 1 ? seg - 1 : seg;
            if (anchor < 0) return;
            var node = Point (path.segs[anchor].x, path.segs[anchor].y);
            if (which == 1) {
                s.x1 = to.x;
                s.y1 = to.y;
            } else {
                s.x2 = to.x;
                s.y2 = to.y;
            }
            var mode = pn.mode_at (anchor);
            if (independent) {
                pn.modes[anchor] = (int) HandleMode.CORNER;
                return;
            }
            if (mode == HandleMode.CORNER) return;
            int inc, outg;
            PathOps.prev_next (path, anchor, out inc, out outg);
            int opposite = which == 1 ? inc : outg;
            if (opposite < 0 || opposite >= path.segs.size || path.segs[opposite].kind != SegKind.CURVE) return;
            var o = path.segs[opposite];
            double dx = to.x - node.x, dy = to.y - node.y;
            double len = Math.hypot (dx, dy);
            if (len < 1e-9) return;
            double ox = which == 1 ? o.x2 : o.x1, oy = which == 1 ? o.y2 : o.y1;
            double olen = Math.hypot (ox - node.x, oy - node.y);
            if (mode == HandleMode.AUTO) {
                double cross = (ox - node.x) * dy - (oy - node.y) * dx;
                double dot = (ox - node.x) * dx + (oy - node.y) * dy;
                if (olen < 1e-9 || dot > 0 || cross.abs () > olen * len * 0.15) return;
            }
            double k = mode == HandleMode.SYMMETRIC ? 1 : olen / len;
            double nx = node.x - dx * k, ny = node.y - dy * k;
            if (which == 1) {
                o.x2 = nx;
                o.y2 = ny;
            } else {
                o.x1 = nx;
                o.y1 = ny;
            }
        }

        public static void convert_anchor (PathNode pn, int anchor) {
            detach_live (pn);
            var path = pn.path;
            int inc, outg;
            PathOps.prev_next (path, anchor, out inc, out outg);
            var node = Point (path.segs[anchor].x, path.segs[anchor].y);
            bool has_handles = false;
            if (inc >= 0 && path.segs[inc].kind == SegKind.CURVE && Point (path.segs[inc].x2, path.segs[inc].y2).distance (node) > 0.01) has_handles = true;
            if (outg >= 0 && path.segs[outg].kind == SegKind.CURVE && Point (path.segs[outg].x1, path.segs[outg].y1).distance (node) > 0.01) has_handles = true;
            if (has_handles) {
                if (inc >= 0 && path.segs[inc].kind == SegKind.CURVE) {
                    path.segs[inc].x2 = node.x;
                    path.segs[inc].y2 = node.y;
                }
                if (outg >= 0 && path.segs[outg].kind == SegKind.CURVE) {
                    path.segs[outg].x1 = node.x;
                    path.segs[outg].y1 = node.y;
                }
                pn.modes[anchor] = (int) HandleMode.CORNER;
                return;
            }
            Point prev = node, next = node;
            if (inc > 0) prev = Point (path.segs[inc - 1].x, path.segs[inc - 1].y);
            if (outg >= 0) next = Point (path.segs[outg].x, path.segs[outg].y);
            double tx = next.x - prev.x, ty = next.y - prev.y;
            double tl = Math.hypot (tx, ty);
            if (tl < 1e-9) return;
            tx /= tl;
            ty /= tl;
            if (inc >= 0 && path.segs[inc].kind != SegKind.CLOSE) {
                to_curve (path, inc);
                double d = node.distance (prev) / 3;
                path.segs[inc].x2 = node.x - tx * d;
                path.segs[inc].y2 = node.y - ty * d;
            }
            if (outg >= 0 && path.segs[outg].kind != SegKind.CLOSE) {
                to_curve (path, outg);
                double d = node.distance (next) / 3;
                path.segs[outg].x1 = node.x + tx * d;
                path.segs[outg].y1 = node.y + ty * d;
            }
            pn.modes[anchor] = (int) HandleMode.SMOOTH;
        }

        public static void to_curve (PathData path, int index) {
            var s = path.segs[index];
            if (s.kind != SegKind.LINE) return;
            var start = Point (path.segs[index - 1].x, path.segs[index - 1].y);
            s.kind = SegKind.CURVE;
            s.x1 = start.x + (s.x - start.x) / 3;
            s.y1 = start.y + (s.y - start.y) / 3;
            s.x2 = start.x + (s.x - start.x) * 2 / 3;
            s.y2 = start.y + (s.y - start.y) * 2 / 3;
        }

        public static bool hit_handle (VectorCanvas c, Point p, out PathNode? node, out int seg, out int which) {
            node = null;
            seg = -1;
            which = 0;
            double tol = c.px (5);
            foreach (var e in c.anchors.entries) {
                var path = e.key.path;
                foreach (int a in e.value) {
                    int inc, outg;
                    PathOps.prev_next (path, a, out inc, out outg);
                    if (inc >= 0 && inc < path.segs.size && path.segs[inc].kind == SegKind.CURVE && Point (path.segs[inc].x2, path.segs[inc].y2).distance (p) < tol) {
                        node = e.key;
                        seg = inc;
                        which = 2;
                        return true;
                    }
                    if (outg >= 0 && outg < path.segs.size && path.segs[outg].kind == SegKind.CURVE && Point (path.segs[outg].x1, path.segs[outg].y1).distance (p) < tol) {
                        node = e.key;
                        seg = outg;
                        which = 1;
                        return true;
                    }
                }
            }
            return false;
        }

        public static bool hit_anchor (VectorCanvas c, Gee.Collection<PathNode> nodes, Point p, out PathNode? node, out int index) {
            node = null;
            index = -1;
            double tol = c.px (5);
            double best = tol;
            foreach (var pn in nodes) {
                foreach (int a in PathOps.anchors (pn.path)) {
                    double d = Point (pn.path.segs[a].x, pn.path.segs[a].y).distance (p);
                    if (d < best) {
                        best = d;
                        node = pn;
                        index = a;
                    }
                }
            }
            return node != null;
        }

        public static Gee.ArrayList<PathNode> editable_paths (VectorCanvas c) {
            var list = new Gee.ArrayList<PathNode> ();
            foreach (var n in c.selection) collect (n, list);
            foreach (var k in c.anchors.keys) if (!list.contains (k)) list.add (k);
            return list;
        }

        public static void collect (Node n, Gee.ArrayList<PathNode> list) {
            var pn = n as PathNode;
            if (pn != null) {
                list.add (pn);
                return;
            }
            var g = n as GroupNode;
            if (g != null && g.generated (null) == null) foreach (var c in g.children) collect (c, list);
            if (g != null && g is BlendNode) foreach (var c in g.children) collect (c, list);
        }
    }
}
