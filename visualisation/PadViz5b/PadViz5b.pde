// PadViz5b — Paddle + boat visualiser (built on PadViz4 quaternion path)
// Processing 4.x
// Coordinate system: X right, Y into screen, Z up
//
// Keys:
//   Space        — play / pause
//   Left/Right   — step one frame
//   Home/End     — jump to start / end
//   O            — open paddle ImuLog CSV
//   B            — open BoatLog CSV
//   E            — export current zoom range to merged CSV
//   L            — connect / disconnect live serial (paddle only)
//   R            — reset camera to default
//   1/2/3        — isolate roll / pitch / yaw only (test modes)
//   0            — normal mode (all axes)
//   -  =         — nudge correction rotation -/+ 5° about current tune axis
//   A            — cycle tune axis (X → Y → Z) for correction nudge
//   K            — toggle kayak (deck) camera view
//   P            — toggle paddle position tracking (requires 15-col CSV with accel)

import processing.serial.*;

// ── Layout ────────────────────────────────────────────────────────────────────
static final int VIEW_W  = 900;
static final int PANEL_W = 500;
static final int TOTAL_W = VIEW_W + PANEL_W;    // 1400
static final int TOP_H   = 700;                 // 3D view + side panel
static final int GRAPH_H = 300;                 // bottom graph strip
static final int TOTAL_H = TOP_H + GRAPH_H;     // 1000

// ── Playback ──────────────────────────────────────────────────────────────────
static final float SPEED_STEP = -1.0f;
static final float SPEED_MAX  =  4.0f;

float   playSpeed = 1.0f;
boolean playing   = true;
int     frameIdx  = 0;
float   frameFrac = 0;

// ── Mode ──────────────────────────────────────────────────────────────────────
boolean liveMode = false;
int     testMode = 0;   // 0=all, 1=roll only, 2=pitch only, 3=yaw only

// ── Paddle correction (interactive tuning via - = keys) ──────────────────────
// Body-frame PRE-rotation applied to the OBJ before the IMU quaternion, i.e.
// q_render = qImu ⊗ qCorr. This is the correct frame for a fixed sensor-mount
// offset — the rotation stays with the sensor as the paddle moves.
//
// Default corrZ = 180°: field observation is that with all corr = 0 the two
// paddle blades appear swapped left↔right AND the stroke motion is time-
// reversed. Both symptoms are consistent with the sensor being mounted 180°
// rotated about the paddle's vertical (Z_paddle) axis, so sensor +X points to
// the left blade instead of the right. Rz(180°) as a body-frame pre-rotation
// undoes that. Nudge X/Y with A → -/= for any residual roll/pitch bias.
float corrX = 0, corrY = 0, corrZ = 180;
int   tuneAxis = 0;   // start on X for fine roll-bias trimming after Rz(180)
static final float NUDGE = 5.0f;

// ── Yaw averaging (kayak heading + deck camera) ───────────────────────────────
static final float YAW_EMA_ALPHA = 0.002f;
float yawEmaSin = 0.0f, yawEmaCos = 1.0f;
float avgYaw    = 0.0f;

// ── Position tracking ─────────────────────────────────────────────────────────
// Off by default — integrator drift lets the paddle wander off screen.
// Turn on with P once you're actively investigating the accel path.
boolean posMode = false;

// ── Objects ───────────────────────────────────────────────────────────────────
DataSource ds;
BoatSource dsBoat;
SyncMap    sync;
Model3D    m3d;
SidePanel  panel;
GraphPanel graph;
Integrator integ;

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    size(1400, 1000, P2D);
    surface.setTitle("PadViz5b");
    textFont(createFont("SansSerif", 13));

    ds     = new DataSource();
    dsBoat = new BoatSource();
    sync   = new SyncMap();
    m3d    = new Model3D(this);
    panel  = new SidePanel(VIEW_W, TOP_H, PANEL_W);
    graph  = new GraphPanel(0, TOP_H, TOTAL_W, GRAPH_H);
    integ  = new Integrator();
    integ.reset();

    java.io.File sample = new java.io.File(sketchPath("ImuLog0420260521.CSV"));
    if (sample.exists()) ds.loadCSV(sample.getAbsolutePath());
    sync.build(ds, dsBoat);
}

