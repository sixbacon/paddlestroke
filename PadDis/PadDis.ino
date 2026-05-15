#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <SPI.h>
#include <SD.h>

#define SKETCH_NAME    "PadDis"
#define SKETCH_VERSION "8.4"

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

// ── Asymmetry bar ─────────────────────────────────────────────────────────────
#define BAR_Y       40            // top of bar — below the signal dot (dot bottom ≈ y=32)
#define BAR_H       18            // bar height in pixels
#define BAR_W      220            // total bar width in pixels
#define BAR_MAX_MS 500            // asymmetry (ms) at which bar reaches full deflection
// Positive asymMs = left stroke shorter = RED bar extends left of centre
// Negative asymMs = right stroke shorter = GREEN bar extends right of centre
// Bar is invisible (white) until asymValid=true; no grey background to avoid colour artifacts.
#define BAR_RED   ((uint16_t)0x001F)   // display is BGR: send blue value to get red appearance

// ── SD logging ────────────────────────────────────────────────────────────────
#define FLUSH_INTERVAL_MS 5000UL

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

// ── Asymmetry state ───────────────────────────────────────────────────────────
static int32_t  asymMs    = 0;
static bool     asymValid = false;
static uint32_t tLastR    = 0;     // TX timestamp_ms of last right-labelled stroke
static uint32_t tLastL    = 0;     // TX timestamp_ms of last left-labelled stroke
static uint32_t prevSc    = 0;     // previous stroke_count (to detect increments)

// Option A — rolling midpoint for L/R classification
// Instead of pitch >= 0 (unreliable with offset mounting), track the midpoint
// between consecutive peak and trough roll values.  midRoll self-calibrates to
// the mounting offset and drifts slowly with it during the session.
static float asymPrevRoll   = NAN; // roll at the previous stroke event
static float asymPeakRoll   = NAN; // roll at most recent positive-side extremum
static float asymTroughRoll = NAN; // roll at most recent negative-side extremum
static float asymMidRoll    = NAN; // EMA of (peakRoll + troughRoll) / 2

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
    for (int r = 0; r < 4; r++) { tft.setRotation(r); tft.fillScreen(TFT_WHITE); }
    tft.setRotation(2);
}

// Draws (or redraws) the asymmetry bar from current asymMs / asymValid state.
// Must be called after any drawRate() call since drawRate wipes the usable area.
// Background is always white (invisible) to avoid colour rendering artefacts.
static void drawAsymmetryBar() {
    int usableW = tft.width() - (ICON_R * 2 + 16);
    int cx      = usableW / 2;
    int barX    = cx - BAR_W / 2;

    // Clear bar area to white — invisible until asymmetry data is available
    tft.fillRect(barX, BAR_Y, BAR_W, BAR_H, TFT_WHITE);

    if (!asymValid) return;

    // Coloured fill
    int half = BAR_W / 2;
    int fill = min(half, (int)((long)abs(asymMs) * half / BAR_MAX_MS));
    if (fill > 1) {
        if (asymMs > 0)   // left shorter → RED extends left of centre
            tft.fillRect(cx - fill, BAR_Y, fill, BAR_H, BAR_RED);
        else              // right shorter → GREEN extends right of centre
            tft.fillRect(cx, BAR_Y, fill, BAR_H, TFT_GREEN);
    }

    // Outline and centre tick so scale is visible
    tft.drawRect(barX, BAR_Y, BAR_W, BAR_H, GREY);
    tft.drawLine(cx, BAR_Y, cx, BAR_Y + BAR_H - 1, GREY);
}

static void drawRate(uint32_t cpm, bool active) {
    uint16_t col     = active ? TFT_BLACK : GREY;
    int      w       = tft.width();
    int      h       = tft.height();
    int      usableW = w - (ICON_R * 2 + 16);
    tft.fillRect(0, 0, usableW, h, TFT_WHITE);
    tft.setTextFont(8);
    tft.setTextColor(col, TFT_WHITE);
    String s  = hasReceived ? String(cpm) : "--";
    int    tw = tft.textWidth(s);
    int    th = tft.fontHeight(8);
    int    x  = (usableW - tw) / 2;
    int    y  = (h - th) / 2 - 10;
    tft.setCursor(x, y);
    tft.print(s);
    tft.setTextFont(4);
    tft.setTextColor(col, TFT_WHITE);
    String label = "CPM";
    tft.setCursor((usableW - tft.textWidth(label)) / 2, y + th + 4);
    tft.print(label);
    // Restore bar (drawRate wipes the whole usable area)
    drawAsymmetryBar();
}

static void drawIcon(bool receiving, bool filled) {
    tft.fillRect(iconCx - ICON_R - 2, 0, (ICON_R + 2) * 2, iconCy + ICON_R + 4, TFT_WHITE);
    if (receiving && filled)  tft.fillCircle(iconCx, iconCy, ICON_R, TFT_BLACK);
    else if (receiving)       tft.drawCircle(iconCx, iconCy, ICON_R, TFT_BLACK);
    else                      tft.drawCircle(iconCx, iconCy, ICON_R, GREY);
}

