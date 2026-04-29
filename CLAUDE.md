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

## Key Constraints

- Cycle rate valid range: **0.25 – 2.5 Hz** (0.4 s – 4.0 s period)
- Amplitude gate: peak-to-trough roll must be **≥ 45°**; smaller swings are ignored
- Rate averaging: rolling window over the last **4 qualifying cycles** (event-based, not time-based)
- IMU sample rate: minimum 50 Hz, 100 Hz preferred

## Serial Output Format

```
CYCLE_RATE: <cpm> CPM  (<hz> Hz)   // emitted after each qualifying cycle
CYCLE_RATE: 0 CPM  (0.00 Hz)       // emitted when no valid cycle detected for > 3 s
PaddleStroke v1.0 — ready          // banner on startup
```

## Git

Commit and push to `origin/main` (GitHub) after each meaningful change with a descriptive commit message.