// ── Draw ──────────────────────────────────────────────────────────────────────
void draw() {
    background(30);

    if (!liveMode) advanceCSV();
    else           ds.drainSerial();

    FrameData     fd  = liveMode ? ds.liveLatest() : ds.frameAt(frameIdx);
    BoatFrameData bfd = liveMode ? null            : sync.boatFrameFor(frameIdx);
    FrameData     td  = applyTestMode(fd);

    float yr = radians(fd.yaw);
    yawEmaSin += YAW_EMA_ALPHA * (sin(yr) - yawEmaSin);
    yawEmaCos += YAW_EMA_ALPHA * (cos(yr) - yawEmaCos);
    avgYaw = degrees(atan2(yawEmaSin, yawEmaCos));

    if (posMode) integ.update(td);

    m3d.draw(td, bfd, corrX, corrY, corrZ, avgYaw,
             posMode ? integ.posX : 0,
             0,        // Z translation deferred
             posMode);
    image(m3d.canvas, 0, 0);

    panel.draw(ds, dsBoat, frameIdx, fd, playSpeed, playing);

    graph.draw(ds, dsBoat, sync, frameIdx);

    drawHudOverlay(td, bfd);
    if (liveMode) drawSerialDebug(fd);
}

// ── CSV advance ───────────────────────────────────────────────────────────────
void advanceCSV() {
    if (ds.frameCount() == 0 || !playing || playSpeed == SPEED_STEP) return;
    frameFrac += playSpeed;
    int steps  = (int) frameFrac;
    frameFrac -= steps;
    frameIdx = min(frameIdx + steps, ds.frameCount() - 1);
    if (frameIdx >= ds.frameCount() - 1) {
        playing = false;  frameIdx = ds.frameCount() - 1;
    }
}

// ── Test mode (isolate one rotation axis) ─────────────────────────────────────
FrameData applyTestMode(FrameData src) {
    if (testMode == 0) return src;
    FrameData fd = new FrameData();
    fd.ts          = src.ts;
    fd.strokeCount = src.strokeCount;
    fd.cpm         = src.cpm;
    fd.hasQuat     = src.hasQuat;
    fd.accelX      = src.accelX;
    fd.accelY      = src.accelY;
    fd.accelZ      = src.accelZ;
    fd.roll  = (testMode == 1) ? src.roll  : 0;
    fd.pitch = (testMode == 2) ? src.pitch : 0;
    fd.yaw   = (testMode == 3) ? src.yaw   : 0;
    fd.recomputeQuat();
    return fd;
}

