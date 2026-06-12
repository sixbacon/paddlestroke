// PadViz — Paddle stroke 3-D visualiser
// Processing 4.x
// Live serial (PadVizLog on COM3) or CSV file replay
//
// Keys:
//   Space        — play / pause
//   Left/Right   — step one frame (works in any mode)
//   Home/End     — jump to start / end
//   O            — open file dialog
//   L            — connect / disconnect live serial
//   R            — reset camera
//   0            — normal mode (use file/serial data)
//   1            — test: shaft axis only
//   2            — test: blade-face axis only
//   3            — test: blade-up axis only
//   T            — toggle setup view (look down Z: X right, Y up)
//   K            — toggle kayak context view (fixed camera above-aft)

import processing.serial.*;

// ── Layout ────────────────────────────────────────────────────────────────────
static final int VIEW_W  = 900;
static final int PANEL_W = 500;
static final int TOTAL_W = VIEW_W + PANEL_W;
static final int TOTAL_H = 800;

// ── Playback ──────────────────────────────────────────────────────────────────
static final float SPEED_STEP = -1.0f;   // sentinel: manual step only
static final float SPEED_MAX  =  4.0f;

float   playSpeed = 1.0f;
boolean playing   = true;
int     frameIdx  = 0;
float   frameFrac = 0;

// ── Mode ──────────────────────────────────────────────────────────────────────
boolean liveMode = false;

// ── Axis test mode (0=off, 1=X, 2=Y, 3=Z) ───────────────────────────────────
int testMode = 0;

// ── Objects ───────────────────────────────────────────────────────────────────
DataSource ds;
Model3D    m3d;
SidePanel  panel;

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    size(1400, 800, P2D);
    surface.setTitle("PadViz");
    textFont(createFont("SansSerif", 13));

    ds    = new DataSource();
    m3d   = new Model3D(this);
    panel = new SidePanel(VIEW_W, TOTAL_H, PANEL_W);

    // Auto-load sample CSV if present in the sketch folder
    java.io.File sample = new java.io.File(sketchPath("ImuLog0420260521.CSV"));
    if (sample.exists()) {
        ds.loadCSV(sample.getAbsolutePath());
    }
}

// ── Draw ──────────────────────────────────────────────────────────────────────
void draw() {
    background(30);

    if (!liveMode) {
        advanceCSV();
    } else {
        ds.drainSerial();
    }

    FrameData real = liveMode ? ds.liveLatest() : ds.frameAt(frameIdx);
    FrameData fd   = (testMode > 0) ? testFrame(real) : real;

    m3d.draw(fd);
    image(m3d.canvas, 0, 0);

    panel.draw(ds, frameIdx, fd, playSpeed, playing);

    if (liveMode) drawSerialDebug();
    if (m3d.setupView) drawSetupLabel();
    if (testMode > 0) drawTestDiag(real);
}

// ── CSV frame advance ─────────────────────────────────────────────────────────
void advanceCSV() {
    if (ds.frameCount() == 0 || !playing || playSpeed == SPEED_STEP) return;

    frameFrac += playSpeed;
    int steps  = (int) frameFrac;
    frameFrac -= steps;

    frameIdx = min(frameIdx + steps, ds.frameCount() - 1);
    if (frameIdx >= ds.frameCount() - 1) {
        playing  = false;
        frameIdx = ds.frameCount() - 1;
    }
}

// ── Test-mode diagnostic overlay ─────────────────────────────────────────────
// Shows the total[] quaternion (IMU × correction) live so formulas can be
// verified empirically: rotate the device about one physical axis at a time
// and observe which components change.
void drawTestDiag(FrameData real) {
    float[] t = qMul(real.qw, real.qx, real.qy, real.qz,
                     MAP_CORR_W, MAP_CORR_X, MAP_CORR_Y, MAP_CORR_Z);
    fill(0, 0, 0, 160);  noStroke();
    rect(6, TOTAL_H - 36, VIEW_W - 12, 30, 3);
    fill(255, 200, 80);
    textSize(12);  textAlign(LEFT, CENTER);
    text(String.format("total  w=%.3f  x=%.3f  y=%.3f  z=%.3f", t[0], t[1], t[2], t[3]),
         14, TOTAL_H - 21);
}

