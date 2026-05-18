# Kayak Paddle Stroke Rate Monitor — Functional Specification

**Project:** paddlestroke  
**Date:** 18 May 2026  
**Version:** 2.1

---

## 1. Overview

A device mounted at the centre of a kayak paddle shaft that measures paddle cycle rate in real time using an inertial measurement unit (IMU). The primary sensing axis is roll of the paddle shaft. Cycle rate (one left stroke + one right stroke = one cycle) is computed from the oscillating roll signal and reported over a serial interface.

The long-term goal is a fully **sealed, waterproof paddle device**. To achieve this, SD card logging is being moved from the paddle device to the CYD display unit via an ESPnow full-IMU data link (Phase 7). Once that link is validated, the paddle device need only transmit data — no external connectors are required and the housing can be sealed.

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
- Field data confirms roll is the correct sensing axis: BNO085 fusion output is clean (~1° sample-to-sample noise), high amplitude, and unambiguously rhythmic during paddling.
- The roll signal has a **slow DC wander** of several degrees over seconds, caused by paddler lean, mounting angle, or kayak trim changes. A high-pass pre-filter is applied to compensate — see §4.2.

### 3.2 Valid Paddling Conditions

| Parameter | Minimum | Maximum |
|-----------|---------|---------|
| Cycle period | 0.4 s | 4.0 s |
| Cycle rate | 0.25 cycles/s (15 CPM) | 2.5 cycles/s (150 CPM) |
| Peak-to-trough roll amplitude | 90° (feathered paddle) | 180° (±90° range) |

*Note: the original individual-stroke period range of 0.2 s – 2.0 s maps to a cycle period range of 0.4 s – 4.0 s.*

**Amplitude gate — feathered paddle:** The initial gate of 45° was designed for unfeathered paddles. Field analysis (18 May 2026) showed that a 60° feathered paddle produces a wrist rotation before each blade entry that generates a 70–85° roll event in the EMA-filtered signal — larger than the raw angle because the DC high-pass filter shifts the effective baseline. This spurious event passes all algorithm gates at 45° and at 70°, inflating CPM by ~1.7×. A gate of **90°** cleanly rejects feather rotation events (which peak at ~85°) while passing all genuine strokes (which produce ~100°+ peak-to-trough). The gate must be set to 90° for a 60° feathered paddle. Other feather angles require a gate approximately equal to feather_angle × 1.5.

Results outside these bounds must be discarded and not reported.

### 3.3 Field Test Observations (Phase 4, 2 May 2026)

First field data recorded with the device mounted on a kayak paddle shaft, paddled on the river. File: `PadDat02-20260502.CSV`. Two steady paddling sessions identified:

| Measurement | Session 1 | Session 2 |
|-------------|-----------|-----------|
| Duration | 388.7 s | 296.3 s |
| Stroke rate | 1.09 Hz (65.6 CPM) | 1.29 Hz (77.6 CPM) |
| Roll peak-to-trough | ~105° | ~101° |
| Roll absolute range | −69° to +84° | −66° to +76° |

Key findings:
- **Roll is confirmed as the correct sensing axis.** Signal is clean, high amplitude, and unambiguously rhythmic.
- **The 45° amplitude gate is workable.** Real strokes produce ~100° peak-to-trough, giving ample margin above the gate. The gate could be raised to 60° for stronger false-positive rejection without risk of missing genuine strokes.
- **Both observed rates (1.09–1.29 Hz) are comfortably within the 0.25–2.5 Hz valid range.** No change to the rate gate is needed.
- **Pitch is rhythmic (~100° range) but drifts with kayak trim**, making it a weaker signal than roll. No backup algorithm using pitch is implemented.
- **Yaw reflects compass heading** and is not useful for stroke detection.

### 3.4 Field Test Observations (Phase 8 v8.4, 18 May 2026)

File: `ImuLog1620260518.CSV`. 257,112 rows, 43.8 min, 100 Hz. True CPM ~32 (T-T interval 1895ms). Roll mean −31.4° (IMU mounting offset from shaft centreline).

**Root cause — feather rotation artefacts:**
The paddle has 60° feathered blades. The wrist rotation before each blade entry produces a 70–85° amplitude peak in the EMA high-pass filtered roll signal. This is above the 45° gate and passes the period gate (530–670 ms sub-event period is within 0.4–4.0 s bounds). Result: every stroke cycle generates one spurious qualifying event, in a repeating T, P, spurious-peak pattern.

- 32% of all qualifying events (702 of 2177) are feather rotation artefacts.
- Displayed CPM ~54 CPM is ~1.7× the true paddling rate of ~32 CPM.
- P:T event ratio = 0.61 (should be 1.0 for genuine strokes).
- Trough-to-trough CPM = 48.7 CPM (feather events split each true trough interval into two sub-intervals).

**Amplitude gate sweep (Python re-simulation on CSV):**

| Gate | P:T ratio | P-P CPM | T-T CPM | Result |
|------|-----------|---------|---------|--------|
| 45°  | 0.61 | — | 48.7 | Feather events pass freely |
| 70°  | 0.69 | — | 48.7 | Feather events still pass (amplitude 73–77° in filtered space) |
| 80°  | 0.93 | 32.9 | 36.1 | Better but not clean |
| **90°** | **0.90** | **31.7** | **33.6** | **Feather events rejected; true CPM correct** |
| 100° | — | — | — | Starts losing true strokes |

**Correct amplitude gate for a 60° feathered paddle = 90°.**

**Asymmetry analysis at 90° gate:**
- Option 1 (amplitude): mean ~0°, stdev 7° during steady paddling. Amplitude is symmetric — asymmetry is entirely in timing, not amplitude.
- Option 2 (event midRoll EMA + timing): 94% agreement with Option 3; stdev ~155 ms per 20-cycle window.
- Option 3 (consecutive-event comparison + timing): parameter-free, 35% less noisy than Option 2; **preferred**.
- Genuine timing asymmetry at 90° gate: P→T = 1494 ms, T→P = 401 ms (ratio 3.7:1), 98% of cycles; stdev 155–200 ms — stable enough to display.

**v8.4 asymmetry bar issues identified:**
- Bar almost always red because `asymMidRoll` EMA is updated on every 100 Hz sample (not at stroke events), so mid-stroke noise dominates.
- Five ±180° roll wrap events at t = 1.6–2.3 min corrupted the EMA immediately after session start.
- All asymmetry options are distorted by feather events until the amplitude gate is raised to 90°.

---

## 4. Functional Requirements

### 4.1 IMU Initialisation

- Initialise the BNO085 over SPI at startup.
- Request the **rotation vector** or **game rotation vector** report at a sample rate sufficient to resolve the maximum stroke rate (minimum **50 Hz** recommended; 100 Hz preferred).
- If the IMU fails to initialise, output an error message on the serial port and halt.

### 4.2 Roll Extraction

- With the BNO085 mounted at the centre of the paddle shaft, the roll axis aligns with the shaft's long axis. Extract the roll component (rotation about this axis, in degrees) from each IMU report.
- Apply a **3-sample moving average** to suppress noise-induced false extrema.
- Apply an **EMA high-pass filter** to remove slow DC offset caused by paddler lean or mounting drift: `dcOffset += DC_ALPHA × (roll − dcOffset); filteredRoll = roll − dcOffset`, with `DC_ALPHA = 0.002` (time constant ≈ 5 s at 100 Hz). The DC offset is initialised to the first sample to avoid startup transients.

### 4.3 Stroke Detection Algorithm

Cycles are detected by identifying successive peaks and troughs in the roll signal. One peak + one trough = one complete cycle.

