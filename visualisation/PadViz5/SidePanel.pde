// SidePanel — slim right panel: file names, play/pause, speed slider

class SidePanel {
    int px, ph, pw;

    static final int MARGIN   = 10;
    static final int BUTTON_H = 28;
    static final int SLIDER_H = 18;
    static final float STEP_FRAC = 0.08f;

    int playBtnY, sliderY;

    SidePanel(int originX, int height, int width) {
        px = originX;  ph = height;  pw = width;
    }

    void draw(DataSource ds, BoatSource dsBoat, int frameIdx,
              FrameData fd, BoatFrameData bfd, float curSpeed, boolean playing) {
        pushMatrix();
        translate(px, 0);

        fill(40, 42, 52);  noStroke();  rect(0, 0, pw, ph);
        stroke(80);  line(0, 0, 0, ph);  noStroke();

        int y = MARGIN;

        // File names
        fill(160);  textSize(11);  textAlign(LEFT, TOP);
        String padName = ds.sourceName().length() > 0 ? ds.sourceName() : "(no ImuLog — press O)";
        text("PAD: " + padName, MARGIN, y);  y += 16;
        String boatName = dsBoat.sourceName().length() > 0 ? dsBoat.sourceName() : "(no BoatLog — press B)";
        text("BOAT: " + boatName, MARGIN, y);  y += 20;

        // Sync status
        if (ds.frameCount() > 0 && dsBoat.frameCount() > 0) {
            fill(100, 220, 100);
        } else {
            fill(180, 140, 60);
        }
        textSize(10);
        String syncLabel = (ds.frameCount() > 0 && dsBoat.frameCount() > 0)
            ? "SYNCED on gps_utc_sec"
            : "load both files to sync";
        text(syncLabel, MARGIN, y);  y += 18;

        // Play/pause
        playBtnY = y;
        int bw = pw - MARGIN * 2;
        fill(playing ? color(55, 130, 55) : color(110, 55, 55));
        noStroke();  rect(MARGIN, y, bw, BUTTON_H, 4);
        fill(255);  textSize(13);  textAlign(CENTER, CENTER);
        text(playing ? "||  PAUSE" : ">  PLAY", MARGIN + bw / 2, y + BUTTON_H / 2);
        y += BUTTON_H + 10;

        // Speed slider
        sliderY = y + 8;
        drawSpeedSlider(curSpeed);
        y += SLIDER_H + 26;

        // Frame info
        fill(140);  textSize(10);  textAlign(LEFT, TOP);
        if (ds.frameCount() > 0) {
            text("frame " + frameIdx + " / " + (ds.frameCount()-1), MARGIN, y);  y += 14;
            text("t = " + nf(fd.ts / 1000.0f, 0, 2) + " s", MARGIN, y);  y += 14;
        }

        // GPS time
        if (fd.gpsUtcSec > 0) {
            long localSec = fd.gpsUtcSec + 3600;
            int hh = (int)((localSec / 3600) % 24);
            int mm = (int)((localSec / 60) % 60);
            int ss = (int)(localSec % 60);
            fill(100, 200, 255);  textSize(11);
            text("GPS  " + String.format("%02d:%02d:%02d BST", hh, mm, ss), MARGIN, y);
            y += 16;
        }

        // Export button
        int ey = ph - MARGIN - BUTTON_H;
        fill(60, 60, 100);  noStroke();  rect(MARGIN, ey, bw, BUTTON_H, 4);
        fill(200);  textSize(12);  textAlign(CENTER, CENTER);
        text("Export zoom (E)", MARGIN + bw / 2, ey + BUTTON_H / 2);

        popMatrix();
    }

    void drawSpeedSlider(float curSpeed) {
        int sx = MARGIN, sw = pw - MARGIN * 2, sy = sliderY;
        fill(65);  noStroke();  rect(sx, sy, sw, SLIDER_H, 4);
        float t  = speedToT(curSpeed);
        int   tx = sx + (int)(t * sw);
        fill(220, 200, 60);  rect(tx - 4, sy - 2, 8, SLIDER_H + 4, 3);
        int stepX = sx + (int)(STEP_FRAC * sw);
        stroke(160, 80, 80);  strokeWeight(1);
        line(stepX, sy - 5, stepX, sy + SLIDER_H + 5);  noStroke();
        fill(155);  textSize(10);
        textAlign(LEFT,   BASELINE);  text("STEP", sx,        sy - 2);
        textAlign(CENTER, BASELINE);  text("1x",   sx + sw/2, sy - 2);
        textAlign(RIGHT,  BASELINE);  text("4x",   sx + sw,   sy - 2);
        String lbl = (curSpeed == SPEED_STEP) ? "step" : nf(curSpeed, 0, 2) + "x";
        fill(255, 220, 80);  textSize(11);  textAlign(CENTER, TOP);
        text(lbl, sx + sw / 2, sy + SLIDER_H + 3);
    }

    void mousePressed(int mx, int my, DataSource ds, int frameIdx) {
        // Play button
        if (my >= playBtnY && my < playBtnY + BUTTON_H) {
            togglePlayPause();
            return;
        }
        // Speed slider
        int sx = MARGIN, sw = pw - MARGIN * 2;
        if (my >= sliderY - 4 && my <= sliderY + SLIDER_H + 4 && mx >= sx && mx <= sx + sw) {
            applySlider(mx, sx, sw);
        }
        // Export button
        int ey = ph - MARGIN - BUTTON_H;
        if (my >= ey && my < ey + BUTTON_H) {
            selectOutput("Export merged CSV", "exportFileSelected");
        }
    }

    void mouseDragged(int mx, int my, DataSource ds) {
        int sx = MARGIN, sw = pw - MARGIN * 2;
        if (my >= sliderY - 8 && my <= sliderY + SLIDER_H + 8) {
            applySlider(mx, sx, sw);
        }
    }

    void mouseReleased() {}

    private void applySlider(int mx, int sx, int sw) {
        float t = constrain((float)(mx - sx) / sw, 0, 1);
        setPlaySpeed(tToSpeed(t));
    }

    float tToSpeed(float t) {
        if (t < STEP_FRAC) return SPEED_STEP;
        float nt = (t - STEP_FRAC) / (1.0f - STEP_FRAC);
        return exp(log(SPEED_MAX) * nt);
    }

    float speedToT(float spd) {
        if (spd == SPEED_STEP) return STEP_FRAC * 0.4f;
        float nt = log(max(spd, 0.01f)) / log(SPEED_MAX);
        return STEP_FRAC + nt * (1.0f - STEP_FRAC);
    }
}
