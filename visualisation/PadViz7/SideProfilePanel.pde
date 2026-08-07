// SideProfilePanel — full-window ZY-plane (side-on) blade-immersion analysis
// (v0.22, spec §14.9). Toggled with x (F2 alt); an ALTERNATIVE to the main 3D
// visualisation, not an overlay drawn on top of it: while shown, draw() skips
// the 3D scene, the left/right analysis panels, the HUD, the axis compass and
// the legend (same screen-owning gate the setup Wizard uses), keeping only the
// bottom graph strip so playback can still be scrubbed.
//
// The window is split horizontally into two side-profile views of the boat
// (Y = fore/aft along the hull, Z = height), each showing ONE blade seen
// edge-on down the boat's across-boat (X) axis:
//
//   TOP    — LEFT blade,  viewed from the port side      (looking +X, from −X)
//   BOTTOM — RIGHT blade, viewed from the starboard side (looking −X, from +X)
//
// The two views look at the boat from opposite sides, so +Y (bow) falls on
// opposite screen sides in each — which is why the bow is marked in RED on both:
// it removes the left/right ambiguity when comparing them.
//
// Each view draws:
//   - a BLUE waterline = mean blade-TIP height at that blade's catch (entry)
//     events, over the whole file (the tip is the leading edge that breaks the
//     surface first — spec §14.9). Static, so the view doesn't jump.
//   - a kayak side silhouette anchored to that waterline, bow tip in RED;
//   - the paddle BLADE drawn as a 32 cm segment (CatchEvents.bladeSegmentYZ) —
//     RED for the right blade, YELLOW for the left — at the live playback frame
//     (bold), plus faintly at each completed stroke's deepest point, so the
//     depth of immersion of every stroke is visible at a glance;
//   - a footer: stroke count, average and max immersion depth below the water.
//
// The vertical scale is FIXED (Z_TOP_M..Z_BOT_M, metres vs the hands/shaft
// centre), not fitted to the data, so the panels keep a constant height and
// don't resize as strokes accumulate. Fore/aft (Y) is drawn to a fixed scale
// that fits the whole kayak length across the width, so the two axes have
// different px/metre — both carry metre tick labels to make the scales explicit
// (the boat silhouette is a scale / orientation reference, not a metric hull).

class SideProfilePanel {
    boolean shown = false;

    static final float VIEW_HALF_LEN_M = 2.45f;  // kayak half-length + margin (Y)
    static final float Z_TOP_M         = 0.45f;  // fixed vertical window, top (vs hands)
    static final float Z_BOT_M         = -1.30f; // fixed vertical window, bottom
    static final float HULL_ABOVE_WL_M = 0.22f;  // deck height above waterline (ref)
    static final float HULL_BELOW_WL_M = 0.22f;  // hull depth below waterline (ref)
    static final float DEFAULT_WL_M    = -0.55f; // fallback waterline if no catches

    final int COL_RIGHT = color(235, 60, 60);    // right blade — red
    final int COL_LEFT  = color(240, 210, 40);   // left blade  — yellow
    final int COL_WATER = color(70, 130, 255);   // waterline   — blue
    final int COL_BOW   = color(255, 60, 60);    // bow marker  — red

    // Strokes starting before this frame are excluded from the faint history
    // (right-click restart). The waterline stays whole-file for stability.
    int resetAtFrame = 0;

    void toggle() { shown = !shown; }
    void reset(int atFrame) { resetAtFrame = atFrame; }

    void draw(CatchEvents ce, int curFrame) {
        int H = height - GRAPH_H;             // area above the graph strip
        int half = H / 2;

        noStroke();
        fill(18, 20, 26);
        rect(0, 0, width, H);

        boolean ready = (ce != null && ce.uzTip != null && ce.phi != null);

        // TOP: left blade, port-side view (looking +X from −X) → bow (+Y) on the
        // LEFT of the screen, so yDir = −1.
        drawHalf(ce, curFrame, ready, 0,    half, false, -1,
                 "LEFT blade — view from PORT  (looking +X)", COL_LEFT);
        // BOTTOM: right blade, starboard-side view (looking −X from +X) → bow
        // (+Y) on the RIGHT, so yDir = +1.
        drawHalf(ce, curFrame, ready, half, half, true,  +1,
                 "RIGHT blade — view from STARBOARD  (looking −X)", COL_RIGHT);

        // Divider between the two halves (drawn last so nothing bleeds across).
        stroke(90);  strokeWeight(1.5);
        line(0, half, width, half);
        strokeWeight(1);  noStroke();
    }

