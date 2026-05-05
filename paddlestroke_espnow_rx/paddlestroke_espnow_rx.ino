#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>

#define TFT_BL_PIN      21
#define SPLASH_MS       20000UL
#define SIGNAL_TIMEOUT  3000UL
#define FLASH_MS        500UL
#define ICON_R          10
#define GREY            ((uint16_t)0x9492)   // #909090 in RGB565

struct __attribute__((packed)) EspNowPayload {
    uint32_t cpm;
    float    hz;
};

TFT_eSPI tft;

volatile uint32_t g_cpm = 0;
volatile bool     g_new = false;
portMUX_TYPE      g_mux = portMUX_INITIALIZER_UNLOCKED;

static bool          hasReceived  = false;
static uint32_t      displayedCpm = 0;
static unsigned long lastRxMs     = 0;
static int           iconCx, iconCy;

// ── ESPnow callback (WiFi task context) ──────────────────────────────────────

void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    if (len != (int)sizeof(EspNowPayload)) return;
    EspNowPayload p;
    memcpy(&p, data, sizeof(p));
    portENTER_CRITICAL(&g_mux);
    g_cpm = p.cpm;
    g_new = true;
    portEXIT_CRITICAL(&g_mux);
}

// ── Display helpers ───────────────────────────────────────────────────────────

void clearAllPixels() {
    for (int r = 0; r < 4; r++) {
        tft.setRotation(r);
        tft.fillScreen(TFT_WHITE);
    }
    tft.setRotation(2);
}

void drawRate(uint32_t cpm, bool active) {
    uint16_t col    = active ? TFT_BLACK : GREY;
    int      w      = tft.width();
    int      h      = tft.height();
    int      usableW = w - (ICON_R * 2 + 16);  // leave room for icon column

    // Clear content area only (icon column stays untouched)
    tft.fillRect(0, 0, usableW, h, TFT_WHITE);

    // Large number — Font 8 (75px 7-segment style)
    tft.setTextFont(8);
    tft.setTextColor(col, TFT_WHITE);
    String s  = hasReceived ? String(cpm) : "--";
    int    tw = tft.textWidth(s);
    int    th = tft.fontHeight(8);
    int    x  = (usableW - tw) / 2;
    int    y  = (h - th) / 2 - 10;
    tft.setCursor(x, y);
    tft.print(s);

    // "CPM" sub-label — Font 4
    tft.setTextFont(4);
    tft.setTextColor(col, TFT_WHITE);
    String label = "CPM";
    tft.setCursor((usableW - tft.textWidth(label)) / 2, y + th + 4);
    tft.print(label);
}

void drawIcon(bool receiving, bool filled) {
    // Clear icon area
    tft.fillRect(iconCx - ICON_R - 2, 0, (ICON_R + 2) * 2, iconCy + ICON_R + 4, TFT_WHITE);

    if (receiving && filled) {
        tft.fillCircle(iconCx, iconCy, ICON_R, TFT_BLACK);
    } else if (receiving) {
        tft.drawCircle(iconCx, iconCy, ICON_R, TFT_BLACK);
    } else {
        tft.drawCircle(iconCx, iconCy, ICON_R, GREY);
    }
}

void fatalError(const char *msg) {
    tft.fillScreen(TFT_WHITE);
    tft.setTextFont(2);
    tft.setTextColor(TFT_RED, TFT_WHITE);
    int tw = tft.textWidth(msg);
    tft.setCursor((tft.width() - tw) / 2, tft.height() / 2 - 8);
    tft.print(msg);
    Serial.println(msg);
    while (true) delay(1000);
}

// ── Setup ─────────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);

    tft.init();
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);
    clearAllPixels();

    iconCx = tft.width()  - ICON_R - 8;
    iconCy = ICON_R + 8;

    // Splash screen
    tft.setTextFont(2);
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    const char *splash = "paddlestroke_espnow_rx";
    tft.setCursor((tft.width()  - tft.textWidth(splash)) / 2,
                  (tft.height() - tft.fontHeight(2))      / 2);
    tft.print(splash);

    // ESPnow init
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) fatalError("ESPnow init FAILED");
    esp_now_register_recv_cb(onReceive);

    delay(SPLASH_MS);

    // Initial main screen: -- CPM, grey, hollow icon (no signal yet)
    tft.fillScreen(TFT_WHITE);
    drawRate(0, false);
    drawIcon(false, false);
}

// ── Loop ──────────────────────────────────────────────────────────────────────

void loop() {
    // Consume any incoming packet
    uint32_t cpm = 0;
    bool     got = false;
    portENTER_CRITICAL(&g_mux);
    if (g_new) { cpm = g_cpm; got = true; g_new = false; }
    portEXIT_CRITICAL(&g_mux);

    if (got) {
        hasReceived  = true;
        lastRxMs     = millis();
        displayedCpm = cpm;
        drawRate(cpm, true);
        Serial.printf("RX: %u CPM\n", cpm);
    }

    bool receiving = hasReceived && (millis() - lastRxMs < SIGNAL_TIMEOUT);

    static bool          prevReceiving = false;
    static bool          iconFilled    = true;
    static unsigned long lastFlash     = 0;

    if (receiving != prevReceiving) {
        if (!receiving) {
            // Signal just lost — redraw rate in grey, static hollow icon
            drawRate(displayedCpm, false);
            drawIcon(false, false);
            Serial.println("Signal lost");
        } else {
            // Signal just acquired — start flashing icon immediately
            iconFilled = true;
            lastFlash  = millis();
            drawIcon(true, true);
        }
        prevReceiving = receiving;
    }

    // Flash icon while receiving
    if (receiving && (millis() - lastFlash >= FLASH_MS)) {
        lastFlash  = millis();
        iconFilled = !iconFilled;
        drawIcon(true, iconFilled);
    }
}
