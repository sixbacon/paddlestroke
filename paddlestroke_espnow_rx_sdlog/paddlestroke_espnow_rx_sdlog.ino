// paddlestroke_espnow_rx_sdlog.ino
// Receives synthetic IMU packets from paddlestroke_espnow_tx_test.
// Logs to SD card; shows stroke count and signal status on TFT.
// Flash to CYD (ESP32-2432S028, COM7).
//
// SPI buses — no conflict:
//   Display ILI9341 : HSPI  SCK=14  MOSI=13  MISO=12  CS=15  (User_Setup.h)
//   SD card         : VSPI  SCK=18  MOSI=23  MISO=19  CS=5
//
// Automated tests (60 s window):
//   T-1  Packet loss     < 1 %
//   T-2  Max inter-packet gap  < 50 ms
//   T-3  Euler re-derivation error  < 0.0001 °   (tests double transmission)
//   T-4  accel_z error vs 9.80665   < 0.0001 m/s²  (constant cross-check)
//   T-5  SD card written successfully
//   T-6  No ring-buffer overflow
//
// Manual tests (not automated):
//   T-7  Cold start: power RX before TX — should show '---' then lock automatically
//   T-8  TX restart: power-cycle TX mid-test — RX should recover without reboot
//
// Post-processing the CSV verifies formula accuracy:
//   expected accel_x = 2·sin(seq · 2PI/200)
//   expected accel_z = 9.80665
//   expected roll = 0, pitch = 0
//   expected yaw  = (seq mod 200) · 1.8°  (wrapped to (-180,180])

#include <TFT_eSPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <SPI.h>
#include <SD.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── Payload struct — must match TX sketch exactly ─────────────────────────────
struct __attribute__((packed)) ImuDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    double   accel_x;
    double   accel_y;
    double   accel_z;
    double   q_w;
    double   q_x;
    double   q_y;
    double   q_z;
    double   roll;
    double   pitch;
    double   yaw;
    uint32_t stroke_count;
};
static_assert(sizeof(ImuDataPayload) == 92, "Payload size mismatch — check struct");

// ── Pin assignments ───────────────────────────────────────────────────────────
#define TFT_BL_PIN  21
#define SD_CS        5
#define SD_SCK      18
#define SD_MOSI     23
#define SD_MISO     19

// ── Test pass criteria ────────────────────────────────────────────────────────
#define TEST_DURATION_MS    60000UL
#define MAX_LOSS_PCT         1.0f
#define MAX_GAP_MS              50      // 100 Hz → ~10 ms normal; allow 5 dropped in burst
#define MAX_EULER_ERR_DEG    0.0001     // re-derived vs received Euler (double integrity)
#define MAX_AZ_ERR           0.0001     // received accel_z vs 9.80665

// ── Timing ───────────────────────────────────────────────────────────────────
#define DISPLAY_INTERVAL_MS  2000UL
#define SERIAL_INTERVAL_MS   5000UL
#define SIGNAL_TIMEOUT_MS    3000UL

// ── Ring buffer (WiFi task Core 0 → loop Core 1) ─────────────────────────────
#define RING_SIZE 32
static ImuDataPayload rxRing[RING_SIZE];
static volatile int   rxHead     = 0;
static volatile int   rxTail     = 0;
static volatile int   rxOverflow = 0;
portMUX_TYPE          rxMux      = portMUX_INITIALIZER_UNLOCKED;

// ── State ─────────────────────────────────────────────────────────────────────
TFT_eSPI  tft;
SPIClass  sdSpi(VSPI);
static bool     sdReady        = false;
static File     logFile;

static uint32_t totalReceived  = 0;
static uint32_t totalLost      = 0;
static uint32_t lastSeq        = UINT32_MAX;
static uint32_t maxGapMs       = 0;
static uint32_t lastTsMs       = 0;
static uint32_t lastStroke     = 0;
static double   maxEulerErr    = 0.0;
static double   maxAzErr       = 0.0;
static bool     testComplete   = false;
static unsigned long lastRxMs  = 0;
static bool          hasSignal = false;