    // Draw one side-profile view into the rect (0, y0, width, hh).
    //  rightBlade — which blade this view shows.
    //  yDir       — screen-x direction of +Y (bow): −1 = bow left, +1 = bow right.
    void drawHalf(CatchEvents ce, int curFrame, boolean ready,
                  int y0, int hh, boolean rightBlade, int yDir,
                  String title, int bladeCol) {
        final int MARGIN_X = 70;
        final int TOP_PAD   = 44;   // room for the title
        final int BOT_PAD   = 30;   // room for the axis labels / footer
        int plotTop = y0 + TOP_PAD;
        int plotBot = y0 + hh - BOT_PAD;
        int cx      = width / 2;

        // Fore/aft: fixed scale that fits the whole kayak length across width.
        float scaleY = (width - 2 * MARGIN_X) / (2 * VIEW_HALF_LEN_M);

        // Title.
        fill(200, 220, 255);  textAlign(LEFT, TOP);  textSize(17);
        text(title, MARGIN_X, y0 + 12);

        if (!ready) {
            fill(150);  textSize(13);
            text("no blade data — load a paddle CSV", MARGIN_X, plotTop + 10);
            return;
        }
        int last = paddleData.frameCount() - 1;

        // Waterline (metres vs hands) = mean blade-TIP height at this blade's
        // catch (entry) events over the WHOLE file — the tip is what enters
        // first. Whole-file (not accumulated to the cursor) so the blue line is
        // steady rather than creeping as you play.
        float waterM = meanEntryTipZ(ce, rightBlade);

        // Fixed vertical scale — panels keep a constant height, no resize.
        float scaleZ = (plotBot - plotTop) / (Z_TOP_M - Z_BOT_M);

        // Vertical fore/aft grid lines every 1 m.
        stroke(38);  strokeWeight(1);
        for (int m = -2; m <= 2; m++) {
            float gx = cx + yDir * m * scaleY;
            line(gx, plotTop, gx, plotBot);
        }
        // Horizontal height grid every 0.25 m, with metre labels.
        textSize(10);
        for (float zm = ceil(Z_BOT_M * 4) / 4.0f; zm <= Z_TOP_M + 1e-3; zm += 0.25f) {
            float gy = zToScreen(zm, plotTop, plotBot);
            stroke(zm == 0 ? color(70, 90, 70) : color(38));
            line(MARGIN_X, gy, width - MARGIN_X, gy);
            noStroke();  fill(110);  textAlign(RIGHT, CENTER);
            text(nf(zm, 0, 2) + "m", MARGIN_X - 4, gy);
        }
        noStroke();

        // Hands / shaft-centre reference line (z = 0).
        float syFor0 = zToScreen(0, plotTop, plotBot);
        stroke(80, 110, 80);  strokeWeight(1);
        line(MARGIN_X, syFor0, width - MARGIN_X, syFor0);
        noStroke();  fill(120, 160, 120);  textAlign(LEFT, BOTTOM);  textSize(10);
        text("hands (shaft centre)", MARGIN_X + 4, syFor0 - 2);

        // Kayak side silhouette anchored to the waterline, bow in red.
        drawKayakSide(cx, yDir, scaleY, plotTop, plotBot, waterM);

        // Blue waterline (drawn after the hull so it reads on top).
        float syWater = zToScreen(waterM, plotTop, plotBot);
        stroke(COL_WATER);  strokeWeight(2);
        line(MARGIN_X, syWater, width - MARGIN_X, syWater);
        noStroke();  fill(COL_WATER);  textAlign(RIGHT, BOTTOM);  textSize(10);
        text("water (mean catch)", width - MARGIN_X - 4, syWater - 2);

        // Faint blade at each completed stroke's deepest-immersion frame, up to
        // the cursor — so every stroke's max depth is visible stacked together.
        ArrayList<int[]> runs = rightBlade ? ce.rightRuns : ce.leftRuns;
        int nStrokes = 0;  float sumDepth = 0, maxDepth = -1e9;
        if (runs != null) {
            for (int[] run : runs) {
                int s = run[0], e = run[1];
                if (s < resetAtFrame || e > curFrame || e <= s || s < 0 || e > last) continue;
                int di = deepestFrame(ce, s, e, rightBlade);
                drawBlade(ce, di, rightBlade, cx, yDir, scaleY, plotTop, plotBot, bladeCol, 55, 2);
                float depth = waterM - ce.bladeTipZ(di, rightBlade);
                sumDepth += depth;  maxDepth = max(maxDepth, depth);  nStrokes++;
            }
        }

        // Live blade at the playback cursor (bold), red/yellow.
        int liveIdx = constrain(curFrame, 0, last);
        drawBlade(ce, liveIdx, rightBlade, cx, yDir, scaleY, plotTop, plotBot, bladeCol, 255, 4);

        // Fore/aft axis labels — stern ↔ bow along the bottom.
        fill(120);  textSize(10);  textAlign(CENTER, TOP);
        text(yDir < 0 ? "← bow" : "bow →", cx + yDir * 2 * scaleY, plotBot + 4);
        text(yDir < 0 ? "stern →" : "← stern", cx - yDir * 2 * scaleY, plotBot + 4);

        // Footer: strokes + average / max immersion depth below the water.
        fill(bladeCol);  textSize(12);  textAlign(LEFT, TOP);
        String s = (rightBlade ? "right" : "left") + ": " + nStrokes
                   + (nStrokes == 1 ? " stroke" : " strokes");
        if (nStrokes > 0)
            s += String.format("   immersion  avg %.2f m   max %.2f m", sumDepth / nStrokes, maxDepth);
        text(s, MARGIN_X, y0 + hh - BOT_PAD + 14);
    }

