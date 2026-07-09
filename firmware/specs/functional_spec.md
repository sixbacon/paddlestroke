# Kayak Paddle Stroke Rate Monitor — Functional Specification

**Project:** paddlestroke  
**Date:** 2026-07-09  
**Version:** 2.9  (Phase 10 RELEASED — commit d8ce219 bumps PadLog v8.7→v8.8, BoatLog v1.0→v1.1, PadDis v8.10→v8.11 as a coordinated set. Bench-verified: banners + payload sizes + MAG_CAL emission on both TX units + new SD file naming (`/PadLog##.CSV`). Outstanding hardware tests documented in §15.7.)  
**Version:** 2.8  (§15 extended — Phase 10 now also bundles boat accelerometer forwarding: `BoatDataPayload` gains three `float` accel fields, boat CSV gains `boat_accel_x/y/z` columns, test T-46 added. Same coordinated release: PadLog v8.8 / BoatLog v1.1 / PadDis v8.11.)  
**Version:** 2.7  (§15 added — Phase 10 magnetometer calibration support: mag report enable, on-change serial status, DCD save on first convergence, `mag_cal` CSV column on paddle + boat, Phase 10 test plan T-40 to T-45, release-coupling requirement PadLog v8.8 / BoatLog v1.1 / PadDis v8.11.)

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

### 3.5 Field Test Observations (Phase 8 v8.6, 20 May 2026)

File: `ImuLog0520260520.CSV`. 222,164 rows, 37.8 min, 97.9 Hz, 71% active.

**Stroke detection — 90° gate confirmed working:**
- P:T event ratio = **1.02** (was 0.61 at 45° gate on 18 May). Feather rotation artefacts are essentially eliminated.
- True full-cycle CPM from P-P / T-T intervals: mean **33.3**, stdev **4.7**.
- Displayed CPM (20 s EMA): mean 35.5, stdev 9.5.

**Roll waveform symmetry:**
Roll amplitude is symmetric: peak excursion above the roll mean = 44.1° ± 39.0°; trough excursion below mean = 45.0° ± 31.0°. Difference = **0.9°** — negligible. The asymmetry is entirely in timing, not amplitude.

**Timing asymmetry — structural, not left/right:**

| Half-interval | Mean | Stdev |
|---------------|------|-------|
| Peak → Trough | 1414 ms | 358 ms |
| Trough → Peak | 510 ms | 443 ms |
| Ratio | 2.77:1 | |

This is a biomechanical feature of the feathered paddle: the down-phase (which includes wrist rotation preparing the opposite blade) is consistently slow; the recovery phase is fast. This structural asymmetry causes the v8.6 Option 3 asymmetry bar to always deflect in the same direction regardless of paddling technique. **Conclusion: timing-based asymmetry measurement on roll alone is not informative for this paddle. The asymmetry bar and all related state variables are to be removed in the next firmware version.**

**Pitch as a L/R classifier:**

| Event type | Mean pitch | IQR |
|------------|------------|-----|
| Peak events (roll at maximum) | −26.4° ± 12.8° | [−36.1°, −20.9°] |
| Trough events (roll at minimum) | +11.9° ± 10.7° | [+13.3°, +15.5°] |

IQR overlap = 0° — the two distributions are completely non-overlapping. Using `pitch < 0` as a threshold gives **92% classification accuracy** (95% peaks, 90% troughs) with no calibration required.

Physical explanation: when a blade is being pulled through the water, the paddle shaft is tilted forward (negative pitch); when the opposite blade is entering, the shaft is tilted back (positive pitch). This is a reliable, parameter-free signal.

Pitch cannot separate the structural timing asymmetry from genuine L/R paddling imbalance, but it is the correct starting point for any future L/R classification requirement (e.g., Phase 9 blade-entry detection).

---

### 3.6 Field Test Observations (Phase 8 v8.7, 21 May 2026)

File: `ImuLog0420260521.CSV`. 155,930 rows, 27.8 min, 93.4 Hz mean (two large gaps reduce average — see below), 75% active.

**Stroke detection:**
- Total strokes: **1,336**. Active time: 19.6 min.
- Main CPM cluster: **30–39 CPM** (mean 36.2, median 35, SD 9.6 raw from log).
- Slightly higher pace than 20 May (33.3 CPM mean) — shorter but harder session.

**Spurious high-CPM rows:**
2,288 rows (1.5%) show CPM > 60 (range 70–129). These are confined to two windows:
- **Startup** (sc = 5–18, first 18 strokes, ~ts 198–430 s): paddle being picked up and initial strokes before pace settled.
- **End-of-session** (sc = 1333–1336, ~ts 1390–1432 s): paddle being put down.

No spurious high-CPM values were observed during the sustained paddling phase. The 90° gate continues to perform correctly in-session.

**Session gaps:**

| Gap | Timestamp | Explanation |
|-----|-----------|-------------|
| 19,768 ms | ts = 86 s, row 30 | PadLog 20 s startup pause — matches `STARTUP_PAUSE_MS` exactly |
| 84,409 ms | ts = 26.9 min, end | Paddle laid down; session over |

**Pitch L/R classifier — confirmed, distributions shifted vs 20 May:**

| Event type | 20 May mean / IQR | 21 May mean / IQR |
|---|---|---|
| Peak (pitch < 0) | −26.4° / [−34°, −19°] | −25.2° / [−38°, −13°] |
| Trough (pitch ≥ 0) | +11.9° / [+7°, +16°] | +26.1° / [+14°, +38°] |
| IQR overlap | none | none |