// ── Setup view label (drawn on main canvas, not PGraphics) ───────────────────
void drawSetupLabel() {
    fill(255, 220, 60);  noStroke();
    textSize(13);  textAlign(CENTER, TOP);
    text("SETUP VIEW  — looking down -Z  (X→right, Y→up)  |  press T to exit",
         VIEW_W / 2, 6);
}

// ── Live serial debug overlay ─────────────────────────────────────────────────
void drawSerialDebug() {
    int bx = 10, by = TOTAL_H - 90, bw = VIEW_W - 20, bh = 84;
    fill(0, 0, 0, 180);  noStroke();
    rect(bx, by, bw, bh, 4);

    textSize(11);  textAlign(LEFT, TOP);
    int y = by + 6;

    fill(ds.liveFrameTotal > 0 ? color(100, 255, 100) : color(255, 180, 50));
    text("LIVE  frames=" + ds.liveFrameTotal + "  errors=" + ds.liveParseErrors, bx + 6, y);
    y += 15;

    fill(200);
    String raw = ds.lastRawLine;
    if (raw.length() > 100) raw = raw.substring(0, 100) + "...";
    text("last: " + raw, bx + 6, y);
    y += 15;

    FrameData lv = ds.liveLatest();
    fill(180, 220, 255);
    text(String.format("roll=%.1f  pitch=%.1f  yaw=%.1f  cpm=%.1f",
         lv.roll, lv.pitch, lv.yaw, lv.cpm), bx + 6, y);
    y += 15;

    fill(160);
    text(String.format("qw=%.4f  qx=%.4f  qy=%.4f  qz=%.4f",
         lv.qw, lv.qx, lv.qy, lv.qz), bx + 6, y);
}

// ── Quaternion helpers ────────────────────────────────────────────────────────
float[] qMul(float aw, float ax, float ay, float az,
             float bw, float bx, float by, float bz) {
    return new float[] {
        aw*bw - ax*bx - ay*by - az*bz,
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw
    };
}

float[] qNorm(float[] q) {
    float n = sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]);
    if (n < 1e-6f) return new float[]{ 1, 0, 0, 0 };
    return new float[]{ q[0]/n, q[1]/n, q[2]/n, q[3]/n };
}

// ── Axis test mode ────────────────────────────────────────────────────────────
// Computes the full corrected rotation (IMU × correction), extracts only the
// component around the requested corrected paddle axis (swing-twist projection),
// then back-transforms so that draw()'s IMU×correction gives that projection.
//
// *** WARNING: these projection formulas are derived for a SPECIFIC correction
// quaternion. If MAP_CORR_* in ModelMapping.pde is changed, all three case
// formulas below must be rederived to match the new corrected paddle axes. ***
//
// Current correction [0,1,0,0] = Rx(180°). Corrected paddle axes:
//   Mode 1 — shaft      → world +X  (OBJ X → Rx(180°) → +X)
//   Mode 2 — blade-face → world -Y  (OBJ Y → Rx(180°) → -Y)
//   Mode 3 — blade-up   → world -Z  (OBJ Z → Rx(180°) → -Z)
// NOTE: modes 2 and 3 projection formulas below are stale (written for old
// correction [0,0,-1,0]) and need updating for the current correction [0,1,0,0].
FrameData testFrame(FrameData real) {
    FrameData fd = new FrameData();
    fd.hasQuat     = true;
    fd.roll        = real.roll;
    fd.pitch       = real.pitch;
    fd.yaw         = real.yaw;
    fd.cpm         = real.cpm;
    fd.strokeCount = real.strokeCount;
    fd.ts          = real.ts;

    // total = what draw() would produce: IMU × correction
    float[] total = qMul(real.qw, real.qx, real.qy, real.qz,
                         MAP_CORR_W, MAP_CORR_X, MAP_CORR_Y, MAP_CORR_Z);

    // project total onto desired corrected paddle axis (swing-twist)
    float[] proj;
    switch (testMode) {
        case 1:  proj = qNorm(new float[]{ total[0],  total[1], 0,        0        }); break;
        case 2:  proj = qNorm(new float[]{ total[0],  0,        total[2], 0        }); break;
        case 3:  proj = qNorm(new float[]{ total[0],  0,        0,       -total[3] }); break;
        default: proj = new float[]{ real.qw, real.qx, real.qy, real.qz };
    }

    // fd.quat × correction = proj  →  fd.quat = proj × correction_conjugate
    float[] result = qMul(proj[0], proj[1], proj[2], proj[3],
                          MAP_CORR_W, -MAP_CORR_X, -MAP_CORR_Y, -MAP_CORR_Z);
    fd.qw = result[0];  fd.qx = result[1];
    fd.qy = result[2];  fd.qz = result[3];

    return fd;
}

