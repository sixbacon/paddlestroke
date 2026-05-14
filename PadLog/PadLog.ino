#include <SPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <Adafruit_BNO08x.h>
#include "esp_sleep.h"
#include "driver/gpio.h"
#include "StrokeDetector.h"

#define SKETCH_NAME    "PadLog"
#define SKETCH_VERSION "8.2"

// ── Payload struct — must match PadDis (PadDis.ino) exactly ──────────────────
struct __attribute__((packed)) ImuDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    float    accel_x, accel_y, accel_z;   // m/s², raw (includes gravity)
    float    q_w, q_x, q_y, q_z;          // rotation vector quaternion
    float    roll, pitch, yaw;             // degrees, derived on TX
    uint32_t stroke_count;                 // cumulative qualifying strokes
    uint32_t cpm;                          // current stroke rate CPM
    float    hz;                           // current stroke rate Hz
};
static_assert(sizeof(ImuDataPayload) == 60, "Payload size mismatch — check struct");

// ── Timing constants ──────────────────────────────────────────────────────────
#define DOZE_TIMEOUT_MS  (3UL * 60UL * 1000UL)
#define DOZE_REPORT_US   500000
#define NORMAL_REPORT_US 10000
#define MOTION_THRESHOLD 20.0f
// 20-second pause before WiFi init — keeps CH340 USB stable for reprogramming
// at 100 Hz ESPnow. Upload firmware during this window after each power cycle.
#define STARTUP_PAUSE_MS 20000UL

// ── BNO085 pins (VSPI) ────────────────────────────────────────────────────────
#define BNO_CS   5
#define BNO_INT  4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

static SPIClass           vspi(VSPI);
static Adafruit_BNO08x    bno(BNO_RST);
static sh2_SensorValue_t  sensorValue;
static StrokeDetector     detector;

static bool               timeoutActive   = false;
static bool               inDozeMode      = false;
static bool               espNowReady     = false;
static float              dozeFirstRoll   = NAN;
static unsigned long      inactiveStartMs = 0;

static uint32_t           g_seq           = 0;
static uint32_t           g_strokeCount   = 0;
static uint32_t           g_cpm           = 0;
static float              g_hz            = 0.0f;
static uint8_t            g_strokeStreak  = 0;    // consecutive qualifying strokes
static float              g_accel_x       = 0.0f;
static float              g_accel_y       = 0.0f;
static float              g_accel_z       = 0.0f;

// ── Helpers ───────────────────────────────────────────────────────────────────
struct Euler { float yaw, pitch, roll; };

static Euler extractEuler(const sh2_RotationVectorWAcc_t& rv) {
    float qr = rv.real, qi = rv.i, qj = rv.j, qk = rv.k;
    float sqi = qi*qi, sqj = qj*qj, sqk = qk*qk, sqr = qr*qr;
    Euler e;
    e.yaw   = atan2f(2.0f*(qi*qj + qk*qr),  sqi - sqj - sqk + sqr) * RAD_TO_DEG;
    e.pitch = asinf(-2.0f*(qi*qk - qj*qr) / (sqi + sqj + sqk + sqr)) * RAD_TO_DEG;
    e.roll  = atan2f(2.0f*(qj*qk + qi*qr), -sqi - sqj + sqk + sqr)  * RAD_TO_DEG;
    return e;
}

static void printTimestamp() {
    unsigned long s = millis() / 1000;
    char buf[12];
    snprintf(buf, sizeof(buf), "[%02lu:%02lu] ", s / 60, s % 60);
    Serial.print(buf);
}

static void enableNormalReports() {
    bno.enableReport(SH2_ARVR_STABILIZED_RV, NORMAL_REPORT_US);
    bno.enableReport(SH2_ACCELEROMETER,       NORMAL_REPORT_US);
}

static void initESPNow() {
    if (espNowReady) esp_now_deinit();
    espNowReady = false;
    WiFi.mode(WIFI_STA);
    if (esp_now_init() != ESP_OK) {
        Serial.println("ESPnow init failed — wireless disabled");
        return;
    }
    static const uint8_t broadcast[] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    esp_now_peer_info_t peer = {};
    memcpy(peer.peer_addr, broadcast, 6);
    peer.channel = 1;
    peer.encrypt = false;
    esp_now_add_peer(&peer);
    espNowReady = true;
}

static void sendImuPayload(const sh2_RotationVectorWAcc_t& rv, const Euler& e) {
    if (!espNowReady) return;
    static const uint8_t broadcast[] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    ImuDataPayload p;
    p.seq          = g_seq++;
    p.timestamp_ms = (uint32_t)millis();
    p.accel_x      = g_accel_x;
    p.accel_y      = g_accel_y;
    p.accel_z      = g_accel_z;
    p.q_w          = rv.real;
    p.q_x          = rv.i;
    p.q_y          = rv.j;
    p.q_z          = rv.k;
    p.roll         = e.roll;
    p.pitch        = e.pitch;
    p.yaw          = e.yaw;
    p.stroke_count = g_strokeCount;
    p.cpm          = g_cpm;
    p.hz           = g_hz;
    esp_now_send(broadcast, (uint8_t*)&p, sizeof(p));
}

