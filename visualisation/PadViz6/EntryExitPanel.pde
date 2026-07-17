// EntryExitPanel — blade entry/exit scatter (v0.14, spec §13.4).
//
// Occupies the left 20 % of the window, from the top down to the graph
// strip. Top-down boat-frame plot: +X starboard (screen right), +Y forward
// (screen up), kayak outline for scale. One dot per CatchEvent:
//   red  = right blade      green = left blade
//   filled = water entry    hollow ring = exit
// Dots accumulate as the playback cursor passes each event's frame, so a
// play-through builds the pattern and scrubbing back rewinds it.

class EntryExitPanel {
    static final float RANGE_X_M = 1.7f;   // half-range drawn, metres

    final int COL_RIGHT = color(255, 80, 80);
    final int COL_LEFT  = color(80, 220, 100);

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
        textSize(14);  textAlign(LEFT, TOP);
        text("Blade entry / exit", 10, 10);
        textSize(10);
        int ly = 30;
        fill(COL_RIGHT);  ellipse(16, ly + 4, 8, 8);
        fill(200);        text("right entry", 24, ly - 1);
        noFill();  stroke(COL_RIGHT);  strokeWeight(1.5);
        ellipse(16 + w / 2, ly + 4, 8, 8);
        noStroke();  fill(200);  text("right exit", 24 + w / 2, ly - 1);
        ly += 16;
        fill(COL_LEFT);   ellipse(16, ly + 4, 8, 8);
        fill(200);        text("left entry", 24, ly - 1);
        noFill();  stroke(COL_LEFT);  strokeWeight(1.5);
        ellipse(16 + w / 2, ly + 4, 8, 8);
        noStroke();  fill(200);  text("left exit", 24 + w / 2, ly - 1);
        strokeWeight(1);

        // Plot area below the legend, above the status footer.
        int plotTop = ly + 22;
        int plotBot = h - 46;
        int cxp = w / 2;
        int cyp = (plotTop + plotBot) / 2;
        float scale = (w - 26) / (2 * RANGE_X_M);   // px per metre

        // Axes hints.
        stroke(60);
        line(10, cyp, w - 10, cyp);
        line(cxp, plotTop, cxp, plotBot);
        noStroke();
        fill(120);
        textSize(9);
        textAlign(RIGHT, BOTTOM);  text("stbd →", w - 12, cyp - 3);
        textAlign(LEFT,  BOTTOM);  text("fwd ↑",  cxp + 4, plotTop + 12);

        // 1 m grid rings around the cockpit.
        stroke(45);  noFill();
        for (int m = 1; m <= 2; m++) {
            ellipse(cxp, cyp, 2 * m * scale, 2 * m * scale);
        }
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
                float sx = cxp + e.xB * scale;
                float sy = cyp - e.yB * scale;
                if (sy < plotTop || sy > plotBot) continue;
                int col = e.right ? COL_RIGHT : COL_LEFT;
                if (e.entry) {
                    noStroke();  fill(col, 200);
                    ellipse(sx, sy, 7, 7);
                } else {
                    noFill();  stroke(col, 200);  strokeWeight(1.5);
                    ellipse(sx, sy, 7, 7);
                }
                shown++;
            }
        }
        strokeWeight(1);  noStroke();

        // Status footer.
        fill(140);
        textSize(9);
        textAlign(LEFT, TOP);
        if (ce == null) {
            text("no events computed", 10, h - 40);
        } else {
            text(shown + " / " + ce.events.size() + " events shown", 10, h - 40);
            // Wrap the status string across two lines if needed.
            String s = ce.status;
            int cut = s.indexOf(" | heading");
            if (cut > 0) {
                text(s.substring(0, cut), 10, h - 28);
                text(s.substring(cut + 3), 10, h - 16);
            } else {
                text(s, 10, h - 28);
            }
        }
    }
}
