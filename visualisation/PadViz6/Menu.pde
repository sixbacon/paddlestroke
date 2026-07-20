// Menu — "Commands ▾" pull-down (v0.14, spec §13.2).
//
// Replaces the static left-edge key-list HUD. The button sits top-left of
// the visualisation area (right of the entry/exit panel when visible); the
// drop-down lists every binding, grouped, with the key shown as a badge.
// Clicking an actionable row synthesises the same keystroke the keyboard
// path uses (single code path — the menu never re-implements a command).
// Info-only rows (mouse gestures) render dimmed and are not clickable.

class MenuItem {
    String keyLabel;   // what to show in the key badge ("p", "Space", "←/→"…)
    String desc;
    char   ch;         // synthesised key ( 0 = none )
    int    code;       // synthesised keyCode for CODED keys ( 0 = none )
    boolean header;    // section header row
    boolean info;      // non-clickable informational row

    MenuItem(String k, String d, char c, int kc) {
        keyLabel = k; desc = d; ch = c; code = kc; header = false; info = false;
    }
}

class Menu {
    boolean open = false;

    // Button rect (relative to the visualisation-area left edge).
    static final int BTN_W = 118;
    static final int BTN_H = 26;
    static final int BTN_Y = 10;

    // Drop-down layout.
    static final int ROW_H   = 22;
    static final int HDR_H   = 26;
    static final int DROP_W  = 340;

    ArrayList<MenuItem> items = new ArrayList<MenuItem>();

    int btnX() { return leftPanelWidth() + 20; }

    MenuItem header(String title) {
        MenuItem m = new MenuItem("", title, (char) 0, 0);
        m.header = true;
        return m;
    }

    MenuItem info(String k, String d) {
        MenuItem m = new MenuItem(k, d, (char) 0, 0);
        m.info = true;
        return m;
    }

    // Rebuild each frame — cheap, and lets the content follow the slice.
    void rebuild() {
        items.clear();
        items.add(header("FILES"));
        items.add(new MenuItem("p", "Open paddle CSV", 'p', 0));
        items.add(new MenuItem("b", "Open boat CSV",   'b', 0));
        items.add(new MenuItem("E", "Export merged CSV (current zoom)", 'E', 0));
        items.add(header("PLAYBACK"));
        items.add(new MenuItem("Space", "Play / pause",        ' ', 0));
        items.add(new MenuItem("<-",    "Step back 100 frames",  (char) 0, LEFT));
        items.add(new MenuItem("->",    "Step forward 100 frames",(char) 0, RIGHT));
        items.add(new MenuItem(",",     "Step back 1 frame",     ',', 0));
        items.add(new MenuItem(".",     "Step forward 1 frame",  '.', 0));
        items.add(new MenuItem(">",     "Fast replay (x2, repeatable)", '>', 0));
        items.add(new MenuItem("<",     "Reset replay speed to x1",     '<', 0));
        items.add(new MenuItem("Home",  "Jump to start",         (char) 0, 36));
        items.add(new MenuItem("End",   "Jump to end",           (char) 0, 35));
        items.add(header("SLICES"));
        items.add(new MenuItem("0", "Slice 0 — model calibration", '0', 0));
        items.add(new MenuItem("1", "Slice A — paddle",            '1', 0));
        items.add(new MenuItem("2", "Slice B — kayak",             '2', 0));
        items.add(new MenuItem("3", "Slice C — combined",          '3', 0));
        items.add(new MenuItem("Bksp", "Previous slice (ping-pong)", (char) 8, 0));
        items.add(header("CAMERA"));
        items.add(new MenuItem("V", "Snap side / top preset (recentres)", 'V', 0));
        items.add(info("drag",  "orbit camera (left-drag in 3D area)"));
        items.add(info("wheel", "zoom in / out"));
        items.add(header("CALIBRATION"));
        items.add(new MenuItem("k", "Capture reference (mean ±50 frames)", 'k', 0));
        items.add(new MenuItem("u", "Clear reference",                     'u', 0));
        items.add(new MenuItem("C", "Build session sidecar (from cursor)", 'C', 0));
        items.add(header("GRAPH"));
        items.add(new MenuItem("S", "Reset graph zoom to full range", 'S', 0));
        items.add(info("click",   "seek playback cursor"));
        items.add(info("R-click", "x2 = zoom to span; double = revert"));
        items.add(header("ENTRY/EXIT PANEL"));
        items.add(info("R-click", "clear accumulated entry/exit dots"));
        if (sliceMode == 0) {
            items.add(header("SLICE 0 KEYS"));
            items.add(info("y/Y i/I r/R", "nudge model yaw / pitch / roll"));
            items.add(info("[ / ]", "halve / double step"));
            items.add(info("Z / S / L", "zero / save / list triple"));
            items.add(info("n/N", "nudge entry/exit yaw datum (manual)"));
            items.add(info("g", "reset entry/exit yaw datum to 0"));
        }
    }