Zero IQR overlap confirmed — the `pitch < 0` classifier remains valid. However, the **trough distribution has shifted substantially** (+11.9° → +26.1°) and both distributions are wider (IQR ≈ 25° vs ≈ 9° on 20 May). The most likely cause is a slightly different IMU seating angle in the shaft clamp between sessions; a smaller contribution from different forward lean or water conditions.

**Phase 9 implication:** The inter-session shift in the trough pitch mean (+14°) means a fixed classifier threshold cannot be assumed. Any Phase 9 L/R classification will require per-session calibration (e.g., from the first N strokes) rather than a hard-coded `pitch < 0` cut.

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

**Diagnostic override (`DOZE_DISABLED`):** When `#define DOZE_DISABLED` is active in `PadLog.ino`, both the doze entry check and the doze loop are compiled out. The device logs continuously regardless of inactivity. Comment out the define to restore normal doze behaviour. The onboard LED (GPIO 22, active LOW) flashes 50 ms every 2 s as a heartbeat indicator whenever the sketch is running.

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
| **8** | Production integration — full-IMU ESPnow payload in PadLog; SD logging in PadDis; SD card removed from paddle device. Sketches renamed PadLog / PadDis with version scheme phase.iteration. v8.1: hardware validated 12 May 2026 (63 min session, 100 Hz, <0.03% loss, 51–76 CPM). v8.2: streak gate, separate rate buffers, asymmetry bar. v8.3: doze/wake bug fixed — accelerometer left active in doze mode was consuming all wakeup events, blocking RV data; fix disables accelerometer on doze entry. Full cycle validated 14 May 2026. v8.4: `isRateMature()` gate prevents post-wake CPM spike; rolling-midpoint asymmetry replaces `pitch >= 0` classifier. Field test 18 May 2026 revealed feather rotation artefacts inflating CPM 1.7× at 45° gate. v8.5 (PadDis only): CSV column selector (`CSV_COLUMNS_REDUCED`) reduces SD write volume 72%; 20-second EMA on displayed CPM (raw CSV unchanged). v8.6: `AMPLITUDE_GATE_DEG` raised 45°→90° (PadLog + sim_test) — rejects feather rotation events; Option 3 consecutive-event asymmetry replaces v8.4 rolling-midpoint EMA; dark display theme (black background, white text). v8.7 (PadDis only): asymmetry bar and all related state removed (timing asymmetry is structural — see §3.5); CPM display EMA 20 s→10 s; yellow NO SD CARD warning on splash screen. *(Complete — v8.7 flashed and validated 20 May 2026)* v8.8 (PadDis only): `CSV_COLUMNS_REDUCED` commented out — full 15-column set default for PadViz4 data collection. v8.9 (PadDis only): boat unit ESPnow integration (BoatLog v1.0); CPM 1 dp display; speed in knots; GPS time stamped into paddle CSV; display rewritten to three-line layout (Font 4 throughout — time+dots line 1, speed line 2 size 2 centred, CPM line 3 size 2 centred). *(Complete — v8.9 flashed 30 Jun 2026; BoatLog T1+T2 PASS 30 Jun 2026)* v8.7 diagnostic (PadLog only, 2 Jul 2026): `#define DOZE_DISABLED` added — bypasses doze entry and doze loop so PadLog logs continuously; onboard LED (GPIO 22, active LOW) flashes 50 ms every 2 s as a heartbeat. Comment out `DOZE_DISABLED` to restore normal doze behaviour. |
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

#### 10.1.3 ST7789 Driver Investigation (20 May 2026)

The official witnessmenow CYD2USB reference `User_Setup.h` specifies `ST7789_DRIVER`, not `ILI9341_DRIVER`. A dedicated test sketch (`cyd_st7789_test/`) was flashed to confirm behaviour. Results:

| Property | ILI9341 (current) | ST7789 |
|----------|-------------------|--------|
| Full 320×240 coverage | yes (with 4-rotation clear workaround) | yes |
| Landscape rotation | `setRotation(2)` | `setRotation(1)` |
| After `tft.init()` | nothing | `tft.invertDisplay(false)` |
| BGR colour order | yes — `0x001F` = red | identical |
| `TFT_GREEN` | correct | correct |

**ST7789 init sends INVON by default.** Calling `tft.invertDisplay(true)` is a no-op (already on). `tft.invertDisplay(false)` cancels it and restores correct colour polarity.

**BGR behaviour is identical to ILI9341.** All existing colour workarounds (`BAR_RED = 0x001F`, etc.) carry over unchanged.

**Decision:** PadDis remains on `ILI9341_DRIVER` for the current firmware — it is validated and the colour workarounds are unchanged. Switch to `ST7789_DRIVER` in the next rewrite (change driver define, add `invertDisplay(false)`, change rotation 2→1). One open question: whether ST7789 eliminates the four-rotation startup `fillScreen` noise-pixel workaround — not yet tested without it.

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

Both sketches define `SKETCH_VERSION`. Versions are not required to stay in sync when only one sketch changes.

```cpp
// PadLog (current):
#define SKETCH_VERSION "8.7"
// PadDis (current):
#define SKETCH_VERSION "8.8"
```

The version string appears in:
- Serial startup banner: `PadLog v8.7 — ready`
- CYD splash screen (PadDis only): `PadDis v8.8`
- First line of every CSV log file: `# PadDis v8.8`

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

