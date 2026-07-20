// StrokeAveragePanel — right-hand mirror of EntryExitPanel (spec §13.8,
// notes 20 Jul 2026).
//
// Plots the average roll trace over each blade's in-water run (the same
// runs CatchEvents builds its entry/exit events from — runStart..runEnd,
// gated by MIN_RUN_S/MAX_RUN_S), separately for left (green) and right
// (red), each stroke resampled to a fixed number of points so runs of
// different length can be averaged together. A run is folded into the
// average once the playback cursor passes its end frame, mirroring how
// EntryExitPanel accumulates dots — so a play-through builds the traces
// and scrubbing back removes strokes again. Right-click resets the
// accumulation from the current playback frame forward; independent of
// the left panel's own right-click reset (each panel only reacts to
// clicks inside its own bounds).
//
// Roll is averaged with a plain arithmetic mean (no wrap handling) —
// matching Sidecar.meanRPYFromFrames' existing convention for roll/pitch,
// since a single stroke's roll swing doesn't cross the +-180 deg wrap.

class StrokeAveragePanel {
    static final int   N_SAMPLES = 40;   // resampled points per stroke
    static final float RANGE_DEG = 80;   // +- half-range on the roll axis

    final int COL_RIGHT = color(255, 80, 80);
    final int COL_LEFT  = color(80, 220, 100);

    // Runs starting before this frame are excluded from the average.
    int resetAtFrame = 0;

    void reset(int atFrame) {
        resetAtFrame = atFrame;
    }

    void draw(CatchEvents ce, DataSource pad, int curFrame) {
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
        textSize(14);  textAlign(LEFT, TOP);
        text("Stroke average (roll)", x0 + 10, 10);
        textSize(9);
        fill(120);
        textAlign(RIGHT, TOP);
        text("R-click: restart", width - 8, 12);
        textAlign(LEFT, TOP);

        textSize(10);
        int ly = 30;
        stroke(COL_RIGHT);  strokeWeight(2);  line(x0 + 10, ly + 4, x0 + 26, ly + 4);
        noStroke();  fill(200);  text("right", x0 + 32, ly - 1);
        stroke(COL_LEFT);   line(x0 + 10 + w / 2, ly + 4, x0 + 26 + w / 2, ly + 4);
        noStroke();  fill(200);  text("left", x0 + 32 + w / 2, ly - 1);
        strokeWeight(1);

        int plotTop = ly + 22;
        int plotBot = h - 46;
        int plotL   = x0 + 14;
        int plotR   = x0 + w - 14;

        // Zero-roll reference line + axis hints.
        int cy = (plotTop + plotBot) / 2;
        stroke(60);
        line(plotL, cy, plotR, cy);
        noStroke();
        fill(120);
        textSize(9);
        textAlign(LEFT, BOTTOM);
        text("stroke phase →", plotL, plotTop - 2);
        textAlign(RIGHT, CENTER);
        text("0°", plotL - 4, cy);

        int nRight = 0, nLeft = 0;
        if (ce != null && pad != null) {
            float[] avgRight = averageTrace(ce.rightRuns, pad, curFrame);
            float[] avgLeft  = averageTrace(ce.leftRuns,  pad, curFrame);
            nRight = countIncluded(ce.rightRuns, curFrame);
            nLeft  = countIncluded(ce.leftRuns,  curFrame);
            if (avgRight != null) drawTrace(avgRight, COL_RIGHT, plotL, plotR, plotTop, plotBot);
            if (avgLeft  != null) drawTrace(avgLeft,  COL_LEFT,  plotL, plotR, plotTop, plotBot);
        }

        fill(140);
        textSize(9);
        textAlign(LEFT, TOP);
        String note = (resetAtFrame > 0) ? ("  (since frame " + resetAtFrame + ")") : "";
        text("right: " + nRight + " strokes" + note, x0 + 10, h - 40);
        text("left:  " + nLeft  + " strokes" + note, x0 + 10, h - 28);
    }

    // Resamples each qualifying run's roll trace to N_SAMPLES points and
    // returns the per-sample mean, or null if no runs qualify yet.
    float[] averageTrace(ArrayList<int[]> runs, DataSource pad, int curFrame) {
        float[] sum = new float[N_SAMPLES];
        int n = 0;
        for (int[] run : runs) {
            int s = run[0], e = run[1];
            if (s < resetAtFrame || e > curFrame || e <= s) continue;
            for (int k = 0; k < N_SAMPLES; k++) {
                float idxF = s + (k / (float) (N_SAMPLES - 1)) * (e - s);
                int   i0   = (int) idxF;
                int   i1   = min(e, i0 + 1);
                float frac = idxF - i0;
                float r0   = pad.frameAt(i0).roll;
                float r1   = pad.frameAt(i1).roll;
                sum[k] += r0 + (r1 - r0) * frac;
            }
            n++;
        }
        if (n == 0) return null;
        float[] avg = new float[N_SAMPLES];
        for (int k = 0; k < N_SAMPLES; k++) avg[k] = sum[k] / n;
        return avg;
    }

    int countIncluded(ArrayList<int[]> runs, int curFrame) {
        int n = 0;
        for (int[] run : runs) {
            if (run[0] >= resetAtFrame && run[1] <= curFrame && run[1] > run[0]) n++;
        }
        return n;
    }

    void drawTrace(float[] avg, int col, int plotL, int plotR, int plotTop, int plotBot) {
        int   cy    = (plotTop + plotBot) / 2;
        float halfH = (plotBot - plotTop) / 2.0f;
        stroke(col);  strokeWeight(2);  noFill();
        beginShape();
        for (int k = 0; k < avg.length; k++) {
            float x = map(k, 0, avg.length - 1, plotL, plotR);
            float y = cy - constrain(avg[k] / RANGE_DEG, -1, 1) * halfH;
            vertex(x, y);
        }
        endShape();
        strokeWeight(1);  noStroke();
    }
}
