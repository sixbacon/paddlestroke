// PadViz7 — Slice 0 (model cal) + Slice A (paddle, data-driven) + Slice B (kayak, data-driven).
// Forked from PadViz6 v0.15 (21 Jul 2026). Adds the session-setup Wizard + the
// sidecar Classification section (spec §14). See Wizard.pde / Classification.pde.
// See visualisation/specs/padviz6_spec.md.
//
// Fixed render pipeline (both slices A and B share the same shape):
//   1. Handedness bridge         scale(1, 1, -1)   — sensor LH → world RH.
//   2. Model calibration triple  ZYX Euler         — Blender/model → sensor frame.
//   3. Data quaternion           per-frame         — object's world orientation.
// Optionally in Slices A/B: view-alignment reference subtraction (K key)
// so that a chosen rest frame renders at identity — useful for validation
// against the Slice 0 target pose.

Calibration cal;
Model3D     model3D;
DataSource  paddleData;   // null until user loads a paddle CSV
BoatSource  boatData;     // null until user loads a boat CSV
SyncMap     sync;         // paddle-frame -> boat-frame lookup; rebuilt on load
GraphPanel  graph;        // bottom strip; visible when a paddle CSV is loaded
Wizard      wizard;       // guided session-setup flow (v0.16, spec §14)
Sidecar     sidecar;      // per-session calibration; null until built or loaded
Classification classify;  // data-quality sections + exclusion index (v0.16, spec §14)
Menu        menu;         // Commands pull-down (v0.14, spec §13.2)
CatchEvents catchEvents;  // blade entry/exit detector (v0.14, spec §13.3)
EntryExitPanel eePanel;   // left 20% boat-frame scatter (v0.14, spec §13.4)
DetailPanel detailPanel;  // collapsible HUD text box (v0.15, spec §13.8)
StrokeAveragePanel avgPanel; // right 20% averaged L/R roll traces (v0.15, spec §13.8)

// True when visualisation/recordings/ holds at least one *.session.json at
// startup — enables the wizard's "J = load a saved session" one-step shortcut
// (v0.17). Computed once in setup(); the folder doesn't change during a run.
boolean g_sessionsAvailable = false;

// Height of the graph panel at the bottom of the window (px).
// Anything above it belongs to the 3D scene + HUD.
final int GRAPH_H = 220;

// Pixels per metre for all mesh + world translations. Must match the paddle
// OBJ scale (Model3D.loadPaddle uses 300) and the kayak vertex scale.
final float MODEL_SCALE = 300;

// Average paddle-centre position relative to the boat's centre, toward the
// bow — a measured physical fact (user, 20 Jul 2026), not a tuned display
// offset. Kayak-body +Y = bow (Model3D.drawKayak()'s convention, shared by
// CatchEvents' boat-frame xB/yB). Global so drawSliceC()'s 3D mesh
// translate and CatchEvents.addEventIfLoud()'s entry/exit placement use
// the same single value — they were briefly out of sync (found 20 Jul
// 2026: the 3D view moved, the entry/exit panel didn't).
final float PADDLE_BOW_OFFSET_M = 0.45f;

// Slice / view state
int     sliceMode  = 0;   // 0 = Slice 0 (calibration), 1 = Slice A, 2 = Slice B, 3 = Slice C (combined)

// Camera — orbit + zoom around world origin. az / el / dist replace the old
// two-preset viewMode. V cycles between the side and near-top presets; mouse
// drag orbits; wheel zooms.
float   camAzimDeg    = 0;      // rotation about world Z; 0 = looking from -Y
float   camElevDeg    = 0;      // elevation above horizontal; +ve tilts toward physical up
float   camDist       = 1200;   // distance from origin
int     dragMouseX    = 0;
int     dragMouseY    = 0;
float   dragStartAz   = 0;
float   dragStartEl   = 0;
boolean camDragging   = false;

// Per-source frame indices and playback
int     paddleFrameIdx = 0;
int     boatFrameIdx   = 0;
boolean playing        = false;
int     lastAdvanceMs  = 0;

// Playback speed multiplier — '>' doubles it (capped), '<' resets to x1.
// Real-time bookkeeping in stepPlayback() stays decoupled from this so
// there's no drift when the speed changes mid-playback (notes 20 Jul 2026).
float   playbackSpeed    = 1.0f;
final float PLAYBACK_SPEED_MAX = 8.0f;

// Reference-pose subtraction — separate for paddle and boat.
// When active, each frame renders q_ref_conj * q_current so that the
// captured frame appears in the Slice 0 identity pose.
float[] qRefPad       = { 1, 0, 0, 0 };
int     refFramePad   = -1;
float[] qRefBoat      = { 1, 0, 0, 0 };
int     refFrameBoat  = -1;

// GRV counterparts of qRefPad/qRefBoat, captured over the same windows
// (same refFramePad/refFrameBoat >= 0 gates whether they're valid) —
// used only by drawSliceC()'s paddle-vs-kayak relative orientation, not
// by Slice A/B (which stay fused-only, unaffected). Fused yaw was found
// to carry a mag artefact for this exact relative-yaw quantity (spec
// §16.11); GRV is mag-free. Investigation 20 Jul 2026 (notes20260720.txt)
// found drawSliceC() was still fused-only after CatchEvents had already
// switched to GRV — this pair closes that gap. Identity when unset or
// when either CSV lacks GRV columns.
float[] qRefPadGrv    = { 1, 0, 0, 0 };
float[] qRefBoatGrv   = { 1, 0, 0, 0 };

// Slice-history ping-pong. Backspace / '-' swaps sliceMode with the last
// value it held. Same model as GraphPanel's double-right-click zoom revert.
int     prevSliceMode = -1;

// Top-centre HUD flash — brief visual confirmation for ref capture/clear,
// or (triggerErrorFlash) a warning/error that stays until the user clicks
// it to dismiss, since a 1.5 s auto-fade was too short to reliably read
// (notes 20 Jul 2026). flashBox* is the last-drawn hit box, used by
// mousePressed() to detect the dismiss click.
int     refFlashUntilMs = 0;
String  refFlashMsg     = "";
boolean refFlashIsError = false;
float   flashBoxL, flashBoxR, flashBoxT, flashBoxB;

void settings() {
    size(1400, 900, P3D);
    smooth(4);
}

void setup() {
    cal = new Calibration();
    cal.load(sketchPath("data/model_calibration.json"));

    model3D = new Model3D();
    model3D.loadPaddle("paddle60.obj");

    sync      = new SyncMap();
    graph     = new GraphPanel(0, height - GRAPH_H, width, GRAPH_H);
    wizard    = new Wizard();
    classify  = new Classification();
    menu      = new Menu();
    eePanel   = new EntryExitPanel();
    detailPanel = new DetailPanel();
    avgPanel    = new StrokeAveragePanel();

    g_sessionsAvailable = hasSessionJson();

    surface.setResizable(true);
    surface.setTitle("PadViz7");
    println("PadViz7 —  0=Slice0 cal   1=SliceA paddle   2=SliceB kayak   3=SliceC world   V=cycle preset   Backspace/-=back");
    println("Session setup wizard: F1 shows/hides it. Return advances each step.");
    println("Camera:  left-drag orbits   mouse wheel zooms   V snaps to side/top preset");
    println("Load:  p=paddle CSV   b=boat CSV");
    println("Slices A/B/C:  Space=play/pause   Left/Right=step 100   ,/.=step 1   >/<=fast x2/reset speed   k=capture ref   u=clear ref   S=reset zoom   E=export   C=build session sidecar");
    println("Slice 0:  y/Y i/I r/R=nudge model triple   n/N=nudge entry-exit yaw datum   g=reset it   [/]=step   Z/S/L=zero/save/list");
}

void draw() {
    background(20);
    // Keep the graph bounds locked to the window each frame so resize
    // immediately re-lays out the strip.
    if (graph != null) graph.setBounds(0, height - GRAPH_H, width, GRAPH_H);
    stepPlayback();

    // While the setup/summary window is up it owns the screen: skip the 3D
    // scene and the analysis overlays (side panels, HUD + detail box, axis
    // compass + legend) so nothing shows through or pokes out around the
    // compact panel. Only the graph strip stays — it's needed to position the
    // cursor in steps 3 (rest window) and 4 (classification). This is the real
    // fix for "cover the windows underneath": a compact panel can't physically
    // cover full-height side panels or the bottom compass, and in P3D even an
    // opaque fill let them bleed — so we don't draw them at all here.
    boolean setup = (wizard != null && wizard.shown);

    if (!setup) drawScene3D();

    // 2D overlays, back to front: side panels (entry/exit left, stroke
    // average right), HUD (shifted right of the left panel), graph strip,
    // startup overlay, menu, flash.
    camera();
    hint(DISABLE_DEPTH_TEST);
    if (!setup && isPanelVisible()) {
        eePanel.draw(catchEvents, paddleFrameIdx);
        avgPanel.draw(catchEvents, paddleFrameIdx);
    }
    if (!setup) {
        pushMatrix();
        translate(leftPanelWidth(), 0);
        drawHUD();
        drawAxisCompass();
        popMatrix();
        drawAxisLegend();
    }
    if (isGraphVisible()) graph.draw(paddleData, boatData, sync, paddleFrameIdx);
    if (wizard != null) wizard.draw();
    if (menu != null) menu.draw();
    drawRefFlash();
    hint(ENABLE_DEPTH_TEST);
}

// Graph panel is only meaningful when a paddle CSV is loaded and we're in a
// data-driven slice (A/B/C). Slice 0 is a static calibration view.
boolean isGraphVisible() {
    return graph != null
        && sliceMode >= 1
        && paddleData != null
        && paddleData.frameCount() > 0;
}

