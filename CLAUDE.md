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
| `visualisation/` | Processing sketches (PadViz…PadViz7; **PadViz7 is current**) + `stroke_*.py` offline analysis toolkit |
| `visualisation/specs/` | `padviz6_spec.md` (active PadViz spec, through v0.16/PadViz7), `simulation_specification.md` |
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

### PadDis (RX — CYD, COM6 as of 20 Jul 2026 — port moves, check `arduino-cli board list`)

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
- **Phase 9** — Feasibility PROVEN offline 17 Jul 2026 (spec §13.5, `visualisation/stroke_catch_explore.py` on 16 Jul data): entry and exit each produce phase-locked 8–30 Hz accel transients (four bumps per cycle, per-cycle jitter ±33–96 ms), corroborated by boat surge and tip-height kinematics; GRV relative yaw chosen for blade geometry (spec §16.11). Firmware/algorithm design not started.
- **Detector robustness (12–13 Jul 2026, spec §16)** — 11 Jul field test with a two-piece paddle: joint-play shoulder notches drove reported CPM to 87 vs true 30. Fixes applied 12 Jul (commit 87f49d9): 30° prominence gate in StrokeDetector + `detector.reset()` on timeout in PadLog.ino; sim suite 20/20 on hardware; **on-water verification PASSED 13 Jul 2026** (five-segment protocol, spec §16.8 result block — median |err| ≤ 1 CPM, immediate segment-5 recovery, no runaway in 35 min; analysis script `visualisation/stroke_field_verify.py`). 13 Jul algorithm review: peak detector kept — it is the only source of per-stroke events at ~1-stroke latency; an autocorrelation (ACF) cross-check was prototyped and validated offline (`visualisation/stroke_acf.py`, spec §16.9) — on the 11 Jul data it flags the padbad failure 100 % of the time with a 1–3 % nuisance rate during good paddling. Firmware port of the ACF arbiter is unscheduled until §16.8 passes. Known limit: zero-feather (symmetric) roll waveforms are half-period ambiguous for **any** roll-only algorithm — resolving needs relative yaw (§16.6) or Phase 9 accel transients. Full alternatives survey (zero-crossing, FFT, PLL, matched filter) in spec §16.6/§16.9.
- **GRV data collection (13 Jul 2026, spec §16.11)** — coordinated release PadLog v8.9 / BoatLog v1.2 / PadDis v8.12: BNO085 Game Rotation Vector (mag-free quaternion) at 100 Hz on both TX units, appended to both payloads (paddle 64→80 B, boat 74→90 B) and both CSVs (`grv_qw..qz` / `boat_grv_qw..qz`, appended at end). Data collection only — feeds the future Phase 9 fused-vs-GRV relative-yaw decision, since GRV is not reconstructible offline. Same release: TX firmware version in two former pad bytes; PadDis writes CSV headers on first received packet so the comment line names the TX firmware. All three units flashed and **bench-verified 13 Jul 2026** (spec §16.11 result block). **v8.13** (PadDis only, same evening): splash wait drains rings to SD — no more ~20 s startup packet gap (bench: 1998+1995 packets logged during splash); speed line shows grey `-- kn` placeholder when no GPS/boat data. **Field-verified 16 Jul 2026** (spec §16.11 field result block): CYD powered ~9 min after TX units, no seq gap > 10 packets (paddle loss 0.01 %); first field GRV dataset banked; paddle mag_cal reached 3 for 75 % of session; zero-feather pitch channel confirmed again while yaw read 2× — yaw eliminated, pitch stands alone (spec §16.10 addendum).
- **Zero-feather CPM fix (20 Jul 2026, spec §16.12)** — pitch-fed `CadenceACF` (new `CadenceACF.h/.cpp`, ported from `visualisation/stroke_acf.py`) built into PadLog v8.10 / PadDis v8.14; payload's reserved pad byte becomes `cpm_source` (0=peak detector white, 1=ACF zero-feather fallback yellow `0x07FF`, 2=arbiter-suppressed `?? cpm`), payload size unchanged at 80 B. Offline acceptance test (`visualisation/stroke_zero_feather_regression.py`) PASSES both cases: 16 Jul zero-feather segment reports source=1 at 32.7 CPM (spec table: 32.8) for 100% of settled samples; 11 Jul padbad case (via the CSV's own recorded `cpm` vs a fresh pitch-ACF estimate, matching `stroke_acf.py`'s already-validated methodology) flags 100% disagreement, matching spec §16.9. Arbiter threshold fixed at the tested 30% (not the plan text's "~25%" approximation). **FLASHED 20 Jul 2026** (PadLog COM3, PadDis COM6) — now the deployed version on both units. **Bench PARTIALLY verified same day**: both sketches boot clean, ESPnow link solid (2004 packets received during PadDis's ~20 s splash window alone), payload struct/`cpm_source` decode confirmed correct via serial (`CPM: 0.0 (raw 0) (0.00 Hz) stroke=0 source=0` at idle). **Not verified**: CPM tracking against real paddle motion, the yellow zero-feather fallback, and absence of arbiter false-positives during normal paddling — the physical bench steps were cut short by a stuck Claude Code permission dialog (VS Code integrated terminal input bug, same class as anthropics/claude-code#72200) and the user chose to proceed straight to a field session instead of retrying the bench. **Field test pending** — awaiting the returned SD CSV for offline verification. On-hardware 20-test sim suite additions also still needed (not blocking).
- **Phase 10** — Magnetometer calibration support: complete (9 Jul 2026, commit d8ce219). Coordinated release PadLog v8.8 / BoatLog v1.1 / PadDis v8.11 per spec §15.6. Enables `SH2_MAGNETIC_FIELD_CALIBRATED` at 10 Hz on both TX units, on-change `MAG_CAL:` serial, `sh2_saveDcdNow()` on first status=3. Payload struct grows: paddle 60→64 B (mag_cal + pad), boat 58→74 B (accel_x/y/z + mag_cal + pad — boat accel forwarding was previously read and discarded, spec §15.2.5 rider). New CSV columns: paddle gains `mag_cal`, boat gains `boat_accel_x/y/z,mag_cal`. PadDis SD paddle-log prefix renamed `ImuLog → PadLog`. Bench-verified 9 Jul 2026; T-41..T-46 hardware tests need cleaner mag environment or on-water session (see spec §15.7).
- **Visualisation (PadViz Processing sketches, spec `visualisation/specs/padviz6_spec.md`)** — separate strand from the firmware phases above; renders paddle/boat IMU CSVs offline. Lineage PadViz→…→PadViz6, all superseded but kept for reference. **PadViz7 is current** (v0.16, 21 Jul 2026, spec §14): forked from PadViz6 v0.15, adds a guided F1 session-setup wizard (`Wizard.pde`, replacing `Checklist.pde`) and a sidecar Classification section (`Classification.pde` + `classification_sections` JSON) marking good right/left/zero-feather stretches and excluding ranges from the graph + all navigation. Reads the current v8.14 full-column CSVs (trailing `cpm_source` ignored positionally); backward-compatible with pre-v0.16 `.session.json` sidecars. **BUILT + compiles clean** via `processing-java --build` (Processing 4.3); on-screen keyboard/click walkthrough still pending (spec §14.4). Build: `"/c/Program Files/processing-4.3/processing-java.exe" --sketch=<abs>/visualisation/PadViz7 --build`. Offline algorithm toolkit is the separate `visualisation/stroke_*.py` scripts (see Simulation Test section).

## Production Sketches

| Sketch | Directory | MCU | Port | FQBN |
|---|---|---|---|---|
| PadLog | `firmware/production/PadLog/` | LOLIN32 Lite | COM3 | `esp32:esp32:lolin32-lite` |
| PadDis | `firmware/production/PadDis/` | CYD ESP32-2432S028 | COM6 | `esp32:esp32:esp32` |
| BoatLog | `firmware/production/BoatLog/` | LOLIN32 Lite | COM3 | `esp32:esp32:lolin32-lite` |

**Version scheme:** `<phase>.<iteration>` — PadLog **v8.10**, PadDis **v8.14**, BoatLog **v1.2**. Versions can diverge when only one sketch changes; Phase 10, the GRV release, and the zero-feather fix (spec §16.12) required coordinated bumps per spec §15.6 (payload struct/semantics changes).

**Paddle payload struct** (80 bytes, float — must be identical in PadLog and PadDis):
```
seq, timestamp_ms, accel_x/y/z, q_w/x/y/z, roll/pitch/yaw, stroke_count, cpm, hz,
grv_qw/x/y/z, mag_cal, fw_major, fw_minor, _pad[1]
```

**Boat payload struct** (90 bytes — must be identical in BoatLog and PadDis):
```
seq, timestamp_ms, gps_utc_sec, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg,
gps_fix, gps_uk_offset, kayak_qw/x/y/z, kayak_roll/pitch/yaw,
accel_x/y/z, grv_qw/x/y/z, mag_cal, fw_major, fw_minor, _pad[1]
```

`fw_major`/`fw_minor` carry the TX sketch version (from `SKETCH_VER_MAJOR/MINOR`, which also generate `SKETCH_VERSION` — single source of truth).

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
- **Full** (v8.13 default — directive commented out): `seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, gps_utc_sec, gps_uk_offset, rx_ms, mag_cal, grv_qw, grv_qx, grv_qy, grv_qz`

`gps_utc_sec` and `gps_uk_offset` are 0 when no GPS fix is active. `rx_ms` is CYD-side `millis()` captured at the moment the ESPnow receive callback fires — same clock domain on both paddle and boat log rows, so post-processing sync is a straight nearest-`rx_ms` match (< 10 ms typical). `mag_cal` is the BNO085 magnetometer accuracy 0–3 (see spec §15). First line of every file names both RX and TX firmware: `# PadDis v8.13 paddle | PadLog v8.9` / `# PadDis v8.13 boat | BoatLog v1.2`. Headers are written on the **first received packet** of each stream (not at startup) so the TX version can be included; a stream that never received packets leaves an empty file. `cpm` column is raw (un-EMAd).

**Boat log** (auto-numbered `/BoatLog00.CSV`): `seq, timestamp_ms, gps_utc_sec, gps_uk_offset, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix, kayak_qw, kayak_qx, kayak_qy, kayak_qz, kayak_roll, kayak_pitch, kayak_yaw, rx_ms, boat_accel_x, boat_accel_y, boat_accel_z, mag_cal, boat_grv_qw, boat_grv_qx, boat_grv_qy, boat_grv_qz`

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
