// GraphPanel — full-width graph across the bottom third of the screen.
//
// Up to 3 coloured traces, each from a field selector dropdown.
// Supports zoom (drag on chart), cursor seek, field change at any zoom level,
// and export of the zoomed region to a merged CSV.

class GraphPanel {
    int gx, gy, gw, gh;

    // ── Field definitions ─────────────────────────────────────────────────────
    // Source prefix: 0 = paddle (ImuLog), 1 = boat (BoatLog)
    static final int N_FIELDS = 13;
    final String[] FIELD_NAMES = {
        "Pad: roll", "Pad: pitch", "Pad: yaw", "Pad: CPM", "Pad: strokeCount",
        "Pad: accel_x", "Pad: accel_y", "Pad: accel_z",
        "Boat: kayak_roll", "Boat: kayak_pitch", "Boat: kayak_yaw",
        "Boat: speed_ms", "Boat: cog_deg"
    };
    // Map field index → {source (0=pad,1=boat), subField}
    final int[][] FIELD_MAP = {
        {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6},{0,7},
        {1,0},{1,1},{1,2},{1,3},{1,4}
    };

    static final int N_SLOTS = 3;
    final int[] SLOT_COLS = {color(255, 100, 100), color(100, 220, 100), color(100, 160, 255)};
    int[] slotField = {0, 2, 3};   // default: roll, yaw, CPM

    // ── Layout ────────────────────────────────────────────────────────────────
    static final int SEL_W    = 220;   // width of left field-selector panel
    static final int MARGIN   = 8;
    static final int ROW_H    = 20;
    static final int BTN_H    = 22;

    // ── Zoom state (in paddle frame indices) ──────────────────────────────────
    int     zoomA = -1, zoomB = -1;

    // ── Dropdown state ────────────────────────────────────────────────────────
    int  dropdownSlot    = -1;   // which slot is open (-1 = none)
    int  dropdownX, dropdownY;

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

        // Zoom footer buttons
        drawFooter(ds);

        // Draw open dropdown on top of everything else
        if (dropdownSlot >= 0) drawDropdown();