// Entry/exit panel (v0.14) — left 20 % of the window in data slices.
boolean isPanelVisible() {
    return eePanel != null
        && sliceMode >= 1
        && paddleData != null
        && paddleData.frameCount() > 0
        && catchEvents != null;
}

// Width in px of the entry/exit panel, 0 when hidden. HUD, compass, menu
// and the startup overlay all shift right by this amount.
int leftPanelWidth() {
    return isPanelVisible() ? int(width * 0.20f) : 0;
}

// Width in px of the stroke-average panel (v0.15, right-hand mirror of
// the entry/exit panel) — same visibility condition, same proportion.
// The axis legend shifts left by this amount so it isn't hidden behind it.
int rightPanelWidth() {
    return isPanelVisible() ? int(width * 0.20f) : 0;
}

// ── 3D scene ──────────────────────────────────────────────────────────────────

void drawScene3D() {
    lights();
    setCamera();

    pushMatrix();
    scale(1, 1, -1);          // handedness bridge: worldRH ← sensorLH

    // (Axis triad is drawn as a 2D compass widget in the HUD — see
    //  drawAxisCompass(). Nothing is drawn at world origin here so the
    //  paddle/kayak meshes are not visually cluttered.)

    if (sliceMode == 3 && paddleData != null && paddleData.frameCount() > 0
                       && boatData   != null && boatData.frameCount()   > 0) {
        drawSliceC();
    } else if (sliceMode == 2 && boatData != null && boatData.frameCount() > 0) {
        // Slice B — kayak from boat CSV. No paddle cal triple: kayak is not
        // in the paddle-model Blender frame.
        BoatFrameData bfd = boatData.frameAt(boatFrameIdx);
        float[] qCur = { bfd.qw, bfd.qx, bfd.qy, bfd.qz };
        float[] qDisp = (refFrameBoat >= 0) ? qMul(qConj(qRefBoat), qCur) : qCur;
        model3D.applyQuat(qDisp[0], qDisp[1], qDisp[2], qDisp[3]);
        model3D.drawKayak();
    } else if (sliceMode == 1 && paddleData != null && paddleData.frameCount() > 0) {
        // Slice A — paddle from paddle CSV.
        FrameData fd = paddleData.frameAt(paddleFrameIdx);
        float[] qCur = { fd.qw, fd.qx, fd.qy, fd.qz };
        float[] qDisp = (refFramePad >= 0) ? qMul(qConj(qRefPad), qCur) : qCur;
        // Paddle-centre offset from accel double-integration (world_LH, metres).
        // Written first so it is applied last to the vertex — the mesh is
        // rotated by cal + quat as before, then translated to its world position.
        translate(fd.posX * MODEL_SCALE, fd.posY * MODEL_SCALE, fd.posZ * MODEL_SCALE);
        applyCalTriple();
        model3D.applyQuat(qDisp[0], qDisp[1], qDisp[2], qDisp[3]);
        model3D.drawPaddle();
    } else {
        // Slice 0 or empty data — draw paddle at identity, under cal triple.
        applyCalTriple();
        model3D.drawPaddle();
    }

    popMatrix();
}

// sensorLH ← blenderLH — paddle OBJ mesh alignment to paddle-IMU frame.
// Immutable, values from model_calibration.json. Applied only inside branches
// that draw the paddle mesh.
void applyCalTriple() {
    rotateZ(radians(cal.yawDeg));
    rotateY(radians(cal.pitchDeg));
    rotateX(radians(cal.rollDeg));
}

// Slice C — combined. Kayak drives world orientation; paddle drawn inside
// the kayak's local frame using its relative rotation.
//
// Absolute quats from BNO085 map body-rest -> sensor-world. Relative paddle-
// vs-kayak rotation is  qRel = qKayak_conj * qPaddle.  If both K refs have
// been captured (over the same window), the constant rest offset
// (qRefBoat_conj * qRefPad) is subtracted from qRel so the captured pose
// renders at Slice 0 identity in the kayak frame.
//
// Boat frame is selected via SyncMap.rx_ms (< 10 ms typical) or gps_utc_sec
// (± 5 s fallback). If no match, boatFrameIdx is preserved and rendering
// proceeds; the HUD flags NO SYNC.
void drawSliceC() {
    int bi = sync.boatIdxFor(paddleFrameIdx);
    if (bi >= 0) boatFrameIdx = bi;     // sync'd; keep HUD honest
    int bDraw = (bi >= 0) ? bi : boatFrameIdx;

    FrameData     fd  = paddleData.frameAt(paddleFrameIdx);
    BoatFrameData bfd = boatData.frameAt(bDraw);

    // Prefer GRV (mag-free) over fused for this render when both files
    // have it — CatchEvents already made this switch (spec §16.11: fused
    // yaw carries an in-band cycle-periodic mag artefact for exactly this
    // paddle-vs-boat relative-yaw quantity; GRV doesn't). Investigation
    // 20 Jul 2026 (notes20260720.txt) found this function had been left
    // fused-only, so its rest-window reference could bake in a large
    // magnetometer bias from whatever mag_cal state existed at the
    // captured instant — plausible root cause of a reported ~60° error
    // that the entry/exit panel (GRV-based) didn't share. Gated on BOTH
    // files having GRV (not per-sensor) so paddle and boat are never
    // mixed fused-vs-GRV, which would reintroduce the same class of bug.
    boolean useGrvC = paddleData.hasGrv && boatData.hasGrv;

    float[] qPad  = useGrvC ? new float[]{ fd.grvQw,  fd.grvQx,  fd.grvQy,  fd.grvQz  }
                             : new float[]{ fd.qw,     fd.qx,     fd.qy,     fd.qz     };
    float[] qBoat = useGrvC ? new float[]{ bfd.grvQw, bfd.grvQx, bfd.grvQy, bfd.grvQz }
                             : new float[]{ bfd.qw,    bfd.qx,    bfd.qy,    bfd.qz    };

    // kayakLH ← paddleLH  (paddle rotation expressed in kayak-body frame)
    float[] qRel = qMul(qConj(qBoat), qPad);

    // Reference-subtraction. Applied per-frame only if both refs captured.
    // Kayak: rendered relative to captured kayak rest (as in Slice B).
    // Paddle: rendered relative to captured paddle-vs-kayak rest offset —
    // this collapses the magnetic-yaw datum difference between the two IMUs.
    // qRefPadGrv/qRefBoatGrv are captured over the same windows as
    // qRefPad/qRefBoat (same refFramePad/refFrameBoat >= 0 gate) — see
    // buildAndSaveSidecar(), applySidecarToDisplay(), handleFrameNavCombined().
    float[] qBoatDisp = qBoat;
    float[] qRelDisp  = qRel;
    if (refFrameBoat >= 0) {
        qBoatDisp = qMul(qConj(useGrvC ? qRefBoatGrv : qRefBoat), qBoat);
    }
    if (refFramePad >= 0 && refFrameBoat >= 0) {
        float[] qRefP = useGrvC ? qRefPadGrv  : qRefPad;
        float[] qRefB = useGrvC ? qRefBoatGrv : qRefBoat;
        float[] qRelRef = qMul(qConj(qRefB), qRefP);   // kayakLH ← paddleLH at rest
        qRelDisp = qMul(qConj(qRelRef), qRel);
    }

    // Same yaw-datum manual override as the entry/exit panel (Sidecar.
    // yawManualAdjustDeg, n/N/g — spec §13.7), still applied on top of the
    // GRV-based reference above as a residual fine-adjustment — e.g. for
    // whatever small physical mounting misalignment remains between the
    // two sensors' own axis conventions, which GRV doesn't correct (GRV
    // removes the *magnetic* bias, not a mechanical one). Now that the
    // rest-window reference itself is GRV-based when available (spec
    // §13.7 item 9), this value is expected to need only a small nudge in
    // the common case, not the ~60° that was compensating for a fused-quat
    // magnetic bias before this fix. Applied as an extra rotation about
    // the kayak's own Z (deck-up) axis, composed on the outside of
    // qRelDisp so it spins the paddle around the kayak's vertical without
    // touching its tilt. Sign matches CatchEvents' convention (positive
    // nudge rotates clockwise, viewed from above) but is not independently
    // verified for this 3D view — flip the sign below if it goes the wrong
    // way on screen.
    if (sidecar != null && sidecar.yawManualAdjustDeg != 0) {
        float corrRad = -radians(sidecar.yawManualAdjustDeg);
        float[] qYawCorr = { cos(corrRad / 2), 0, 0, sin(corrRad / 2) };
        qRelDisp = qMul(qYawCorr, qRelDisp);
    }

    // Kayak in world (boat-IMU frame; no paddle cal triple).
    // worldRH ← kayakLH
    pushMatrix();
    model3D.applyQuat(qBoatDisp[0], qBoatDisp[1], qBoatDisp[2], qBoatDisp[3]);
    model3D.drawKayak();

    // Lift the paddle so its shaft centre sits above the deck rather than
    // overlapping the cockpit. This is a display offset applied in kayak-body
    // coords (deck-up = +Z_kayak) — not a measurement of the physical paddle
    // location. 300 px/m matches the paddle and kayak model scale.
    final float PADDLE_LIFT_M = 0.3f;

    // PADDLE_BOW_OFFSET_M (global, top of file) — same +Y bow translate,
    // shared with CatchEvents.addEventIfLoud()'s entry/exit placement.
    translate(0, PADDLE_BOW_OFFSET_M * MODEL_SCALE, PADDLE_LIFT_M * MODEL_SCALE);

    // Paddle-centre offset from accel double-integration. Applied in kayak-
    // body frame so the paddle swings relative to the kayak rather than the
    // world — visually it drops toward whichever side has a blade in the water.
    FrameData fdP = paddleData.frameAt(paddleFrameIdx);
    translate(fdP.posX * MODEL_SCALE, fdP.posY * MODEL_SCALE, fdP.posZ * MODEL_SCALE);

    // Paddle inside the kayak's local frame — cal triple + relative quat.
    // kayakLH ← paddleLH ← blenderLH
    applyCalTriple();
    model3D.applyQuat(qRelDisp[0], qRelDisp[1], qRelDisp[2], qRelDisp[3]);
    model3D.drawPaddle();
    popMatrix();
}

