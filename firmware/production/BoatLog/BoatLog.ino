#include <SPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <Adafruit_BNO08x.h>
#include <TinyGPSPlus.h>

#define SKETCH_NAME    "BoatLog"
#define SKETCH_VERSION "1.0"

// Define to disable ESPnow and echo raw NMEA to serial — for GPS bench testing only.
// Comment out for normal operation.
// #define GPS_TEST_MODE

// ── Payload struct — must match BoatDataPayload in PadDis exactly ─────────────
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
};
static_assert(sizeof(BoatDataPayload) == 58, "BoatDataPayload size mismatch — check struct");

// ── BNO085 pins (VSPI — same as PadLog) ──────────────────────────────────────
#define BNO_CS    5
#define BNO_INT   4
#define BNO_RST  16
#define BNO_SCK  18
#define BNO_MOSI 23
#define BNO_MISO 19

// ── GPS UART ──────────────────────────────────────────────────────────────────
#define GPS_RX_PIN  13   // ESP32 RX ← GPS TX  (physical wire on GPIO13)
#define GPS_TX_PIN  14   // ESP32 TX → GPS RX  (physical wire on GPIO14)
#define GPS_BAUD  9600

// ── Timing ───────────────────────────────────────────────────────────────────
#define STARTUP_PAUSE_MS 20000UL
#define REPORT_US        10000   // 100 Hz BNO085 reports

static SPIClass          vspi(VSPI);
static Adafruit_BNO08x   bno(BNO_RST);
static sh2_SensorValue_t sensorValue;
static TinyGPSPlus       gps;
static HardwareSerial    gpsSerial(2);   // UART2

static uint32_t g_seq     = 0;
static float    g_accel_x = 0.0f;
static float    g_accel_y = 0.0f;
static float    g_accel_z = 0.0f;
static bool     espNowReady = false;
static bool     gpsPrinted  = false;   // T2 one-shot print flag

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

// Tomohiko Sakamoto algorithm — returns 0=Sun through 6=Sat
static int dayOfWeek(int y, int m, int d) {
    static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    if (m < 3) y--;
    return (y + y/4 - y/100 + y/400 + t[m-1] + d) % 7;
}

// Day number of the last Sunday in a given month
static int lastSunday(int y, int m) {
    static const int dim[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    int days = dim[m-1];
    if (m == 2 && (y % 4 == 0) && (y % 100 != 0 || y % 400 == 0)) days = 29;
    return days - dayOfWeek(y, m, days);
}

// UK offset: +1 during BST (last Sunday March 01:00 UTC → last Sunday October 01:00 UTC)
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

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println(SKETCH_NAME " v" SKETCH_VERSION " — ready");
    Serial.printf("Payload: %u bytes  |  USB window: %lu s — upload firmware now if needed\n",
                  (unsigned)sizeof(BoatDataPayload), STARTUP_PAUSE_MS / 1000UL);
    delay(STARTUP_PAUSE_MS);

#ifndef GPS_TEST_MODE
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
#else
    Serial.println("GPS_TEST_MODE: BNO085 disabled");
#endif

    // GPS UART
    gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    Serial.println("[TEST 2] GPS UART started — waiting for NMEA data...");

#ifndef GPS_TEST_MODE
    initESPNow();
#else
    Serial.println("GPS_TEST_MODE: ESPnow disabled — NMEA stream will echo to serial");
#endif
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    // Buffer complete NMEA sentences and print each one as a whole line
    static char nmeaBuf[100];
    static int  nmeaLen = 0;
    while (gpsSerial.available()) {
        char c = (char)gpsSerial.read();
        gps.encode(c);
        if (c == '\n') {
            if (nmeaLen > 0) {
                nmeaBuf[nmeaLen] = '\0';
                Serial.println(nmeaBuf);
                if (!gpsPrinted) {
                    Serial.println("[TEST 2] GPS: PASS");
                    gpsPrinted = true;
                }
            }
            nmeaLen = 0;
        } else if (c != '\r' && nmeaLen < (int)sizeof(nmeaBuf) - 1) {
            nmeaBuf[nmeaLen++] = c;
        }
    }

#ifndef GPS_TEST_MODE
    if (bno.wasReset()) enableReports();
    if (!bno.getSensorEvent(&sensorValue)) return;
#else
    return;   // GPS_TEST_MODE: skip BNO085 and ESPnow entirely
#endif

    if (sensorValue.sensorId == SH2_ACCELEROMETER) {
        g_accel_x = sensorValue.un.accelerometer.x;
        g_accel_y = sensorValue.un.accelerometer.y;
        g_accel_z = sensorValue.un.accelerometer.z;
        return;
    }

    if (sensorValue.sensorId != SH2_ARVR_STABILIZED_RV) return;
#ifndef GPS_TEST_MODE
    if (!espNowReady) return;
#endif

    const sh2_RotationVectorWAcc_t& rv = sensorValue.un.arvrStabilizedRV;
    Euler e = extractEuler(rv);

    // GPS fields — use last-known values; gps_fix=0 until location is valid
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

#ifndef GPS_TEST_MODE
    esp_now_send(broadcast, (uint8_t*)&p, sizeof(p));
#endif
}
