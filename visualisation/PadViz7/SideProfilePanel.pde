// SideProfilePanel — full-window ZY-plane (side-on) blade-immersion analysis
// (v0.24, spec §14.9). Toggled with x (F2 alt); an ALTERNATIVE to the main 3D
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
// The hull is the REAL sea-kayak side profile traced from
// visualisation/seakayakside.svg (Visio export), scaled to its true 5.1816 m
// (17 ft) length — outline only, no deck/cockpit detail. It is positioned so:
//   - its WATERLINE (a fixed 0.1143 m / 4.5 in above the keel, per the real
//     hull's draft) coincides with the panel's blue waterline; and
//   - the paddle's shaft centre sits 0.3048 m (1 ft) FORWARD of the hull's
//     mid-point, so the blade band lands where the paddler actually reaches.
// The forward nose of that outline is filled RED as the bow marker, tracing the
// real hull so the coloured area overlays the boat properly.
//
// Each view draws:
//   - a BLUE waterline = mean blade-TIP height at that blade's catch (entry)
//     events, over the whole file (the tip is the leading edge that breaks the
//     surface first — spec §14.9). Static, so the view doesn't jump.
//   - the real kayak side outline anchored to that waterline, bow nose RED;
//   - the immersed part of the paddle BLADE at EVERY in-water frame up to the
//     cursor, drawn faintly — RED for the right blade, YELLOW for the left — so
//     the marks accumulate into a persistent BAND of colour along the hull side
//     showing where, and how deep, the blade works across the whole session;
//   - the live blade at the playback frame (bold) — drawn ONLY while it is in
//     the water (tip below the waterline), to any extent;
//   - a footer: stroke count, average and max immersion depth below the water.
//
// The vertical scale is FIXED (Z_TOP_M..Z_BOT_M, metres vs the hands/shaft
// centre), not fitted to the data, so the panels keep a constant height and
// don't resize as strokes accumulate. Fore/aft (Y) is drawn to a fixed scale
// that fits the whole kayak length across the width, so the two axes have
// different px/metre — both carry metre tick labels to make the scales explicit.

class SideProfilePanel {
    boolean shown = false;

    static final float KAYAK_LEN_M     = 5.1816f;  // real hull length, 17 ft
    static final float WL_ABOVE_KEEL_M = 0.1143f;  // waterline 4.5 in above keel
    // Paddle shaft centre sits this far FORWARD of the hull mid-point (1 ft).
    static final float PADDLE_FWD_OF_CENTRE_M = 0.3048f;

    static final float VIEW_HALF_LEN_M = 2.90f;  // half-length + margin (Y), fits 17 ft
    static final float Z_TOP_M         = 0.45f;  // fixed vertical window, top (vs hands)
    static final float Z_BOT_M         = -1.30f; // fixed vertical window, bottom
    static final float DEFAULT_WL_M    = -0.55f; // fallback waterline if no catches

    final int COL_RIGHT = color(235, 60, 60);    // right blade — red
    final int COL_LEFT  = color(240, 210, 40);   // left blade  — yellow
    final int COL_WATER = color(70, 130, 255);   // waterline   — blue
    final int COL_BOW   = color(255, 60, 60);    // bow marker  — red
    final int COL_HULL  = color(150, 170, 200);  // hull outline

    // Real sea-kayak side outline, traced from seakayakside.svg (Visio export)
    // and converted to metres: { fore/aft, height } where fore/aft is +bow,
    // measured from the hull mid-point, and height is +up, measured from the
    // WATERLINE (so keel points sit at −WL_ABOVE_KEEL_M). Bow tip is index 7.
    // SVG→m: x·0.0107526 (481.89 units = 5.1816 m); y flipped, keel datum, −WL.
    final float[][] HULL = {
        { -2.591f,  0.221f },   //  0 stern, deck line
        { -2.408f,  0.038f },   //  1
        { -2.332f, -0.038f },   //  2
        { -0.579f, -0.114f },   //  3 keel
        {  0.335f, -0.114f },   //  4 keel
        {  1.890f, -0.023f },   //  5 forefoot
        {  2.164f,  0.038f },   //  6
        {  2.591f,  0.297f },   //  7 BOW TIP
        {  1.981f,  0.221f },   //  8 deck at bow
        {  0.793f,  0.221f },   //  9 deck
        {  0.183f,  0.221f },   // 10 deck
        { -0.610f,  0.099f },   // 11
        { -1.722f,  0.145f }    // 12
    };
    // Forward nose vertices (indices into HULL) filled red as the bow marker,
    // tracing the real outline: forefoot → bow tip → deck.
    final int[] BOW_NOSE = { 5, 6, 7, 8 };

