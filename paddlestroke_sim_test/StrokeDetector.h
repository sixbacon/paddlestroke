#pragma once
#include <stdint.h>

class StrokeDetector {
public:
    void reset();
    bool update(float rollDeg, unsigned long timestampUs);
    float getRateHz() const;
    bool isTimedOut(unsigned long nowUs) const;
    bool isRateMature() const;   // true once both peak and trough buffers have ≥ 2 entries

private:
    float         _inBuf[3];
    uint8_t       _inFill;

    float         _dcOffset;
    bool          _dcInitialized;

    float         _prev2, _prev1, _curr;
    uint8_t       _samplesSeen;
    unsigned long _prevTs;

    float         _lastPeakVal;
    unsigned long _lastPeakTs;
    bool          _hasPeak;

    float         _lastTroughVal;
    unsigned long _lastTroughTs;
    bool          _hasTrough;

    // Separate buffers prevent peak-to-peak and trough-to-trough intervals
    // from mixing, which was the root cause of erratic CPM output.
    float _rateBufPeak[4];
    int   _rateBufPeakCount;
    int   _rateBufPeakHead;
    float _rateBufTrough[4];
    int   _rateBufTroughCount;
    int   _rateBufTroughHead;

    unsigned long _lastQualifyingTs;
    float         _currentRateHz;

    bool _onExtrema(bool isPeak, float val, unsigned long tsUs);
    void _pushRate(float rateHz, bool isPeak);
    void _computeAverage();
};
