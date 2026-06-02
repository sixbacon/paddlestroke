// SidePanel — speed slider, play/pause, strip chart, variable selector, zoom

class SidePanel {
    // Panel geometry
    int px, ph, pw;

    // ── Variable selector ─────────────────────────────────────────────────────
    final int N_VARS  = 5;
    final int N_SLOTS = 3;
    final String[] VAR_NAMES  = {"roll", "pitch", "yaw", "CPM", "strokes"};
    final int[]    SLOT_COLS  = {color(255, 100, 100), color(100, 220, 100), color(100, 160, 255)};
    int[]          slotVar    = {0, 1, -1};   // slot → field index; -1 = empty

    // ── Layout ────────────────────────────────────────────────────────────────
    final int MARGIN    = 12;
    final int SLIDER_H  = 18;
    final int BUTTON_H  = 28;
    final int VAR_ROW_H = 22;
    final float STEP_FRAC = 0.08f;   // left fraction of slider = step mode

    // ── Cached geometry (set during draw) ─────────────────────────────────────
    int sliderY, playBtnY;
    int chartX, chartY, chartW, chartH;
    int varRowsTop;

    // ── Zoom state ────────────────────────────────────────────────────────────
    int  zoomA = -1, zoomB = -1;
    boolean sliderDrag = false, zoomDrag = false;
    int  zoomDragStart;

    SidePanel(int originX, int height, int width) {
        px = originX;  ph = height;  pw = width;
    }

    // ── Draw ─────────────────────────────────────────────────────────────────
    void draw(DataSource ds, int frameIdx, FrameData fd, float curSpeed, boolean playing) {
        pushMatrix();
        translate(px, 0);

        // Background + separator
        fill(40, 42, 52);  noStroke();  rect(0, 0, pw, ph);
        stroke(80);  line(0, 0, 0, ph);  noStroke();

        int y = MARGIN;

        // Source name
        fill(190);  textSize(12);  textAlign(LEFT, TOP);
        String name = ds.sourceName().length() > 0 ? ds.sourceName() : "(no file — press O to open)";
        text(name, MARGIN, y);
        y += 18;

        // Play/pause button
        playBtnY = y;
        drawPlayBtn(playing);
        y += BUTTON_H + 8;

        // Speed slider
        sliderY = y + 10;
        drawSpeedSlider(curSpeed);
        y += SLIDER_H + 26;

        // Variable selector
        varRowsTop = y + 14;
        fill(155);  textSize(11);  textAlign(LEFT, TOP);
        text("Variables  (click to assign/remove slot)", MARGIN, y);
        y += 14;
        for (int v = 0; v < N_VARS; v++) {
            int slot = slotOf(v);
            fill(slot >= 0 ? SLOT_COLS[slot] : color(55, 57, 70));
            noStroke();  rect(MARGIN, y, pw - MARGIN * 2, VAR_ROW_H - 2, 3);
            fill(slot >= 0 ? 20 : 210);  textSize(12);  textAlign(LEFT, CENTER);
            text(VAR_NAMES[v], MARGIN + 6, y + VAR_ROW_H / 2);
            y += VAR_ROW_H;
        }
        y += MARGIN;

        // Strip chart (remaining height minus footer)
        chartX = MARGIN;
        chartW = pw - MARGIN * 2;
        chartY = y;
        chartH = ph - y - MARGIN - 24;
        if (ds.frameCount() > 1 && chartH > 60) drawChart(ds, frameIdx);

        // Zoom footer
        drawZoomFooter(ds);

        popMatrix();
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

    // ── Strip chart ───────────────────────────────────────────────────────────
    void drawChart(DataSource ds, int frameIdx) {
        int n = ds.frameCount();
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB > 0  && zoomB > zoomA) ? zoomB : n - 1;

        fill(18, 20, 28);  noStroke();  rect(chartX, chartY, chartW, chartH);

        // Cursor line
        float curT = (float)(frameIdx - viewA) / max(1, viewB - viewA);
        stroke(255, 255, 100, 180);  strokeWeight(1);
        line(chartX + curT * chartW, chartY, chartX + curT * chartW, chartY + chartH);

        // Zoom region overlay
        if (zoomA >= 0 && zoomB > zoomA) {
            float zA = (float) zoomA / (n - 1);
            float zB = (float) zoomB / (n - 1);
            fill(80, 120, 200, 35);  noStroke();
            rect(chartX + zA * chartW, chartY, (zB - zA) * chartW, chartH);
        }

        // Plot slots
        for (int slot = 0; slot < N_SLOTS; slot++) {
            int fi = slotVar[slot];
            if (fi < 0) continue;
            float[] rng = ds.fieldRange(fi);
            float mn = rng[0], mx = rng[1];
            stroke(SLOT_COLS[slot]);  strokeWeight(1);  noFill();
            beginShape();
            for (int pxi = 0; pxi < chartW; pxi++) {
                int idx = viewA + (int)((float)pxi / max(1, chartW - 1) * (viewB - viewA));
                idx = constrain(idx, 0, n - 1);
                float v  = ds.fieldAt(idx, fi);
                float vy = chartY + chartH - map(v, mn, mx, 0, chartH);
                vertex(chartX + pxi, vy);
            }
            endShape();
        }

        // Axis labels
        fill(110);  textSize(10);
        textAlign(LEFT,  TOP);  text(nf(ds.firstTs() / 1000.0f, 0, 0) + "s", chartX, chartY + chartH + 1);
        textAlign(RIGHT, TOP);  text(nf(ds.lastTs()  / 1000.0f, 0, 0) + "s", chartX + chartW, chartY + chartH + 1);
    }

