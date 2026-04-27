#include "StrokeDetector.h"
#include <math.h>

static const float         SAMPLE_RATE_HZ    = 100.0f;
static const unsigned long SAMPLE_INTERVAL_US = 10000UL;
static const float         RATE_TOL_HZ        = 2.0f / 60.0f;

static StrokeDetector det;
static int g_passed = 0;
static int g_failed = 0;

// ---------------------------------------------------------------------------
// Signal generator + standard test runner
// ---------------------------------------------------------------------------

// Feed numCycles of a sine wave into det. Returns last reported rate (Hz).
// outRates[] receives each qualifying cycle rate in order; outCount is set.
static float feedSine(float ampDeg, float freqHz, int numCycles,
                      unsigned long startUs,
                      float* outRates, int* outCount) {
    int   nSamples  = (int)(numCycles / freqHz * SAMPLE_RATE_HZ);
    float lastRate  = 0.0f;
    int   captured  = 0;

    for (int i = 0; i < nSamples; i++) {
        unsigned long tUs = startUs + (unsigned long)i * SAMPLE_INTERVAL_US;
        float tSec = tUs / 1000000.0f;
        float roll = ampDeg * sinf(2.0f * (float)M_PI * freqHz * tSec);
        if (det.update(roll, tUs)) {
            lastRate = det.getRateHz();
            if (outRates && outCount) {
                outRates[captured++] = lastRate;
            }
        }
    }
    if (outCount) *outCount = captured;
    return lastRate;
}

// Pass/fail for a rate check
static bool checkRate(const char* id, const char* desc,
                      float reportedHz, float expectedHz, float tolHz) {
    float repCpm = reportedHz * 60.0f;
    float expCpm = expectedHz * 60.0f;
    float tolCpm = tolHz      * 60.0f;
    bool  pass   = fabsf(reportedHz - expectedHz) <= tolHz;
    Serial.print(pass ? "[PASS] " : "[FAIL] ");
    Serial.print(id); Serial.print(" "); Serial.print(desc);
    Serial.print(": reported ");
    Serial.print(repCpm, 1);
    Serial.print(" CPM (expected ");
    Serial.print((int)roundf(expCpm));
    Serial.print(" CPM +/-");
    Serial.print((int)roundf(tolCpm));
    Serial.println(")");
    if (pass) g_passed++; else g_failed++;
    return pass;
}

static bool checkZero(const char* id, const char* desc, float reportedHz) {
    bool pass = (reportedHz == 0.0f);
    Serial.print(pass ? "[PASS] " : "[FAIL] ");
    Serial.print(id); Serial.print(" "); Serial.print(desc);
    Serial.print(": reported ");
    Serial.print(reportedHz * 60.0f, 1);
    Serial.println(" CPM (expected 0 CPM)");
    if (pass) g_passed++; else g_failed++;
    return pass;
}

static bool checkBool(const char* id, const char* desc,
                      bool actual, bool expected) {
    bool pass = (actual == expected);
    Serial.print(pass ? "[PASS] " : "[FAIL] ");
    Serial.print(id); Serial.print(" "); Serial.print(desc);
    Serial.print(": got ");
    Serial.print(actual ? "true" : "false");
    Serial.print(" (expected ");
    Serial.print(expected ? "true" : "false");
    Serial.println(")");
    if (pass) g_passed++; else g_failed++;
    return pass;
}

// ---------------------------------------------------------------------------
// Individual test cases
// ---------------------------------------------------------------------------

static void st01() {
    det.reset();
    float r = feedSine(60.0f, 1.0f, 8, 0, nullptr, nullptr);
    checkRate("ST-01", "Valid 1 Hz +/-60deg", r, 1.0f, RATE_TOL_HZ);
}

static void st02() {
    det.reset();
    float r = feedSine(60.0f, 0.5f, 8, 0, nullptr, nullptr);
    checkRate("ST-02", "Valid 0.5 Hz +/-60deg", r, 0.5f, RATE_TOL_HZ);
}

static void st03() {
    det.reset();
    float r = feedSine(60.0f, 2.0f, 8, 0, nullptr, nullptr);
    checkRate("ST-03", "Valid 2.0 Hz +/-60deg", r, 2.0f, RATE_TOL_HZ);
}

static void st04() {
    // spec originally said +-30deg but 60deg peak-to-trough > 45deg gate.
    // Corrected to +-20deg (40deg peak-to-trough) to test below-threshold.
    det.reset();
    float r = feedSine(20.0f, 1.0f, 8, 0, nullptr, nullptr);
    checkZero("ST-04", "Amplitude gate below 45deg (+-20deg)", r);
}

