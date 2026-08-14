// StrokeAveragePanel — right-hand mirror of EntryExitPanel (spec §13.8,
// notes 20 Jul 2026).
//
// Same top-down boat-frame plot as EntryExitPanel (+X starboard, +Y
// forward, kayak outline for scale), but instead of a dot per event it
// draws ONE averaged curve per blade — the path the blade tip traces
// between its entry and exit point, averaged over every completed
// in-water run (CatchEvents.rightRuns/leftRuns, the same runStart..runEnd
// each pair of entry/exit events is built from). Each run's path is
// resampled to a fixed point count (so runs of different length can be
// averaged together) using CatchEvents.bladeXY(frame, rightBlade), which
// exposes the same boat-frame position formula addEventIfLoud() uses for
// a single event frame, at any frame in the run.
//
// A run is folded into the average once the playback cursor passes its
// end frame, mirroring EntryExitPanel's dot accumulation — so a
// play-through builds the curve and scrubbing back removes strokes
// again. Right-click resets the accumulation from the current playback
// frame; independent of the left panel's own right-click reset (each
// panel only reacts to clicks inside its own bounds). Filled dot marks
// the averaged entry point, hollow ring the averaged exit point — same
// convention as EntryExitPanel.

class StrokeAveragePanel {
    static final int   N_SAMPLES = 24;   // resampled points per stroke path
    // Scale is fitted to the plot HEIGHT (kayak length) rather than the narrow
    // panel width, so the tall panel is filled instead of drawing a tiny plot
    // in the middle (23 Jul 2026). Capped so at least ±MIN_HALF_X_M across
    // still fits horizontally.
    static final float VIEW_HALF_LEN_M = 2.45f; // kayak half-length + margin
    static final float MIN_HALF_X_M    = 1.0f;  // min stbd/port half-range kept

    final int COL_RIGHT = color(255, 80, 80);
    final int COL_LEFT  = color(80, 220, 100);

    // Runs starting before this frame are excluded from the average.
    int resetAtFrame = 0;

    // 'o' toggles this: mirror the right blade path about the Y (fore-aft)
    // axis and overlay it on the left path, so left/right asymmetry shows as a
    // gap between the two curves instead of two separate side plots.
    boolean mirrorOverlay = false;

    void reset(int atFrame) {
        resetAtFrame = atFrame;
    }

    void toggleMirror() {
        mirrorOverlay = !mirrorOverlay;
    }

