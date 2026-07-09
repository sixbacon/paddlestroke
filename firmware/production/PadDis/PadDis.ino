#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <SPI.h>
#include <SD.h>

#define SKETCH_NAME    "PadDis"
#define SKETCH_VERSION "8.11"

// v8.11 (Phase 10): mag_cal column on both CSVs + boat_accel_x/y/z columns on
// boat CSV. Payload structs grow by 4 bytes (paddle) and 16 bytes (boat) —
// PadLog v8.8 / BoatLog v1.1 / PadDis v8.11 must ship together.
// v8.10: add rx_ms column (CYD-side receive timestamp, captured in ESPnow
// callback) to both paddle and boat CSVs. rx_ms uses the SAME CYD millis()
// clock for both streams, so post-processing sync = match rows by nearest
// rx_ms — typically < 5 ms accuracy, dominated by ESPnow send-side jitter.
// Old ±5-second gps_utc_sec sync remains as a cross-check / absolute time ref.

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
    uint8_t  mag_cal;
    uint8_t  _pad[3];
};
static_assert(sizeof(ImuDataPayload) == 64, "ImuDataPayload size mismatch — check struct");

// ── Boat payload — must match BoatLog exactly ─────────────────────────────────
struct __attribute__((packed)) BoatDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    uint32_t gps_utc_sec;
    float    gps_lat;
    float    gps_lon;
    float    gps_speed_ms;
    float    gps_cog_deg;
    uint8_t  gps_fix;
    uint8_t  gps_uk_offset;
    float    kayak_qw, kayak_qx, kayak_qy, kayak_qz;
    float    kayak_roll, kayak_pitch, kayak_yaw;
    float    accel_x, accel_y, accel_z;
    uint8_t  mag_cal;
    uint8_t  _pad[3];
};
static_assert(sizeof(BoatDataPayload) == 74, "BoatDataPayload size mismatch — check struct");

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

// Three-line layout: top line Font 4 (26 px); speed + CPM Font 4 ×2 (52 px)
#define LINE_H    26                               // Font 4 size 1
#define LINE_H_LG 52                               // Font 4 size 2
#define LINE_PAD  10
#define LINE1_Y    6                               // time + signal circles
#define LINE2_Y   (LINE1_Y + LINE_H    + LINE_PAD) // speed  (= 42)
#define LINE3_Y   (LINE2_Y + LINE_H_LG + LINE_PAD) // CPM    (= 104)

// ── SD logging ────────────────────────────────────────────────────────────────
#define FLUSH_INTERVAL_MS 5000UL

// v8.8/8.9: full column set for PadViz4 position-tracking data collection
//#define CSV_COLUMNS_REDUCED

// ── CPM display EMA — 10-second time constant at 100 Hz ──────────────────────
#define CPM_EMA_ALPHA 0.001f

// ── Ring buffers (WiFi task Core 0 → loop Core 1) ────────────────────────────
#define RING_SIZE      32
#define BOAT_RING_SIZE 32

// Each ring entry pairs the received payload with the CYD-side millis()
// captured inside the ESPnow receive callback. Same clock domain for both
// paddle and boat entries → common time reference for sync.
struct PadRxEntry  { ImuDataPayload  p; uint32_t rx_ms; };
struct BoatRxEntry { BoatDataPayload p; uint32_t rx_ms; };

static PadRxEntry     rxRing[RING_SIZE];
static volatile int   rxHead = 0;
static volatile int   rxTail = 0;

static BoatRxEntry    boatRing[BOAT_RING_SIZE];
static volatile int   boatHead = 0;
static volatile int   boatTail = 0;

portMUX_TYPE rxMux = portMUX_INITIALIZER_UNLOCKED;

TFT_eSPI  tft;
SPIClass  sdSpi(VSPI);

static bool   sdReady     = false;
static bool   boatSdReady = false;
static File   logFile;
static File   boatLogFile;

static bool          hasReceived     = false;
static int           displayedCpmX10 = -1;
static unsigned long lastRxMs        = 0;

static bool          boatReceived = false;
static unsigned long lastBoatRxMs = 0;

// ── CPM EMA state ─────────────────────────────────────────────────────────────
static float cpmEma    = 0.0f;
static bool  cpmSeeded = false;

// ── Last-known GPS time (updated from boat packets) ───────────────────────────
static uint32_t g_gps_utc_sec   = 0;
static uint8_t  g_gps_uk_offset = 0;

// ── Top-line shared state (time + both circles) ───────────────────────────────
static int  g_iconCx, g_boatIconCx, g_iconCy;
static int  g_timeH = -1, g_timeM = -1;   // -1 = no valid time
static bool g_padReceiving  = false, g_padFilled  = true;
static bool g_boatReceiving = false, g_boatFilled = true;

