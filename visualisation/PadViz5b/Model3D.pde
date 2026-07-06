// Model3D — 3-D sub-canvas (P3D).
//
// Coordinate system: X right, Y into screen, Z up.
// Achieved by: camera with up=(0,0,-1) + scale(-1,1,1).
// Paddle position: translate(posX*S, 0, posZ*S) in user coords before rotation.

class Model3D {
    PGraphics canvas;
    PShape    paddle;

    float camAz   =  0.0f;
    float camEl   = 20.0f;
    float camDist = 560.0f;

    boolean deckCam = false;

    private int   dragStartX, dragStartY;
    private float dragStartAz, dragStartEl;
    private boolean dragging = false;

    static final float S = 150.0f;

    Model3D(PApplet app) {
        canvas = app.createGraphics(VIEW_W, TOP_H, P3D);
        paddle = app.loadShape("paddle60.obj");
        if (paddle == null) println("Warning: paddle60.obj not found — using placeholder box");
    }

    // ── Render ────────────────────────────────────────────────────────────────
    // bfd = boat frame (nullable). When present, the kayak is drawn with its
    // full quaternion (roll+pitch+yaw); otherwise it falls back to avgYaw only.
    // The deck camera also follows boat yaw when bfd is present.
    void draw(FrameData fd, BoatFrameData bfd,
              float corrX, float corrY, float corrZ, float avgYaw,
              float posX, float posZ, boolean posMode) {
        canvas.beginDraw();
        canvas.background(20, 24, 32);
        canvas.perspective(PI / 4.0f, (float) VIEW_W / TOP_H, 1, 5000);

        float deckYaw = (bfd != null) ? bfd.kayakYaw : avgYaw;
        setCamera(deckYaw);

        canvas.lights();
        canvas.ambientLight(60, 60, 60);
        canvas.directionalLight(220, 220, 220, 0.4f, 0.6f, -0.7f);

        canvas.scale(-1, 1, 1);

        drawAxes(canvas, 60);

        canvas.pushMatrix();
        if (bfd != null) {
            float[] qBoat = { bfd.kayakQw, bfd.kayakQx, bfd.kayakQy, bfd.kayakQz };
            applyQuat(canvas, qBoat);
        } else {
            canvas.rotateZ(radians(avgYaw));
        }
        drawKayak(canvas);
        canvas.popMatrix();

        canvas.pushMatrix();
        if (posMode) canvas.translate(posX * S, 0, 0);   // X only for now
        // qCorr as BODY-FRAME PRE-ROTATION: applied to the OBJ before the IMU
        // rotation takes it to world. This is the right frame for a fixed
        // sensor-mount offset. quatMul(qImu, qCorr) means qCorr acts first on
        // the vertex, then qImu; the effective rotation is qImu ⊗ qCorr.
        float[] qCorr = eulerToQuat(corrX, corrY, corrZ);
        float[] qImu  = { fd.qw, fd.qx, fd.qy, fd.qz };
        float[] q     = quatMul(qImu, qCorr);
        applyQuat(canvas, q);
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
    private void setCamera(float avgYaw) {
        if (deckCam) {
            float a    = radians(avgYaw);
            float dist = 3.25f * S;
            float dz   = -0.4f * S;
            canvas.camera(-dist * sin(a), -dist * cos(a), dz,
                           0, 0, dz,
                           0, 0, -1);
        } else {
            float azR = radians(camAz);
            float elR = radians(camEl);
            float ux =  camDist * cos(elR) * sin(-azR);
            float uy = -camDist * cos(elR) * cos( azR);
            float uz =  camDist * sin(elR);
            canvas.camera(ux, uy, uz, 0, 0, 0, 0, 0, -1);
        }
    }

    void resetCamera() { camAz = 0; camEl = 20.0f; camDist = 560; }

    // ── World axes ────────────────────────────────────────────────────────────
    private void drawAxes(PGraphics g, float len) {
        g.strokeWeight(2);
        g.stroke(220, 60, 60);   g.line(0, 0, 0, len,   0,   0);
        g.stroke(60, 220, 60);   g.line(0, 0, 0,   0, len,   0);
        g.stroke(80, 120, 255);  g.line(0, 0, 0,   0,   0, len);
        g.strokeWeight(1);
        g.fill(220, 60,  60);  g.textSize(11);  g.text("X", len+4,    0,    0);
        g.fill(60, 220,  60);                   g.text("Y",    0, len+4,    0);
        g.fill(80, 120, 255);                   g.text("Z",    0,    0, len+4);
        g.noFill();
    }

    // ── Kayak ─────────────────────────────────────────────────────────────────
    private void drawKayak(PGraphics g) {
        float s  = S;
        float zt = -0.50f;
        float zb = -0.65f;

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

        g.fill(0, 50, 200);
        g.beginShape(TRIANGLES);
        for (int i = 1; i < n - 1; i++) {
            g.vertex(top[0][0]*s, top[0][1]*s, top[0][2]*s);
            g.vertex(top[i][0]*s, top[i][1]*s, top[i][2]*s);
            g.vertex(top[i+1][0]*s, top[i+1][1]*s, top[i+1][2]*s);
        }
        g.endShape();

        g.fill(160, 160, 160);
        g.beginShape(TRIANGLES);
        for (int i = n - 2; i > 0; i--) {
            g.vertex(bot[n-1][0]*s, bot[n-1][1]*s, bot[n-1][2]*s);
            g.vertex(bot[i][0]*s,   bot[i][1]*s,   bot[i][2]*s);
            g.vertex(bot[i-1][0]*s, bot[i-1][1]*s, bot[i-1][2]*s);
        }
        g.endShape();

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

    // ── Quaternion helpers ────────────────────────────────────────────────────

    private float[] eulerToQuat(float rollDeg, float pitchDeg, float yawDeg) {
        float cr = cos(radians(rollDeg)  * 0.5f);
        float sr = sin(radians(rollDeg)  * 0.5f);
        float cp = cos(radians(pitchDeg) * 0.5f);
        float sp = sin(radians(pitchDeg) * 0.5f);
        float cy = cos(radians(yawDeg)   * 0.5f);
        float sy = sin(radians(yawDeg)   * 0.5f);
        return new float[]{
            cr*cp*cy + sr*sp*sy,
            sr*cp*cy - cr*sp*sy,
            cr*sp*cy + sr*cp*sy,
            cr*cp*sy - sr*sp*cy
        };
    }

    private float[] quatMul(float[] q1, float[] q2) {
        float w1=q1[0], x1=q1[1], y1=q1[2], z1=q1[3];
        float w2=q2[0], x2=q2[1], y2=q2[2], z2=q2[3];
        return new float[]{
            w1*w2 - x1*x2 - y1*y2 - z1*z2,
            w1*x2 + x1*w2 + y1*z2 - z1*y2,
            w1*y2 - x1*z2 + y1*w2 + z1*x2,
            w1*z2 + x1*y2 - y1*x2 + z1*w2
        };
    }

    private void applyQuat(PGraphics g, float[] q) {
        float w=q[0], x=q[1], y=q[2], z=q[3];
        float m00 = 1 - 2*(y*y + z*z);
        float m01 =     2*(x*y - w*z);
        float m02 =     2*(x*z + w*y);
        float m10 =     2*(x*y + w*z);
        float m11 = 1 - 2*(x*x + z*z);
        float m12 =     2*(y*z - w*x);
        float m20 =     2*(x*z - w*y);
        float m21 =     2*(y*z + w*x);
        float m22 = 1 - 2*(x*x + y*y);
        g.applyMatrix(m00, m01, m02, 0,
                      m10, m11, m12, 0,
                      m20, m21, m22, 0,
                        0,   0,   0, 1);
    }
}