**Full column set** (v8.10 default — directive commented out; `hz` removed in v8.9, `gps_utc_sec` + `gps_uk_offset` added in v8.9, `rx_ms` added in v8.10):
```
# PadDis v8.10
seq,timestamp_ms,accel_x,accel_y,accel_z,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm,gps_utc_sec,gps_uk_offset,rx_ms
```

**Reduced column set** (when `CSV_COLUMNS_REDUCED` is defined — see §12.3.6):
```
# PadDis v8.10
timestamp_ms,roll,pitch,yaw,stroke_count,cpm,gps_utc_sec,gps_uk_offset,rx_ms
```

`rx_ms` is CYD `millis()` captured **inside the ESPnow receive callback** — same clock domain as the boat log's `rx_ms`, so post-processing sync is a nearest-`rx_ms` match (< 10 ms typical accuracy, dominated by send-side jitter). See §14.1.8.

`cpm` is the raw un-EMAd value. `gps_utc_sec` and `gps_uk_offset` are 0 when no GPS fix is active. Every received packet is written as one CSV row. The file is flushed every 5 s and on signal loss. SD absence is non-fatal.

#### 12.3.3 Display

The splash screen shows `PadDis v8.7` (Font 4) for 20 seconds. If the SD card is absent or fails to open, a yellow warning `NO SD CARD — logging disabled` is displayed below the version text in Font 2 for the duration of the splash. The main screen shows: large CPM number (Font 8) centred on screen, signal icon top-right. Colour scheme: black background, white active text, grey on signal loss. The CPM number is refreshed only when the smoothed integer value changes — not on every 100 Hz packet — to avoid blocking the loop. The displayed value is a 10-second EMA of the raw CPM (see §12.3.7).

#### 12.3.4 Serial Output

CPM is logged to serial only when the value changes, avoiding 100 lines/second of output:

```
CPM: 72 (raw 71)  (1.20 Hz)  stroke=14
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

**Removed in v8.7:** Field analysis of 20 May 2026 data (§3.5) confirmed that the timing asymmetry measured by Option 3 is a structural biomechanical feature of the feathered paddle (P→T = 1414 ms, T→P = 510 ms, ratio 2.77:1), not a left/right paddling imbalance. The bar deflected in the same direction every session. All asymmetry state variables (`prevEventRoll`, `tLastR`, `tLastL`, `asymMs`, `asymValid`) and `drawAsymmetryBar()` were removed in v8.7. The CPM number is now centred on the full usable screen area.

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

**v8.7 update:** Time constant changed from 20 s to **10 s** (`alpha = 0.001` at 100 Hz). 20 May 2026 data showed true stdev 4.7 CPM and displayed stdev 9.5 CPM at 20 s; 10 s halves the display lag while still smoothing the raw signal significantly.

**v8.8 update (PadDis only):** `CSV_COLUMNS_REDUCED` commented out — full 15-column set is now the default. Re-enable the directive to revert to the compact fieldset for general field use. Change made to capture accel_x/y/z and q_w/q_x/q_y/q_z data required by PadViz4 position tracking (double-integration of IMU accelerometer).

---

### 12.4 Build and Flash

```bash
# PadLog
arduino-cli compile firmware/production/PadLog/
arduino-cli upload -p COM3 firmware/production/PadLog/

# PadDis
arduino-cli compile firmware/production/PadDis/
arduino-cli upload -p COM6 firmware/production/PadDis/
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

### T-38 Left-Handed Paddle — Stroke Detection

*Status: PENDING — requires recorded session data.*

**Background:** The current system has been validated only with a right-handed paddle (60° feather, right-wrist control). A left-handed paddle uses the same feather angle but with left-wrist control; the shaft rotation direction during feathering may be reversed relative to the right-handed case. Since the IMU is mounted at the shaft centre, the peak/trough roll sequence seen during a left-handed stroke may be inverted. The amplitude gate (±90°) and rate gate (0.25–2.5 Hz) are symmetric and should be unaffected, but the L/R blade classification (§13.4, `pitch < 0`) and asymmetry bar direction should be verified.

**Pre-condition:** Record a full paddling session using a left-handed paddle with PadDis logging to SD card (full or reduced column CSV).

**Steps:**
1. Load session CSV into PadViz3 or PadViz4. Confirm roll signal amplitude and shape matches right-handed session (≥ 90° peak-to-trough, consistent cadence).
2. Check CPM reported on PadDis during the session was stable and plausible.
3. Apply the pitch classifier (`pitch < 0` → right blade): verify L/R labels are correct or systematically inverted (inverted = expected for left-handed paddle).
4. Confirm asymmetry bar direction corresponds to actual left/right stroke lengths.

**Pass:** CPM is detected and stable; roll amplitude ≥ 90°. Pitch classifier L/R labels are either correct or consistently inverted (inverted is acceptable — documents the required sign-flip for left-handed mode).

---

### T-39 Variable Feather Angle — Amplitude Gate Sensitivity

*Status: PENDING — requires recorded session data at each feather setting.*

**Background:** The amplitude gate (90°) was set for a 60° feathered paddle. At lower feather angles the roll amplitude seen by the IMU decreases, potentially falling below the gate. At 0° feather (parallel blades) no roll rotation occurs during feathering and the gate will reject all strokes. At 90° feather the roll amplitude increases and the gate margin widens. These tests document the usable range of feather angles for the current gate setting.

**Pre-condition:** Record sessions at each target feather angle. Note the feather angle in the CSV filename or a comment line.

**Feather angles to test:** 0°, 30°, 45°, 60° (baseline), 90°.