// ── HUD overlay ───────────────────────────────────────────────────────────────
void drawHudOverlay(FrameData fd, BoatFrameData bfd) {
    noStroke();
    fill(255, 255, 255, 200);
    textSize(13);  textAlign(LEFT, TOP);
    int x = 12, y = 12, dy = 17;
    text("t     " + nf(fd.ts / 1000.0f, 0, 1) + " s", x, y);  y += dy;
    text("roll  " + nf(fd.roll,  0, 1) + "°",           x, y);  y += dy;
    text("pitch " + nf(fd.pitch, 0, 1) + "°",           x, y);  y += dy;
    text("yaw   " + nf(fd.yaw,   0, 1) + "°",           x, y);  y += dy;
    text("CPM   " + nf(fd.cpm,   0, 1),                 x, y);  y += dy;
    text("sc    " + fd.strokeCount,                      x, y);  y += dy;

    if (bfd != null) {
        y += 4;
        fill(100, 200, 255, 200);
        text("kYaw   " + nf(bfd.kayakYaw,   0, 1) + "°", x, y);  y += dy;
        text("kRoll  " + nf(bfd.kayakRoll,  0, 1) + "°", x, y);  y += dy;
        text("kPitch " + nf(bfd.kayakPitch, 0, 1) + "°", x, y);  y += dy;
        text("speed  " + nf(bfd.speedMs * 1.94384f, 0, 2) + " kn", x, y);  y += dy;
        fill(255, 255, 255, 200);
    }

    if (posMode) {
        y += 4;
        fill(140, 255, 140, 200);
        text("posX  " + nf(integ.posX, 0, 3) + " m"
             + (integ.usingFallback ? "  (roll est.)" : "  (accel)"), x, y);  y += dy;
        text("velX  " + nf(integ.velX, 0, 3) + " m/s", x, y);  y += dy;
    }

    y += 6;
    fill(255, 200, 80, 200);
    String axName = new String[]{"X","Y","Z"}[tuneAxis];
    text("corr  Rx=" + nf(corrX,0,1) + "  Ry=" + nf(corrY,0,1) + "  Rz=" + nf(corrZ,0,1)
         + "   tune:" + axName + " (A to cycle, -/= to nudge)", x, y);
    y += dy;
    fill(m3d.deckCam ? color(100, 220, 100, 200) : color(160, 160, 160, 200));
    text("cam   " + (m3d.deckCam ? "KAYAK" : "WORLD") + "  (K to toggle)", x, y);
    y += dy;
    fill(posMode ? color(140, 255, 140, 200) : color(160, 160, 160, 200));
    text("pos X " + (posMode ? "ON" : "OFF") + "  (P to toggle)", x, y);

    if (testMode > 0) {
        y += dy + 4;
        fill(255, 120, 120, 220);
        String[] names = {"","ROLL ONLY","PITCH ONLY","YAW ONLY"};
        text("TEST: " + names[testMode], x, y);
    }
}

// ── Serial debug ──────────────────────────────────────────────────────────────
void drawSerialDebug(FrameData lv) {
    int bx = 10, by = TOP_H - 60, bw = VIEW_W - 20, bh = 54;
    fill(0, 0, 0, 180);  noStroke();
    rect(bx, by, bw, bh, 4);
    textSize(11);  textAlign(LEFT, TOP);
    int y = by + 6;
    fill(ds.liveFrameTotal > 0 ? color(100, 255, 100) : color(255, 180, 50));
    text("LIVE  frames=" + ds.liveFrameTotal + "  errors=" + ds.liveParseErrors, bx + 6, y);
    y += 16;
    fill(200);
    String raw = ds.lastRawLine;
    if (raw.length() > 100) raw = raw.substring(0, 100) + "...";
    text("last: " + raw, bx + 6, y);
    y += 16;
    fill(180, 220, 255);
    text(String.format("roll=%.1f  pitch=%.1f  yaw=%.1f  cpm=%.1f",
         lv.roll, lv.pitch, lv.yaw, lv.cpm), bx + 6, y);
}