void setCamera() {
    float[] eye   = new float[3];
    float[] fwd   = new float[3];
    float[] right = new float[3];
    float[] up    = new float[3];
    getCameraBasis(eye, fwd, right, up);
    camera(eye[0], eye[1], eye[2],  0, 0, 0,  up[0], up[1], up[2]);
}

// Compute the current camera's world-space basis. Also used by
// drawAxisCompass() so the 2D compass rotates in step with the 3D scene.
//
// Baseline (az = 0, el = 0): eye at (0, -camDist, 0), looking toward origin.
// Elevation positive tilts the eye toward physical up (world -Z after the
// handedness bridge). world_up choice is world +Z throughout; clamped
// elevation range (constrained to ±89° at input) keeps right non-degenerate.
void getCameraBasis(float[] eye, float[] fwd, float[] right, float[] up) {
    float az = radians(camAzimDeg);
    float el = radians(camElevDeg);
    float ch = cos(el);
    float sh = sin(el);

    eye[0] =  camDist * ch * sin(az);
    eye[1] = -camDist * ch * cos(az);
    eye[2] = -camDist * sh;

    float mag = sqrt(eye[0]*eye[0] + eye[1]*eye[1] + eye[2]*eye[2]);
    if (mag < 1e-6) mag = 1;
    fwd[0] = -eye[0] / mag;
    fwd[1] = -eye[1] / mag;
    fwd[2] = -eye[2] / mag;

    // world_up = (0, 0, 1). right = normalize(cross(forward, world_up)).
    right[0] = fwd[1] * 1 - fwd[2] * 0;
    right[1] = fwd[2] * 0 - fwd[0] * 1;
    right[2] = fwd[0] * 0 - fwd[1] * 0;
    float rmag = sqrt(right[0]*right[0] + right[1]*right[1] + right[2]*right[2]);
    if (rmag < 1e-6) rmag = 1;
    right[0] /= rmag; right[1] /= rmag; right[2] /= rmag;

    up[0] = right[1] * fwd[2] - right[2] * fwd[1];
    up[1] = right[2] * fwd[0] - right[0] * fwd[2];
    up[2] = right[0] * fwd[1] - right[1] * fwd[0];
}

// 2D axis compass drawn in the HUD overlay, in the bottom-left of the
// visualisation area. Sits above the graph panel when the graph is visible,
// otherwise at the bottom of the window. About one third the on-screen size
// of the previous world-origin axes (~80 px per axis). Colour convention
// matches the world-origin lines: X red, Y green, Z blue.
//
// The letter above the compass names the frame currently in view:
//   Slice 0 / A  -> "P" (paddle)
//   Slice B      -> "K" (kayak)
//   Slice C      -> "W" (combined world)
// 2D axis triad, projected through the current camera. Placed in the
// bottom-left of the visualisation area — above the graph when it's visible,
// otherwise at the window bottom.
//
// Each sensor axis is transformed through the handedness bridge and then
// projected through the current camera basis (via getCameraBasis) so the
// compass rotates in step with the 3D scene. Axes that are near-perpendicular
// to the screen render as a disc-in-ring (out of screen) or an X (into
// screen); those with meaningful projected length render as coloured lines.
void drawAxisCompass() {
    // Bottom of the 3D area — above the graph strip when it's showing.
    int bottom = isGraphVisible() ? (height - GRAPH_H) : height;
    int ox = 92;
    int oy = bottom - 30;
    int L  = 80;

    float[] eye   = new float[3];
    float[] fwd   = new float[3];
    float[] right = new float[3];
    float[] up    = new float[3];
    getCameraBasis(eye, fwd, right, up);

    // Sensor axes after the handedness bridge (scale(1,1,-1) flips Z).
    float[][] axes = {
        {1, 0,  0},   // sensor +X
        {0, 1,  0},   // sensor +Y
        {0, 0, -1}    // sensor +Z (physical up under bridge)
    };
    int[]    cols   = { color(255, 100, 100), color(120, 220, 120), color(120, 200, 255) };
    String[] labels = { "+X", "+Y", "+Z" };

    // Frame letter above the triad.
    fill(230);  textAlign(CENTER, BOTTOM);  textSize(30);
    text(compassLetter(), ox, oy - L - 8);

    for (int i = 0; i < 3; i++) {
        float[] v = axes[i];
        float sdx = right[0]*v[0] + right[1]*v[1] + right[2]*v[2];
        float sdy = up[0]   *v[0] + up[1]   *v[1] + up[2]   *v[2];
        float dep = fwd[0]  *v[0] + fwd[1]  *v[1] + fwd[2]  *v[2];
        float pm  = sqrt(sdx*sdx + sdy*sdy);

        if (pm > 0.15) {
            float endX = ox + L * sdx;
            float endY = oy + L * sdy;
            stroke(cols[i]);  strokeWeight(2);
            line(ox, oy, endX, endY);
            noStroke();  fill(cols[i]);  textSize(12);
            textAlign(sdx >  0.1 ? LEFT   : (sdx < -0.1 ? RIGHT  : CENTER),
                      sdy >  0.1 ? TOP    : (sdy < -0.1 ? BOTTOM : CENTER));
            float lx = endX + 6 * (sdx > 0.1 ? 1 : (sdx < -0.1 ? -1 : 0));
            float ly = endY + 6 * (sdy > 0.1 ? 1 : (sdy < -0.1 ? -1 : 0));
            text(labels[i], lx, ly);
        } else {
            // Near-perpendicular to screen — disc (out) or X (in).
            stroke(cols[i]);  strokeWeight(2);
            if (dep < 0) {
                noFill();  ellipse(ox, oy, 14, 14);
                noStroke(); fill(cols[i]);  ellipse(ox, oy, 4, 4);
            } else {
                line(ox - 4, oy - 4, ox + 4, oy + 4);
                line(ox - 4, oy + 4, ox + 4, oy - 4);
                noStroke();
            }
            fill(cols[i]);  textSize(12);
            textAlign(LEFT, TOP);
            text(labels[i], ox + 10, oy + 8 + i * 12);   // stack labels vertically
        }
    }
    strokeWeight(1);
    textAlign(LEFT, TOP);
}

String compassLetter() {
    switch (sliceMode) {
        case 0:  return "P";
        case 1:  return "P";
        case 2:  return "K";
        default: return "W";
    }
}

// ── HUD ───────────────────────────────────────────────────────────────────────

void drawHUD() {
    noStroke();
    fill(255);
    textAlign(LEFT, TOP);
    textSize(16);

    String modeName;
    switch (sliceMode) {
        case 0:  modeName = "Slice 0 — Paddle Model Calibration"; break;
        case 1:  modeName = "Slice A — Paddle (data-driven)";      break;
        case 2:  modeName = "Slice B — Kayak (data-driven)";       break;
        default: modeName = "Slice C — Combined (paddle + kayak)"; break;
    }
    String viewName = String.format("cam az=%+.0f°  el=%+.0f°  d=%.0f",
                                     camAzimDeg, camElevDeg, camDist);
    String speedStr = (sliceMode >= 1 && playbackSpeed != 1.0f)
                       ? String.format("   speed=x%.0f%s", playbackSpeed, playing ? "" : " (paused)")
                       : "";
    // Own top row — the Commands and Detail buttons sit on the row below
    // (y=38), not sharing this line, so this no longer needs to dodge
    // the Commands button on x (notes 20 Jul 2026).
    text("PadViz7   " + modeName + "   [" + viewName + "]" + speedStr, 20, 10);

    // Detail panel (v0.15, spec §13.8) — collapsible box for everything
    // below (sidecar/yaw-datum corrections, per-slice current-data-point
    // readout, footer). The title line above stays visible either way.
    detailPanel.drawButton();
    if (!detailPanel.open) return;
    detailPanel.drawBox();

    // The per-slice drawHUD_sliceX() functions (and the sidecar line
    // below) use y-coordinates designed for the pre-v0.15 layout, where
    // this content started right under the title line. Shifting the
    // whole block down by CONTENT_Y_OFFSET clears the button (ends at
    // y=64) and starts just inside the box top (BOX_Y=70) without having
    // to touch every hardcoded y value in four functions.
    final int CONTENT_Y_OFFSET = 40;
    pushMatrix();
    translate(0, CONTENT_Y_OFFSET);

    // Sidecar indicator.
    if (sidecar != null && sidecar.valid) {
        int col = (sidecar.confidence.equals("high"))   ? color(150, 220, 150)
                : (sidecar.confidence.equals("medium")) ? color(230, 220, 140)
                :                                         color(230, 140, 140);
        fill(col);
        textSize(12);
        text(String.format("SIDECAR [%s]  padMount r=%+.1f° p=%+.1f°  boatMount r=%+.1f° p=%+.1f°  yaw datum=%+.1f°",
                           sidecar.confidence,
                           sidecar.rollOffsetPadDeg,  sidecar.pitchOffsetPadDeg,
                           sidecar.rollOffsetBoatDeg, sidecar.pitchOffsetBoatDeg,
                           sidecar.yawDatumDeg),
             20, 38);
        textSize(13);
    }
    // (v0.14: the "SIDECAR not built" hint is gone — the startup overlay
    //  stays on screen through the seek-and-C step instead.)

    textSize(13);
    if      (sliceMode == 0) drawHUD_slice0();
    else if (sliceMode == 1) drawHUD_sliceA();
    else if (sliceMode == 2) drawHUD_sliceB();
    else                     drawHUD_sliceC();
    popMatrix();

    // (Axis legend is drawn by draw() outside the panel translate so it
    //  stays anchored to the window's right edge.)

    // Classification summary (v0.16, spec §14) — counts per type + total
    // excluded duration; the "note that data has been excluded" line the user
    // asked for. Sits just above the footer, clear of the per-slice readout.
    if (sidecar != null && sidecar.valid && sidecar.classification.size() > 0) {
        fill(190, 200, 220);
        textSize(11);
        text(classificationSummary(sidecar.classification),
             20, DetailPanel.BOX_Y + DetailPanel.BOX_H - 32);
    }

    // Footer — inside the detail box now, not the literal window bottom.
    fill(160);
    textSize(11);
    text("model calibration file:  " + cal.savePath, 20, DetailPanel.BOX_Y + DetailPanel.BOX_H - 16);
}

