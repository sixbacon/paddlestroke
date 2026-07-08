// PadViz6 — Slice 0 (model cal) + Slice A (paddle, data-driven) + Slice B (kayak, data-driven).
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

// Slice / view state
int     sliceMode  = 0;   // 0 = Slice 0 (calibration), 1 = Slice A, 2 = Slice B, 3 = Slice C (combined)
int     viewMode   = 0;   // 0 = side view (X-Z), 1 = top-down (X-Y)

// Per-source frame indices and playback
int     paddleFrameIdx = 0;
int     boatFrameIdx   = 0;
boolean playing        = false;
int     lastAdvanceMs  = 0;

// Reference-pose subtraction — separate for paddle and boat.
// When active, each frame renders q_ref_conj * q_current so that the
// captured frame appears in the Slice 0 identity pose.
float[] qRefPad       = { 1, 0, 0, 0 };
int     refFramePad   = -1;
float[] qRefBoat      = { 1, 0, 0, 0 };
int     refFrameBoat  = -1;

void settings() {
    size(1400, 900, P3D);
    smooth(4);
}

void setup() {
    cal = new Calibration();
    cal.load(sketchPath("data/model_calibration.json"));

    model3D = new Model3D();
    model3D.loadPaddle("paddle60.obj");

    sync = new SyncMap();

    surface.setTitle("PadViz6");
    println("PadViz6 —  0=Slice0 cal   1=SliceA paddle   2=SliceB kayak   3=SliceC combined   V=toggle view");
    println("Load:  O=paddle CSV   B=boat CSV");
    println("Slices A/B/C:  Space=play/pause   Left/Right=step 100   ,/.=step 1   K=capture ref   U=clear ref");
}

void draw() {
    background(20);
    stepPlayback();
    drawScene3D();

    // 2D HUD overlay
    camera();
    hint(DISABLE_DEPTH_TEST);
    drawHUD();
    hint(ENABLE_DEPTH_TEST);
}

// ── 3D scene ──────────────────────────────────────────────────────────────────