// ── ESPnow callback (Core 0) ──────────────────────────────────────────────────
void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    if (len != (int)sizeof(ImuDataPayload)) return;
    ImuDataPayload p;
    memcpy(&p, data, sizeof(p));
    portENTER_CRITICAL(&rxMux);
    int next = (rxHead + 1) % RING_SIZE;
    if (next == rxTail) {
        rxOverflow++;
    } else {
        rxRing[rxHead] = p;
        rxHead         = next;
    }
    portEXIT_CRITICAL(&rxMux);
}

// ── Euler from quaternion (same formula as TX) ────────────────────────────────
static void quatToEuler(double qw, double qx, double qy, double qz,
                        double &roll, double &pitch, double &yaw) {
    roll  = atan2(2.0*(qw*qx + qy*qz), 1.0 - 2.0*(qx*qx + qy*qy)) * (180.0 / M_PI);
    double sinp = 2.0*(qw*qy - qz*qx);
    pitch = (fabs(sinp) >= 1.0) ? copysign(90.0, sinp) : asin(sinp) * (180.0 / M_PI);
    yaw   = atan2(2.0*(qw*qz + qx*qy), 1.0 - 2.0*(qy*qy + qz*qz)) * (180.0 / M_PI);
}

// ── Display ───────────────────────────────────────────────────────────────────
static void drawScreen() {
    tft.fillScreen(TFT_WHITE);

    // Header
    tft.setTextFont(2);
    tft.setTextColor(TFT_DARKGREY, TFT_WHITE);
    tft.setCursor(4, 4);
    tft.print(sdReady ? "ESPnow SD test [SD OK]" : "ESPnow SD test [NO SD]");

    int y = 28;
    bool rxing = hasSignal && (millis() - lastRxMs < SIGNAL_TIMEOUT_MS);
    float lossPct = (totalReceived + totalLost > 0)
        ? 100.0f * totalLost / (totalReceived + totalLost) : 0.0f;

    tft.setTextFont(4);

    // Stroke count — the main "stroke rate" readout
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    tft.setCursor(4, y); tft.printf("Strokes: %u", lastStroke); y += 30;

    // Signal indicator
    tft.setTextColor(rxing ? TFT_BLACK : TFT_RED, TFT_WHITE);
    tft.setCursor(4, y);
    tft.print(rxing ? "Signal:  OK" : "Signal:  ---"); y += 30;

    // Packet stats
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    tft.setCursor(4, y); tft.printf("RX:   %u", totalReceived); y += 28;

    tft.setTextColor(lossPct < MAX_LOSS_PCT ? TFT_BLACK : TFT_RED, TFT_WHITE);
    tft.setCursor(4, y); tft.printf("Loss: %.2f%%", lossPct); y += 28;

    tft.setTextColor(maxGapMs < MAX_GAP_MS ? TFT_BLACK : TFT_RED, TFT_WHITE);
    tft.setCursor(4, y); tft.printf("Gap:  %ums", maxGapMs); y += 28;

    // Test status
    if (testComplete) {
        bool pass = (lossPct < MAX_LOSS_PCT) &&
                    (maxGapMs < (uint32_t)MAX_GAP_MS) &&
                    (maxEulerErr < MAX_EULER_ERR_DEG) &&
                    (maxAzErr   < MAX_AZ_ERR) &&
                    sdReady;
        tft.setTextColor(pass ? TFT_GREEN : TFT_RED, TFT_WHITE);
        tft.setCursor(4, y);
        tft.print(pass ? "60s  PASS" : "60s  FAIL");
    } else {
        tft.setTextColor(TFT_DARKGREY, TFT_WHITE);
        unsigned long el = millis();
        tft.setCursor(4, y);
        if (el < TEST_DURATION_MS)
            tft.printf("t+%lus / 60s", el / 1000);
        else
            tft.print("running...");
    }
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println("paddlestroke_espnow_rx_sdlog — starting");

    // Display (HSPI, configured in User_Setup.h)
    tft.init();
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);
    // Clear noise pixels in all rotations then settle on rotation 2
    for (int r = 0; r < 4; r++) { tft.setRotation(r); tft.fillScreen(TFT_WHITE); }
    tft.setRotation(2);
    tft.setTextFont(2);
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    tft.setCursor(4, 4);
    tft.print("Init SD...");

    // SD card (VSPI — separate bus from display, no conflict)
    sdSpi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    if (!SD.begin(SD_CS, sdSpi, 4000000)) {
        Serial.println("SD init failed — continuing without SD");
        tft.setTextColor(TFT_RED, TFT_WHITE);
        tft.setCursor(4, 24); tft.print("SD FAILED — no card?");
        delay(1500);
    } else {
        char fname[] = "/ImuLog00.CSV";
        for (int i = 0; i < 100; i++) {
            fname[7] = '0' + i / 10;
            fname[8] = '0' + i % 10;
            if (!SD.exists(fname)) break;
        }
        logFile = SD.open(fname, FILE_WRITE);
        if (!logFile) {
            Serial.println("SD file open failed");
        } else {
            logFile.println(
                "seq,timestamp_ms,"
                "accel_x,accel_y,accel_z,"
                "q_w,q_x,q_y,q_z,"
                "roll,pitch,yaw,"
                "stroke_count,"
                "d_roll,d_pitch,d_yaw,"
                "roll_err,pitch_err,yaw_err,"
                "az_err");
            Serial.print("Logging to "); Serial.println(fname);
            sdReady = true;
        }
    }

    // ESPnow
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) {
        Serial.println("ESPnow init FAILED — halting");
        tft.setTextColor(TFT_RED, TFT_WHITE);
        tft.setCursor(4, 44); tft.print("ESPnow FAILED");
        while (true) delay(100);
    }
    esp_now_register_recv_cb(onReceive);

    drawScreen();
    Serial.printf("Pass criteria: loss<%.0f%%  gap<%dms  euler_err<%.4f  az_err<%.4f\n",
                  MAX_LOSS_PCT, MAX_GAP_MS, MAX_EULER_ERR_DEG, MAX_AZ_ERR);
    Serial.println("Waiting for packets (T-7: this unit ready before TX is powered on)");
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    // ── Drain one packet from ring buffer per iteration ───────────────────────
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
        totalReceived++;
        hasSignal = true;
        lastRxMs  = millis();

        // Sequence-number gap → count lost packets
        if (lastSeq != UINT32_MAX && pkt.seq > lastSeq + 1)
            totalLost += pkt.seq - lastSeq - 1;
        lastSeq = pkt.seq;

        // Timestamp gap between consecutive received packets
        if (lastTsMs > 0) {
            uint32_t gap = pkt.timestamp_ms - lastTsMs;
            if (gap > maxGapMs) maxGapMs = gap;
        }
        lastTsMs  = pkt.timestamp_ms;
        lastStroke = pkt.stroke_count;

        // T-3: re-derive Euler from received quaternion
        double d_roll, d_pitch, d_yaw;
        quatToEuler(pkt.q_w, pkt.q_x, pkt.q_y, pkt.q_z, d_roll, d_pitch, d_yaw);
        double rErr     = fabs(d_roll  - pkt.roll);
        double pErr     = fabs(d_pitch - pkt.pitch);
        double yErr     = fabs(d_yaw   - pkt.yaw);
        if (yErr > 180.0) yErr = 360.0 - yErr;   // handle ±180° wrap discontinuity
        double eulerErr = fmax(fmax(rErr, pErr), yErr);
        if (eulerErr > maxEulerErr) maxEulerErr = eulerErr;

        // T-4: accel_z vs known constant
        double azErr = fabs(pkt.accel_z - 9.80665);
        if (azErr > maxAzErr) maxAzErr = azErr;

        // Write CSV row (all values; d_euler and errors appended for offline check)
        if (sdReady) {
            char row[320];
            int n = snprintf(row, sizeof(row),
                "%u,%u,"
                "%.5f,%.5f,%.5f,"
                "%.8f,%.8f,%.8f,%.8f,"
                "%.5f,%.5f,%.5f,"
                "%u,"
                "%.5f,%.5f,%.5f,"
                "%.8f,%.8f,%.8f,"
                "%.8f\n",
                pkt.seq, pkt.timestamp_ms,
                pkt.accel_x, pkt.accel_y, pkt.accel_z,
                pkt.q_w, pkt.q_x, pkt.q_y, pkt.q_z,
                pkt.roll, pkt.pitch, pkt.yaw,
                pkt.stroke_count,
                d_roll, d_pitch, d_yaw,
                rErr, pErr, yErr,
                azErr);
            logFile.write((const uint8_t*)row, n);
        }
    }

    unsigned long now = millis();

    // ── Serial stats every 5 s ────────────────────────────────────────────────
    static unsigned long lastSerial = 0;
    if (now - lastSerial >= SERIAL_INTERVAL_MS) {
        lastSerial = now;
        int overflow;
        portENTER_CRITICAL(&rxMux);
        overflow = rxOverflow;
        portEXIT_CRITICAL(&rxMux);
        float lossPct = (totalReceived + totalLost > 0)
            ? 100.0f * totalLost / (totalReceived + totalLost) : 0.0f;
        Serial.printf("t+%lus  RX=%u Lost=%u Loss=%.2f%% MaxGap=%ums "
                      "EulerErr=%.7f AzErr=%.7f Overflow=%d Stroke=%u\n",
            now/1000, totalReceived, totalLost, lossPct, maxGapMs,
            maxEulerErr, maxAzErr, overflow, lastStroke);
        if (sdReady) logFile.flush();
    }

    // ── Display refresh every 2 s ─────────────────────────────────────────────
    static unsigned long lastDisplay = 0;
    if (!testComplete && now - lastDisplay >= DISPLAY_INTERVAL_MS) {
        lastDisplay = now;
        drawScreen();
    }

    // ── 60 s test complete ────────────────────────────────────────────────────
    static bool markedDone = false;
    if (!markedDone && now >= TEST_DURATION_MS) {
        markedDone = testComplete = true;
        if (sdReady) { logFile.flush(); }

        int overflow;
        portENTER_CRITICAL(&rxMux);
        overflow = rxOverflow;
        portEXIT_CRITICAL(&rxMux);

        float lossPct = (totalReceived + totalLost > 0)
            ? 100.0f * totalLost / (totalReceived + totalLost) : 0.0f;
        bool T1 = lossPct    < MAX_LOSS_PCT;
        bool T2 = maxGapMs   < (uint32_t)MAX_GAP_MS;
        bool T3 = maxEulerErr < MAX_EULER_ERR_DEG;
        bool T4 = maxAzErr    < MAX_AZ_ERR;
        bool T5 = sdReady;
        bool T6 = (overflow == 0);

        Serial.println("\n=== 60 s TEST COMPLETE ===");
        Serial.printf("Expected ~6000 packets at 100 Hz\n");
        Serial.printf("Received: %u  Lost: %u\n", totalReceived, totalLost);
        Serial.printf("T-1 Loss:     %.2f%%      %s  (pass < %.0f%%)\n",
                      lossPct, T1?"PASS":"FAIL", MAX_LOSS_PCT);
        Serial.printf("T-2 MaxGap:   %u ms       %s  (pass < %d ms)\n",
                      maxGapMs, T2?"PASS":"FAIL", MAX_GAP_MS);
        Serial.printf("T-3 EulerErr: %.7f deg  %s  (pass < %.4f)\n",
                      maxEulerErr, T3?"PASS":"FAIL", MAX_EULER_ERR_DEG);
        Serial.printf("T-4 AzErr:    %.7f m/s2 %s  (pass < %.4f)\n",
                      maxAzErr, T4?"PASS":"FAIL", MAX_AZ_ERR);
        Serial.printf("T-5 SD:       %s\n", T5?"PASS":"FAIL (no SD)");
        Serial.printf("T-6 Overflow: %d         %s\n", overflow, T6?"PASS":"FAIL");
        Serial.println((T1&&T2&&T3&&T4&&T5&&T6) ? "OVERALL: PASS" : "OVERALL: FAIL");
        Serial.println("T-7/T-8: manual — see sketch header comments");

        drawScreen();
        // Continue running so TFT remains visible; SD remains flushed
    }
}
