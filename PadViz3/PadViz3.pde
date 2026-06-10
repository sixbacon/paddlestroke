// PadViz3 — axes only, used to nail the coordinate system before adding geometry

void setup() {
    size(900, 800, P3D);
    surface.setTitle("PadViz3 — axes");
}

void draw() {
    background(30);

    // Camera: position (0, -400, 400), looking at origin, Z up
    camera(0, -400, 400,   // eye: first view
           0,    0,   0,   // centre
           0,    0,  -1);  // up

    // Mirror about YZ plane: x → -x
    scale(-1, 1, 1);

    lights();

    // Axes from origin, length 150
    strokeWeight(3);

    stroke(220, 60, 60);    // X — red
    line(0, 0, 0,  150,   0,   0);

    stroke(60, 220, 60);    // Y — green
    line(0, 0, 0,    0, 150,   0);

    stroke(80, 120, 255);   // Z — blue
    line(0, 0, 0,    0,   0, 150);

    // Labels
    fill(220, 60, 60);   textSize(16);  text("X", 160,   0,   0);
    fill(60, 220, 60);                  text("Y",   0, 160,   0);
    fill(80, 120, 255);                 text("Z",   0,   0, 160);
}