    // Strokes/frames before this frame are excluded from the accumulated band
    // (right-click restart). The waterline stays whole-file for stability.
    int resetAtFrame = 0;

    void toggle() { shown = !shown; }
    void reset(int atFrame) { resetAtFrame = atFrame; }

    // Boat-frame Y of the hull mid-point: the shaft centre lives at
    // PADDLE_BOW_OFFSET_M, and the paddle is PADDLE_FWD_OF_CENTRE_M ahead of the
    // hull centre, so the hull centre sits that much sternward of the shaft.
    float boatCentreY() { return PADDLE_BOW_OFFSET_M - PADDLE_FWD_OF_CENTRE_M; }

    void draw(CatchEvents ce, int curFrame) {
        int H = height - GRAPH_H;             // area above the graph strip
        int half = H / 2;

        // The band only ever spans resetAtFrame..cursor, so a restart point left
        // AHEAD of the cursor (e.g. restart near the end, then rewind to replay)
        // would draw nothing. Re-anchor the restart point to the cursor whenever
        // the cursor moves behind it, so "restart, then run again from earlier"
        // rebuilds the band as playback advances.
        if (curFrame < resetAtFrame) resetAtFrame = max(0, curFrame);

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
        float bcY    = boatCentreY();

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

        // Vertical fore/aft grid lines every 1 m (boat-frame Y reference).
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

        // Real kayak side outline anchored to the waterline, bow nose in red.
        drawKayakSide(cx, yDir, scaleY, bcY, plotTop, plotBot, waterM);

        // Blue waterline (drawn after the hull so it reads on top).
        float syWater = zToScreen(waterM, plotTop, plotBot);
        stroke(COL_WATER);  strokeWeight(2);
        line(MARGIN_X, syWater, width - MARGIN_X, syWater);
        noStroke();  fill(COL_WATER);  textAlign(RIGHT, BOTTOM);  textSize(10);
        text("water (mean catch)", width - MARGIN_X - 4, syWater - 2);

        // Persistent immersion band: the immersed part of the blade at EVERY
        // in-water frame up to the cursor. Marks accumulate into a band of
        // colour along the hull side. Stepped by 2 (frames are ~10 ms apart) to
        // halve the draw cost with no visible loss.
        int upto = min(curFrame, last);
        for (int i = max(0, resetAtFrame); i <= upto; i += 2) {
            if (ce.bladeTipZ(i, rightBlade) >= waterM) continue;   // out of water
            drawImmersed(ce, i, rightBlade, cx, yDir, scaleY, plotTop, plotBot,
                         waterM, bladeCol, 34);
        }

        // Live blade at the playback cursor (bold) — only while in the water.
        int liveIdx = constrain(curFrame, 0, last);
        if (ce.bladeTipZ(liveIdx, rightBlade) < waterM)
            drawBlade(ce, liveIdx, rightBlade, cx, yDir, scaleY, plotTop, plotBot,
                      bladeCol, 255, 4);

        // Per-stroke immersion stats for the footer (deepest frame of each run).
        ArrayList<int[]> runs = rightBlade ? ce.rightRuns : ce.leftRuns;
        int nStrokes = 0;  float sumDepth = 0, maxDepth = -1e9;
        if (runs != null) {
            for (int[] run : runs) {
                int s = run[0], e = run[1];
                if (s < resetAtFrame || e > upto || e <= s || s < 0 || e > last) continue;
                int di = deepestFrame(ce, s, e, rightBlade);
                float depth = waterM - ce.bladeTipZ(di, rightBlade);
                sumDepth += depth;  maxDepth = max(maxDepth, depth);  nStrokes++;
            }
        }

        // Fore/aft axis labels — stern ↔ bow at the real hull tips.
        float bowY   = bcY + KAYAK_LEN_M / 2;
        float sternY = bcY - KAYAK_LEN_M / 2;
        fill(120);  textSize(10);  textAlign(CENTER, TOP);
        text(yDir < 0 ? "← bow"   : "bow →",   cx + yDir * bowY   * scaleY, plotBot + 4);
        text(yDir < 0 ? "stern →" : "← stern", cx + yDir * sternY * scaleY, plotBot + 4);

        // Footer: strokes + average / max immersion depth below the water.
        fill(bladeCol);  textSize(12);  textAlign(LEFT, TOP);
        String s = (rightBlade ? "right" : "left") + ": " + nStrokes
                   + (nStrokes == 1 ? " stroke" : " strokes");
        if (nStrokes > 0)
            s += String.format("   immersion  avg %.2f m   max %.2f m", sumDepth / nStrokes, maxDepth);
        text(s, MARGIN_X, y0 + hh - BOT_PAD + 14);
    }