void drawAxisLegend() {
    // Shifts left by rightPanelWidth() so the stroke-average panel (v0.15)
    // doesn't sit behind it.
    int lx = width - 380 - rightPanelWidth();
    textSize(13);
    fill(220);
    if (sliceMode == 2 || sliceMode == 3) {
        // Slice B: kayak alone. Slice C: kayak drives world, so world axes = boat frame.
        text("Boat sensor axes at origin", lx, 16);
        textSize(12);
        fill(255, 80, 80);   text("+X  starboard",              lx, 42);
        fill(80, 255, 80);   text("+Y  bow (forward)",           lx, 60);
        fill(100, 140, 255); text("+Z  up (deck)",               lx, 78);
    } else {
        text("Paddle sensor axes at origin", lx, 16);
        textSize(12);
        fill(255, 80, 80);   text("+X  shaft toward right blade", lx, 42);
        fill(80, 255, 80);   text("+Y  blade normal",             lx, 60);
        fill(100, 140, 255); text("+Z  in-blade (up in cal pose)",lx, 78);
    }
}

void drawHUD_slice0() {
    fill(200, 220, 255);
    text("Model calibration (ZYX Euler, degrees)", 20, 56);
    fill(255);
    text(String.format("yaw   = %8.2f", cal.yawDeg),   20, 78);
    text(String.format("pitch = %8.2f", cal.pitchDeg), 20, 96);
    text(String.format("roll  = %8.2f", cal.rollDeg),  20, 114);
    fill(180);
    text(String.format("step  = %8.2f", cal.stepDeg),  20, 138);

    // Paddle-vs-boat yaw datum — a data-record calibration, not the
    // model-mesh triple above. Drives two independent renders: CatchEvents'
    // entry/exit placement (auto value = rest-window or whole-file mean),
    // and drawSliceC()'s 3D paddle-vs-kayak relative orientation (via an
    // extra Z-axis rotation on qRelDisp). n/N nudge one manual correction
    // that both consume, saved into the sidecar so it persists (notes
    // 20 Jul 2026, spec §13.7).
    fill(200, 220, 255);
    text("Paddle-vs-boat yaw datum (data record)", 20, 168);
    if (catchEvents != null) {
        String src    = catchEvents.datumFromSidecar ? "rest window" : "whole-file mean";
        float  manual = (sidecar != null) ? sidecar.yawManualAdjustDeg : 0;
        float  total  = wrapDeg180(catchEvents.datumAutoDeg + manual);
        fill(255);
        text(String.format("auto (%s)  = %+7.2f°", src, catchEvents.datumAutoDeg), 20, 190);
        text(String.format("manual adjust      = %+7.2f°", manual), 20, 208);
        fill(180, 255, 180);
        text(String.format("effective total    = %+7.2f°", total), 20, 226);
        fill(140);
        textSize(11);
        text("n/N nudge by step   g reset manual to 0   (needs C run at least once)", 20, 248);
        text("affects the entry/exit panel AND Slice C's 3D paddle-vs-kayak view", 20, 264);
        textSize(13);
    } else {
        fill(150);
        text("no data loaded — press p to load a paddle CSV, then C", 20, 190);
    }

    fill(140);
    textSize(12);
    text("key bindings: Commands menu (top-left)", 20, 272);
}

void drawHUD_sliceA() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No paddle CSV loaded — press P", 20, 56);
        return;
    }
    FrameData fd = paddleData.frameAt(paddleFrameIdx);
    int   nFrames = paddleData.frameCount();
    float tSec    = fd.ts / 1000.0;

    fill(200, 220, 255);
    text("Paddle CSV:  " + paddleData.sourceName(), 20, 56);
    fill(255);
    text(String.format("frame  %6d / %d", paddleFrameIdx, nFrames - 1), 20, 78);
    text(String.format("ts     %10.3f s   (rx_ms %d)", tSec, fd.rxMs), 20, 96);
    text(String.format("q  = (%.4f, %.4f, %.4f, %.4f)", fd.qw, fd.qx, fd.qy, fd.qz), 20, 114);
    text(String.format("euler  roll=%7.2f  pitch=%7.2f  yaw=%7.2f", fd.roll, fd.pitch, fd.yaw), 20, 132);

    drawRefStatus(refFramePad, 150);
}

void drawHUD_sliceB() {
    if (boatData == null || boatData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No boat CSV loaded — press B", 20, 56);
        return;
    }
    BoatFrameData bfd = boatData.frameAt(boatFrameIdx);
    int   nFrames = boatData.frameCount();
    float tSec    = bfd.ts / 1000.0;

    fill(200, 220, 255);
    text("Boat CSV:  " + boatData.sourceName(), 20, 56);
    fill(255);
    text(String.format("frame  %6d / %d", boatFrameIdx, nFrames - 1), 20, 78);
    text(String.format("ts     %10.3f s   (rx_ms %d)", tSec, bfd.rxMs), 20, 96);
    text(String.format("q  = (%.4f, %.4f, %.4f, %.4f)", bfd.qw, bfd.qx, bfd.qy, bfd.qz), 20, 114);
    text(String.format("euler  roll=%7.2f  pitch=%7.2f  yaw=%7.2f", bfd.roll, bfd.pitch, bfd.yaw), 20, 132);

    // K = kayak-only. If the paddle CSV is also loaded, point the user at the
    // combined view — a common expectation after seeing "K" on the compass.
    int gpsY = 152;
    if (paddleData != null && paddleData.frameCount() > 0) {
        fill(140, 200, 255);
        textSize(11);
        text("Paddle CSV also loaded — press 3 for combined kayak+paddle view", 20, 152);
        textSize(13);
        gpsY = 172;
    }

    // GPS block
    fill(200);
    text(String.format("GPS  fix=%s  speed=%.2f m/s  COG=%.1f°  utc=%d",
                       bfd.gpsFix ? "yes" : "no", bfd.speedMs, bfd.cogDeg, bfd.gpsUtcSec), 20, gpsY);

    drawRefStatus(refFrameBoat, gpsY + 20);
}

void drawHUD_sliceC() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No paddle CSV loaded — press P", 20, 56);
        return;
    }
    if (boatData == null || boatData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No boat CSV loaded — press B", 20, 56);
        return;
    }
    FrameData     fd  = paddleData.frameAt(paddleFrameIdx);
    BoatFrameData bfd = boatData.frameAt(boatFrameIdx);
    int   nPad  = paddleData.frameCount();
    int   nBoat = boatData.frameCount();

    // Sync status
    int  bi     = sync.boatIdxFor(paddleFrameIdx);
    long dSync  = sync.syncDeltaMs(paddleData, paddleFrameIdx);
    String syncStr;
    if (bi < 0) syncStr = "NO SYNC (paddle frame outside match window)";
    else if (sync.usedRxMs && dSync != Long.MAX_VALUE)
        syncStr = String.format("rx_ms path  delta = %+d ms", dSync);
    else syncStr = "gps_utc path  (+-5 s)";

    fill(200, 220, 255);
    text("Paddle CSV:  " + paddleData.sourceName(), 20, 56);
    text("Boat   CSV:  " + boatData.sourceName(),   20, 74);
    fill(255);
    text(String.format("pad frame  %6d / %d   rx_ms %d", paddleFrameIdx, nPad  - 1, fd.rxMs),  20, 96);
    text(String.format("boat frame %6d / %d   rx_ms %d", boatFrameIdx,   nBoat - 1, bfd.rxMs), 20, 114);
    fill((bi < 0) ? color(255, 120, 120) : color(150, 220, 150));
    text("sync:  " + syncStr, 20, 132);

    fill(255);
    text(String.format("q_paddle (%.3f, %.3f, %.3f, %.3f)", fd.qw, fd.qx, fd.qy, fd.qz),   20, 154);
    text(String.format("q_kayak  (%.3f, %.3f, %.3f, %.3f)", bfd.qw, bfd.qx, bfd.qy, bfd.qz), 20, 172);

    fill(200);
    text(String.format("GPS  fix=%s  speed=%.2f m/s  COG=%.1f°  utc=%d",
                       bfd.gpsFix ? "yes" : "no", bfd.speedMs, bfd.cogDeg, bfd.gpsUtcSec), 20, 192);

    // Two-line ref status — Slice C consumes both refs together.
    int y = 214;
    if (refFramePad >= 0 && refFrameBoat >= 0) {
        fill(180, 255, 180);
        text(String.format("refs captured   pad frame %d   boat frame %d   (paddle rendered relative to captured rest offset)",
                           refFramePad, refFrameBoat), 20, y);
    } else if (refFramePad >= 0 || refFrameBoat >= 0) {
        fill(230, 220, 140);
        text("only one ref captured — press K again after loading both CSVs; U to clear", 20, y);
    } else {
        fill(200);
        text("refs = identity  (K captures paddle + matched boat rest simultaneously; U clears)", 20, y);
    }

    // Quat source for this render — GRV (mag-free) when both files have
    // it, else fused. See drawSliceC()'s useGrvC (spec §13.7 item 9).
    boolean useGrvC = paddleData.hasGrv && boatData.hasGrv;
    fill(useGrvC ? color(150, 220, 150) : color(230, 220, 140));
    textSize(11);
    text("relative-yaw source: " + (useGrvC ? "GRV (mag-free)" : "fused (no GRV in one or both files)"),
         20, y + 20);
    textSize(13);
}

