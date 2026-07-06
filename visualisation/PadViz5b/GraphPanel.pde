// GraphPanel — full-width strip along the bottom of the window.
//
// Up to 3 colour-coded traces, each selected from a dropdown of paddle
// (and later boat) fields. Drag on the chart to zoom, drag the yellow
// cursor line to seek. "Full" button clears the zoom.
//
// Slice 4 exposes paddle fields only; boat fields land in slice 5.
// Export button lands in slice 6.

class GraphPanel {
    int gx, gy, gw, gh;

    // ── Field definitions ─────────────────────────────────────────────────────
    // Source: 0 = paddle (ImuLog), 1 = boat (BoatLog).
    // Boat sub-fields: 0=kayakRoll 1=kayakPitch 2=kayakYaw 3=speedMs 4=cogDeg.
    static final int N_FIELDS = 13;
    final String[] FIELD_NAMES = {
        "Pad: roll", "Pad: pitch", "Pad: yaw", "Pad: CPM", "Pad: strokeCount",
        "Pad: accel_x", "Pad: accel_y", "Pad: accel_z",
        "Boat: kayak_roll", "Boat: kayak_pitch", "Boat: kayak_yaw",
        "Boat: speed_ms", "Boat: cog_deg"
    };
    final int[][] FIELD_MAP = {
        {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6},{0,7},
        {1,0},{1,1},{1,2},{1,3},{1,4}
    };

    // Dropdown item 0 = "— none —" (fi=-1), items 1..N = fields 0..N-1
    int DD_ITEM_COUNT = N_FIELDS + 1;

    static final int N_SLOTS = 3;
    final int[] SLOT_COLS = {color(255, 100, 100), color(100, 220, 100), color(100, 160, 255)};
    int[] slotField = {0, 2, 3};   // default: roll, yaw, CPM

    // ── Layout ────────────────────────────────────────────────────────────────
    static final int SEL_W  = 220;
    static final int MARGIN = 8;
    static final int ROW_H  = 20;
    static final int BTN_H  = 22;

    // ── Zoom state (in paddle frame indices) ──────────────────────────────────
    int zoomA = -1, zoomB = -1;

    // ── Dropdown state ────────────────────────────────────────────────────────
    int dropdownSlot   = -1;     // which slot is open (-1 = none)
    int dropdownY;
    int dropdownScroll = 0;

    // ── Drag state ────────────────────────────────────────────────────────────
    boolean zoomDrag  = false;
    boolean seekDrag  = false;
    int     zoomDragStart;

    // Cached chart geometry (set during draw)
    int chartX, chartY, chartW, chartH;

    GraphPanel(int x, int y, int w, int h) {
        gx = x;  gy = y;  gw = w;  gh = h;
    }

    // ── Draw ─────────────────────────────────────────────────────────────────
    void draw(DataSource ds, BoatSource dsBoat, SyncMap sync, int frameIdx) {
        pushMatrix();
        translate(gx, gy);

        // Background
        fill(28, 30, 38);  noStroke();  rect(0, 0, gw, gh);
        stroke(70);  line(0, 0, gw, 0);  noStroke();

        // Left: field selector column
        drawFieldSelector();

        // Right: chart area
        chartX = SEL_W + MARGIN;
        chartY = MARGIN + BTN_H + 4;
        chartW = gw - SEL_W - MARGIN * 2;
        chartH = gh - chartY - MARGIN - 18;

        if (ds.frameCount() > 1 && chartH > 40) {
            drawChart(ds, dsBoat, sync, frameIdx);
        }

        drawFooter(ds);

        // Dropdown on top
        if (dropdownSlot >= 0) drawDropdown();

        popMatrix();
    }

    // ── Field selector ────────────────────────────────────────────────────────
    void drawFieldSelector() {
        int x = MARGIN, y = MARGIN;

        fill(150);  textSize(10);  textAlign(LEFT, TOP);
        text("Fields  (click slot to change)", x, y);
        y += 14;

        for (int s = 0; s < N_SLOTS; s++) {
            int fi = slotField[s];
            boolean active = (fi >= 0 && fi < N_FIELDS);
            fill(active ? SLOT_COLS[s] : color(55, 58, 70));  noStroke();
            rect(x, y, SEL_W - MARGIN, BTN_H, 3);
            fill(active ? 20 : 140);  textSize(11);  textAlign(LEFT, CENTER);
            String lbl = active ? FIELD_NAMES[fi] : "— none —";
            text(lbl, x + 6, y + BTN_H / 2);
            y += BTN_H + 4;
        }

        y += 4;
        fill(100);  textSize(10);  textAlign(LEFT, TOP);
        text("Drag chart to zoom · drag cursor to seek", x, y);
    }