static void st05() {
    det.reset();
    float r = feedSine(22.5f, 1.0f, 8, 0, nullptr, nullptr);
    checkRate("ST-05", "Amplitude gate at 45deg (+-22.5deg)", r, 1.0f, RATE_TOL_HZ);
}

static void st06() {
    det.reset();
    float r = feedSine(60.0f, 3.0f, 8, 0, nullptr, nullptr);
    checkZero("ST-06", "Rate gate too fast 3.0 Hz", r);
}

static void st07() {
    det.reset();
    float r = feedSine(60.0f, 0.15f, 4, 0, nullptr, nullptr);
    checkZero("ST-07", "Rate gate too slow 0.15 Hz", r);
}

static void st08() {
    det.reset();
    float r = feedSine(60.0f, 0.25f, 8, 0, nullptr, nullptr);
    checkRate("ST-08", "Rate gate lower boundary 0.25 Hz", r, 0.25f, RATE_TOL_HZ);
}

static void st09() {
    det.reset();
    float r = feedSine(60.0f, 2.5f, 8, 0, nullptr, nullptr);
    checkRate("ST-09", "Rate gate upper boundary 2.5 Hz", r, 2.5f, RATE_TOL_HZ);
}

static void st10() {
    det.reset();

    // Phase A: 10 oscillations at 1 Hz — ensures all 4 window slots hold 1 Hz rates
    unsigned long tUs = 0;
    int nA = (int)(10.0f / 1.0f * SAMPLE_RATE_HZ);
    for (int i = 0; i < nA; i++) {
        float tSec = tUs / 1000000.0f;
        det.update(60.0f * sinf(2.0f * (float)M_PI * 1.0f * tSec), tUs);
        tUs += SAMPLE_INTERVAL_US;
    }

    // Phase B: 10 oscillations at 2 Hz, continuous timestamps.
    // The first 2 qualifying events are cross-phase transitions; after 6 events
    // the window is fully filled with 2 Hz measurements.
    float lastRateHz = 0.0f;
    int nB = (int)(10.0f / 2.0f * SAMPLE_RATE_HZ);
    for (int i = 0; i < nB; i++) {
        float tSec = tUs / 1000000.0f;
        if (det.update(60.0f * sinf(2.0f * (float)M_PI * 2.0f * tSec), tUs)) {
            lastRateHz = det.getRateHz();
        }
        tUs += SAMPLE_INTERVAL_US;
    }

    checkRate("ST-10", "Rolling average converges to 2 Hz after step change",
              lastRateHz, 2.0f, RATE_TOL_HZ);
    if (lastRateHz > 0.0f) {
        Serial.print("       (final reported: "); Serial.print(lastRateHz * 60.0f, 1);
        Serial.println(" CPM)");
    }
}

static void st11() {
    det.reset();
    bool timedOut = det.isTimedOut(3100000UL);
    checkBool("ST-11", "Timeout no motion at 3.1s", timedOut, true);
}

static void st12() {
    det.reset();
    float rates[10];
    int   count = 0;
    int   nSamples = (int)(4.0f / 1.0f * SAMPLE_RATE_HZ);
    unsigned long tUs = 0;
    for (int i = 0; i < nSamples; i++) {
        float tSec = tUs / 1000000.0f;
        if (det.update(60.0f * sinf(2.0f * (float)M_PI * 1.0f * tSec), tUs)) {
            if (count < 10) rates[count++] = det.getRateHz();
        }
        tUs += SAMPLE_INTERVAL_US;
    }
    unsigned long lastTUs = tUs - SAMPLE_INTERVAL_US;
    bool afterMotion = det.isTimedOut(lastTUs);
    bool afterPause  = det.isTimedOut(lastTUs + 3100000UL);
    bool pass = (!afterMotion && afterPause);

    Serial.print(pass ? "[PASS] " : "[FAIL] ");
    Serial.println("ST-12 Timeout motion then stop");
    if (!pass) {
        Serial.print("  afterMotion="); Serial.print(afterMotion ? "true" : "false");
        Serial.print(" afterPause=");  Serial.println(afterPause  ? "true" : "false");
    }
    if (pass) g_passed++; else g_failed++;
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

void setup() {
    Serial.begin(115200);
    delay(2000);
    Serial.println("PaddleStroke sim test starting...");
    Serial.println();

    st01(); st02(); st03(); st04(); st05(); st06();
    st07(); st08(); st09(); st10(); st11(); st12();

    Serial.println();
    Serial.print("Results: "); Serial.print(g_passed);
    Serial.print(" passed, "); Serial.print(g_failed);
    Serial.println(" failed");
}

void loop() {}