**Steps (for each angle):**
1. Load session CSV into PadViz3. Observe the roll signal peak-to-trough amplitude.
2. Record: min, max, and median amplitude across all detected cycles.
3. Note whether PadDis reported CPM continuously, intermittently, or not at all.

**Pass criteria per angle:**

| Feather | Expected roll amplitude | Expected outcome |
|---|---|---|
| 0° | ~0° | No CPM output (all cycles rejected by gate) |
| 30° | ~30–50° | No CPM output (below 90° gate) |
| 45° | ~45–70° | No CPM output (below 90° gate) |
| 60° | ~90–120° | CPM output continuous (baseline confirmed) |
| 90° | ~130–160° | CPM output continuous; amplitude headroom confirmed |

If 45° sessions show intermittent CPM, the amplitude gate value (currently 90°) should be reconsidered in Phase 9.

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

---

### 13.4 L/R Blade Classification — Pitch Signal (20 May 2026)

Analysis of 20 May 2026 field data (§3.5) identified pitch as a reliable, parameter-free L/R classifier:

- At peak roll events (one blade side in water): pitch mean = −26.4°, IQR [−36.1°, −20.9°]
- At trough roll events (other blade side in water): pitch mean = +11.9°, IQR [+13.3°, +15.5°]
- IQR overlap = 0°; `pitch < 0` threshold gives 92% accuracy with no calibration.

**How to apply in Phase 9:** Use `pitch < 0` at each `stroke_count` event to determine which blade side just completed its pull. This label can be used to time-align accelerometer transients per blade side for catch/release detection.

---

## 14. Future Hardware Extensions

*Status: §14.1 BoatLog v1.0 firmware written and compiled (19 Jun 2026). PadDis v8.9 integrates boat unit. Field testing pending.*

---

### 14.1 Boat Unit — ESP32 Lite + BNO085 + NEO-6M GPS

**Decision (11 Jun 2026):** Adding GPS and a second IMU directly to the CYD display unit
is not feasible — the CYD-2432S028 has insufficient accessible GPIO once the display
(HSPI) and SD card (VSPI) SPI buses are allocated. A third dedicated unit fixed to the
kayak hull is the chosen architecture.

#### 14.1.1 Hardware

| Component | Interface | Notes |
|-----------|-----------|-------|
| WEMOS LOLIN32 Lite (ESP32) | — | Same MCU as PadLog; known-good platform |
| BNO085 IMU | SPI | Kayak body-frame orientation; no SPI conflict (GPS uses UART) |
| u-blox NEO-6M GPS | UART | NMEA sentences; configure to 5 Hz for better track resolution |

The boat unit is powered independently (small LiPo) and fixed to the cockpit rim or
deck. It transmits continuously to the CYD via ESPnow — no USB connection required
during operation.

#### 14.1.2 What it adds

**From the BNO085 (kayak IMU):**

| Measurement | How obtained | Value |
|-------------|--------------|-------|
| Paddle orientation relative to kayak | `q_paddle × q_kayak⁻¹` | True catch and exit angles in the boat frame — the quantities a coach cares about |
| Kayak yaw rate during stroke | kayak IMU | Well-executed stroke minimises yaw; excess yaw indicates unbalanced push-pull |
| Kayak lean (roll) | kayak IMU | Edge control; independent of paddle |
| Kayak pitch | kayak IMU | Fore/aft trim; changes with load and conditions |

Without the kayak IMU, all paddle orientation data is expressed in the absolute world
frame, which is a less meaningful reference for technique analysis — a catch angle of 20°
in world frame changes meaning as the kayak turns. The relative frame is physically
invariant to heading.

Yaw drift in the relative quaternion `q_paddle × q_kayak⁻¹` is substantially reduced
because both BNO085s share the same fusion algorithm and correlated environmental
conditions — heading errors cancel in the difference.

**From the NEO-6M GPS:**

| Data | Rate | Value |
|------|------|-------|
| Ground speed | 1–5 Hz | Metres per stroke at a given CPM — the primary efficiency metric; not obtainable from IMU alone |
| Course over ground (COG) | 1–5 Hz | Drift-free absolute heading; slow correction for BNO085 yaw drift in both units |
| Position (lat/lon) | 1–5 Hz | Session track; paddling trajectory |
| UTC time | 1 Hz | Absolute timestamp — aligns the paddle log and boat log in post-processing |

GPS COG provides a drift-free yaw reference updated at 1–5 Hz. It can be fused as a
very slow correction (time constant 30–60 s) to prevent long-session heading accumulation
in both IMUs. This directly improves the paddle-centre position estimate in PadViz4 (§14.3).

#### 14.1.3 ESPnow architecture

The CYD already receives one ESPnow stream (from PadLog, the paddle unit). It will
receive a second stream from the boat unit. The ESPnow receive callback demuxes by
packet size: 60 bytes → paddle ring buffer, 58 bytes → boat ring buffer.

**Boat unit ESPnow packet (58 bytes packed — `static_assert` enforced):**
```
seq            uint32    monotonic counter
timestamp_ms   uint32    millis() on boat unit
gps_utc_sec    uint32    UTC seconds since midnight (0 if no fix)
gps_lat        float     degrees
gps_lon        float     degrees
gps_speed_ms   float     m/s (speed over ground)
gps_cog_deg    float     degrees (course over ground)
gps_fix        uint8     0=none, 1=valid fix
gps_uk_offset  uint8     0=GMT, 1=BST (computed from GPS date by BoatLog)
kayak_qw       float
kayak_qx       float
kayak_qy       float
kayak_qz       float
kayak_roll     float     degrees
kayak_pitch    float     degrees
kayak_yaw      float     degrees
```
Total: 58 bytes — well within the 250-byte ESPnow limit.

