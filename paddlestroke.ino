#include <SPI.h>
#include <SD.h>
#include <WiFi.h>
#include <esp_now.h>
#include <Adafruit_BNO08x.h>
#include "esp_sleep.h"
#include "driver/gpio.h"
#include "StrokeDetector.h"

struct __attribute__((packed)) EspNowPayload {
    uint32_t cpm;
    float    hz;
};

#define DOZE_TIMEOUT_MS  (3UL * 60UL * 1000UL)
#define NORMAL_REPORT_US 10000
#define MOTION_THRESHOLD 20.0f
#define MOTION_WINDOW_MS 300

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
static bool               timeoutActive   = false;
static bool               SD_present      = false;
static File               logFile;
static unsigned long      lastFlushMs     = 0;
static unsigned long      inactiveStartMs = 0;
static bool               inDozeMode      = false;
static bool               espNowReady     = false;

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

static void espNowSend(uint32_t cpm, float hz) {
    if (!espNowReady) return;
    static const uint8_t broadcast[] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    EspNowPayload payload = {cpm, hz};
    esp_now_send(broadcast, (uint8_t*)&payload, sizeof(payload));
}

static void armDozeWakeup() {
    bno.enableReport(SH2_ARVR_STABILIZED_RV, 0);
    // Drain pending SHTP packets so INT goes high before sleep
    sh2_SensorValue_t dummy;
    unsigned long drainEnd = millis() + 50;
    while (millis() < drainEnd) bno.getSensorEvent(&dummy);
    bno.enableReport(SH2_SIGNIFICANT_MOTION, 0);
    gpio_wakeup_enable((gpio_num_t)BNO_INT, GPIO_INTR_LOW_LEVEL);
    esp_sleep_enable_gpio_wakeup();
}

static void enterDozeMode() {
    if (SD_present) logFile.flush();
    armDozeWakeup();
    Serial.println("DOZE: low-power mode — waiting for motion");
    Serial.flush();
    inDozeMode = true;
}

static bool checkForMotion() {
    float         firstRoll = NAN;
    unsigned long deadline  = millis() + MOTION_WINDOW_MS;
    while (millis() < deadline) {
        if (bno.getSensorEvent(&sensorValue) &&
            sensorValue.sensorId == SH2_ARVR_STABILIZED_RV) {
            float r = extractEuler(sensorValue.un.arvrStabilizedRV).roll;
            if (isnan(firstRoll)) { firstRoll = r; }
            else if (fabsf(r - firstRoll) > MOTION_THRESHOLD) return true;
        }
    }
    return false;
}

static void exitDozeMode() {
    initESPNow();
    bno.enableReport(SH2_ARVR_STABILIZED_RV, NORMAL_REPORT_US);
    detector.reset();
    timeoutActive   = false;
    inactiveStartMs = 0;
    inDozeMode      = false;
    Serial.println("WAKE: motion detected — resuming");
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

    if (!bno.enableReport(SH2_ARVR_STABILIZED_RV, NORMAL_REPORT_US)) {
        Serial.println("BNO085 report enable failed — halting");
        while (true) delay(100);
    }

    detector.reset();
    initESPNow();
}

void loop() {
    if (!inDozeMode && timeoutActive &&
        millis() - inactiveStartMs >= DOZE_TIMEOUT_MS) {
        enterDozeMode();
    }

    if (inDozeMode) {
        esp_light_sleep_start();
        // Wake = BNO085 significant motion asserted INT (GPIO4)
        bno.enableReport(SH2_ARVR_STABILIZED_RV, NORMAL_REPORT_US);
        if (checkForMotion()) {
            exitDozeMode();
        } else {
            armDozeWakeup();
        }
        return;
    }

    if (bno.wasReset()) {
        bno.enableReport(SH2_ARVR_STABILIZED_RV, NORMAL_REPORT_US);
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
        espNowSend((uint32_t)cpm, hz);
        timeoutActive   = false;
        inactiveStartMs = 0;
        if (SD_present && nowMs - lastFlushMs >= 30000) {
            logFile.flush();
            lastFlushMs = nowMs;
        }
    } else if (detector.isTimedOut(nowUs) && !timeoutActive) {
        Serial.println("CYCLE_RATE: 0 CPM  (0.00 Hz)");
        espNowSend(0, 0.0f);
        timeoutActive   = true;
        inactiveStartMs = nowMs;
        if (SD_present) { logFile.flush(); lastFlushMs = nowMs; }
    }
}
