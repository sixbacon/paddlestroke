# Kayak Paddle Stroke Rate Monitor — Functional Specification

**Project:** paddlestroke  
**Date:** 29 April 2026  
**Version:** 1.2

---

## 1. Overview

A device mounted at the centre of a kayak paddle shaft that measures paddle cycle rate in real time using an inertial measurement unit (IMU). The primary sensing axis is roll of the paddle shaft. Cycle rate (one left stroke + one right stroke = one cycle) is computed from the oscillating roll signal and reported over a serial interface.

---

## 2. Hardware

| Component | Part |
|-----------|------|
| Processor | WEMOS LOLIN32 Lite (ESP32) |
| IMU | Bosch BNO085 |
| IMU Interface | SPI |
| Storage | Micro SD card reader |
| IDE | Arduino IDE |
| IMU Library | Adafruit_BNO08x |

### 2.1 Wiring — WEMOS LOLIN32 Lite ↔ BNO085

| WEMOS LOLIN32 Lite | BNO085 |
|--------------------|--------|
| +3V3 | Vin |
| +3V3 | P0 |
| +3V3 | P1 |
| GND | GND |
| GPIO4 | INT |
| GPIO5 | CS |
| GPIO16 | RST |
| GPIO18 | SCL |
| GPIO19 | SDA |
| GPIO23 | DI |

### 2.2 Wiring — WEMOS LOLIN32 Lite ↔ Micro SD Card Reader

| WEMOS LOLIN32 Lite | SD Card Reader |
|--------------------|----------------|
| +3V3 | Vcc |
| GND | GND |
| GPIO12 | MISO |
| GPIO13 | MOSI |
| GPIO14 | SCK |
| GPIO27 | CS |

---

## 3. Signal Characteristics

### 3.1 Roll Signal

- The BNO085 is mounted at the centre of the paddle shaft. Roll is rotation about the shaft's long axis.
- As the paddle rotates during alternating left and right strokes, the roll signal oscillates between **−90° and +90°**.
- One complete oscillation (peak → trough → peak, or trough → peak → trough) corresponds to one full cycle (left stroke + right stroke).

### 3.2 Valid Paddling Conditions

| Parameter | Minimum | Maximum |
|-----------|---------|---------|
| Cycle period | 0.4 s | 4.0 s |
| Cycle rate | 0.25 cycles/s (15 CPM) | 2.5 cycles/s (150 CPM) |
| Peak-to-trough roll amplitude | 45° | 180° (±90° range) |

*Note: the original individual-stroke period range of 0.2 s – 2.0 s maps to a cycle period range of 0.4 s – 4.0 s.*

Results outside these bounds must be discarded and not reported.

---

## 4. Functional Requirements

### 4.1 IMU Initialisation

- Initialise the BNO085 over SPI at startup.
- Request the **rotation vector** or **game rotation vector** report at a sample rate sufficient to resolve the maximum stroke rate (minimum **50 Hz** recommended; 100 Hz preferred).
- If the IMU fails to initialise, output an error message on the serial port and halt.

### 4.2 Roll Extraction

- With the BNO085 mounted at the centre of the paddle shaft, the roll axis aligns with the shaft's long axis. Extract the roll component (rotation about this axis, in degrees) from each IMU report.
- No additional filtering is mandatory at this stage; the stroke-detection algorithm provides implicit low-pass behaviour.

### 4.3 Stroke Detection Algorithm

Cycles are detected by identifying successive peaks and troughs in the roll signal. One peak + one trough = one complete cycle.

1. **Peak/trough detection** — a local maximum followed by a local minimum (or vice versa) constitutes one cycle. Each half-cycle is a single blade entry.
2. **Amplitude gate** — the absolute difference between a detected peak and the adjacent trough must be **≥ 45°**. Pairs that do not meet this threshold are ignored.
3. **Period measurement** — record the timestamp of each qualifying peak and trough. The time from one peak (or trough) to the next same-polarity extreme is one full cycle period.
4. **Rate validity gate** — only accept cycle periods in the range **0.4 s – 4.0 s**. Discard any cycle whose period falls outside this range.
5. **Rate averaging** — compute a rolling average of cycle rate over the last **4 qualifying cycles** to reduce noise.

### 4.4 Output

- Report cycle rate on the Arduino serial port at **115200 baud**.
- Output a new line each time a qualifying cycle is completed.
- Format:

```
CYCLE_RATE: <rate_cpm> CPM  (<rate_hz> Hz)
```

Where:
- `rate_cpm` = cycles per minute, integer, rounded to nearest whole number.
- `rate_hz` = cycles per second, two decimal places.

Example:

```
CYCLE_RATE: 72 CPM  (1.20 Hz)
```

- If no valid cycles are detected for more than **3 seconds**, output:

```
CYCLE_RATE: 0 CPM  (0.00 Hz)
```

- On startup, output a banner line:

```
PaddleStroke v1.0 — ready
```

---

## 5. Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| Latency from cycle completion to output | < 500 ms |
| IMU sample rate | ≥ 50 Hz |
| Serial baud rate | 115200 |
| Power supply | 3.3 V / 5 V via USB or LiPo |

---

## 6. Out of Scope (Phase 1–2)

The following are excluded from the current implementation. Items marked with a target phase are planned for later work.

- Display (LCD, OLED, etc.)
- Bluetooth / BLE / ESPnow transmission *(Phase 5)*
- Mobile app for stroke-rate display *(Phase 5)*
- SD card logging of IMU data *(Phase 3)*
- Low-power / sleep mode with motion wake-up *(Phase 4)*
- Forward speed or GPS integration
- Calibration UI

---

