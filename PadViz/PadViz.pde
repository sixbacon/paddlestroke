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
//   1            — test: slow rotation around X axis
//   2            — test: slow rotation around Y axis
//   3            — test: slow rotation around Z axis

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

// ── Axis test mode ────────────────────────────────────────────────────────────
// Takes the real frame and rebuilds the quaternion using only one Euler angle,
// so you can physically rotate the device and verify each axis independently.
FrameData testFrame(FrameData real) {
    FrameData fd = new FrameData();
    fd.hasQuat  = true;
    fd.roll     = real.roll;
    fd.pitch    = real.pitch;
    fd.yaw      = real.yaw;
    fd.cpm      = real.cpm;
    fd.strokeCount = real.strokeCount;
    fd.ts       = real.ts;
    float h, s, c;
    switch (testMode) {
        case 1:  // X axis only — driven by roll
            h = radians(real.roll) * 0.5f;
            s = sin(h); c = cos(h);
            fd.qw=c; fd.qx=s; fd.qy=0; fd.qz=0;
            break;
        case 2:  // Y axis only — driven by pitch
            h = radians(real.pitch) * 0.5f;
            s = sin(h); c = cos(h);
            fd.qw=c; fd.qx=0; fd.qy=s; fd.qz=0;
            break;
        case 3:  // Z axis only — driven by yaw
            h = radians(real.yaw) * 0.5f;
            s = sin(h); c = cos(h);
            fd.qw=c; fd.qx=0; fd.qy=0; fd.qz=s;
            break;
    }
    return fd;
}

// ── Keyboard ──────────────────────────────────────────────────────────────────
void keyPressed() {
    if (key == ' ')  { playing = !playing;  return; }
    if (key == '0')  { testMode = 0; surface.setTitle("PadViz"); return; }
    if (key == '1')  { testMode = 1; surface.setTitle("PadViz — TEST: X axis"); return; }
    if (key == '2')  { testMode = 2; surface.setTitle("PadViz — TEST: Y axis"); return; }
    if (key == '3')  { testMode = 3; surface.setTitle("PadViz — TEST: Z axis"); return; }
    if (key == 'o' || key == 'O') { selectInput("Select CSV log file", "fileSelected"); return; }
    if (key == 'r' || key == 'R') { m3d.resetCamera(); return; }
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
