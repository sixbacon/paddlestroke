// Classification — per-session data-quality sections (PadViz7 v0.16, spec §14).
//
// Replaces the hand-kept note file the user used to record which stretches of
// a recording are good right-handed / left-handed / zero-feather paddling, or
// should be excluded entirely (e.g. the drive home with the units still
// logging). The closest prior analogue in the repo is the hardcoded SEGMENTS
// dict at the top of visualisation/stroke_catch_explore.py — this in-app UI
// supersedes it as the source of truth for future sessions.
//
// Two responsibilities live here:
//   1. ClassificationSection — the persisted record (start/end paddle-frame,
//      type). Stored in the sidecar's "classification_sections" JSON array.
//   2. Classification — the runtime controller: the in-progress marking
//      mini-state-machine (yellow start cursor → red stop cursor → classify),
//      the graph shading, and the frame-visibility index that makes EXCLUDED
//      ranges take up no pixels and be unreachable by any navigation path.
//
// Frames are paddle-frame indices throughout — classification is paddle-
// anchored, matching SyncMap's "paddle is master" convention.

// ── Section types ──────────────────────────────────────────────────────────
final int CLASS_RIGHT    = 0;   // right-handed forward paddling
final int CLASS_LEFT     = 1;   // left-handed forward paddling
final int CLASS_ZERO     = 2;   // zero-feather (symmetric) paddling
final int CLASS_EXCLUDED = 3;   // cut from graph + navigation (e.g. drive home)

String classTypeName(int t) {
    switch (t) {
        case CLASS_RIGHT:    return "right";
        case CLASS_LEFT:     return "left";
        case CLASS_ZERO:     return "zero";
        case CLASS_EXCLUDED: return "excluded";
        default:             return "unknown";
    }
}

int classTypeFromName(String s) {
    if (s == null) return -1;
    s = s.toLowerCase();
    if (s.equals("right"))    return CLASS_RIGHT;
    if (s.equals("left"))     return CLASS_LEFT;
    if (s.equals("zero"))     return CLASS_ZERO;
    if (s.equals("excluded")) return CLASS_EXCLUDED;
    return -1;
}

// Shading colour per type. Excluded sections are cut from the graph so their
// colour is only ever seen briefly (if at all); the others tint the strip.
int classTypeColor(int t) {
    switch (t) {
        case CLASS_RIGHT:    return color( 90, 150, 255);   // blue
        case CLASS_LEFT:     return color(110, 220, 130);   // green
        case CLASS_ZERO:     return color(235, 185,  95);   // amber
        case CLASS_EXCLUDED: return color(210,  90,  90);   // red
        default:             return color(180);
    }
}

// ── Persisted record ────────────────────────────────────────────────────────
class ClassificationSection {
    int startFrame, endFrame;   // inclusive paddle-frame range, startFrame <= endFrame
    int type;

    ClassificationSection(int s, int e, int t) {
        startFrame = min(s, e);
        endFrame   = max(s, e);
        type       = t;
    }

    int frameCount() { return endFrame - startFrame + 1; }
}

// ── Marking phases (in-progress pair being built in Step 4a) ────────────────
final int MARK_IDLE  = 0;   // awaiting the start of a section
final int MARK_START = 1;   // start committed (yellow cursor), awaiting the end
final int MARK_END   = 2;   // end committed (red cursor), awaiting a classify key

class Classification {
    // In-progress marking state (Step 4a). pendingStart/pendingEnd are raw
    // paddle-frame indices, -1 when unset.
    int markPhase   = MARK_IDLE;
    int pendingStart = -1;
    int pendingEnd   = -1;

    // ── Visibility / exclusion index ────────────────────────────────────────
    // Rebuilt whenever sidecar.classification changes or the paddle CSV loads.
    //   posOf[raw]  — count of visible frames before `raw` (== its own visible
    //                 position for a visible frame; the next visible position
    //                 for an excluded frame). Monotonic non-decreasing.
    //   rawOf[vpos] — inverse: the raw frame at visible position vpos.
    //   excl[raw]   — true if `raw` sits inside an EXCLUDED section.
    // With no exclusions posOf/rawOf are the identity and everything below
    // reduces to today's raw-index behaviour (the zero-exclusion special case,
    // not a separate code path).
    int[]     posOf = new int[0];
    int[]     rawOf = new int[0];
    boolean[] excl  = new boolean[0];
    int nFrames  = 0;
    int visCount = 0;

    void rebuild(int n, ArrayList<ClassificationSection> sections) {
        nFrames = max(0, n);
        excl = new boolean[nFrames];
        if (sections != null) {
            for (ClassificationSection cs : sections) {
                if (cs.type != CLASS_EXCLUDED) continue;
                int a = constrain(cs.startFrame, 0, nFrames - 1);
                int b = constrain(cs.endFrame,   0, nFrames - 1);
                for (int i = a; i <= b; i++) excl[i] = true;
            }
        }
        posOf = new int[nFrames];
        int vis = 0;
        for (int i = 0; i < nFrames; i++) {
            posOf[i] = vis;               // visible frames strictly before i
            if (!excl[i]) vis++;
        }
        visCount = vis;
        rawOf = new int[max(1, visCount)];
        int v = 0;
        for (int i = 0; i < nFrames; i++) if (!excl[i]) rawOf[v++] = i;
    }

    boolean hasExclusions() { return visCount < nFrames; }

    boolean isExcluded(int raw) {
        return (raw >= 0 && raw < nFrames) ? excl[raw] : false;
    }