1. **Peak/trough detection** — a local maximum followed by a local minimum (or vice versa) constitutes one cycle. Each half-cycle is a single blade entry.
2. **Amplitude gate** — the absolute difference between a detected peak and the adjacent trough must be **≥ 90°** (for a 60° feathered paddle). Pairs that do not meet this threshold are ignored. The original 45° gate was insufficient for feathered paddles: the wrist rotation before each blade entry generates a 70–85° spurious event in the filtered signal, inflating CPM by ~1.7× — see §3.2 and §3.4.
3. **Period measurement** — record the timestamp of each qualifying peak and trough. The time from one peak (or trough) to the next same-polarity extreme is one full cycle period.
4. **Rate validity gate** — only accept cycle periods in the range **0.4 s – 4.0 s**. Discard any cycle whose period falls outside this range.
5. **Rate averaging** — compute a rolling average of cycle rate over the last **4 qualifying cycles** to reduce noise. Peak-to-peak intervals and trough-to-trough intervals are tracked in **separate ring buffers** (4 entries each); the average is taken over all entries in both buffers. This prevents alternating half-cycle durations from mixing in a single buffer, which would produce erratic CPM when stroke timing varies.
6. **Streak gate** — CPM and Hz are updated only after **3 consecutive qualifying strokes** without interruption. A single qualifying stroke increments the internal stroke count but does not update the displayed rate. This suppresses CPM spikes from device handling, transport jolts, and isolated noise peaks.

### 4.5 Low-Power Doze Mode

After **3 minutes** of continuous inactivity (no qualifying paddle cycles), the device enters doze mode to conserve battery.

**Entering doze:**
- Flush the SD log file.
- Reduce the `SH2_ARVR_STABILIZED_RV` report rate to **2 Hz** (`DOZE_REPORT_US = 500 ms`).
- Configure **GPIO4** (wired to BNO085 INT, active-low) as the ESP32 light-sleep wakeup source. The BNO085 asserts INT on each data-ready event, waking the ESP32 at 2 Hz.
- Print `DOZE: low-power mode — waiting for motion` on serial.
- Enter **ESP32 light sleep** (RAM and SPI state preserved).

**While in doze:**
- Sleep until the BNO085 asserts INT (GPIO4 goes low) at the 2 Hz report rate.
- On wake: restore `SH2_ARVR_STABILIZED_RV` to 100 Hz and poll for **300 ms**, checking whether roll changes by ≥ **20°** (`MOTION_THRESHOLD`).
- If the roll-delta check fails (no real stroke), re-arm GPIO4 wakeup at 2 Hz and re-enter light sleep.

**Exiting doze:**
- Re-initialise ESPnow (WiFi radio is powered down during light sleep).
- Re-enable `SH2_ARVR_STABILIZED_RV` at 100 Hz (already done by wake check).
- Reset the stroke detector.
- Print `WAKE: motion detected — resuming` on serial.
- Resume normal IMU polling and SD logging.

### 4.6 ESPnow Transmission

After each CYCLE_RATE event the device broadcasts an 8-byte packet over ESPnow to the broadcast MAC address (`FF:FF:FF:FF:FF:FF`) on channel 1. No receiver pairing or network association is required.

**Payload (packed struct, 8 bytes):**

| Field | Type | Description |
|-------|------|-------------|
| `cpm` | uint32_t | Cycles per minute (0 = no valid rate) |
| `hz`  | float    | Cycles per second (0.00 = no valid rate) |

**Behaviour:**
- Initialised at startup (`WiFi.mode(WIFI_STA)` + `esp_now_init()`). Init failure is non-fatal; a warning is printed and the device continues with serial output only.
- Transmitted on every qualifying stroke and on every 3 s inactivity timeout, exactly mirroring the serial output events.
- Re-initialised on wake from doze mode (WiFi radio is powered down during ESP32 light sleep).
- No transmission during doze.

> The receiver hardware and display are specified in **§10**. The payload struct above defines the interface between the two projects.

### 4.4 Output

- Report cycle rate on the Arduino serial port at **115200 baud**.
- Output a new line each time a qualifying cycle is completed.
- Format:

```
[MM:SS] CYCLE_RATE: <rate_cpm> CPM  (<rate_hz> Hz)
```

Where:
- `MM:SS` = elapsed time since power-on (minutes and seconds, zero-padded).
- `rate_cpm` = cycles per minute, integer, rounded to nearest whole number.
- `rate_hz` = cycles per second, two decimal places.

Example:

```
[03:42] CYCLE_RATE: 72 CPM  (1.20 Hz)
```

- If no valid cycles are detected for more than **3 seconds**, output:

```
[MM:SS] CYCLE_RATE: 0 CPM  (0.00 Hz)
```

- Doze and wake events are also timestamped:

```
[MM:SS] DOZE: low-power mode — waiting for motion
[MM:SS] WAKE: motion detected — resuming
```

- On startup, output a banner line (no timestamp):

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
- Bluetooth / BLE transmission *(Phase 5)*
- ESPnow receiver device and display *(Phase 5 — separate project)*
- Mobile app for stroke-rate display *(Phase 5)*
- SD card logging of IMU data *(Phase 3)*
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
| **2** | Develop full stroke measurement unit based on hardware; test over USB serial in the laboratory using a dummy paddle. *(Complete)* |
| **3** | Add logging of all orientation and position data to the micro SD card; test in the laboratory. *(Complete)* |
| **4** | Field testing on real paddle shaft. Data collected and analysed 2 May 2026 — roll confirmed as best signal, high-pass filter added to algorithm. Low-power doze mode with GPIO4 interrupt wakeup implemented. *(Complete)* |
| **5** | Transmit stroke rate via ESPnow broadcast. Transmit side complete and tested (T-18a–T-18c). Receiver/display is a separate project. BLE and mobile app deferred. *(Complete)* |
| **6** | CYD ESPnow receiver with TFT display. LVGL dropped in favour of TFT_eSPI direct. Tests T-19–T-22 passed. *(Complete — 5 May 2026)* |
| **7** | ESPnow full-IMU data link — transmit raw IMU data from paddle device to CYD at 100 Hz; log to CYD SD card. Enables sealed paddle device. All tests T-23–T-31 passed (6 May 2026). *(Complete)* |
| **8** | Production integration — full-IMU ESPnow payload in PadLog; SD logging in PadDis; SD card removed from paddle device. Sketches renamed PadLog / PadDis with version scheme phase.iteration. v8.1: hardware validated 12 May 2026 (63 min session, 100 Hz, <0.03% loss, 51–76 CPM). v8.2: streak gate, separate rate buffers, asymmetry bar. v8.3: doze/wake bug fixed — accelerometer left active in doze mode was consuming all wakeup events, blocking RV data; fix disables accelerometer on doze entry. Full cycle validated 14 May 2026. v8.4: `isRateMature()` gate prevents post-wake CPM spike; rolling-midpoint asymmetry replaces `pitch >= 0` classifier. Field test 18 May 2026 revealed feather rotation artefacts inflating CPM 1.7× at 45° gate. v8.5 (PadDis only): CSV column selector (`CSV_COLUMNS_REDUCED`) reduces SD write volume 72%; 20-second EMA on displayed CPM (raw CSV unchanged). v8.6: `AMPLITUDE_GATE_DEG` raised 45°→90° (PadLog + sim_test) — rejects feather rotation events; Option 3 consecutive-event asymmetry replaces v8.4 rolling-midpoint EMA; dark display theme (black background, white text). *(Complete — v8.6 flashed and confirmed 18 May 2026)* |
| **9** | Blade entry/exit detection — use `accel_x`/`accel_y` transients to detect blade catch and release independently of roll oscillation. Enables stroke quality metrics (catch angle, release timing). *(Pending — design not started)* |

---

## 9. Test Plan

All tests are manual, performed with the ESP32 connected via USB and the Arduino Serial Monitor open at **115200 baud**. Unless stated otherwise, the BNO085 is connected and the firmware is freshly flashed.

---

### T-01 Startup Banner

**Steps:**
1. Flash firmware and power-cycle the ESP32.
2. Observe serial output within 2 s.

**Pass:** The first line received is exactly `PadLog v8.4 — ready` (version number reflects current release).

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
- `[MM:SS] CYCLE_RATE: <integer> CPM  (<two-decimal> Hz)` — two spaces between `CPM` and `(`
- `[MM:SS] CYCLE_RATE: 0 CPM  (0.00 Hz)`

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

---

### T-13 Enter Doze After 3-Minute Inactivity

**Steps:**
1. Start the device and confirm normal operation (observe startup banner and `CYCLE_RATE` output).
2. Hold the paddle completely still for at least 3 minutes 10 seconds.
3. Observe serial output throughout.

