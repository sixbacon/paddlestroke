#include <SPI.h>
#include <Adafruit_BNO08x.h>
#include "StrokeDetector.h"

#define SKETCH_NAME    "PadVizLog"
#define SKETCH_VERSION "1.0"

// ── BNO085 pins (VSPI — same as PadLog) ──────────────────────────────────────
#define BNO_CS   5
#define BNO_INT  4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

#define REPORT_US 10000   // 100 Hz

static SPIClass          vspi(VSPI);
static Adafruit_BNO08x   bno(BNO_RST);
static sh2_SensorValue_t sensorValue;
static StrokeDetector    detector;

static uint32_t g_strokeCount  = 0;
static float    g_cpm          = 0.0f;
static uint8_t  g_strokeStreak = 0;

// ── Euler angles from rotation vector quaternion ──────────────────────────────
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

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    // Header lines — Processing PadViz skips lines starting with '#'
    Serial.println("# " SKETCH_NAME " v" SKETCH_VERSION);
    Serial.println("# timestamp_ms,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm");

    vspi.begin(BNO_SCK, BNO_MISO, BNO_MOSI, BNO_CS);
    pinMode(BNO_INT, INPUT);
    pinMode(BNO_RST, OUTPUT);
    digitalWrite(BNO_RST, LOW);  delay(10);
    digitalWrite(BNO_RST, HIGH); delay(300);

    if (!bno.begin_SPI(BNO_CS, BNO_INT, &vspi)) {
        Serial.println("# BNO085 init failed — halting");
        while (true) delay(100);
    }

    bno.enableReport(SH2_ARVR_STABILIZED_RV, REPORT_US);
    detector.reset();
    Serial.println("# ready");
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    if (bno.wasReset()) {
        bno.enableReport(SH2_ARVR_STABILIZED_RV, REPORT_US);
        return;
    }

    if (!bno.getSensorEvent(&sensorValue)) return;
    if (sensorValue.sensorId != SH2_ARVR_STABILIZED_RV) return;

    const sh2_RotationVectorWAcc_t& rv = sensorValue.un.arvrStabilizedRV;
    Euler         angles = extractEuler(rv);
    unsigned long nowUs  = micros();

    if (detector.update(angles.roll, nowUs)) {
        g_strokeCount++;
        g_strokeStreak++;
        if (g_strokeStreak >= 3 && detector.isRateMature()) {
            g_cpm = detector.getRateHz() * 60.0f;
        }
    } else if (detector.isTimedOut(nowUs)) {
        g_strokeStreak = 0;
        g_cpm          = 0.0f;
    }

    Serial.printf("%u,%.6f,%.6f,%.6f,%.6f,%.5f,%.5f,%.5f,%u,%.1f\n",
                  (uint32_t)millis(),
                  rv.real, rv.i, rv.j, rv.k,
                  angles.roll, angles.pitch, angles.yaw,
                  g_strokeCount, g_cpm);
}
