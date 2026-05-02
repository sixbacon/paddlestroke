#include "StrokeDetector.h"
#include <math.h>

static const float         AMPLITUDE_GATE_DEG    = 45.0f;
static const float         PERIOD_MIN_S          = 0.4f;
static const float         PERIOD_MAX_S          = 4.0f;
static const unsigned long TIMEOUT_US            = 3000000UL;
static const unsigned long MIN_EXTREMA_INTERVAL  = 200000UL;  // 200 ms — half of min valid period
static const float         DC_ALPHA              = 0.002f;    // EMA coefficient: ~5 s time constant at 100 Hz

void StrokeDetector::reset() {
    _inBuf[0] = _inBuf[1] = _inBuf[2] = 0.0f;
    _inFill = 0;

    _dcOffset = 0.0f;
    _dcInitialized = false;

    _prev2 = _prev1 = _curr = 0.0f;
    _samplesSeen = 0;
    _prevTs = 0;

    _lastPeakVal = 0.0f; _lastPeakTs = 0; _hasPeak = false;
    _lastTroughVal = 0.0f; _lastTroughTs = 0; _hasTrough = false;

    for (int i = 0; i < 4; i++) _rateBuf[i] = 0.0f;
    _rateBufCount = 0;
    _rateBufHead  = 0;

    _lastQualifyingTs = 0;
    _currentRateHz    = 0.0f;
}

bool StrokeDetector::update(float rollDeg, unsigned long timestampUs) {
    // 3-sample moving average — suppresses noise-induced false extrema
    _inBuf[2] = _inBuf[1]; _inBuf[1] = _inBuf[0]; _inBuf[0] = rollDeg;
    if (_inFill < 3) _inFill++;
    rollDeg = (_inBuf[0] + _inBuf[1] + _inBuf[2]) / (float)_inFill;

    // EMA high-pass — removes slow DC wander (paddler lean, mounting drift)
    if (!_dcInitialized) { _dcOffset = rollDeg; _dcInitialized = true; }
    else _dcOffset += DC_ALPHA * (rollDeg - _dcOffset);
    rollDeg -= _dcOffset;

    unsigned long candidateTs = _prevTs;

    _prev2 = _prev1;
    _prev1 = _curr;
    _curr  = rollDeg;
    _prevTs = timestampUs;

    if (_samplesSeen < 3) { _samplesSeen++; }

    if (_samplesSeen < 3) return false;

    if (_prev2 < _prev1 && _prev1 >= _curr) {
        return _onExtrema(true,  _prev1, candidateTs);
    }
    if (_prev2 > _prev1 && _prev1 <= _curr) {
        return _onExtrema(false, _prev1, candidateTs);
    }
    return false;
}

bool StrokeDetector::_onExtrema(bool isPeak, float val, unsigned long tsUs) {
    bool qualified = false;

    if (isPeak) {
        if (_hasPeak && (tsUs - _lastPeakTs) < MIN_EXTREMA_INTERVAL) return false;

        if (!_hasTrough) {
            _lastPeakVal = val; _lastPeakTs = tsUs; _hasPeak = true;
            return false;
        }
        float amp = val - _lastTroughVal;
        if (amp < AMPLITUDE_GATE_DEG) return false;

        if (_hasPeak) {
            float periodS = (float)(tsUs - _lastPeakTs) / 1000000.0f;
            if (periodS >= PERIOD_MIN_S && periodS <= PERIOD_MAX_S) {
                _pushRate(1.0f / periodS);
                _computeAverage();
                _lastQualifyingTs = tsUs;
                qualified = true;
            }
        }
        _lastPeakVal = val; _lastPeakTs = tsUs; _hasPeak = true;

    } else {
        if (_hasTrough && (tsUs - _lastTroughTs) < MIN_EXTREMA_INTERVAL) return false;

        if (!_hasPeak) {
            _lastTroughVal = val; _lastTroughTs = tsUs; _hasTrough = true;
            return false;
        }
        float amp = _lastPeakVal - val;
        if (amp < AMPLITUDE_GATE_DEG) return false;

        if (_hasTrough) {
            float periodS = (float)(tsUs - _lastTroughTs) / 1000000.0f;
            if (periodS >= PERIOD_MIN_S && periodS <= PERIOD_MAX_S) {
                _pushRate(1.0f / periodS);
                _computeAverage();
                _lastQualifyingTs = tsUs;
                qualified = true;
            }
        }
        _lastTroughVal = val; _lastTroughTs = tsUs; _hasTrough = true;
    }

    return qualified;
}

float StrokeDetector::getRateHz() const { return _currentRateHz; }

bool StrokeDetector::isTimedOut(unsigned long nowUs) const {
    return (nowUs - _lastQualifyingTs) > TIMEOUT_US;
}

void StrokeDetector::_pushRate(float rateHz) {
    _rateBuf[_rateBufHead] = rateHz;
    _rateBufHead = (_rateBufHead + 1) % 4;
    if (_rateBufCount < 4) _rateBufCount++;
}

void StrokeDetector::_computeAverage() {
    float sum = 0.0f;
    for (int i = 0; i < _rateBufCount; i++) sum += _rateBuf[i];
    _currentRateHz = (_rateBufCount > 0) ? sum / _rateBufCount : 0.0f;
}
