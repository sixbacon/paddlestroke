#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <SPI.h>
#include <SD.h>

#define SKETCH_NAME    "PadDis"
#define SKETCH_VERSION "8.8"

// ── Payload struct — must match PadLog (PadLog.ino) exactly ──────────────────
struct __attribute__((packed)) ImuDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    float    accel_x, accel_y, accel_z;
    float    q_w, q_x, q_y, q_z;
    float    roll, pitch, yaw;
    uint32_t stroke_count;
    uint32_t cpm;
    float    hz;
};
static_assert(sizeof(ImuDataPayload) == 60, "Payload size mismatch — check struct");

// ── Pin assignments ───────────────────────────────────────────────────────────
#define TFT_BL_PIN  21
// SD card on VSPI — independent bus from display HSPI (no conflict)
#define SD_CS    5
#define SD_SCK  18
#define SD_MOSI 23
#define SD_MISO 19

// ── Display constants ─────────────────────────────────────────────────────────
#define SPLASH_MS      20000UL
#define SIGNAL_TIMEOUT  3000UL
#define FLASH_MS         500UL
#define ICON_R              10
#define GREY  ((uint16_t)0x9492)   // #909090 in RGB565

// ── SD logging ────────────────────────────────────────────────────────────────
#define FLUSH_INTERVAL_MS 5000UL

// Comment out to log all payload fields; leave defined for the compact fieldset.
// Reduced set:  timestamp_ms, roll, pitch, yaw, stroke_count, cpm
// Full set:     seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll, pitch, yaw, stroke_count, cpm, hz
// v8.8: full set enabled for PadViz4 position-tracking data collection
//#define CSV_COLUMNS_REDUCED

// ── CPM display EMA ───────────────────────────────────────────────────────────
// 10-second time constant at 100 Hz: alpha = 1 - exp(-0.01/10) ≈ 0.001
// Raw pkt.cpm is written to SD unchanged; only the displayed value is smoothed.
#define CPM_EMA_ALPHA 0.001f

// ── Ring buffer (WiFi task Core 0 → loop Core 1) ─────────────────────────────
#define RING_SIZE 32
static ImuDataPayload rxRing[RING_SIZE];
static volatile int   rxHead = 0;
static volatile int   rxTail = 0;
portMUX_TYPE          rxMux  = portMUX_INITIALIZER_UNLOCKED;

TFT_eSPI  tft;
SPIClass  sdSpi(VSPI);
static bool   sdReady       = false;
static File   logFile;

static bool          hasReceived  = false;
static uint32_t      displayedCpm = UINT32_MAX;   // force first draw
static unsigned long lastRxMs     = 0;
static int           iconCx, iconCy;

// ── CPM EMA state ─────────────────────────────────────────────────────────────
static float cpmEma    = 0.0f;
static bool  cpmSeeded = false;

// ── ESPnow callback (Core 0) ──────────────────────────────────────────────────
void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    if (len != (int)sizeof(ImuDataPayload)) return;
    ImuDataPayload p;
    memcpy(&p, data, sizeof(p));
    portENTER_CRITICAL(&rxMux);
    int next = (rxHead + 1) % RING_SIZE;
    if (next != rxTail) {
        rxRing[rxHead] = p;
        rxHead         = next;
    }
    portEXIT_CRITICAL(&rxMux);
}

// ── Display helpers ───────────────────────────────────────────────────────────
static void clearAllPixels() {
    for (int r = 0; r < 4; r++) { tft.setRotation(r); tft.fillScreen(TFT_BLACK); }
    tft.setRotation(2);
}

static void drawRate(uint32_t cpm, bool active) {
    uint16_t col     = active ? TFT_WHITE : GREY;
    int      w       = tft.width();
    int      h       = tft.height();
    int      usableW = w - (ICON_R * 2 + 16);
    tft.fillRect(0, 0, usableW, h, TFT_BLACK);
    tft.setTextFont(8);
    tft.setTextColor(col, TFT_BLACK);
    String s  = hasReceived ? String(cpm) : "--";
    int    tw = tft.textWidth(s);
    int    th = tft.fontHeight(8);
    int    x  = (usableW - tw) / 2;
    int    y  = (h - th) / 2;
    tft.setCursor(x, y);
    tft.print(s);
    tft.setTextFont(4);
    tft.setTextColor(col, TFT_BLACK);
    String label = "CPM";
    tft.setCursor((usableW - tft.textWidth(label)) / 2, y + th + 4);
    tft.print(label);
}

static void drawIcon(bool receiving, bool filled) {
    tft.fillRect(iconCx - ICON_R - 2, 0, (ICON_R + 2) * 2, iconCy + ICON_R + 4, TFT_BLACK);
    if (receiving && filled)  tft.fillCircle(iconCx, iconCy, ICON_R, TFT_WHITE);
    else if (receiving)       tft.drawCircle(iconCx, iconCy, ICON_R, TFT_WHITE);
    else                      tft.drawCircle(iconCx, iconCy, ICON_R, GREY);
}

