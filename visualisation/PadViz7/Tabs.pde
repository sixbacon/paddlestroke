// Tabs — view-switch tab bar (v0.25, spec §14.10).
//
// Two mutually-exclusive full-window views share the sketch: the main 3D
// visualisation and the side-profile blade window (SideProfilePanel, key x).
// This bar draws a clickable tab for each, so they can be switched with the
// mouse as well as the keyboard — the active view's tab is highlighted. Clicks
// route through the same showSideProfile() helper the x key and Commands menu
// use, so keyboard and mouse never drift out of sync. (A third "track plot"
// tab is planned; the bar has room to take it later.)
//
// Placement: the top row is crowded — the HUD title runs left-of-centre and
// the axis legend sits centre-right — so the bar is docked into the gap
// between the axis legend and the right-hand panel (a constant ~230 px wide
// whatever the window size, since both scale with 0.8·width), right-aligned
// just left of where the right panel begins. That slot is clear in the 3D view
// and (title on the left, water label mid-height) in the side view too.
//
// It is hidden while the setup Wizard owns the screen, drawn LAST in draw(),
// and hit-tested AFTER the Commands drop-down, so an open menu still wins.

class Tabs {
    static final int TAB_W = 70;         // 30% narrower than v0.25's first cut (was 100)
    static final int TAB_H = 26;
    static final int TAB_Y = 6;
    static final int GAP   = 4;
    static final int RIGHT_MARGIN = 8;   // gap to the right-panel edge

    // Labels + the view each selects. index 0 = 3D scene, 1 = side profile.
    final String[] labels = { "3D VIEW", "SIDE PROFILE" };

    boolean visible() { return !(wizard != null && wizard.shown); }

    // Which tab is active right now (reads the real view state, so the
    // highlight is always correct however the view was last switched).
    int activeTab() { return sideActive() ? 1 : 0; }

    // Largest text size (<= start) at which s fits in maxW, floored at 8.
    float fitSize(String s, float maxW, float start) {
        float sz = start;
        textSize(sz);
        while (sz > 8 && textWidth(s) > maxW) { sz -= 0.5f; textSize(sz); }
        return sz;
    }

    int barW() { return labels.length * TAB_W + (labels.length - 1) * GAP; }
    // Left edge: right-aligned just inside the right-hand panel's left edge.
    int barX() { return width - rightPanelWidth() - RIGHT_MARGIN - barW(); }

    void draw() {
        if (!visible()) return;
        int active = activeTab();
        int x = barX();
        textAlign(CENTER, CENTER);
        for (int i = 0; i < labels.length; i++) {
            int tx = x + i * (TAB_W + GAP);
            boolean on = (i == active);
            // Body.
            noStroke();
            fill(on ? color(48, 78, 128) : color(34, 38, 46), on ? 255 : 230);
            rect(tx, TAB_Y, TAB_W, TAB_H, 6);
            // Border.
            noFill();
            stroke(on ? color(120, 165, 225) : color(78, 84, 94));
            strokeWeight(on ? 2 : 1);
            rect(tx, TAB_Y, TAB_W, TAB_H, 6);
            // Label — shrink the font per label so it fits the narrow tab.
            noStroke();
            fill(on ? color(232, 242, 255) : color(165, 172, 182));
            textSize(fitSize(labels[i], TAB_W - 10, 12));
            text(labels[i], tx + TAB_W / 2, TAB_Y + TAB_H / 2 + 1);
        }
        strokeWeight(1);
    }

    // Returns true if a tab was clicked (and the view switched).
    boolean mousePressed(int mx, int my) {
        if (!visible()) return false;
        if (my < TAB_Y || my > TAB_Y + TAB_H) return false;
        int x = barX();
        for (int i = 0; i < labels.length; i++) {
            int tx = x + i * (TAB_W + GAP);
            if (mx >= tx && mx <= tx + TAB_W) {
                showSideProfile(i == 1);   // 0 = 3D scene, 1 = side profile
                return true;
            }
        }
        return false;
    }
}
