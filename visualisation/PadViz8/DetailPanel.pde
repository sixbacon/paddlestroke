// DetailPanel — collapsible box for the HUD text that used to be drawn
// straight onto the 3D view: sidecar/yaw-datum corrections and the
// per-slice current-data-point readout (drawHUD_slice0/A/B/C in
// PadViz6.pde, unchanged internally). Minimised shows only a "Detail ▾"
// label; the mode/camera title line above it stays always visible.
// Mirrors Menu.pde's toggle-button pattern (notes 20 Jul 2026, spec §13.8).
//
// The button and box are drawn inside drawHUD()'s translate(leftPanelWidth(),
// 0) block (same local coordinate system drawHUD_sliceX() already uses),
// so mousePressed() below re-adds that offset to match against the real
// (untranslated) mouse position.
//
// Button sits on the same row as Menu's "Commands" button, immediately to
// its right (BTN_X = Menu's local x 20 + BTN_W 118 + 10 px gap = 148), same
// BTN_Y/BTN_H so both tops and bottoms line up — the title line moved to
// its own row above them (notes 20 Jul 2026).

class DetailPanel {
    boolean open = true;

    static final int BTN_X = 148;
    static final int BTN_Y = 38;
    static final int BTN_W = 100;
    static final int BTN_H = 26;

    static final int BOX_X = 10;
    static final int BOX_Y = BTN_Y + BTN_H + 6;
    static final int BOX_W = 680;
    static final int BOX_H = 330;

    void drawButton() {
        stroke(open ? color(140, 180, 240) : color(100, 120, 160));
        strokeWeight(1.5);
        fill(open ? color(45, 55, 85) : color(34, 40, 54));
        rect(BTN_X, BTN_Y, BTN_W, BTN_H, 5);
        strokeWeight(1);  noStroke();
        fill(210, 225, 250);
        textSize(12);  textAlign(CENTER, CENTER);
        text("Detail " + (open ? "▴" : "▾"), BTN_X + BTN_W / 2, BTN_Y + BTN_H / 2);
        textAlign(LEFT, TOP);
    }

    void drawBox() {
        stroke(70, 80, 100);  strokeWeight(1);
        fill(20, 22, 30, 210);
        rect(BOX_X, BOX_Y, BOX_W, BOX_H, 6);
        noStroke();
        strokeWeight(1);
    }

    // mx/my are absolute window coordinates.
    boolean mousePressed(int mx, int my) {
        int bx = leftPanelWidth() + BTN_X;
        if (mx >= bx && mx <= bx + BTN_W && my >= BTN_Y && my <= BTN_Y + BTN_H) {
            open = !open;
            return true;
        }
        return false;
    }
}