// ── Keyboard ──────────────────────────────────────────────────────────────────
void keyPressed() {
    if (key == ' ')  { playing = !playing; return; }
    if (key == '0')  { testMode = 0; surface.setTitle("PadViz5b"); return; }
    if (key == '1')  { testMode = 1; surface.setTitle("PadViz5b — TEST: roll only"); return; }
    if (key == '2')  { testMode = 2; surface.setTitle("PadViz5b — TEST: pitch only"); return; }
    if (key == '3')  { testMode = 3; surface.setTitle("PadViz5b — TEST: yaw only"); return; }
    if (key == 'r' || key == 'R') { m3d.resetCamera(); return; }
    if (key == 'o' || key == 'O') { selectInput("Select paddle ImuLog CSV", "fileSelected"); return; }
    if (key == 'b' || key == 'B') { selectInput("Select BoatLog CSV",       "boatFileSelected"); return; }
    if (key == 'e' || key == 'E') { selectOutput("Export merged CSV",       "exportFileSelected"); return; }
    if (key == 'l' || key == 'L') { toggleLive(); return; }
    if (key == 'a' || key == 'A') { tuneAxis = (tuneAxis + 1) % 3; return; }
    if (key == 'k' || key == 'K') { m3d.deckCam = !m3d.deckCam; return; }
    if (key == 'p' || key == 'P') {
        posMode = !posMode;
        if (posMode) integ.reset();
        return;
    }
    if (key == '-' || key == '_') { nudgeCorr(-NUDGE); return; }
    if (key == '=' || key == '+') { nudgeCorr(+NUDGE); return; }
    if (keyCode == RIGHT) { frameIdx = min(frameIdx + 1, max(0, ds.frameCount()-1)); playing = false; }
    if (keyCode == LEFT)  { frameIdx = max(frameIdx - 1, 0); playing = false; }
    if (keyCode == 36)    { frameIdx = 0; }
    if (keyCode == 35 && ds.frameCount() > 0) frameIdx = ds.frameCount() - 1;
}

void nudgeCorr(float delta) {
    if (tuneAxis == 0) corrX += delta;
    else if (tuneAxis == 1) corrY += delta;
    else corrZ += delta;
}

// ── Mouse ─────────────────────────────────────────────────────────────────────
void mousePressed() {
    if (mouseY >= TOP_H) {
        graph.mousePressed(mouseX, mouseY - TOP_H, ds, frameIdx);
        return;
    }
    if (mouseX >= VIEW_W) panel.mousePressed(mouseX - VIEW_W, mouseY, ds, frameIdx);
    else                  m3d.mousePressed(mouseX, mouseY);
}
void mouseDragged() {
    if (mouseY >= TOP_H || pmouseY >= TOP_H) {
        graph.mouseDragged(mouseX, mouseY - TOP_H, ds);
        return;
    }
    if (pmouseX >= VIEW_W || mouseX >= VIEW_W) panel.mouseDragged(mouseX - VIEW_W, mouseY, ds);
    else                                       m3d.mouseDragged(mouseX, mouseY);
}
void mouseReleased() {
    panel.mouseReleased(mouseX - VIEW_W, mouseY);
    graph.mouseReleased();
    m3d.mouseReleased();
}
void mouseWheel(MouseEvent e) {
    if (mouseY >= TOP_H) { graph.mouseWheel(e.getCount()); return; }
    if (mouseX < VIEW_W)   m3d.mouseWheel(e.getCount());
}

// ── File / live callbacks ─────────────────────────────────────────────────────
void fileSelected(java.io.File f) {
    if (f == null) return;
    liveMode = false;
    ds.loadCSV(f.getAbsolutePath());
    sync.build(ds, dsBoat);
    frameIdx = 0;  playing = true;  frameFrac = 0;
    if (posMode) integ.reset();
}

void boatFileSelected(java.io.File f) {
    if (f == null) return;
    dsBoat.loadCSV(f.getAbsolutePath());
    sync.build(ds, dsBoat);
}

void exportFileSelected(java.io.File f) {
    if (f == null) return;
    graph.exportMerged(f.getAbsolutePath(), ds, dsBoat, sync);
}

void setPlaySpeed(float s) { playSpeed = s;  if (s != SPEED_STEP) playing = true; }
void setPlaying(boolean p) { playing = p; }
void setFrameIdx(int idx)  {
    frameIdx = constrain(idx, 0, max(0, ds.frameCount()-1));
    if (posMode) integ.reset();
}

void toggleLive() {
    if (liveMode) { ds.closeSerial(); liveMode = false; return; }
    String[] ports = Serial.list();
    if (ports.length == 0) { println("No serial ports"); return; }
    String chosen = ports[0];
    for (String p : ports) if (p.contains("COM3") || p.contains("COM6")) { chosen = p; break; }
    ds.openSerial(this, chosen, 115200);
    liveMode = true;
    println("Live: " + chosen);
}
