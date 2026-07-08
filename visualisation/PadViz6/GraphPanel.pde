// GraphPanel — full-width strip along the bottom of the window.
//
// Up to 3 colour-coded traces, each selected from a dropdown of paddle and
// boat fields. Drag on the chart to zoom, drag the yellow cursor line to
// seek. "Full" button clears the zoom. "Cols" button cycles the export
// column set between "curated" and "all-fields" (spec §9). Export writes a
// merged CSV over the current zoom range.
//
// Ported from PadViz5b/GraphPanel.pde. Field-name deltas vs PadViz5b:
//   - PadViz6 BoatFrameData uses roll/pitch/yaw (no kayak-prefix).
//   - PadViz6 FrameData: accel/stroke/cpm fields added in this session so the
//     graph dropdowns line up with the PadViz5b column order.

class GraphPanel {
    int gx, gy, gw, gh;

    // Field definitions — source: 0 = paddle, 1 = boat.
    // See DataSource.FrameData.field() and BoatSource.BoatFrameData.field()
    // for the index mapping on each side.
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

    // Dropdown item 0 = "— none —" (fi=-1), items 1..N = fields 0..N-1.
    int DD_ITEM_COUNT = N_FIELDS + 1;

    static final int N_SLOTS = 3;
    final int[] SLOT_COLS = {color(255, 100, 100), color(100, 220, 100), color(100, 160, 255)};
    int[] slotField = {0, 2, 3};   // default: roll, yaw, CPM

    // Layout constants
    static final int SEL_W  = 220;
    static final int MARGIN = 8;
    static final int ROW_H  = 20;
    static final int BTN_H  = 22;

    // Applied zoom (in paddle frame indices). -1 = full range.
    int zoomA = -1, zoomB = -1;

    // Single-slot zoom history — the (a,b) pair that was active before the
    // current one. Right-double-click swaps between them (ping-pong).
    int prevZoomA = -1, prevZoomB = -1;

    // Pending right-click selection markers. selPendingA is the first right
    // click; when selPendingB is set by the second right click we finalise
    // the zoom and clear both markers.
    int selPendingA = -1;
    int selPendingB = -1;

    // For distinguishing a fresh right-click from a double-right-click.
    int lastRightClickMs   = -100000;
    int lastRightClickPx   = -100000;
    static final int DOUBLE_CLICK_MS = 400;
    static final int DOUBLE_CLICK_PX = 8;    // must click within this many px

    // Dropdown state
    int dropdownSlot   = -1;     // which slot is open (-1 = none)
    int dropdownY;
    int dropdownScroll = 0;

    // Left-drag scrub of the yellow playhead.
    boolean seekDrag = false;

    // Export column set: 0 = curated (default), 1 = all-fields.
    int exportMode = 0;

    // Cached chart geometry (set during draw)
    int chartX, chartY, chartW, chartH;

    GraphPanel(int x, int y, int w, int h) {
        gx = x;  gy = y;  gw = w;  gh = h;
    }

    void setBounds(int x, int y, int w, int h) {
        gx = x;  gy = y;  gw = w;  gh = h;
    }

    // ── Draw ─────────────────────────────────────────────────────────────────
    void draw(DataSource ds, BoatSource dsBoat, SyncMap syncMap, int frameIdx) {
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

        if (ds != null && ds.frameCount() > 1 && chartH > 40) {
            drawChart(ds, dsBoat, syncMap, frameIdx);
        }

        drawFooter(ds);

        // Dropdown on top of everything else
        if (dropdownSlot >= 0) drawDropdown();

        popMatrix();
    }

