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

    FrameData fd = liveMode ? ds.liveLatest() : ds.frameAt(frameIdx);

    m3d.draw(fd);
    image(m3d.canvas, 0, 0);

    panel.draw(ds, frameIdx, fd, playSpeed, playing);
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

// ── Keyboard ──────────────────────────────────────────────────────────────────
void keyPressed() {
    if (key == ' ')  { playing = !playing;  return; }
    if (key == 'o' || key == 'O') { selectInput("Select CSV log file", "fileSelected"); return; }
    if (key == 'r' || key == 'R') { m3d.resetCamera(); return; }
    if (key == 'l' || key == 'L') { toggleLive(); return; }

    if (keyCode == RIGHT) { frameIdx = min(frameIdx + 1, max(0, ds.frameCount() - 1)); playing = false; }
    if (keyCode == LEFT)  { frameIdx = max(frameIdx - 1, 0); playing = false; }
    if (keyCode == HOME)  { frameIdx = 0; }
    if (keyCode == END && ds.frameCount() > 0) frameIdx = ds.frameCount() - 1;
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
