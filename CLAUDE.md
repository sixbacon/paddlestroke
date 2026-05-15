# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Kayak paddle cycle-rate monitor. An ESP32 reads roll from a BNO085 IMU mounted at the centre of the paddle shaft and reports cycles per minute over USB serial. See `functional_spec.md` for full requirements.

## Target Platform

- **MCU:** WEMOS LOLIN32 Lite (`esp32:esp32:lolin32-lite`)
- **Toolchain:** Arduino CLI 1.4.1
- **IMU:** BNO085 via SPI, using the `Adafruit_BNO08x` library
- **Output:** USB serial at 115200 baud

## Build Commands

### PadLog (TX — LOLIN32 Lite, COM3)

```bash
arduino-cli compile PadLog/
arduino-cli upload -p COM3 PadLog/
arduino-cli monitor -p COM3 -c baudrate=115200
```

### PadDis (RX — CYD, COM6)

```bash
arduino-cli compile PadDis/
arduino-cli upload -p COM6 PadDis/
arduino-cli monitor -p COM6 -c baudrate=115200
```

```bash
# List connected boards to find the port
arduino-cli board list
```

The FQBN for PadLog (`esp32:esp32:lolin32-lite`) is set in `PadLog/sketch.yaml`. The FQBN for PadDis (`esp32:esp32:esp32`) is set in `PadDis/sketch.yaml`. The sim test sketch has its own `paddlestroke_sim_test/sketch.yaml` with `esp32:esp32:esp32doit-devkit-v1`.

## Simulation Test

The `paddlestroke_sim_test/` subdirectory contains a self-contained Arduino sketch that runs all 12 algorithm tests using synthetic roll data — no IMU required. Flash it to an ESP DOIT DEVKIT V1:

```bash
# Compile
arduino-cli compile paddlestroke_sim_test/

# Compile and upload (replace COM3 with actual port)
arduino-cli compile -u -p COM3 paddlestroke_sim_test/
```

Expected output ends with `Results: 20 passed, 0 failed`.

The `StrokeDetector.h` and `StrokeDetector.cpp` files inside `paddlestroke_sim_test/` are copies of those in `PadLog/`. Keep them in sync when changing the algorithm.

## Development Status

- **Phase 1** — Algorithm + 20-test sim suite: complete
- **Phase 2** — Live BNO085 IMU integration, serial output: complete
- **Phase 3** — SD card logging (timestamp_ms, roll, pitch, yaw at 100 Hz): complete
- **Phase 4** — Field testing complete (2 May 2026). EMA high-pass filter added. Low-power doze mode with GPIO4 (BNO085 INT) interrupt wakeup: complete
- **Phase 5** — ESPnow broadcast of stroke rate: complete (transmit side; receiver is a separate project)
- **Phase 6** — CYD ESPnow receiver: complete (5 May 2026). LVGL dropped in favour of TFT_eSPI direct. All tests T-19–T-22 passed.
- **Phase 7** — ESPnow full-IMU data link + CYD SD logging: complete (6 May 2026). All tests T-23–T-31 passed. Bug fixed: yaw wrap at ±180° caused EulerErr=360° (corrected with wrap-aware subtraction in RX sketch).
- **Phase 8** — Production integration: complete (14 May 2026). PadLog v8.3 (TX) + PadDis v8.3 (RX). v8.1: hardware validated 12 May 2026. v8.2: streak gate, separate rate buffers, asymmetry bar. v8.3: doze/wake bug fixed (accelerometer left active in doze blocked RV wakeup events); full system validated 14 May 2026. v8.4: CPM maturity gate (isRateMature — both buffers ≥ 2 entries before first report); asymmetry L/R classification replaced with rolling-midpoint of peak/trough roll values (self-calibrates to mounting offset); uploaded 15 May 2026, field test pending.

## Production Sketches

| Sketch | Directory | MCU | Port | FQBN |
|---|---|---|---|---|
| PadLog | `PadLog/` | LOLIN32 Lite | COM3 | `esp32:esp32:lolin32-lite` |
| PadDis | `PadDis/` | CYD ESP32-2432S028 | COM6 | `esp32:esp32:esp32` |

**Version scheme:** `<phase>.<iteration>` — currently **v8.4**. Version shown in serial banner, CYD splash screen, and CSV first line (`# PadDis v8.4`).

**Payload struct** (60 bytes, float — must be identical in both sketches):
```
seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll/pitch/yaw, stroke_count, cpm, hz
```

**Key display findings (5 May 2026):**
- `setRotation(2)` gives correct landscape orientation on this unit (not rotation 1)
- At startup, call `fillScreen(TFT_WHITE)` in all four rotations before settling on rotation 2 — this clears noise pixels in the display area outside the active window
- TFT_eSPI Font 8 (75 px 7-segment style) is readable and sufficient — no custom font needed
- `User_Setup.h` must be in the sketch directory with `#define USER_SETUP_LOADED`

## Key Constraints

- Cycle rate valid range: **0.25 – 2.5 Hz** (0.4 s – 4.0 s period)
- Amplitude gate: peak-to-trough roll must be **≥ 45°**; smaller swings are ignored
- Rate averaging: rolling window over the last **4 qualifying cycles** per buffer (separate peak/trough buffers, up to 8 values total)
- Streak gate: CPM not reported until **3 consecutive qualifying strokes** detected AND both rate buffers hold ≥ 2 entries (`isRateMature()`)
- IMU sample rate: minimum 50 Hz, 100 Hz preferred
- CYD display is **BGR** pixel order: send `0x001F` to display red (not `TFT_RED = 0xF800`)

## SD Card Logging

CSV file auto-numbered `/PadDat00.CSV` … `/PadDat99.CSV`. Columns: `timestamp_ms,roll,pitch,yaw`. Written at 100 Hz; flush deferred to stroke timeout or every 30 s. SD absence is non-fatal — device continues with serial output only.

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

### TX test (`paddlestroke_espnow_tx_test/`) — LOLIN32 Lite, COM3

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
arduino-cli compile paddlestroke_espnow_tx_test/
arduino-cli upload -p COM3 paddlestroke_espnow_tx_test/
arduino-cli monitor -p COM3 -c baudrate=115200
```

### RX test (`paddlestroke_espnow_rx_sdlog/`) — CYD, COM6

Receives packets, logs to SD, shows stroke count and signal status on TFT.

**SPI buses — no conflict:**
- Display ILI9341: HSPI (SCK=14, MOSI=13, MISO=12, CS=15)
- SD card: VSPI (SCK=18, MOSI=23, MISO=19, CS=5)

CSV columns: `seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll/pitch/yaw, stroke_count, d_roll/d_pitch/d_yaw (re-derived), roll_err/pitch_err/yaw_err, az_err`

```bash
arduino-cli compile paddlestroke_espnow_rx_sdlog/
arduino-cli upload -p COM6 paddlestroke_espnow_rx_sdlog/
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
3. Hold still for doze timeout — `DOZE:` banner appears on PadLog serial
4. Paddle briskly — `WAKE:` banner appears and CPM resumes
5. Confirm SD CSV created on PadDis with correct headers

## Git

Commit and push to `origin/main` (GitHub) after each meaningful change with a descriptive commit message.
