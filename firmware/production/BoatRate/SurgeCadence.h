#pragma once

// Surge-ACF cadence estimator for the boat-only unit (boat_only_spec.md §5).
//
// Adapted from PadLog/CadenceACF.* (the pitch-fed zero-feather fallback) and
// retuned for hull ACCELERATION in m/s² instead of paddle pitch in degrees.
// Feed it one body-axis accel channel every IMU sample (100 Hz); internally it
// decimates 100 Hz -> 10 Hz (block average), keeps a 16 s sliding window, and
// produces a new estimate once per second.
//
// Run one instance on the forward axis (surge, accel_y) and one on the
// starboard axis (sway, accel_x). Every blade plant surges the hull once, so:
//   - single blade  (canoe/SUP): surge fundamental == stroke rate directly,
//                                 and sway sits at the SAME rate (ratio ≈ 1);
//   - double blade  (kayak):     surge == 2× the left-right cycle, sway == the
//                                 cycle rate (ratio ≈ 2).
// The caller derives the paddling mode from surge:sway and the display
// convention from the mode (BoatRate.ino).
//
// FUNDAMENTAL-LOCK: the estimate is the FIRST (smallest-lag) strong ACF peak
// after the zero-lag hill — the true period T. This rejects both the 2× FFT
// harmonic a one-sided surge pulse produces (spec §6.1) AND the 2T/3T
// sub-harmonic ACF peaks a "longest-period" scan would wrongly grab (verified
// offline: that scan reports HALF the real cadence). The constants below are a
// verbatim copy of SC_* in visualisation/stroke_boat_cadence.py — keep in sync.

class SurgeCadence {
public:
    void  reset();
    void  update(float accelMs2, unsigned long timestampUs);
    float getCpm()  const;   // last estimate (per-minute), 0 if none/invalid
    float getAcf()  const;   // last ACF peak height 0..1 (a confidence cue)
    bool  isValid() const;   // true if the last update() produced a usable estimate

private:
    static const int BUF_LEN = 160;   // 16 s at 10 Hz post-decimation
    static const int LAG_HI  = 50;    // floor 0.20 Hz (12/min)

    float _buf[BUF_LEN];
    int   _count;

    float _decimAccum;
    int   _decimCount;
    int   _samplesSinceEstimate;

    float _lastCpm;
    float _lastAcf;
    bool  _lastValid;

    void _pushSample(float v);
    void _estimate();
};
