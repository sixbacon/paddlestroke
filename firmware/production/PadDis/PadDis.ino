#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <SPI.h>
#include <SD.h>

#define SKETCH_NAME    "PadDis"
#define SKETCH_VERSION "8.9"

// ── Paddle payload — must match PadLog exactly ────────────────────────────────
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
static_assert(sizeof(ImuDataPayload) == 60, "ImuDataPayload size mismatch — check struct");

// ── Boat payload — must match BoatLog exactly ─────────────────────────────────
struct __attribute__((packed)) BoatDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    uint32_t gps_utc_sec;    // seconds since midnight UTC; 0 if no fix
    float    gps_lat;
    float    gps_lon;
    float    gps_speed_ms;   // m/s
    float    gps_cog_deg;    // course over ground, degrees
    uint8_t  gps_fix;        // 0 = none, 1 = valid fix
    uint8_t  gps_uk_offset;  // 0 (GMT) or 1 (BST)
    float    kayak_qw, kayak_qx, kayak_qy, kayak_qz;
    float    kayak_roll, kayak_pitch, kayak_yaw;
};
static_assert(sizeof(BoatDataPayload) == 58, "BoatDataPayload size mismatch — check struct");

// ── Pin assignments ───────────────────────────────────────────────────────────
#define TFT_BL_PIN  21
#define SD_CS    5
#define SD_SCK  18
#define SD_MOSI 23
#define SD_MISO 19

// ── Display constants ─────────────────────────────────────────────────────────
#define SPLASH_MS      20000UL
#define SIGNAL_TIMEOUT  3000UL
#define FLASH_MS         500UL
#define ICON_R              10
#define GREY  ((uint16_t)0x9492)

// Horizontal layout: two signal dots on the right; content area to the left.
// iconCx and boatIconCx are set in setup(); USABLE_W is the content width.
#define USABLE_W  256   // 320 - 64 reserved for two dots

// Vertical strips (pixels from top)
#define TOP_STRIP_H   30   // time HH:MM row
#define SPEED_STRIP_H 28   // speed row
#define RATE_TOP      (TOP_STRIP_H + SPEED_STRIP_H)   // 58 — CPM area starts here

// ── SD logging ────────────────────────────────────────────────────────────────
#define FLUSH_INTERVAL_MS 5000UL

// Comment out to log all paddle payload fields; leave defined for the compact fieldset.
// Reduced:  timestamp_ms, roll, pitch, yaw, stroke_count, cpm
// Full:     seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll, pitch, yaw, stroke_count, cpm, hz
// v8.8/8.9: full set enabled for PadViz4 position-tracking data collection
//#define CSV_COLUMNS_REDUCED

// ── CPM display EMA ───────────────────────────────────────────────────────────
// 10-second time constant at 100 Hz: alpha = 1 - exp(-0.01/10) ≈ 0.001
#define CPM_EMA_ALPHA 0.001f

// ── Ring buffers (WiFi task Core 0 → loop Core 1) ────────────────────────────
#define RING_SIZE      32
#define BOAT_RING_SIZE 32

static ImuDataPayload  rxRing[RING_SIZE];
static volatile int    rxHead = 0;
static volatile int    rxTail = 0;

static BoatDataPayload boatRing[BOAT_RING_SIZE];
static volatile int    boatHead = 0;
static volatile int    boatTail = 0;

portMUX_TYPE rxMux = portMUX_INITIALIZER_UNLOCKED;

TFT_eSPI  tft;
SPIClass  sdSpi(VSPI);

static bool   sdReady     = false;
static bool   boatSdReady = false;
static File   logFile;
static File   boatLogFile;

static bool          hasReceived     = false;
static int           displayedCpmX10 = -1;    // x10 for 0.1 CPM change-detection
static unsigned long lastRxMs        = 0;
static int           iconCx, iconCy;
static int           boatIconCx, boatIconCy;

static bool          boatReceived   = false;
static unsigned long lastBoatRxMs   = 0;
static bool          boatIconFilled = true;
static unsigned long lastBoatFlash  = 0;

// ── CPM EMA state ─────────────────────────────────────────────────────────────
static float cpmEma    = 0.0f;
static bool  cpmSeeded = false;