## 7. Resolved Decisions

| # | Decision |
|---|----------|
| 1 | **Cycle rate** is reported (one left stroke + one right stroke = one cycle). |
| 2 | BNO085 is mounted at the **centre of the paddle shaft**; roll = rotation about the shaft's long axis. |
| 3 | Rate averaging uses an **event-based window** (last 4 qualifying cycles). |

---

## 8. Development Roadmap

| Phase | Description |
|-------|-------------|
| **1** | Develop stroke detection algorithm and test it. *(Complete)* |
| **2** | Develop full stroke measurement unit based on hardware; test over USB serial in the laboratory using a dummy paddle. |
| **3** | Add logging of all orientation and position data to the micro SD card; test in the laboratory. |
| **4** | *(Field testing — outside AI scope.)* Test on a real paddle in a kayak on the water. Analyse recorded data to confirm roll is the best signal for stroke-rate detection. Implement low-power mode; wake up periodically to check for appropriate movement and switch the device into operational mode. |
| **5** | Improve stroke detection algorithm if field data indicates it is necessary. Transmit stroke rate and battery charge to other devices via BLE and ESPnow. Develop a mobile-phone app to display stroke rate. |

---

## 9. Test Plan

All tests are manual, performed with the ESP32 connected via USB and the Arduino Serial Monitor open at **115200 baud**. Unless stated otherwise, the BNO085 is connected and the firmware is freshly flashed.

---

### T-01 Startup Banner

**Steps:**
1. Flash firmware and power-cycle the ESP32.
2. Observe serial output within 2 s.

**Pass:** The first line received is exactly `PaddleStroke v1.0 — ready`.

---

### T-02 IMU Initialisation Failure

**Steps:**
1. Disconnect the BNO085 SPI wiring (or remove the chip).
2. Flash firmware and power-cycle.
3. Observe serial output.

**Pass:** An error message indicating IMU failure is printed and no further output is produced (firmware halts).

---

### T-03 Static / No Motion — Timeout Output

**Steps:**
1. Hold the paddle completely still for at least 4 s after startup.
2. Observe serial output.

**Pass:** After 3 s of no qualifying cycles, the line `CYCLE_RATE: 0 CPM  (0.00 Hz)` is emitted, with no spurious cycle-rate lines before it.

---

### T-04 Amplitude Gate — Below Threshold (< 45°)

**Steps:**
1. Rotate the paddle shaft slowly back and forth through an arc of approximately 20°–30° (well below 45°) at a rate that would otherwise be valid (≈ 1 Hz).
2. Observe serial output for 10 s.

**Pass:** No `CYCLE_RATE` lines with a non-zero rate are emitted; the 3 s timeout line may appear.

---

### T-05 Amplitude Gate — Above Threshold (≥ 45°)

**Steps:**
1. Rotate the paddle shaft through a smooth ±45° arc (90° peak-to-trough) at approximately 1 Hz.
2. Observe serial output.

**Pass:** Non-zero `CYCLE_RATE` lines are emitted within one cycle period of the first qualifying cycle.

---

### T-06 Rate Gate — Too Fast (> 2.5 Hz)

**Steps:**
1. Oscillate the paddle shaft through ≥ 45° at approximately 3 Hz (one cycle every ≈ 0.33 s).
2. Observe serial output for 10 s.

**Pass:** No non-zero `CYCLE_RATE` lines are emitted; cycles at this period are discarded.

---

### T-07 Rate Gate — Too Slow (< 0.25 Hz)

**Steps:**
1. Oscillate the paddle shaft through ≥ 45° with a period of approximately 5 s per cycle.
2. Observe serial output.

**Pass:** No non-zero `CYCLE_RATE` lines are emitted for those slow cycles; the 3 s timeout line may appear mid-cycle.

---

### T-08 Rate Gate — Valid Boundaries

**Steps:**
1. Perform cycles at approximately 0.25 Hz (4.0 s period). Record whether accepted.
2. Perform cycles at approximately 2.5 Hz (0.4 s period). Record whether accepted.

**Pass:** Both boundary rates produce non-zero `CYCLE_RATE` output.

---

### T-09 Output Format

**Steps:**
1. Paddle at a steady ≈ 1 Hz for several cycles.
2. Copy 3–5 consecutive `CYCLE_RATE` lines from the serial monitor.

**Pass:** Every line matches one of the two valid formats exactly:
- `CYCLE_RATE: <integer> CPM  (<two-decimal> Hz)` — two spaces between `CPM` and `(`
- `CYCLE_RATE: 0 CPM  (0.00 Hz)`

No trailing spaces, no extra fields, no missing fields.

---

### T-10 Rate Averaging (4-Cycle Window)

**Steps:**
1. Paddle at a steady 1.0 Hz (60 CPM) for 5 cycles; note reported rates.
2. Abruptly increase to ≈ 2.0 Hz (120 CPM) for 4 more cycles; note reported rates after each cycle.

**Pass:**
- During the step-change, the reported rate blends gradually over 4 cycles rather than jumping immediately.
- After 4 cycles at the new rate, the reported value is within ±5 CPM of 120 CPM.

---

### T-11 Output Latency

**Steps:**
1. Paddle at ≈ 1 Hz.
2. With a second observer or video capture, estimate the time from the moment a cycle visually completes (paddle returns to starting position) to when the serial line appears.

**Pass:** Latency is consistently below 500 ms.

---

### T-12 Sustained Operation

**Steps:**
1. Paddle at a steady ≈ 1 Hz for 5 minutes without interruption.
2. Observe output throughout.

**Pass:** Output remains continuous and correctly formatted; no freezes, crashes, or garbled lines.