    // ── Field selector column ────────────────────────────────────────────────
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
        text("Right-click twice to zoom (dbl-rclick reverts)", x, y);
        y += 12;
        text("Left-click chart to move cursor", x, y);
    }

    // ── Chart ────────────────────────────────────────────────────────────────
    void drawChart(DataSource ds, BoatSource dsBoat, SyncMap syncMap, int frameIdx) {
        int n = ds.frameCount();
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        fill(15, 17, 24);  noStroke();  rect(chartX, chartY, chartW, chartH);

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
                if (dsBoat == null || dsBoat.frameCount() == 0) continue;
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
                    int boatIdx = (syncMap == null) ? -1 : syncMap.boatIdxFor(padIdx);
                    BoatFrameData bfd = (boatIdx >= 0 && dsBoat != null)
                        ? dsBoat.frameAt(boatIdx) : null;
                    if (bfd == null) {
                        if (inShape) { endShape(); inShape = false; }
                        continue;
                    }
                    v = bfd.field(subFi);
                }

                float vy = chartY + chartH - map(v, mn, mx, 0, chartH);
                if (!inShape) { beginShape(); inShape = true; }
                vertex(chartX + pxi, vy);
            }
            if (inShape) endShape();
        }

        // Pending click-selection markers (green vertical dashed lines).
        drawSelMarker(selPendingA, viewA, viewB, "A");
        drawSelMarker(selPendingB, viewA, viewB, "B");

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

    // Dashed green vertical line at the given paddle-frame index, with a
    // letter label at the top. Skipped if the frame is out of the current
    // view range or the marker is not set.
    void drawSelMarker(int frameIdx, int viewA, int viewB, String label) {
        if (frameIdx < 0 || frameIdx < viewA || frameIdx > viewB) return;
        float t = (float)(frameIdx - viewA) / max(1, viewB - viewA);
        int mx = chartX + (int)(t * chartW);
        stroke(100, 230, 130, 220);  strokeWeight(1);
        // Dashed line — 6px on, 4px off.
        for (int py = chartY; py < chartY + chartH; py += 10) {
            line(mx, py, mx, min(chartY + chartH, py + 6));
        }
        strokeWeight(1);
        noStroke();  fill(120, 240, 150);
        textSize(11);  textAlign(CENTER, BOTTOM);
        text(label, mx, chartY - 1);
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    void drawFooter(DataSource ds) {
        int fy = gh - MARGIN - 16;

        // Full button
        fill(65);  noStroke();  rect(SEL_W + MARGIN, fy, 40, 16, 3);
        fill(200);  textSize(10);  textAlign(CENTER, CENTER);
        text("Full", SEL_W + MARGIN + 20, fy + 8);

        // Cols toggle button (cycles export column set)
        fill(60, 60, 80);  rect(SEL_W + MARGIN + 46, fy, 90, 16, 3);
        fill(210);
        text("Cols: " + (exportMode == 0 ? "curated" : "all"),
             SEL_W + MARGIN + 46 + 45, fy + 8);

        // Export button
        fill(80, 100, 60);  rect(SEL_W + MARGIN + 142, fy, 60, 16, 3);
        fill(210);  text("Export…", SEL_W + MARGIN + 142 + 30, fy + 8);

        // Zoom range readout
        if (ds != null && ds.frameCount() > 0) {
            int a = (zoomA >= 0) ? zoomA : 0;
            int b = (zoomB >  0) ? zoomB : ds.frameCount() - 1;
            long tA = ds.frameAt(a).ts, tB = ds.frameAt(b).ts;
            fill(120);  textAlign(LEFT, CENTER);
            text(nf(tA/1000.0f,0,1) + "s – " + nf(tB/1000.0f,0,1) + "s  ("
                 + nf((tB-tA)/1000.0f,0,1) + "s)",
                 SEL_W + MARGIN + 208, fy + 8);
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

        textAlign(RIGHT, CENTER);  textSize(11);
        if (dropdownScroll > 0) {
            fill(100, 180, 255);
            text("^", x + w - 4, y + 2 + ROW_H / 2);
        }
        if (dropdownScroll + visRows < DD_ITEM_COUNT) {
            fill(100, 180, 255);
            text("v", x + w - 4, y + pxH - ROW_H / 2);
        }
    }

    // ── Mouse ────────────────────────────────────────────────────────────────
    // mx/my are in panel-local coordinates (gx/gy already subtracted by caller).
    // `button` is Processing's LEFT / RIGHT / CENTER constant.
    // Returns true if the event was consumed by the panel.
    boolean mousePressed(int mx, int my, DataSource ds, int button) {
        if (mx < 0 || my < 0 || mx > gw || my > gh) return false;

        // If dropdown is open, any click routes there (left-click only).
        if (dropdownSlot >= 0) {
            if (button == LEFT && mx >= MARGIN && mx <= SEL_W) {
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
            return true;
        }

        // Slot / footer buttons — left-click only.
        if (button == LEFT) {
            int sy = MARGIN + 14;
            for (int s = 0; s < N_SLOTS; s++) {
                if (mx >= MARGIN && mx <= SEL_W - MARGIN
                    && my >= sy && my < sy + BTN_H) {
                    dropdownSlot   = s;
                    dropdownY      = sy + BTN_H + 2;
                    dropdownScroll = 0;
                    return true;
                }
                sy += BTN_H + 4;
            }

            int fy = gh - MARGIN - 16;
            // Full
            if (my >= fy && my <= fy + 16
                && mx >= SEL_W + MARGIN && mx <= SEL_W + MARGIN + 40) {
                resetZoomToFull();
                return true;
            }
            // Cols toggle
            if (my >= fy && my <= fy + 16
                && mx >= SEL_W + MARGIN + 46 && mx <= SEL_W + MARGIN + 46 + 90) {
                exportMode = 1 - exportMode;
                return true;
            }
            // Export…
            if (my >= fy && my <= fy + 16
                && mx >= SEL_W + MARGIN + 142 && mx <= SEL_W + MARGIN + 142 + 60) {
                selectOutput("Export merged CSV", "exportFileSelected");
                return true;
            }
        }

        // Chart area.
        if (mx >= chartX && mx <= chartX + chartW && my >= chartY && my <= chartY + chartH) {
            int n = ds.frameCount();
            if (n < 2) return true;

            if (button == LEFT) {
                // Cursor scrub — move playhead to click position and pause.
                seekDrag = true;
                setFrameIdx(frameFromChartX(mx, ds));
                setPlaying(false);
                return true;
            }
            if (button == RIGHT) {
                handleRightClickOnChart(mx, ds);
                return true;
            }
        }
        return false;
    }

    // Right-click on the chart.
    //   Idle:      place selPendingA. But if this is a double-click AND
    //              a previous zoom exists, revert to the previous zoom
    //              instead (ping-pong).
    //   Half-set:  place selPendingB, apply zoom, move playhead to zoomA,
    //              clear pending.
    private void handleRightClickOnChart(int mx, DataSource ds) {
        int now = millis();
        boolean fast     = (now - lastRightClickMs) < DOUBLE_CLICK_MS;
        boolean samePlace = abs(mx - lastRightClickPx) <= DOUBLE_CLICK_PX;
        boolean isDouble  = fast && samePlace;
        lastRightClickMs = now;
        lastRightClickPx = mx;

        // A genuine double-right-click (same place, fast) always means REVERT,
        // regardless of whether a pending marker was set by the first click.
        // The first click of the double was a spurious marker placement — we
        // undo it here.
        if (isDouble
            && (prevZoomA >= 0 || prevZoomB >= 0 || zoomA >= 0 || zoomB >= 0)) {
            int tA = zoomA, tB = zoomB;
            zoomA = prevZoomA;  zoomB = prevZoomB;
            prevZoomA = tA;     prevZoomB = tB;
            selPendingA = selPendingB = -1;
            setFrameIdx(zoomA >= 0 ? zoomA : 0);
            setPlaying(false);
            return;
        }

        // Not a double-click. Standard two-click zoom flow.
        if (selPendingA >= 0 && selPendingB < 0) {
            // Second right-click — finalise.
            int f = frameFromChartX(mx, ds);
            if (f != selPendingA) {
                int na = min(selPendingA, f);
                int nb = max(selPendingA, f);
                pushHistoryThen(na, nb);
                setFrameIdx(na);
                setPlaying(false);
            }
            selPendingA = selPendingB = -1;
            return;
        }

        // Idle → place first marker.
        selPendingA = frameFromChartX(mx, ds);
    }

    // Push the current (zoomA, zoomB) into the single-slot history and apply
    // the given new range. Cursor move is done by the caller so the reset case
    // (Full) doesn't jump the playhead.
    private void pushHistoryThen(int newA, int newB) {
        prevZoomA = zoomA;  prevZoomB = zoomB;
        zoomA = newA;       zoomB = newB;
    }

    // Public shortcut: clear zoom to the full range, retaining the previous
    // zoom in history so double-right-click can ping-pong back. Wired to the
    // "S" key from PadViz6.pde and to the Full button.
    void resetZoomToFull() {
        pushHistoryThen(-1, -1);
        selPendingA = selPendingB = -1;
    }

    void mouseDragged(int mx, DataSource ds) {
        if (seekDrag) setFrameIdx(frameFromChartX(mx, ds));
    }

    void mouseReleased() {
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
    // Column sets per spec §9. Called by PadViz6.pde's exportFileSelected
    // callback after selectOutput() returns a path.
    void exportMerged(String path, DataSource ds, BoatSource dsBoat, SyncMap syncMap) {
        if (ds == null || ds.frameCount() == 0) {
            println("Export skipped: no paddle data");
            return;
        }
        int n = ds.frameCount();
        int a = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int b = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;

        PrintWriter pw = createWriter(path);
        pw.println("# PadViz6 export — mode=" + (exportMode == 0 ? "curated" : "all-fields")
                 + "   sync=" + (syncMap != null && syncMap.usedRxMs ? "rx_ms" : "gps_utc"));

        if (exportMode == 0) exportCurated(pw, ds, dsBoat, syncMap, a, b);
        else                 exportAllFields(pw, ds, dsBoat, syncMap, a, b);

        pw.flush();  pw.close();
        println("Exported " + (b - a + 1) + " paddle frames to " + path);
    }

    // Curated (default) — the PadViz5b-compatible column set plus rx_ms.
    private void exportCurated(PrintWriter pw, DataSource ds, BoatSource dsBoat,
                               SyncMap syncMap, int a, int b) {
        pw.println("pad_idx,pad_ts,pad_roll,pad_pitch,pad_yaw,pad_cpm,pad_stroke,"
                 + "pad_accel_x,pad_accel_y,pad_accel_z,pad_rx_ms,pad_gps_utc,"
                 + "boat_ts,boat_rx_ms,boat_gps_utc,"
                 + "boat_lat,boat_lon,boat_speed_ms,boat_cog_deg,"
                 + "kayak_qw,kayak_qx,kayak_qy,kayak_qz,"
                 + "kayak_roll,kayak_pitch,kayak_yaw");

        ArrayList<FrameData>     pf = ds.getFrames();
        ArrayList<BoatFrameData> bf = (dsBoat == null) ? null : dsBoat.getFrames();

        for (int pi = a; pi <= b && pi < pf.size(); pi++) {
            FrameData fd = pf.get(pi);
            String padCols = pi + "," + fd.ts + ","
                + nf(fd.roll,0,5) + "," + nf(fd.pitch,0,5) + "," + nf(fd.yaw,0,5) + ","
                + nf(fd.cpm,0,3) + "," + fd.strokeCount + ","
                + nf(fd.accelX,0,5) + "," + nf(fd.accelY,0,5) + "," + nf(fd.accelZ,0,5) + ","
                + fd.rxMs + "," + fd.gpsUtcSec;
            int bi = (syncMap == null) ? -1 : syncMap.boatIdxFor(pi);
            if (bf != null && bi >= 0 && bi < bf.size()) {
                BoatFrameData bfd = bf.get(bi);
                pw.println(padCols + ","
                    + bfd.ts + "," + bfd.rxMs + "," + bfd.gpsUtcSec + ","
                    + nf(bfd.gpsLat,0,6) + "," + nf(bfd.gpsLon,0,6) + ","
                    + nf(bfd.speedMs,0,4) + "," + nf(bfd.cogDeg,0,2) + ","
                    + nf(bfd.qw,0,5) + "," + nf(bfd.qx,0,5) + ","
                    + nf(bfd.qy,0,5) + "," + nf(bfd.qz,0,5) + ","
                    + nf(bfd.roll,0,5) + "," + nf(bfd.pitch,0,5) + "," + nf(bfd.yaw,0,5));
            } else {
                pw.println(padCols + ",,,,,,,,,,,,,,");
            }
        }
    }

    // All-fields — every column present in both loaded CSVs, unfiltered. When
    // no boat CSV is loaded, boat columns are omitted entirely from the header.
    private void exportAllFields(PrintWriter pw, DataSource ds, BoatSource dsBoat,
                                 SyncMap syncMap, int a, int b) {
        ArrayList<BoatFrameData> bf =
            (dsBoat != null && dsBoat.frameCount() > 0) ? dsBoat.getFrames() : null;
        boolean withBoat = (bf != null);

        String header = "pad_idx,pad_ts,pad_accel_x,pad_accel_y,pad_accel_z,"
                      + "pad_qw,pad_qx,pad_qy,pad_qz,"
                      + "pad_roll,pad_pitch,pad_yaw,pad_stroke,pad_cpm,"
                      + "pad_gps_utc,pad_rx_ms";
        if (withBoat) {
            header += ",boat_ts,boat_gps_utc,boat_lat,boat_lon,boat_speed_ms,"
                    + "boat_cog_deg,boat_gps_fix,"
                    + "kayak_qw,kayak_qx,kayak_qy,kayak_qz,"
                    + "kayak_roll,kayak_pitch,kayak_yaw,boat_rx_ms";
        }
        pw.println(header);

        ArrayList<FrameData> pf = ds.getFrames();

        for (int pi = a; pi <= b && pi < pf.size(); pi++) {
            FrameData fd = pf.get(pi);
            String padCols = pi + "," + fd.ts + ","
                + nf(fd.accelX,0,5) + "," + nf(fd.accelY,0,5) + "," + nf(fd.accelZ,0,5) + ","
                + nf(fd.qw,0,6) + "," + nf(fd.qx,0,6) + "," + nf(fd.qy,0,6) + "," + nf(fd.qz,0,6) + ","
                + nf(fd.roll,0,5) + "," + nf(fd.pitch,0,5) + "," + nf(fd.yaw,0,5) + ","
                + fd.strokeCount + "," + nf(fd.cpm,0,3) + ","
                + fd.gpsUtcSec + "," + fd.rxMs;

            if (!withBoat || bf == null) { pw.println(padCols); continue; }

            int bi = (syncMap == null) ? -1 : syncMap.boatIdxFor(pi);
            if (bi >= 0 && bi < bf.size()) {
                BoatFrameData bfd = bf.get(bi);
                pw.println(padCols + ","
                    + bfd.ts + "," + bfd.gpsUtcSec + ","
                    + nf(bfd.gpsLat,0,6) + "," + nf(bfd.gpsLon,0,6) + ","
                    + nf(bfd.speedMs,0,4) + "," + nf(bfd.cogDeg,0,2) + ","
                    + (bfd.gpsFix ? 1 : 0) + ","
                    + nf(bfd.qw,0,6) + "," + nf(bfd.qx,0,6) + ","
                    + nf(bfd.qy,0,6) + "," + nf(bfd.qz,0,6) + ","
                    + nf(bfd.roll,0,5) + "," + nf(bfd.pitch,0,5) + "," + nf(bfd.yaw,0,5) + ","
                    + bfd.rxMs);
            } else {
                pw.println(padCols + ",,,,,,,,,,,,,,,");
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private int frameFromChartX(int mx, DataSource ds) {
        int n = ds.frameCount();
        if (n < 2) return 0;
        int viewA = (zoomA >= 0 && zoomB > zoomA) ? zoomA : 0;
        int viewB = (zoomB >  0 && zoomB > zoomA) ? zoomB : n - 1;
        float t = constrain((float)(mx - chartX) / max(1, chartW), 0, 1);
        return constrain(viewA + (int)(t * (viewB - viewA)), 0, n - 1);
    }
}
