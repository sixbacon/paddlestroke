// Checklist — startup onboarding overlay (v0.14, spec §13.1).
//
// A floating panel drawn over the 3D view, horizontally centred in the
// visualisation area, sitting just above the graph strip. Guides the user
// through the calibration workflow: load paddle → load boat → seek + build
// sidecar. Each row is clickable (same effect as its shortcut key) and
// auto-ticks from live state.
//
// Unlike v0.13 (bottom-strip checklist that vanished on paddle load), the
// overlay persists through the seek-and-C step — the graph appears below it
// as soon as the paddle CSV loads, so the user can drag the cursor to the
// calibration rest moment while the instructions are still on screen. The
// overlay dismisses when the sidecar is built or auto-loaded.

class Checklist {
    // Panel rect — recomputed each draw so resize just works. Kept as fields
    // so mousePressed() hit-tests with the same numbers draw() used.
    int px, py, pw = 680, ph = 216;

    // ── State predicates — read directly from top-level PadViz6 fields ────
    boolean stepPaddleLoaded() { return paddleData != null && paddleData.frameCount() > 0; }
    boolean stepBoatLoaded()   { return boatData   != null && boatData.frameCount()   > 0; }
    boolean stepSidecarBuilt() { return sidecar    != null && sidecar.valid; }

    // Complete = paddle loaded + sidecar built. The boat row is shown and
    // encouraged but not required — a paddle-only session is legitimate
    // (sidecar then has no yaw datum; confidence reflects that).
    boolean isComplete() {
        return stepPaddleLoaded() && stepSidecarBuilt();
    }

    // Dismissal delay — the overlay stays for a moment after the last box
    // ticks so the user sees the completion state.
    int completedAtMs = -1;
    static final int DISMISS_DELAY_MS = 2500;

    boolean shouldStayVisible() {
        if (!isComplete()) {
            completedAtMs = -1;
            return true;
        }
        if (completedAtMs < 0) completedAtMs = millis();
        return (millis() - completedAtMs) < DISMISS_DELAY_MS;
    }

    float remainingS() {
        if (completedAtMs < 0) return -1;
        int rem = DISMISS_DELAY_MS - (millis() - completedAtMs);
        return (rem > 0) ? rem / 1000.0f : 0;
    }

    // Row layout — shared by draw() and mousePressed().
    static final int ROW_H  = 46;
    static final int ROW_Y0 = 64;
    static final int PAD_X  = 24;

    void draw() {
        // Centre in the area right of the entry/exit panel, above the strip.
        int areaX = leftPanelWidth();
        px = areaX + ((width - areaX) - pw) / 2;
        py = height - GRAPH_H - ph - 14;
        if (px < areaX + 8) px = areaX + 8;
        if (py < 8)         py = 8;

        pushMatrix();
        translate(px, py);

        // Panel background — slightly translucent so the 3D scene reads
        // through, with a border to lift it off the scene.
        stroke(110, 130, 170);  strokeWeight(1.5);
        fill(24, 27, 36, 235);
        rect(0, 0, pw, ph, 8);
        strokeWeight(1);  noStroke();

        fill(200, 220, 255);
        textSize(18);  textAlign(LEFT, TOP);
        text("Getting started — do these in order", PAD_X, 14);

        fill(150);
        textSize(11);
        text("Rows tick automatically. Click a row or press its key. This window closes after calibration.", PAD_X, 40);

        drawRow(0, "Load paddle CSV",
                   "PadDis IMU log (accelerometer + quaternion columns)",
                   "p", stepPaddleLoaded(), true);
        drawRow(1, "Load boat CSV",
                   "BoatLog — GPS + kayak quaternion. Enables yaw datum + boat-frame panel.",
                   "b", stepBoatLoaded(), stepPaddleLoaded());
        drawRow(2, "Calibrate",
                   "drag the graph cursor to the start of the calibration (rest) data, then press C",
                   "C", stepSidecarBuilt(), stepPaddleLoaded());

        float rem = remainingS();
        if (rem >= 0) {
            fill(150, 220, 170);
            textSize(13);
            textAlign(CENTER, CENTER);
            text(String.format("Calibrated — closing in %.1f s", rem), pw / 2, ph - 16);
        }

        popMatrix();
        textAlign(LEFT, TOP);
    }

    void drawRow(int idx, String title, String subtitle, String keyHint,
                 boolean done, boolean enabled) {
        int y = ROW_Y0 + idx * ROW_H;
        int x = PAD_X;

        stroke(done ? color(120, 220, 150) : color(enabled ? 150 : 90));
        strokeWeight(2);
        noFill();
        rect(x, y, 22, 22, 3);
        if (done) {
            line(x +  5, y + 12, x + 10, y + 18);
            line(x + 10, y + 18, x + 19, y +  5);
        }
        strokeWeight(1);  noStroke();

        int badgeX = x + 34;
        int badgeY = y - 1;
        int badgeW = 36;
        int badgeH = 26;
        int badgeStroke = done    ? color(90, 170, 110)
                        : enabled ? color(120, 160, 220)
                        :           color(90);
        int badgeFill   = done    ? color(35, 65, 45)
                        : enabled ? color(45, 55, 85)
                        :           color(38, 40, 48);
        int badgeText   = done    ? color(160, 230, 180)
                        : enabled ? color(210, 230, 255)
                        :           color(130);
        stroke(badgeStroke);  strokeWeight(1.5);
        fill(badgeFill);
        rect(badgeX, badgeY, badgeW, badgeH, 4);
        strokeWeight(1);  noStroke();
        fill(badgeText);
        textSize(16);  textAlign(CENTER, CENTER);
        text(keyHint, badgeX + badgeW / 2, badgeY + badgeH / 2 + 1);

        int titleCol = done    ? color(160, 220, 170)
                     : enabled ? color(230, 230, 230)
                     :           color(140);
        fill(titleCol);
        textSize(15);  textAlign(LEFT, CENTER);
        text(title, badgeX + badgeW + 14, y + 11);

        fill(enabled ? color(160) : color(110));
        textSize(11);  textAlign(LEFT, TOP);
        text(subtitle, badgeX + badgeW + 14, y + 23);

        if (enabled && !done) {
            fill(color(120, 140, 180));
            textSize(10);
            textAlign(RIGHT, CENTER);
            text("(or click this row)", pw - PAD_X, y + 11);
        }
    }

    // Absolute window coords. Returns true if the click landed inside the
    // panel (consumed), whether or not a row action fired.
    boolean mousePressed(int mx, int my) {
        if (mx < px || mx > px + pw || my < py || my > py + ph) return false;
        int ly = my - py;
        for (int i = 0; i < 3; i++) {
            int y = ROW_Y0 + i * ROW_H;
            if (ly < y - 2 || ly > y + ROW_H - 6) continue;
            boolean enabled = (i == 0) || stepPaddleLoaded();
            if (!enabled) return true;

            if      (i == 0) selectInput("Select paddle CSV", "onPaddleFileSelected");
            else if (i == 1) selectInput("Select boat CSV",   "onBoatFileSelected");
            else if (i == 2) buildAndSaveSidecar();
            return true;
        }
        return true;   // inside panel background — consume so orbit doesn't start
    }
}