// ── ESPnow callback — demux by packet size ────────────────────────────────────
void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    if (len == (int)sizeof(ImuDataPayload)) {
        ImuDataPayload p;
        memcpy(&p, data, sizeof(p));
        portENTER_CRITICAL(&rxMux);
        int next = (rxHead + 1) % RING_SIZE;
        if (next != rxTail) { rxRing[rxHead] = p; rxHead = next; }
        portEXIT_CRITICAL(&rxMux);
    } else if (len == (int)sizeof(BoatDataPayload)) {
        BoatDataPayload p;
        memcpy(&p, data, sizeof(p));
        portENTER_CRITICAL(&rxMux);
        int next = (boatHead + 1) % BOAT_RING_SIZE;
        if (next != boatTail) { boatRing[boatHead] = p; boatHead = next; }
        portEXIT_CRITICAL(&rxMux);
    }
}

// ── Display helpers ───────────────────────────────────────────────────────────
static void clearAllPixels() {
    for (int r = 0; r < 4; r++) { tft.setRotation(r); tft.fillScreen(TFT_BLACK); }
    tft.setRotation(2);
}

// CPM: integer part in Font 8, ".x" decimal in Font 4 baseline-aligned beside it
static void drawRate(float cpm, bool active) {
    uint16_t col   = active ? TFT_WHITE : GREY;
    int      rateH = tft.height() - RATE_TOP;

    tft.fillRect(0, RATE_TOP, USABLE_W, rateH, TFT_BLACK);

    int    cpmX10  = (int)(cpm * 10.0f + 0.5f);
    int    intPart = cpmX10 / 10;
    int    decPart = cpmX10 % 10;
    String sInt    = hasReceived ? String(intPart) : "--";
    String sDec    = hasReceived ? ("." + String(decPart)) : "";

    tft.setTextFont(8);
    int intW = tft.textWidth(sInt);
    int intH = tft.fontHeight(8);

    tft.setTextFont(4);
    int decW   = hasReceived ? tft.textWidth(sDec) : 0;
    int decH   = tft.fontHeight(4);

    int totalW = intW + decW;
    int totalH = intH + 4 + decH;   // number + gap + "CPM" label
    int startX = (USABLE_W - totalW) / 2;
    int startY = RATE_TOP + (rateH - totalH) / 2;

    tft.setTextFont(8);
    tft.setTextColor(col, TFT_BLACK);
    tft.setCursor(startX, startY);
    tft.print(sInt);

    if (hasReceived) {
        tft.setTextFont(4);
        tft.setTextColor(col, TFT_BLACK);
        // Align bottom of ".x" with bottom of Font 8 numeral
        tft.setCursor(startX + intW, startY + intH - decH);
        tft.print(sDec);
    }

    tft.setTextFont(4);
    tft.setTextColor(col, TFT_BLACK);
    String label = "CPM";
    tft.setCursor((USABLE_W - tft.textWidth(label)) / 2, startY + intH + 4);
    tft.print(label);
}

static void drawIcon(bool receiving, bool filled) {
    tft.fillRect(iconCx - ICON_R - 2, 0, (ICON_R + 2) * 2, iconCy + ICON_R + 4, TFT_BLACK);
    if (receiving && filled)  tft.fillCircle(iconCx, iconCy, ICON_R, TFT_WHITE);
    else if (receiving)       tft.drawCircle(iconCx, iconCy, ICON_R, TFT_WHITE);
    else                      tft.drawCircle(iconCx, iconCy, ICON_R, GREY);
}

static void drawBoatIcon(bool receiving, bool filled) {
    tft.fillRect(boatIconCx - ICON_R - 2, 0, (ICON_R + 2) * 2, boatIconCy + ICON_R + 4, TFT_BLACK);
    if (receiving && filled)  tft.fillCircle(boatIconCx, boatIconCy, ICON_R, TFT_WHITE);
    else if (receiving)       tft.drawCircle(boatIconCx, boatIconCy, ICON_R, TFT_WHITE);
    else                      tft.drawCircle(boatIconCx, boatIconCy, ICON_R, GREY);
}

static void drawTime(int localH, int localM, bool valid) {
    tft.fillRect(0, 0, 90, TOP_STRIP_H, TFT_BLACK);
    if (!valid) return;
    char buf[6];
    snprintf(buf, sizeof(buf), "%02d:%02d", localH, localM);
    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor(4, (TOP_STRIP_H - tft.fontHeight(4)) / 2);
    tft.print(buf);
}

static void drawSpeed(float speed_ms, bool show) {
    tft.fillRect(0, TOP_STRIP_H, USABLE_W, SPEED_STRIP_H, TFT_BLACK);
    if (!show) return;
    float knots = speed_ms * 1.94384f;
    char  buf[12];
    snprintf(buf, sizeof(buf), "%.1f kn", (double)knots);
    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor((USABLE_W - tft.textWidth(buf)) / 2,
                  TOP_STRIP_H + (SPEED_STRIP_H - tft.fontHeight(4)) / 2);
    tft.print(buf);
}

