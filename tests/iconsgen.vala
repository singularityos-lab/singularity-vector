using Singularity.Vector;
using Singularity.Apps.Vector;

PathData acc;

void s (string d, double w = 1.5, CapKind cap = CapKind.ROUND, JoinKind join = JoinKind.ROUND) {
    acc.append (CurveOffset.stroke (PathData.parse_svg (d), w, join, cap));
}

void f (string d) {
    acc.append (PathData.parse_svg (d));
}

void circle (double x, double y, double r) {
    acc.append (new PathData.ellipse (x, y, r, r));
}

void ring (double x, double y, double r, double w = 1.5) {
    acc.append (CurveOffset.stroke (new PathData.ellipse (x, y, r, r), w, JoinKind.ROUND, CapKind.BUTT));
}

void square (double x, double y, double size) {
    acc.append (new PathData.rect (x - size / 2, y - size / 2, size, size));
}

void emit (string dir, string name) {
    var clean = CurveBoolean.unite_all (single (acc));
    string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><path fill=\"#2e3436\" d=\"%s\"/></svg>\n".printf (clean.to_svg (3));
    try {
        FileUtils.set_contents (Path.build_filename (dir, "vector-" + name + "-symbolic.svg"), svg);
    } catch (Error e) {
        printerr ("%s\n", e.message);
    }
    acc = new PathData ();
}

Gee.ArrayList<PathData> single (PathData p) {
    var l = new Gee.ArrayList<PathData> ();
    l.add (p);
    return l;
}