    void draw(CatchEvents ce, int curFrame) {
        int w = rightPanelWidth();
        if (w <= 0) return;
        int h  = height - GRAPH_H;
        int x0 = width - w;

        noStroke();
        fill(24, 26, 33);
        rect(x0, 0, w, h);
        stroke(70);
        line(x0, 0, x0, h);
        noStroke();

        fill(200, 220, 255);
        textSize(18);  textAlign(LEFT, TOP);
        text("Blade path (avg)", x0 + 10, 10);
        textSize(12);
        textAlign(RIGHT, TOP);
        fill(120);
        text("R-click: restart", width - 8, 12);
        fill(mirrorOverlay ? color(255, 200, 120) : color(120));
        text("o: mirror " + (mirrorOverlay ? "ON" : "off"), width - 8, 28);
        textAlign(LEFT, TOP);
        textSize(13);
        int ly = 40;
        fill(COL_RIGHT);  ellipse(x0 + 18, ly + 5, 10, 10);
        fill(200);        text("right", x0 + 28, ly - 1);
        fill(COL_LEFT);   ellipse(x0 + 18 + w / 2, ly + 5, 10, 10);
        fill(200);        text("left", x0 + 28 + w / 2, ly - 1);

        // Plot area below the legend, above the status footer — same
        // layout constants as EntryExitPanel.
        int plotTop = ly + 26;
        int plotBot = h - 54;
        int cxp = x0 + w / 2;
        int cyp = (plotTop + plotBot) / 2;
        // Fit the kayak length to the plot height (fills the tall panel), but
        // don't zoom so far that the horizontal blade range overflows.
        float scale = min((plotBot - plotTop) / (2 * VIEW_HALF_LEN_M),
                          (w - 12)            / (2 * MIN_HALF_X_M));

        stroke(60);
        line(x0 + 10, cyp, x0 + w - 10, cyp);
        line(cxp, plotTop, cxp, plotBot);
        noStroke();
        fill(120);
        textSize(11);
        textAlign(RIGHT, BOTTOM);  text("stbd →", x0 + w - 12, cyp - 3);
        textAlign(LEFT,  BOTTOM);  text("fwd ↑",  cxp + 4, plotTop + 13);

        // 0.5 m / 1 m grid rings around the cockpit.
        stroke(45);  noFill();
        ellipse(cxp, cyp, 1.0f * scale, 1.0f * scale);   // 0.5 m radius
        ellipse(cxp, cyp, 2.0f * scale, 2.0f * scale);   // 1.0 m radius
        noStroke();

        // Kayak outline — same shape/scale as EntryExitPanel.
        stroke(90, 110, 140);  strokeWeight(1.5);  noFill();
        float halfBeam = 0.30f * scale;
        float halfLen  = 2.30f * scale;
        beginShape();
        vertex(cxp, cyp - halfLen);
        bezierVertex(cxp + halfBeam, cyp - halfLen * 0.45f,
                     cxp + halfBeam, cyp + halfLen * 0.45f,
                     cxp, cyp + halfLen);
        bezierVertex(cxp - halfBeam, cyp + halfLen * 0.45f,
                     cxp - halfBeam, cyp - halfLen * 0.45f,
                     cxp, cyp - halfLen);
        endShape();
        ellipse(cxp, cyp, 0.5f * scale, 0.9f * scale);
        strokeWeight(1);  noStroke();

        // Red bow marker — a filled triangle at the bow tip (points forward /
        // up), matching EntryExitPanel, so the boat's front is unambiguous.
        fill(230, 40, 40);  noStroke();
        float bowY = cyp - halfLen;
        triangle(cxp, bowY, cxp - 12, bowY + 26, cxp + 12, bowY + 26);

        int nRight = 0, nLeft = 0;
        if (ce != null) {
            nRight = countIncluded(ce.rightRuns, curFrame);
            nLeft  = countIncluded(ce.leftRuns,  curFrame);
            float[][] pathRight = averagePath(ce.rightRuns, ce, curFrame, true);
            float[][] pathLeft  = averagePath(ce.leftRuns,  ce, curFrame, false);
            // In mirror mode the right path is reflected about the Y axis so it
            // lands on top of the left path (draw left first, mirrored-right on
            // top). Otherwise each blade plots on its own side.
            if (pathLeft  != null) drawPath(pathLeft,  COL_LEFT,  cxp, cyp, scale, plotTop, plotBot, false);
            if (pathRight != null) drawPath(pathRight, COL_RIGHT, cxp, cyp, scale, plotTop, plotBot, mirrorOverlay);
        }

        // Footer: per-blade stroke count + averaged entry→exit time and
        // straight-line distance, colour-coded to match the paths.
        float[] statR = (ce != null) ? strokeStats(ce.rightRuns, ce, curFrame, true)  : null;
        float[] statL = (ce != null) ? strokeStats(ce.leftRuns,  ce, curFrame, false) : null;

        textSize(12);  textAlign(LEFT, TOP);
        fill(COL_RIGHT);  text(statLine("right", nRight, statR), x0 + 10, h - 48);
        fill(COL_LEFT);   text(statLine("left",  nLeft,  statL), x0 + 10, h - 32);
        if (resetAtFrame > 0) {
            fill(120);  textSize(10);
            text("(averaged since frame " + resetAtFrame + ")", x0 + 10, h - 16);
        }
    }

    // "right: 4 strokes   1.23 s   0.85 m" — time/distance omitted until at
    // least one stroke is in the average.
    String statLine(String label, int n, float[] stat) {
        String s = label + ": " + n + (n == 1 ? " stroke" : " strokes");
        if (stat != null) s += String.format("   %.2f s   %.2f m", stat[0], stat[1]);
        return s;
    }

