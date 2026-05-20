#include <TFT_eSPI.h>

TFT_eSPI tft;

static void clearAll(uint8_t settleRotation) {
    for (uint8_t r = 0; r < 4; r++) {
        tft.setRotation(r);
        tft.fillScreen(TFT_BLACK);
    }
    tft.setRotation(settleRotation);
}

void setup() {
    Serial.begin(115200);
    delay(200);

    pinMode(TFT_BL, OUTPUT);
    digitalWrite(TFT_BL, HIGH);

    tft.init();
    tft.invertDisplay(false);  // cancel ST7789 default INVON
    clearAll(1);               // rotation 1 = landscape on ST7789

    int w = tft.width();
    int h = tft.height();
    Serial.printf("ST7789 invertDisplay(false) rot=1  w=%d h=%d\n", w, h);

    // Left half: TFT_RED (0xF800)   Right half: 0x001F (BGR red, works on ILI9341)
    tft.fillRect(0,      0, w/2, h/2, TFT_RED);   // top-left
    tft.fillRect(w/2,    0, w/2, h/2, 0x001F);     // top-right
    tft.fillRect(0,   h/2, w/2, h/2, TFT_GREEN);  // bottom-left
    tft.fillRect(w/2, h/2, w/2, h/2, TFT_BLUE);   // bottom-right

    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setTextDatum(MC_DATUM);
    tft.drawString("TFT_RED",  w/4,   h/4, 2);
    tft.drawString("0x001F",   3*w/4, h/4, 2);
    tft.drawString("TFT_GREEN",w/4,   3*h/4, 2);
    tft.drawString("TFT_BLUE", 3*w/4, 3*h/4, 2);

    Serial.println("Top-left=TFT_RED  Top-right=0x001F  BL=TFT_GREEN  BR=TFT_BLUE");
    Serial.println("Which top quadrant looks red?");
}

void loop() {
    static bool on = false;
    static uint32_t last = 0;
    if (millis() - last > 500) {
        last = millis();
        on = !on;
        // blink both so we can see the colours in motion
        int w = tft.width(), h = tft.height();
        uint16_t c = on ? TFT_YELLOW : TFT_BLACK;
        tft.fillCircle(w/4, h/2, 8, c);      // centre-left dot: TFT_YELLOW
        c = on ? 0x001F : TFT_BLACK;
        tft.fillCircle(3*w/4, h/2, 8, c);    // centre-right dot: 0x001F
    }
}
