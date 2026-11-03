#include <SPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <Adafruit_BNO08x.h>
#include <TinyGPSPlus.h>
#include <NimBLEDevice.h>
#include "SurgeCadence.h"

// ── BoatRate — boat-only cadence + speed unit (boat_only_spec.md) ─────────────
// Forked from BoatLog v1.2. Computes paddling cadence on-device from the hull
// forward-surge acceleration (SurgeCadence) and streams cadence + speed +
// position to a phone over BLE (NimBLE).
//
// DUAL OUTPUT by design (spec validation phase): the existing 100 Hz ESP-NOW →
// CYD → SD logging is kept BYTE-IDENTICAL to BoatLog v1.2 (same BoatDataPayload,
// same broadcast peer) so every outing still produces the raw CSV used as
// offline ground truth — PadDis/CYD firmware is untouched. BLE is added on top.
// Wi-Fi(ESP-NOW) + BLE share the one 2.4 GHz radio via the ESP32 coexistence
// arbiter; BLE runs at ~1 Hz to keep that load tiny (watch CYD seq gaps to
// confirm ESP-NOW throughput survives — spec Phase B).
#define SKETCH_NAME    "BoatRate"
#define SKETCH_VER_MAJOR 0
#define SKETCH_VER_MINOR 1
#define STR2(x) #x
#define STR(x) STR2(x)
#define SKETCH_VERSION STR(SKETCH_VER_MAJOR) "." STR(SKETCH_VER_MINOR)

// BLE GATT contract — MUST match app/index.html. One service, one notify
// characteristic emitting an ASCII CSV line ~1 Hz:
//   seq,ms,surge_cpm,sway_cpm,conf,mode,speed_ms,lat,lon,fix
// surge_cpm = hull-surge fundamental (blade plants/min); sway_cpm = sideways
// rate; mode 0=unknown 1=single(≈1:1) 2=double(≈2:1). The app applies the
// display convention: single → surge is the stroke rate; double(kayak) → sway
// is the left-right cycle rate ("CPM"). Raw numbers only here — no convention
// baked into the firmware.
#define BLE_DEVICE_NAME "BoatRate"
#define BLE_SERVICE_UUID "b0a7c0de-0001-4a7e-9c3b-1d2e3f405160"
#define BLE_CADENCE_UUID "b0a7c0de-0002-4a7e-9c3b-1d2e3f405160"

// ── Payload struct — must match BoatDataPayload in PadDis exactly (BoatLog v1.2)
struct __attribute__((packed)) BoatDataPayload {
    uint32_t seq;
    uint32_t timestamp_ms;
    uint32_t gps_utc_sec;    // seconds since midnight UTC; 0 if no fix
    float    gps_lat;
    float    gps_lon;
    float    gps_speed_ms;   // speed over ground, m/s
    float    gps_cog_deg;    // course over ground, degrees
    uint8_t  gps_fix;        // 0 = none, 1 = valid fix
    uint8_t  gps_uk_offset;  // UK UTC offset in hours: 0 (GMT) or 1 (BST)
    float    kayak_qw, kayak_qx, kayak_qy, kayak_qz;
    float    kayak_roll, kayak_pitch, kayak_yaw;
    float    accel_x, accel_y, accel_z;   // m/s², raw (includes gravity)
    float    grv_qw, grv_qx, grv_qy, grv_qz;  // game rotation vector (mag-free)
    uint8_t  mag_cal;                     // magnetometer accuracy 0–3
    uint8_t  fw_major, fw_minor;          // TX version, stamped into CSV header by PadDis
    uint8_t  _pad[1];                     // reserved, must be zero
};
static_assert(sizeof(BoatDataPayload) == 90, "BoatDataPayload size mismatch — check struct");

// ── BNO085 pins (VSPI — same as BoatLog) ──────────────────────────────────────
#define BNO_CS    5
#define BNO_INT   4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

// ── GPS UART ──────────────────────────────────────────────────────────────────
#define GPS_RX_PIN  13
#define GPS_TX_PIN  14
#define GPS_BAUD  9600

// ── Timing ───────────────────────────────────────────────────────────────────
#define STARTUP_PAUSE_MS 20000UL
#define REPORT_US        10000   // 100 Hz BNO085 reports
#define BLE_EMIT_MS      1000UL  // cadence/speed notify period
#define MODE_RATIO_THRESH 1.5f   // surge:sway ≥ this ⇒ double blade

