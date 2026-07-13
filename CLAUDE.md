# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Kayak paddle cycle-rate monitor. An ESP32 reads roll from a BNO085 IMU mounted at the centre of the paddle shaft and reports cycles per minute over USB serial. See `firmware/specs/functional_spec.md` for full requirements.

## Repository Layout

| Folder | Contents |
|--------|----------|
| `firmware/production/` | PadLog (TX) and PadDis (RX) — currently deployed |
| `firmware/test/` | Development and validation sketches |
| `firmware/specs/` | `functional_spec.md`, `sim_test_spec.md` |
| `firmware/instructions/` | Instruction text files (local only, git-ignored) |
| `firmware/error_reports/` | Error report text files (local only, git-ignored) |
| `visualisation/` | PadViz, PadViz2, PadViz3, PadViz4 Processing sketches |
| `visualisation/specs/` | `simulation_specification.md` |
| `visualisation/instructions/` | Instruction text files (local only, git-ignored) |
| `visualisation/error_reports/` | Error report text files (local only, git-ignored) |
| `data/` | Recorded field session CSVs by date (local only, git-ignored) |
| `archive/` | Superseded sketches, media, diagnostics |

## Target Platform

- **MCU:** WEMOS LOLIN32 Lite (`esp32:esp32:lolin32-lite`)
- **Toolchain:** Arduino CLI 1.4.1
- **IMU:** BNO085 via SPI, using the `Adafruit_BNO08x` library
- **Output:** USB serial at 115200 baud

## Build Commands

### PadLog (TX — LOLIN32 Lite, COM3)

```bash
arduino-cli compile firmware/production/PadLog/
arduino-cli upload -p COM3 firmware/production/PadLog/
arduino-cli monitor -p COM3 -c baudrate=115200
```

### BoatLog (hull unit — LOLIN32 Lite, COM3)

```bash
arduino-cli compile firmware/production/BoatLog/
arduino-cli upload -p COM3 firmware/production/BoatLog/
arduino-cli monitor -p COM3 -c baudrate=115200
```

### PadDis (RX — CYD, COM6)

```bash
arduino-cli compile firmware/production/PadDis/
arduino-cli upload -p COM6 firmware/production/PadDis/
arduino-cli monitor -p COM6 -c baudrate=115200
```

```bash
# List connected boards to find the port
arduino-cli board list
```

The FQBN for PadLog (`esp32:esp32:lolin32-lite`) is set in `firmware/production/PadLog/sketch.yaml`. The FQBN for PadDis (`esp32:esp32:esp32`) is set in `firmware/production/PadDis/sketch.yaml`. The sim test sketch has its own `firmware/test/paddlestroke_sim_test/sketch.yaml` with `esp32:esp32:esp32doit-devkit-v1`.

## Simulation Test

The `firmware/test/paddlestroke_sim_test/` subdirectory contains a self-contained Arduino sketch that runs all 12 algorithm tests using synthetic roll data — no IMU required. Flash it to an ESP DOIT DEVKIT V1:

```bash
# Compile
arduino-cli compile firmware/test/paddlestroke_sim_test/

# Compile and upload (replace COM3 with actual port)
arduino-cli compile -u -p COM3 firmware/test/paddlestroke_sim_test/
```

Expected output ends with `Results: 20 passed, 0 failed`.

The `StrokeDetector.h` and `StrokeDetector.cpp` files inside `firmware/test/paddlestroke_sim_test/` are copies of those in `firmware/production/PadLog/`. Keep them in sync when changing the algorithm.

For offline algorithm iteration against field CSVs there is a Python toolkit in `visualisation/stroke_*.py` (spec §16.5): `stroke_spectral.py` gives ground-truth CPM per file, `stroke_detector_sim.py` is a faithful Python port of StrokeDetector, `stroke_regression.py` ports the 20-test suite for quick pre-C++ checks, `stroke_acf.py` is the ACF cross-check prototype. Prototype algorithm changes there first; on-hardware sim remains authoritative for timing.

## Development Status