void drawRefStatus(int refFrame, int yPos) {
    if (refFrame >= 0) {
        fill(180, 255, 180);
        text(String.format("ref frame %d  (relative to captured rest pose)", refFrame), 20, yPos);
    } else {
        fill(200);
        text("ref = identity  (raw absolute quaternion — K to capture rest)", 20, yPos);
    }
}

// ── Playback / input ─────────────────────────────────────────────────────────

void stepPlayback() {
    if (!playing) return;
    int now = millis();
    // Real-time 100 Hz tick count, tracked drift-free regardless of speed —
    // playbackSpeed only scales how many frames each tick advances.
    int nReal = (now - lastAdvanceMs) / 10;
    if (nReal <= 0) return;
    lastAdvanceMs += nReal * 10;
    int nAdvance = round(nReal * playbackSpeed);
    if (nAdvance <= 0) return;

    if ((sliceMode == 1 || sliceMode == 3)
            && paddleData != null && paddleData.frameCount() > 0) {
        // Slice A + C: paddle frame is the timeline master. In Slice C the
        // matched boat frame is picked up in drawSliceC() via SyncMap.
        // stepVisible skips excluded classification ranges (spec §14).
        int last = classify.lastVisible();
        paddleFrameIdx = classify.stepVisible(paddleFrameIdx, nAdvance);
        if (paddleFrameIdx >= last) playing = false;
    } else if (sliceMode == 2 && boatData != null && boatData.frameCount() > 0) {
        int last = boatData.frameCount() - 1;
        boatFrameIdx = min(last, boatFrameIdx + nAdvance);
        if (boatFrameIdx >= last) playing = false;
    }
}

void keyPressed() {
    // ESC closes the Commands menu instead of quitting the sketch.
    if (key == ESC && menu != null && menu.open) {
        menu.handleEscape();
        key = 0;
        return;
    }
    // F1 shows/hides the session-setup wizard (spec §14). Available always,
    // including as a read-only summary after the wizard has completed.
    if (key == CODED && keyCode == 112) {   // 112 = VK_F1
        if (wizard != null) wizard.toggle();
        return;
    }
    // While the wizard is active it gets first refusal on keys, but only
    // consumes the ones meaningful to the current step — navigation keys
    // (digits, Space, arrows, ,/. …) fall through so the user can still move
    // the graph cursor to position for Steps 3 and 4.
    if (wizard != null && wizard.active() && wizard.handleKey(key, keyCode)) return;
    // Slice/view/load switches — always active.
    // Slice switching is on digits 0/1/2/3 only. The compass letters P/K/W
    // are pure labels — earlier versions bound Shift+letter to the switch,
    // but Caps Lock on Windows silently rewrites case, so pressing `k`
    // (intending to capture the reference) with Caps Lock on would jump to
    // Slice B instead. Dropping the letter shortcuts eliminates that
    // footgun (see spec §12.10 item 2).
    if      (key == '0') { switchSlice(0); return; }
    else if (key == '1') { switchSlice(1); return; }
    else if (key == '2') { switchSlice(2); return; }
    else if (key == '3') { switchSlice(3); return; }
    else if (key == 'v' || key == 'V') {
        // Cycle canonical presets: side (az=0, el=0) <-> near-top (az=0, el=89).
        // Also snaps az to 0 and distance to default, so V doubles as
        // "recenter" from wherever mouse orbit has taken the camera.
        camAzimDeg = 0;
        camDist    = 1200;
        camElevDeg = (abs(camElevDeg) < 45) ? 89 : 0;
        return;
    }
    // Backspace / '-' — ping-pong to the previous slice.
    else if (key == BACKSPACE || key == '-') {
        if (prevSliceMode >= 0) {
            int p         = prevSliceMode;
            prevSliceMode = sliceMode;
            sliceMode     = p;
        }
        return;
    }
    // Lowercase 'p' / 'b' still open the CSV file pickers.
    else if (key == 'p') { selectCsvInput("Select paddle CSV", true);  return; }
    else if (key == 'b' || key == 'B') { selectCsvInput("Select boat CSV", false); return; }

    // Entry/exit yaw-datum manual override (n/N/g) — active in every slice,
    // not just Slice 0. The numeric readout lives in Slice 0's HUD
    // (drawHUD_slice0()), but the panel showing the actual effect is only
    // visible in slices 1-3 (isPanelVisible()), so the nudge itself can't
    // be Slice-0-only or there would be no way to see it move while nudging
    // (bug found 20 Jul 2026 — n/N appeared to do nothing because it was
    // gated inside the sliceMode==0 branch below).
    if (key == 'n') { nudgeManualYawDatum( cal.stepDeg); return; }
    if (key == 'N') { nudgeManualYawDatum(-cal.stepDeg); return; }
    if (key == 'g' || key == 'G') { resetManualYawDatum(); return; }

    // Slice-specific keys.
    if (sliceMode == 0) {
        // Slice 0 — model-mesh calibration triple only (y/Y i/I r/R via
        // cal.handleKey). The yaw-datum override above is handled first and
        // returns, so it never reaches cal.handleKey().
        cal.handleKey(key);
        return;
    }

    // Slices A / B / C — playback, reference, export, zoom reset.
    if (key == ' ') { playing = !playing; lastAdvanceMs = millis(); return; }
    if (key == '>') {
        playbackSpeed = min(playbackSpeed * 2, PLAYBACK_SPEED_MAX);
        triggerRefFlash("PLAYBACK SPEED  x" + nf(playbackSpeed, 0, 0));
        return;
    }
    if (key == '<') {
        playbackSpeed = 1.0f;
        triggerRefFlash("PLAYBACK SPEED RESET  x1");
        return;
    }
    if (key == 'e' || key == 'E') {
        selectOutput("Export merged CSV", "exportFileSelected");
        return;
    }
    if (key == 'c' || key == 'C') {
        buildAndSaveSidecar();
        return;
    }
    if (key == 's' || key == 'S') {
        // Reset graph zoom to full range (same as Full button), retaining the
        // previous zoom in history so a double-right-click on the chart can
        // ping-pong back to where you were.
        if (graph != null) graph.resetZoomToFull();
        return;
    }

    if (sliceMode == 1 && paddleData != null && paddleData.frameCount() > 0) {
        handleFrameNavPaddle();
    } else if (sliceMode == 2 && boatData != null && boatData.frameCount() > 0) {
        handleFrameNavBoat();
    } else if (sliceMode == 3 && paddleData != null && paddleData.frameCount() > 0
                              && boatData   != null && boatData.frameCount()   > 0) {
        handleFrameNavCombined();
    }
}

// Slice C — paddle frame is master; boat frame follows via SyncMap. K
// captures BOTH refs simultaneously (mean over +-50 paddle frames, and over
// the boat window that syncs to the same rx_ms range).
void handleFrameNavCombined() {
    int last = paddleData.frameCount() - 1;
    // Route through stepVisible so excluded classification ranges are skipped
    // by every navigation path, not just autoplay (spec §14). Identity when
    // there are no exclusions.
    if      (key == ',')       paddleFrameIdx = classify.stepVisible(paddleFrameIdx,   -1);
    else if (key == '.')       paddleFrameIdx = classify.stepVisible(paddleFrameIdx,   +1);
    else if (keyCode == LEFT)  paddleFrameIdx = classify.stepVisible(paddleFrameIdx, -100);
    else if (keyCode == RIGHT) paddleFrameIdx = classify.stepVisible(paddleFrameIdx, +100);
    else if (keyCode == 36)    paddleFrameIdx = classify.firstVisible();
    else if (keyCode == 35)    paddleFrameIdx = classify.lastVisible();
    else if (key == 'k') {
        int padLo = paddleFrameIdx - 50, padHi = paddleFrameIdx + 50;
        qRefPad     = paddleData.meanQuat(padLo, padHi);
        refFramePad = paddleFrameIdx;

        // Match the boat window to the same rx_ms span.
        int boatLo = sync.boatIdxFor(max(0, padLo));
        int boatHi = sync.boatIdxFor(min(paddleData.frameCount() - 1, padHi));
        int boatCentre = sync.boatIdxFor(paddleFrameIdx);
        if (boatCentre < 0) boatCentre = boatFrameIdx;
        if (boatLo < 0) boatLo = boatCentre - 50;
        if (boatHi < 0) boatHi = boatCentre + 50;
        qRefBoat     = boatData.meanQuat(boatLo, boatHi);
        refFrameBoat = boatCentre;

        // GRV counterparts over the same windows, for drawSliceC()'s
        // relative-orientation render (spec §13.7 item 9) — identity if
        // either file lacks GRV columns.
        qRefPadGrv  = paddleData.hasGrv ? paddleData.meanQuatGrv(padLo, padHi) : new float[]{ 1, 0, 0, 0 };
        qRefBoatGrv = boatData.hasGrv   ? boatData.meanQuatGrv(boatLo, boatHi) : new float[]{ 1, 0, 0, 0 };

        println("Slice C refs captured — pad frame " + refFramePad
                + "  boat frame " + refFrameBoat);
        triggerRefFlash("BOTH REFS CAPTURED  (pad " + refFramePad
                        + ", boat " + refFrameBoat + ")");
    }
    else if (key == 'u') {
        qRefPad = new float[]{ 1, 0, 0, 0 };
        qRefBoat = new float[]{ 1, 0, 0, 0 };
        qRefPadGrv = new float[]{ 1, 0, 0, 0 };
        qRefBoatGrv = new float[]{ 1, 0, 0, 0 };
        refFramePad = -1;
        refFrameBoat = -1;
        println("Slice C refs cleared.");
        triggerRefFlash("REFS CLEARED");
    }
}