// ── ESPnow callback — demux by packet size ────────────────────────────────────
// Capture millis() first so rx_ms reflects reception time on the CYD, not the
// time this callback finished processing.
void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    uint32_t rx_ms = millis();
    if (len == (int)sizeof(ImuDataPayload)) {
        ImuDataPayload p;
        memcpy(&p, data, sizeof(p));
        portENTER_CRITICAL(&rxMux);
        int next = (rxHead + 1) % RING_SIZE;
        if (next != rxTail) {
            rxRing[rxHead].p     = p;
            rxRing[rxHead].rx_ms = rx_ms;
            rxHead               = next;
        }
        portEXIT_CRITICAL(&rxMux);
    } else if (len == (int)sizeof(BoatDataPayload)) {
        BoatDataPayload p;
        memcpy(&p, data, sizeof(p));
        portENTER_CRITICAL(&rxMux);
        int next = (boatHead + 1) % BOAT_RING_SIZE;
        if (next != boatTail) {
            boatRing[boatHead].p     = p;
            boatRing[boatHead].rx_ms = rx_ms;
            boatHead                 = next;
        }
        portEXIT_CRITICAL(&rxMux);
    }
}

// ── Display helpers ───────────────────────────────────────────────────────────
static void clearAllPixels() {
    for (int r = 0; r < 4; r++) { tft.setRotation(r); tft.fillScreen(TFT_BLACK); }
    tft.setRotation(2);
}

// Redraws the entire top line: time (left) + boat circle + paddle circle (right)
static void drawTopLine() {
    tft.fillRect(0, 0, tft.width(), LINE1_Y + LINE_H + 2, TFT_BLACK);

    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    if (g_timeH >= 0) {
        char buf[6];
        snprintf(buf, sizeof(buf), "%02d:%02d", g_timeH, g_timeM);
        tft.setCursor(4, LINE1_Y);
        tft.print(buf);
    }

    // Boat circle (left of paddle circle)
    if (g_boatReceiving && g_boatFilled)
        tft.fillCircle(g_boatIconCx, g_iconCy, ICON_R, TFT_WHITE);
    else
        tft.drawCircle(g_boatIconCx, g_iconCy, ICON_R,
                       g_boatReceiving ? TFT_WHITE : GREY);

    // Paddle circle (rightmost)
    if (g_padReceiving && g_padFilled)
        tft.fillCircle(g_iconCx, g_iconCy, ICON_R, TFT_WHITE);
    else
        tft.drawCircle(g_iconCx, g_iconCy, ICON_R,
                       g_padReceiving ? TFT_WHITE : GREY);
}

static void drawSpeed(float speed_ms, bool show) {
    tft.fillRect(0, LINE2_Y, tft.width(), LINE_H_LG + 2, TFT_BLACK);
    if (!show) return;
    char buf[12];
    snprintf(buf, sizeof(buf), "%.1f kn", (double)(speed_ms * 1.94384f));
    tft.setTextFont(4);
    tft.setTextSize(2);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor((tft.width() - tft.textWidth(buf)) / 2, LINE2_Y);
    tft.print(buf);
    tft.setTextSize(1);
}

