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

```bash
# Compile
arduino-cli compile paddlestroke/

# Upload (replace COM3 with the actual port)
arduino-cli upload -p COM3 paddlestroke/

# Compile and upload in one step
arduino-cli compile -u -p COM3 paddlestroke/

# Serial monitor
arduino-cli monitor -p COM3 -c baudrate=115200

# List connected boards to find the port
arduino-cli board list
```

The FQBN for the main sketch (`esp32:esp32:lolin32-lite`) is set in `sketch.yaml`. The sim test sketch has its own `paddlestroke_sim_test/sketch.yaml` with `esp32:esp32:esp32doit-devkit-v1`.

## Simulation Test

The `paddlestroke_sim_test/` subdirectory contains a self-contained Arduino sketch that runs all 12 algorithm tests using synthetic roll data — no IMU required. Flash it to an ESP DOIT DEVKIT V1:

```bash
# Compile
arduino-cli compile paddlestroke_sim_test/

# Compile and upload (replace COM3 with actual port)
arduino-cli compile -u -p COM3 paddlestroke_sim_test/
```

Expected output ends with `Results: 20 passed, 0 failed`.

The `StrokeDetector.h` and `StrokeDetector.cpp` files inside `paddlestroke_sim_test/` are copies of the ones in the root sketch directory. Keep them in sync when changing the algorithm.

## Development Status

- **Phase 1** — Algorithm + 20-test sim suite: complete
- **Phase 2** — Live BNO085 IMU integration, serial output: complete
- **Phase 3** — SD card logging (timestamp_ms, roll, pitch, yaw at 100 Hz): complete
- **Phase 4** — Field testing complete (2 May 2026). EMA high-pass filter added. Low-power doze mode with GPIO4 (BNO085 INT) interrupt wakeup: complete
- **Phase 5** — ESPnow broadcast of stroke rate: complete (transmit side; receiver is a separate project)
- **Phase 6** — CYD ESPnow receiver: display hardware characterised, main receiver sketch written and flashed (5 May 2026). LVGL dropped in favour of TFT_eSPI direct. T-19 passed. T-20–T-22 pending (require transmitter).

## CYD Receiver (`paddlestroke_espnow_rx/`)

- **MCU:** ESP32-2432S028 CYD2USB (`esp32:esp32:esp32`)
- **Display:** ILI9341 2.8" TFT via TFT_eSPI 2.5.43 — **no LVGL**
- **Port:** COM7

```bash
# Compile
arduino-cli compile paddlestroke_espnow_rx/

# Upload
arduino-cli upload -p COM7 paddlestroke_espnow_rx/
```

**Key display findings (5 May 2026):**
- `setRotation(2)` gives correct landscape orientation on this unit (not rotation 1)
- At startup, call `fillScreen(TFT_WHITE)` in all four rotations before settling on rotation 2 — this clears noise pixels in the display area outside the active window
- TFT_eSPI Font 8 (75 px 7-segment style) is readable and sufficient — no custom font needed
- `User_Setup.h` must be in the sketch directory with `#define USER_SETUP_LOADED`

## Key Constraints

- Cycle rate valid range: **0.25 – 2.5 Hz** (0.4 s – 4.0 s period)
- Amplitude gate: peak-to-trough roll must be **≥ 45°**; smaller swings are ignored
- Rate averaging: rolling window over the last **4 qualifying cycles** (event-based, not time-based)
- IMU sample rate: minimum 50 Hz, 100 Hz preferred

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

## Git

Commit and push to `origin/main` (GitHub) after each meaningful change with a descriptive commit message.