static void drawGpsWarning(bool show) {
    int warnH = 20;
    int warnY = tft.height() - warnH;
    tft.fillRect(0, warnY, USABLE_W, warnH, TFT_BLACK);
    if (!show) return;
    const char *warn = "NO GPS";
    tft.setTextFont(2);
    tft.setTextColor(0x07FF, TFT_BLACK);   // yellow on BGR ILI9341
    tft.setCursor((USABLE_W - tft.textWidth(warn)) / 2, warnY + 2);
    tft.print(warn);
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

    // Paddle dot (right), boat dot (left of paddle)
    iconCx     = tft.width()  - ICON_R - 8;
    iconCy     = ICON_R + 8;
    boatIconCx = iconCx - (ICON_R * 2 + 8);
    boatIconCy = iconCy;

    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    const char *splash = SKETCH_NAME " v" SKETCH_VERSION;
    int splashY = (tft.height() - tft.fontHeight(4)) / 2;
    tft.setCursor((tft.width() - tft.textWidth(splash)) / 2, splashY);
    tft.print(splash);

    // SD card (VSPI — separate bus from display HSPI)
    sdSpi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    if (!SD.begin(SD_CS, sdSpi, 4000000)) {
        Serial.println("SD init failed — logging disabled");
    } else {
        // Paddle log
        char fname[] = "/ImuLog00.CSV";
        for (int i = 0; i < 100; i++) {
            fname[7] = '0' + i / 10;
            fname[8] = '0' + i % 10;
            if (!SD.exists(fname)) break;
        }
        logFile = SD.open(fname, FILE_WRITE);
        if (!logFile) {
            Serial.println("Paddle log open failed");
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
            Serial.print("Paddle logging to "); Serial.println(fname);
            sdReady = true;
        }

        // Boat log
        char bfname[] = "/BoatLog00.CSV";
        for (int i = 0; i < 100; i++) {
            bfname[8] = '0' + i / 10;
            bfname[9] = '0' + i % 10;
            if (!SD.exists(bfname)) break;
        }
        boatLogFile = SD.open(bfname, FILE_WRITE);
        if (!boatLogFile) {
            Serial.println("Boat log open failed");
        } else {
            boatLogFile.println("# " SKETCH_NAME " v" SKETCH_VERSION " boat");
            boatLogFile.println("seq,timestamp_ms,gps_utc_sec,gps_uk_offset,"
                                "gps_lat,gps_lon,gps_speed_ms,gps_cog_deg,gps_fix,"
                                "kayak_qw,kayak_qx,kayak_qy,kayak_qz,"
                                "kayak_roll,kayak_pitch,kayak_yaw");
            Serial.print("Boat logging to "); Serial.println(bfname);
            boatSdReady = true;
        }
    }

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
    drawRate(0.0f, false);
    drawIcon(false, false);
    drawBoatIcon(false, false);
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    unsigned long now = millis();

    // ── Paddle packet ─────────────────────────────────────────────────────────
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
        lastRxMs    = now;

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

        // CPM EMA — pre-seed to first value; reset immediately on inactivity
        if (pkt.cpm == 0) {
            cpmEma    = 0.0f;
            cpmSeeded = false;
        } else if (!cpmSeeded) {
            cpmEma    = (float)pkt.cpm;
            cpmSeeded = true;
        } else {
            cpmEma = CPM_EMA_ALPHA * (float)pkt.cpm + (1.0f - CPM_EMA_ALPHA) * cpmEma;
        }

        float showCpmF   = (pkt.cpm == 0) ? 0.0f : cpmEma;
        int   showCpmX10 = (int)(showCpmF * 10.0f + 0.5f);

        if (showCpmX10 != displayedCpmX10) {
            displayedCpmX10 = showCpmX10;
            drawRate(showCpmF, true);
            Serial.printf("CPM: %.1f (raw %u)  (%.2f Hz)  stroke=%u\n",
                          (double)cpmEma, pkt.cpm, (double)pkt.hz, pkt.stroke_count);
        }
    }

    // ── Boat packet ───────────────────────────────────────────────────────────
    BoatDataPayload bpkt;
    bool gotBoat = false;
    portENTER_CRITICAL(&rxMux);
    if (boatHead != boatTail) {
        bpkt     = boatRing[boatTail];
        boatTail = (boatTail + 1) % BOAT_RING_SIZE;
        gotBoat  = true;
    }
    portEXIT_CRITICAL(&rxMux);

    if (gotBoat) {
        boatReceived = true;
        lastBoatRxMs = now;

        if (boatSdReady) {
            char row[200];
            int n = snprintf(row, sizeof(row),
                "%u,%u,%u,%u,%.6f,%.6f,%.4f,%.2f,%u,"
                "%.8f,%.8f,%.8f,%.8f,%.5f,%.5f,%.5f\n",
                bpkt.seq, bpkt.timestamp_ms,
                bpkt.gps_utc_sec, (uint32_t)bpkt.gps_uk_offset,
                (double)bpkt.gps_lat, (double)bpkt.gps_lon,
                (double)bpkt.gps_speed_ms, (double)bpkt.gps_cog_deg,
                (uint32_t)bpkt.gps_fix,
                (double)bpkt.kayak_qw, (double)bpkt.kayak_qx,
                (double)bpkt.kayak_qy, (double)bpkt.kayak_qz,
                (double)bpkt.kayak_roll, (double)bpkt.kayak_pitch,
                (double)bpkt.kayak_yaw);
            boatLogFile.write((const uint8_t*)row, n);
        }

        // Update time and speed display; track fix state for transition handling
        static bool prevFixActive = false;
        bool thisFixActive = (bpkt.gps_fix != 0);

        if (thisFixActive) {
            uint32_t localSec = bpkt.gps_utc_sec + (uint32_t)bpkt.gps_uk_offset * 3600u;
            int localH = (int)((localSec / 3600) % 24);
            int localM = (int)((localSec / 60)   % 60);

            static int prevH = -1, prevM = -1;
            if (localH != prevH || localM != prevM) {
                prevH = localH; prevM = localM;
                drawTime(localH, localM, true);
            }

            static int prevSpeedX10 = -1;
            int speedX10 = (int)(bpkt.gps_speed_ms * 1.94384f * 10.0f + 0.5f);
            if (speedX10 != prevSpeedX10) {
                prevSpeedX10 = speedX10;
                drawSpeed(bpkt.gps_speed_ms, true);
            }

            drawGpsWarning(false);
            prevFixActive = true;
        } else {
            if (prevFixActive) {
                drawTime(0, 0, false);
                drawSpeed(0.0f, false);
                drawGpsWarning(true);
            }
            prevFixActive = false;
        }
    }

    // ── Periodic SD flush ─────────────────────────────────────────────────────
    static unsigned long lastFlush = 0;
    if (now - lastFlush >= FLUSH_INTERVAL_MS) {
        lastFlush = now;
        if (sdReady)     logFile.flush();
        if (boatSdReady) boatLogFile.flush();
    }

    // ── Paddle signal state ───────────────────────────────────────────────────
    bool receiving = hasReceived && (now - lastRxMs < SIGNAL_TIMEOUT);
    static bool          prevReceiving = false;
    static bool          iconFilled    = true;
    static unsigned long lastFlash     = 0;

    if (receiving != prevReceiving) {
        if (!receiving) {
            cpmSeeded = false;
            drawRate(cpmEma, false);
            drawIcon(false, false);
            Serial.println("Paddle signal lost");
            if (sdReady) logFile.flush();
        } else {
            iconFilled = true;
            lastFlash  = now;
            drawIcon(true, true);
        }
        prevReceiving = receiving;
    }

    if (receiving && (now - lastFlash >= FLASH_MS)) {
        lastFlash  = now;
        iconFilled = !iconFilled;
        drawIcon(true, iconFilled);
    }

    // ── Boat signal state ─────────────────────────────────────────────────────
    bool boatActive = boatReceived && (now - lastBoatRxMs < SIGNAL_TIMEOUT);
    static bool prevBoatActive = false;

    if (boatActive != prevBoatActive) {
        if (!boatActive) {
            drawBoatIcon(false, false);
            drawTime(0, 0, false);
            drawSpeed(0.0f, false);
            drawGpsWarning(false);
            Serial.println("Boat signal lost");
            if (boatSdReady) boatLogFile.flush();
        } else {
            boatIconFilled = true;
            lastBoatFlash  = now;
            drawBoatIcon(true, true);
        }
        prevBoatActive = boatActive;
    }

    if (boatActive && (now - lastBoatFlash >= FLASH_MS)) {
        lastBoatFlash  = now;
        boatIconFilled = !boatIconFilled;
        drawBoatIcon(true, boatIconFilled);
    }
}
