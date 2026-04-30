#include <SPI.h>
#include <Adafruit_BNO08x.h>
#include "StrokeDetector.h"

#define BNO_CS   5
#define BNO_INT  4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

static SPIClass            vspi(VSPI);
static Adafruit_BNO08x     bno(BNO_RST);
static sh2_SensorValue_t   sensorValue;
static StrokeDetector      detector;
static bool                timeoutActive = false;

static float extractRoll(const sh2_RotationVectorWAcc_t& rv) {
    float qr = rv.real, qi = rv.i, qj = rv.j, qk = rv.k;
    return atan2f(2.0f * (qj * qk + qi * qr),
                  -qi*qi - qj*qj + qk*qk + qr*qr) * RAD_TO_DEG;
}

void setup() {
    Serial.begin(115200);
    Serial.println("PaddleStroke v1.0 — ready");

    vspi.begin(BNO_SCK, BNO_MISO, BNO_MOSI, BNO_CS);

    pinMode(BNO_INT, INPUT);
    pinMode(BNO_RST, OUTPUT);
    digitalWrite(BNO_RST, LOW);  delay(10);
    digitalWrite(BNO_RST, HIGH); delay(300);

    if (!bno.begin_SPI(BNO_CS, BNO_INT, &vspi)) {
        Serial.println("BNO085 init failed — halting");
        while (true) delay(100);
    }

    if (!bno.enableReport(SH2_ARVR_STABILIZED_RV, 10000)) {
        Serial.println("BNO085 report enable failed — halting");
        while (true) delay(100);
    }

    detector.reset();
}

void loop() {
    if (bno.wasReset()) {
        bno.enableReport(SH2_ARVR_STABILIZED_RV, 10000);
    }

    if (!bno.getSensorEvent(&sensorValue)) return;
    if (sensorValue.sensorId != SH2_ARVR_STABILIZED_RV) return;

    float roll = extractRoll(sensorValue.un.arvrStabilizedRV);
    unsigned long nowUs = micros();

    if (detector.update(roll, nowUs)) {
        float hz  = detector.getRateHz();
        int   cpm = (int)roundf(hz * 60.0f);
        Serial.print("CYCLE_RATE: ");
        Serial.print(cpm);
        Serial.print(" CPM  (");
        Serial.print(hz, 2);
        Serial.println(" Hz)");
        timeoutActive = false;
    } else if (detector.isTimedOut(nowUs) && !timeoutActive) {
        Serial.println("CYCLE_RATE: 0 CPM  (0.00 Hz)");
        timeoutActive = true;
    }
}