- **Phase 1** — Algorithm + 20-test sim suite: complete
- **Phase 2** — Live BNO085 IMU integration, serial output: complete
- **Phase 3** — SD card logging (timestamp_ms, roll, pitch, yaw at 100 Hz): complete
- **Phase 4** — Field testing complete (2 May 2026). EMA high-pass filter added. Low-power doze mode with GPIO4 (BNO085 INT) interrupt wakeup: complete
- **Phase 5** — ESPnow broadcast of stroke rate: complete (transmit side; receiver is a separate project)
- **Phase 6** — CYD ESPnow receiver: complete (5 May 2026). LVGL dropped in favour of TFT_eSPI direct. All tests T-19–T-22 passed.
- **Phase 7** — ESPnow full-IMU data link + CYD SD logging: complete (6 May 2026). All tests T-23–T-31 passed. Bug fixed: yaw wrap at ±180° caused EulerErr=360° (corrected with wrap-aware subtraction in RX sketch).
- **Phase 8** — Production integration: complete (v8.6 flashed 18 May 2026). v8.1: hardware validated 12 May 2026. v8.2: streak gate, separate rate buffers, asymmetry bar. v8.3: doze/wake bug fixed (accelerometer left active in doze blocked RV wakeup events). v8.4: isRateMature gate + rolling-midpoint asymmetry. Field test 18 May 2026 revealed feather rotation artefacts inflating CPM ~1.7×. v8.5 (PadDis only): CSV_COLUMNS_REDUCED directive; 20-second CPM display EMA. v8.6: AMPLITUDE_GATE_DEG 45°→90°; Option 3 consecutive-event asymmetry; dark display theme. v8.7 (PadDis only): asymmetry bar removed; CPM EMA 20s→10s; yellow SD-absent warning. v8.8 (PadDis only): CSV_COLUMNS_REDUCED commented out — full 15-col CSV for PadViz4 position-tracking data collection. v8.9 (PadDis only): boat unit ESPnow integration; CPM 1dp display; speed/time/GPS warning; BoatLog00.CSV; GPS time stamped into paddle CSV. v8.10 (PadDis only): add rx_ms column (CYD-side ESPnow reception timestamp, captured in receive callback) to both paddle and boat CSVs — common clock domain enables sub-10 ms sync in post-processing.
- **Phase 9** — Pending: blade entry/exit detection using accel_x/accel_y transients to detect blade catch and release independently of roll oscillation. Design not started.
- **Detector robustness (12–13 Jul 2026, spec §16)** — 11 Jul field test with a two-piece paddle: joint-play shoulder notches drove reported CPM to 87 vs true 30. Fixes applied 12 Jul (commit 87f49d9): 30° prominence gate in StrokeDetector + `detector.reset()` on timeout in PadLog.ino; sim suite 20/20 on hardware; on-water verification pending (five-segment protocol, spec §16.8). 13 Jul algorithm review: peak detector kept — it is the only source of per-stroke events at ~1-stroke latency; an autocorrelation (ACF) cross-check was prototyped and validated offline (`visualisation/stroke_acf.py`, spec §16.9) — on the 11 Jul data it flags the padbad failure 100 % of the time with a 1–3 % nuisance rate during good paddling. Firmware port of the ACF arbiter is unscheduled until §16.8 passes. Known limit: zero-feather (symmetric) roll waveforms are half-period ambiguous for **any** roll-only algorithm — resolving needs relative yaw (§16.6) or Phase 9 accel transients. Full alternatives survey (zero-crossing, FFT, PLL, matched filter) in spec §16.6/§16.9.
- **Phase 10** — Magnetometer calibration support: complete (9 Jul 2026, commit d8ce219). Coordinated release PadLog v8.8 / BoatLog v1.1 / PadDis v8.11 per spec §15.6. Enables `SH2_MAGNETIC_FIELD_CALIBRATED` at 10 Hz on both TX units, on-change `MAG_CAL:` serial, `sh2_saveDcdNow()` on first status=3. Payload struct grows: paddle 60→64 B (mag_cal + pad), boat 58→74 B (accel_x/y/z + mag_cal + pad — boat accel forwarding was previously read and discarded, spec §15.2.5 rider). New CSV columns: paddle gains `mag_cal`, boat gains `boat_accel_x/y/z,mag_cal`. PadDis SD paddle-log prefix renamed `ImuLog → PadLog`. Bench-verified 9 Jul 2026; T-41..T-46 hardware tests need cleaner mag environment or on-water session (see spec §15.7).

## Production Sketches

| Sketch | Directory | MCU | Port | FQBN |
|---|---|---|---|---|
| PadLog | `firmware/production/PadLog/` | LOLIN32 Lite | COM3 | `esp32:esp32:lolin32-lite` |
| PadDis | `firmware/production/PadDis/` | CYD ESP32-2432S028 | COM6 | `esp32:esp32:esp32` |
| BoatLog | `firmware/production/BoatLog/` | LOLIN32 Lite | COM3 | `esp32:esp32:lolin32-lite` |

