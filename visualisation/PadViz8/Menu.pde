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

    // Button rect (relative to the visualisation-area left edge). Sits
    // below the "PadViz6..." title line, same row as DetailPanel's button
    // (notes 20 Jul 2026 — title used to share this row, now has its own).
    static final int BTN_W = 118;
    static final int BTN_H = 26;
    static final int BTN_Y = 38;

    // Drop-down layout.
    static final int ROW_H   = 22;
    static final int HDR_H   = 26;
    static final int DROP_W  = 340;
    static final int SCROLLBAR_W = 12;

    ArrayList<MenuItem> items = new ArrayList<MenuItem>();

    // Vertical scroll state for the drop-down when the list is taller than the
    // window (v0.16 — the full list ran off the bottom of the page). scrollY is
    // the pixel offset of the content; the thumb drags, the wheel scrolls, and
    // clicking the track pages.
    int     scrollY = 0;
    boolean scrollDragging = false;
    float   scrollDragStartMouse  = 0;
    int     scrollDragStartScroll = 0;

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
        items.add(new MenuItem("y", "  └ relative-yaw source: GRV <-> fused", 'y', 0));
        items.add(new MenuItem("Bksp", "Previous slice (ping-pong)", (char) 8, 0));
        items.add(header("ANALYSIS WINDOWS"));
        items.add(new MenuItem("w", "Session-setup wizard (show / hide)",         'w', 0));
        items.add(new MenuItem("x", "Side-profile blade window (ZY plane, L/R)",  'x', 0));
        items.add(new MenuItem("f", "  └ flip left-blade view (bow to right)",  'f', 0));
        items.add(new MenuItem("t", "Track window (GPS over OpenStreetMap)",      't', 0));
        items.add(header("CLASSIFICATION"));
        items.add(new MenuItem("q", "Clear ALL classification",                    'q', 0));
        items.add(header("CAMERA"));
        items.add(new MenuItem("V", "Snap side / top preset (recentres)", 'V', 0));
        items.add(info("drag",  "orbit camera (left-drag in 3D area)"));
        items.add(info("wheel", "zoom in / out"));
        items.add(header("CALIBRATION"));
        items.add(new MenuItem("k", "Capture reference (mean ±50 frames)", 'k', 0));
        items.add(new MenuItem("u", "Clear reference",                     'u', 0));
        items.add(new MenuItem("m", "Paddle length / blade / feather (review last, accept or edit)", 'm', 0));
        items.add(new MenuItem("C", "Build session sidecar (asks lengths, from cursor)", 'C', 0));
        items.add(header("GRAPH"));
        items.add(new MenuItem("S", "Reset graph zoom to full range", 'S', 0));
        items.add(info("click",   "seek playback cursor"));
        items.add(info("R-click", "x2 = zoom to span; double = revert"));
        items.add(header("ENTRY/EXIT PANEL (left)"));
        items.add(info("R-click", "clear accumulated entry/exit dots"));
        items.add(header("STROKE AVERAGE PANEL (right)"));
        items.add(info("R-click", "restart average trace accumulation"));
        items.add(new MenuItem("o", "Mirror right blade onto left (compare symmetry)", 'o', 0));
        items.add(header("DETAIL PANEL"));
        items.add(info("click", "\"Detail\" button (below Commands) toggles it"));
        // n/N/g work in every slice (not just Slice 0) so the panel can be
        // watched while nudging — see keyPressed()'s comment, notes 20 Jul
        // 2026. Readout of the numbers is still Slice-0-only.
        items.add(new MenuItem("n", "Nudge yaw datum + step (needs sidecar — C first)", 'n', 0));
        items.add(new MenuItem("N", "Nudge yaw datum − step",                          'N', 0));
        items.add(new MenuItem("g", "Reset yaw datum manual adjust to 0",              'g', 0));
        if (sliceMode == 0) {
            items.add(header("SLICE 0 KEYS"));
            items.add(info("y/Y i/I r/R", "nudge model yaw / pitch / roll"));
            items.add(info("[ / ]", "halve / double step"));
            items.add(info("Z / S / L", "zero / save / list triple"));
        }
    }

    int dropHeight() {
        int h = 6;
        for (MenuItem m : items) h += m.header ? HDR_H : ROW_H;
        return h + 4;
    }

    int dropTopY() { return BTN_Y + BTN_H + 4; }

    // Vertical space available for the open drop-down: from just under the
    // button down to the top of the graph strip (or the window bottom in
    // Slice 0, which has no graph). Floored so it's always usable.
    int dropMaxH() {
        int bottomLimit = isGraphVisible() ? (height - GRAPH_H - 8) : (height - 8);
        return max(140, bottomLimit - dropTopY());
    }

    // Scrollbar track/thumb geometry, valid when the list overflows.
    // Returns { trackX, trackY, trackH, thumbY, thumbH }.
    float[] scrollbarGeom(int dx, int dy, int viewH, int fullH) {
        float trackX = dx + DROP_W - SCROLLBAR_W;
        float trackY = dy + 4;
        float trackH = viewH - 8;
        float thumbH = max(26, trackH * viewH / (float) fullH);
        int   ms     = max(1, fullH - viewH);
        float thumbY = trackY + (trackH - thumbH) * (scrollY / (float) ms);
        return new float[]{ trackX, trackY, trackH, thumbY, thumbH };
    }

    void drawScrollbar(int dx, int dy, int viewH, int fullH) {
        float[] g = scrollbarGeom(dx, dy, viewH, fullH);
        noStroke();
        fill(55, 55, 55, 245);                        // track
        rect(g[0], g[1], SCROLLBAR_W - 3, g[2], 4);
        boolean over = mouseX >= g[0] && mouseX <= g[0] + SCROLLBAR_W
                     && mouseY >= g[3] && mouseY <= g[3] + g[4];
        fill(scrollDragging || over ? color(175, 195, 225) : color(135, 145, 160));
        rect(g[0], g[3], SCROLLBAR_W - 3, g[4], 4);    // thumb
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

        int dx    = bx;
        int dy    = dropTopY();
        int fullH = dropHeight();
        int viewH = min(fullH, dropMaxH());
        boolean sb = fullH > viewH;
        scrollY = constrain(scrollY, 0, max(0, fullH - viewH));
        int contentW = DROP_W - (sb ? SCROLLBAR_W : 0);

        // Panel background — only the visible viewport tall, not the full list.
        stroke(110, 130, 170);  strokeWeight(1.5);
        fill(80, 80, 80);        // opaque neutral grey — must fully cover the
                                 // scene/graph behind or the text is unreadable
        rect(dx, dy, DROP_W, viewH, 6);
        strokeWeight(1);  noStroke();

        // No clip() here on purpose: in P3D clip() flushes the pipeline and
        // the depth test comes back on for everything drawn after it, so the
        // axis compass behind the menu punched through the drop-down text
        // (the background rect above is drawn before any clip, which is why the
        // panel looked fine but the text didn't). Instead we cull to rows that
        // fit entirely inside the viewport — a partial row at a scroll boundary
        // is simply hidden, and the scrollbar shows there's more.
        int y = dy + 6 - scrollY;
        for (MenuItem m : items) {
            int rh = m.header ? HDR_H : ROW_H;
            if (y < dy + 4 || y + rh > dy + viewH - 2) { y += rh; continue; }
            if (m.header) {
                fill(130, 155, 200);
                textSize(11);  textAlign(LEFT, TOP);
                text(m.desc, dx + 12, y + 8);
                y += rh;
                continue;
            }
            boolean hover = !m.info && mouseX >= dx && mouseX <= dx + contentW
                                     && mouseY >= y  && mouseY <  y + ROW_H
                                     && mouseY >= dy && mouseY <= dy + viewH;
            if (hover) {
                fill(50, 62, 92);
                rect(dx + 4, y, contentW - 8, ROW_H, 4);
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

        // Scrollbar (slide bar) on the right edge when the list overflows.
        if (sb) drawScrollbar(dx, dy, viewH, fullH);

        textAlign(LEFT, TOP);
    }

    // Absolute coords. Returns true if the click was consumed by the menu.
    boolean mousePressed(int mx, int my) {
        int bx = btnX();
        if (mx >= bx && mx <= bx + BTN_W && my >= BTN_Y && my <= BTN_Y + BTN_H) {
            open = !open;
            if (open) scrollY = 0;   // reopen at the top of the list
            return true;
        }
        if (!open) return false;

        rebuild();
        int dx    = bx;
        int dy    = dropTopY();
        int fullH = dropHeight();
        int viewH = min(fullH, dropMaxH());
        boolean sb = fullH > viewH;
        scrollY = constrain(scrollY, 0, max(0, fullH - viewH));

        // Click outside the visible viewport closes the menu.
        if (mx < dx || mx > dx + DROP_W || my < dy || my > dy + viewH) {
            open = false;      // click-away closes; not consumed further
            return false;
        }

        // Scrollbar: grab the thumb to drag, or click the track to page.
        if (sb) {
            float[] g = scrollbarGeom(dx, dy, viewH, fullH);
            if (mx >= g[0]) {
                if (my >= g[3] && my <= g[3] + g[4]) {
                    scrollDragging        = true;
                    scrollDragStartMouse  = my;
                    scrollDragStartScroll = scrollY;
                } else {
                    int page = viewH - ROW_H;
                    scrollY = (my < g[3]) ? max(0, scrollY - page)
                                          : min(fullH - viewH, scrollY + page);
                }
                return true;
            }
        }

        int contentW = DROP_W - (sb ? SCROLLBAR_W : 0);
        int y = dy + 6 - scrollY;
        for (MenuItem m : items) {
            int rh = m.header ? HDR_H : ROW_H;
            if (!m.header && !m.info && mx <= dx + contentW
                && my >= y && my < y + rh && my >= dy && my <= dy + viewH) {
                open = false;
                fireItem(m);
                return true;
            }
            y += rh;
        }
        return true;   // inside drop-down chrome
    }

    // Mouse wheel over the open drop-down scrolls the list. Returns true if
    // consumed so the sketch's 3D/graph zoom doesn't also fire.
    boolean mouseWheel(int count) {
        if (!open) return false;
        rebuild();
        int dx    = btnX();
        int dy    = dropTopY();
        int fullH = dropHeight();
        int viewH = min(fullH, dropMaxH());
        if (mouseX < dx || mouseX > dx + DROP_W || mouseY < dy || mouseY > dy + viewH)
            return false;
        if (fullH > viewH)
            scrollY = constrain(scrollY + count * ROW_H, 0, fullH - viewH);
        return true;
    }

    // Scrollbar thumb drag. Returns true while a drag is in progress.
    boolean mouseDragged(int mx, int my) {
        if (!scrollDragging) return false;
        rebuild();
        int fullH = dropHeight();
        int viewH = min(fullH, dropMaxH());
        float trackH = viewH - 8;
        float thumbH = max(26, trackH * viewH / (float) fullH);
        float usable = trackH - thumbH;
        int   ms     = max(1, fullH - viewH);
        if (usable > 0) {
            float d = (my - scrollDragStartMouse) / usable * ms;
            scrollY = (int) constrain(scrollDragStartScroll + d, 0, fullH - viewH);
        }
        return true;
    }

    boolean mouseReleased() {
        if (scrollDragging) { scrollDragging = false; return true; }
        return false;
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
