# Kayak Paddle Stroke Rate Monitor — Functional Specification

**Project:** paddlestroke  
**Date:** 23 April 2026  
**Version:** 1.1

---

## 1. Overview

A device mounted at the centre of a kayak paddle shaft that measures paddle cycle rate in real time using an inertial measurement unit (IMU). The primary sensing axis is roll of the paddle shaft. Cycle rate (one left stroke + one right stroke = one cycle) is computed from the oscillating roll signal and reported over a serial interface.

---

## 2. Hardware

| Component | Part |
|-----------|------|
| Processor | ESP32 |
| IMU | Bosch BNO085 |
| IMU Interface | SPI |
| IDE | Arduino IDE |
| IMU Library | Adafruit_BNO08x |

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

## 6. Out of Scope

- Display (LCD, OLED, etc.)
- Bluetooth or Wi-Fi transmission
- Stroke count accumulation or session logging
- Forward speed or GPS integration
- Calibration UI

---

## 7. Resolved Decisions

| # | Decision |
|---|----------|
| 1 | **Cycle rate** is reported (one left stroke + one right stroke = one cycle). |
| 2 | BNO085 is mounted at the **centre of the paddle shaft**; roll = rotation about the shaft's long axis. |
| 3 | Rate averaging uses an **event-based window** (last 4 qualifying cycles). |