    // Average entry→exit time (s) and straight-line entry→exit distance (m,
    // boat-frame) over the same qualifying runs averagePath() uses. Time comes
    // from the paddle-frame timestamps at run start/end; distance is the gap
    // between the entry and exit blade positions. null if no runs qualify yet.
    float[] strokeStats(ArrayList<int[]> runs, CatchEvents ce, int curFrame, boolean rightBlade) {
        if (paddleData == null || paddleData.frameCount() == 0) return null;
        int last = paddleData.frameCount() - 1;
        float sumT = 0, sumD = 0;
        int n = 0;
        for (int[] run : runs) {
            int s = run[0], e = run[1];
            if (s < resetAtFrame || e > curFrame || e <= s || s < 0 || e > last) continue;
            sumT += (paddleData.frameAt(e).ts - paddleData.frameAt(s).ts) / 1000.0f;
            float[] p0 = ce.bladeXY(s, rightBlade);
            float[] p1 = ce.bladeXY(e, rightBlade);
            sumD += dist(p0[0], p0[1], p1[0], p1[1]);
            n++;
        }
        if (n == 0) return null;
        return new float[]{ sumT / n, sumD / n };
    }

    // Resamples each qualifying run's blade path to N_SAMPLES points
    // (linear interpolation, per-frame boat-frame XY from
    // CatchEvents.bladeXY()) and returns the per-sample mean path, or
    // null if no runs qualify yet.
    float[][] averagePath(ArrayList<int[]> runs, CatchEvents ce, int curFrame, boolean rightBlade) {
        float[] sumX = new float[N_SAMPLES];
        float[] sumY = new float[N_SAMPLES];
        int n = 0;
        for (int[] run : runs) {
            int s = run[0], e = run[1];
            if (s < resetAtFrame || e > curFrame || e <= s) continue;
            for (int k = 0; k < N_SAMPLES; k++) {
                float idxF = s + (k / (float) (N_SAMPLES - 1)) * (e - s);
                int   i0   = (int) idxF;
                int   i1   = min(e, i0 + 1);
                float frac = idxF - i0;
                float[] p0 = ce.bladeXY(i0, rightBlade);
                float[] p1 = ce.bladeXY(i1, rightBlade);
                sumX[k] += p0[0] + (p1[0] - p0[0]) * frac;
                sumY[k] += p0[1] + (p1[1] - p0[1]) * frac;
            }
            n++;
        }
        if (n == 0) return null;
        float[][] avg = new float[N_SAMPLES][2];
        for (int k = 0; k < N_SAMPLES; k++) {
            avg[k][0] = sumX[k] / n;
            avg[k][1] = sumY[k] / n;
        }
        return avg;
    }

    int countIncluded(ArrayList<int[]> runs, int curFrame) {
        int n = 0;
        for (int[] run : runs) {
            if (run[0] >= resetAtFrame && run[1] <= curFrame && run[1] > run[0]) n++;
        }
        return n;
    }

    void drawPath(float[][] path, int col, int cxp, int cyp, float scale, int plotTop, int plotBot, boolean mirrorX) {
        float mx = mirrorX ? -1 : 1;   // reflect about the Y (fore-aft) axis
        stroke(col);  strokeWeight(2);  noFill();
        beginShape();
        for (float[] p : path) {
            float sx = cxp + mx * p[0] * scale;
            float sy = cyp - p[1] * scale;
            vertex(sx, sy);
        }
        endShape();
        strokeWeight(1);

        // Endpoint markers — filled = averaged entry, hollow = averaged
        // exit, matching EntryExitPanel's convention.
        float[] pStart = path[0];
        float[] pEnd   = path[path.length - 1];
        float sx0 = cxp + mx * pStart[0] * scale, sy0 = cyp - pStart[1] * scale;
        float sx1 = cxp + mx * pEnd[0]   * scale, sy1 = cyp - pEnd[1]   * scale;
        if (sy0 >= plotTop && sy0 <= plotBot) {
            noStroke();  fill(col, 220);
            ellipse(sx0, sy0, 8, 8);
        }
        if (sy1 >= plotTop && sy1 <= plotBot) {
            noFill();  stroke(col, 220);  strokeWeight(1.5);
            ellipse(sx1, sy1, 8, 8);
            strokeWeight(1);
        }
        noStroke();
    }
}
