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

    // The OBJ was modelled with the LEFT (yellow) blade feathered at +60°
    // relative to the right (red) blade. drawPaddle() can re-angle the left
    // blade to the session's actual feather by rotating the left half of the
    // mesh about the shaft (X) axis by (sessionFeather − BUILT_FEATHER_DEG).
    // The shaft cross-section is a perfect circle at X=0, so rotating everything
    // with X<0 about the shaft carries the whole left blade (yellow front, grey
    // back, edges) as a unit and only twists the round left half of the shaft —
    // invisible, no seam (spec §15.10).
    static final float BUILT_FEATHER_DEG = 60;
    // Sign of the applied rotation about +X. Verified from the OBJ geometry: the
    // as-built left blade sits at −58.5° (≈ −60°) relative to the right blade in
    // the +X-rotation sense, so SIGN = −1 makes feather 0 give a flat (coplanar)
    // paddle, +60 the as-built right-handed paddle, and −60 the left-handed
    // mirror. (Confirmed by an offline render of feather 60/0/−60, spec §15.10.)
    static final float FEATHER_SIGN = -1;

    // Left-half (X<0) triangles and their ORIGINAL native vertices, captured
    // once at load. setFeather() rebuilds each triangle's vertices from these,
    // so re-angling is always relative to the as-built mesh (no drift from
    // repeated relative rotations).
    ArrayList<PShape> leftTris  = new ArrayList<PShape>();
    ArrayList<float[]> leftOrig = new ArrayList<float[]>();   // [x0,y0,z0, x1..]
    float appliedFeatherDeg = BUILT_FEATHER_DEG;

    void loadPaddle(String path) {
        paddle = loadShape(path);
        if (paddle == null) {
            println("Model3D: failed to load OBJ '" + path + "'");
            return;
        }
        indexLeftBlade();
        // Left at native size (OBJ vertices are in metres); drawPaddle() applies
        // the per-session scale so the model can be re-sized to the real paddle
        // length without reloading.
        println("Model3D: loaded paddle OBJ '" + path + "'  (native "
                + nf(NATIVE_TIP_TO_TIP_M, 0, 3) + " m tip-to-tip, "
                + leftTris.size() + " left-blade tris)");
    }

    // Collect every leaf triangle whose centroid is on the left (X<0) half, with
    // a copy of its original vertices. Processing explodes the OBJ into one
    // GEOMETRY child per face, each with its own (unshared) vertices, so a
    // triangle can be rotated without disturbing its neighbours.
    void indexLeftBlade() {
        leftTris.clear();  leftOrig.clear();
        collectLeftLeaves(paddle);
    }

    void collectLeftLeaves(PShape s) {
        if (s == null) return;
        int nc = s.getChildCount();
        if (nc > 0) {
            for (int i = 0; i < nc; i++) collectLeftLeaves(s.getChild(i));
            return;
        }
        int vc = s.getVertexCount();
        if (vc < 3) return;
        float cx = 0;
        for (int i = 0; i < vc; i++) cx += s.getVertex(i).x;
        cx /= vc;
        if (cx >= 0) return;                       // right blade / right shaft
        float[] orig = new float[vc * 3];
        for (int i = 0; i < vc; i++) {
            PVector p = s.getVertex(i);
            orig[i * 3] = p.x;  orig[i * 3 + 1] = p.y;  orig[i * 3 + 2] = p.z;
        }
        leftTris.add(s);  leftOrig.add(orig);
    }

    // Re-angle the left (yellow) blade to featherDeg (signed: + right-handed,
    // − left-handed, 0 straight). Rotates the stored ORIGINAL left-half vertices
    // about the shaft X-axis by (featherDeg − BUILT_FEATHER_DEG). No-op if the
    // angle is unchanged, so it's cheap to call every frame.
    void setFeather(float featherDeg) {
        if (leftTris.isEmpty()) return;
        if (abs(featherDeg - appliedFeatherDeg) < 0.01) return;
        float a = radians((featherDeg - BUILT_FEATHER_DEG) * FEATHER_SIGN);
        float c = cos(a), sn = sin(a);
        for (int t = 0; t < leftTris.size(); t++) {
            PShape s = leftTris.get(t);
            float[] o = leftOrig.get(t);
            int vc = s.getVertexCount();
            for (int i = 0; i < vc; i++) {
                float x = o[i * 3], y = o[i * 3 + 1], z = o[i * 3 + 2];
                s.setVertex(i, x, y * c - z * sn, y * sn + z * c);
            }
        }
        appliedFeatherDeg = featherDeg;
    }

    // Draw the paddle scaled so its tip-to-tip length is totalLenM metres, at
    // MODEL_SCALE px/m, with the left blade re-angled to featherDeg. Uniform
    // scale about the shaft centre (mesh origin).
    void drawPaddle(float totalLenM, float featherDeg) {
        if (paddle == null) return;
        setFeather(featherDeg);
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