    // Draw the 32 cm blade at frame i as a segment throat→tip, clamped to the
    // plot band so it never bleeds into the other half. alpha/weight set the
    // faint-history vs bold-live look.
    void drawBlade(CatchEvents ce, int i, boolean rightBlade,
                   int cx, int yDir, float scaleY, int plotTop, int plotBot,
                   int col, int alpha, float weight) {
        float[] seg = ce.bladeSegmentYZ(i, rightBlade);   // {yThr, zThr, yTip, zTip}
        float sxThr = cx + yDir * seg[0] * scaleY;
        float syThr = zToScreen(seg[1], plotTop, plotBot);
        float sxTip = cx + yDir * seg[2] * scaleY;
        float syTip = zToScreen(seg[3], plotTop, plotBot);
        stroke(col, alpha);  strokeWeight(weight);
        line(sxThr, syThr, sxTip, syTip);
        // A small dot at the leading tip so the blade's business end is clear.
        strokeWeight(1);  noStroke();  fill(col, alpha);
        ellipse(sxTip, syTip, weight + 3, weight + 3);
    }

    // Kayak side silhouette (a scale / orientation reference, not a metric hull),
    // anchored so its waterline sits at waterM. Bow (+Y tip) drawn in red.
    void drawKayakSide(int cx, int yDir, float scaleY, int plotTop, int plotBot, float waterM) {
        float hl  = 2.30f;                        // half-length (matches other panels)
        float top = waterM + HULL_ABOVE_WL_M;     // deck line
        float bot = waterM - HULL_BELOW_WL_M;     // keel line
        float[][] pts = {
            { +hl,         waterM },   // bow tip (at waterline)
            { +hl * 0.55f, top    },   // deck rise toward cockpit
            { 0,           top    },   // cockpit coaming (deck high)
            { -hl * 0.55f, top    },
            { -hl,         waterM },   // stern tip
            { -hl * 0.55f, bot    },   // keel
            { 0,           bot    },
            { +hl * 0.55f, bot    }
        };
        stroke(90, 110, 140);  strokeWeight(1.5);  noFill();
        beginShape();
        for (float[] p : pts)
            vertex(cx + yDir * p[0] * scaleY, zToScreen(p[1], plotTop, plotBot));
        endShape(CLOSE);
        strokeWeight(1);  noStroke();

        // Red bow marker — a filled wedge at the +Y tip plus a label.
        float bx = cx + yDir * hl * scaleY;
        float by = zToScreen(waterM, plotTop, plotBot);
        float tx = cx + yDir * (hl * 0.7f) * scaleY;
        fill(COL_BOW);  noStroke();
        beginShape();
        vertex(bx, by);
        vertex(tx, zToScreen(top, plotTop, plotBot));
        vertex(tx, zToScreen(bot, plotTop, plotBot));
        endShape(CLOSE);
        fill(COL_BOW);  textSize(11);
        textAlign(yDir < 0 ? LEFT : RIGHT, CENTER);
        text("BOW", bx + yDir * 6, by);
    }

    // Fixed-window height mapping, clamped to the plot band.
    float zToScreen(float z, int plotTop, int plotBot) {
        float y = plotBot - (z - Z_BOT_M) * (plotBot - plotTop) / (Z_TOP_M - Z_BOT_M);
        return constrain(y, plotTop, plotBot);
    }

    // Mean blade-TIP height at this blade's catch/entry events over the whole
    // file, or a default if there are none.
    float meanEntryTipZ(CatchEvents ce, boolean rightBlade) {
        float sum = 0;  int n = 0;
        for (CatchEvent e : ce.events) {
            if (e.right != rightBlade || !e.entry) continue;
            sum += ce.bladeTipZ(e.padFrame, rightBlade);  n++;
        }
        return (n > 0) ? sum / n : DEFAULT_WL_M;
    }

    // Frame of deepest tip immersion (most negative tip z) within [s,e].
    int deepestFrame(CatchEvents ce, int s, int e, boolean rightBlade) {
        int best = s;  float bz = ce.bladeTipZ(s, rightBlade);
        for (int i = s + 1; i <= e; i++) {
            float z = ce.bladeTipZ(i, rightBlade);
            if (z < bz) { bz = z; best = i; }
        }
        return best;
    }
}
