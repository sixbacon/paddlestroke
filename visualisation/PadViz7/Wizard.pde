// Wizard — guided session-setup flow (PadViz7 v0.16, spec §14).
//
// Replaces Checklist.pde. A docked instructions/status panel anchored to the
// TOP of the single PadViz7 window (never over the bottom GRAPH_H strip — the
// "graphics paddle window area"), plus a 5-step state machine that walks the
// user through loading files and calibrating a session:
//
//   Step 1  paddle CSV        (Return = choose)
//   Step 2  boat CSV          (Return = choose, X = skip)
//   Step 3  roll calibration  (3a build from cursor, or 3b use/reset a saved one)
//   Step 4  classification    (4a mark right/left/zero/exclude, or 4b use/reset)
//   Step 5  done              (short dismiss delay)
//
// It is a docked panel, NOT a second OS window — same pattern as the old
// Checklist / Menu / DetailPanel, avoiding the multi-window/AWT-threading risk
// that sank three attempts at the CSV file-picker fix earlier this project.
//
// Everything each step *does* reuses already-verified engines unchanged
// (selectCsvInput / onPaddleFileSelected / onBoatFileSelected, buildAndSave-
// Sidecar, saveSidecarQuiet). The wizard only adds a guided step-sequence and
// gate/confirm/reset UI in front of them, plus the wholly new classification
// feature (Classification.pde).
//
// F1 toggles the panel. Before the wizard completes it shows the current
// step; after completion F1 re-opens it as a read-only summary and never
// restarts the wizard. All instructions AND error messages surface here
// (Step 0 of the instructions) — triggerErrorFlash() routes into this panel
// while the wizard is active.

class Wizard {
    int step   = 1;          // 1..5
    boolean shown    = true;
    boolean complete = false;

    // Step 4 sub-mode: reviewing existing classification (4b) vs marking (4a).
    boolean classReview = false;

    // Step 5 dismiss delay.
    int doneAtMs = -1;
    static final int DISMISS_DELAY_MS = 2500;

    // Persistent error line (overlap warning, build failure, bad filename).
    // Cleared by the next successful action or a click on it.
    String errorMsg = "";
    float errBoxL, errBoxR, errBoxT, errBoxB;

    // Panel rect — recomputed each draw so resize just works.
    int px, py, pw, ph;

    // ── State queries ────────────────────────────────────────────────────────
    boolean active()       { return shown && !complete; }
    // Graph shows classification shading + pending cursors throughout Step 4
    // (both the 4a marking flow and the 4b review of loaded sections).
    boolean isClassifying(){ return active() && step == 4; }

    boolean hasRestCal() {
        return sidecar != null && sidecar.valid && sidecar.restPadStart >= 0;
    }
    boolean hasClassification() {
        return sidecar != null && sidecar.classification.size() > 0;
    }

    void toggle() { shown = !shown; }

    void setError(String msg) { errorMsg = msg; }

    // ── External advance hooks (called from the file-select callbacks) ───────
    void onPaddleLoaded() { if (active() && step == 1) { step = 2; errorMsg = ""; } }
    void onBoatLoaded()   { if (active() && step == 2) { step = 3; errorMsg = ""; } }

    // ── Step transitions ─────────────────────────────────────────────────────
    void enterStep4() {
        classReview = hasClassification();
        classify.markReset();
        errorMsg = "";
    }

    void gotoStep5() {
        classify.markReset();
        step = 5;
        doneAtMs = millis();
        errorMsg = "";
    }

    // Discard the whole sidecar and fall back into Step 3a (spec §14, 3b reset).
    void resetRollCal() {
        sidecar = null;
        qRefPad  = new float[]{ 1, 0, 0, 0 };
        qRefBoat = new float[]{ 1, 0, 0, 0 };
        qRefPadGrv  = new float[]{ 1, 0, 0, 0 };
        qRefBoatGrv = new float[]{ 1, 0, 0, 0 };
        refFramePad = refFrameBoat = -1;
        rebuildCatchEvents();
        rebuildClassificationIndex();
        errorMsg = "";
    }

