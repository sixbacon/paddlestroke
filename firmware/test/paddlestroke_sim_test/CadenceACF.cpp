#include "CadenceACF.h"
#include <math.h>
#include <string.h>

// Mirrors visualisation/stroke_acf.py exactly — see that file and
// firmware spec §16.9 for the rationale behind each constant. Validated
// 20 Jul 2026 by reproducing the spec §16.10 pitch-ACF table numbers
// (e.g. 11 Jul padzero -> 29.6 CPM median) with an equivalent Python
// run before this port.
static const int   DECIM       = 10;     // 100 Hz -> 10 Hz
static const float FS_HZ       = 10.0f;  // post-decimation sample rate
static const int   LAG_LO      = 7;      // round(0.7 s * 10 Hz)
static const int   LAG_HI      = 40;     // round(4.0 s * 10 Hz)
static const float MIN_FILL    = 0.8f;   // buffer fill fraction before estimating
static const float MIN_STD_DEG = 10.0f;  // activity gate (replaces the amplitude gate)
static const float MIN_ACF     = 0.5f;   // periodicity quality gate
static const float FUND_FRAC   = 0.75f;  // fundamental-pick fraction of global max
static const float ZERO_HILL   = 0.30f;  // zero-lag correlation hill guard

void CadenceACF::reset() {
    memset(_buf, 0, sizeof(_buf));
    _count                = 0;
    _decimAccum           = 0.0f;
    _decimCount           = 0;
    _samplesSinceEstimate = 0;
    _lastCpm              = 0.0f;
    _lastValid            = false;
}

void CadenceACF::update(float pitchDeg, unsigned long /*timestampUs*/) {
    _decimAccum += pitchDeg;
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

// Shift-based window (not a modulo ring buffer) — BUF_LEN is only 120
// floats and this runs at 10 Hz, so the memmove cost (≤ 480 B) is
// negligible; it keeps the buffer contents in the same left-to-right
// time order Python's array slicing assumes, avoiding index-wrap bugs.
void CadenceACF::_pushSample(float v) {
    if (_count < BUF_LEN) {
        _buf[_count++] = v;
    } else {
        memmove(_buf, _buf + 1, (BUF_LEN - 1) * sizeof(float));
        _buf[BUF_LEN - 1] = v;
    }
}

void CadenceACF::_estimate() {
    _lastValid = false;
    _lastCpm   = 0.0f;

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
    float stdDeg = sqrtf(sumSq / (float)n);
    if (stdDeg < MIN_STD_DEG) return;

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

    // Zero-lag hill guard — peaks are only meaningful once the ACF has
    // first decorrelated (smooth non-paddling motion correlates trivially
    // at short lags otherwise). See firmware spec §16.9.
    int start = 1;
    while (start <= lagHi && r[start] > ZERO_HILL) start++;
    if (start > lagHi) return;
    if (start < LAG_LO) start = LAG_LO;

    float rmax = r[start];
    for (int lag = start + 1; lag <= lagHi; lag++) {
        if (r[lag] > rmax) rmax = r[lag];
    }
    if (rmax < MIN_ACF) return;

    // Fundamental pick: smallest-lag local maximum within FUND_FRAC of the
    // global max — lands on the full period for an asymmetric (feathered)
    // waveform's weaker half-period correlation. Falls back to the global
    // argmax (the true limit for a symmetric zero-feather waveform — see
    // spec §16.9/§16.10, this is why pitch and not roll feeds this class).
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
    _lastValid = true;
}

float CadenceACF::getCpm()  const { return _lastValid ? _lastCpm : 0.0f; }
bool  CadenceACF::isValid() const { return _lastValid; }