    // Visible position of a raw frame (nearest-visible for excluded frames).
    int visiblePos(int raw) {
        if (nFrames == 0) return 0;
        raw = constrain(raw, 0, nFrames - 1);
        return posOf[raw];
    }

    // Raw frame at a visible position. Clamped; always returns a *visible*
    // frame, so callers routing clicks/nav through here can never land inside
    // an excluded range.
    int rawForVisiblePos(int vpos) {
        if (visCount <= 0) return constrain(vpos, 0, max(0, nFrames - 1));
        vpos = constrain(vpos, 0, visCount - 1);
        return rawOf[vpos];
    }

    // Nearest visible frame to a raw frame (identity if already visible).
    int nearestVisible(int raw) {
        if (visCount <= 0) return constrain(raw, 0, max(0, nFrames - 1));
        if (!isExcluded(raw)) return constrain(raw, 0, nFrames - 1);
        return rawForVisiblePos(visiblePos(raw));
    }

    // Move `delta` visible positions from `raw`, skipping excluded ranges.
    // The single helper every navigation call site routes through.
    int stepVisible(int raw, int delta) {
        if (visCount <= 0) return constrain(raw + delta, 0, max(0, nFrames - 1));
        int v = constrain(visiblePos(raw) + delta, 0, visCount - 1);
        return rawOf[v];
    }

    int firstVisible() { return rawForVisiblePos(0); }
    int lastVisible()  { return rawForVisiblePos(visCount - 1); }

    // ── Marking mini-state-machine (driven by Wizard Step 4a) ───────────────
    void markReset() {
        markPhase = MARK_IDLE;
        pendingStart = pendingEnd = -1;
    }

    void beginStart(int frame) {
        pendingStart = frame;
        pendingEnd   = -1;
        markPhase    = MARK_START;
    }

    // Returns false (leaving phase unchanged) if the end isn't after the start.
    boolean beginEnd(int frame) {
        if (frame <= pendingStart) return false;
        pendingEnd = frame;
        markPhase  = MARK_END;
        return true;
    }

    // Would committing the pending pair overlap any existing section?
    boolean pendingOverlaps(ArrayList<ClassificationSection> sections) {
        int a = min(pendingStart, pendingEnd);
        int b = max(pendingStart, pendingEnd);
        if (sections == null) return false;
        for (ClassificationSection cs : sections) {
            if (a <= cs.endFrame && cs.startFrame <= b) return true;   // ranges touch
        }
        return false;
    }

    // ── Graph overlay — committed shading + pending cursors ─────────────────
    // Drawn from inside GraphPanel.drawChart() (already under translate(gx,gy)),
    // so panel-local chart coords apply. Only committed non-excluded sections
    // produce visible pixels (excluded ranges are cut from the chart entirely).
    void drawOverlay(GraphPanel gp, ArrayList<ClassificationSection> sections,
                     DataSource ds) {
        int cy = gp.chartY, ch = gp.chartH;

        if (sections != null) {
            for (ClassificationSection cs : sections) {
                if (cs.type == CLASS_EXCLUDED) continue;   // cut — no pixels
                float x0 = gp.chartXForFrame(cs.startFrame, ds);
                float x1 = gp.chartXForFrame(cs.endFrame,   ds);
                float lo = constrain(min(x0, x1), gp.chartX, gp.chartX + gp.chartW);
                float hi = constrain(max(x0, x1), gp.chartX, gp.chartX + gp.chartW);
                if (hi <= lo) continue;
                int c = classTypeColor(cs.type);
                noStroke();
                fill(c, 46);
                rect(lo, cy, hi - lo, ch);
                // Type label at the band's top-left.
                fill(c, 220);
                textSize(10);  textAlign(LEFT, TOP);
                text(classTypeName(cs.type), lo + 3, cy + 2);
            }
        }

        // Pending start (yellow) / end (red) cursors.
        if (pendingStart >= 0) drawMarkLine(gp, ds, pendingStart, color(255, 235, 90),  "start");
        if (pendingEnd   >= 0) drawMarkLine(gp, ds, pendingEnd,   color(255, 90,  90),  "end");
        textAlign(LEFT, TOP);
    }

    void drawMarkLine(GraphPanel gp, DataSource ds, int frame, int c, String label) {
        float x = gp.chartXForFrame(frame, ds);
        if (x < gp.chartX - 1 || x > gp.chartX + gp.chartW + 1) return;
        stroke(c);  strokeWeight(2);
        line(x, gp.chartY, x, gp.chartY + gp.chartH);
        strokeWeight(1);  noStroke();
        fill(c);  textSize(11);  textAlign(CENTER, BOTTOM);
        text(label, x, gp.chartY - 1);
    }
}

// ── Summary helper (Detail panel line, spec §14) ───────────────────────────
// counts[0..3] by type, plus total excluded seconds (100 Hz assumption).
String classificationSummary(ArrayList<ClassificationSection> sections) {
    if (sections == null || sections.size() == 0) return "classification: none";
    int[] n = new int[4];
    int exclFrames = 0;
    for (ClassificationSection cs : sections) {
        if (cs.type >= 0 && cs.type < 4) n[cs.type]++;
        if (cs.type == CLASS_EXCLUDED) exclFrames += cs.frameCount();
    }
    return String.format("classification: %d right / %d left / %d zero / %d excluded  (%.1fs cut)",
                         n[CLASS_RIGHT], n[CLASS_LEFT], n[CLASS_ZERO], n[CLASS_EXCLUDED],
                         exclFrames * 0.01f);
}