void drawScene3D() {
    lights();
    setCamera();

    pushMatrix();
    scale(1, 1, -1);          // handedness bridge: worldRH ← sensorLH

    drawSensorAxes();

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

    float[] qPad  = { fd.qw,  fd.qx,  fd.qy,  fd.qz  };
    float[] qBoat = { bfd.qw, bfd.qx, bfd.qy, bfd.qz };

    // kayakLH ← paddleLH  (paddle rotation expressed in kayak-body frame)
    float[] qRel = qMul(qConj(qBoat), qPad);

    // Reference-subtraction. Applied per-frame only if both refs captured.
    // Kayak: rendered relative to captured kayak rest (as in Slice B).
    // Paddle: rendered relative to captured paddle-vs-kayak rest offset —
    // this collapses the magnetic-yaw datum difference between the two IMUs.
    float[] qBoatDisp = qBoat;
    float[] qRelDisp  = qRel;
    if (refFrameBoat >= 0) {
        qBoatDisp = qMul(qConj(qRefBoat), qBoat);
    }
    if (refFramePad >= 0 && refFrameBoat >= 0) {
        float[] qRelRef = qMul(qConj(qRefBoat), qRefPad);   // kayakLH ← paddleLH at rest
        qRelDisp = qMul(qConj(qRelRef), qRel);
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
    translate(0, 0, PADDLE_LIFT_M * 300);

    // Paddle inside the kayak's local frame — cal triple + relative quat.
    // kayakLH ← paddleLH ← blenderLH
    applyCalTriple();
    model3D.applyQuat(qRelDisp[0], qRelDisp[1], qRelDisp[2], qRelDisp[3]);
    model3D.drawPaddle();
    popMatrix();
}

void setCamera() {
    if (viewMode == 0) {
        // Side view: eye on -Y side, up = +Z (Processing screen-DOWN).
        // Red +X right, blue +Z up, green +Y into the screen.
        camera(0, -1200, 0,   0, 0, 0,   0, 0, 1);
    } else {
        // Top-down view: eye at world -Z (physical up after flip).
        // Red +X right, green +Y up, blue +Z out of the screen.
        camera(0, 0, -1200,   0, 0, 0,   0, -1, 0);
    }
}

void drawSensorAxes() {
    float L = 350;
    strokeWeight(3);
    stroke(255, 60, 60);   line(0, 0, 0, L, 0, 0);   // +X sensor
    stroke(60, 255, 60);   line(0, 0, 0, 0, L, 0);   // +Y sensor
    stroke(60, 100, 255);  line(0, 0, 0, 0, 0, L);   // +Z sensor
    strokeWeight(1);
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
    String viewName = (viewMode == 0) ? "side view (X-Z)" : "top-down (X-Y)";
    text("PadViz6   " + modeName + "   [" + viewName + "]", 20, 16);

    textSize(13);
    if      (sliceMode == 0) drawHUD_slice0();
    else if (sliceMode == 1) drawHUD_sliceA();
    else if (sliceMode == 2) drawHUD_sliceB();
    else                     drawHUD_sliceC();

    // Right-column axis legend — labels change with slice mode.
    drawAxisLegend();

    // Footer
    fill(160);
    textSize(11);
    text("model calibration file:  " + cal.savePath, 20, height - 24);
}

void drawAxisLegend() {
    textSize(13);
    fill(220);
    if (sliceMode == 2 || sliceMode == 3) {
        // Slice B: kayak alone. Slice C: kayak drives world, so world axes = boat frame.
        text("Boat sensor axes at origin", width - 380, 16);
        textSize(12);
        fill(255, 80, 80);   text("+X  starboard",              width - 380, 42);
        fill(80, 255, 80);   text("+Y  bow (forward)",           width - 380, 60);
        fill(100, 140, 255); text("+Z  up (deck)",               width - 380, 78);
    } else {
        text("Paddle sensor axes at origin", width - 380, 16);
        textSize(12);
        fill(255, 80, 80);   text("+X  shaft toward right blade", width - 380, 42);
        fill(80, 255, 80);   text("+Y  blade normal",             width - 380, 60);
        fill(100, 140, 255); text("+Z  in-blade (up in cal pose)",width - 380, 78);
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

    fill(180, 200, 180);
    textSize(12);
    int y = 176;
    text("y/Y P/p R/r  nudge yaw/pitch/roll +/- step", 20, y); y += 16;
    text("[ / ]        step size /2 / x2",             20, y); y += 16;
    text("Z            zero all",                      20, y); y += 16;
    text("S            save data/model_calibration.json", 20, y); y += 16;
    text("L            list current triple to console", 20, y); y += 16;
    text("0/1/2/3      Slice 0 / A paddle / B kayak / C combined", 20, y); y += 16;
    text("V            toggle side / top view",        20, y); y += 16;
    text("O / B        open paddle / boat CSV",        20, y);
}

void drawHUD_sliceA() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No paddle CSV loaded — press O", 20, 56);
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
    drawPlaybackKeys(180);
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

    // GPS block
    fill(200);
    text(String.format("GPS  fix=%s  speed=%.2f m/s  COG=%.1f°  utc=%d",
                       bfd.gpsFix ? "yes" : "no", bfd.speedMs, bfd.cogDeg, bfd.gpsUtcSec), 20, 152);

    drawRefStatus(refFrameBoat, 172);
    drawPlaybackKeys(200);
}

void drawHUD_sliceC() {
    if (paddleData == null || paddleData.frameCount() == 0) {
        fill(255, 180, 100);
        text("No paddle CSV loaded — press O", 20, 56);
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

    drawPlaybackKeys(y + 22);
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

void drawPlaybackKeys(int yStart) {
    fill(180, 200, 180);
    textSize(12);
    int y = yStart;
    text("Space   play / pause",                    20, y); y += 16;
    text("Left/Right   step 100 frames",            20, y); y += 16;
    text(", / .        step 1 frame",               20, y); y += 16;
    text("Home / End   jump to start / end",        20, y); y += 16;
    text("K            capture reference (mean of +-50 frames)", 20, y); y += 16;
    text("U            clear reference (back to raw quat)",      20, y); y += 16;
    text("0/1/2/3      Slice 0 / A / B / C",        20, y); y += 16;
    text("V            toggle side / top view",     20, y);
}

// ── Playback / input ─────────────────────────────────────────────────────────

void stepPlayback() {
    if (!playing) return;
    int now = millis();
    int nAdvance = (now - lastAdvanceMs) / 10;   // 100 Hz
    if (nAdvance <= 0) return;
    lastAdvanceMs += nAdvance * 10;

    if ((sliceMode == 1 || sliceMode == 3)
            && paddleData != null && paddleData.frameCount() > 0) {
        // Slice A + C: paddle frame is the timeline master. In Slice C the
        // matched boat frame is picked up in drawSliceC() via SyncMap.
        int last = paddleData.frameCount() - 1;
        paddleFrameIdx = min(last, paddleFrameIdx + nAdvance);
        if (paddleFrameIdx >= last) playing = false;
    } else if (sliceMode == 2 && boatData != null && boatData.frameCount() > 0) {
        int last = boatData.frameCount() - 1;
        boatFrameIdx = min(last, boatFrameIdx + nAdvance);
        if (boatFrameIdx >= last) playing = false;
    }
}

void keyPressed() {
    // Slice/view/load switches — always active.
    if      (key == '0') { sliceMode = 0; return; }
    else if (key == '1') { sliceMode = 1; return; }
    else if (key == '2') { sliceMode = 2; return; }
    else if (key == '3') { sliceMode = 3; return; }
    else if (key == 'v' || key == 'V') { viewMode = 1 - viewMode; return; }
    else if (key == 'o' || key == 'O') { selectInput("Select paddle CSV", "onPaddleFileSelected"); return; }
    else if (key == 'b' || key == 'B') { selectInput("Select boat CSV",   "onBoatFileSelected");   return; }

    // Slice-specific keys.
    if (sliceMode == 0) {
        // Slice 0 — calibration key bindings.
        cal.handleKey(key);
        return;
    }

    // Slices A / B / C — playback and reference.
    if (key == ' ') { playing = !playing; lastAdvanceMs = millis(); return; }

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
    if      (key == ',')       paddleFrameIdx = max(0,    paddleFrameIdx - 1);
    else if (key == '.')       paddleFrameIdx = min(last, paddleFrameIdx + 1);
    else if (keyCode == LEFT)  paddleFrameIdx = max(0,    paddleFrameIdx - 100);
    else if (keyCode == RIGHT) paddleFrameIdx = min(last, paddleFrameIdx + 100);
    else if (keyCode == 36)    paddleFrameIdx = 0;
    else if (keyCode == 35)    paddleFrameIdx = last;
    else if (key == 'k' || key == 'K') {
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
        println("Slice C refs captured — pad frame " + refFramePad
                + "  boat frame " + refFrameBoat);
    }
    else if (key == 'u' || key == 'U') {
        qRefPad = new float[]{ 1, 0, 0, 0 };
        qRefBoat = new float[]{ 1, 0, 0, 0 };
        refFramePad = -1;
        refFrameBoat = -1;
        println("Slice C refs cleared.");
    }
}

void handleFrameNavPaddle() {
    int last = paddleData.frameCount() - 1;
    if      (key == ',')       paddleFrameIdx = max(0,    paddleFrameIdx - 1);
    else if (key == '.')       paddleFrameIdx = min(last, paddleFrameIdx + 1);
    else if (keyCode == LEFT)  paddleFrameIdx = max(0,    paddleFrameIdx - 100);
    else if (keyCode == RIGHT) paddleFrameIdx = min(last, paddleFrameIdx + 100);
    else if (keyCode == 36)    paddleFrameIdx = 0;
    else if (keyCode == 35)    paddleFrameIdx = last;
    else if (key == 'k' || key == 'K') {
        qRefPad     = paddleData.meanQuat(paddleFrameIdx - 50, paddleFrameIdx + 50);
        refFramePad = paddleFrameIdx;
        println("Paddle ref captured at frame " + refFramePad
                + " (w=" + nf(qRefPad[0],0,4) + " x=" + nf(qRefPad[1],0,4)
                + " y=" + nf(qRefPad[2],0,4) + " z=" + nf(qRefPad[3],0,4) + ")");
    }
    else if (key == 'u' || key == 'U') {
        qRefPad = new float[]{ 1, 0, 0, 0 };
        refFramePad = -1;
        println("Paddle ref cleared.");
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
    else if (key == 'k' || key == 'K') {
        qRefBoat     = boatData.meanQuat(boatFrameIdx - 50, boatFrameIdx + 50);
        refFrameBoat = boatFrameIdx;
        println("Boat ref captured at frame " + refFrameBoat
                + " (w=" + nf(qRefBoat[0],0,4) + " x=" + nf(qRefBoat[1],0,4)
                + " y=" + nf(qRefBoat[2],0,4) + " z=" + nf(qRefBoat[3],0,4) + ")");
    }
    else if (key == 'u' || key == 'U') {
        qRefBoat = new float[]{ 1, 0, 0, 0 };
        refFrameBoat = -1;
        println("Boat ref cleared.");
    }
}

// ── File-select callbacks ────────────────────────────────────────────────────

void onPaddleFileSelected(File selection) {
    if (selection == null) return;
    paddleData = new DataSource();
    paddleData.loadCSV(selection.getAbsolutePath());
    paddleFrameIdx = 0;
    playing        = false;
    rebuildSync();
    if (paddleData.frameCount() > 0) {
        // If a boat CSV is already loaded, go straight into combined view.
        sliceMode = (boatData != null && boatData.frameCount() > 0) ? 3 : 1;
    }
}

void onBoatFileSelected(File selection) {
    if (selection == null) return;
    boatData = new BoatSource();
    boatData.loadCSV(selection.getAbsolutePath());
    boatFrameIdx = 0;
    playing      = false;
    rebuildSync();
    if (boatData.frameCount() > 0) {
        sliceMode = (paddleData != null && paddleData.frameCount() > 0) ? 3 : 2;
    }
}

void rebuildSync() {
    if (paddleData == null || boatData == null) return;
    if (paddleData.frameCount() == 0 || boatData.frameCount() == 0) return;
    sync.build(paddleData, boatData);
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
