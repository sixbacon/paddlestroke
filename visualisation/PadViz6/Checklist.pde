// Checklist — startup onboarding strip.
//
// Sits in the bottom strip (same rectangle the graph occupies) whenever no
// paddle CSV is loaded. Three rows guide the user through the calibration
// workflow: load paddle → load boat → build sidecar. Each row is clickable
// (same effect as pressing the shortcut key) and auto-ticks from live state.
//
// Once a paddle CSV is loaded, isGraphVisible() becomes true and the graph
// replaces this strip. From that point onwards the workflow steps are
// discoverable via the HUD indicators (Sidecar line + Slice B hint).

class Checklist {
    int cx, cy, cw, ch;

    Checklist(int x, int y, int w, int h) {
        cx = x; cy = y; cw = w; ch = h;
    }

    void setBounds(int x, int y, int w, int h) {
        cx = x; cy = y; cw = w; ch = h;
    }

    // ── State predicates — read directly from top-level PadViz6 fields ────
    boolean stepPaddleLoaded() { return paddleData != null && paddleData.frameCount() > 0; }
    boolean stepBoatLoaded()   { return boatData   != null && boatData.frameCount()   > 0; }
    boolean stepSidecarBuilt() { return sidecar    != null && sidecar.valid; }

    // True when all three onboarding steps are done.
    boolean isComplete() {
        return stepPaddleLoaded() && stepBoatLoaded() && stepSidecarBuilt();
    }

    // Dismissal delay — the checklist stays visible for a couple of seconds
    // after the last box ticks so the user can see the completion state
    // before the graph takes over.
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

    // Seconds remaining before auto-dismiss, or -1 if not in the delay window.
    float remainingS() {
        if (completedAtMs < 0) return -1;
        int rem = DISMISS_DELAY_MS - (millis() - completedAtMs);
        return (rem > 0) ? rem / 1000.0f : 0;
    }

    // Row layout — consistent so mousePressed can hit-test with the same
    // arithmetic used by draw().
    static final int ROW_H  = 44;
    static final int ROW_Y0 = 62;
    static final int PAD_X  = 28;

    void draw() {
        pushMatrix();
        translate(cx, cy);

        // Background + top border to match the graph strip.
        fill(28, 30, 38);  noStroke();  rect(0, 0, cw, ch);
        stroke(70);  line(0, 0, cw, 0);  noStroke();

        // Title.
        fill(200, 220, 255);
        textSize(18);  textAlign(LEFT, TOP);
        text("Getting started — do these in order", PAD_X, 14);

        fill(150);
        textSize(11);
        text("The rows tick automatically. You can click a row or press its shortcut key.", PAD_X, 40);

        // Rows.
        drawRow(0, "Load paddle CSV",
                   "PadDis v8.10 IMU log (has accelerometer + quaternion columns)",
                   "p", stepPaddleLoaded(), true);
        drawRow(1, "Load boat CSV",
                   "BoatLog v1.0 log — GPS + kayak quaternion. Enables yaw datum.",
                   "b", stepBoatLoaded(), stepPaddleLoaded());
        drawRow(2, "Build session sidecar",
                   "detects rest window; auto-saves <basename>.session.json next to paddle CSV",
                   "C", stepSidecarBuilt(), stepPaddleLoaded());

        // Completion banner during the dismissal delay.
        float rem = remainingS();
        if (rem >= 0) {
            fill(150, 220, 170);
            textSize(14);
            textAlign(CENTER, CENTER);
            text(String.format("All done — opening graph in %.1f s", rem),
                 cw / 2, ch - 22);
        }

        popMatrix();
        textAlign(LEFT, TOP);
    }

    // idx: 0-based row index.
    // enabled: false renders the row dimmed and non-clickable — used to gate
    // rows whose prerequisite hasn't been met (e.g. can't build sidecar
    // without paddle CSV loaded).
    //
    // Layout, left → right:
    //   [checkbox]  [KEY badge]  Title
    //                            Subtitle
    // The key badge is a coloured rectangle around the shortcut letter so
    // it reads as a physical key. When the row is done the badge turns
    // green; when disabled it dims; otherwise it's a soft blue.
    void drawRow(int idx, String title, String subtitle, String keyHint,
                 boolean done, boolean enabled) {
        int y = ROW_Y0 + idx * ROW_H;
        int x = PAD_X;

        // Checkbox — 22 px square. Green tick when done.
        stroke(done ? color(120, 220, 150) : color(enabled ? 150 : 90));
        strokeWeight(2);
        noFill();
        rect(x, y, 22, 22, 3);
        if (done) {
            line(x +  5, y + 12, x + 10, y + 18);
            line(x + 10, y + 18, x + 19, y +  5);
        }
        strokeWeight(1);  noStroke();

        // KEY BADGE — 36 x 26 pill just after the checkbox.
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

        // Title.
        int titleCol = done    ? color(160, 220, 170)
                     : enabled ? color(230, 230, 230)
                     :           color(140);
        fill(titleCol);
        textSize(15);  textAlign(LEFT, CENTER);
        text(title, badgeX + badgeW + 14, y + 11);

        // Subtitle.
        fill(enabled ? color(160) : color(110));
        textSize(11);  textAlign(LEFT, TOP);
        text(subtitle, badgeX + badgeW + 14, y + 23);

        // Trailing "or click this row" hint on the enabled non-done rows.
        if (enabled && !done) {
            fill(color(120, 140, 180));
            textSize(10);
            textAlign(RIGHT, CENTER);
            text("(or click this row)", cw - PAD_X, y + 11);
        }
    }

    // Return true if a row was clicked (and its action was fired).
    // mx, my are in checklist-local coords (relative to cx, cy).
    boolean mousePressed(int mx, int my) {
        for (int i = 0; i < 3; i++) {
            int y = ROW_Y0 + i * ROW_H;
            if (my < y - 2 || my > y + ROW_H - 6) continue;
            boolean enabled = (i == 0) || stepPaddleLoaded();
            if (!enabled) return true;   // consumed but no action

            if      (i == 0) selectInput("Select paddle CSV", "onPaddleFileSelected");
            else if (i == 1) selectInput("Select boat CSV",   "onBoatFileSelected");
            else if (i == 2) buildAndSaveSidecar();
            return true;
        }
        return false;
    }
}