    // ── Key handling — returns true if the key was consumed ──────────────────
    // Only the keys meaningful to the current step are consumed; everything
    // else (digits, Space, arrows, ,/. …) falls through so the user can still
    // navigate the graph cursor while positioning for Steps 3 and 4.
    boolean handleKey(char k, int kc) {
        boolean ret = (k == ENTER || k == RETURN);

        switch (step) {
            case 1:
                if (ret) { selectCsvInput("Select paddle CSV (PadLog…)", true); return true; }
                if ((k == 'j' || k == 'J') && g_sessionsAvailable) { selectSessionInput(); return true; }
                return false;

            case 2:
                if (ret)                  { selectCsvInput("Select boat CSV (BoatLog…)", false); return true; }
                if (k == 'x' || k == 'X') { step = 3; errorMsg = ""; return true; }   // skip boat
                return false;

            case 3:
                if (hasRestCal()) {                         // 3b
                    if (ret)                  { enterStep4(); step = 4; return true; }
                    if (k == 'r' || k == 'R') { resetRollCal(); return true; }
                    return false;
                } else {                                    // 3a
                    if (ret) {
                        boolean ok = buildAndSaveSidecar();
                        if (ok) { enterStep4(); step = 4; }
                        // failure message already routed here via triggerErrorFlash
                        return true;
                    }
                    return false;
                }

            case 4:
                return handleKeyStep4(k, ret);
        }
        return false;
    }

    boolean handleKeyStep4(char k, boolean ret) {
        if (classReview) {                                  // 4b
            if (ret)                  { gotoStep5(); return true; }
            if (k == 'r' || k == 'R') {
                sidecar.classification.clear();
                saveSidecarQuiet();
                rebuildClassificationIndex();
                paddleFrameIdx = classify.nearestVisible(paddleFrameIdx);
                classReview = false;
                classify.markReset();
                errorMsg = "";
                return true;
            }
            return false;
        }

        // 4a — marking.
        if (k == 'f' || k == 'F') { gotoStep5(); return true; }

        switch (classify.markPhase) {
            case MARK_IDLE:
                if (ret) { classify.beginStart(paddleFrameIdx); errorMsg = ""; return true; }
                return false;

            case MARK_START:
                if (ret) {
                    if (!classify.beginEnd(paddleFrameIdx))
                        setError("END must be to the right of START — press Return further along");
                    else errorMsg = "";
                    return true;
                }
                if (k == 'a' || k == 'A') { classify.markReset(); errorMsg = ""; return true; }
                return false;

            case MARK_END:
                if (k == 'r' || k == 'R') { commitClass(CLASS_RIGHT);    return true; }
                if (k == 'l' || k == 'L') { commitClass(CLASS_LEFT);     return true; }
                if (k == 'z' || k == 'Z') { commitClass(CLASS_ZERO);     return true; }
                if (k == 'd' || k == 'D') { commitClass(CLASS_EXCLUDED); return true; }
                if (k == 'a' || k == 'A') { classify.markReset(); errorMsg = ""; return true; }
                return false;
        }
        return false;
    }

    void commitClass(int type) {
        if (classify.pendingOverlaps(sidecar.classification)) {
            setError("SECTION OVERLAPS an existing one — re-mark from the start");
            classify.markReset();
            return;
        }
        int a = min(classify.pendingStart, classify.pendingEnd);
        int b = max(classify.pendingStart, classify.pendingEnd);
        sidecar.classification.add(new ClassificationSection(a, b, type));
        saveSidecarQuiet();
        rebuildClassificationIndex();
        paddleFrameIdx = classify.nearestVisible(paddleFrameIdx);
        classify.markReset();
        errorMsg = "";
    }

    // ── Mouse — dismiss the error line / consume clicks inside the panel ─────
    boolean mousePressed(int mx, int my) {
        if (!shown) return false;
        if (errorMsg.length() > 0
            && mx >= errBoxL && mx <= errBoxR && my >= errBoxT && my <= errBoxB) {
            errorMsg = "";
            return true;
        }
        // Consume any click inside the panel so it doesn't start a camera orbit.
        return (mx >= px && mx <= px + pw && my >= py && my <= py + ph);
    }

