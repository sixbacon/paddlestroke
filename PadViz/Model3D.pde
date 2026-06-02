// Model3D — 3-D paddle sub-canvas with orbit camera
// OBJ model: shaft runs along the X axis (±0.909 m).
// Correction quaternion rotates shaft X → world Y before IMU quat is applied.

class Model3D {
    PGraphics canvas;
    PShape    paddle;

    // ── Camera ────────────────────────────────────────────────────────────────
    float camAz   = 30.0f;    // azimuth  (degrees)
    float camEl   = 20.0f;    // elevation (degrees)
    float camDist = 350.0f;
    final float MODEL_SCALE = 150.0f;

    // Correction: 90°Z then 180°Y = combined [0, 0.70711, 0.70711, 0]
    // 90°Z aligns model X-axis (shaft) to world Y; 180°Y flips upside-down
    float corrW = 0.0f, corrX = 0.70711f, corrY = 0.70711f, corrZ = 0.0f;

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

        // Camera position
        float azR  = radians(camAz);
        float elR  = radians(camEl);
        float eyeX = camDist * cos(elR) * sin(azR);
        float eyeY = camDist * cos(elR) * cos(azR);
        float eyeZ = camDist * sin(elR);
        canvas.camera(eyeX, eyeY, eyeZ, 0, 0, 0, 0, 0, 1);
        canvas.perspective(PI / 4.0f, (float) VIEW_W / TOTAL_H, 1, 5000);

        canvas.lights();
        canvas.ambientLight(60, 60, 60);
        canvas.directionalLight(220, 220, 220, -0.5f, -1.0f, -0.5f);

        // ── Paddle (with IMU rotation) ────────────────────────────────────────
        canvas.pushMatrix();
        // Compound rotation: IMU quat × correction (correction applied first)
        float[] q = quatMul(fd.qw, fd.qx, fd.qy, fd.qz,
                            corrW, corrX, corrY, corrZ);
        applyQuat(canvas, q[0], q[1], q[2], q[3]);
        canvas.scale(MODEL_SCALE);
        if (paddle != null) {
            canvas.shape(paddle, 0, 0);
        } else {
            // Fallback stick
            canvas.fill(180, 180, 200);
            canvas.noStroke();
            canvas.box(0.01f, 1.8f, 0.01f);
        }
        canvas.popMatrix();

        // ── World reference axes (fixed) ──────────────────────────────────────
        drawAxes(canvas, 60);

        // ── HUD ───────────────────────────────────────────────────────────────
        drawHud(fd);

        canvas.endDraw();
    }

    // Apply unit quaternion (w,x,y,z) as rotation matrix via applyMatrix
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

    // HUD: text overlay in screen coords (2-D pass over the 3-D canvas)
    private void drawHud(FrameData fd) {
        canvas.hint(DISABLE_DEPTH_TEST);
        canvas.noLights();
        canvas.camera();
        canvas.ortho(0, VIEW_W, 0, TOTAL_H, -1, 1);
        canvas.noStroke();

        canvas.fill(255, 255, 255, 200);
        canvas.textSize(13);
        canvas.textAlign(LEFT, TOP);

        int x = 12, y = 12, dy = 17;
        canvas.text("t     " + nf(fd.ts / 1000.0f, 0, 1) + " s", x, y);  y += dy;
        canvas.text("roll  " + nf(fd.roll,  0, 1) + "°",     x, y);  y += dy;
        canvas.text("pitch " + nf(fd.pitch, 0, 1) + "°",     x, y);  y += dy;
        canvas.text("yaw   " + nf(fd.yaw,   0, 1) + "°",     x, y);  y += dy;
        canvas.text("CPM   " + nf(fd.cpm,   0, 1),                x, y);  y += dy;
        canvas.text("sc    " + fd.strokeCount,                     x, y);

        // Q/E indicator (quaternion source flag)
        canvas.fill(fd.hasQuat ? color(100, 220, 100) : color(220, 160, 60), 200);
        canvas.text(fd.hasQuat ? "Q" : "E", VIEW_W - 20, 12);

        canvas.hint(ENABLE_DEPTH_TEST);
    }

    void resetCamera() { camAz = 30; camEl = 20; camDist = 350; }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    void mousePressed(int mx, int my) {
        dragStartX = mx;   dragStartY = my;
        dragStartAz = camAz;  dragStartEl = camEl;
        dragging = true;
    }

    void mouseDragged(int mx, int my) {
        if (!dragging) return;
        camAz = dragStartAz + (mx - dragStartX) * 0.5f;
        camEl = constrain(dragStartEl - (my - dragStartY) * 0.5f, -89, 89);
    }

    void mouseReleased() { dragging = false; }

    void mouseWheel(int count) {
        camDist = constrain(camDist + count * 15, 50, 2000);
    }
}
