// Model3D — paddle OBJ loader, draw, and quaternion applier.
//
// Handedness bridge and calibration triple are applied by the caller
// (see PadViz6.pde). This class knows only about the mesh and about
// applying a single sensor quaternion as a 4x4 matrix.

class Model3D {
    PShape paddle;

    // Native tip-to-tip length of paddle60.obj along its shaft (X) axis, metres
    // (measured from the OBJ: X spans -0.9091..+0.9091). drawPaddle() scales the
    // mesh so its rendered length matches the session's real paddle total length
    // (spec §14.9) rather than baking a fixed size at load.
    static final float NATIVE_TIP_TO_TIP_M = 1.8182f;

    void loadPaddle(String path) {
        paddle = loadShape(path);
        if (paddle == null) {
            println("Model3D: failed to load OBJ '" + path + "'");
            return;
        }
        // Left at native size (OBJ vertices are in metres); drawPaddle() applies
        // the per-session scale so the model can be re-sized to the real paddle
        // length without reloading.
        println("Model3D: loaded paddle OBJ '" + path + "'  (native "
                + nf(NATIVE_TIP_TO_TIP_M, 0, 3) + " m tip-to-tip)");
    }

    // Draw the paddle scaled so its tip-to-tip length is totalLenM metres, at
    // MODEL_SCALE px/m. Uniform scale about the shaft centre (mesh origin).
    void drawPaddle(float totalLenM) {
        if (paddle == null) return;
        float s = MODEL_SCALE * totalLenM / NATIVE_TIP_TO_TIP_M;
        pushMatrix();
        scale(s);
        shape(paddle);
        popMatrix();
    }

    // Procedural kayak in the boat-IMU frame:
    //   +X = starboard, +Y = bow (forward), +Z = up (deck).
    // Octagonal cross-section tapered to points at bow and stern (shape
    // reused from PadViz5b). Deck (blue) sits at +Z, hull (grey) at -Z.
    // Cockpit centred on Y = 0. Bright red bow marker at +Y tip.
    void drawKayak() {
        final float S  = 300;       // px per metre (matches paddle scale)
        final float zt = +0.075f;   // deck top, above origin
        final float zb = -0.075f;   // hull bottom, below origin

        // Octagonal cross-section vertices — bow at +Y, stern at -Y.
        // Widths taper from 0 at both ends to +/-0.275 at midship.
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

        pushStyle();
        noStroke();

        // Deck — blue, on +Z face
        fill(0, 50, 200);
        beginShape(TRIANGLES);
        for (int i = 1; i < n - 1; i++) {
            vertex(top[0]  [0]*S, top[0]  [1]*S, top[0]  [2]*S);
            vertex(top[i]  [0]*S, top[i]  [1]*S, top[i]  [2]*S);
            vertex(top[i+1][0]*S, top[i+1][1]*S, top[i+1][2]*S);
        }
        endShape();

        // Hull bottom — grey, on -Z face
        fill(160);
        beginShape(TRIANGLES);
        for (int i = n - 2; i > 0; i--) {
            vertex(bot[n-1][0]*S, bot[n-1][1]*S, bot[n-1][2]*S);
            vertex(bot[i]  [0]*S, bot[i]  [1]*S, bot[i]  [2]*S);
            vertex(bot[i-1][0]*S, bot[i-1][1]*S, bot[i-1][2]*S);
        }
        endShape();

        // Side walls — darker grey
        fill(120, 125, 135);
        beginShape(TRIANGLES);
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            vertex(top[i][0]*S, top[i][1]*S, top[i][2]*S);
            vertex(bot[i][0]*S, bot[i][1]*S, bot[i][2]*S);
            vertex(top[j][0]*S, top[j][1]*S, top[j][2]*S);
            vertex(bot[i][0]*S, bot[i][1]*S, bot[i][2]*S);
            vertex(bot[j][0]*S, bot[j][1]*S, bot[j][2]*S);
            vertex(top[j][0]*S, top[j][1]*S, top[j][2]*S);
        }
        endShape();

        // Cockpit — dark rectangle centred on Y = 0, on the deck.
        // Sits a hair above the deck plane so depth test wins.
        fill(30, 32, 40);
        float zC = (zt + 0.003f) * S;
        beginShape(TRIANGLES);
        vertex(-0.225f*S,  0.40f*S, zC);
        vertex( 0.225f*S,  0.40f*S, zC);
        vertex( 0.225f*S, -0.40f*S, zC);
        vertex(-0.225f*S,  0.40f*S, zC);
        vertex( 0.225f*S, -0.40f*S, zC);
        vertex(-0.225f*S, -0.40f*S, zC);
        endShape();

        // Bow marker — bright red triangle at the +Y tip, on the deck.
        fill(230, 40, 40);
        float zM = (zt + 0.006f) * S;
        beginShape(TRIANGLES);
        vertex( 0.000f*S, 2.75f*S, zM);   // bow tip
        vertex(-0.100f*S, 2.45f*S, zM);
        vertex( 0.100f*S, 2.45f*S, zM);
        endShape();

        popStyle();
    }

    // Applies a Hamilton quaternion (w, x, y, z) as the current-matrix
    // rotation.  paddleRH  <-  paddleLH  (composed onto whatever the
    // caller has pushed above).
    void applyQuat(float qw, float qx, float qy, float qz) {
        float xx = qx * qx, yy = qy * qy, zz = qz * qz;
        float xy = qx * qy, xz = qx * qz, yz = qy * qz;
        float wx = qw * qx, wy = qw * qy, wz = qw * qz;
        applyMatrix(
            1 - 2 * (yy + zz),     2 * (xy - wz),     2 * (xz + wy), 0,
                2 * (xy + wz), 1 - 2 * (xx + zz),     2 * (yz - wx), 0,
                2 * (xz - wy),     2 * (yz + wx), 1 - 2 * (xx + yy), 0,
                0,                 0,                 0,             1
        );
    }
}
