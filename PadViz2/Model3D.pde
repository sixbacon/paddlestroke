// Model3D — 3-D sub-canvas (P3D).
//
// Coordinate system: X right, Y into screen, Z up.
// Processing native is X right, Y down, Z toward viewer.
// The remap matrix applied once per frame converts user coords → Processing coords:
//   (xu, yu, zu) → (xu, -zu, -yu)
//
// Camera default: eye at (0, -1.5 m, +0.5 m) in user coords → Processing (0, -0.5s, 1.5s)

class Model3D {
    PGraphics canvas;
    PShape    paddle;

    // ── Camera orbit (user coords, degrees / metres) ──────────────────────────
    // Default: eye at (0, -1.5m, 0.5m) → dist=sqrt(1.5²+0.5²)×S≈237px, el≈18°
    float camAz   =  0.0f;
    float camEl   = 18.4f;
    float camDist = 237.0f;

    // Mouse drag
    private int   dragStartX, dragStartY;
    private float dragStartAz, dragStartEl;
    private boolean dragging = false;

    static final float S = 150.0f;   // world scale: 1 m = 150 px

    Model3D(PApplet app) {
        canvas = app.createGraphics(VIEW_W, TOTAL_H, P3D);
        paddle = app.loadShape("paddle60.obj");
        if (paddle == null) println("Warning: paddle60.obj not found — using placeholder box");
    }

    // ── Render ────────────────────────────────────────────────────────────────
    void draw(FrameData fd, float corrX, float corrY, float corrZ) {
        canvas.beginDraw();
        canvas.background(20, 24, 32);
        canvas.perspective(PI / 4.0f, (float) VIEW_W / TOTAL_H, 1, 5000);

        // Camera in Processing native coords (see conversion at top)
        setCamera();

        canvas.lights();
        canvas.ambientLight(60, 60, 60);
        canvas.directionalLight(220, 220, 220, 0.4f, 0.6f, -0.7f);

        // Apply coordinate remap: user(x,y,z) → Processing(x,-z,-y)
        canvas.applyMatrix(
            1,  0,  0,  0,
            0,  0, -1,  0,
            0, -1,  0,  0,
            0,  0,  0,  1
        );

        // ── World reference axes ──────────────────────────────────────────────
        // Drawn in user coords (X right, Y into screen, Z up)
        drawAxes(canvas, 60);

        // ── Kayak (fixed, world position) ─────────────────────────────────────
        drawKayak(canvas);

        // ── Paddle ────────────────────────────────────────────────────────────
        canvas.pushMatrix();
        // 1. Apply correction (rest-pose alignment)
        canvas.rotateZ(radians(corrZ));
        canvas.rotateY(radians(corrY));
        canvas.rotateX(radians(corrX));
        // 2. Apply IMU rotation: yaw→pitch→roll (intrinsic, applied right-to-left)
        canvas.rotateZ(radians(fd.yaw));
        canvas.rotateY(radians(fd.pitch));
        canvas.rotateX(radians(fd.roll));
        canvas.scale(S);
        if (paddle != null) {
            canvas.shape(paddle, 0, 0);
        } else {
            canvas.fill(180, 180, 200);  canvas.noStroke();
            canvas.box(1.8f, 0.02f, 0.02f);
        }
        canvas.popMatrix();

        canvas.endDraw();
    }

    // ── Camera ────────────────────────────────────────────────────────────────
    private void setCamera() {
        float azR = radians(camAz);
        float elR = radians(camEl);
        // Eye in user coords
        float ux = camDist * cos(elR) * sin(azR);
        float uy = -camDist * cos(elR) * cos(azR);  // default az=0 → Y into screen
        float uz = camDist * sin(elR);
        // Convert to Processing coords: (ux, -uz, -uy)
        canvas.camera(ux, -uz, -uy,   // eye
                       0,   0,   0,   // centre (origin)
                       0,  -1,   0);  // up: user +Z → Processing -Y
    }

    void resetCamera() { camAz = 0; camEl = 18.4f; camDist = 237; }

    // ── World axes (user coord space) ─────────────────────────────────────────
    private void drawAxes(PGraphics g, float len) {
        g.strokeWeight(2);
        g.stroke(220, 60, 60);   g.line(0, 0, 0, len,   0,   0);   // X red
        g.stroke(60, 220, 60);   g.line(0, 0, 0,   0, len,   0);   // Y green
        g.stroke(80, 120, 255);  g.line(0, 0, 0,   0,   0, len);   // Z blue
        g.strokeWeight(1);
        g.fill(220, 60,  60);  g.textSize(11);  g.text("X", len+4,    0,    0);
        g.fill(60, 220,  60);                   g.text("Y",    0, len+4,    0);
        g.fill(80, 120, 255);                   g.text("Z",    0,    0, len+4);
        g.noFill();
    }