int main (string[] args) {
    string dir = args[1];
    acc = new PathData ();
    f ("M3 1.5 L3 13.5 L6.2 10.6 L8.4 15 L10.3 14.1 L8.2 9.8 L12.5 9.6 Z");
    emit (dir, "select");
    f ("M3 1.5 L3 13.5 L6.2 10.6 L8.4 15 L10.3 14.1 L8.2 9.8 L12.5 9.6 Z");
    acc = CurveOffset.stroke (acc, 1.4, JoinKind.MITER, CapKind.BUTT);
    emit (dir, "direct");
    s ("M5 3 C1 4 1 10 5 11 C9 12 13 9 12 5 C11 1.5 7 2 5 3 Z", 1.4);
    s ("M5 11 L4 14.5", 1.4);
    emit (dir, "lasso");
    f ("M8 1 L12 8 L9.5 14 L6.5 14 L4 8 Z");
    acc = CurveBoolean.apply (acc, new PathData.ellipse (8, 8.5, 1.4, 1.4), BoolOp.SUBTRACT);
    s ("M8 1 L8 7.1", 1.0);
    emit (dir, "pen");
    s ("M2 13 C5 4 11 4 14 13", 1.5);
    square (2, 13, 3);
    square (14, 13, 3);
    circle (8, 6.2, 1.8);
    emit (dir, "curvature");
    s ("M2.5 13.5 L11.5 4.5", 3.2, CapKind.BUTT);
    f ("M11.5 2 L14 4.5 L12.5 6 L10 3.5 Z");
    f ("M1.5 14.5 L2 12 L4 14 Z");
    emit (dir, "pencil");
    s ("M14 2 L7 9", 1.6);
    f ("M7.5 8.5 C9 10 8 13 5 14 C3.5 14.5 2 14.5 1.5 14.5 C2.5 13.5 2.5 12 3.5 10.5 C4.5 9 6 7.5 7.5 8.5 Z");
    emit (dir, "brush");
    f ("M7.5 8.5 C9 10 8 13 5 14 C3.5 14.5 2 14.5 1.5 14.5 C2.5 13.5 2.5 12 3.5 10.5 C4.5 9 6 7.5 7.5 8.5 Z");
    s ("M14 2 L7 9", 1.6);
    circle (13, 13, 2);
    emit (dir, "blob");
    acc = CurveOffset.stroke (new PathData.rect (2.5, 3.5, 11, 9), 1.5, JoinKind.MITER, CapKind.BUTT);
    emit (dir, "rectangle");
    acc = CurveOffset.stroke (new PathData.round_rect (2.5, 3.5, 11, 9, 3), 1.5, JoinKind.MITER, CapKind.BUTT);
    emit (dir, "rounded");
    ring (8, 8, 5.5);
    emit (dir, "ellipse");
    s ("M8 2 L13.7 6.1 L11.5 12.9 L4.5 12.9 L2.3 6.1 Z", 1.5, CapKind.BUTT, JoinKind.MITER);
    emit (dir, "polygon");
    var star = new LiveShape ();
    star.kind = "star";
    star.cx = 8;
    star.cy = 8.6;
    star.w = 14;
    star.h = 14;
    star.sides = 5;
    star.inner = 0.45;
    acc = CurveOffset.stroke (star.build (), 1.3, JoinKind.MITER, CapKind.BUTT);
    emit (dir, "star");
    s ("M2.5 13.5 L13.5 2.5", 1.5);
    emit (dir, "line");
    f ("M2 2 L14 2 L14 5 L12.8 5 L12.3 3.6 L9.2 3.6 L9.2 12.4 L11 13 L11 14 L5 14 L5 13 L6.8 12.4 L6.8 3.6 L3.7 3.6 L3.2 5 L2 5 Z");
    emit (dir, "text");
    s ("M1.5 11 C4 4 12 4 14.5 11", 1.2);
    f ("M5 6 L11 6 L11 7.3 L8.8 7.3 L8.8 12 L7.2 12 L7.2 7.3 L5 7.3 Z");
    emit (dir, "text-path");
    acc = CurveOffset.stroke (new PathData.rect (2.5, 2.5, 11, 11), 1.0, JoinKind.MITER, CapKind.BUTT);
    f ("M4.5 5 L11.5 5 L11.5 6.3 L4.5 6.3 Z M4.5 7.5 L11.5 7.5 L11.5 8.8 L4.5 8.8 Z M4.5 10 L9 10 L9 11.3 L4.5 11.3 Z");
    emit (dir, "text-area");
    ring (4, 12, 2.2, 1.4);
    ring (4, 4, 2.2, 1.4);
    s ("M5.8 10.6 L14 3", 1.3);
    s ("M5.8 5.4 L14 13", 1.3);
    emit (dir, "scissors");
    f ("M2 14 L9 3 C10 1.5 12 1.5 13.5 2.8 L5 14 Z");
    s ("M9.5 9 L14.5 14", 1.2);
    emit (dir, "knife");
    f ("M6 14 L2 10 L9 3 L14 8 L8 14 Z");
    acc = CurveBoolean.apply (acc, PathData.parse_svg ("M2 10 L5.5 6.5 L10.5 11.5 L8 14 L6 14 Z"), BoolOp.SUBTRACT);
    acc.append (CurveOffset.stroke (PathData.parse_svg ("M2 10 L5.5 6.5 L10.5 11.5 L8 14 L6 14 Z"), 1.0, JoinKind.MITER, CapKind.BUTT));
    s ("M8 14.5 L14.5 14.5", 1.0);
    emit (dir, "eraser");
    acc = CurveOffset.stroke (new PathData.ellipse (6, 7, 4, 4), 1.2, JoinKind.ROUND, CapKind.BUTT);
    acc.append (CurveOffset.stroke (new PathData.ellipse (10, 9, 4, 4), 1.2, JoinKind.ROUND, CapKind.BUTT));
    acc.append (CurveBoolean.apply (new PathData.ellipse (6, 7, 4, 4), new PathData.ellipse (10, 9, 4, 4), BoolOp.INTERSECT));
    s ("M11 11 L14.5 14.5", 1.5);
    emit (dir, "shape-builder");
    f ("M3 7 L8 2 L13 7 L8 12 Z");
    acc = CurveOffset.stroke (acc, 1.3, JoinKind.MITER, CapKind.BUTT);
    f ("M3 7 L13 7 L8 12 Z");
    f ("M13.5 9 C14.5 11 15 12 15 13 C15 14 14.3 14.6 13.5 14.6 C12.7 14.6 12 14 12 13 C12 12 12.5 11 13.5 9 Z");
    emit (dir, "live-paint");
    acc = CurveOffset.stroke (new PathData.rect (2.5, 2.5, 11, 11), 1.0, JoinKind.MITER, CapKind.BUTT);
    s ("M4.5 11.5 L11.5 4.5", 1.4);
    circle (4.5, 11.5, 1.8);
    square (11.5, 4.5, 3);
    emit (dir, "gradient");
    acc = CurveOffset.stroke (new PathData.rect (2.5, 2.5, 11, 11), 1.0, JoinKind.MITER, CapKind.BUTT);
    s ("M2.5 8 C6 6 10 10 13.5 8", 1.0);
    s ("M8 2.5 C6 6 10 10 8 13.5", 1.0);
    circle (8, 8, 1.6);
    emit (dir, "mesh");
    s ("M1.5 8 C4 3 6 3 8 8 C10 13 12 13 14.5 8", 1.2);
    f ("M5.3 3.2 L6.6 3.2 L6.6 8 L5.3 8 Z");
    f ("M5.3 3.2 L6.6 3.2 L6.6 1.6 L5.3 1.6 Z");
    s ("M5.95 1.5 L5.95 6.5", 0.9);
    emit (dir, "width");
    f ("M11.5 1.5 L14.5 4.5 L12.8 6.2 L9.8 3.2 Z");
    s ("M10.5 5.5 L3 13", 2.0);
    f ("M1.5 14.5 L2 12.5 L3.5 14 Z");
    emit (dir, "eyedropper");
    circle (3.5, 12.5, 2.3);
    square (12.5, 3.5, 4.4);
    circle (6.5, 9.5, 1.7);
    circle (9.5, 6.5, 1.7);
    emit (dir, "blend");
    s ("M13 8 A5 5 0 1 1 8 3", 1.5);
    f ("M6 0.8 L10 3 L6 5.2 Z");
    emit (dir, "rotate");
    acc = CurveOffset.stroke (new PathData.rect (2.5, 6.5, 7, 7), 1.0, JoinKind.MITER, CapKind.BUTT);
    s ("M7 9 L13 3", 1.4);
    f ("M9 2.5 L13.5 2.5 L13.5 7 Z");
    emit (dir, "scale");
    s ("M8 1 L8 15", 1.0, CapKind.BUTT);
    f ("M6.5 3 L6.5 13 L1.5 13 Z");
    acc.append (CurveOffset.stroke (PathData.parse_svg ("M9.5 3 L9.5 13 L14.5 13 Z"), 1.0, JoinKind.MITER, CapKind.BUTT));
    emit (dir, "reflect");
    acc = CurveOffset.stroke (new PathData.rect (3.5, 3.5, 9, 9), 1.5, JoinKind.MITER, CapKind.BUTT);
    s ("M3.5 0.5 L3.5 3.5", 1.0, CapKind.BUTT);
    s ("M0.5 3.5 L3.5 3.5", 1.0, CapKind.BUTT);
    s ("M12.5 12.5 L12.5 15.5", 1.0, CapKind.BUTT);
    s ("M12.5 12.5 L15.5 12.5", 1.0, CapKind.BUTT);
    emit (dir, "artboard");
    f ("M5 7 L5 2.5 C5 1.5 6.5 1.5 6.5 2.5 L6.5 6.5 L6.5 2 C6.5 1 8 1 8 2 L8 6.5 L8 2.5 C8 1.5 9.5 1.5 9.5 2.5 L9.5 7 L9.5 4.5 C9.5 3.5 11 3.5 11 4.5 L11 10 C11 13 9.5 14.5 7.5 14.5 C5.5 14.5 4.5 13.5 3.5 12 L2 9.5 C1.5 8.5 2.8 7.8 3.5 8.6 L5 10.5 Z");
    emit (dir, "hand");
    ring (6.5, 6.5, 4.5);
    s ("M10 10 L14.5 14.5", 2.0);
    emit (dir, "zoom");
    s ("M1 13 L8 3 L15 13 Z", 1.0, CapKind.BUTT, JoinKind.MITER);
    s ("M8 3 L8 13", 1.0);
    s ("M4.5 8 L11.5 8", 1.0);
    emit (dir, "perspective");
    circle (4, 4, 2);
    circle (11, 5, 1.6);
    circle (6, 11, 1.4);
    circle (12, 12, 2.2);
    f ("M7 7 L9 6.2 L8.5 8.5 Z");
    emit (dir, "symbol-sprayer");
    acc = CurveOffset.stroke (new PathData.ellipse (8, 8, 3, 3), 1.0, JoinKind.ROUND, CapKind.BUTT);
    for (int i = 0; i < 8; i++) {
        double a = i * Math.PI / 4;
        circle (8 + Math.cos (a) * 6, 8 + Math.sin (a) * 6, 1.3);
    }
    emit (dir, "repeat");
    acc = CurveOffset.stroke (PathData.parse_svg ("M2 4 C6 1 10 7 14 4 L14 12 C10 15 6 9 2 12 Z"), 1.2, JoinKind.MITER, CapKind.BUTT);
    s ("M5.5 3.3 L5.5 11.5", 0.9);
    s ("M10.5 4.7 L10.5 12.7", 0.9);
    emit (dir, "envelope");
    f ("M3 5 L8 2 L13 5 L8 8 Z");
    acc.append (CurveOffset.stroke (PathData.parse_svg ("M3 5 L3 11 L8 14 L13 11 L13 5"), 1.2, JoinKind.MITER, CapKind.BUTT));
    s ("M8 8 L8 14", 1.2);
    emit (dir, "3d");
    f ("M2 14 L2 9 L5 9 L5 14 Z M6.5 14 L6.5 4 L9.5 4 L9.5 14 Z M11 14 L11 7 L14 7 L14 14 Z");
    emit (dir, "graph");
    return 0;
}