#### 14.1.4 CYD workload assessment

The CYD (ESP32 dual-core 240 MHz) has ample capacity for the additional stream:

| Load | Current | With boat unit |
|------|---------|----------------|
| ESPnow callbacks/s | ~100 | ~200 (+ boat unit at 100 Hz BNO085) |
| SD write bandwidth | ~15 KB/s (15-col at 100 Hz) | ~25–30 KB/s (two CSV files) |
| Display | unchanged | unchanged |

SD card minimum throughput is ~1 MB/s; 30 KB/s is 3% of capacity. CPU overhead of 200
ESPnow callbacks/s at ~10 µs each = 0.2% of one core. No bottleneck in any resource.

Two separate CSV files on the SD card (paddle log and boat log) are recommended over one
interleaved file. The `gps_utc_sec` field in the boat unit packet provides an absolute
time reference to align both logs in post-processing — no real-time clock synchronisation
between the ESP32 units is needed.

#### 14.1.5 NEO-6M configuration

Default baud rate is 9600; reconfigure to 115200 in firmware. Default update rate is 1 Hz;
configure to 5 Hz by disabling unused NMEA sentences (GGA + RMC sufficient). At kayaking
speed (4–5 km/h), 5 Hz gives a position fix every ~0.25 m — adequate for stroke-level
track resolution.

#### 14.1.6 Logging

Two new CSV files written by PadDis to the SD card:

**Paddle log** (17 col — v8.9 dropped `hz` and added GPS time; v8.10 appends `rx_ms`):
`seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, gps_utc_sec, gps_uk_offset, rx_ms`

`gps_utc_sec` and `gps_uk_offset` are stamped from the most recent valid BoatLog packet; both are 0 when no GPS fix is active. This embeds an absolute time reference directly in the paddle log without requiring post-processing alignment. `rx_ms` is the CYD-side reception timestamp — see §14.1.8.

**Boat log** (v8.10 — 17 col with `rx_ms`):
`seq, timestamp_ms, gps_utc_sec, gps_uk_offset, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix, kayak_qw, kayak_qx, kayak_qy, kayak_qz, kayak_roll, kayak_pitch, kayak_yaw, rx_ms`

#### 14.1.7 PadDis v8.9 — Boat Unit Integration

**Wiring (BoatLog — WEMOS LOLIN32 Lite):**

| Signal | GPIO |
|--------|------|
| BNO085 CS | 5 |
| BNO085 INT | 4 |
| BNO085 RST | 16 |
| BNO085 SCK | 18 |
| BNO085 MISO | 19 |
| BNO085 MOSI | 23 |
| GPS UART RX (← GPS TX) | 14 |
| GPS UART TX (→ GPS RX) | 13 |

GPS baud: 9600 (NEO-6M default). Library: TinyGPS++.

**BoatLog serial test output:**
```
BoatLog v1.0 — ready
[TEST 1] BNO085: PASS
[TEST 2] GPS UART started — waiting for NMEA data...
[TEST 2] GPS: PASS                         // on first parsed NMEA sentence
GPS fix: 14:32:01 UK  lat=51.123456 lon=-1.234567  3.42 kn  COG=270.0°  // every 5 s when fix
```

**Build commands:**
```bash
arduino-cli compile firmware/production/BoatLog/
arduino-cli upload -p <COM?> firmware/production/BoatLog/
arduino-cli monitor -p <COM?> -c baudrate=115200
```

**PadDis v8.9 display layout (320 × 240) — all Font 4, black background:**
```
┌──────────────────────────────────────────┐
│  HH:MM  (size 1, top-left — GPS fix)  ● ●│  ← paddle + boat signal dots
│           x.x kn  (size 2, centred)      │  ← GPS fix only
│          36.2 cpm  (size 2, centred)     │  ← grey when signal lost
└──────────────────────────────────────────┘
```

- All text Font 4 (TFT_eSPI built-in). Top line size 1 (26 px); speed and CPM size 2 (52 px).
- Two signal dots top-right of line 1: right = paddle (PadLog), left = boat (BoatLog). Filled and flashing while receiving; outline-only (grey) on 3 s timeout.
- Time and speed rows shown only when `gps_fix == 1`; cleared when fix lost or boat signal lost.
- CPM displayed to 1 decimal place (change-detection at 0.1 CPM resolution). Shows `-- cpm` before first paddle packet.
- No GPS warning text or other elements drawn.

#### 14.1.8 PadDis v8.10 — rx_ms cross-device sync

**Motivation.** The v8.9 paddle log embeds GPS UTC seconds, but GPS resolution is 1 s — coarser than a stroke and useless for aligning inter-packet detail between the paddle and boat streams. A finer common clock is needed to correlate the two streams in post-processing (e.g. `PadViz5b` bottom-graph traces from both sources).

**Change.** In `PadDis.ino`, the ESPnow receive callback captures `millis()` **before** any parsing or ring-buffer work, and the ring-buffer entry now wraps the payload plus that timestamp:

```cpp
struct PadRxEntry  { ImuDataPayload  p; uint32_t rx_ms; };
struct BoatRxEntry { BoatDataPayload p; uint32_t rx_ms; };

void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
    uint32_t rx_ms = millis();
    // …memcpy payload, push {p, rx_ms} to the appropriate ring…
}
```

The value is written as the trailing column of both paddle and boat CSV rows.