    int dropHeight() {
        int h = 6;
        for (MenuItem m : items) h += m.header ? HDR_H : ROW_H;
        return h + 4;
    }

    void draw() {
        int bx = btnX();

        // Button.
        stroke(open ? color(140, 180, 240) : color(100, 120, 160));
        strokeWeight(1.5);
        fill(open ? color(45, 55, 85) : color(34, 40, 54));
        rect(bx, BTN_Y, BTN_W, BTN_H, 5);
        strokeWeight(1);  noStroke();
        fill(210, 225, 250);
        textSize(13);  textAlign(CENTER, CENTER);
        text("Commands " + (open ? "▴" : "▾"), bx + BTN_W / 2, BTN_Y + BTN_H / 2);
        textAlign(LEFT, TOP);

        if (!open) return;
        rebuild();

        int dx = bx;
        int dy = BTN_Y + BTN_H + 4;
        int dh = dropHeight();

        stroke(110, 130, 170);  strokeWeight(1.5);
        fill(24, 27, 36, 245);
        rect(dx, dy, DROP_W, dh, 6);
        strokeWeight(1);  noStroke();

        int y = dy + 6;
        for (MenuItem m : items) {
            if (m.header) {
                fill(130, 155, 200);
                textSize(11);
                text(m.desc, dx + 12, y + 8);
                y += HDR_H;
                continue;
            }
            boolean hover = !m.info && mouseX >= dx && mouseX <= dx + DROP_W
                                     && mouseY >= y  && mouseY <  y + ROW_H;
            if (hover) {
                fill(50, 62, 92);
                rect(dx + 4, y, DROP_W - 8, ROW_H, 4);
            }
            // Key badge.
            fill(m.info ? color(120) : color(200, 220, 255));
            textSize(11);  textAlign(RIGHT, CENTER);
            text(m.keyLabel, dx + 74, y + ROW_H / 2);
            // Description.
            fill(m.info ? color(130) : color(215));
            textAlign(LEFT, CENTER);
            text(m.desc, dx + 84, y + ROW_H / 2);
            y += ROW_H;
        }
        textAlign(LEFT, TOP);
    }

    // Absolute coords. Returns true if the click was consumed by the menu.
    boolean mousePressed(int mx, int my) {
        int bx = btnX();
        if (mx >= bx && mx <= bx + BTN_W && my >= BTN_Y && my <= BTN_Y + BTN_H) {
            open = !open;
            return true;
        }
        if (!open) return false;

        rebuild();
        int dx = bx;
        int dy = BTN_Y + BTN_H + 4;
        int dh = dropHeight();
        if (mx < dx || mx > dx + DROP_W || my < dy || my > dy + dh) {
            open = false;      // click-away closes; not consumed further
            return false;
        }

        int y = dy + 6;
        for (MenuItem m : items) {
            int rh = m.header ? HDR_H : ROW_H;
            if (!m.header && !m.info && my >= y && my < y + rh) {
                open = false;
                fireItem(m);
                return true;
            }
            y += rh;
        }
        return true;   // inside drop-down chrome
    }

    // Synthesise the keystroke so the keyboard handler stays the single
    // source of command behaviour.
    void fireItem(MenuItem m) {
        if (m.code != 0) {
            key     = (char) CODED;
            keyCode = m.code;
        } else {
            key     = m.ch;
            keyCode = 0;
        }
        keyPressed();
    }

    void handleEscape() { open = false; }
}