    // ── Chart ─────────────────────────────────────────────────────────────────
    void drawChart(DataSource ds, BoatSource dsBoat, SyncMap sync, int frameIdx) {
        int n = ds.frameCount();
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        fill(15, 17, 24);  noStroke();  rect(chartX, chartY, chartW, chartH);

        // Zoom-selection overlay while dragging (visual feedback)
        if (zoomA >= 0 && zoomB > zoomA) {
            float zA = (float)(zoomA - 0) / max(1, n - 1);
            float zB = (float)(zoomB - 0) / max(1, n - 1);
            // Only show the overlay when zoom hasn't been applied yet — i.e. always,
            // as a subtle band indicating the current selection extent.
            fill(80, 120, 200, 25);  noStroke();
            rect(chartX + zA * chartW, chartY, (zB - zA) * chartW, chartH);
        }

        // Per-slot traces
        for (int s = 0; s < N_SLOTS; s++) {
            int fi = slotField[s];
            if (fi < 0 || fi >= N_FIELDS) continue;
            int src   = FIELD_MAP[fi][0];
            int subFi = FIELD_MAP[fi][1];

            float[] rng;
            if (src == 0) {
                rng = ds.fieldRange(subFi);
            } else {
                if (dsBoat.frameCount() == 0) continue;
                rng = dsBoat.fieldRange(subFi);
            }
            float mn = rng[0], mx = rng[1];

            stroke(SLOT_COLS[s]);  strokeWeight(1);  noFill();
            boolean inShape = false;
            for (int pxi = 0; pxi < chartW; pxi++) {
                int padIdx = viewA + (int)((float)pxi / max(1, chartW - 1) * (viewB - viewA));
                padIdx = constrain(padIdx, 0, n - 1);

                float v;
                if (src == 0) {
                    v = ds.fieldAt(padIdx, subFi);
                } else {
                    int boatIdx = sync.boatIdxFor(padIdx);
                    if (boatIdx < 0) {
                        if (inShape) { endShape(); inShape = false; }
                        continue;
                    }
                    v = dsBoat.frameAt(boatIdx).field(subFi);
                }

                float vy = chartY + chartH - map(v, mn, mx, 0, chartH);
                if (!inShape) { beginShape(); inShape = true; }
                vertex(chartX + pxi, vy);
            }
            if (inShape) endShape();
        }

        // Cursor line
        float curT = (float)(frameIdx - viewA) / max(1, viewB - viewA);
        int   curX = chartX + (int)(curT * chartW);
        stroke(255, 255, 100, 220);  strokeWeight(2);
        line(curX, chartY, curX, chartY + chartH);
        strokeWeight(1);

        // Time axis labels (view start / end)
        fill(110);  textSize(10);
        FrameData fA = ds.frameAt(viewA), fB = ds.frameAt(viewB);
        textAlign(LEFT,  TOP);  text(nf(fA.ts / 1000.0f, 0, 1) + "s", chartX, chartY + chartH + 1);
        textAlign(RIGHT, TOP);  text(nf(fB.ts / 1000.0f, 0, 1) + "s", chartX + chartW, chartY + chartH + 1);
    }

    // ── Footer ────────────────────────────────────────────────────────────────
    void drawFooter(DataSource ds) {
        int fy = gh - MARGIN - 16;

        // Full button
        fill(65);  noStroke();  rect(SEL_W + MARGIN, fy, 40, 16, 3);
        fill(200);  textSize(10);  textAlign(CENTER, CENTER);
        text("Full", SEL_W + MARGIN + 20, fy + 8);

        // Export button
        fill(80, 100, 60);  rect(SEL_W + MARGIN + 46, fy, 60, 16, 3);
        fill(210);  text("Export…", SEL_W + MARGIN + 76, fy + 8);

        // Zoom range readout
        if (ds.frameCount() > 0) {
            int a = (zoomA >= 0) ? zoomA : 0;
            int b = (zoomB >  0) ? zoomB : ds.frameCount() - 1;
            long tA = ds.frameAt(a).ts, tB = ds.frameAt(b).ts;
            fill(120);  textAlign(LEFT, CENTER);
            text(nf(tA/1000.0f,0,1) + "s – " + nf(tB/1000.0f,0,1) + "s  ("
                 + nf((tB-tA)/1000.0f,0,1) + "s)",
                 SEL_W + MARGIN + 112, fy + 8);
        }
    }

