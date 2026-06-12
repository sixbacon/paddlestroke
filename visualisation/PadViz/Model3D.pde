// Model3D — 3-D paddle sub-canvas with orbit camera.
// All model-specific alignment values are in ModelMapping.pde.

class Model3D {
    PGraphics canvas;
    PShape    paddle;

    // ── Camera orbit ──────────────────────────────────────────────────────────
    float camAz   = 30.0f;
    float camEl   = 20.0f;
    float camDist = 350.0f;

    // Setup view: camera on +Z axis looking at origin, X right, Y up on screen.
    // Toggle with T key. Useful for verifying model orientation.
    boolean setupView = false;

    // Kayak context view: fixed camera at (0, +1.5m, +1.5m) looking at paddle origin.
    // Toggle with K key.
    boolean kayakView = false;

    // ── Mouse drag ────────────────────────────────────────────────────────────
    private int   dragStartX, dragStartY;
    private float dragStartAz, dragStartEl;
    private boolean dragging = false;

    Model3D(PApplet app) {
        canvas = app.createGraphics(VIEW_W, TOTAL_H, P3D);
        paddle = app.loadShape("paddle60.obj");
        if (paddle == null) println("Warning: paddle60.obj not found in data/");
    }

    // ── Render one frame ──────────────────────────────────────────────────────
    void draw(FrameData fd) {
        canvas.beginDraw();
        canvas.background(20, 24, 32);
        canvas.perspective(PI / 4.0f, (float) VIEW_W / TOTAL_H, 1, 5000);

        // Camera
        if (setupView) {
            // Look straight down the Z axis: X goes right, Y goes up on screen.
            canvas.camera(0, 0, camDist, 0, 0, 0, 0, 1, 0);
        } else if (kayakView) {
            // Fixed context camera: (0, +1.5m, +1.5m) looking at paddle origin, Z up.
            float d = 1.5f * MAP_SCALE;
            canvas.camera(0, d, -d, 0, 0, 0, 0, 0, 1);
        } else {
            float azR  = radians(camAz);
            float elR  = radians(camEl);
            float eyeX = camDist * cos(elR) * sin(azR);
            float eyeY = camDist * cos(elR) * cos(azR);
            float eyeZ = camDist * sin(elR);
            canvas.camera(eyeX, eyeY, eyeZ, 0, 0, 0, 0, 0, 1);
        }

        canvas.lights();
        canvas.ambientLight(60, 60, 60);
        // X component of light direction is negated to compensate for MAP_SIGN_X mirror
        canvas.directionalLight(220, 220, 220,
            -MAP_SIGN_X * 0.5f, -1.0f, -0.5f);

        // ── Paddle ────────────────────────────────────────────────────────────
        // In setup view use identity IMU quat so only the correction is applied,
        // letting the user see the true model rest pose independently of live data.
        canvas.pushMatrix();
        float iw = setupView ? 1.0f : fd.qw;
        float ix = setupView ? 0.0f : fd.qx;
        float iy = setupView ? 0.0f : fd.qy;
        float iz = setupView ? 0.0f : fd.qz;
        float[] q = quatMul(iw, ix, iy, iz,
                            MAP_CORR_W, MAP_CORR_X, MAP_CORR_Y, MAP_CORR_Z);
        applyQuat(canvas, q[0], q[1], q[2], q[3]);
        canvas.scale(MAP_SIGN_X * MAP_SCALE,
                     MAP_SIGN_Y * MAP_SCALE,
                     MAP_SIGN_Z * MAP_SCALE);
        if (paddle != null) {
            canvas.shape(paddle, 0, 0);
        } else {
            canvas.fill(180, 180, 200);  canvas.noStroke();
            canvas.box(0.01f, 1.8f, 0.01f);
        }
        canvas.popMatrix();

        // ── Kayak (fixed world position, no IMU rotation) ────────────────────
        // Local long axis is X; rotateZ(HALF_PI) maps it to +Y in world space.
        // Centre at (0, -0.4m, 0.4m).
        canvas.pushMatrix();
        canvas.translate(0, -0.4f * MAP_SCALE, 0.4f * MAP_SCALE);
        canvas.rotateY(PI);
        canvas.rotateZ(HALF_PI);
        drawKayakShape(canvas);
        canvas.popMatrix();

        // ── World reference axes ──────────────────────────────────────────────
        drawAxes(canvas, 60);

        // (Setup view label is drawn on the main sketch canvas in PadViz.pde)

        // ── HUD ───────────────────────────────────────────────────────────────
        drawHud(fd);

        canvas.endDraw();
    }

    // Apply unit quaternion as rotation matrix (avoids gimbal lock)
    private void applyQuat(PGraphics g, float w, float x, float y, float z) {
        float x2=x*x, y2=y*y, z2=z*z;
        float xy=x*y, xz=x*z, yz=y*z, wx=w*x, wy=w*y, wz=w*z;
        g.applyMatrix(
            1-2*(y2+z2),  2*(xy-wz),    2*(xz+wy),   0,
            2*(xy+wz),    1-2*(x2+z2),  2*(yz-wx),   0,
            2*(xz-wy),    2*(yz+wx),    1-2*(x2+y2), 0,
            0,            0,            0,            1
        );
    }