    // ── Kayak (user coords) ───────────────────────────────────────────────────
    // Long axis along Y. Deck (blue top) at z = -0.5 m, hull bottom at z ≈ -0.65 m.
    // Cockpit at z = -0.5 m (deck surface).
    private void drawKayak(PGraphics g) {
        float s  = S;
        float zt = -0.50f;   // deck z
        float zb = -0.65f;   // hull bottom z

        // 8 vertices around hull, half-widths in X (±0.275 m), Y extent ±2.75 m
        float[][] top = {
            { 0.000f,  2.75f, zt}, {-0.200f,  1.50f, zt},
            {-0.275f,  0.00f, zt}, {-0.200f, -1.50f, zt},
            { 0.000f, -2.75f, zt}, { 0.200f, -1.50f, zt},
            { 0.275f,  0.00f, zt}, { 0.200f,  1.50f, zt}
        };
        float[][] bot = {
            { 0.000f,  2.75f, zb}, {-0.200f,  1.50f, zb},
            {-0.275f,  0.00f, zb}, {-0.200f, -1.50f, zb},
            { 0.000f, -2.75f, zb}, { 0.200f, -1.50f, zb},
            { 0.275f,  0.00f, zb}, { 0.200f,  1.50f, zb}
        };
        int n = top.length;
        g.noStroke();

        // Blue deck — fan from top[0]
        g.fill(0, 50, 200);
        g.beginShape(TRIANGLES);
        for (int i = 1; i < n - 1; i++) {
            g.vertex(top[0][0]*s, top[0][1]*s, top[0][2]*s);
            g.vertex(top[i][0]*s, top[i][1]*s, top[i][2]*s);
            g.vertex(top[i+1][0]*s, top[i+1][1]*s, top[i+1][2]*s);
        }
        g.endShape();

        // Grey hull bottom — fan from bot[n-1], reversed winding
        g.fill(160, 160, 160);
        g.beginShape(TRIANGLES);
        for (int i = n - 2; i > 0; i--) {
            g.vertex(bot[n-1][0]*s, bot[n-1][1]*s, bot[n-1][2]*s);
            g.vertex(bot[i][0]*s,   bot[i][1]*s,   bot[i][2]*s);
            g.vertex(bot[i-1][0]*s, bot[i-1][1]*s, bot[i-1][2]*s);
        }
        g.endShape();

        // Sides
        g.fill(120, 125, 135);
        g.beginShape(TRIANGLES);
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            g.vertex(top[i][0]*s, top[i][1]*s, top[i][2]*s);
            g.vertex(bot[i][0]*s, bot[i][1]*s, bot[i][2]*s);
            g.vertex(top[j][0]*s, top[j][1]*s, top[j][2]*s);
            g.vertex(bot[i][0]*s, bot[i][1]*s, bot[i][2]*s);
            g.vertex(bot[j][0]*s, bot[j][1]*s, bot[j][2]*s);
            g.vertex(top[j][0]*s, top[j][1]*s, top[j][2]*s);
        }
        g.endShape();

        // Cockpit (dark rectangle on deck)
        g.fill(30, 32, 40);
        g.beginShape(TRIANGLES);
        g.vertex(-0.225f*s,  0.40f*s, zt*s);
        g.vertex( 0.225f*s,  0.40f*s, zt*s);
        g.vertex( 0.225f*s, -0.40f*s, zt*s);
        g.vertex(-0.225f*s,  0.40f*s, zt*s);
        g.vertex( 0.225f*s, -0.40f*s, zt*s);
        g.vertex(-0.225f*s, -0.40f*s, zt*s);
        g.endShape();
    }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    void mousePressed(int mx, int my) {
        dragStartX = mx;  dragStartY = my;
        dragStartAz = camAz;  dragStartEl = camEl;
        dragging = true;
    }
    void mouseDragged(int mx, int my) {
        if (!dragging) return;
        camAz = dragStartAz + (mx - dragStartX) * 0.5f;
        camEl = constrain(dragStartEl - (my - dragStartY) * 0.5f, -89, 89);
    }
    void mouseReleased() { dragging = false; }
    void mouseWheel(int count) { camDist = constrain(camDist + count * 15, 50, 2000); }
}