        popMatrix();
    }

    // ── Field selector ────────────────────────────────────────────────────────
    void drawFieldSelector() {
        int x = MARGIN, y = MARGIN;

        fill(50);  textSize(10);  textAlign(LEFT, TOP);
        fill(150);  text("Fields  (click slot to change)", x, y);
        y += 14;

        for (int s = 0; s < N_SLOTS; s++) {
            int fi = slotField[s];
            fill(SLOT_COLS[s]);  noStroke();
            rect(x, y, SEL_W - MARGIN, BTN_H, 3);
            fill(20);  textSize(11);  textAlign(LEFT, CENTER);
            String lbl = (fi >= 0 && fi < N_FIELDS) ? FIELD_NAMES[fi] : "— none —";
            text(lbl, x + 6, y + BTN_H / 2);
            y += BTN_H + 4;
        }

        // Zoom info
        y += 4;
        fill(100);  textSize(10);  textAlign(LEFT, TOP);
        text("Drag chart to zoom · click cursor to seek", x, y);
    }

    // ── Chart ─────────────────────────────────────────────────────────────────
    void drawChart(DataSource ds, BoatSource dsBoat, SyncMap sync, int frameIdx) {
        int n = ds.frameCount();
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        fill(15, 17, 24);  noStroke();  rect(chartX, chartY, chartW, chartH);

        // Traces — compute combined range per slot for Y scaling
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
        int   curX  = chartX + (int)(curT * chartW);
        stroke(255, 255, 100, 200);  strokeWeight(2);
        line(curX, chartY, curX, chartY + chartH);
        strokeWeight(1);

        // Time axis labels
        fill(100);  textSize(10);
        FrameData fA = ds.frameAt(viewA), fB = ds.frameAt(viewB);
        textAlign(LEFT,  TOP);  text(nf(fA.ts / 1000.0f, 0, 1) + "s", chartX, chartY + chartH + 1);
        textAlign(RIGHT, TOP);  text(nf(fB.ts / 1000.0f, 0, 1) + "s", chartX + chartW, chartY + chartH + 1);
    }

    // ── Footer ────────────────────────────────────────────────────────────────
    void drawFooter(DataSource ds) {
        int fy = gh - MARGIN - 16;
        // "Full" button
        fill(65);  noStroke();  rect(SEL_W + MARGIN, fy, 40, 16, 3);
        fill(200);  textSize(10);  textAlign(CENTER, CENTER);
        text("Full", SEL_W + MARGIN + 20, fy + 8);

        // Zoom range text
        if (ds.frameCount() > 0) {
            int a = (zoomA >= 0) ? zoomA : 0;
            int b = (zoomB >  0) ? zoomB : ds.frameCount() - 1;
            long tA = ds.frameAt(a).ts, tB = ds.frameAt(b).ts;
            fill(120);  textAlign(LEFT, CENTER);
            text(nf(tA/1000.0f,0,1) + "s – " + nf(tB/1000.0f,0,1) + "s  ("
                 + nf((tB-tA)/1000.0f,0,1) + "s)",
                 SEL_W + MARGIN + 48, fy + 8);
        }
    }

    // ── Dropdown ─────────────────────────────────────────────────────────────
    void drawDropdown() {
        int x = MARGIN, y = dropdownY;
        int w = SEL_W - MARGIN, rh = ROW_H;
        fill(45, 48, 60);  stroke(90);  strokeWeight(1);
        rect(x, y, w, N_FIELDS * rh + 4, 3);

        for (int fi = 0; fi < N_FIELDS; fi++) {
            int ry = y + 2 + fi * rh;
            boolean sel = slotField[dropdownSlot] == fi;
            fill(sel ? SLOT_COLS[dropdownSlot] : color(55, 58, 72));
            noStroke();  rect(x + 2, ry, w - 4, rh - 2, 2);
            fill(sel ? 20 : 200);  textSize(10);  textAlign(LEFT, CENTER);
            text(FIELD_NAMES[fi], x + 8, ry + rh / 2);
        }
    }

    // ── Export merged CSV ─────────────────────────────────────────────────────
    void exportMerged(String path, DataSource ds, BoatSource dsBoat, SyncMap sync) {
        int n = ds.frameCount();
        int a = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int b = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        PrintWriter pw = createWriter(path);
        pw.println("# PadViz5 export — paddle+boat merged");
        pw.println("pad_seq,pad_ts,pad_roll,pad_pitch,pad_yaw,pad_cpm,pad_stroke,"
                 + "pad_accel_x,pad_accel_y,pad_accel_z,pad_gps_utc,"
                 + "boat_ts,boat_gps_utc,boat_lat,boat_lon,boat_speed_ms,boat_cog,"
                 + "kayak_roll,kayak_pitch,kayak_yaw");

        ArrayList<FrameData>     pf = ds.getFrames();
        ArrayList<BoatFrameData> bf = dsBoat.getFrames();

        for (int pi = a; pi <= b && pi < pf.size(); pi++) {
            FrameData fd = pf.get(pi);
            int bi = sync.boatIdxFor(pi);
            if (bi >= 0 && bi < bf.size()) {
                BoatFrameData bfd = bf.get(bi);
                pw.println(pi + "," + fd.ts + ","
                    + nf(fd.roll,0,5) + "," + nf(fd.pitch,0,5) + "," + nf(fd.yaw,0,5) + ","
                    + nf(fd.cpm,0,3) + "," + fd.strokeCount + ","
                    + nf(fd.accelX,0,5) + "," + nf(fd.accelY,0,5) + "," + nf(fd.accelZ,0,5) + ","
                    + fd.gpsUtcSec + ","
                    + bfd.ts + "," + bfd.gpsUtcSec + ","
                    + nf(bfd.gpsLat,0,6) + "," + nf(bfd.gpsLon,0,6) + ","
                    + nf(bfd.speedMs,0,4) + "," + nf(bfd.cogDeg,0,2) + ","
                    + nf(bfd.kayakRoll,0,5) + "," + nf(bfd.kayakPitch,0,5) + "," + nf(bfd.kayakYaw,0,5));
            } else {
                // No boat data for this paddle frame
                pw.println(pi + "," + fd.ts + ","
                    + nf(fd.roll,0,5) + "," + nf(fd.pitch,0,5) + "," + nf(fd.yaw,0,5) + ","
                    + nf(fd.cpm,0,3) + "," + fd.strokeCount + ","
                    + nf(fd.accelX,0,5) + "," + nf(fd.accelY,0,5) + "," + nf(fd.accelZ,0,5) + ","
                    + fd.gpsUtcSec + ",,,,,,,,,");
            }
        }
        pw.flush();  pw.close();
        println("Exported " + (b - a + 1) + " frames to " + path);
    }

    // ── Mouse ─────────────────────────────────────────────────────────────────
    void mousePressed(int mx, int my, DataSource ds) {
        // Close dropdown on any click
        if (dropdownSlot >= 0) {
            // Check if clicking inside the dropdown
            if (mx >= MARGIN && mx <= SEL_W && my >= dropdownY) {
                int fi = (my - dropdownY - 2) / ROW_H;
                if (fi >= 0 && fi < N_FIELDS) {
                    slotField[dropdownSlot] = fi;
                }
            }
            dropdownSlot = -1;
            return;
        }

        // Slot buttons: open dropdown
        int sy = MARGIN + 14;
        for (int s = 0; s < N_SLOTS; s++) {
            if (mx >= MARGIN && mx <= SEL_W - MARGIN
                && my >= sy && my < sy + BTN_H) {
                dropdownSlot = s;
                dropdownX    = MARGIN;
                dropdownY    = sy + BTN_H + 2;
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

        // Chart: seek or start zoom drag
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