**Pass:**
- Within 3 s of no strokes, `CYCLE_RATE: 0 CPM  (0.00 Hz)` appears.
- Approximately 3 minutes after that, `DOZE: low-power mode — waiting for motion` is printed once.
- No further serial output for the remainder of the test.
- No premature doze message before the 3-minute mark.

---

### T-14 Wake from Doze on Motion

**Steps:**
1. Allow the device to enter doze mode (as per T-13).
2. Rotate the paddle shaft by ≥ 20° to trigger the BNO085 significant motion detector.
3. Observe serial output.

**Pass:** `WAKE: motion detected — resuming` is printed within a few seconds of the motion, followed by normal `CYCLE_RATE` output once qualifying strokes resume.

---

### T-15 No Premature Doze

**Steps:**
1. Hold the paddle still for 2 minutes 50 seconds, observing serial output.

**Pass:** Only `CYCLE_RATE: 0 CPM  (0.00 Hz)` lines are emitted; the `DOZE:` banner does not appear before 3 minutes have elapsed.

---

### T-16 Inactivity Timer Reset by Resumed Paddling

**Steps:**
1. Hold the paddle still until `CYCLE_RATE: 0 CPM` appears but before the 3-minute doze timeout.
2. Resume paddling with qualifying strokes (≥45°, valid rate).
3. Stop paddling again and hold still for at least 3 minutes.

**Pass:** The `DOZE:` banner does not appear during the paddling interval; after stopping, the full 3-minute inactivity period restarts from zero and doze is entered only after another 3 minutes of inactivity.

---

### T-17 Multiple Sleep/Wake Cycles

**Steps:**
1. Allow device to enter doze (as per T-13).
2. Wake with paddle motion (as per T-14); perform several qualifying strokes.
3. Stop paddling and hold still for 3 minutes.
4. Confirm device enters doze again.
5. Repeat once more.

**Pass:** `DOZE:` and `WAKE:` banners appear correctly on each cycle; stroke detection and SD logging operate normally between doze periods.

---

### T-18a ESPnow Init (no receiver required)

**Steps:**
1. Flash firmware and power-cycle.
2. Observe serial output during startup.

**Pass:** No `ESPnow init failed` message appears. Normal `CYCLE_RATE` output is unaffected.

---

### T-18b ESPnow Packet Reception (requires DOIT ESP32 DEVKIT V1)

A dedicated receiver sketch is provided in `paddlestroke_espnow_rx/`. It targets the DOIT ESP32 DEVKIT V1, listens on ESPnow channel 1, and prints received packets to its serial port in the same `CYCLE_RATE:` format as the transmitter.