    // Draw the blade at frame i as a full segment throat→tip (used for the bold
    // live blade), clamped to the plot band. alpha/weight set the look.
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

    // Draw ONLY the immersed part of the blade at frame i (from the waterline
    // down to the tip). Caller has already checked the tip is below waterM.
    void drawImmersed(CatchEvents ce, int i, boolean rightBlade,
                      int cx, int yDir, float scaleY, int plotTop, int plotBot,
                      float waterM, int col, int alpha) {
        float[] seg = ce.bladeSegmentYZ(i, rightBlade);   // {yThr, zThr, yTip, zTip}
        float yThr = seg[0], zThr = seg[1], yTip = seg[2], zTip = seg[3];
        float yA, zA;
        if (zThr <= waterM) {                 // whole blade immersed
            yA = yThr;  zA = zThr;
        } else {                              // clip to where it crosses the water
            float t = (waterM - zThr) / (zTip - zThr);   // 0..1 (tip below, throat above)
            yA = yThr + t * (yTip - yThr);
            zA = waterM;
        }
        float sxA = cx + yDir * yA   * scaleY, syA = zToScreen(zA,   plotTop, plotBot);
        float sxT = cx + yDir * yTip * scaleY, syT = zToScreen(zTip, plotTop, plotBot);
        stroke(col, alpha);  strokeWeight(2);
        line(sxA, syA, sxT, syT);
        noStroke();
    }

    // Real kayak side outline (from seakayakside.svg, scaled to 17 ft),
    // anchored so its waterline sits at waterM and its centre at boat-frame bcY.
    // Outline only; the forward nose is filled red as the bow marker.
    void drawKayakSide(int cx, int yDir, float scaleY, float bcY,
                       int plotTop, int plotBot, float waterM) {
        // Outline.
        stroke(COL_HULL);  strokeWeight(1.5);  noFill();
        beginShape();
        for (float[] p : HULL)
            vertex(cx + yDir * (bcY + p[0]) * scaleY,
                   zToScreen(waterM + p[1], plotTop, plotBot));
        endShape(CLOSE);
        strokeWeight(1);  noStroke();

        // Red bow nose — filled region tracing the real forward outline, so the
        // coloured area overlays the hull rather than floating past its tip.
        fill(COL_BOW, 165);  noStroke();
        beginShape();
        for (int idx : BOW_NOSE) {
            float[] p = HULL[idx];
            vertex(cx + yDir * (bcY + p[0]) * scaleY,
                   zToScreen(waterM + p[1], plotTop, plotBot));
        }
        endShape(CLOSE);

        // BOW label at the bow tip.
        float[] tip = HULL[7];
        float bx = cx + yDir * (bcY + tip[0]) * scaleY;
        float by = zToScreen(waterM + tip[1], plotTop, plotBot);
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