**Why the callback and not the CSV-writing loop.** `millis()` in the writing loop drifts by the ring-buffer depth (up to ~320 ms). Capturing at callback fire time locks the timestamp to physical arrival.

**Sync accuracy.** Same CYD clock domain for both streams → nearest-`rx_ms` match is < 10 ms typical, dominated by ESPnow send-side jitter (paddle radio ready vs. boat radio ready). The old `gps_utc_sec` column is retained as an absolute-time cross-check and for cross-day file merges.

**Client side.** PadViz5b `SyncMap.build()` uses the `rx_ms` path (±500 ms guard) when both CSVs carry the column, and falls back to `gps_utc_sec` (±5 s) for older files. Path selected at load time from the CSV header line.

---

### 14.2 PadViz4 — Paddle Centre Position Tracking

*Planned for implementation in Processing (PadViz4 sketch).*

The goal is to animate the centre of the paddle model moving in the X (left-right) and
Z (up-down) directions, driven by the IMU accelerometer data. The Y direction (fore-aft)
is out of scope for this phase.

**Approach — double integration with physical constraints:**

Position is obtained by double-integrating the world-frame linear acceleration. Raw
accelerometer data (which includes gravity) is rotated into the world frame using the
quaternion, then gravity is subtracted to give linear acceleration. This is then
integrated twice: linear acceleration → velocity → position.

Double integration of accelerometer data accumulates drift that grows without bound.
Two physical constraints are used to prevent this:

| Axis | Physical constraint | Correction method |
|------|--------------------|--------------------|
| X (left-right) | Net displacement over several stroke cycles is zero — the paddle returns to centre | High-pass filter: `posX_filtered = posX − posX_lowpass`, where `posX_lowpass` tracks with time constant τ ≈ 10 s |
| Z (up-down) | Average height varies by at most ±0.5 m over a session | High-pass with long time constant τ ≈ 30 s; hard clamp to ±0.5 m if exceeded |

The high-pass approach enforces the zero-mean constraint continuously rather than
requiring discrete cycle detection.

**Implementation plan (PadViz4):**

*Step 1 — DataSource:*
Parse the full 15-column CSV format (`seq, timestamp_ms, accel_x/y/z, q_w/x/y/z,
roll, pitch, yaw, stroke_count, cpm, hz`) to extract raw accelerometer data.
Add `accelX/Y/Z` fields to `FrameData`.

*Step 2 — Integrator tab (new):*
Per frame:
1. Compute `dt` from consecutive timestamps; clamp to 50 ms to handle seeks and pauses.
2. Rotate raw accel vector to world frame: `a_world = R(q) × a_sensor`.
3. Subtract gravity: in the Z-up world frame, gravity acts in the −Z direction
   (`a_world.z += 9.81`); X and Y components require no correction if the quaternion
   is accurate.
4. Integrate velocity: `vel += a_world × dt`.
5. Integrate position: `pos += vel × dt`.
6. High-pass X: `posX_lp += (posX − posX_lp) × (dt / tau_x)`;
   `posX_filtered = posX − posX_lp`.
7. Reset all integrator state (velocity, position, low-pass baseline) on file load or seek.

*Step 3 — Model3D:*
Translate the paddle model by `(posX_filtered × S, 0, 0)` before applying the
rotation quaternion.

*Step 4 — Key `P`:*
Toggle position tracking on/off for direct A/B comparison.

*Step 5 — HUD:*
Display `posX` and `velX` for diagnostic purposes during tuning.

*Step 6 — X confirmed working, then add Z:*
Once X position looks physically plausible, apply the same integration to Z with
`tau_z ≈ 30 s` and a ±0.5 m hard clamp.

**Data quality note:** The current payload uses raw accelerometer output from
`SH2_ACCELEROMETER` (gravity included). Manual gravity subtraction via quaternion
rotation introduces error proportional to orientation uncertainty. The BNO085 provides
a dedicated `SH2_LINEAR_ACCELERATION` report (gravity removed internally by the fusion
algorithm) which is more accurate. Adding this report to PadLog and PadDis (a minor
firmware change) is the recommended next step once the integration approach is
validated in PadViz4 using existing data.

**GPS integration (when boat unit is available, §14.1):** GPS ground speed from the
NEO-6M replaces the low-frequency velocity estimate from double-integration, dramatically
reducing position drift. GPS velocity (at 5 Hz) is used as the baseline; the paddle IMU
acceleration fills in the high-frequency detail between GPS fixes. This is a standard
GNSS/IMU loose-coupling architecture and will give significantly more reliable position
estimates than accelerometer integration alone. The boat unit's `gps_utc_sec` field
aligns the two logs for this fusion in post-processing.

---

## 15. Magnetometer Calibration Support (Phase 10)

*Firmware-side counterpart to PadViz6 spec §7 (per-session calibration procedure).*

### 15.1 Motivation

The BNO085 fusion references world +X to magnetic north via a self-calibrating
magnetometer. Yaw accuracy — and therefore paddle-vs-kayak orientation comparisons in
Slice C — depends on both sensors' magnetometers being well-calibrated in the same local
field. In practice this requires:

- A figure-8 warm-up per unit before every session.
- Persistent storage of Dynamic Calibration Data (DCD) so it survives power-cycle.
- A signal to the operator that calibration has converged (`mag status = 3`).
- An archival record of mag confidence per CSV row so post-processing can flag low-
  confidence segments.

None of this is currently exposed by PadLog or BoatLog — the mag status is emitted by
the sensor but silently discarded.

### 15.2 Requirements

