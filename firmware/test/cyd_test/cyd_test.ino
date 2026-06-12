#include <TFT_eSPI.h>

#define TFT_BL_PIN  21
#define UPDATE_MS   5000
#define COUNT_MAX   20

TFT_eSPI tft;
int count = 0;

void drawCount() {
    int w = tft.width();
    int h = tft.height();

    tft.fillScreen(TFT_WHITE);

    // Large centred number using Font 8 (75 px 7-segment style)
    tft.setTextFont(8);
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    String s = String(count);
    int tw = tft.textWidth(s);
    int th = tft.fontHeight(8);
    int x  = (w - tw) / 2;
    int y  = (h - th) / 2 - 10;
    tft.setCursor(x, y);
    tft.print(s);

    // "CPM" label in Font 4 below the number
    tft.setTextFont(4);
    tft.setTextColor(TFT_DARKGREY, TFT_WHITE);
    String label = "CPM";
    tft.setCursor((w - tft.textWidth(label)) / 2, y + th + 4);
    tft.print(label);

    Serial.printf("count=%d  display=%dx%d  num_xy=(%d,%d)\n",
                  count, w, h, x, y);
}

void setup() {
    Serial.begin(115200);
    tft.init();
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);
    for (int r = 0; r < 4; r++) {
        tft.setRotation(r);
        tft.fillScreen(TFT_WHITE);
    }
    tft.setRotation(2);
    drawCount();
}

void loop() {
    static unsigned long last = 0;
    if (millis() - last >= UPDATE_MS) {
        last = millis();
        count = (count >= COUNT_MAX) ? 0 : count + 1;
        drawCount();
    }
}