// ── Keyboard ──────────────────────────────────────────────────────────────────
void keyPressed() {
    if (key == ' ')  { playing = !playing;  return; }
    if (key == '0')  { testMode = 0; surface.setTitle("PadViz"); return; }
    if (key == '1')  { testMode = 1; surface.setTitle("PadViz — TEST: shaft axis");
                       m3d.camAz = 0; m3d.camEl = 0; return; }   // look from +Y: gaze is -Y (opposite green)
    if (key == '2')  { testMode = 2; surface.setTitle("PadViz — TEST: blade-face axis");
                       m3d.camAz = 0; m3d.camEl = 0; return; }  // Z points up on screen
    if (key == '3')  { testMode = 3; surface.setTitle("PadViz — TEST: blade-up axis");
                       m3d.camAz = 30; m3d.camEl = 20; return; } // default 3/4 view: blue (Z) axis points up
    if (key == 'o' || key == 'O') { selectInput("Select CSV log file", "fileSelected"); return; }
    if (key == 'r' || key == 'R') { m3d.resetCamera(); return; }
    if (key == 't' || key == 'T') { m3d.toggleSetupView(); return; }
    if (key == 'k' || key == 'K') { m3d.kayakView = !m3d.kayakView; return; }
    if (key == 'l' || key == 'L') { toggleLive(); return; }

    if (keyCode == RIGHT) { frameIdx = min(frameIdx + 1, max(0, ds.frameCount() - 1)); playing = false; }
    if (keyCode == LEFT)  { frameIdx = max(frameIdx - 1, 0); playing = false; }
    if (keyCode == 36)  { frameIdx = 0; }                                         // Home
    if (keyCode == 35 && ds.frameCount() > 0) frameIdx = ds.frameCount() - 1;    // End
}

// ── Mouse ─────────────────────────────────────────────────────────────────────
void mousePressed() {
    if (mouseX >= VIEW_W) panel.mousePressed(mouseX - VIEW_W, mouseY, ds, frameIdx);
    else                  m3d.mousePressed(mouseX, mouseY);
}

void mouseDragged() {
    if (pmouseX >= VIEW_W || mouseX >= VIEW_W) panel.mouseDragged(mouseX - VIEW_W, mouseY, ds);
    else                                       m3d.mouseDragged(mouseX, mouseY);
}

void mouseReleased() {
    panel.mouseReleased(mouseX - VIEW_W, mouseY);
    m3d.mouseReleased();
}

void mouseWheel(MouseEvent e) {
    if (mouseX < VIEW_W) m3d.mouseWheel(e.getCount());
}

// ── File dialog callback ──────────────────────────────────────────────────────
void fileSelected(java.io.File f) {
    if (f == null) return;
    liveMode = false;
    ds.loadCSV(f.getAbsolutePath());
    frameIdx = 0;  playing = true;  frameFrac = 0;
}

// ── Speed / play callbacks (called from SidePanel) ────────────────────────────
void setPlaySpeed(float s)    { playSpeed = s;  if (s != SPEED_STEP) playing = true; }
void setPlaying(boolean p)    { playing = p; }
void setFrameIdx(int idx)     { frameIdx = constrain(idx, 0, max(0, ds.frameCount() - 1)); }

// ── Live serial ───────────────────────────────────────────────────────────────
void toggleLive() {
    if (liveMode) { ds.closeSerial(); liveMode = false; println("Live: disconnected"); return; }

    String[] ports = Serial.list();
    if (ports.length == 0) { println("No serial ports found"); return; }

    // Prefer COM3 (PadVizLog) over others
    String chosen = ports[0];
    for (String p : ports) {
        if (p.contains("COM3") || p.contains("COM6")) { chosen = p; break; }
    }
    ds.openSerial(this, chosen, 115200);
    liveMode = true;
    println("Live: " + chosen);
}