#### 15.2.1 Enable the calibrated-magnetic-field report

Both PadLog and BoatLog must, in `setup()`, enable
`SH2_MAGNETIC_FIELD_CALIBRATED` at ≥ 10 Hz alongside the existing rotation-vector
report. The report's `.status` field (0–3) is the mag calibration accuracy.

Adafruit_BNO08x example:

```cpp
if (!bno.enableReport(SH2_MAGNETIC_FIELD_CALIBRATED, 100000UL)) {  // 10 Hz
    Serial.println("MAG report enable failed");
}
```

#### 15.2.2 Serial mag-status output — on-change only

Once per `loop()`, sample the latest mag report and emit a serial line **only when the
status value has changed** from the previously-emitted value:

```
[MM:SS] MAG_CAL: 0
[MM:SS] MAG_CAL: 1
[MM:SS] MAG_CAL: 2
[MM:SS] MAG_CAL: 3
```

Emit `MAG_CAL: 3` when the value first reaches 3; do not re-emit on subsequent frames
until the value changes. On-change output keeps the serial channel quiet during steady-
state operation while making figure-8 convergence visible in real time.

#### 15.2.3 Save DCD after first convergence

When mag status reaches 3 for the first time in a given power-cycle, call
`sh2_saveDcdNow()` once. Log the outcome:

```
[MM:SS] MAG_CAL: 3
[MM:SS] DCD_SAVED
```

This persists the calibration to the BNO085's on-chip flash so the next power-cycle
starts with a converged mag rather than requiring a fresh figure-8. Subsequent status
transitions (3 → 2 → 3 etc.) do **not** re-trigger the save — one save per boot.

#### 15.2.4 Log mag_cal per CSV row

Add a `mag_cal` column (uint8, 0–3) to both the paddle payload struct and the boat
payload struct. This is a payload change — versions of PadLog, PadDis, and BoatLog that
carry `mag_cal` must be released together and the payload struct definition kept in
byte-for-byte sync as with previous phases.

CSV column additions (appended after `rx_ms`):

- **Paddle log** (v8.10 full 15-col becomes 16-col; reduced 9-col becomes 10-col):
  `..., rx_ms, mag_cal`
- **Boat log** (v1.0 17-col becomes 21-col — three accel columns added per §15.2.5 in
  addition to `mag_cal`):
  `..., rx_ms, boat_accel_x, boat_accel_y, boat_accel_z, mag_cal`

Header comment version bumps: PadDis → **v8.11**, BoatLog → **v1.1**, PadLog → **v8.8**.

#### 15.2.5 Boat accelerometer forwarding

BoatLog already enables `SH2_ACCELEROMETER` at 100 Hz alongside the rotation-vector
report but the samples are read and discarded. Phase 10 adds the missing forwarding so
the boat side matches the paddle side:

- BoatLog: cache the latest `accel_x/y/z` in the existing `SH2_ACCELEROMETER` event
  branch (see BoatLog.ino around L187) and emit them in every outgoing payload.
- `BoatDataPayload` gains three `float` fields (`accel_x`, `accel_y`, `accel_z`),
  inserted before `mag_cal` so mag stays as the final semantic field.
- PadDis boat CSV gains three columns (`boat_accel_x`, `boat_accel_y`, `boat_accel_z`),
  inserted before `mag_cal` so mag stays as the final column.

Motivation: symmetry with paddle CSV; enables rest-window detection on the boat side
(PadViz6 `Sidecar.pde` currently uses paddle accel only); enables surge/heave/lateral
kayak analysis in later visualiser work.

Deferred until now because it did not merit its own coordinated release, but bundles
naturally with Phase 10 since Phase 10 already breaks the boat payload struct.

#### 15.2.6 CYD indicator (optional, deferred)

On the CYD display, an `M<0-3>` letter next to the existing signal dots (line 1),
coloured red/orange/yellow/green for 0/1/2/3. Deferred until field use confirms whether
the serial channel is sufficient during figure-8 warm-up on shore. Not blocking for
Phase 10 acceptance.

### 15.3 Payload struct — updated

**Paddle** — `ImuDataPayload` gains a single `uint8_t mag_cal` field appended after the
existing content, plus three padding bytes for 4-byte alignment:

```cpp
struct ImuDataPayload {
    // ... existing fields ...
    uint8_t  mag_cal;
    uint8_t  _pad[3];   // reserved for future use, must be zero
};
```

Paddle payload grows 60 → 64 bytes.

**Boat** — `BoatDataPayload` gains three `float` accel fields **plus** the same
`mag_cal + _pad[3]`. Accel goes before `mag_cal` so the mag byte stays as the final
semantic field on both sides:

```cpp
struct BoatDataPayload {
    // ... existing fields ...
    float    accel_x;
    float    accel_y;
    float    accel_z;
    uint8_t  mag_cal;
    uint8_t  _pad[3];   // reserved for future use, must be zero
};
```

Boat payload grows 58 → 74 bytes (12 for accel + 4 for mag). Both still well under the
250-byte ESP-NOW limit.

### 15.4 Test Plan (Phase 10)

#### T-40 Mag Report Enabled at Startup

**Purpose:** confirm both firmwares enable the mag report without error.

**Steps:** flash PadLog (or BoatLog); monitor serial from cold start.

**Pass:** no `MAG report enable failed` line appears. First `MAG_CAL: <n>` line appears
within 5 s of the startup banner.

#### T-41 Mag Status Converges to 3 on Figure-8

**Purpose:** confirm the sensor learns calibration in a clean environment.

