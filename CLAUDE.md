# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Kayak paddle cycle-rate monitor. An ESP32 reads roll from a BNO085 IMU mounted at the centre of the paddle shaft and reports cycles per minute over USB serial. See `functional_spec.md` for full requirements.

## Target Platform

- **MCU:** ESP32
- **IDE:** Arduino IDE
- **IMU:** BNO085 via SPI, using the `Adafruit_BNO08x` library
- **Output:** USB serial at 115200 baud

There is no host build system. Firmware is compiled and flashed through the Arduino IDE. There are no automated tests.

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