void handleFrameNavPaddle() {
    int last = paddleData.frameCount() - 1;
    // Route through stepVisible so excluded classification ranges are skipped
    // by every navigation path, not just autoplay (spec §14). Identity when
    // there are no exclusions.
    if      (key == ',')       paddleFrameIdx = classify.stepVisible(paddleFrameIdx,   -1);
    else if (key == '.')       paddleFrameIdx = classify.stepVisible(paddleFrameIdx,   +1);
    else if (keyCode == LEFT)  paddleFrameIdx = classify.stepVisible(paddleFrameIdx, -100);
    else if (keyCode == RIGHT) paddleFrameIdx = classify.stepVisible(paddleFrameIdx, +100);
    else if (keyCode == 36)    paddleFrameIdx = classify.firstVisible();
    else if (keyCode == 35)    paddleFrameIdx = classify.lastVisible();
    else if (key == 'k') {
        qRefPad     = paddleData.meanQuat(paddleFrameIdx - 50, paddleFrameIdx + 50);
        refFramePad = paddleFrameIdx;
        println("Paddle ref captured at frame " + refFramePad
                + " (w=" + nf(qRefPad[0],0,4) + " x=" + nf(qRefPad[1],0,4)
                + " y=" + nf(qRefPad[2],0,4) + " z=" + nf(qRefPad[3],0,4) + ")");
        triggerRefFlash("PADDLE REF CAPTURED  (frame " + refFramePad + ")");
    }
    else if (key == 'u') {
        qRefPad = new float[]{ 1, 0, 0, 0 };
        refFramePad = -1;
        println("Paddle ref cleared.");
        triggerRefFlash("PADDLE REF CLEARED");
    }
}

void handleFrameNavBoat() {
    int last = boatData.frameCount() - 1;
    if      (key == ',')       boatFrameIdx = max(0,    boatFrameIdx - 1);
    else if (key == '.')       boatFrameIdx = min(last, boatFrameIdx + 1);
    else if (keyCode == LEFT)  boatFrameIdx = max(0,    boatFrameIdx - 100);
    else if (keyCode == RIGHT) boatFrameIdx = min(last, boatFrameIdx + 100);
    else if (keyCode == 36)    boatFrameIdx = 0;
    else if (keyCode == 35)    boatFrameIdx = last;
    else if (key == 'k') {
        qRefBoat     = boatData.meanQuat(boatFrameIdx - 50, boatFrameIdx + 50);
        refFrameBoat = boatFrameIdx;
        println("Boat ref captured at frame " + refFrameBoat
                + " (w=" + nf(qRefBoat[0],0,4) + " x=" + nf(qRefBoat[1],0,4)
                + " y=" + nf(qRefBoat[2],0,4) + " z=" + nf(qRefBoat[3],0,4) + ")");
        triggerRefFlash("KAYAK REF CAPTURED  (frame " + refFrameBoat + ")");
    }
    else if (key == 'u') {
        qRefBoat = new float[]{ 1, 0, 0, 0 };
        refFrameBoat = -1;
        println("Boat ref cleared.");
        triggerRefFlash("KAYAK REF CLEARED");
    }
}

// ── CSV file picker ──────────────────────────────────────────────────────────
//
// Two prior attempts at filtering the OS dialog to .csv/.CSV only (a
// custom java.awt.FileDialog, first via reflection then a raw background
// Thread, then EventQueue.invokeLater) all failed to actually work when
// the user tried them (20 Jul 2026) — undiagnosable further from here
// since this environment can't run the GUI to observe which part broke.
// Reverted to Processing's own selectInput(), proven reliable for this
// sketch's entire history; the requested ".csv only" behaviour is instead
// enforced by rejecting a non-.csv selection inside onPaddleFileSelected/
// onBoatFileSelected (with an on-screen message) rather than filtering
// what the OS dialog lists.
void selectCsvInput(String prompt, boolean isPaddle) {
    selectInput(prompt, isPaddle ? "onPaddleFileSelected" : "onBoatFileSelected",
                recordingsStartFile());
}

// Start the load dialogs in visualisation/recordings (the session-CSV
// folder) instead of the sketch directory. Processing's FileDialog path
// uses defaultSelection.getParent() as the opening directory, so we hand it
// a placeholder child of the recordings folder — its parent is the folder we
// want open. The placeholder name has no .csv extension, so if the dialog is
// dismissed with it still selected, isCsv() rejects it with the normal
// on-screen message rather than trying to load a non-existent file. Returns
// null (→ Processing's default sketch-folder behaviour) if the folder is
// missing, so a fresh checkout without recordings/ still works.
File recordingsStartFile() {
    try {
        File dir = new File(sketchPath("../recordings")).getCanonicalFile();
        if (dir.isDirectory()) return new File(dir, "select a recording");
    } catch (Exception e) { }
    return null;
}

boolean isCsv(File f) {
    return f.getName().toLowerCase().endsWith(".csv");
}

// ── Saved-session one-step load (v0.17) ──────────────────────────────────────
//
// If visualisation/recordings/ holds any *.session.json, the wizard offers a
// "J = load a saved session" shortcut that picks one JSON and loads all three
// files (paddle CSV, boat CSV, and the sidecar calibration + classification)
// in a single step, with no further wizard input. The JSON records the CSV
// filenames (paddle_csv / boat_csv) as bare names next to it.

File[] listSessionJsons() {
    try {
        File dir = new File(sketchPath("../recordings")).getCanonicalFile();
        if (dir.isDirectory()) {
            File[] all = dir.listFiles();
            if (all != null) {
                ArrayList<File> out = new ArrayList<File>();
                for (File f : all)
                    if (f.isFile() && f.getName().toLowerCase().endsWith(".session.json")) out.add(f);
                return out.toArray(new File[0]);
            }
        }
    } catch (Exception e) { }
    return new File[0];
}

boolean hasSessionJson() { return listSessionJsons().length > 0; }

void selectSessionInput() {
    selectInput("Select a saved session (.session.json)", "onSessionJsonSelected",
                recordingsStartFile());
}

void onSessionJsonSelected(File selection) {
    if (selection == null) return;
    if (!selection.getName().toLowerCase().endsWith(".json")) {
        triggerErrorFlash("SESSION — please choose a .session.json file");
        return;
    }
    Sidecar probe = new Sidecar();
    if (!probe.loadFromFile(selection.getAbsolutePath())) {
        triggerErrorFlash("SESSION — could not read " + selection.getName());
        return;
    }
    if (probe.paddleCsvName == null || probe.paddleCsvName.length() == 0) {
        triggerErrorFlash("SESSION — the JSON names no paddle CSV (paddle_csv)");
        return;
    }
    File dir     = selection.getParentFile();
    File padFile = new File(dir, probe.paddleCsvName);
    if (!padFile.exists()) {
        triggerErrorFlash("SESSION — paddle CSV not found beside JSON: " + probe.paddleCsvName);
        return;
    }
    // Load paddle (this also auto-loads the sibling sidecar), then boat.
    onPaddleFileSelected(padFile);
    if (probe.boatCsvName != null && probe.boatCsvName.length() > 0) {
        File boatFile = new File(dir, probe.boatCsvName);
        if (boatFile.exists()) onBoatFileSelected(boatFile);
        else triggerRefFlash("SESSION — boat CSV missing (" + probe.boatCsvName + "); loaded paddle only");
    }
    // Ensure the PICKED session's calibration + classification are what's
    // applied, regardless of sibling-file naming, then jump to the ready view.
    sidecar = probe;
    applySidecarToDisplay();
    rebuildCatchEvents();
    rebuildClassificationIndex();
    if (classify != null) paddleFrameIdx = classify.nearestVisible(0);
    if (wizard != null) wizard.gotoStep5();
    triggerRefFlash("SESSION LOADED  ←  " + selection.getName());
}

// ── File-select callbacks ────────────────────────────────────────────────────

void onPaddleFileSelected(File selection) {
    if (selection == null) return;
    if (!isCsv(selection)) {
        triggerErrorFlash("PADDLE CSV — please choose a .csv file");
        return;
    }
    // Step 1 name check (spec §14): PadLog files start "pad".
    if (!selection.getName().toLowerCase().startsWith("pad")) {
        triggerErrorFlash("PADDLE CSV — expected a PadLog file (name starts \"pad\")");
        return;
    }
    paddleData = new DataSource();
    paddleData.loadCSV(selection.getAbsolutePath());
    paddleFrameIdx = 0;
    playing        = false;
    rebuildSync();
    tryAutoLoadSidecar(paddleData.sourcePath());
    applySidecarToDisplay();
    rebuildCatchEvents();
    rebuildClassificationIndex();
    if (eePanel != null) eePanel.clear(0);   // fresh CSV — new frame numbering
    if (avgPanel != null) avgPanel.reset(0);
    if (paddleData.frameCount() > 0) {
        // If a boat CSV is already loaded, go straight into combined view.
        switchSlice((boatData != null && boatData.frameCount() > 0) ? 3 : 1);
    }
    if (wizard != null) wizard.onPaddleLoaded();
}