**Version scheme:** `<phase>.<iteration>` — PadLog **v8.8**, PadDis **v8.11**, BoatLog **v1.1**. Versions can diverge when only one sketch changes; Phase 10 required a coordinated bump per spec §15.6 (payload struct change).

**Paddle payload struct** (64 bytes, float — must be identical in PadLog and PadDis):
```
seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll/pitch/yaw, stroke_count, cpm, hz, mag_cal, _pad[3]
```

**Boat payload struct** (74 bytes — must be identical in BoatLog and PadDis):
```
seq, timestamp_ms, gps_utc_sec, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg,
gps_fix, gps_uk_offset, kayak_qw/x/y/z, kayak_roll/pitch/yaw,
accel_x/y/z, mag_cal, _pad[3]
```

**Key display findings (5 May 2026 / updated 30 Jun 2026):**
- `setRotation(2)` gives correct landscape orientation on this unit (not rotation 1)
- At startup, call `fillScreen(TFT_BLACK)` in all four rotations before settling on rotation 2 — this clears noise pixels in the display area outside the active window
- `User_Setup.h` must be in the sketch directory with `#define USER_SETUP_LOADED`
- v8.9 display: Font 4 throughout — line 1 (time + signal dots) size 1, lines 2–3 (speed, CPM) size 2 (52 px), centred. `setTextSize(2)` scales Font 4; reset to `setTextSize(1)` after each draw call.

## Key Constraints

- Cycle rate valid range: **0.25 – 2.5 Hz** (0.4 s – 4.0 s period)
- Amplitude gate: peak-to-trough roll must be **≥ 90°** for a 60° feathered paddle (raised from 45° in v8.6 — field test 18 May 2026 showed feather rotation events reach 70–85° in filtered space, inflating CPM ~1.7× at 45°)
- Prominence gate: a candidate extremum must sit **≥ 30°** beyond the running excursion since the last accepted same-type extremum (added 12 Jul 2026 — two-piece paddle joint play created shoulder notches that cleared the amplitude gate, spec §16.3)
- Rate averaging: rolling window over the last **4 qualifying cycles** per buffer (separate peak/trough buffers, up to 8 values total)
- Streak gate: CPM not reported until **3 consecutive qualifying strokes** detected AND both rate buffers hold ≥ 2 entries (`isRateMature()`)
- IMU sample rate: minimum 50 Hz, 100 Hz preferred
- CYD display is **BGR** pixel order: send `0x001F` to display red (not `TFT_RED = 0xF800`)

## SD Card Logging

Paddle CSV files auto-numbered `/PadLog00.CSV` … `/PadLog99.CSV` on PadDis SD card (renamed from `/ImuLog##.CSV` in v8.11 to match BoatLog convention; older `ImuLog` files stay). Written at 100 Hz; flush every 5 s and on signal loss. SD absence is non-fatal.

**Paddle log column sets** (controlled by `#define CSV_COLUMNS_REDUCED` in `PadDis.ino`):

- **Reduced** (re-enable for field use): `timestamp_ms, roll, pitch, yaw, stroke_count, cpm, gps_utc_sec, gps_uk_offset, rx_ms, mag_cal`
- **Full** (v8.11 default — directive commented out): `seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, gps_utc_sec, gps_uk_offset, rx_ms, mag_cal`

`gps_utc_sec` and `gps_uk_offset` are 0 when no GPS fix is active. `rx_ms` is CYD-side `millis()` captured at the moment the ESPnow receive callback fires — same clock domain on both paddle and boat log rows, so post-processing sync is a straight nearest-`rx_ms` match (< 10 ms typical). `mag_cal` is the BNO085 magnetometer accuracy 0–3 (see spec §15). First line of every file: `# PadDis v8.11 paddle` / `# PadDis v8.11 boat`. `cpm` column is raw (un-EMAd).

**Boat log** (auto-numbered `/BoatLog00.CSV`): `seq, timestamp_ms, gps_utc_sec, gps_uk_offset, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix, kayak_qw, kayak_qx, kayak_qy, kayak_qz, kayak_roll, kayak_pitch, kayak_yaw, rx_ms, boat_accel_x, boat_accel_y, boat_accel_z, mag_cal`

## Serial Output Format

