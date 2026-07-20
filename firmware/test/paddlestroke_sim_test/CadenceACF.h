#pragma once

// Pitch-fed autocorrelation cadence estimator — arbiter cross-check for
// StrokeDetector and zero-feather CPM fallback (firmware spec §16.9 /
// §16.10, port plan §16.12). Ported from visualisation/stroke_acf.py,
// validated offline against 11/13/16 Jul field sessions (pitch input
// reproduces the true cycle rate at zero feather, where roll reads the
// half-period; see §16.10 for why pitch, not roll).
//
// Call update() every IMU sample (100 Hz) with paddle pitch in degrees.
// Internally decimates 100 Hz -> 10 Hz (10-sample block average) and
// keeps a 12 s sliding window, producing a new estimate once per second.
// No per-stroke events — this is a rate estimator, not an edge detector.

class CadenceACF {
public:
    void  reset();
    void  update(float pitchDeg, unsigned long timestampUs);
    float getCpm()  const;   // last estimate, 0 if none/invalid
    bool  isValid() const;   // true if the last update() produced a usable estimate

private:
    static const int BUF_LEN = 120;   // 12 s at 10 Hz post-decimation

    float _buf[BUF_LEN];
    int   _count;

    float _decimAccum;
    int   _decimCount;
    int   _samplesSinceEstimate;

    float _lastCpm;
    bool  _lastValid;

    void _pushSample(float v);
    void _estimate();
};