void onBoatFileSelected(File selection) {
    if (selection == null) return;
    if (!isCsv(selection)) {
        triggerErrorFlash("BOAT CSV — please choose a .csv file");
        return;
    }
    // Step 2 name check (spec §14): BoatLog files start "boat".
    if (!selection.getName().toLowerCase().startsWith("boat")) {
        triggerErrorFlash("BOAT CSV — expected a BoatLog file (name starts \"boat\")");
        return;
    }
    boatData = new BoatSource();
    boatData.loadCSV(selection.getAbsolutePath());
    boatFrameIdx = 0;
    playing      = false;
    rebuildSync();
    // A sidecar loaded earlier from the paddle CSV can now finish applying
    // its boat rest quaternion, since we've just gained boat data.
    applySidecarToDisplay();
    rebuildCatchEvents();
    if (boatData.frameCount() > 0) {
        switchSlice((paddleData != null && paddleData.frameCount() > 0) ? 3 : 2);
    }
    if (wizard != null) wizard.onBoatLoaded();
}

// v0.14 — recompute blade entry/exit events whenever the inputs change
// (paddle CSV, boat CSV, or sidecar — the sidecar sets the yaw datum).
void rebuildCatchEvents() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        catchEvents = null;
        return;
    }
    catchEvents = new CatchEvents();
    catchEvents.compute(paddleData, boatData, sync, sidecar);
}

void rebuildSync() {
    if (paddleData == null || boatData == null) return;
    if (paddleData.frameCount() == 0 || boatData.frameCount() == 0) return;
    sync.build(paddleData, boatData);
}

// v0.16 — rebuild the classification exclusion/visibility index whenever the
// paddle CSV or sidecar.classification changes (spec §14). Safe to call with
// no data (empty index) or no sidecar (no exclusions).
void rebuildClassificationIndex() {
    if (classify == null) return;
    int n = (paddleData != null) ? paddleData.frameCount() : 0;
    ArrayList<ClassificationSection> secs =
        (sidecar != null) ? sidecar.classification : null;
    classify.rebuild(n, secs);
}

// ── Sidecar auto-load ──────────────────────────────────────────────────────
//
// After a paddle CSV loads, look for a sibling `.session.json`. If present,
// parse it into `sidecar` and re-derive the rest-window mean quats from the
// just-loaded CSV so qRefPad / qRefBoat can be seeded (those quats aren't
// stored in the JSON — only the frame indices are).

void tryAutoLoadSidecar(String paddleCsvPath) {
    if (paddleCsvPath == null || paddleCsvPath.length() == 0) return;
    String candidate = deriveSidecarPath(paddleCsvPath);
    java.io.File f   = new java.io.File(candidate);
    if (!f.exists() || !f.isFile()) return;

    Sidecar loaded = new Sidecar();
    if (!loaded.loadFromFile(candidate)) return;
    sidecar = loaded;

    int cut     = max(candidate.lastIndexOf('\\'), candidate.lastIndexOf('/'));
    String leaf = (cut >= 0) ? candidate.substring(cut + 1) : candidate;
    println("Sidecar auto-loaded from " + candidate
            + "  (confidence " + loaded.confidence + ")");
    triggerRefFlash("SIDECAR AUTO-LOADED (" + loaded.confidence + ")  ←  " + leaf);
}

// Recompute rest-window mean quats from the loaded CSVs and seed
// qRefPad / qRefBoat so the display shows the sidecar's correction. Safe to
// call whenever CSV state changes; no-ops when the required data is absent.
void applySidecarToDisplay() {
    if (sidecar == null || !sidecar.valid) return;

    if (paddleData != null && paddleData.frameCount() > 0
        && sidecar.restPadStart >= 0 && sidecar.restPadEnd > sidecar.restPadStart) {
        sidecar.qRestPad = paddleData.meanQuat(sidecar.restPadStart, sidecar.restPadEnd);
        qRefPad     = sidecar.qRestPad;
        refFramePad = (sidecar.restPadStart + sidecar.restPadEnd) / 2;
        qRefPadGrv  = paddleData.hasGrv
                      ? paddleData.meanQuatGrv(sidecar.restPadStart, sidecar.restPadEnd)
                      : new float[]{ 1, 0, 0, 0 };
    }

    if (boatData != null && boatData.frameCount() > 0
        && sidecar.restBoatStart >= 0 && sidecar.restBoatEnd > sidecar.restBoatStart) {
        sidecar.qRestBoat = boatData.meanQuat(sidecar.restBoatStart, sidecar.restBoatEnd);
        qRefBoat     = sidecar.qRestBoat;
        refFrameBoat = (sidecar.restBoatStart + sidecar.restBoatEnd) / 2;
        qRefBoatGrv  = boatData.hasGrv
                       ? boatData.meanQuatGrv(sidecar.restBoatStart, sidecar.restBoatEnd)
                       : new float[]{ 1, 0, 0, 0 };
    }
}

// ── Slice / HUD helpers ─────────────────────────────────────────────────────

// Change slice, remembering the previous mode so Backspace / '-' can go back.
void switchSlice(int newMode) {
    if (newMode == sliceMode) return;
    prevSliceMode = sliceMode;
    sliceMode     = newMode;
}

void triggerRefFlash(String msg) {
    refFlashMsg     = msg;
    refFlashUntilMs = millis() + 1500;
    refFlashIsError = false;
}

// Warning/error flash — same top-centre spot, but doesn't auto-fade.
// Stays until the user clicks it (dismissClicked(), wired into
// mousePressed()). Notes 20 Jul 2026: the 1.5 s auto-fade was too short
// to reliably read an error before it vanished.
void triggerErrorFlash(String msg) {
    // While the session-setup wizard is on screen, errors surface in its
    // docked panel (Step 0 of the instructions, spec §14). Otherwise fall
    // back to the top-centre click-to-dismiss flash used everywhere else.
    if (wizard != null && wizard.active()) {
        wizard.setError(msg);
        return;
    }
    refFlashMsg     = msg;
    refFlashIsError = true;
}

void drawRefFlash() {
    int now = millis();
    if (!refFlashIsError && now >= refFlashUntilMs) return;

    int alpha = 240;
    if (!refFlashIsError) {
        // Fade linearly over the last 400 ms of the flash; full opacity before.
        int remaining = refFlashUntilMs - now;
        alpha = (remaining >= 400) ? 240 : (int)(240 * remaining / 400.0);
    }

    textSize(20);
    String shown = refFlashIsError ? (refFlashMsg + "   [click to dismiss]") : refFlashMsg;
    float  boxW  = textWidth(shown) + 32;
    flashBoxL = width / 2 - boxW / 2;
    flashBoxR = width / 2 + boxW / 2;
    flashBoxT = 10;
    flashBoxB = 50;

    noStroke();
    fill(refFlashIsError ? color(70, 25, 25) : color(20, 20, 30), alpha);
    rectMode(CENTER);
    rect(width / 2, 30, boxW, 40, 6);
    rectMode(CORNER);
    fill(refFlashIsError ? color(255, 160, 160) : color(120, 230, 200), alpha);
    textAlign(CENTER, CENTER);
    text(shown, width / 2, 30);
    textAlign(LEFT, TOP);
}

// Absolute window coords. Returns true (and dismisses) if an error flash
// is showing and the click landed inside its box.
boolean dismissFlashClicked(int mx, int my) {
    if (!refFlashIsError) return false;
    if (mx < flashBoxL || mx > flashBoxR || my < flashBoxT || my > flashBoxB) return false;
    refFlashIsError = false;
    refFlashUntilMs = 0;
    return true;
}

// ── Quaternion helpers (Hamilton, [w, x, y, z]) ─────────────────────────────

float[] qMul(float[] a, float[] b) {
    return new float[] {
        a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3],
        a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2],
        a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1],
        a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0]
    };
}

float[] qConj(float[] q) {
    return new float[] { q[0], -q[1], -q[2], -q[3] };
}

// Wrap a degree value to (-180, 180].
float wrapDeg180(float d) {
    while (d >  180) d -= 360;
    while (d < -180) d += 360;
    return d;
}

// ── Graph panel → sketch bridging ────────────────────────────────────────────
//
// GraphPanel calls these to seek/pause when the user drags the cursor.

void setFrameIdx(int idx) {
    if (paddleData == null || paddleData.frameCount() == 0) return;
    idx = constrain(idx, 0, paddleData.frameCount() - 1);
    // Never land inside an excluded classification range (spec §14).
    paddleFrameIdx = (classify != null) ? classify.nearestVisible(idx) : idx;
}

void setPlaying(boolean p) {
    playing       = p;
    lastAdvanceMs = millis();
}

// ── Mouse routing ──────────────────────────────────────────────────────────
//
// Split by region: graph strip along the bottom belongs to GraphPanel;
// everything above it is the 3D scene, where left-drag orbits the camera and
// the mouse wheel zooms.

boolean pointerInGraph() {
    return isGraphVisible() && mouseY >= (height - GRAPH_H);
}