**Steps:** place unit on bench (no ferrous mass within 30 cm), start serial monitor,
wave the unit in a figure-8 pattern (three axes of rotation).

**Pass:** `MAG_CAL: 3` line emitted within 60 s of the first figure-8 movement.

#### T-42 DCD_SAVED Fires Exactly Once Per Boot

**Purpose:** confirm calibration is persisted, and only once.

**Steps:** run T-41 to convergence. Continue moving the unit for another 5 minutes,
occasionally holding still.

**Pass:** exactly one `DCD_SAVED` line emitted, immediately after the first
`MAG_CAL: 3` line. No further `DCD_SAVED` lines regardless of subsequent status
oscillation.

#### T-43 DCD Survives Power-Cycle

**Purpose:** confirm on-chip flash preserves calibration.

**Steps:** run T-42 to `DCD_SAVED`. Power-cycle the unit. On restart, monitor serial
without moving the unit.

**Pass:** first `MAG_CAL:` line reports status ≥ 2 (usually 3). No figure-8 is required
before the unit reaches status 3 again.

#### T-44 mag_cal Column Present in CSVs

**Purpose:** confirm the new column reaches the SD file.

**Steps:** flash PadDis v8.11 and BoatLog v1.1 (or PadLog v8.8 + PadDis v8.11); record
a short session with both units powered.

**Pass:** both `ImuLogNN.CSV` and `BoatLogNN.CSV` contain a `mag_cal` column as the
last field. Values are integers in `[0, 3]`. Header-comment version lines updated
(`# PadDis v8.11`, `# BoatLog v1.1`).

#### T-45 mag_cal Populated After DCD Load

**Purpose:** confirm the archival log reflects post-load calibration state.

**Steps:** power-cycle a unit that has previously saved DCD. Start recording within 10 s
of the CYD acquiring signal.

**Pass:** `mag_cal` column reads 3 (or ≥ 2) within the first 100 rows without any
figure-8 movement.

#### T-46 Boat Accel Columns Populated

**Purpose:** confirm the boat-side accel forwarding is live end-to-end.

**Steps:** flash BoatLog v1.1 and PadDis v8.11; record a short session; move the boat
unit (or the whole boat) in a known direction — e.g. lift the bow, tilt to starboard.

**Pass:** boat CSV contains `boat_accel_x`, `boat_accel_y`, `boat_accel_z` columns
before `mag_cal`. `sqrt(x² + y² + z²)` ≈ 9.8 m/s² when the unit is still. Tilting the
unit produces the expected sign changes on the tilted axes.

### 15.5 Interaction with PadViz6

The visualiser's per-session sidecar (PadViz6 spec §7) reads the `mag_cal` column during
rest-window detection. Rest windows are only accepted with `mag_cal ≥ 2` on both
sensors; low-confidence windows produce a sidecar with `"confidence": "none"`. The
visualiser then displays `LOW MAG CONFIDENCE` in the Slice C HUD and skips the yaw
datum correction (mount offsets are still applied — they're accel-only).

### 15.6 Release Coupling

Phase 10 is released as a co-ordinated set: PadLog v8.8, BoatLog v1.1, PadDis v8.11.
Any two of these built against different payload struct definitions are incompatible.
Version bumps must be committed in a single commit and the payload struct definition
kept identical across the three sketches.

### 15.7 Release Status (9 Jul 2026)

**Released** in single commit `d8ce219` on `main`:

- PadLog v8.8, BoatLog v1.1, PadDis v8.11 (payload struct byte-locked at 64 B / 74 B).
- PadDis SD paddle-log prefix renamed `ImuLog → PadLog` alongside; existing `ImuLog##.CSV`
  files stay unchanged.

**Bench-verified 9 Jul 2026:**

- PadLog banner + `Payload: 64 bytes` line + `MAG_CAL:` telemetry emitting on-change.
- BoatLog banner + `MAG_CAL:` telemetry emitting (values 0, 1, 2 observed).
- PadDis boots + SD init + creates `/PadLog##.CSV` and `/BoatLog##.CSV` on the new naming
  convention.

**Outstanding (require cleaner magnetic environment or on-water session):**

- **T-41** mag climb to stable status 3 — reached 3 briefly on PadLog but sensor
  bench environment (nearby computer + USB hub) is noisy; not held long enough to
  verify.
- **T-42** `DCD_SAVED` emitted exactly once per boot at first status=3 — line did not
  appear in the bench run despite `MAG_CAL: 3` appearing. Possible causes to investigate:
  status oscillation between the two consecutive prints (unlikely — same event dispatch),
  `sh2_saveDcdNow()` silently blocked/failed (would show a POWERON on next boot — did
  not), or environment-dependent transient. Add a debug printf capturing
  `sh2_saveDcdNow()`'s return value on the re-flash pass.
- **T-43** DCD survives power-cycle — gated on T-42.
- **T-44 / T-45** `mag_cal` column populated in both CSVs — verify by pulling the SD
  card and inspecting a `PadLog##.CSV` and `BoatLog##.CSV` written during a session.
- **T-46** `boat_accel_x/y/z` populated with plausible gravity vector — same SD-card
  inspection covers this.

**Diagnostic tool:** `firmware/diag/mag_watch.ps1` — opens the serial port on Windows
without triggering the ESP32 DTR/RTS reset and filters for boot / MAG_CAL / DCD_SAVED
/ CSV-init lines. Useful for inspecting a running sketch without restarting it.
Usage: `powershell -File firmware/diag/mag_watch.ps1 -Port COM3 -Baud 115200`.
