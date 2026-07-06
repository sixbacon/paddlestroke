// SidePanel — slim info + transport strip on the right of the 3D view.
//
// PadViz5b: chart + variable selector live in the bottom GraphPanel.
// This panel holds: paddle + boat file names, Load buttons, play/pause,
// speed slider.

class SidePanel {
    int px, ph, pw;

    // ── Layout ────────────────────────────────────────────────────────────────
    final int MARGIN     = 12;
    final int SLIDER_H   = 18;
    final int BUTTON_H   = 28;
    final int LOAD_BTN_H = 22;
    final float STEP_FRAC = 0.08f;

    // ── Cached geometry (set during draw) ─────────────────────────────────────
    int sliderY, playBtnY;
    int loadPadBtnY, loadBoatBtnY;
    int loadPadBtnX, loadBoatBtnX;
    int loadBtnW;

    // ── Drag state ────────────────────────────────────────────────────────────
    boolean sliderDrag = false;

    SidePanel(int originX, int height, int width) {
        px = originX;  ph = height;  pw = width;
    }

    // ── Draw ─────────────────────────────────────────────────────────────────
    void draw(DataSource ds, BoatSource dsBoat, int frameIdx, FrameData fd,
              float curSpeed, boolean playing) {
        pushMatrix();
        translate(px, 0);

        // Background + separator
        fill(40, 42, 52);  noStroke();  rect(0, 0, pw, ph);
        stroke(80);  line(0, 0, 0, ph);  noStroke();

        int y = MARGIN;

        // File names
        fill(190);  textSize(12);  textAlign(LEFT, TOP);
        String padName  = ds.sourceName().length()     > 0 ? ds.sourceName()     : "(none — click Load Paddle)";
        String boatName = dsBoat.sourceName().length() > 0 ? dsBoat.sourceName() : "(none — click Load Boat)";
        text("Paddle: " + padName,  MARGIN, y);  y += 18;
        text("Boat:   " + boatName, MARGIN, y);  y += 22;

        // Load Paddle / Load Boat buttons side-by-side
        loadBtnW      = (pw - MARGIN * 3) / 2;
        loadPadBtnX   = MARGIN;
        loadBoatBtnX  = MARGIN + loadBtnW + MARGIN;
        loadPadBtnY   = y;
        loadBoatBtnY  = y;
        drawLoadBtn(loadPadBtnX,  y, loadBtnW, "Load Paddle CSV  (O)");
        drawLoadBtn(loadBoatBtnX, y, loadBtnW, "Load Boat CSV  (B)");
        y += LOAD_BTN_H + 10;

        // Play/pause button
        playBtnY = y;
        drawPlayBtn(playing);
        y += BUTTON_H + 8;

        // Speed slider
        sliderY = y + 10;
        drawSpeedSlider(curSpeed);

        popMatrix();
    }

    // ── Load button (generic) ─────────────────────────────────────────────────
    void drawLoadBtn(int bx, int by, int bw, String label) {
        fill(60, 80, 110);  noStroke();  rect(bx, by, bw, LOAD_BTN_H, 3);
        fill(220);  textSize(11);  textAlign(CENTER, CENTER);
        text(label, bx + bw / 2, by + LOAD_BTN_H / 2);
    }

    // ── Play button ───────────────────────────────────────────────────────────
    void drawPlayBtn(boolean playing) {
        int bx = MARGIN, bw = pw - MARGIN * 2;
        fill(playing ? color(55, 130, 55) : color(110, 55, 55));
        noStroke();  rect(bx, playBtnY, bw, BUTTON_H, 4);
        fill(255);  textSize(14);  textAlign(CENTER, CENTER);
        text(playing ? "||  PAUSE" : ">  PLAY", bx + bw / 2, playBtnY + BUTTON_H / 2);
    }

    // ── Speed slider ──────────────────────────────────────────────────────────
    void drawSpeedSlider(float curSpeed) {
        int sx = MARGIN, sw = pw - MARGIN * 2, sy = sliderY;
        fill(65);  noStroke();  rect(sx, sy, sw, SLIDER_H, 4);

        float t  = speedToT(curSpeed);
        int   tx = sx + (int)(t * sw);
        fill(220, 200, 60);  rect(tx - 4, sy - 2, 8, SLIDER_H + 4, 3);

        int stepX = sx + (int)(STEP_FRAC * sw);
        stroke(160, 80, 80);  strokeWeight(1);
        line(stepX, sy - 5, stepX, sy + SLIDER_H + 5);  noStroke();

        fill(155);  textSize(11);
        textAlign(LEFT,   BASELINE);  text("STEP", sx,       sy - 2);
        textAlign(CENTER, BASELINE);  text("1x",   sx + sw/2, sy - 2);
        textAlign(RIGHT,  BASELINE);  text("4x",   sx + sw,   sy - 2);

        String lbl = (curSpeed == SPEED_STEP) ? "step" : nf(curSpeed, 0, 2) + "x";
        fill(255, 220, 80);  textSize(12);  textAlign(CENTER, TOP);
        text(lbl, sx + sw / 2, sy + SLIDER_H + 3);
    }

    // ── Mouse handlers ────────────────────────────────────────────────────────
    void mousePressed(int mx, int my, DataSource ds, int frameIdx) {
        // Load buttons
        if (my >= loadPadBtnY && my < loadPadBtnY + LOAD_BTN_H) {
            if (mx >= loadPadBtnX && mx < loadPadBtnX + loadBtnW) {
                selectInput("Select paddle ImuLog CSV", "fileSelected");
                return;
            }
            if (mx >= loadBoatBtnX && mx < loadBoatBtnX + loadBtnW) {
                selectInput("Select BoatLog CSV", "boatFileSelected");
                return;
            }
        }

        // Play button
        if (my >= playBtnY && my < playBtnY + BUTTON_H) {
            togglePlayPause();
            return;
        }

        // Speed slider
        int sx = MARGIN, sw = pw - MARGIN * 2;
        if (my >= sliderY - 4 && my <= sliderY + SLIDER_H + 4 && mx >= sx && mx <= sx + sw) {
            sliderDrag = true;
            applySlider(mx, sx, sw);
        }
    }

    void mouseDragged(int mx, int my, DataSource ds) {
        if (sliderDrag) applySlider(mx, MARGIN, pw - MARGIN * 2);
    }

    void mouseReleased(int mx, int my) {
        sliderDrag = false;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private void applySlider(int mx, int sx, int sw) {
        float t = constrain((float)(mx - sx) / sw, 0, 1);
        setPlaySpeed(tToSpeed(t));
    }

    float tToSpeed(float t) {
        if (t < STEP_FRAC) return SPEED_STEP;
        float nt = (t - STEP_FRAC) / (1.0f - STEP_FRAC);
        return exp(log(SPEED_MAX) * nt);
    }

    float speedToT(float spd) {
        if (spd == SPEED_STEP) return STEP_FRAC * 0.4f;
        float nt = log(max(spd, 0.01f)) / log(SPEED_MAX);
        return STEP_FRAC + nt * (1.0f - STEP_FRAC);
    }
}

// ── Top-level callbacks invoked by SidePanel ──────────────────────────────────
void togglePlayPause() { playing = !playing; }