static SPIClass          vspi(VSPI);
static Adafruit_BNO08x   bno(BNO_RST);
static sh2_SensorValue_t sensorValue;
static TinyGPSPlus       gps;
static HardwareSerial    gpsSerial(2);

static uint32_t g_seq     = 0;
static float    g_accel_x = 0.0f;
static float    g_accel_y = 0.0f;
static float    g_accel_z = 0.0f;
static bool     espNowReady = false;
static bool     gpsPrinted  = false;

// Mag calibration state
static uint8_t  g_mag_cal       = 0;
static uint8_t  g_mag_lastPrint = 255;
static bool     g_dcdSaved      = false;

// Latest game rotation vector (mag-free)
static float    g_grv_qw = 1.0f;
static float    g_grv_qx = 0.0f;
static float    g_grv_qy = 0.0f;
static float    g_grv_qz = 0.0f;

// Last-known GPS (for the BLE/serial emit between fixes)
static float    g_gps_speed = 0.0f;
static float    g_gps_lat   = 0.0f;
static float    g_gps_lon   = 0.0f;
static uint8_t  g_gps_fix   = 0;

// On-device cadence estimators: surge on forward axis, sway on starboard axis.
static SurgeCadence g_surge;   // accel_y
static SurgeCadence g_sway;    // accel_x

// BLE
static NimBLECharacteristic* g_cadenceChar = nullptr;
static bool g_bleConnected = false;

class ServerCb : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* s) override {
        g_bleConnected = true;
        Serial.println("BLE: phone connected");
    }
    void onDisconnect(NimBLEServer* s) override {
        g_bleConnected = false;
        Serial.println("BLE: phone disconnected — re-advertising");
        NimBLEDevice::startAdvertising();   // allow immediate reconnect (spec B-4)
    }
};

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

static int dayOfWeek(int y, int m, int d) {
    static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    if (m < 3) y--;
    return (y + y/4 - y/100 + y/400 + t[m-1] + d) % 7;
}