    // p × q quaternion multiplication → [w,x,y,z]
    float[] quatMul(float pw, float px, float py, float pz,
                    float qw, float qx, float qy, float qz) {
        return new float[]{
            pw*qw - px*qx - py*qy - pz*qz,
            pw*qx + px*qw + py*qz - pz*qy,
            pw*qy - px*qz + py*qw + pz*qx,
            pw*qz + px*qy - py*qx + pz*qw
        };
    }

    private void drawAxes(PGraphics g, float len) {
        g.strokeWeight(2);
        g.stroke(220, 60, 60);   g.line(0, 0, 0, len, 0, 0);   // X red
        g.stroke(60, 220, 60);   g.line(0, 0, 0, 0, len, 0);   // Y green
        g.stroke(80, 120, 255);  g.line(0, 0, 0, 0, 0, len);   // Z blue
        g.strokeWeight(1);
    }

    private void drawHud(FrameData fd) {
        canvas.hint(DISABLE_DEPTH_TEST);
        canvas.noLights();
        canvas.camera();
        canvas.ortho(0, VIEW_W, 0, TOTAL_H, -1, 1);
        canvas.noStroke();

        canvas.fill(255, 255, 255, 200);
        canvas.textSize(13);
        canvas.textAlign(LEFT, TOP);
        int x = 12, y = 30, dy = 17;   // y=30 leaves room for setup label drawn above
        canvas.text("t     " + nf(fd.ts / 1000.0f, 0, 1) + " s", x, y);  y += dy;
        canvas.text("roll  " + nf(fd.roll,  0, 1) + "°", x, y);  y += dy;
        canvas.text("pitch " + nf(fd.pitch, 0, 1) + "°", x, y);  y += dy;
        canvas.text("yaw   " + nf(fd.yaw,   0, 1) + "°", x, y);  y += dy;
        canvas.text("CPM   " + nf(fd.cpm,   0, 1),            x, y);  y += dy;
        canvas.text("sc    " + fd.strokeCount,                 x, y);

        canvas.fill(fd.hasQuat ? color(100, 220, 100) : color(220, 160, 60), 200);
        canvas.text(fd.hasQuat ? "Q" : "E", VIEW_W - 20, 30);

        canvas.hint(ENABLE_DEPTH_TEST);
    }

    // ── Procedural kayak ─────────────────────────────────────────────────────
    // 8-vertex hull: long axis X (-2.75 to +2.75 m), half-width 0.275 m,
    // half-height 0.15 m. Coordinates in metres, scaled by MAP_SCALE.
    private void drawKayakShape(PGraphics g) {
        float s = MAP_SCALE;
        float[][] top = {
            { 2.75f,  0.000f, 0.15f}, { 1.50f, -0.200f, 0.15f},
            { 0.00f, -0.275f, 0.15f}, {-1.50f, -0.200f, 0.15f},
            {-2.75f,  0.000f, 0.15f}, {-1.50f,  0.200f, 0.15f},
            { 0.00f,  0.275f, 0.15f}, { 1.50f,  0.200f, 0.15f}
        };
        float[][] bot = {
            { 2.75f,  0.000f, -0.15f}, { 1.50f, -0.200f, -0.15f},
            { 0.00f, -0.275f, -0.15f}, {-1.50f, -0.200f, -0.15f},
            {-2.75f,  0.000f, -0.15f}, {-1.50f,  0.200f, -0.15f},
            { 0.00f,  0.275f, -0.15f}, { 1.50f,  0.200f, -0.15f}
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

        // Sides — two triangles per quad
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

        // Cockpit — dark rectangle on deck (drawn above blue deck, same z=+0.15)
        // Vertices match kayak.obj: (±0.40, ±0.225, 0.15)
        g.fill(30, 32, 40);
        g.beginShape(TRIANGLES);
        g.vertex( 0.40f*s, -0.225f*s, 0.15f*s);
        g.vertex( 0.40f*s,  0.225f*s, 0.15f*s);
        g.vertex(-0.40f*s,  0.225f*s, 0.15f*s);
        g.vertex( 0.40f*s, -0.225f*s, 0.15f*s);
        g.vertex(-0.40f*s,  0.225f*s, 0.15f*s);
        g.vertex(-0.40f*s, -0.225f*s, 0.15f*s);
        g.endShape();
    }

    void resetCamera() {
        if (setupView) { camDist = 350; return; }
        camAz = 30;  camEl = 20;  camDist = 350;
    }

    void toggleSetupView() {
        setupView = !setupView;
        camDist   = 350;
    }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    void mousePressed(int mx, int my) {
        dragStartX = mx;  dragStartY = my;
        dragStartAz = camAz;  dragStartEl = camEl;
        dragging = true;
    }

    void mouseDragged(int mx, int my) {
        if (!dragging || setupView || kayakView) return;
        camAz = dragStartAz + (mx - dragStartX) * 0.5f;
        camEl = constrain(dragStartEl - (my - dragStartY) * 0.5f, -89, 89);
    }

    void mouseReleased() { dragging = false; }

    void mouseWheel(int count) {
        camDist = constrain(camDist + count * 15, 50, 2000);
    }
}
