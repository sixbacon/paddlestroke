// PadViz5 — Paddle + Boat dual-log visualiser
// Processing 4.x
//
// Keys:
//   Space        — play / pause
//   Left/Right   — step one frame
//   Home/End     — jump to start / end
//   O            — open ImuLog (paddle) CSV
//   B            — open BoatLog CSV
//   E            — export zoomed section to merged CSV
//   R            — reset camera
//   C            — toggle deck camera
//   1/2/3        — isolate roll / pitch / yaw (test modes)
//   0            — normal mode
//   A            — cycle correction tune axis
//   -  =         — nudge correction rotation ±5°
//   P            — toggle paddle position tracking

import processing.serial.*;

// ── Layout ────────────────────────────────────────────────────────────────────
static final int VIEW_W   = 900;
static final int PANEL_W  = 300;
static final int TOTAL_W  = VIEW_W + PANEL_W;   // 1200
static final int TOP_H    = 700;
static final int GRAPH_H  = 300;
static final int TOTAL_H  = TOP_H + GRAPH_H;    // 1000

// ── Playback ──────────────────────────────────────────────────────────────────
static final float SPEED_STEP = -1.0f;
static final float SPEED_MAX  =  4.0f;

float   playSpeed = 1.0f;
boolean playing   = true;
int     frameIdx  = 0;
float   frameFrac = 0;

// ── Mode ──────────────────────────────────────────────────────────────────────
int     testMode = 0;

// ── Paddle correction ─────────────────────────────────────────────────────────
float corrX = 0, corrY = 0, corrZ = 0;
int   tuneAxis = 0;
static final float NUDGE = 5.0f;

// ── Yaw averaging ─────────────────────────────────────────────────────────────
static final float YAW_EMA_ALPHA = 0.002f;
float yawEmaSin = 0.0f, yawEmaCos = 1.0f;
float avgYaw    = 0.0f;

// ── Position tracking ─────────────────────────────────────────────────────────
boolean posMode = true;

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
    size(1200, 1000, P2D);
    surface.setTitle("PadViz5");
    textFont(createFont("SansSerif", 13));

    ds     = new DataSource();
    dsBoat = new BoatSource();
    sync   = new SyncMap();
    m3d    = new Model3D(this);
    panel  = new SidePanel(VIEW_W, TOP_H, PANEL_W);
    graph  = new GraphPanel(0, TOP_H, TOTAL_W, GRAPH_H);
    integ  = new Integrator();
    integ.reset();
}