    // ── Dropdown ─────────────────────────────────────────────────────────────
    void drawDropdown() {
        int x = MARGIN;
        int y = dropdownY;
        int w = SEL_W - MARGIN;

        int maxRows = max(4, (gh - y - 6) / ROW_H);
        int visRows = min(maxRows, DD_ITEM_COUNT);
        int pxH     = visRows * ROW_H + 4;

        fill(45, 48, 60);  stroke(90);  strokeWeight(1);
        rect(x, y, w, pxH, 3);

        for (int vi = 0; vi < visRows; vi++) {
            int itemIdx = dropdownScroll + vi;
            if (itemIdx >= DD_ITEM_COUNT) break;
            int fi = itemIdx - 1;             // -1 = none
            int ry = y + 2 + vi * ROW_H;
            boolean sel = (slotField[dropdownSlot] == fi);
            fill(sel ? SLOT_COLS[dropdownSlot] : color(55, 58, 72));
            noStroke();  rect(x + 2, ry, w - 4, ROW_H - 2, 2);
            fill(sel ? 20 : 200);  textSize(10);  textAlign(LEFT, CENTER);
            text(fi < 0 ? "— none —" : FIELD_NAMES[fi], x + 8, ry + ROW_H / 2);
        }

        // Scroll arrows when list exceeds viewport
        textAlign(RIGHT, CENTER);  textSize(11);
        if (dropdownScroll > 0) {
            fill(100, 180, 255);
            text("▲", x + w - 4, y + 2 + ROW_H / 2);
        }
        if (dropdownScroll + visRows < DD_ITEM_COUNT) {
            fill(100, 180, 255);
            text("▼", x + w - 4, y + pxH - ROW_H / 2);
        }
    }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    // mx/my are in panel-local coordinates (gx/gy already subtracted by caller).
    void mousePressed(int mx, int my, DataSource ds, int frameIdx) {
        // If dropdown is open, any click routes there
        if (dropdownSlot >= 0) {
            if (mx >= MARGIN && mx <= SEL_W) {
                int maxRows = max(4, (gh - dropdownY - 6) / ROW_H);
                int visRows = min(maxRows, DD_ITEM_COUNT);
                int vi = (my - dropdownY - 2) / ROW_H;
                if (vi >= 0 && vi < visRows) {
                    int itemIdx = dropdownScroll + vi;
                    if (itemIdx < DD_ITEM_COUNT) {
                        slotField[dropdownSlot] = itemIdx - 1;   // -1 = none
                    }
                }
            }
            dropdownSlot = -1;
            return;
        }

        // Slot buttons
        int sy = MARGIN + 14;
        for (int s = 0; s < N_SLOTS; s++) {
            if (mx >= MARGIN && mx <= SEL_W - MARGIN
                && my >= sy && my < sy + BTN_H) {
                dropdownSlot   = s;
                dropdownY      = sy + BTN_H + 2;
                dropdownScroll = 0;
                return;
            }
            sy += BTN_H + 4;
        }

        // "Full" button
        int fy = gh - MARGIN - 16;
        if (my >= fy && my <= fy + 16 && mx >= SEL_W + MARGIN && mx <= SEL_W + MARGIN + 40) {
            zoomA = zoomB = -1;
            return;
        }

        // "Export…" button — routes to the top-level file picker in PadViz5b.pde
        if (my >= fy && my <= fy + 16
            && mx >= SEL_W + MARGIN + 46 && mx <= SEL_W + MARGIN + 46 + 60) {
            selectOutput("Export merged CSV", "exportFileSelected");
            return;
        }

        // Chart: seek if near cursor, else start a zoom drag
        if (mx >= chartX && mx <= chartX + chartW && my >= chartY && my <= chartY + chartH) {
            int n = ds.frameCount();
            if (n < 2) return;
            int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
            int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;
            float curT   = (float)(frameIdx - viewA) / max(1, viewB - viewA);
            int   cursorX = chartX + (int)(curT * chartW);
            if (abs(mx - cursorX) <= 6) {
                seekDrag = true;
                setFrameIdx(frameFromChartX(mx, ds));
                setPlaying(false);
            } else {
                zoomDrag      = true;
                zoomDragStart = frameFromChartX(mx, ds);
                zoomA = zoomB = zoomDragStart;
            }
        }
    }