static void fatalError(const char *msg) {
    tft.fillScreen(TFT_WHITE);
    tft.setTextFont(2);
    tft.setTextColor(TFT_RED, TFT_WHITE);
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
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    const char *splash = SKETCH_NAME " v" SKETCH_VERSION;
    tft.setCursor((tft.width()  - tft.textWidth(splash)) / 2,
                  (tft.height() - tft.fontHeight(4))      / 2);
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
            logFile.println("seq,timestamp_ms,"
                            "accel_x,accel_y,accel_z,"
                            "q_w,q_x,q_y,q_z,"
                            "roll,pitch,yaw,"
                            "stroke_count,cpm,hz");
            Serial.print("Logging to "); Serial.println(fname);
            sdReady = true;
        }
    }

    // ESPnow
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) fatalError("ESPnow init FAILED");
    esp_now_register_recv_cb(onReceive);

    delay(SPLASH_MS);

    tft.fillScreen(TFT_WHITE);
    drawRate(0, false);   // also draws the (initially grey) bar
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

        // Log every packet to SD
        if (sdReady) {
            char row[192];
            int n = snprintf(row, sizeof(row),
                "%u,%u,%.5f,%.5f,%.5f,%.8f,%.8f,%.8f,%.8f,%.5f,%.5f,%.5f,%u,%u,%.3f\n",
                pkt.seq, pkt.timestamp_ms,
                pkt.accel_x, pkt.accel_y, pkt.accel_z,
                pkt.q_w, pkt.q_x, pkt.q_y, pkt.q_z,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count, pkt.cpm, pkt.hz);
            logFile.write((const uint8_t*)row, n);
        }

        // ── Stroke asymmetry tracking ─────────────────────────────────────────
        // Label each stroke R or L using the rolling midpoint of peak/trough roll
        // values (Option A).  This self-calibrates to the mounting offset so the
        // bar reflects true stroke asymmetry rather than mounting angle.
        if (pkt.stroke_count != prevSc) {
            prevSc = pkt.stroke_count;
            uint32_t ts   = pkt.timestamp_ms;
            float    roll = pkt.roll;

            // Update peak / trough tracking from consecutive stroke roll values.
            // Consecutive strokes alternate extrema, so comparing to the previous
            // stroke roll reliably identifies peaks (higher) and troughs (lower).
            if (!isnan(asymPrevRoll)) {
                if (roll > asymPrevRoll) asymPeakRoll   = roll;
                else                     asymTroughRoll = roll;
            }
            asymPrevRoll = roll;

            // Recompute midpoint EMA whenever both sides are known.
            if (!isnan(asymPeakRoll) && !isnan(asymTroughRoll)) {
                float newMid = (asymPeakRoll + asymTroughRoll) * 0.5f;
                asymMidRoll  = isnan(asymMidRoll) ? newMid : (0.9f * asymMidRoll + 0.1f * newMid);
            }

            // Classify stroke: above midpoint = positive-side (right), below = left.
            // Fall back to roll >= 0 until the midpoint is established.
            bool isRight = isnan(asymMidRoll) ? (roll >= 0.0f) : (roll > asymMidRoll);

            if (isRight) {
                if (tLastL > tLastR && tLastR > 0) {
                    // Complete R → L → R sequence: both halves available
                    int32_t r2l = (int32_t)(tLastL - tLastR);
                    int32_t l2r = (int32_t)(ts     - tLastL);
                    if (r2l > 150 && r2l < 4000 && l2r > 150 && l2r < 4000) {
                        asymMs    = r2l - l2r;  // +ve = left shorter = RED
                        asymValid = true;
                    }
                }
                tLastR = ts;
            } else {
                if (tLastR > tLastL && tLastL > 0) {
                    // Complete L → R → L sequence: both halves available
                    int32_t l2r = (int32_t)(tLastR - tLastL);
                    int32_t r2l = (int32_t)(ts     - tLastR);
                    if (l2r > 150 && l2r < 4000 && r2l > 150 && r2l < 4000) {
                        asymMs    = r2l - l2r;  // same sign convention
                        asymValid = true;
                    }
                }
                tLastL = ts;
            }
        }

        // Update CPM display only when value changes
        if (pkt.cpm != displayedCpm) {
            displayedCpm = pkt.cpm;
            drawRate(pkt.cpm, true);   // drawRate also redraws the bar
            Serial.printf("CPM: %u  (%.2f Hz)  stroke=%u  asymMs=%d\n",
                          pkt.cpm, pkt.hz, pkt.stroke_count, asymMs);
        } else {
            // Redraw bar independently when asymmetry updates between CPM changes
            static int32_t prevAsymMs    = INT32_MIN;
            static bool    prevAsymValid = false;
            if (asymMs != prevAsymMs || asymValid != prevAsymValid) {
                prevAsymMs    = asymMs;
                prevAsymValid = asymValid;
                drawAsymmetryBar();
                Serial.printf("Asym: %+d ms  (%s shorter)\n",
                              asymMs, asymMs > 0 ? "LEFT" : "RIGHT");
            }
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
            // Reset asymmetry state on signal loss
            asymValid     = false;
            tLastR        = 0;
            tLastL        = 0;
            prevSc        = 0;
            asymPrevRoll   = NAN;
            asymPeakRoll   = NAN;
            asymTroughRoll = NAN;
            asymMidRoll    = NAN;
            drawRate(displayedCpm, false);   // also redraws bar (now grey)
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
