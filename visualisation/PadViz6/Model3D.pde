// Model3D — paddle OBJ loader, draw, and quaternion applier.
//
// Handedness bridge and calibration triple are applied by the caller
// (see PadViz6.pde). This class knows only about the mesh and about
// applying a single sensor quaternion as a 4x4 matrix.

class Model3D {
    PShape paddle;

    void loadPaddle(String path) {
        paddle = loadShape(path);
        if (paddle == null) {
            println("Model3D: failed to load OBJ '" + path + "'");
            return;
        }
        // Display scale — not a physical correction, just a size for the
        // window. OBJ vertices are in metres; 300 px/m fits the paddle in
        // a 1400x900 window with margin.
        paddle.scale(300);
        println("Model3D: loaded paddle OBJ '" + path + "'");
    }

    void drawPaddle() {
        if (paddle == null) return;
        shape(paddle);
    }

    // Procedural kayak in the boat-IMU frame:
    //   +X = starboard, +Y = bow (forward), +Z = up (deck).
    // Simple hull as a stretched box with a coloured deck patch and a
    // bright bow marker so orientation is unambiguous under any rotation.
    void drawKayak() {
        final float S    = 300;      // px per metre (matches paddle scale)
        final float LEN  = 4.5 * S;  // Y extent (bow-stern)
        final float WID  = 0.55 * S; // X extent (port-starboard)
        final float DEP  = 0.35 * S; // Z extent (deck-hull)

        // Hull — grey box centred at origin.
        pushStyle();
        strokeWeight(1);
        stroke(80);
        fill(140);
        box(WID, LEN, DEP);
        popStyle();

        // Deck patch — thin blue plate sitting on the +Z face.
        pushMatrix();
        translate(0, 0, DEP / 2 + 2);
        pushStyle();
        noStroke();
        fill(60, 100, 200);
        box(WID * 0.85, LEN * 0.95, 4);
        popStyle();
        popMatrix();

        // Bow marker — bright red block at the +Y end, on top of the deck.
        pushMatrix();
        translate(0, LEN / 2 - 0.15 * S, DEP / 2 + 8);
        pushStyle();
        noStroke();
        fill(220, 60, 60);
        box(WID * 0.5, 0.3 * S, 8);
        popStyle();
        popMatrix();

        // Cockpit — small dark rectangle just aft of centre on the deck.
        pushMatrix();
        translate(0, -0.4 * S, DEP / 2 + 4);
        pushStyle();
        noStroke();
        fill(20);
        box(WID * 0.55, 0.5 * S, 4);
        popStyle();
        popMatrix();
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