    // ── Draw ─────────────────────────────────────────────────────────────────
    void draw() {
        // Auto-dismiss after Step 5's delay.
        if (step == 5 && !complete) {
            if (doneAtMs < 0) doneAtMs = millis();
            if (millis() - doneAtMs >= DISMISS_DELAY_MS) { complete = true; shown = false; }
        }
        if (!shown) return;

        px = 12;
        // Start below the HUD title line + the Commands/Detail button row
        // (that row sits at y=38..64), so those buttons are never overdrawn by
        // — or drawn on top of — this panel.
        py = 74;
        pw = width - 24;
        // Compact panel. It does NOT try to physically cover the analysis
        // overlays (full-height side panels, bottom compass, legend) — those
        // are simply not drawn while this window is shown (see PadViz7.draw()'s
        // `setup` gate), so nothing pokes out around this shorter panel.
        ph = min(216, height - GRAPH_H - py - 10);
        if (ph < 120) ph = 120;

        pushMatrix();
        translate(px, py);

        stroke(120, 150, 200);  strokeWeight(1.5);
        fill(80, 80, 80);        // opaque neutral grey — must fully cover the
                                 // scene behind or the text is unreadable
        rect(0, 0, pw, ph, 8);
        strokeWeight(1);  noStroke();

        int PADX = 22;
        // Title row.
        fill(205, 225, 255);
        textSize(18);  textAlign(LEFT, TOP);
        String title = complete ? "PadViz7 — session summary" : "PadViz7 — session setup";
        text(title, PADX, 12);
        if (!complete) {
            fill(150);
            textSize(12);  textAlign(RIGHT, TOP);
            text("Step " + step + " of 5", pw - PADX, 15);
        }
        fill(150);
        textSize(10);  textAlign(RIGHT, BOTTOM);
        text("w = show/hide this window", pw - PADX, ph - 8);

        int y = 46;
        if (complete) {
            drawSummaryBody(PADX, y);
        } else {
            switch (step) {
                case 1: y = drawStep1(PADX, y); break;
                case 2: y = drawStep2(PADX, y); break;
                case 3: y = drawStep3(PADX, y); break;
                case 4: y = drawStep4(PADX, y); break;
                case 5: y = drawStep5(PADX, y); break;
            }
        }

        // Error line — persists until the next action or a click.
        if (errorMsg.length() > 0) {
            String shownMsg = errorMsg + "    [click to dismiss]";
            noStroke();  fill(70, 25, 25, 240);
            float ew = pw - PADX * 2;
            float ey = ph - 46;
            rect(PADX - 4, ey - 4, ew + 8, 26, 4);
            fill(255, 165, 165);
            textSize(13);  textAlign(LEFT, CENTER);
            text(shownMsg, PADX, ey + 9);
            // Hit box in absolute window coords.
            errBoxL = px + PADX - 4;   errBoxR = errBoxL + ew + 8;
            errBoxT = py + ey - 4;     errBoxB = errBoxT + 26;
        } else {
            errBoxL = errBoxR = errBoxT = errBoxB = -1;
        }

        popMatrix();
        textAlign(LEFT, TOP);
    }

    // ── Per-step bodies (return the y after the last line) ───────────────────
    int line(int x, int y, int sz, int c, String s) {
        fill(c);  textSize(sz);  textAlign(LEFT, TOP);
        text(s, x, y);
        return y + sz + 8;
    }
    int opts(int x, int y, String s) {
        return line(x, y, 14, color(150, 200, 255), s);
    }

    int drawStep1(int x, int y) {
        y = line(x, y, 16, color(230), "1.  Load paddle CSV");
        y = line(x, y, 13, color(180), "Choose the PadLog…CSV recorded on the paddle unit (name must start \"pad\", end \".csv\").");
        y = opts(x, y, "Return  =  choose paddle file");
        if (g_sessionsAvailable) {
            y += 8;
            y = line(x, y, 13, color(180), "Or reload a previously saved session in one step — paddle + boat + calibration + classification:");
            y = opts(x, y, "J  =  pick a saved session (.session.json)");
        }
        return y;
    }