**Build and flash (replace COM4 with the receiver's actual port):**

```bash
arduino-cli compile paddlestroke_espnow_rx/
arduino-cli upload -p COM4 paddlestroke_espnow_rx/
```

**Steps:**
1. Flash the receiver sketch to the DEVKIT V1 (it will be on a different COM port from the main device — use `arduino-cli board list` to identify both ports).
2. Open two serial monitors simultaneously — one for each COM port — both at 115200 baud.
3. With both devices powered, paddle at a steady rate for several cycles.
4. Compare the `CYCLE_RATE` lines on both monitors.

**Pass:** Every `CYCLE_RATE` line on the transmitter produces a matching line on the receiver within 100 ms; `cpm` and `hz` values agree.

---

### T-18c ESPnow After Doze/Wake

**Steps:**
1. With receiver running (as per T-18b), allow the transmitter to enter doze.
2. Wake with paddle motion and resume paddling.
3. Observe receiver output.

**Pass:** The first stroke after wake produces a received packet; no ESPnow failure messages on the transmitter serial port.

> **Note (2026-05-03):** T-18c initially triggered spurious wakes from room movement. Doze mode reworked to use GPIO4 (BNO085 INT) interrupt wakeup with ARVR report at 2 Hz, replacing the 2-second timer poll. Re-tested 4 May 2026 — passed.

---

## 10. ESPnow Receiver — CYD Display Unit

This section specifies the separate receiver project (`paddlestroke_espnow_rx/`). It receives ESPnow packets from the transmitter and displays the stroke rate on the CYD's built-in TFT screen.

---

### 10.1 Hardware

| Component | Part |
|-----------|------|
| Board | ESP32-2432S028 (CYD — Cheap Yellow Display) |
| Variant | CYD2USB (two USB ports: micro USB + USB-C) |
| Display | 2.8" ILI9341 TFT, 320×240 pixels (landscape) |
| Interface | Arduino CLI, same toolchain as transmitter |
| FQBN | `esp32:esp32:esp32` |

#### 10.1.1 Display Pin Assignments (HSPI)

| GPIO | Function |
|------|----------|
| IO2  | TFT_DC (RS) |
| IO12 | TFT_MISO |
| IO13 | TFT_MOSI |
| IO14 | TFT_SCK |
| IO15 | TFT_CS |
| IO21 | TFT_BL (backlight) |

#### 10.1.2 CYD2USB Notes

The USB-C port requires a USB-C to USB-A adaptor when connecting to a USB-C-only computer.

**Display inversion:** Some CYD2USB units ship with a hardware-inverted display and require `tft.invertDisplay(true)` in firmware to correct it. The unit used in this project does **not** require software inversion — calling `invertDisplay(true)` causes all colours to be inverted (white background appears black). Do not enable software inversion unless testing shows colours are wrong without it.

**Rotation:** `tft.setRotation(2)` gives correct landscape orientation on this unit. Rotations 1 and 3 produce portrait, rotation 0 produces landscape mirrored.

**Startup display clear:** The display has noise pixels in areas outside the active window that persist across reboots. At startup, call `tft.fillScreen(TFT_BLACK)` in all four rotations before settling on rotation 2. This writes the background colour to every addressable pixel regardless of rotation mapping, eliminating the noise strip.

---

### 10.2 Libraries

| Library | Purpose |
|---------|---------|
| `TFT_eSPI` 2.5.43 | Hardware display driver |
| `WiFi` / `esp_now` | ESPnow reception |

LVGL is **not used**. TFT_eSPI is driven directly. Font 8 (built-in 75 px 7-segment style) is used for the large rate number; Font 4 for the CPM sub-label. A `User_Setup.h` with `#define USER_SETUP_LOADED` must be present in the sketch directory.

---

### 10.3 Display Behaviour

#### 10.3.1 Startup Splash (0–20 s)

On power-up, display the sketch name centred on screen for 20 seconds before switching to the main rate screen:

```
paddlestroke_espnow_rx
```

Text should be legible but need not fill the screen.

#### 10.3.2 Main Rate Screen

After the splash, show the stroke rate. The rate value must occupy most of the screen — use TFT_eSPI Font 8 (75 px 7-segment style), centred.

**Layout (landscape, rotation 2):**

```
┌─────────────────────────────┐  ← black background
│                          [●] │  ← signal icon (top-right), white
│                              │
│          72 CPM              │  ← white text; grey when signal lost
│                              │
│      ────────|──────────     │  ← asymmetry bar (red/green)
└─────────────────────────────┘
```

- The CPM value is an integer. The unit label `CPM` is displayed alongside or below the number, smaller.
- On startup (before any packet received) display `-- CPM`.

#### 10.3.3 Signal Indicator Icon

A small icon in the top-right corner indicates reception state:

| State | Icon appearance |
|-------|----------------|
| Receiving (packet within last 3 s) | Filled circle, flashing at ~1 Hz |
| Signal lost (no packet for > 3 s) | Hollow circle, static |

#### 10.3.4 Colour Scheme

Background is black throughout. Text and icon colours:

| State | Colour |
|-------|--------|
| Receiving (packet within last 3 s) | White `#FFFFFF` (black background) |
| Signal lost (no packet for > 3 s) | Grey `0x9492` |

When signal is lost the last received rate remains on screen in grey. The display does not reset to `--` until the device is power-cycled.

**Startup clear:** At startup, `fillScreen(TFT_BLACK)` is called in all four rotations before settling on rotation 2. This writes black to every addressable pixel regardless of rotation mapping, eliminating noise pixels in areas outside the active window.

---

### 10.4 ESPnow Reception

- Initialise WiFi in station mode and set channel 1 at startup.
- Register a receive callback; on each valid 8-byte packet, update the displayed rate and timestamp the last-received time.
- Payload struct (must match transmitter exactly):

```cpp
struct __attribute__((packed)) EspNowPayload {
    uint32_t cpm;
    float    hz;
};
```

- A packet with `cpm == 0` represents a transmitter inactivity timeout; display `0 CPM` in the active colour (the transmitter is still alive).
- ESPnow init failure is fatal for this device — display an error message and halt.

---

### 10.5 Build and Flash

```bash
# Compile
arduino-cli compile paddlestroke_espnow_rx/

# Upload
arduino-cli upload -p COM6 paddlestroke_espnow_rx/
```

---

### T-19 Startup Splash

**Steps:**
1. Power-cycle the CYD receiver.
2. Observe the display for 20 seconds.

**Pass:** The sketch name is displayed for approximately 20 seconds, then the main rate screen appears.

**Result: PASSED (5 May 2026)**

---

### T-20 Rate Display — Active

**Steps:**
1. With the transmitter paddling at a steady rate, power up the receiver.
2. Observe the display.

**Pass:** The current CPM value is shown in white in large text; the signal icon is filled and flashing at ~1 Hz.

**Result: PASSED (5 May 2026)**

---

### T-21 Rate Display — Signal Lost

**Steps:**
1. With the receiver showing an active rate, stop transmitting (power off transmitter or let it enter doze).
2. Wait 5 seconds and observe the display.

**Pass:** After 3 seconds with no packet, the last rate value remains on screen but changes to grey; the signal icon becomes a static hollow circle.

**Result: PASSED (5 May 2026)**

---

### T-22 Rate Resumes After Loss

**Steps:**
1. Allow the display to enter signal-lost state (T-21).
2. Resume transmitting.

**Pass:** Within one packet period the value updates, returns to white, and the signal icon resumes flashing.

**Result: PASSED (5 May 2026)**

---

## 11. ESPnow Full-IMU Data Link — CYD SD Logging (Phase 7)

This section specifies the Phase 7 ESPnow data link that transmits raw IMU data from the paddle device to the CYD at 100 Hz, where it is logged to SD card. The goal is to eliminate the need for an SD card or USB connector on the paddle device, enabling a fully sealed waterproof enclosure.

**Do not modify `paddlestroke.ino` or `paddlestroke_espnow_rx.ino` until tests T-23–T-31 pass.**

---

### 11.1 Motivation

The current paddle device has an SD card slot and USB connector that prevent waterproofing. If all data recording is offloaded to the CYD (which is in the kayak cockpit, not submerged), the paddle device needs only a power connection and a radio — both of which can be made waterproof. The ESPnow link already exists for stroke rate; this phase extends it to carry the full 100 Hz IMU stream.

---

### 11.2 ESPnow Payload

A single packed struct is broadcast at every IMU sample (100 Hz). The struct is shared between the TX and RX sketches and must be kept identical in both.

**Payload struct (92 bytes, well within the 250-byte ESP-NOW limit):**

```cpp
struct __attribute__((packed)) ImuDataPayload {
    uint32_t seq;           // monotonic counter — gap means lost packet(s)
    uint32_t timestamp_ms;  // TX millis()
    double   accel_x;       // m/s²
    double   accel_y;       // m/s²
    double   accel_z;       // m/s²
    double   q_w;           // quaternion (w, x, y, z)
    double   q_x;
    double   q_y;
    double   q_z;
    double   roll;          // degrees, derived from quaternion on TX
    double   pitch;         // degrees
    double   yaw;           // degrees
    uint32_t stroke_count;  // increments on each qualifying stroke
};
// static_assert(sizeof(ImuDataPayload) == 92, "Payload size mismatch");
```

All floating-point fields use `double` (64-bit IEEE 754 on ESP32). The `seq` field allows the receiver to detect and count any dropped packets. `stroke_count` is sent in every packet but incremented only on qualifying strokes, so it is redundant with the stroke-rate ESPnow packets but available in the raw log for alignment.

**No application checksum is required.** ESP-NOW embeds a hardware CRC-32 in every 802.11 frame. Corrupted packets are discarded by the radio before reaching the receive callback — anything that arrives is already bit-validated. The sequence number detects losses; T-26 detects any struct packing error.

---

### 11.3 Data Rate Analysis

| Parameter | Value |
|-----------|-------|
| Packet rate | 100 Hz |
| Payload size | 92 bytes |
| Raw data rate | 9.2 KB/s |
| ESP-NOW min PHY rate | 1 Mbps (125 KB/s usable) |
| SD write rate | ~18 KB/s (CSV ~180 chars/row) |
| SD SPI clock | 4 MHz → 500 KB/s capacity |

The data rate is comfortably within ESP-NOW capacity. SD write throughput at 4 MHz SPI is ~27× the required rate. No rate limiting or backpressure is needed.

---

### 11.4 CYD Hardware — SD Card

The CYD micro SD slot is on the **VSPI** bus. The display is on **HSPI**. These are independent hardware SPI controllers on the ESP32 and can operate simultaneously without conflict.

#### 11.4.1 SD Card Pin Assignments (VSPI)

| GPIO | Function |
|------|----------|
| IO5  | SD_CS |
| IO18 | SD_SCK |
| IO23 | SD_MOSI |
| IO19 | SD_MISO |

#### 11.4.2 SPI Bus Allocation on CYD

| Bus | Peripheral | Pins |
|-----|-----------|------|
| HSPI | ILI9341 display | SCK=14, MOSI=13, MISO=12, CS=15 |
| VSPI | Micro SD card | SCK=18, MOSI=23, MISO=19, CS=5 |
| (separate) | XPT2046 touch | SCK=25, MOSI=32, MISO=39, CS=33 |

The touch controller (XPT2046) is on its own pins and is **not used** in Phase 7. No SPI conflicts exist between display and SD in this phase.

---

### 11.5 CSV Log Format

File auto-numbered `/ImuLog00.CSV` … `/ImuLog99.CSV` on the CYD SD card.

**Columns:**

| Column | Description |
|--------|-------------|
| `seq` | TX sequence number |
| `timestamp_ms` | TX millis() at sample time |
| `accel_x`, `accel_y`, `accel_z` | Acceleration, m/s² (5 decimal places) |
| `q_w`, `q_x`, `q_y`, `q_z` | Quaternion components (8 decimal places) |
| `roll`, `pitch`, `yaw` | Euler angles, degrees (5 decimal places) |
| `stroke_count` | Cumulative stroke count from TX |
| `d_roll`, `d_pitch`, `d_yaw` | Euler angles re-derived from received quaternion on RX |
| `roll_err`, `pitch_err`, `yaw_err` | \|received − re-derived\| (8 decimal places) |
| `az_err` | \|accel_z − 9.80665\| for test data; use as data-integrity column in production |

SD writes are batched (no flush per row). The log file is flushed every 5 s and on test completion.

---

### 11.6 Test Sketches

Two dedicated test sketches validate the link before any changes to production firmware.

#### 11.6.1 TX Test Sketch — `paddlestroke_espnow_tx_test/`

**Target:** LOLIN32 Lite (`esp32:esp32:lolin32-lite`), COM3.

Generates synthetic IMU data at 100 Hz — **no BNO085 hardware required**. Data follows a known formula so the receiver can verify integrity independently:

| Field | Formula | Verifiable property |
|-------|---------|-------------------|
| `angle` | `seq × 2π / 200` | One full rotation per 2 s |
| `accel_x` | `2.0 × sin(angle)` | Sinusoidal, amplitude 2 m/s² |
| `accel_y` | `2.0 × cos(angle)` | 90° phase-shifted from accel_x |
| `accel_z` | `9.80665` | **Constant** — easy cross-check |
| `q_w/x/y/z` | Pure Z-axis rotation at `angle` | Roll=0, pitch=0 always |
| `roll` | 0° | Exact for pure Z rotation |
| `pitch` | 0° | Exact for pure Z rotation |
| `yaw` | `angle` in degrees, wrapped to (−180, 180] | Predictable from seq |
| `stroke_count` | Increments every 100 packets | Simulates ~60 CPM |

Varied data (angle changes every packet) means any missing or reordered packet is immediately detectable from both the sequence gap and the value discontinuity.

The sketch retries ESPnow initialisation every 10 s if it fails at startup. It broadcasts unconditionally — no receiver needs to be present.

```bash
arduino-cli compile paddlestroke_espnow_tx_test/
arduino-cli upload -p COM3 paddlestroke_espnow_tx_test/
arduino-cli monitor -p COM3 -c baudrate=115200
```

Serial output: MAC address at startup, TX stats every 5 s (`seq`, `sent`, `fail`, `stroke_count`).

#### 11.6.2 RX Test Sketch — `paddlestroke_espnow_rx_sdlog/`

**Target:** CYD (`esp32:esp32:esp32`), COM7.

Receives ESPnow packets, logs to SD, and shows live stats on TFT. Runs a 60-second automated test (T-24–T-29) then prints PASS/FAIL to serial and updates the display.

The sketch uses a 32-entry ring buffer (FIFO, protected by a critical section) between the WiFi task (Core 0) and the main loop (Core 1). The display (HSPI) and SD card (VSPI) operate on independent SPI buses concurrently.

```bash
arduino-cli compile paddlestroke_espnow_rx_sdlog/
arduino-cli upload -p COM7 paddlestroke_espnow_rx_sdlog/
arduino-cli monitor -p COM6 -c baudrate=115200
```

Serial output: pass criteria at startup, stats every 5 s, full PASS/FAIL report at 60 s.

---

### 11.7 Post-Processing Verification (CSV)

After a test run, the CSV can be analysed in Excel or Python to verify formula accuracy:

| Column | Expected value |
|--------|---------------|
| `accel_x[i]` | `2 × sin(seq[i] × 2π / 200)` |
| `accel_y[i]` | `2 × cos(seq[i] × 2π / 200)` |
| `accel_z[i]` | 9.80665 (exactly) |
| `roll[i]` | 0° (exactly) |
| `pitch[i]` | 0° (exactly) |
| `yaw[i]` | `(seq[i] mod 200) × 1.8°` |
| `roll_err`, `pitch_err`, `yaw_err` | < 1 × 10⁻⁴ ° throughout |
| `stroke_count` | Monotonically non-decreasing, increments by exactly 1 |

Any row where `seq` jumps by more than 1 from the previous row indicates a lost packet. The gap in the formula values confirms which packet number was dropped.

---

### T-23 Data Rate — ESPnow Bandwidth

**Precondition:** Analysis only (no hardware needed).

**Verification:**
- Payload: 92 bytes × 100 Hz = 9.2 KB/s
- ESP-NOW minimum PHY rate: 1 Mbps = 125 KB/s usable throughput
- Margin: > 13×

**Pass:** Data rate is below 10% of minimum ESP-NOW throughput. No hardware throttling or buffering strategy is required.

**Result: PASS by analysis (6 May 2026)**

---

### T-24 Packet Loss Rate

**Setup:** TX test sketch running on LOLIN32 Lite; RX test sketch running on CYD with SD card inserted. Devices within normal operating range (< 5 m for lab test).

**Steps:**
1. Flash both sketches and power on TX first.
2. Power on RX and allow the 60-second test to complete.
3. Read the serial output from the RX.

**Pass:** Packet loss < 1 % over the 60-second window (~6 000 packets expected).

**Result: PASSED (6 May 2026)** — loss 0.27 % over 60 s.

---

### T-25 Maximum Inter-Packet Gap

**Setup:** As T-24.

**Steps:**
1. Run the 60-second test.
2. Read `MaxGap` from the serial PASS/FAIL report.

**Pass:** Maximum gap between consecutive received packets < 50 ms. (Normal gap at 100 Hz is ~10 ms; criterion allows up to 4 consecutive lost packets before failing.)

**Result: PASSED (6 May 2026)** — MaxGap 20 ms.

---

### T-26 Euler Re-Derivation Accuracy (Double Transmission Integrity)

**Setup:** As T-24.

**Steps:**
1. Run the 60-second test.
2. Read `EulerErr` from the serial PASS/FAIL report.

**Method:** The RX re-derives roll/pitch/yaw from the received quaternion using the same formula as the TX. If the doubles are transmitted correctly, the re-derived values must match the received Euler fields to within floating-point rounding error.

**Pass:** Maximum absolute error < 0.0001° across all received packets for all three Euler angles.

**Result: PASSED (6 May 2026)** — EulerErr 0.0000000° throughout. Bug found and fixed during testing: simple `fabs(d_yaw − pkt.yaw)` returned 360° at the ±180° yaw wrap boundary. Fixed with wrap-aware subtraction: `if (yErr > 180.0) yErr = 360.0 - yErr` in `paddlestroke_espnow_rx_sdlog.ino`.

---

### T-27 Known Constant Accuracy (accel_z Cross-Check)

**Setup:** As T-24.

**Steps:**
1. Run the 60-second test.
2. Read `AzErr` from the serial PASS/FAIL report.

**Method:** The TX always sends `accel_z = 9.80665`. The RX checks `|received accel_z − 9.80665|` for every packet.

**Pass:** Maximum error < 0.0001 m/s² across all received packets.

**Result: PASSED (6 May 2026)** — AzErr 0.0000000 throughout.

---

### T-28 SD Card Logging

**Setup:** As T-24, SD card inserted in CYD.

**Steps:**
1. Run the 60-second test.
2. Remove the SD card and inspect the file on a PC.
3. Check that `/ImuLog00.CSV` (or the next auto-numbered file) was created.
4. Verify the row count matches `totalReceived` reported by the RX serial output.
5. Check headers and data format.

**Pass:**
- File exists and is non-empty.
- Header row matches the specification (§11.5).
- Row count equals reported received packet count.
- No truncated rows.

**Result: PASSED (6 May 2026)** — ImuLog00.CSV and ImuLog01.CSV created; headers correct; all error columns 0.00000000 throughout; row counts consistent with reported received packet counts.

---

### T-29 No Ring Buffer Overflow

**Setup:** As T-24.

**Steps:**
1. Run the 60-second test.
2. Read `Overflow` from the serial PASS/FAIL report.

**Pass:** Overflow count = 0. (A non-zero value indicates that loop() fell behind the ESPnow callback — e.g., due to an SD or display operation blocking for too long.)

**Result: PASSED (6 May 2026)** — Overflow 0 throughout the 60 s automated window.

---

### T-30 Cold Start — RX Waits for TX (Manual)

**Steps:**
1. Flash both sketches but power on the **RX only**.
2. Observe the RX display and serial output for 30 seconds.
3. Power on the TX.
4. Observe the RX display and serial output.

**Pass:**
- While TX is absent: RX displays `Signal: ---`, serial shows no packet counts incrementing. No crash or hang.
- Within 5 seconds of TX power-on: RX begins receiving packets, `Signal: OK` appears, packet count starts incrementing. No manual intervention on either device.

**Result: PASSED (6 May 2026)**

---

### T-31 TX Restart Recovery (Manual)

**Setup:** Both devices running, RX showing `Signal: OK` and accumulating packets.

**Steps:**
1. Power off the TX while the RX is running.
2. Wait 10 seconds and confirm the RX shows `Signal: ---`.
3. Power the TX back on.
4. Observe the RX.

**Pass:**
- Within 3 seconds of TX power-off: RX shows `Signal: ---` (signal timeout).
- Within 5 seconds of TX restart: RX shows `Signal: OK` and resumes packet accumulation. No manual intervention required.

**Result: PASSED (6 May 2026)** — RX recovered automatically within one 5 s reporting interval after TX restart. Known limitation: `MaxGap` metric shows a spurious ~4.3×10⁹ ms value on TX restart due to `uint32_t` underflow when TX `millis()` resets to near zero. This does not affect normal operation and is a test-harness display artefact only. Up to 32 ring-buffer overflows may occur in the burst immediately after TX restart (one `fillScreen()` call can block loop() for >320 ms); this also does not affect normal operation.

> **Note:** ESP-NOW is connectionless broadcast — there is no handshake or pairing. T-30 and T-31 confirm that automatic recovery is a property of the protocol, not firmware logic.

---

## 12. Phase 8 — Production Integration

This section specifies the production firmware that replaces the Phase 7 test sketches. The paddle device SD card is removed; all IMU data is logged by the CYD display unit via the ESPnow link validated in Phase 7.

---

### 12.0 Test Protocol

**After every firmware change, the following minimum checks must be performed before committing:**

| Check | Method |
|-------|--------|
| ESPnow link active | PadDis shows CPM within 5 s of PadLog power-on |
| CPM displayed correctly | Paddle at steady rate — PadDis updates and stabilises |
| Doze entered after inactivity | Hold still for timeout period — `DOZE:` banner appears |
| Wake on paddle motion | Paddle briskly after doze — `WAKE:` banner and CPM resume |
| SD logging | CSV file created on PadDis SD card with correct headers and rows |

If any check fails, the change must be investigated and fixed before the version is incremented or the commit is pushed. The v8.2→v8.3 doze/wake regression (accelerometer not disabled on doze entry) was caught because the full test cycle was run after the v8.2 release.

---

### 12.1 Sketch Naming and Version Convention

| Sketch | Directory | File | Target | Port |
|--------|-----------|------|--------|------|
| **PadLog** | `PadLog/` | `PadLog.ino` | LOLIN32 Lite | COM3 |
| **PadDis** | `PadDis/` | `PadDis.ino` | CYD ESP32-2432S028 | COM6 |

**Version numbering:** `<phase>.<iteration>` — e.g., v8.1 is Phase 8, first iteration. The major number increments with each new development phase; the minor number increments for each firmware release within that phase.

Both sketches define:
```cpp
#define SKETCH_NAME    "PadLog"   // or "PadDis"
#define SKETCH_VERSION "8.6"
```

The version string appears in:
- Serial startup banner: `PadLog v8.6 — ready`
- CYD splash screen (PadDis only)
- First line of every CSV log file: `# PadDis v8.6`

---

### 12.2 PadLog — Changes from Phase 7

#### 12.2.1 ESPnow Payload

The 8-byte stroke-rate payload is replaced by a 60-byte full-IMU payload transmitted at every IMU sample (100 Hz). The payload carries CPM and Hz so the display has all information it needs without recomputing stroke rate.

```cpp
struct __attribute__((packed)) ImuDataPayload {
    uint32_t seq;           // monotonic counter
    uint32_t timestamp_ms;  // TX millis()
    float    accel_x, accel_y, accel_z;  // m/s², raw accelerometer (includes gravity)
    float    q_w, q_x, q_y, q_z;         // ARVR stabilised rotation vector
    float    roll, pitch, yaw;            // degrees, derived on TX
    uint32_t stroke_count;               // cumulative qualifying strokes
    uint32_t cpm;                        // current stroke rate CPM (0 if none)
    float    hz;                         // current stroke rate Hz (0.0 if none)
};
// sizeof == 60 bytes (static_assert enforced)
```

The `accel_x/y/z` fields come from the BNO085 `SH2_ACCELEROMETER` report (raw, includes gravity). Both `SH2_ARVR_STABILIZED_RV` and `SH2_ACCELEROMETER` are enabled at 100 Hz. Accelerometer samples are stored when received and included in the next rotation-vector packet.

The `cpm` and `hz` fields carry the most recently computed stroke rate (updated when `StrokeDetector` fires; unchanged between strokes). The `stroke_count` increments by 1 on each qualifying stroke.

#### 12.2.2 SD Card Removed

All SD card code, the HSPI bus, and SD pin definitions are removed from PadLog. The paddle device now requires only: BNO085 (VSPI), WiFi/ESPnow, and USB power.

#### 12.2.3 Startup USB Window

A 20-second delay before `WiFi.mode()` / `esp_now_init()` is inserted in `setup()`. During this window the CH340 USB chip is stable and the device can be reprogrammed. After 20 s, 100 Hz ESPnow begins and the USB port becomes inaccessible. The serial banner announces the window:

```
PadLog v8.1 — ready
Payload: 60 bytes  |  USB window: 20 s — upload firmware now if needed
```

#### 12.2.4 Doze Mode

Doze mode is unchanged in behaviour. On entering doze, ESPnow is inactive and the USB port becomes accessible again (WiFi radio off). On wake, both BNO085 reports and ESPnow are re-initialised.

#### 12.2.5 Doze/Wake Fix — Disable Accelerometer on Doze Entry (v8.3)

**Bug (present through v8.2):** `armDozeWakeup()` reduced the RV report rate to 2 Hz but did not disable the accelerometer. The accelerometer continued running at 100 Hz, keeping the BNO085 INT pin (GPIO4) asserted at 100 Hz. After each light-sleep wakeup, `getSensorEvent` returned the accelerometer packet (sensor ID 1) instead of the RV packet — the motion check always saw no RV data and set `dozeFirstRoll = NAN`, so the device never woke from paddle motion.

**Fix:**
- `armDozeWakeup()` now calls `bno.enableReport(SH2_ACCELEROMETER, 0)` before setting the RV report to 2 Hz, stopping accelerometer output for the duration of doze.
- The doze wake check loops through up to 20 queued events to find the RV packet, rather than reading only one event. This is defensive but harmless — with the accelerometer disabled only one event will be present.
- `exitDozeMode()` calls `enableNormalReports()` which re-enables both the RV and accelerometer reports at 100 Hz.

**Validated 14 May 2026:** full cycle confirmed — ESPnow active, CPM displayed correctly, doze entered after 3 minutes inactivity, device woke on paddle motion.

#### 12.2.6 Streak Gate (v8.2)

CPM and Hz are updated only after **3 consecutive qualifying strokes** (`g_strokeStreak >= 3`). Each qualifying stroke increments `g_strokeCount` immediately (so `stroke_count` in the payload reflects all detected strokes). The inactivity timer (`inactiveStartMs`) is also reset only after the 3-stroke threshold is met. This eliminates CPM spikes from device handling, transport, and isolated noise peaks seen in Phase 8 v8.1 field data.

The streak counter resets to zero when the stroke detector times out (3 s no qualifying cycles) and also when doze mode is exited.

#### 12.2.7 StrokeDetector — Separate Rate Buffers (v8.2)

The stroke rate averaging buffer is split into two independent 4-entry ring buffers: one for peak-to-peak intervals and one for trough-to-trough intervals. The reported rate is the average over all entries across both buffers (up to 8 values).

**Motivation:** A single shared buffer alternates peak intervals and trough intervals. If the left and right half-strokes differ in duration (asymmetric paddling), the alternating values produce erratic CPM output — each new qualifying event replaces an interval of the opposite type, causing the average to oscillate. Separate buffers ensure each buffer type converges independently.

**StrokeDetector API change:** The internal `_pushRate(float, bool isPeak)` method routes to the appropriate buffer. The public interface (`update`, `getRateHz`, `isTimedOut`, `reset`) is unchanged.

#### 12.2.8 Rate Maturity Gate — `isRateMature()` (v8.4)

CPM and Hz are reported only when **both** rate buffers contain at least **2 entries** (`isRateMature()` returns `true`), in addition to the streak gate (§12.2.6).

**Bug (present through v8.3):** `_computeAverage()` divides by `n` (the total count across both buffers) for any `n > 0`. After the third qualifying stroke, `n` may be as low as 2 (one peak interval + one trough interval). With only two data points the reported CPM is highly sensitive to timing jitter and can read 89–116 CPM at the start of a session or after a doze wake, when the true rate is ~54 CPM.

**Fix:** `PadLog.ino` adds a second guard to the CPM update condition:

```cpp
if (g_strokeStreak >= 3 && detector.isRateMature()) {
    g_hz  = detector.getRateHz();
    g_cpm = (uint32_t)roundf(g_hz * 60.0f);
    ...
}
```

`isRateMature()` returns `true` only when `_rateBufPeakCount >= 2 && _rateBufTroughCount >= 2` — i.e., at least 4 individual half-cycle intervals (two peak-to-peak, two trough-to-trough) have been accumulated. This ensures the rolling average has meaningful data before the first CPM is displayed.

**Field validation:** 59-min session 15 May 2026 showed 89–116 CPM spike in the first few strokes with v8.3. With v8.4 the start-of-session CPM is withheld until both buffers reach 2 entries, eliminating the spike.

---

#### 12.2.9 Amplitude Gate Raised to 90° (v8.6)

**Change:** `AMPLITUDE_GATE_DEG` in `PadLog/StrokeDetector.cpp` (and the sync copy in `paddlestroke_sim_test/StrokeDetector.cpp`) raised from 45° to 90°.

**Why this was necessary:** The v8.1–v8.4 gate of 45° was designed for an unfeathered paddle. Field analysis of the 18 May 2026 session (§3.4) revealed that the 60° feathered blades on this paddle require a wrist rotation before each blade entry. In the EMA high-pass filtered roll signal this rotation produces a 70–85° amplitude event — larger than the raw 60° wrist angle because the DC filter shifts the effective baseline. At 45° and even at 70°, these feather events pass the amplitude gate and also pass the period gate (530–670 ms sub-event period is within the 0.4–4.0 s range). The result is one spurious qualifying event per true stroke cycle, in a repeating T, P, feather-peak pattern, which inflated the displayed CPM by ~1.7×.

A gate of 90° cleanly separates feather events (70–85° filtered amplitude) from genuine strokes (~100°+ filtered amplitude) with ~10° margin on each side. This was confirmed by re-running the detection algorithm at five gate values (45°, 70°, 80°, 90°, 100°) against the recorded CSV — only 90° produced a P:T ratio near 1.0 and a T-T CPM matching the true paddling rate of ~32 CPM.

**Sim-test update:** ST-04 threshold changed from ±22.5° to ±40° (80° P-T, below the 90° gate); ST-05 changed from ±22.5° to ±46° (92° P-T, above the 90° gate with margin for the 3-sample MA ~1% attenuation at 1 Hz / 100 Hz sample rate). All 20 tests pass.

---

### 12.3 PadDis — Changes from Phase 7

#### 12.3.1 Payload and Ring Buffer

Receives the 60-byte `ImuDataPayload`. Ring buffer stores `ImuDataPayload` entries (32 slots = 320 ms at 100 Hz).

#### 12.3.2 SD Logging

Auto-numbered `/ImuLog00.CSV` … `/ImuLog99.CSV`. The first line is a version comment; the second is the column header:

**Full column set:**
```
# PadDis v8.6
seq,timestamp_ms,accel_x,accel_y,accel_z,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm,hz
```

**Reduced column set** (when `CSV_COLUMNS_REDUCED` is defined — see §12.3.6):
```
# PadDis v8.6
timestamp_ms,roll,pitch,yaw,stroke_count,cpm
```

Every received packet is written as one CSV row. The file is flushed every 5 s and on signal loss. SD absence is non-fatal.

#### 12.3.3 Display

The splash screen shows `PadDis v8.6` (Font 4) for 20 seconds. The main screen shows: large CPM number (Font 8), signal icon, and asymmetry bar (see §12.3.5). Colour scheme: black background, white active text, grey on signal loss. The CPM number is refreshed only when the displayed value changes — not on every 100 Hz packet — to avoid blocking the loop. The displayed value is a 20-second EMA of the raw CPM (see §12.3.7).

#### 12.3.4 Serial Output

CPM is logged to serial only when the value changes, avoiding 100 lines/second of output. Asymmetry is also logged when it changes:

```
CPM: 72  (1.20 Hz)  stroke=14  asymMs=0
Asym: +45 ms  (LEFT shorter)
Signal lost
```

#### 12.3.5 Asymmetry Bar

A horizontal bar displayed on the CYD below the signal icon visualises left/right stroke timing asymmetry in real time. The bar was introduced in v8.2 but the v8.4 algorithm was found to be unreliable in field data (see §3.4 and the v8.4 baseline subsection below). The v8.6 production algorithm is **Option 3 — consecutive-event comparison**. This section documents the v8.4 baseline (for historical reference), the three algorithms evaluated offline on 18 May 2026 field data, and the v8.6 production implementation.

**Layout (single bar — v8.4 current):**

```
┌─────────────────────────────────┐
│                            [●]  │  ← signal icon
│    ████████|                    │  ← asymmetry bar (red = left shorter)
│                                 │
│             72                  │  ← CPM number (Font 8)
│            CPM                  │
└─────────────────────────────────┘
```

**Bar specification:**

| Parameter | Value |
|-----------|-------|
| Width | 220 px |
| Height | 18 px |
| Full-deflection asymmetry | 500 ms |
| Centre tick | Grey line at bar midpoint |
| Outline | Grey rectangle (only when `asymValid`) |
| Background | Black (invisible against dark theme) when no data available |

**Colour convention:**

| Bar direction | Colour | Meaning |
|---------------|--------|---------|
| Extends left of centre | Red | Left stroke shorter |
| Extends right of centre | Green | Right stroke shorter |
| Not shown | (white) | Asymmetry not yet computed |

**Colour note (CYD hardware):** The ILI9341 display on this CYD unit uses **BGR** pixel order. To render red, the firmware sends `0x001F` (the RGB565 blue value); the BGR hardware interprets it as full red. Green (0x07E0) is symmetric and unaffected. TFT_WHITE (0xFFFF) is also symmetric.

---

**v8.4 rolling-midpoint algorithm (historical — replaced in v8.6):**

L/R classification used a self-calibrating rolling midpoint of roll values, replacing the earlier `pitch >= 0` classifier.

```cpp
// Executed on every received packet (100 Hz)
if (!isnan(asymPrevRoll)) {
    if (roll > asymPrevRoll) asymPeakRoll   = roll;
    else                     asymTroughRoll = roll;
}
asymPrevRoll = roll;
if (!isnan(asymPeakRoll) && !isnan(asymTroughRoll)) {
    float newMid = (asymPeakRoll + asymTroughRoll) * 0.5f;
    asymMidRoll  = isnan(asymMidRoll) ? newMid : (0.9f * asymMidRoll + 0.1f * newMid);
}
bool isRight = isnan(asymMidRoll) ? (roll >= 0.0f) : (roll > asymMidRoll);
```

**Known problems (from 18 May 2026 field analysis):**
- `asymMidRoll` is updated on every 100 Hz sample, so mid-stroke roll values dominate — the EMA never converges to the true neutral.
- Five ±180° roll wrap events at session start injected ±179° values, resetting `asymMidRoll` to near 0° within the first 2 minutes.
- Feather rotation artefacts (at 45° gate) create extra events that confound L/R classification regardless of the midpoint estimate.

All three issues are resolved by raising the amplitude gate to 90° (eliminates feather events) and switching to event-only updates.

---

**Three candidate asymmetry options (evaluated in Python on 18 May CSV at 90° gate):**

**Option 1 — Amplitude asymmetry:**
Compute a running EMA of prior-cycle midpoints as the neutral reference. Each cycle: `asymAmp = (peak − neutral) − (neutral − trough)`. Positive = peak side longer. Uses roll amplitude only, no timing.

- Result at 90° gate: mean ~0°, stdev 7° during steady paddling.
- Conclusion: amplitude is symmetric for this paddler. Asymmetry is in **timing**, not amplitude. Option 1 is useful as a diagnostic but cannot detect the asymmetry present in this data.

**Option 2 — Event-based midRoll EMA + timing:**
Update peak/trough estimates only at qualifying stroke events (not every sample). Compute midRoll = EMA((peakRoll + troughRoll) / 2), updated each cycle. L/R label = roll > midRoll at the event. Time the L and R half-periods; display the difference.

- Result at 90° gate: 94% agreement with Option 3 on L/R label; stdev ~155 ms per 20-cycle window.
- Advantage: self-calibrates to mounting offset; insensitive to 100 Hz noise.
- Disadvantage: EMA parameter (α = 0.1) introduces lag and must be tuned.

**Option 3 — Consecutive-event comparison + timing (preferred):**
Compare roll values of consecutive qualifying events. The higher-roll event is labelled the peak side (Right); the lower is the trough side (Left) — no midpoint or EMA parameter required. Time each L and R half-period; display the difference.

- Result at 90° gate: 35% less noisy than Option 2; parameter-free; 98% consistent cycle classification.
- Genuine asymmetry measured: P→T = 1494 ms, T→P = 401 ms (ratio 3.7:1); stdev 155–200 ms — stable for display.
- Preferred for Phase 9 production use.

**Physical interpretation of timing asymmetry:** The peak-to-trough descent (which includes the wrist rotation preparing the opposite blade) consistently takes ~1494 ms; the return trough-to-peak is consistently only ~401 ms. This is a real biomechanical feature of the feathered-paddle stroke, not measurement noise.

---

**Stroke timing logic (Options 2 and 3):**

- Track `timestamp_ms` of last Right event (`tLastR`) and last Left event (`tLastL`).
- On each new Right event: if R→L→R sequence complete, compute `r2l = tLastL − tLastR`, `l2r = ts − tLastL`, `asymMs = r2l − l2r`. Positive = left interval shorter.
- On each new Left event: mirror (L→R→L sequence, same sign convention).
- Both half-intervals must be in range 150 ms – 4000 ms; discard otherwise.
- `asymValid` reset to `false` on signal loss (all state variables reset to NAN).

**Redraw discipline:** `drawRate()` wipes the display area and calls `drawAsymmetryBar()`. When asymmetry changes between CPM updates, `drawAsymmetryBar()` is called independently.

---

---

**v8.6 production algorithm — Option 3 (consecutive-event comparison + timing):**

Option 3 was selected for production based on offline analysis of 18 May 2026 field data at the 90° gate: 35% lower noise than Option 2, parameter-free, 98% consistent cycle classification. The three-bar evaluation display was not required.

```cpp
// On each new qualifying stroke event (pkt.stroke_count change):
// Higher roll than the previous event = peak side (right); lower = trough side (left).
// No midpoint, no EMA — just a comparison of two consecutive roll values.
if (!isnan(prevEventRoll)) {
    bool isRight = (roll > prevEventRoll);
    if (isRight) {
        if (tLastL > tLastR && tLastR > 0) {
            int32_t r2l = (int32_t)(tLastL - tLastR);
            int32_t l2r = (int32_t)(ts     - tLastL);
            if (r2l > 150 && r2l < 4000 && l2r > 150 && l2r < 4000) {
                asymMs    = r2l - l2r;  // +ve = left shorter = RED
                asymValid = true;
            }
        }
        tLastR = ts;
    } else {
        if (tLastR > tLastL && tLastL > 0) {
            int32_t l2r = (int32_t)(tLastR - tLastL);
            int32_t r2l = (int32_t)(ts     - tLastR);
            if (l2r > 150 && l2r < 4000 && r2l > 150 && r2l < 4000) {
                asymMs    = r2l - l2r;
                asymValid = true;
            }
        }
        tLastL = ts;
    }
}
prevEventRoll = roll;
```

State variables: `prevEventRoll`, `tLastR`, `tLastL`, `asymMs`, `asymValid`. All reset to NAN/0/false on signal loss. This replaces four state variables (`asymPrevRoll`, `asymPeakRoll`, `asymTroughRoll`, `asymMidRoll`) from v8.4 with a single `prevEventRoll`.

---

#### 12.3.6 CSV Column Selector (v8.5)

A compiler directive in `PadDis.ino` selects which columns are written to each CSV row:

```cpp
#define CSV_COLUMNS_REDUCED   // comment out for full columns
```

**Reduced column set** (defined by default — for field use):
`timestamp_ms, roll, pitch, yaw, stroke_count, cpm`
~50 characters/row, ~72% smaller than the full set.

**Full column set** (comment out `CSV_COLUMNS_REDUCED`):
All fields in `ImuDataPayload`: `seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, hz`

`stroke_count` is included in the reduced set because it identifies which samples are qualifying stroke events, enabling offline asymmetry algorithm evaluation in Python. `cpm` is included in raw (un-EMAd) form for the same reason.

#### 12.3.7 CPM Display EMA (v8.5)

A 20-second exponential moving average is applied to the **displayed** CPM value on PadDis. The raw CPM value received from PadLog is stored in the CSV unchanged.

```
alpha = 1 − exp(−(1/100) / 20) ≈ 0.0005   // at 100 Hz sample rate
displayCpm = alpha × rawCpm + (1 − alpha) × displayCpm
```

- On first valid CPM received after signal return (or session start), pre-seed `displayCpm` to `rawCpm` immediately — no ramp-up delay.
- When `rawCpm == 0` (PadLog inactivity timeout), reset `displayCpm` to 0 immediately — no gradual decay.
- The display refreshes only when the rounded integer value of `displayCpm` changes, to avoid unnecessary redraws.

**Motivation:** 18 May 2026 field data showed stdev of 16.8 CPM at a true rate of ~32 CPM (~52% relative noise). A 20-second EMA reduces visible fluctuation to ~2–3 CPM stdev while still tracking genuine rate changes within a few seconds.

---

### 12.4 Build and Flash

```bash
# PadLog
arduino-cli compile PadLog/
arduino-cli upload -p COM3 PadLog/

# PadDis
arduino-cli compile PadDis/
arduino-cli upload -p COM6 PadDis/
```

---

### T-32 Streak Gate — CPM Not Reported on First Two Strokes

**Steps:**
1. Start PadLog with the paddle completely still (CYCLE_RATE: 0 CPM visible on PadDis).
2. Perform exactly **two** qualifying strokes (≥45°, valid period), then stop.
3. Observe the PadDis display and PadLog serial output.

**Pass:**
- The CPM display on PadDis does **not** update after the first or second stroke.
- PadDis serial shows no `CPM:` line after fewer than 3 strokes.
- CYCLE_RATE: 0 CPM line was emitted by PadLog when it timed out, and PadDis continues to show 0 or the previous value.

---

### T-33 Streak Gate — CPM Updates After Third Stroke

**Steps:**
1. From rest, perform three consecutive qualifying strokes at approximately 1 Hz.
2. Observe PadDis display and PadLog serial after each stroke.

**Pass:**
- After the third stroke: a non-zero CPM value appears on PadDis and `CPM:` is printed on serial.
- The value is within ±10 CPM of the actual stroke rate.

---

### T-34 Asymmetry Bar — No Bar Before First Measurement

**Steps:**
1. Power on both units.
2. Observe PadDis after the splash screen, before any paddle motion.

**Pass:** The asymmetry bar area is white (invisible) — no coloured fill, no outline. Only the CPM number and signal icon are visible.

---

### T-35 Asymmetry Bar — Red on Left Shorter

**Steps:**
1. Paddle for at least 3 cycles to establish asymmetry data.
2. Deliberately shorten the left paddle stroke (faster left entry, slower right).
3. Observe PadDis asymmetry bar.

**Pass:** The bar shows a **red fill extending left of centre**, proportional in length to the asymmetry. Grey outline and centre tick are visible.

---

### T-36 Asymmetry Bar — Green on Right Shorter

**Steps:**
1. As T-35, but deliberately shorten the **right** stroke.

**Pass:** The bar shows a **green fill extending right of centre**.

---

### T-37 Asymmetry Bar — Resets on Signal Loss

**Steps:**
1. With asymmetry bar showing, power off PadLog.
2. Wait 5 seconds for PadDis to detect signal loss.
3. Observe the asymmetry bar.

**Pass:** The bar area returns to white (invisible) when signal is lost. It does not reappear until PadLog is restored and a valid asymmetry measurement is computed.

---

## 13. Phase 9 — Blade Entry/Exit Detection

*Status: pending — design not started.*

Phase 9 adds stroke quality metrics by detecting the moment the blade enters the water (catch) and exits the water (release) independently of the roll oscillation cycle already used for CPM. These events are not cleanly visible in the roll signal but should be detectable as transients in `accel_x` and `accel_y` (lateral and forward accelerometer channels), which are already included in the ESPnow payload and logged to the SD card.

---

### 13.1 Motivation

The Phase 8 stroke detection confirms that a cycle occurred and measures its rate. It does not distinguish between an efficient catch (blade enters at low angle, pulls cleanly) and an inefficient one (blade slaps the water, or enters late). Blade entry and exit events produce distinct accelerometer transients; characterising these enables coaching feedback beyond CPM.

---

### 13.2 Data Available

All required data is already captured in the Phase 8 CSV (even in the reduced column set, `accel_x`, `accel_y`, and `accel_z` are available alongside `roll` and `stroke_count`). No hardware or firmware changes are needed to capture data for offline analysis.

---

### 13.3 Approach (to be designed)

Candidate approach: detect the onset and cessation of lateral acceleration transients time-locked to the roll zero-crossing (mid-stroke) in each qualifying cycle. The `stroke_count` transitions in the CSV provide exact event timestamps to align against.

Design, offline validation, and firmware specification are deferred to a future session.
