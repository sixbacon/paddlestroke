#pragma once
#include <stdint.h>

class StrokeDetector {
public:
    void reset();
    bool update(float rollDeg, unsigned long timestampUs);
    float getRateHz() const;
    bool isTimedOut(unsigned long nowUs) const;

private:
    float         _inBuf[3];
    uint8_t       _inFill;

    float         _prev2, _prev1, _curr;
    uint8_t       _samplesSeen;
    unsigned long _prevTs;

    float         _lastPeakVal;
    unsigned long _lastPeakTs;
    bool          _hasPeak;

    float         _lastTroughVal;
    unsigned long _lastTroughTs;
    bool          _hasTrough;

    float _rateBuf[4];
    int   _rateBufCount;
    int   _rateBufHead;

    unsigned long _lastQualifyingTs;
    float         _currentRateHz;

    bool _onExtrema(bool isPeak, float val, unsigned long tsUs);
    void _pushRate(float rateHz);
    void _computeAverage();
};