void mousePressed() {
    // Overlay priority (v0.14/v0.15): error-flash dismiss (draws on top of
    // everything else), menu button/drop-down, detail-panel toggle, then
    // the startup overlay, then the graph strip, then the side panels
    // (each only reacts to right-click inside its own bounds), then 3D
    // orbit.
    if (dismissFlashClicked(mouseX, mouseY)) return;
    if (menu != null && menu.mousePressed(mouseX, mouseY)) return;
    if (detailPanel != null && detailPanel.mousePressed(mouseX, mouseY)) return;
    if (wizard != null && wizard.mousePressed(mouseX, mouseY)) return;
    if (pointerInGraph()) {
        int localY = mouseY - (height - GRAPH_H);
        graph.mousePressed(mouseX, localY, paddleData, mouseButton);
        return;
    }
    if (mouseX < leftPanelWidth() && mouseY < height - GRAPH_H) {
        // Right-click in the entry/exit panel clears accumulated dots
        // (notes 20 Jul 2026) — everything before the current playback
        // frame is hidden until the panel is cleared again.
        if (mouseButton == RIGHT && eePanel != null) {
            eePanel.clear(paddleFrameIdx);
            triggerRefFlash("ENTRY/EXIT VIEW CLEARED");
        }
        return;
    }
    if (mouseX >= width - rightPanelWidth() && mouseY < height - GRAPH_H) {
        // Right-click in the stroke-average panel restarts its own
        // accumulation — independent of the entry/exit panel's reset
        // (notes 20 Jul 2026).
        if (mouseButton == RIGHT && avgPanel != null) {
            avgPanel.reset(paddleFrameIdx);
            triggerRefFlash("STROKE AVERAGE RESTARTED");
        }
        return;
    }
    // 3D scene — left-drag orbits.
    if (mouseButton == LEFT) {
        dragMouseX  = mouseX;
        dragMouseY  = mouseY;
        dragStartAz = camAzimDeg;
        dragStartEl = camElevDeg;
        camDragging = true;
    }
}

void mouseDragged() {
    if (menu != null && menu.mouseDragged(mouseX, mouseY)) return;
    if (camDragging) {
        camAzimDeg = dragStartAz + (mouseX - dragMouseX) * 0.4;
        camElevDeg = constrain(dragStartEl - (mouseY - dragMouseY) * 0.4, -89, 89);
        return;
    }
    if (isGraphVisible()) graph.mouseDragged(mouseX, paddleData);
}

void mouseReleased() {
    if (menu != null && menu.mouseReleased()) return;
    if (camDragging) { camDragging = false; return; }
    if (isGraphVisible()) graph.mouseReleased();
}

void mouseWheel(processing.event.MouseEvent e) {
    if (menu != null && menu.mouseWheel(e.getCount())) return;
    if (pointerInGraph()) {
        graph.mouseWheel(e.getCount());
        return;
    }
    // 3D scene — zoom. Positive count = wheel down = zoom out.
    camDist = constrain(camDist * pow(1.12, e.getCount()), 200, 5000);
}

// ── Export callback (top-level so selectOutput can invoke it) ───────────────

void exportFileSelected(File out) {
    if (out == null || graph == null) return;
    graph.exportMerged(out.getAbsolutePath(), paddleData, boatData, sync);
}

// ── Sidecar build + save ────────────────────────────────────────────────────
//
// C key: run the rest-window detector on the currently loaded paddle CSV,
// compute mount offsets from mean roll/pitch and (if a synced boat CSV is
// available) yaw datum from paddle-vs-boat mean yaw, then save the result
// automatically to `<paddle-basename>.session.json` next to the paddle CSV.
// No dialog — spec §7.5 fixes the path. Also seeds qRefPad / qRefBoat with
// the rest-window means so the visual correction shows immediately; the
// archived JSON keeps the decomposed values for post-processing.

boolean buildAndSaveSidecar() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        triggerErrorFlash("SIDECAR — LOAD PADDLE CSV FIRST");
        return false;
    }
    int searchStart = paddleFrameIdx;
    Sidecar built = buildSidecar(paddleData, boatData, sync, searchStart);
    sidecar = built;

    println("Sidecar build result:");
    println("  search start:    frame " + searchStart);
    println("  confidence:      " + built.confidence);
    println("  notes:           " + built.notes);
    if (built.valid) {
        println("  rest window:     pad " + built.restPadStart + "-" + built.restPadEnd
                + " (" + nf(built.restDurationS, 0, 1) + " s)"
                + "   boat " + built.restBoatStart + "-" + built.restBoatEnd);
        println("  paddle mount:    roll=" + nf(built.rollOffsetPadDeg, 0, 2)
                + "°  pitch=" + nf(built.pitchOffsetPadDeg, 0, 2) + "°");
        println("  boat   mount:    roll=" + nf(built.rollOffsetBoatDeg, 0, 2)
                + "°  pitch=" + nf(built.pitchOffsetBoatDeg, 0, 2) + "°");
        println("  yaw datum:       " + nf(built.yawDatumDeg, 0, 2) + "°");
        println("  accel var max:   " + nf(built.restAccelVarMax, 0, 4));
    }

    if (!built.valid) {
        triggerErrorFlash("SIDECAR — " + built.notes);
        return false;
    }

    // Seed rest references so the visual correction shows immediately.
    if (built.qRestPad != null) {
        qRefPad     = built.qRestPad;
        refFramePad = (built.restPadStart + built.restPadEnd) / 2;
        qRefPadGrv  = paddleData.hasGrv
                      ? paddleData.meanQuatGrv(built.restPadStart, built.restPadEnd)
                      : new float[]{ 1, 0, 0, 0 };
    }
    if (built.qRestBoat != null) {
        qRefBoat     = built.qRestBoat;
        refFrameBoat = (built.restBoatStart + built.restBoatEnd) / 2;
        qRefBoatGrv  = boatData.hasGrv
                       ? boatData.meanQuatGrv(built.restBoatStart, built.restBoatEnd)
                       : new float[]{ 1, 0, 0, 0 };
    }

    // Sidecar changed — the entry/exit yaw datum depends on it. Fresh C run
    // also resets any manual yaw-datum nudge (built is a brand-new Sidecar)
    // and any panel clear marker, since this is effectively a new calibration.
    // A fresh sidecar has no classification sections, so the exclusion index
    // resets to "nothing excluded" (spec §14).
    rebuildCatchEvents();
    rebuildClassificationIndex();
    if (eePanel != null) eePanel.clear(0);
    if (avgPanel != null) avgPanel.reset(0);

    // Auto-save to <paddle-basename>.session.json in the paddle CSV's folder.
    String savePath = deriveSidecarPath(paddleData.sourcePath());
    try {
        sidecar.save(savePath);
        println("Sidecar saved to " + savePath);
        // Trim to filename for the on-screen flash.
        int cut = max(savePath.lastIndexOf('\\'), savePath.lastIndexOf('/'));
        String leaf = (cut >= 0) ? savePath.substring(cut + 1) : savePath;
        triggerRefFlash("SIDECAR BUILT + SAVED  (" + built.confidence + ")  →  " + leaf);
    } catch (Exception e) {
        println("Sidecar save FAILED: " + e.getMessage() + "   path=" + savePath);
        triggerErrorFlash("SIDECAR BUILT but save failed — see console");
    }
    return true;
}

// ── Entry/exit yaw datum manual override (notes 20 Jul 2026, spec §13.7) ───
//
// CatchEvents computes an automatic yaw datum per compute() call — a rest-
// window circular mean if a sidecar is built, else a whole-file mean (see
// CatchEvents.datumAutoDeg). Field use found this can read tens of degrees
// off on a given session. Until a more reliable automatic method exists,
// n/N in Slice 0 nudge a manual correction on top of the automatic value;
// it is saved into the sidecar (yawManualAdjustDeg) so it persists with
// this data record, and shown alongside the automatic value in
// drawHUD_slice0() so the two are never confused.

void nudgeManualYawDatum(float deltaDeg) {
    if (sidecar == null || !sidecar.valid) {
        triggerErrorFlash("YAW DATUM ADJUST — BUILD SIDECAR WITH C FIRST");
        return;
    }
    sidecar.yawManualAdjustDeg = wrapDeg180(sidecar.yawManualAdjustDeg + deltaDeg);
    rebuildCatchEvents();
    saveSidecarQuiet();
    triggerRefFlash(String.format("YAW DATUM MANUAL = %+.1f°", sidecar.yawManualAdjustDeg));
}

void resetManualYawDatum() {
    if (sidecar == null || !sidecar.valid) return;
    sidecar.yawManualAdjustDeg = 0;
    rebuildCatchEvents();
    saveSidecarQuiet();
    triggerRefFlash("YAW DATUM MANUAL RESET");
}

// Re-saves the current sidecar to its existing path without the console
// chatter buildAndSaveSidecar() prints — used for the frequent small nudges
// above, which would otherwise flood the console.
void saveSidecarQuiet() {
    if (paddleData == null || sidecar == null) return;
    String savePath = deriveSidecarPath(paddleData.sourcePath());
    try {
        sidecar.save(savePath);
    } catch (Exception e) {
        println("Sidecar save FAILED: " + e.getMessage() + "   path=" + savePath);
    }
}

// Given a paddle CSV path, return the sibling `.session.json` path.
// Strips the last extension (case-insensitive) and appends the sidecar suffix.
// Fallback: append `.session.json` verbatim if there's no visible extension.
String deriveSidecarPath(String csvPath) {
    if (csvPath == null || csvPath.length() == 0) return "session.json";
    int slash = max(csvPath.lastIndexOf('\\'), csvPath.lastIndexOf('/'));
    int dot   = csvPath.lastIndexOf('.');
    String base = (dot > slash) ? csvPath.substring(0, dot) : csvPath;
    return base + ".session.json";
}