static void fatalError(const char *msg) {
    tft.fillScreen(TFT_BLACK);
    tft.setTextFont(2);
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.setCursor((tft.width() - tft.textWidth(msg)) / 2, tft.height() / 2 - 8);
    tft.print(msg);
    Serial.println(msg);
    while (true) delay(1000);
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println(SKETCH_NAME " v" SKETCH_VERSION " — starting");

    tft.init();
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);
    clearAllPixels();

    iconCx = tft.width()  - ICON_R - 8;
    iconCy = ICON_R + 8;

    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    const char *splash = SKETCH_NAME " v" SKETCH_VERSION;
    int splashY = (tft.height() - tft.fontHeight(4)) / 2;
    tft.setCursor((tft.width() - tft.textWidth(splash)) / 2, splashY);
    tft.print(splash);

    // SD card (VSPI — separate bus from display)
    sdSpi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    if (!SD.begin(SD_CS, sdSpi, 4000000)) {
        Serial.println("SD init failed — logging disabled");
    } else {
        char fname[] = "/ImuLog00.CSV";
        for (int i = 0; i < 100; i++) {
            fname[7] = '0' + i / 10;
            fname[8] = '0' + i % 10;
            if (!SD.exists(fname)) break;
        }
        logFile = SD.open(fname, FILE_WRITE);
        if (!logFile) {
            Serial.println("SD file open failed — logging disabled");
        } else {
            logFile.println("# " SKETCH_NAME " v" SKETCH_VERSION);
#ifdef CSV_COLUMNS_REDUCED
            logFile.println("timestamp_ms,roll,pitch,yaw,stroke_count,cpm");
#else
            logFile.println("seq,timestamp_ms,"
                            "accel_x,accel_y,accel_z,"
                            "q_w,q_x,q_y,q_z,"
                            "roll,pitch,yaw,"
                            "stroke_count,cpm,hz");
#endif
            Serial.print("Logging to "); Serial.println(fname);
            sdReady = true;
        }
    }

    // Warn on splash screen if SD unavailable (0x07FF = yellow on BGR ILI9341)
    if (!sdReady) {
        const char *warn = "NO SD CARD — logging disabled";
        tft.setTextFont(2);
        tft.setTextColor(0x07FF, TFT_BLACK);
        tft.setCursor((tft.width() - tft.textWidth(warn)) / 2,
                      splashY + tft.fontHeight(4) + 10);
        tft.print(warn);
    }

    // ESPnow
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) fatalError("ESPnow init FAILED");
    esp_now_register_recv_cb(onReceive);

    delay(SPLASH_MS);

    tft.fillScreen(TFT_BLACK);
    drawRate(0, false);
    drawIcon(false, false);
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    // Drain one packet per iteration
    ImuDataPayload pkt;
    bool got = false;
    portENTER_CRITICAL(&rxMux);
    if (rxHead != rxTail) {
        pkt    = rxRing[rxTail];
        rxTail = (rxTail + 1) % RING_SIZE;
        got    = true;
    }
    portEXIT_CRITICAL(&rxMux);

    if (got) {
        hasReceived = true;
        lastRxMs    = millis();

        // Log every packet to SD (raw pkt.cpm — not EMA-smoothed)
        if (sdReady) {
#ifdef CSV_COLUMNS_REDUCED
            char row[80];
            int n = snprintf(row, sizeof(row),
                "%u,%.5f,%.5f,%.5f,%u,%u\n",
                pkt.timestamp_ms,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count, pkt.cpm);
#else
            char row[192];
            int n = snprintf(row, sizeof(row),
                "%u,%u,%.5f,%.5f,%.5f,%.8f,%.8f,%.8f,%.8f,%.5f,%.5f,%.5f,%u,%u,%.3f\n",
                pkt.seq, pkt.timestamp_ms,
                pkt.accel_x, pkt.accel_y, pkt.accel_z,
                pkt.q_w, pkt.q_x, pkt.q_y, pkt.q_z,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count, pkt.cpm, pkt.hz);
#endif
            logFile.write((const uint8_t*)row, n);
        }

        // EMA smoothing for the displayed CPM (10-second time constant at 100 Hz).
        // Pre-seed to first received value so there is no warm-up ramp.
        // Reset immediately to 0 on inactivity (pkt.cpm == 0).
        if (pkt.cpm == 0) {
            cpmEma    = 0.0f;
            cpmSeeded = false;
        } else if (!cpmSeeded) {
            cpmEma    = (float)pkt.cpm;
            cpmSeeded = true;
        } else {
            cpmEma = CPM_EMA_ALPHA * (float)pkt.cpm + (1.0f - CPM_EMA_ALPHA) * cpmEma;
        }
        uint32_t showCpm = (pkt.cpm == 0) ? 0u : (uint32_t)roundf(cpmEma);

        // Update display only when the smoothed integer value changes
        if (showCpm != displayedCpm) {
            displayedCpm = showCpm;
            drawRate(showCpm, true);
            Serial.printf("CPM: %u (raw %u)  (%.2f Hz)  stroke=%u\n",
                          showCpm, pkt.cpm, pkt.hz, pkt.stroke_count);
        }
    }

    unsigned long now = millis();

    // Flush SD periodically
    static unsigned long lastFlush = 0;
    if (sdReady && now - lastFlush >= FLUSH_INTERVAL_MS) {
        lastFlush = now;
        logFile.flush();
    }

    // Signal state transitions
    bool receiving = hasReceived && (now - lastRxMs < SIGNAL_TIMEOUT);
    static bool          prevReceiving = false;
    static bool          iconFilled    = true;
    static unsigned long lastFlash     = 0;

    if (receiving != prevReceiving) {
        if (!receiving) {
            cpmSeeded = false;   // re-seed EMA to first packet on signal return
            drawRate(displayedCpm, false);
            drawIcon(false, false);
            Serial.println("Signal lost");
            if (sdReady) logFile.flush();
        } else {
            iconFilled = true;
            lastFlash  = now;
            drawIcon(true, true);
        }
        prevReceiving = receiving;
    }

    // Flash icon while receiving
    if (receiving && (now - lastFlash >= FLASH_MS)) {
        lastFlash  = now;
        iconFilled = !iconFilled;
        drawIcon(true, iconFilled);
    }
}
