// EntryExitPanel — blade entry/exit scatter (v0.14, spec §13.4).
//
// Occupies the left 20 % of the window, from the top down to the graph
// strip. Top-down boat-frame plot: +X starboard (screen right), +Y forward
// (screen up), kayak outline for scale. One dot per CatchEvent:
//   red  = right blade      green = left blade
//   filled = water entry    hollow ring = exit
// Dots accumulate as the playback cursor passes each event's frame, so a
// play-through builds the pattern and scrubbing back rewinds it. Right-
// click anywhere in the panel clears the accumulated dots (notes 20 Jul
// 2026) — events before the click's playback frame are hidden until the
// panel is cleared again or a new CSV/sidecar is loaded.

class EntryExitPanel {
    // Scale is fitted to the plot HEIGHT (kayak length) rather than the narrow
    // panel width, so the tall panel is filled instead of a tiny central plot
    // (23 Jul 2026). Capped so at least ±MIN_HALF_X_M across still fits.
    static final float VIEW_HALF_LEN_M = 2.45f; // kayak half-length + margin
    static final float MIN_HALF_X_M    = 1.0f;  // min stbd/port half-range kept

    final int COL_RIGHT = color(255, 80, 80);
    final int COL_LEFT  = color(80, 220, 100);

    // Events with padFrame < clearAtFrame are hidden — set by clear().
    int clearAtFrame = 0;

    void clear(int atFrame) {
        clearAtFrame = atFrame;
    }

    void draw(CatchEvents ce, int curFrame) {
        int w = leftPanelWidth();
        if (w <= 0) return;
        int h = height - GRAPH_H;

        // Background + right border.
        noStroke();
        fill(24, 26, 33);
        rect(0, 0, w, h);
        stroke(70);
        line(w - 1, 0, w - 1, h);
        noStroke();

        // Title + legend.
        fill(200, 220, 255);
        textSize(18);  textAlign(LEFT, TOP);
        text("Blade entry / exit", 10, 10);
        textSize(11);
        fill(120);
        textAlign(RIGHT, TOP);
        text("R-click: clear", w - 8, 12);
        textAlign(LEFT, TOP);
        textSize(13);
        int ly = 42;
        fill(COL_RIGHT);  ellipse(18, ly + 5, 10, 10);
        fill(200);        text("right entry", 28, ly - 1);
        noFill();  stroke(COL_RIGHT);  strokeWeight(1.5);
        ellipse(18 + w / 2, ly + 5, 10, 10);
        noStroke();  fill(200);  text("right exit", 28 + w / 2, ly - 1);
        ly += 20;
        fill(COL_LEFT);   ellipse(18, ly + 5, 10, 10);
        fill(200);        text("left entry", 28, ly - 1);
        noFill();  stroke(COL_LEFT);  strokeWeight(1.5);
        ellipse(18 + w / 2, ly + 5, 10, 10);
        noStroke();  fill(200);  text("left exit", 28 + w / 2, ly - 1);
        strokeWeight(1);

        // Plot area below the legend, above the status footer.
        int plotTop = ly + 26;
        int plotBot = h - 54;
        int cxp = w / 2;
        int cyp = (plotTop + plotBot) / 2;
        // Fit the kayak length to the plot height (fills the tall panel), but
        // don't zoom so far that the horizontal blade range overflows.
        float scale = min((plotBot - plotTop) / (2 * VIEW_HALF_LEN_M),
                          (w - 12)            / (2 * MIN_HALF_X_M));

        // Axes hints.
        stroke(60);
        line(10, cyp, w - 10, cyp);
        line(cxp, plotTop, cxp, plotBot);
        noStroke();
        fill(120);
        textSize(11);
        textAlign(RIGHT, BOTTOM);  text("stbd →", w - 12, cyp - 3);
        textAlign(LEFT,  BOTTOM);  text("fwd ↑",  cxp + 4, plotTop + 13);

        // 0.5 m / 1 m grid rings around the cockpit.
        stroke(45);  noFill();
        ellipse(cxp, cyp, 1.0f * scale, 1.0f * scale);   // 0.5 m radius
        ellipse(cxp, cyp, 2.0f * scale, 2.0f * scale);   // 1.0 m radius
        noStroke();

        // Kayak outline — 0.6 m beam, 4.6 m length, bow up. Pure scale cue.
        stroke(90, 110, 140);  strokeWeight(1.5);  noFill();
        float halfBeam = 0.30f * scale;
        float halfLen  = 2.30f * scale;
        beginShape();
        vertex(cxp, cyp - halfLen);                       // bow
        bezierVertex(cxp + halfBeam, cyp - halfLen * 0.45f,
                     cxp + halfBeam, cyp + halfLen * 0.45f,
                     cxp, cyp + halfLen);                 // stern
        bezierVertex(cxp - halfBeam, cyp + halfLen * 0.45f,
                     cxp - halfBeam, cyp - halfLen * 0.45f,
                     cxp, cyp - halfLen);
        endShape();
        // Cockpit at origin.
        ellipse(cxp, cyp, 0.5f * scale, 0.9f * scale);
        strokeWeight(1);  noStroke();

        // Events up to the playback cursor.
        int shown = 0;
        if (ce != null) {
            for (CatchEvent e : ce.events) {
                if (e.padFrame > curFrame) break;   // sorted by frame
                if (e.padFrame < clearAtFrame) continue;   // cleared by R-click
                float sx = cxp + e.xB * scale;
                float sy = cyp - e.yB * scale;
                if (sy < plotTop || sy > plotBot) continue;
                int col = e.right ? COL_RIGHT : COL_LEFT;
                if (e.entry) {
                    noStroke();  fill(col, 200);
                    ellipse(sx, sy, 9, 9);
                } else {
                    noFill();  stroke(col, 200);  strokeWeight(1.5);
                    ellipse(sx, sy, 9, 9);
                }
                shown++;
            }
        }
        strokeWeight(1);  noStroke();

        // Status footer.
        fill(140);
        textSize(11);
        textAlign(LEFT, TOP);
        if (ce == null) {
            text("no events computed", 10, h - 44);
        } else {
            String clearNote = (clearAtFrame > 0) ? ("  (cleared @" + clearAtFrame + ")") : "";
            text(shown + " / " + ce.events.size() + " events shown" + clearNote, 10, h - 48);
            // Wrap the status string across two lines if needed.
            String s = ce.status;
            int cut = s.indexOf(" | heading");
            if (cut > 0) {
                text(s.substring(0, cut), 10, h - 32);
                text(s.substring(cut + 3), 10, h - 16);
            } else {
                text(s, 10, h - 32);
            }
        }
    }
}
