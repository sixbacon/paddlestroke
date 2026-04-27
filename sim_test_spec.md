# Stroke Detection Algorithm — Simulation Test Specification

**Project:** paddlestroke  
**Date:** 27 April 2026  
**Version:** 1.0

---

## 1. Purpose

Verify the stroke detection algorithm (peak/trough detection, amplitude gate, rate gate, and 4-cycle rolling average) using synthetic roll data injected directly into the algorithm, without requiring the BNO085 IMU or a live paddle motion.

---

## 2. Hardware

| Component | Part |
|-----------|------|
| Processor | ESP DOIT DEVKIT V1 (`esp32:esp32:esp32doit-devkit-v1`) |
| IMU | None — roll data is synthesised in firmware |
| Interface | USB serial at 115200 baud |

No SPI wiring or IMU is required.

---

## 3. Architecture

### 3.1 Code Structure

The stroke detection algorithm is split out of `paddlestroke.ino` into a dedicated module:

```
paddlestroke/
  paddlestroke.ino          # main sketch — calls IMU, feeds StrokeDetector
  StrokeDetector.h          # algorithm class declaration
  StrokeDetector.cpp        # algorithm implementation

paddlestroke_sim_test/
  paddlestroke_sim_test.ino # test runner sketch
  StrokeDetector.h          # symlinked or copied from main sketch
  StrokeDetector.cpp        # symlinked or copied from main sketch
```

### 3.2 StrokeDetector Interface

```cpp
class StrokeDetector {
public:
    void reset();
    // Feed one roll sample (degrees) and the timestamp it was captured (microseconds).
    // Returns true if a qualifying cycle was just completed.
    bool update(float rollDeg, unsigned long timestampUs);
    // Rate from the last qualifying cycle (Hz). Returns 0.0 if no valid cycle yet.
    float getRateHz() const;
    // Returns true if no qualifying cycle has been seen for > 3 s.
    bool isTimedOut(unsigned long nowUs) const;
};
```

### 3.3 Signal Generator

The test sketch generates synthetic roll signals as discrete samples computed from a parametric waveform:

```
roll(t) = amplitude * sin(2π * frequency * t)
```

Samples are produced at a configurable rate (default 100 Hz) with a configurable amplitude (degrees peak) and frequency (Hz). Timestamps are advanced in fixed steps matching the sample interval — no real `delay()` is used, so tests run faster than real-time.

---

## 4. Test Output Format

Each test case prints to serial:

```
[PASS] ST-01 Valid 1 Hz, ±60°: reported 60.00 CPM (expected 60 CPM ±5)
[FAIL] ST-02 Amplitude gate 30°: reported 58.00 CPM (expected 0 CPM)
```

After all cases:

```
Results: 10 passed, 0 failed
```

A test passes when the reported rate (averaged over the last 4 cycles of the stimulus) falls within the stated tolerance.

---

## 5. Test Cases

### ST-01 Nominal rate — 1 Hz, ±60°

| Parameter | Value |
|-----------|-------|
| Waveform | Sine |
| Amplitude | ±60° |
| Frequency | 1.00 Hz |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 60 CPM ± 2 CPM |

**Pass criterion:** Reported rate within tolerance after the 8th qualifying cycle; no timeout fires during the run.

---

### ST-02 Nominal rate — 0.5 Hz, ±60°

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 0.50 Hz |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 30 CPM ± 2 CPM |

---

### ST-03 Nominal rate — 2.0 Hz, ±60°

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 2.00 Hz |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 120 CPM ± 2 CPM |

---

### ST-04 Amplitude gate — below threshold (40°)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±20° (40° peak-to-trough) |
| Frequency | 1.00 Hz |
| Cycles fed | 8 |
| Expected rate | 0 CPM (all cycles rejected) |

**Pass criterion:** `getRateHz()` returns 0.0 for all 8 cycles; `isTimedOut()` returns true after 3 s simulated time.

---

### ST-05 Amplitude gate — at threshold (45°)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±22.5° (exactly 45° peak-to-trough) |
| Frequency | 1.00 Hz |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 60 CPM ± 2 CPM |

**Pass criterion:** All 8 cycles are accepted (amplitude gate is inclusive at exactly 45°).

---

### ST-06 Rate gate — too fast (3.0 Hz)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 3.00 Hz (period ≈ 0.33 s) |
| Cycles fed | 8 |
| Expected rate | 0 CPM (all cycles rejected) |

---

### ST-07 Rate gate — too slow (0.15 Hz)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 0.15 Hz (period ≈ 6.7 s) |
| Cycles fed | 4 |
| Expected rate | 0 CPM (all cycles rejected) |

---

### ST-08 Rate gate — lower boundary (0.25 Hz)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 0.25 Hz (period = 4.0 s) |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 15 CPM ± 2 CPM |

**Pass criterion:** Cycles are accepted (lower boundary is inclusive).

---

### ST-09 Rate gate — upper boundary (2.5 Hz)

| Parameter | Value |
|-----------|-------|
| Amplitude | ±60° |
| Frequency | 2.50 Hz (period = 0.4 s) |
| Cycles fed | 8 |
| Expected rate after cycle 8 | 150 CPM ± 2 CPM |

**Pass criterion:** Cycles are accepted (upper boundary is inclusive).

---

### ST-10 Rolling average — step change

| Parameter | Phase A | Phase B |
|-----------|---------|---------|
| Amplitude | ±60° | ±60° |
| Frequency | 1.00 Hz | 2.00 Hz |
| Oscillations fed | 10 | 10 |

Phase A and Phase B share a continuous timestamp. Phase B begins immediately after Phase A ends — no reset between phases.

Because the algorithm triggers on both peaks and troughs, the first two Phase B qualifying events measure cross-phase periods (spanning the 1 Hz → 2 Hz boundary) rather than pure 2 Hz periods. After approximately 6 Phase B qualifying events the rolling window is fully refreshed with 2 Hz measurements.

**Pass criterion:** After 10 Phase B oscillations the reported rate is **120 CPM ± 2 CPM**, confirming the 4-cycle rolling average has fully converged to the new rate.

---

### ST-11 Timeout — no motion

| Parameter | Value |
|-----------|-------|
| Samples fed | 0 (no `update()` calls after reset) |
| Simulated elapsed time | 3.1 s |

**Pass criterion:** `isTimedOut()` returns true after 3.1 s simulated elapsed time.

---

### ST-12 Timeout — motion then stop

| Parameter | Value |
|-----------|-------|
| Phase 1 | 4 qualifying cycles at 1.0 Hz |
| Phase 2 | No further `update()` calls; advance time by 3.1 s |

**Pass criterion:** `isTimedOut()` returns false immediately after phase 1, true after phase 2.

---

## 6. Build and Run

```bash
# Compile
arduino-cli compile --fqbn esp32:esp32:esp32doit-devkit-v1 paddlestroke_sim_test/

# Upload (replace COM3 with actual port)
arduino-cli compile -u -p COM3 --fqbn esp32:esp32:esp32doit-devkit-v1 paddlestroke_sim_test/

# View results
arduino-cli monitor -p COM3 -c baudrate=115200
```

Tests run once automatically on startup. Reset the board to re-run.

---

## 7. Pass/Fail Definition

The full test suite passes when the serial output ends with:

```
Results: 12 passed, 0 failed
```

Any `[FAIL]` line constitutes a suite failure.