// ── Doze mode ─────────────────────────────────────────────────────────────────
static void armDozeWakeup() {
    bno.enableReport(SH2_ARVR_STABILIZED_RV, DOZE_REPORT_US);
    sh2_SensorValue_t dummy;
    unsigned long drainEnd = millis() + 50;
    while (millis() < drainEnd) bno.getSensorEvent(&dummy);
    gpio_wakeup_enable((gpio_num_t)BNO_INT, GPIO_INTR_LOW_LEVEL);
    esp_sleep_enable_gpio_wakeup();
}

static void enterDozeMode() {
    dozeFirstRoll = NAN;
    armDozeWakeup();
    printTimestamp(); Serial.println("DOZE: low-power mode — waiting for motion");
    Serial.flush();
    inDozeMode = true;
}

static void exitDozeMode() {
    initESPNow();
    enableNormalReports();
    sh2_SensorValue_t dummy;
    unsigned long settleEnd = millis() + 500;
    while (millis() < settleEnd) bno.getSensorEvent(&dummy);
    detector.reset();
    g_strokeStreak  = 0;
    timeoutActive   = false;
    inactiveStartMs = 0;
    inDozeMode      = false;
    printTimestamp(); Serial.println("WAKE: motion detected — resuming");
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println(SKETCH_NAME " v" SKETCH_VERSION " — ready");
    Serial.printf("Payload: %u bytes  |  USB window: %lu s — upload firmware now if needed\n",
                  (unsigned)sizeof(ImuDataPayload), STARTUP_PAUSE_MS / 1000UL);
    delay(STARTUP_PAUSE_MS);

    vspi.begin(BNO_SCK, BNO_MISO, BNO_MOSI, BNO_CS);
    pinMode(BNO_INT, INPUT);
    pinMode(BNO_RST, OUTPUT);
    digitalWrite(BNO_RST, LOW);  delay(10);
    digitalWrite(BNO_RST, HIGH); delay(300);

    if (!bno.begin_SPI(BNO_CS, BNO_INT, &vspi)) {
        Serial.println("BNO085 init failed — halting");
        while (true) delay(100);
    }

    enableNormalReports();
    detector.reset();
    initESPNow();
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    if (!inDozeMode && timeoutActive &&
        millis() - inactiveStartMs >= DOZE_TIMEOUT_MS) {
        enterDozeMode();
    }

    if (inDozeMode) {
        esp_light_sleep_start();
        if (bno.getSensorEvent(&sensorValue) &&
            sensorValue.sensorId == SH2_ARVR_STABILIZED_RV) {
            float roll = extractEuler(sensorValue.un.arvrStabilizedRV).roll;
            if (!isnan(roll)) {
                if (!isnan(dozeFirstRoll) && fabsf(roll - dozeFirstRoll) > MOTION_THRESHOLD) {
                    dozeFirstRoll = NAN;
                    exitDozeMode();
                    return;
                }
                dozeFirstRoll = roll;
            } else {
                dozeFirstRoll = NAN;
            }
        } else {
            dozeFirstRoll = NAN;
        }
        armDozeWakeup();
        return;
    }

    if (bno.wasReset()) enableNormalReports();

    if (!bno.getSensorEvent(&sensorValue)) return;

    // Store latest accelerometer sample; used in next RV packet
    if (sensorValue.sensorId == SH2_ACCELEROMETER) {
        g_accel_x = sensorValue.un.accelerometer.x;
        g_accel_y = sensorValue.un.accelerometer.y;
        g_accel_z = sensorValue.un.accelerometer.z;
        return;
    }

    if (sensorValue.sensorId != SH2_ARVR_STABILIZED_RV) return;

    const sh2_RotationVectorWAcc_t& rv = sensorValue.un.arvrStabilizedRV;
    Euler         angles = extractEuler(rv);
    unsigned long nowUs  = micros();
    unsigned long nowMs  = millis();

    if (detector.update(angles.roll, nowUs)) {
        g_strokeCount++;
        g_strokeStreak++;
        // Only report and reset inactivity after 3 consecutive qualifying strokes —
        // suppresses CPM spikes from handling, transport, and isolated noise peaks.
        if (g_strokeStreak >= 3) {
            g_hz  = detector.getRateHz();
            g_cpm = (uint32_t)roundf(g_hz * 60.0f);
            timeoutActive   = false;
            inactiveStartMs = 0;
            printTimestamp();
            Serial.printf("CYCLE_RATE: %u CPM  (%.2f Hz)\n", g_cpm, g_hz);
        }
    } else if (detector.isTimedOut(nowUs) && !timeoutActive) {
        g_strokeStreak  = 0;
        g_cpm           = 0;
        g_hz            = 0.0f;
        printTimestamp(); Serial.println("CYCLE_RATE: 0 CPM  (0.00 Hz)");
        timeoutActive   = true;
        inactiveStartMs = nowMs;
    }

    sendImuPayload(rv, angles);
}