static int lastSunday(int y, int m) {
    static const int dim[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    int days = dim[m-1];
    if (m == 2 && (y % 4 == 0) && (y % 100 != 0 || y % 400 == 0)) days = 29;
    return days - dayOfWeek(y, m, days);
}

static int ukUtcOffsetHours(int y, int m, int d, int h) {
    if (m < 3 || m > 10) return 0;
    if (m > 3 && m < 10) return 1;
    int bstStart = lastSunday(y, 3);
    int bstEnd   = lastSunday(y, 10);
    if (m == 3)  return ((d > bstStart) || (d == bstStart && h >= 1)) ? 1 : 0;
    if (m == 10) return ((d < bstEnd)   || (d == bstEnd   && h <  1)) ? 1 : 0;
    return 0;
}

static void enableReports() {
    bno.enableReport(SH2_ARVR_STABILIZED_RV, REPORT_US);
    bno.enableReport(SH2_ACCELEROMETER,       REPORT_US);
    if (!bno.enableReport(SH2_GAME_ROTATION_VECTOR, REPORT_US)) {
        Serial.println("GRV report enable failed");
    }
    if (!bno.enableReport(SH2_MAGNETIC_FIELD_CALIBRATED, 100000UL)) {
        Serial.println("MAG report enable failed");
    }
}

static void printTimestamp() {
    unsigned long s = millis() / 1000;
    char buf[12];
    snprintf(buf, sizeof(buf), "[%02lu:%02lu] ", s / 60, s % 60);
    Serial.print(buf);
}

static void initESPNow() {
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
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

static void initBLE() {
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setMTU(185);   // ask for a larger MTU so the full CSV line fits one notify
    NimBLEServer* server = NimBLEDevice::createServer();
    server->setCallbacks(new ServerCb());
    NimBLEService* svc = server->createService(BLE_SERVICE_UUID);
    g_cadenceChar = svc->createCharacteristic(
        BLE_CADENCE_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    g_cadenceChar->setValue("waiting");
    svc->start();

    // Keep the advertising packet under the 31-byte BLE limit: the 128-bit
    // service UUID (18 B) goes in the ADV packet (Web Bluetooth's service
    // filter needs it there), and the device name goes in the SCAN RESPONSE
    // (otherwise UUID + name + flags = 31 B exactly, which can overflow and
    // stop advertising from starting at all).
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData advData;
    advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    advData.setCompleteServices(NimBLEUUID(BLE_SERVICE_UUID));
    adv->setAdvertisementData(advData);
    NimBLEAdvertisementData scanData;
    scanData.setName(BLE_DEVICE_NAME);
    adv->setScanResponseData(scanData);
    bool ok = NimBLEDevice::startAdvertising();
    Serial.printf("BLE: advertising %s as %s\n", ok ? "STARTED" : "FAILED", BLE_DEVICE_NAME);
}

// Build the ASCII CSV line and send it over BLE notify + serial.
static void emitCadence() {
    float surge = g_surge.getCpm();
    float sway  = g_sway.getCpm();
    float conf  = g_surge.getAcf();
    int   mode  = 0;    // 0 unknown, 1 single (≈1:1), 2 double (≈2:1)
    if (g_surge.isValid() && g_sway.isValid() && sway > 1.0f) {
        mode = (surge / sway >= MODE_RATIO_THRESH) ? 2 : 1;
    }

    char line[128];
    snprintf(line, sizeof(line),
             "%lu,%lu,%.1f,%.1f,%.2f,%d,%.2f,%.6f,%.6f,%d",
             (unsigned long)g_seq, (unsigned long)millis(),
             (double)surge, (double)sway, (double)conf, mode,
             (double)g_gps_speed, (double)g_gps_lat, (double)g_gps_lon,
             (int)g_gps_fix);

    if (g_cadenceChar) {
        g_cadenceChar->setValue((uint8_t*)line, strlen(line));
        if (g_bleConnected) g_cadenceChar->notify();
    }
    Serial.print("DATA ");
    Serial.println(line);
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println(SKETCH_NAME " v" SKETCH_VERSION " — ready");
    Serial.printf("Payload: %u bytes  |  USB window: %lu s — upload firmware now if needed\n",
                  (unsigned)sizeof(BoatDataPayload), STARTUP_PAUSE_MS / 1000UL);
    delay(STARTUP_PAUSE_MS);

    // BNO085 via VSPI
    vspi.begin(BNO_SCK, BNO_MISO, BNO_MOSI, BNO_CS);
    pinMode(BNO_INT, INPUT);
    pinMode(BNO_RST, OUTPUT);
    digitalWrite(BNO_RST, LOW);  delay(10);
    digitalWrite(BNO_RST, HIGH); delay(300);

    if (!bno.begin_SPI(BNO_CS, BNO_INT, &vspi)) {
        Serial.println("[TEST 1] BNO085: FAIL — halting");
        while (true) delay(100);
    }
    enableReports();
    Serial.println("[TEST 1] BNO085: PASS");

    g_surge.reset();
    g_sway.reset();

    // GPS UART
    gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    Serial.println("[TEST 2] GPS UART started — waiting for NMEA data...");

    initESPNow();   // Wi-Fi/ESP-NOW first …
    initBLE();      // … then BLE on top (coexistence arbiter handles the shared radio)
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    // ~1 Hz cadence/speed emit, independent of the IMU event cadence
    static uint32_t lastEmit = 0;
    if (millis() - lastEmit >= BLE_EMIT_MS) {
        lastEmit = millis();
        emitCadence();
    }

    // GPS — feed the parser; one-shot PASS print
    static char nmeaBuf[100];
    static int  nmeaLen = 0;
    while (gpsSerial.available()) {
        char c = (char)gpsSerial.read();
        gps.encode(c);
        if (c == '\n') {
            if (nmeaLen > 0 && !gpsPrinted) {
                Serial.println("[TEST 2] GPS: PASS");
                gpsPrinted = true;
            }
            nmeaLen = 0;
        } else if (c != '\r' && nmeaLen < (int)sizeof(nmeaBuf) - 1) {
            nmeaBuf[nmeaLen++] = c;
        }
    }

    if (bno.wasReset()) enableReports();
    if (!bno.getSensorEvent(&sensorValue)) return;

    if (sensorValue.sensorId == SH2_ACCELEROMETER) {
        g_accel_x = sensorValue.un.accelerometer.x;
        g_accel_y = sensorValue.un.accelerometer.y;
        g_accel_z = sensorValue.un.accelerometer.z;
        // Feed the on-device estimators every 100 Hz accel sample.
        g_surge.update(g_accel_y, micros());   // forward = surge
        g_sway.update(g_accel_x, micros());     // starboard = sway
        return;
    }

    if (sensorValue.sensorId == SH2_GAME_ROTATION_VECTOR) {
        g_grv_qw = sensorValue.un.gameRotationVector.real;
        g_grv_qx = sensorValue.un.gameRotationVector.i;
        g_grv_qy = sensorValue.un.gameRotationVector.j;
        g_grv_qz = sensorValue.un.gameRotationVector.k;
        return;
    }

    if (sensorValue.sensorId == SH2_MAGNETIC_FIELD_CALIBRATED) {
        g_mag_cal = sensorValue.status & 0x03;
        if (g_mag_cal != g_mag_lastPrint) {
            printTimestamp();
            Serial.printf("MAG_CAL: %u\n", (unsigned)g_mag_cal);
            g_mag_lastPrint = g_mag_cal;
        }
        if (g_mag_cal == 3 && !g_dcdSaved) {
            sh2_saveDcdNow();
            printTimestamp();
            Serial.println("DCD_SAVED");
            g_dcdSaved = true;
        }
        return;
    }

    if (sensorValue.sensorId != SH2_ARVR_STABILIZED_RV) return;
    if (!espNowReady) return;

    const sh2_RotationVectorWAcc_t& rv = sensorValue.un.arvrStabilizedRV;
    Euler e = extractEuler(rv);

    uint32_t utcSec   = 0;
    float    lat      = 0.0f, lon     = 0.0f;
    float    speedMs  = 0.0f, cog     = 0.0f;
    uint8_t  fix      = 0;
    uint8_t  ukOffset = 0;

    if (gps.location.isValid() && gps.time.isValid() && gps.date.isValid()) {
        fix      = 1;
        lat      = (float)gps.location.lat();
        lon      = (float)gps.location.lng();
        speedMs  = (float)gps.speed.mps();
        cog      = (float)gps.course.deg();
        int utcH = gps.time.hour();
        int utcM = gps.time.minute();
        int utcS = gps.time.second();
        utcSec   = (uint32_t)(utcH * 3600 + utcM * 60 + utcS);
        ukOffset = (uint8_t)ukUtcOffsetHours(gps.date.year(), gps.date.month(),
                                             gps.date.day(), utcH);

        int localH = (utcH + (int)ukOffset) % 24;
        static uint32_t lastGpsPrint = 0;
        if (millis() - lastGpsPrint >= 5000) {
            lastGpsPrint = millis();
            Serial.printf("GPS fix: %02d:%02d:%02d UK  lat=%.6f lon=%.6f  %.2f kn  COG=%.1f°\n",
                          localH, utcM, utcS,
                          (double)lat, (double)lon,
                          (double)gps.speed.knots(), (double)cog);
        }
    }

    // Keep last-known GPS for the BLE emit between fixes
    g_gps_speed = speedMs;
    g_gps_lat   = lat;
    g_gps_lon   = lon;
    g_gps_fix   = fix;

    static const uint8_t broadcast[] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    BoatDataPayload p;
    p.seq          = g_seq++;
    p.timestamp_ms = (uint32_t)millis();
    p.gps_utc_sec  = utcSec;
    p.gps_lat      = lat;
    p.gps_lon      = lon;
    p.gps_speed_ms = speedMs;
    p.gps_cog_deg  = cog;
    p.gps_fix       = fix;
    p.gps_uk_offset = ukOffset;
    p.kayak_qw     = rv.real;
    p.kayak_qx     = rv.i;
    p.kayak_qy     = rv.j;
    p.kayak_qz     = rv.k;
    p.kayak_roll   = e.roll;
    p.kayak_pitch  = e.pitch;
    p.kayak_yaw    = e.yaw;
    p.accel_x      = g_accel_x;
    p.accel_y      = g_accel_y;
    p.accel_z      = g_accel_z;
    p.grv_qw       = g_grv_qw;
    p.grv_qx       = g_grv_qx;
    p.grv_qy       = g_grv_qy;
    p.grv_qz       = g_grv_qz;
    p.mag_cal      = g_mag_cal;
    p.fw_major     = SKETCH_VER_MAJOR;
    p.fw_minor     = SKETCH_VER_MINOR;
    p._pad[0]      = 0;

    esp_now_send(broadcast, (uint8_t*)&p, sizeof(p));
}