```
[MM:SS] CYCLE_RATE: <cpm> CPM  (<hz> Hz)   // emitted after each qualifying cycle
[MM:SS] CYCLE_RATE: 0 CPM  (0.00 Hz)       // emitted when no valid cycle detected for > 3 s
[MM:SS] DOZE: low-power mode — waiting for motion
[MM:SS] WAKE: motion detected — resuming
PaddleStroke v1.0 — ready                  // banner on startup (no timestamp)
```

## ESPnow IMU Data Link — Test Sketches (Phase 7)

Goal: move SD logging from the paddle device to the CYD so the paddle unit can be sealed.

**All tests T-23–T-31 passed (6 May 2026). Production integration (Phase 8) can proceed.**

### TX test (`firmware/test/paddlestroke_espnow_tx_test/`) — LOLIN32 Lite, COM3

Synthetic 100 Hz transmitter, no IMU needed. Payload (92 bytes, well within 250-byte ESP-NOW limit):

| Field | Type | Value |
|---|---|---|
| seq | uint32 | monotonic counter |
| timestamp_ms | uint32 | millis() |
| accel_x/y | double | 2·sin/cos(angle) |
| accel_z | double | 9.80665 (constant) |
| q_w/x/y/z | double | pure Z-axis rotation |
| roll/pitch/yaw | double | derived from quat (roll=0, pitch=0 always) |
| stroke_count | uint32 | increments every 100 packets (~60 CPM) |

angle = seq × 2π/200 → one full rotation per 2 s.

```bash
arduino-cli compile firmware/test/paddlestroke_espnow_tx_test/
arduino-cli upload -p COM3 firmware/test/paddlestroke_espnow_tx_test/
arduino-cli monitor -p COM3 -c baudrate=115200
```

### RX test (`firmware/test/paddlestroke_espnow_rx_sdlog/`) — CYD, COM6

Receives packets, logs to SD, shows stroke count and signal status on TFT.

**SPI buses — no conflict:**
- Display ILI9341: HSPI (SCK=14, MOSI=13, MISO=12, CS=15)
- SD card: VSPI (SCK=18, MOSI=23, MISO=19, CS=5)

CSV columns: `seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll/pitch/yaw, stroke_count, d_roll/d_pitch/d_yaw (re-derived), roll_err/pitch_err/yaw_err, az_err`

```bash
arduino-cli compile firmware/test/paddlestroke_espnow_rx_sdlog/
arduino-cli upload -p COM6 firmware/test/paddlestroke_espnow_rx_sdlog/
arduino-cli monitor -p COM6 -c baudrate=115200
```

### Automated tests (60 s window on RX)

| ID | Test | Pass criterion |
|---|---|---|
| T-1 | Packet loss | < 1 % |
| T-2 | Max inter-packet gap | < 50 ms |
| T-3 | Euler re-derivation error | < 0.0001 ° |
| T-4 | accel_z vs 9.80665 | < 0.0001 m/s² |
| T-5 | SD card written | file exists |
| T-6 | Ring buffer overflow | 0 |

### Manual tests

- **T-7 Cold start:** power RX first → shows `---` → power TX → signal locks within 5 s (no reboot)
- **T-8 TX restart:** power-cycle TX mid-run → RX shows `---` → TX restarts → RX recovers automatically

### Post-processing (Excel/Python on CSV)

- `accel_x[i]` ≈ 2·sin(seq[i] × 2π/200)
- `accel_z[i]` = 9.80665 exactly
- `roll[i]` ≈ 0, `pitch[i]` ≈ 0 throughout
- `yaw[i]` ≈ (seq[i] mod 200) × 1.8 °
- `roll_err`, `pitch_err`, `yaw_err` < 1×10⁻⁴ throughout

### No application checksum needed

ESP-NOW hardware CRC-32 validates every 802.11 frame. Corrupted packets are dropped before the receive callback. The sequence number detects losses; T-3 and T-4 detect any double-transmission corruption.

## Test Protocol

After every firmware change, run this minimum check before committing:
1. PadDis shows CPM within 5 s of PadLog power-on (ESPnow link)
2. Paddle at steady rate — CPM updates and stabilises on PadDis
3. Hold still for doze timeout — `DOZE:` banner appears on PadLog serial (**skip while doze is disabled** — `#define DOZE_DISABLED` at PadLog.ino line 28)
4. Paddle briskly — `WAKE:` banner appears and CPM resumes (skip while doze is disabled)
5. Confirm SD CSV created on PadDis with correct headers

## Git

Commit and push to `origin/main` (GitHub) after each meaningful change with a descriptive commit message.