    int drawStep2(int x, int y) {
        y = line(x, y, 16, color(230), "2.  Load boat CSV  (optional)");
        y = line(x, y, 13, color(180), "Choose the BoatLog…CSV (name must start \"boat\", end \".csv\"), or skip for a paddle-only session.");
        y = opts(x, y, "Return  =  choose boat file        X  =  skip");
        return y;
    }

    int drawStep3(int x, int y) {
        if (hasRestCal()) {
            y = line(x, y, 16, color(230), "3.  Roll calibration  —  saved calibration found");
            y = line(x, y, 12, color(170), String.format(
                "confidence %s   padMount r=%+.1f° p=%+.1f°   boatMount r=%+.1f° p=%+.1f°   yaw datum=%+.1f°",
                sidecar.confidence,
                sidecar.rollOffsetPadDeg,  sidecar.pitchOffsetPadDeg,
                sidecar.rollOffsetBoatDeg, sidecar.pitchOffsetBoatDeg,
                sidecar.yawDatumDeg));
            y = line(x, y, 12, color(170), String.format(
                "rest window  pad %d–%d  (%.1fs)", sidecar.restPadStart, sidecar.restPadEnd, sidecar.restDurationS));
            y = opts(x, y, "Return  =  use it        r/R  =  reset & recalibrate");
        } else {
            y = line(x, y, 16, color(230), "3.  Roll calibration");
            y = line(x, y, 13, color(180), "Drag the graph cursor to the START of a still (rest) moment, then press Return.");
            y = opts(x, y, "Return  =  detect rest window & build calibration");
        }
        return y;
    }

    int drawStep4(int x, int y) {
        if (classReview) {
            y = line(x, y, 16, color(230), "4.  Classification  —  saved sections found");
            y = line(x, y, 13, color(180), classificationSummary(sidecar.classification));
            y = opts(x, y, "Return  =  use them        r/R  =  reset & reclassify");
            return y;
        }
        y = line(x, y, 16, color(230), "4.  Classification");
        switch (classify.markPhase) {
            case MARK_IDLE:
                y = line(x, y, 13, color(180), "Position the graph cursor at the START of a section, then press Return.");
                y = opts(x, y, "Return  =  mark start        f/F  =  finish");
                break;
            case MARK_START:
                y = line(x, y, 13, color(255, 235, 90),
                        "START marked at frame " + classify.pendingStart + " (yellow). Now position the cursor at the END.");
                y = opts(x, y, "Return  =  mark end        a/A  =  abort pair        f/F  =  finish");
                break;
            case MARK_END:
                y = line(x, y, 13, color(255, 160, 160),
                        "Section " + classify.pendingStart + "–" + classify.pendingEnd + " marked. Classify it:");
                y = opts(x, y, "r/R right    l/L left    z/Z zero-feather    d/D exclude    a/A abort    f/F finish");
                break;
        }
        y = line(x, y, 11, color(140), classificationSummary(sidecar.classification));
        return y;
    }

    int drawStep5(int x, int y) {
        y = line(x, y, 16, color(150, 230, 170), "Done — session ready.");
        drawSummaryBody(x, y);
        float rem = (doneAtMs < 0) ? 0 : (DISMISS_DELAY_MS - (millis() - doneAtMs)) / 1000.0f;
        line(x, ph - 74, 12, color(150, 220, 170),
             String.format("closing in %.1f s   (w reopens this summary)", max(0, rem)));
        return y;
    }

    void drawSummaryBody(int x, int y) {
        if (sidecar != null && sidecar.valid) {
            y = line(x, y, 12, color(180), String.format(
                "roll cal: confidence %s   padMount r=%+.1f° p=%+.1f°   yaw datum=%+.1f°",
                sidecar.confidence, sidecar.rollOffsetPadDeg, sidecar.pitchOffsetPadDeg, sidecar.yawDatumDeg));
            y = line(x, y, 12, color(180), classificationSummary(sidecar.classification));
        } else {
            y = line(x, y, 12, color(180), "no calibration loaded");
        }
    }
}