static void drawCpm(float cpm, bool active) {
    tft.fillRect(0, LINE3_Y, tft.width(), LINE_H_LG + 2, TFT_BLACK);
    tft.setTextFont(4);
    tft.setTextSize(2);
    tft.setTextColor(active ? TFT_WHITE : GREY, TFT_BLACK);
    char buf[16];
    if (!hasReceived) {
        snprintf(buf, sizeof(buf), "-- cpm");
    } else {
        int cpmX10 = (int)(cpm * 10.0f + 0.5f);
        snprintf(buf, sizeof(buf), "%d.%d cpm", cpmX10 / 10, cpmX10 % 10);
    }
    tft.setCursor((tft.width() - tft.textWidth(buf)) / 2, LINE3_Y);
    tft.print(buf);
    tft.setTextSize(1);
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

    // Circle positions: paddle rightmost, boat to its left
    g_iconCx     = tft.width() - ICON_R - 8;
    g_iconCy     = LINE1_Y + LINE_H / 2;
    g_boatIconCx = g_iconCx - (ICON_R * 2 + 8);

    // Splash
    tft.setTextFont(4);
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    const char *splash = SKETCH_NAME " v" SKETCH_VERSION;
    int splashY = (tft.height() - LINE_H) / 2;
    tft.setCursor((tft.width() - tft.textWidth(splash)) / 2, splashY);
    tft.print(splash);

    // SD card (VSPI — separate bus from display HSPI)
    sdSpi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    if (!SD.begin(SD_CS, sdSpi, 4000000)) {
        Serial.println("SD init failed — logging disabled");
    } else {
        // Paddle log
        char fname[] = "/PadLog00.CSV";
        for (int i = 0; i < 100; i++) {
            fname[7] = '0' + i / 10;
            fname[8] = '0' + i % 10;
            if (!SD.exists(fname)) break;
        }
        logFile = SD.open(fname, FILE_WRITE);
        if (!logFile) {
            Serial.println("Paddle log open failed");
        } else {
            logFile.println("# " SKETCH_NAME " v" SKETCH_VERSION " paddle");
#ifdef CSV_COLUMNS_REDUCED
            logFile.println("timestamp_ms,roll,pitch,yaw,stroke_count,cpm,"
                            "gps_utc_sec,gps_uk_offset,rx_ms,mag_cal");
#else
            logFile.println("seq,timestamp_ms,"
                            "accel_x,accel_y,accel_z,"
                            "q_w,q_x,q_y,q_z,"
                            "roll,pitch,yaw,"
                            "stroke_count,cpm,"
                            "gps_utc_sec,gps_uk_offset,rx_ms,mag_cal");
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
                                "kayak_roll,kayak_pitch,kayak_yaw,rx_ms,"
                                "boat_accel_x,boat_accel_y,boat_accel_z,mag_cal");
            Serial.print("Boat logging to "); Serial.println(bfname);
            boatSdReady = true;
        }
    }

    if (!sdReady) {
        tft.setTextFont(2);
        tft.setTextColor(0x07FF, TFT_BLACK);
        const char *warn = "NO SD CARD — logging disabled";
        tft.setCursor((tft.width() - tft.textWidth(warn)) / 2, splashY + LINE_H + 10);
        tft.print(warn);
    }

    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) fatalError("ESPnow init FAILED");
    esp_now_register_recv_cb(onReceive);

    delay(SPLASH_MS);

    tft.fillScreen(TFT_BLACK);
    drawTopLine();
    drawSpeed(0.0f, false);
    drawCpm(0.0f, false);
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    unsigned long now = millis();

    // ── Paddle packet ─────────────────────────────────────────────────────────
    ImuDataPayload pkt;
    uint32_t       pktRxMs = 0;
    bool got = false;
    portENTER_CRITICAL(&rxMux);
    if (rxHead != rxTail) {
        pkt     = rxRing[rxTail].p;
        pktRxMs = rxRing[rxTail].rx_ms;
        rxTail  = (rxTail + 1) % RING_SIZE;
        got     = true;
    }
    portEXIT_CRITICAL(&rxMux);

    if (got) {
        hasReceived = true;
        lastRxMs    = now;

        if (sdReady) {
#ifdef CSV_COLUMNS_REDUCED
            char row[96];
            int n = snprintf(row, sizeof(row),
                "%u,%.5f,%.5f,%.5f,%u,%u,%u,%u,%u,%u\n",
                pkt.timestamp_ms,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count, pkt.cpm,
                g_gps_utc_sec, (uint32_t)g_gps_uk_offset,
                pktRxMs, (uint32_t)pkt.mag_cal);
#else
            char row[220];
            int n = snprintf(row, sizeof(row),
                "%u,%u,%.5f,%.5f,%.5f,%.8f,%.8f,%.8f,%.8f,%.5f,%.5f,%.5f,%u,%u,%u,%u,%u,%u\n",
                pkt.seq, pkt.timestamp_ms,
                pkt.accel_x, pkt.accel_y, pkt.accel_z,
                pkt.q_w, pkt.q_x, pkt.q_y, pkt.q_z,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count, pkt.cpm,
                g_gps_utc_sec, (uint32_t)g_gps_uk_offset,
                pktRxMs, (uint32_t)pkt.mag_cal);
#endif
            logFile.write((const uint8_t*)row, n);
        }

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
            drawCpm(showCpmF, true);
            Serial.printf("CPM: %.1f (raw %u)  (%.2f Hz)  stroke=%u\n",
                          (double)cpmEma, pkt.cpm, (double)pkt.hz, pkt.stroke_count);
        }
    }

    // ── Boat packet ───────────────────────────────────────────────────────────
    BoatDataPayload bpkt;
    uint32_t        bpktRxMs = 0;
    bool gotBoat = false;
    portENTER_CRITICAL(&rxMux);
    if (boatHead != boatTail) {
        bpkt     = boatRing[boatTail].p;
        bpktRxMs = boatRing[boatTail].rx_ms;
        boatTail = (boatTail + 1) % BOAT_RING_SIZE;
        gotBoat  = true;
    }
    portEXIT_CRITICAL(&rxMux);

    if (gotBoat) {
        boatReceived = true;
        lastBoatRxMs = now;

        if (boatSdReady) {
            char row[280];
            int n = snprintf(row, sizeof(row),
                "%u,%u,%u,%u,%.6f,%.6f,%.4f,%.2f,%u,"
                "%.8f,%.8f,%.8f,%.8f,%.5f,%.5f,%.5f,%u,"
                "%.5f,%.5f,%.5f,%u\n",
                bpkt.seq, bpkt.timestamp_ms,
                bpkt.gps_utc_sec, (uint32_t)bpkt.gps_uk_offset,
                (double)bpkt.gps_lat, (double)bpkt.gps_lon,
                (double)bpkt.gps_speed_ms, (double)bpkt.gps_cog_deg,
                (uint32_t)bpkt.gps_fix,
                (double)bpkt.kayak_qw, (double)bpkt.kayak_qx,
                (double)bpkt.kayak_qy, (double)bpkt.kayak_qz,
                (double)bpkt.kayak_roll, (double)bpkt.kayak_pitch,
                (double)bpkt.kayak_yaw,
                bpktRxMs,
                (double)bpkt.accel_x, (double)bpkt.accel_y, (double)bpkt.accel_z,
                (uint32_t)bpkt.mag_cal);
            boatLogFile.write((const uint8_t*)row, n);
        }

        if (bpkt.gps_fix) {
            g_gps_utc_sec   = bpkt.gps_utc_sec;
            g_gps_uk_offset = bpkt.gps_uk_offset;
        } else {
            g_gps_utc_sec   = 0;
            g_gps_uk_offset = 0;
        }

        static bool prevFixActive = false;
        bool thisFixActive = (bpkt.gps_fix != 0);

        if (thisFixActive) {
            uint32_t localSec = bpkt.gps_utc_sec + (uint32_t)bpkt.gps_uk_offset * 3600u;
            int localH = (int)((localSec / 3600) % 24);
            int localM = (int)((localSec / 60)   % 60);

            static int prevH = -1, prevM = -1;
            if (localH != prevH || localM != prevM) {
                prevH = localH; prevM = localM;
                g_timeH = localH; g_timeM = localM;
                drawTopLine();
            }

            static int prevSpeedX10 = -1;
            int speedX10 = (int)(bpkt.gps_speed_ms * 1.94384f * 10.0f + 0.5f);
            if (speedX10 != prevSpeedX10) {
                prevSpeedX10 = speedX10;
                drawSpeed(bpkt.gps_speed_ms, true);
            }

            prevFixActive = true;
        } else {
            if (prevFixActive) {
                g_timeH = -1; g_timeM = -1;
                drawTopLine();
                drawSpeed(0.0f, false);
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
            cpmSeeded      = false;
            g_padReceiving = false;
            drawTopLine();
            drawCpm(cpmEma, false);
            Serial.println("Paddle signal lost");
            if (sdReady) logFile.flush();
        } else {
            iconFilled     = true;
            lastFlash      = now;
            g_padReceiving = true;
            g_padFilled    = true;
            drawTopLine();
        }
        prevReceiving = receiving;
    }

    if (receiving && (now - lastFlash >= FLASH_MS)) {
        lastFlash   = now;
        iconFilled  = !iconFilled;
        g_padFilled = iconFilled;
        drawTopLine();
    }

    // ── Boat signal state ─────────────────────────────────────────────────────
    bool boatActive = boatReceived && (now - lastBoatRxMs < SIGNAL_TIMEOUT);
    static bool          prevBoatActive = false;
    static bool          boatIconFilled = true;
    static unsigned long lastBoatFlash  = 0;

    if (boatActive != prevBoatActive) {
        if (!boatActive) {
            g_boatReceiving = false;
            g_timeH = -1; g_timeM = -1;
            drawTopLine();
            drawSpeed(0.0f, false);
            Serial.println("Boat signal lost");
            if (boatSdReady) boatLogFile.flush();
        } else {
            boatIconFilled  = true;
            lastBoatFlash   = now;
            g_boatReceiving = true;
            g_boatFilled    = true;
            drawTopLine();
        }
        prevBoatActive = boatActive;
    }

    if (boatActive && (now - lastBoatFlash >= FLASH_MS)) {
        lastBoatFlash  = now;
        boatIconFilled = !boatIconFilled;
        g_boatFilled   = boatIconFilled;
        drawTopLine();
    }
}
