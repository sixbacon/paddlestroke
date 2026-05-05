// Diagnostic sketch — find correct rotation for CYD2USB.
// Cycles through rotations 0-3 every 4 seconds.
// Note which rotation number fills the whole screen with no noise strip
// and reads correctly (text right-way up, TL/TR/BL/BR in correct corners).

#include <TFT_eSPI.h>

#define TFT_BL_PIN 21

TFT_eSPI tft;
uint8_t  currentRot = 0;

void showRotation(uint8_t rot) {
    tft.setRotation(rot);
    uint16_t w = tft.width();
    uint16_t h = tft.height();

    tft.fillScreen(TFT_WHITE);
    tft.setTextColor(TFT_BLACK, TFT_WHITE);

    // 2-pixel border so we can see if it reaches all four edges
    tft.drawRect(0,     0,     w,   h,   TFT_BLACK);
    tft.drawRect(1,     1,     w-2, h-2, TFT_BLACK);

    // Corner labels
    tft.setTextSize(2);
    tft.setCursor(4, 4);           tft.print("TL");
    tft.setCursor(w - 36, 4);     tft.print("TR");
    tft.setCursor(4, h - 20);     tft.print("BL");
    tft.setCursor(w - 36, h - 20);tft.print("BR");

    // Dimensions line
    tft.setTextSize(2);
    tft.setCursor(4, 28);
    tft.printf("ROT %d   %d x %d", rot, w, h);

    // Large rotation digit in centre using font 8 (75 px, digits only)
    tft.setTextSize(1);
    tft.setTextFont(8);
    // font-8 digit is ~55 px wide × 75 px tall
    tft.setCursor(w / 2 - 28, h / 2 - 38);
    tft.print(rot);
    tft.setTextFont(1);  // reset

    Serial.printf("Showing rotation %d: %d x %d\n", rot, w, h);
}

void setup() {
    Serial.begin(115200);
    tft.init();
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);
    showRotation(0);
}

void loop() {
    delay(4000);
    currentRot = (currentRot + 1) % 4;
    showRotation(currentRot);
}