    void mouseDragged(int mx, int my, DataSource ds) {
        if (seekDrag) { setFrameIdx(frameFromChartX(mx, ds)); return; }
        if (zoomDrag) {
            int fi = frameFromChartX(mx, ds);
            if (fi >= zoomDragStart) { zoomA = zoomDragStart; zoomB = fi; }
            else                     { zoomA = fi;            zoomB = zoomDragStart; }
        }
    }

    void mouseReleased() {
        zoomDrag = false;
        seekDrag = false;
    }

    void mouseWheel(int count) {
        if (dropdownSlot >= 0) {
            int maxRows = max(4, (gh - dropdownY - 6) / ROW_H);
            int visRows = min(maxRows, DD_ITEM_COUNT);
            dropdownScroll = constrain(dropdownScroll + count, 0, max(0, DD_ITEM_COUNT - visRows));
        }
    }

    // ── Export merged CSV over the current zoom range ────────────────────────
    void exportMerged(String path, DataSource ds, BoatSource dsBoat, SyncMap sync) {
        int n = ds.frameCount();
        if (n == 0) { println("Export skipped: no paddle data"); return; }
        int a = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int b = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        PrintWriter pw = createWriter(path);
        pw.println("# PadViz5b export — paddle+boat merged");
        pw.println("pad_idx,pad_ts,pad_roll,pad_pitch,pad_yaw,pad_cpm,pad_stroke,"
                 + "pad_accel_x,pad_accel_y,pad_accel_z,pad_gps_utc,"
                 + "boat_ts,boat_gps_utc,boat_lat,boat_lon,boat_speed_ms,boat_cog_deg,"
                 + "kayak_roll,kayak_pitch,kayak_yaw");

        ArrayList<FrameData>     pf = ds.getFrames();
        ArrayList<BoatFrameData> bf = dsBoat.getFrames();

        for (int pi = a; pi <= b && pi < pf.size(); pi++) {
            FrameData fd = pf.get(pi);
            int bi = sync.boatIdxFor(pi);
            String padCols = pi + "," + fd.ts + ","
                + nf(fd.roll,0,5) + "," + nf(fd.pitch,0,5) + "," + nf(fd.yaw,0,5) + ","
                + nf(fd.cpm,0,3) + "," + fd.strokeCount + ","
                + nf(fd.accelX,0,5) + "," + nf(fd.accelY,0,5) + "," + nf(fd.accelZ,0,5) + ","
                + fd.gpsUtcSec;
            if (bi >= 0 && bi < bf.size()) {
                BoatFrameData bfd = bf.get(bi);
                pw.println(padCols + ","
                    + bfd.ts + "," + bfd.gpsUtcSec + ","
                    + nf(bfd.gpsLat,0,6) + "," + nf(bfd.gpsLon,0,6) + ","
                    + nf(bfd.speedMs,0,4) + "," + nf(bfd.cogDeg,0,2) + ","
                    + nf(bfd.kayakRoll,0,5) + "," + nf(bfd.kayakPitch,0,5) + ","
                    + nf(bfd.kayakYaw,0,5));
            } else {
                pw.println(padCols + ",,,,,,,,,");
            }
        }
        pw.flush();  pw.close();
        println("Exported " + (b - a + 1) + " frames to " + path);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private int frameFromChartX(int mx, DataSource ds) {
        int n = ds.frameCount();
        if (n < 2) return 0;
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;
        float t = constrain((float)(mx - chartX) / max(1, chartW), 0, 1);
        return constrain(viewA + (int)(t * (viewB - viewA)), 0, n - 1);
    }
}
