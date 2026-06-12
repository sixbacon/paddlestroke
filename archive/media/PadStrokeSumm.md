# PadStroke — Kayak Paddle Stroke Rate Monitor

**Version:** 8.7  
**Date:** May 2026

---

## System Overview

PadStroke measures kayak paddle cycle rate (strokes per minute) in real time using an IMU
mounted at the centre of the paddle shaft. As the paddle alternates left and right strokes,
the shaft rolls back and forth. The system detects each roll oscillation, computes the cycle
rate, and displays it live on a wireless display unit clipped to the kayak. All raw IMU data
is logged to an SD card for post-session analysis.

---

## Hardware

| Unit | Function | MCU | Key Components |
|------|----------|-----|----------------|
| **PadLog** | Paddle sensor + transmitter | WEMOS LOLIN32 Lite (ESP32) | Bosch BNO085 IMU (SPI) |
| **PadDis** | Wireless display + data logger | CYD ESP32-2432S028 | 2.8″ TFT colour display, micro SD card |

**PadLog** is mounted at the centre of the paddle shaft. The BNO085 provides a fused
rotation vector (roll, pitch, yaw) and 3-axis accelerometer data at **100 Hz** over SPI.
IMU data is broadcast wirelessly to PadDis over **ESP-NOW** (802.11 Wi-Fi, ≤ 1% packet
loss measured at 100 Hz).

**PadDis** receives the wireless data stream, displays the current cycle rate as a large
numeric readout, and writes all IMU data to a timestamped CSV file on the SD card.

---

## Stroke Detection Algorithm

### Signal pre-processing

1. Extract **roll** from the BNO085 ARVR stabilised rotation vector at 100 Hz.
   Roll is rotation about the paddle shaft's long axis; it oscillates ±90° with each
   stroke cycle.
2. Apply a **3-sample moving average** to suppress sample-to-sample noise.
3. Apply an **EMA high-pass filter** to remove slow DC wander from paddler lean or
   kayak trim: `dcOffset += 0.002 × (roll − dcOffset)` (time constant ≈ 5 s).
   The filtered signal is centred near 0° regardless of mounting angle.

### Event detection and gating

Each local maximum (peak) and minimum (trough) in the filtered roll signal is a
candidate stroke event. A candidate is accepted only if all four gates are passed:

| Gate | Rule | Purpose |
|------|------|---------|
| **Amplitude** | \|peak − trough\| ≥ **90°** | Rejects wrist rotation from feathered blade entry (~85° in filtered space) |
| **Period** | Cycle period **0.4 s – 4.0 s** | Rejects transient noise and stationary handling |
| **Streak** | **3 consecutive** qualifying strokes required before rate is reported | Suppresses false starts at pickup |
| **Maturity** | Both peak and trough rate buffers must hold ≥ 2 entries | Prevents an early single-interval CPM spike |

### Rate computation

The stroke rate is averaged over a rolling window of the last **4 qualifying cycles**.
Peak-to-peak intervals and trough-to-trough intervals are tracked in **separate ring
buffers** (4 entries each) and averaged together. Separate buffers prevent alternating
half-cycle durations from mixing, which would produce erratic CPM when the two halves
of the stroke are timed differently.

The displayed CPM is smoothed with a **10-second EMA** (α = 0.001 at 100 Hz) to reduce
second-to-second jitter on the display. Raw (un-smoothed) CPM is written to the SD log.

### Typical stroke cycle

```
Filtered
roll (°)

         Peak            Peak            Peak
  +50     *               *               *
         /|\             /|\             /|
  +25   / | \           / | \           / |
       /  |  \         /  |  \         /  |
   0 -+---+---\-------/---+---\-------/---+--  (DC baseline)
       |   |   \     /    |    \     /    |
  -25  |   |    \   /     |     \   /     |
       |   |     \ /      |      \ /      |
  -50  |   |      *       |       *       |
       |      Trough              Trough
       |
       |<---------- 1 cycle ------------->|
       |            0.4 – 4.0 s
       |
       |<- amplitude ->|
       |    >= 90 deg   |
       | (peak-trough)  |
       |                |
       stroke count +1  stroke count +1
```

**Valid range:** 15 – 150 CPM (0.25 – 2.5 Hz). Events outside this range are discarded.

**Note on feathered paddles:** A 60° feathered paddle requires the **90° amplitude gate**.
The wrist rotation before each blade entry generates a ~85° roll event in the filtered
signal which the gate cleanly rejects. Unfeathered paddles may use a lower gate; as a
guide, set the gate to approximately feather_angle × 1.5.

---

## Low-Power Mode

After **3 minutes** of no qualifying paddle cycles, PadLog enters light sleep. The IMU
report rate drops to 2 Hz; the ESP32 wakes briefly every 500 ms to check for motion.
If roll changes by more than 20° between consecutive wake checks, normal 100 Hz operation
resumes immediately and the display reconnects within one stroke cycle.

---

## Data Logging — Output File Format

PadDis writes a CSV file to the SD card at 100 Hz. Files are auto-numbered
`ImuLog00.CSV` … `ImuLog99.CSV`. The first line identifies the firmware version;
the second line is the column header.

```
# PadDis v8.7
timestamp_ms,roll,pitch,yaw,stroke_count,cpm
85970,-65.577,40.841,69.489,0,0
85980,-65.512,40.798,69.501,0,0
...
```

### Column definitions

| Column | Type | Unit | Description |
|--------|------|------|-------------|
| `timestamp_ms` | integer | ms | Time since PadLog power-on |
| `roll` | float | degrees | Rotation about paddle shaft long axis. Oscillates ±90° with each stroke. |
| `pitch` | float | degrees | Fore-aft tilt of shaft. Negative = blade pulling through water; positive = opposite blade entering. |
| `yaw` | float | degrees | Compass heading of shaft. Not used for stroke detection. |
| `stroke_count` | integer | — | Cumulative qualifying strokes since power-on |
| `cpm` | integer | cycles/min | Raw (un-smoothed) cycle rate at time of packet. Zero until 3 consecutive qualifying strokes detected. |

**Logging rate:** 100 Hz (one row per IMU packet received). File is flushed to SD every
5 seconds and on signal loss. If no SD card is present, logging is silently disabled and
the display continues normally.

---

## Display

The CYD shows the current cycle rate as a large 7-segment-style numeral with a **CPM**
label. The readout uses a 10-second EMA to smooth second-to-second variation.
A flashing circle in the top-right corner indicates the wireless link is active.
The readout dims to grey if no packets are received for 3 seconds.

---

## Wireless Link

| Parameter | Value |
|-----------|-------|
| Protocol | ESP-NOW (802.11, channel 1) |
| Addressing | Broadcast (FF:FF:FF:FF:FF:FF) — no pairing required |
| Payload | 60 bytes (seq, timestamp, accel x/y/z, quaternion, roll/pitch/yaw, stroke_count, cpm, hz) |
| Rate | 100 Hz |
| Measured packet loss | < 0.03% |
| Range | Indoor Wi-Fi range; sufficient for kayak deck-to-shaft distance |