    // ── Zoom footer ───────────────────────────────────────────────────────────
    void drawZoomFooter(DataSource ds) {
        int y = ph - MARGIN - 22;
        fill(68);  noStroke();  rect(MARGIN, y, 48, 20, 3);
        fill(200);  textSize(11);  textAlign(CENTER, CENTER);
        text("Full", MARGIN + 24, y + 10);

        int n = ds.frameCount();
        if (n > 0) {
            int a = (zoomA >= 0) ? zoomA : 0;
            int b = (zoomB >  0) ? zoomB : n - 1;
            long tA = ds.frameAt(a).ts, tB = ds.frameAt(b).ts;
            fill(140);  textSize(10);  textAlign(LEFT, CENTER);
            text(nf(tA / 1000.0f, 0, 1) + "s – " + nf(tB / 1000.0f, 0, 1) + "s",
                 MARGIN + 56, y + 10);
        }
    }

    // ── Mouse handlers ────────────────────────────────────────────────────────
    void mousePressed(int mx, int my, DataSource ds, int frameIdx) {
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
            return;
        }

        // Variable rows
        for (int v = 0; v < N_VARS; v++) {
            int ry = varRowsTop + v * VAR_ROW_H;
            if (my >= ry && my < ry + VAR_ROW_H) { cycleSlot(v); return; }
        }

        // Chart zoom drag
        if (my >= chartY && my <= chartY + chartH && mx >= chartX && mx <= chartX + chartW) {
            zoomDrag      = true;
            zoomDragStart = frameFromChartX(mx, ds);
            zoomA = zoomB = zoomDragStart;
            return;
        }

        // "Full" button
        if (my >= ph - MARGIN - 22 && my <= ph - MARGIN - 2 && mx >= MARGIN && mx <= MARGIN + 48) {
            zoomA = zoomB = -1;
        }
    }

    void mouseDragged(int mx, int my, DataSource ds) {
        if (sliderDrag) { applySlider(mx, MARGIN, pw - MARGIN * 2); return; }
        if (zoomDrag) {
            int fi = frameFromChartX(mx, ds);
            if (fi >= zoomDragStart) { zoomA = zoomDragStart; zoomB = fi; }
            else                     { zoomA = fi;            zoomB = zoomDragStart; }
        }
    }

    void mouseReleased(int mx, int my) {
        sliderDrag = false;
        zoomDrag   = false;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private void applySlider(int mx, int sx, int sw) {
        float t = constrain((float)(mx - sx) / sw, 0, 1);
        setPlaySpeed(tToSpeed(t));
    }

    private int slotOf(int varIdx) {
        for (int s = 0; s < N_SLOTS; s++) if (slotVar[s] == varIdx) return s;
        return -1;
    }

    private void cycleSlot(int varIdx) {
        int cur = slotOf(varIdx);
        if (cur >= 0) {
            slotVar[cur] = -1;   // remove
        } else {
            for (int s = 0; s < N_SLOTS; s++) {
                if (slotVar[s] < 0) { slotVar[s] = varIdx; return; }
            }
            slotVar[0] = varIdx;  // evict slot 0 if all full
        }
    }

    private int frameFromChartX(int mx, DataSource ds) {
        int n = ds.frameCount();
        if (n < 2) return 0;
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;
        float t = constrain((float)(mx - chartX) / max(1, chartW), 0, 1);
        return constrain(viewA + (int)(t * (viewB - viewA)), 0, n - 1);
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
