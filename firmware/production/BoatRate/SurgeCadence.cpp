#include "SurgeCadence.h"
#include <math.h>
#include <string.h>

// Verbatim copy of the SC_* contract in
// visualisation/stroke_boat_cadence.py, validated 3 Nov 2026 against
// boat_only_spec.md §4/§6.1 (21 Oct SUP 30.9/min & canoe-back 29.3/min single;
// 30 Aug 72.8 / 12 Aug zero-feather 66.3 / 12 Aug feathered 70.3 — all 2× cycle
// for double blade). Change here and in the Python together.
static const int   DECIM     = 10;      // 100 Hz -> 10 Hz
static const float FS_HZ     = 10.0f;   // post-decimation sample rate
static const int   LAG_LO    = 6;       // ceiling 10/6 ≈ 1.67 Hz (100/min)
static const float MIN_FILL  = 0.8f;    // buffer fill fraction before estimating
static const float STD_GATE  = 0.10f;   // activity gate: surge/sway std in m/s²
static const float MIN_ACF   = 0.5f;    // periodicity quality gate
static const float FUND_FRAC = 0.75f;   // a local max is "strong" at ≥ this × global max
static const float ZERO_HILL = 0.30f;   // zero-lag correlation hill guard

void SurgeCadence::reset() {
    memset(_buf, 0, sizeof(_buf));
    _count                = 0;
    _decimAccum           = 0.0f;
    _decimCount           = 0;
    _samplesSinceEstimate = 0;
    _lastCpm              = 0.0f;
    _lastAcf              = 0.0f;
    _lastValid            = false;
}

void SurgeCadence::update(float accelMs2, unsigned long /*timestampUs*/) {
    _decimAccum += accelMs2;
    _decimCount++;
    if (_decimCount < DECIM) return;

    float avg   = _decimAccum / (float)DECIM;
    _decimAccum = 0.0f;
    _decimCount = 0;
    _pushSample(avg);

    _samplesSinceEstimate++;
    if (_samplesSinceEstimate >= (int)FS_HZ) {   // one estimate per second
        _samplesSinceEstimate = 0;
        _estimate();
    }
}

// Shift-based window (not a modulo ring) — BUF_LEN is only 160 floats at 10 Hz,
// so the memmove is negligible and keeps left-to-right time order.
void SurgeCadence::_pushSample(float v) {
    if (_count < BUF_LEN) {
        _buf[_count++] = v;
    } else {
        memmove(_buf, _buf + 1, (BUF_LEN - 1) * sizeof(float));
        _buf[BUF_LEN - 1] = v;
    }
}

void SurgeCadence::_estimate() {
    _lastValid = false;
    _lastCpm   = 0.0f;
    _lastAcf   = 0.0f;

    int n = _count;
    if (n < (int)(MIN_FILL * BUF_LEN)) return;

    float mean = 0.0f;
    for (int i = 0; i < n; i++) mean += _buf[i];
    mean /= (float)n;

    float x[BUF_LEN];
    float sumSq = 0.0f;
    for (int i = 0; i < n; i++) {
        x[i]   = _buf[i] - mean;
        sumSq += x[i] * x[i];
    }
    float std = sqrtf(sumSq / (float)n);
    if (std < STD_GATE) return;                 // not enough motion — glide/rest

    int lagHi = LAG_HI;
    if (lagHi > n - 4) lagHi = n - 4;
    if (lagHi < LAG_LO) return;

    float r[LAG_HI + 1];
    for (int lag = 1; lag <= lagHi; lag++) {
        int   m = n - lag;
        float dotAB = 0.0f, dotAA = 0.0f, dotBB = 0.0f;
        for (int i = 0; i < m; i++) {
            float a = x[i];
            float b = x[i + lag];
            dotAB += a * b;
            dotAA += a * a;
            dotBB += b * b;
        }
        float denom = sqrtf(dotAA * dotBB);
        r[lag] = (denom > 0.0f) ? (dotAB / denom) : 0.0f;
    }

    // Zero-lag hill guard — peaks are only meaningful once the ACF has first
    // decorrelated (smooth non-paddling motion correlates trivially at short
    // lags otherwise).
    int start = 1;
    while (start <= lagHi && r[start] > ZERO_HILL) start++;
    if (start > lagHi) return;
    if (start < LAG_LO) start = LAG_LO;

    float rmax = r[start];
    for (int lag = start + 1; lag <= lagHi; lag++) {
        if (r[lag] > rmax) rmax = r[lag];
    }
    if (rmax < MIN_ACF) return;

    // Fundamental-lock: the FIRST (smallest-lag) local max within FUND_FRAC of
    // the global max — the true period T (see SurgeCadence.h). Falls back to
    // the global argmax if no local max clears the fraction.
    int best = 0;
    for (int lag = start + 1; lag < lagHi; lag++) {
        if (r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1] && r[lag] >= FUND_FRAC * rmax) {
            best = lag;
            break;
        }
    }
    if (best == 0) {
        best = start;
        for (int lag = start + 1; lag <= lagHi; lag++) {
            if (r[lag] > r[best]) best = lag;
        }
    }

    // 3-point parabolic interpolation for sub-lag period precision.
    float delta = 0.0f;
    if (start < best && best < lagHi) {
        float y0 = r[best - 1], y1 = r[best], y2 = r[best + 1];
        float denom = y0 - 2.0f * y1 + y2;
        if (fabsf(denom) > 1e-12f) {
            delta = 0.5f * (y0 - y2) / denom;
            if (delta < -0.5f) delta = -0.5f;
            if (delta > 0.5f) delta = 0.5f;
        }
    }

    float periodS = ((float)best + delta) / FS_HZ;
    if (periodS <= 0.0f) return;

    _lastCpm   = 60.0f / periodS;
    _lastAcf   = rmax;
    _lastValid = true;
}

float SurgeCadence::getCpm()  const { return _lastValid ? _lastCpm : 0.0f; }
float SurgeCadence::getAcf()  const { return _lastAcf; }
bool  SurgeCadence::isValid() const { return _lastValid; }
