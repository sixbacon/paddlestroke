#include <SPI.h>
#include <SD.h>
#include <Adafruit_BNO08x.h>
#include "StrokeDetector.h"

#define BNO_CS   5
#define BNO_INT  4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

#define SD_CS   27
#define SD_SCK  14
#define SD_MOSI 13
#define SD_MISO 12

static SPIClass           vspi(VSPI);
static SPIClass           hspi(HSPI);
static Adafruit_BNO08x    bno(BNO_RST);
static sh2_SensorValue_t  sensorValue;
static StrokeDetector     detector;
static bool               timeoutActive = false;
static bool               SD_present    = false;
static File               logFile;
static unsigned long      lastFlushMs   = 0;

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

void setup() {
    Serial.begin(115200);
    Serial.println("PaddleStroke v1.0 — ready");

    // SD on HSPI
    hspi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
    if (!SD.begin(SD_CS, hspi, 1000000)) {
        Serial.println("SD init failed — logging disabled");
    } else {
        char fileName[] = "/PadDat00.CSV";
        for (int i = 0; i < 100; i++) {
            fileName[7] = '0' + i / 10;
            fileName[8] = '0' + i % 10;
            if (!SD.exists(fileName)) break;
        }
        logFile = SD.open(fileName, FILE_WRITE);
        if (!logFile) {
            Serial.println("SD file open failed — logging disabled");
        } else {
            logFile.println("timestamp_ms,roll,pitch,yaw");
            Serial.print("Logging to ");
            Serial.println(fileName);
            SD_present = true;
        }
    }

    // BNO085 on VSPI
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

    Euler         angles = extractEuler(sensorValue.un.arvrStabilizedRV);
    unsigned long nowUs  = micros();
    unsigned long nowMs  = millis();

    if (SD_present) {
        char row[64];
        int  len = snprintf(row, sizeof(row), "%lu,%.4f,%.4f,%.4f\n",
                            nowMs, angles.roll, angles.pitch, angles.yaw);
        logFile.write((const uint8_t*)row, len);
    }

    if (detector.update(angles.roll, nowUs)) {
        float hz  = detector.getRateHz();
        int   cpm = (int)roundf(hz * 60.0f);
        Serial.print("CYCLE_RATE: ");
        Serial.print(cpm);
        Serial.print(" CPM  (");
        Serial.print(hz, 2);
        Serial.println(" Hz)");
        timeoutActive = false;
        if (SD_present && nowMs - lastFlushMs >= 30000) {
            logFile.flush();
            lastFlushMs = nowMs;
        }
    } else if (detector.isTimedOut(nowUs) && !timeoutActive) {
        Serial.println("CYCLE_RATE: 0 CPM  (0.00 Hz)");
        timeoutActive = true;
        if (SD_present) { logFile.flush(); lastFlushMs = nowMs; }
    }
}