// ── Draw ──────────────────────────────────────────────────────────────────────
void draw() {
    background(30);

    advanceCSV();

    FrameData     fd  = ds.frameAt(frameIdx);
    BoatFrameData bfd = sync.boatFrameFor(frameIdx);
    FrameData     td  = applyTestMode(fd);

    float yr = radians(fd.yaw);
    yawEmaSin += YAW_EMA_ALPHA * (sin(yr) - yawEmaSin);
    yawEmaCos += YAW_EMA_ALPHA * (cos(yr) - yawEmaCos);
    avgYaw = degrees(atan2(yawEmaSin, yawEmaCos));

    if (posMode) integ.update(td);

    m3d.draw(td, bfd, corrX, corrY, corrZ, avgYaw,
             posMode ? integ.posX : 0, 0, posMode);
    image(m3d.canvas, 0, 0);

    panel.draw(ds, dsBoat, frameIdx, fd, bfd, playSpeed, playing);
    graph.draw(ds, dsBoat, sync, frameIdx);

    drawHudOverlay(td, bfd);
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

// ── Test mode ─────────────────────────────────────────────────────────────────
FrameData applyTestMode(FrameData src) {
    if (testMode == 0) return src;
    FrameData fd = new FrameData();
    fd.ts = src.ts;  fd.strokeCount = src.strokeCount;  fd.cpm = src.cpm;
    fd.hasQuat = src.hasQuat;
    fd.accelX = src.accelX;  fd.accelY = src.accelY;  fd.accelZ = src.accelZ;
    fd.gpsUtcSec = src.gpsUtcSec;
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
    text("t       " + nf(fd.ts / 1000.0f, 0, 1) + " s",  x, y);  y += dy;
    text("roll    " + nf(fd.roll,  0, 1) + "°",           x, y);  y += dy;
    text("pitch   " + nf(fd.pitch, 0, 1) + "°",           x, y);  y += dy;
    text("yaw     " + nf(fd.yaw,   0, 1) + "°",           x, y);  y += dy;
    text("CPM     " + nf(fd.cpm,   0, 1),                 x, y);  y += dy;
    text("stroke  " + fd.strokeCount,                      x, y);  y += dy;

    if (bfd != null) {
        y += 4;
        fill(100, 200, 255, 200);
        text("kYaw    " + nf(bfd.kayakYaw,   0, 1) + "°", x, y);  y += dy;
        text("kRoll   " + nf(bfd.kayakRoll,  0, 1) + "°", x, y);  y += dy;
        text("kPitch  " + nf(bfd.kayakPitch, 0, 1) + "°", x, y);  y += dy;
        text("speed   " + nf(bfd.speedMs * 1.94384f, 0, 2) + " kn", x, y);  y += dy;
    }

    if (posMode) {
        y += 4;
        fill(140, 255, 140, 200);
        text("posX    " + nf(integ.posX, 0, 3) + " m"
             + (integ.usingFallback ? "  (roll est.)" : "  (accel)"), x, y);  y += dy;
    }

    y += 6;
    fill(255, 200, 80, 200);
    String axName = new String[]{"X","Y","Z"}[tuneAxis];
    text("corr   Rx=" + nf(corrX,0,1) + "  Ry=" + nf(corrY,0,1) + "  Rz=" + nf(corrZ,0,1)
         + "   tune:" + axName, x, y);
    y += dy;
    fill(m3d.deckCam ? color(100, 220, 100, 200) : color(160, 160, 160, 200));
    text("cam    " + (m3d.deckCam ? "DECK" : "ORBIT") + "  (C)", x, y);

    if (testMode > 0) {
        y += dy + 4;
        fill(255, 120, 120, 220);
        String[] names = {"","ROLL ONLY","PITCH ONLY","YAW ONLY"};
        text("TEST: " + names[testMode], x, y);
    }
}

// ── Keyboard ──────────────────────────────────────────────────────────────────
void keyPressed() {
    if (key == ' ')  { playing = !playing; return; }
    if (key == '0')  { testMode = 0; return; }
    if (key == '1')  { testMode = 1; return; }
    if (key == '2')  { testMode = 2; return; }
    if (key == '3')  { testMode = 3; return; }
    if (key == 'r' || key == 'R') { m3d.resetCamera(); return; }
    if (key == 'o' || key == 'O') { selectInput("Select ImuLog (paddle) CSV", "imuFileSelected"); return; }
    if (key == 'b' || key == 'B') { selectInput("Select BoatLog CSV", "boatFileSelected"); return; }
    if (key == 'e' || key == 'E') { selectOutput("Export merged CSV", "exportFileSelected"); return; }
    if (key == 'a' || key == 'A') { tuneAxis = (tuneAxis + 1) % 3; return; }
    if (key == 'c' || key == 'C') { m3d.deckCam = !m3d.deckCam; return; }
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
        graph.mousePressed(mouseX, mouseY - TOP_H, ds);
    } else if (mouseX >= VIEW_W) {
        panel.mousePressed(mouseX - VIEW_W, mouseY, ds, frameIdx);
    } else {
        m3d.mousePressed(mouseX, mouseY);
    }
}
void mouseDragged() {
    if (mouseY >= TOP_H || pmouseY >= TOP_H) {
        graph.mouseDragged(mouseX, mouseY - TOP_H, ds);
    } else if (pmouseX >= VIEW_W || mouseX >= VIEW_W) {
        panel.mouseDragged(mouseX - VIEW_W, mouseY, ds);
    } else {
        m3d.mouseDragged(mouseX, mouseY);
    }
}
void mouseReleased() {
    panel.mouseReleased();
    graph.mouseReleased();
    m3d.mouseReleased();
}
void mouseWheel(MouseEvent e) {
    if (mouseY >= TOP_H) { graph.mouseWheel(e.getCount()); return; }
    if (mouseX < VIEW_W) m3d.mouseWheel(e.getCount());
}

// ── File callbacks ────────────────────────────────────────────────────────────
void imuFileSelected(java.io.File f) {
    if (f == null) return;
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

// ── Callbacks from SidePanel / GraphPanel ─────────────────────────────────────
void setPlaySpeed(float s) { playSpeed = s;  if (s != SPEED_STEP) playing = true; }
void setPlaying(boolean p) { playing = p; }
void setFrameIdx(int idx)  {
    frameIdx = constrain(idx, 0, max(0, ds.frameCount()-1));
}
void togglePlayPause() { playing = !playing; }
