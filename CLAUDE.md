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
| `visualisation/` | Processing sketches (PadViz…PadViz8; **PadViz8 is current**, PadViz7 kept as last-known-good) + `stroke_*.py` offline analysis toolkit |
| `visualisation/specs/` | `padviz6_spec.md` (active PadViz spec, through v0.38/PadViz8), `simulation_specification.md` |
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

For offline algorithm iteration against field CSVs there is a Python toolkit in `visualisation/stroke_*.py` (spec §16.5): `stroke_spectral.py` gives ground-truth CPM per file, `stroke_detector_sim.py` is a faithful Python port of StrokeDetector, `stroke_regression.py` ports the 20-test suite for quick pre-C++ checks, `stroke_acf.py` is the ACF cross-check prototype, `stroke_kinematic_model.py` examines the seat-anchored kinematic-model paddle-centre estimate (functional_spec §8.1.1) on a well-calibrated session. Prototype algorithm changes there first; on-hardware sim remains authoritative for timing.

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
- **Zero-feather CPM fix (20 Jul 2026, spec §16.12)** — pitch-fed `CadenceACF` (new `CadenceACF.h/.cpp`, ported from `visualisation/stroke_acf.py`) built into PadLog v8.10 / PadDis v8.14; payload's reserved pad byte becomes `cpm_source` (0=peak detector white, 1=ACF zero-feather fallback yellow `0x07FF`, 2=arbiter-suppressed `?? cpm`), payload size unchanged at 80 B. Offline acceptance test (`visualisation/stroke_zero_feather_regression.py`) PASSES both cases: 16 Jul zero-feather segment reports source=1 at 32.7 CPM (spec table: 32.8) for 100% of settled samples; 11 Jul padbad case (via the CSV's own recorded `cpm` vs a fresh pitch-ACF estimate, matching `stroke_acf.py`'s already-validated methodology) flags 100% disagreement, matching spec §16.9. Arbiter threshold fixed at the tested 30% (not the plan text's "~25%" approximation). **FLASHED 20 Jul 2026** (PadLog COM3, PadDis COM6) — now the deployed version on both units. **Bench PARTIALLY verified same day**: both sketches boot clean, ESPnow link solid (2004 packets received during PadDis's ~20 s splash window alone), payload struct/`cpm_source` decode confirmed correct via serial (`CPM: 0.0 (raw 0) (0.00 Hz) stroke=0 source=0` at idle). **Not verified**: CPM tracking against real paddle motion, the yellow zero-feather fallback, and absence of arbiter false-positives during normal paddling — the physical bench steps were cut short by a stuck Claude Code permission dialog (VS Code integrated terminal input bug, same class as anthropics/claude-code#72200) and the user chose to proceed straight to a field session instead of retrying the bench. **FIELD TEST PASSED 12 Aug 2026** — `visualisation/recordings/PadLog20260812.CSV` (header `PadDis v8.14 | PadLog v8.10`). On the PadViz-classified zero-feather section (sidecar frames 33470–50499, 171 s), the firmware's own recorded columns show `cpm_source=1` (ACF yellow) for **97.7%** of the section at recorded **cpm median 33.0** — the true cadence: pitch spectral truth ≈ 32.5 CPM while roll spectral read ≈ 65 (2× half-period ambiguity, the exact failure the fix targets). Offline sim over the same rows agrees (source=1 100% of settled samples, ACF median 32.8), matching the 16 Jul segment's 32.8. So the **yellow zero-feather fallback is field-confirmed**. The **white peak-detector path and the arbiter are also field-confirmed** on the same file's right-handed section (frames 65766–341749, 46 min): firmware `cpm_source=0` (white) 97.9% at cpm median 35.0 = roll/pitch spectral truth (35.0), and the **arbiter `?? cpm` (source=2) fired only 0.3%** — brief transient blips, no meaningful false-positive problem, so the 30% `ARBITER_DISAGREE_FRAC` is validated as-is. (Offline sim splits 61% white / 39% ACF-fallback vs the firmware's 98/2 — the known `stroke_detector_sim` Python-port timeout fidelity gap — but both paths still report ~35 CPM, so cadence is correct either way.) Note the sidecar calibration only affects the offline 3D view; `roll/pitch/stroke_count/cpm/cpm_source` are firmware values, so a wrong-for-section cal doesn't change detection. Both checks are now permanent regression cases — **tests 3 & 4 in `visualisation/stroke_zero_feather_regression.py`** (zero-feather field / white+arbiter field), which reuse `simulate()` + `stroke_spectral.spectral_rate` and **skip** if the git-ignored `recordings/PadLog20260812.CSV` is absent (suite: 4 passed, 0 failed, 0 skipped locally). `visualisation/recordings/*.CSV/*.csv` are now git-ignored. On-hardware 20-test sim suite additions also still needed (not blocking).
- **Phase 10** — Magnetometer calibration support: complete (9 Jul 2026, commit d8ce219). Coordinated release PadLog v8.8 / BoatLog v1.1 / PadDis v8.11 per spec §15.6. Enables `SH2_MAGNETIC_FIELD_CALIBRATED` at 10 Hz on both TX units, on-change `MAG_CAL:` serial, `sh2_saveDcdNow()` on first status=3. Payload struct grows: paddle 60→64 B (mag_cal + pad), boat 58→74 B (accel_x/y/z + mag_cal + pad — boat accel forwarding was previously read and discarded, spec §15.2.5 rider). New CSV columns: paddle gains `mag_cal`, boat gains `boat_accel_x/y/z,mag_cal`. PadDis SD paddle-log prefix renamed `ImuLog → PadLog`. Bench-verified 9 Jul 2026; T-41..T-46 hardware tests need cleaner mag environment or on-water session (see spec §15.7).
- **Visualisation (PadViz Processing sketches, spec `visualisation/specs/padviz6_spec.md`)** — separate strand from the firmware phases above; renders paddle/boat IMU CSVs offline. Lineage PadViz→…→PadViz6, all superseded but kept for reference. **PadViz8 is current** (v0.38, spec §15); **PadViz7** (v0.25, 12 Aug 2026, spec §14) is kept as the last-known-good and remains fully documented below. PadViz7 forked from PadViz6 v0.15, adds a guided F1 session-setup wizard (`Wizard.pde`, replacing `Checklist.pde`) and a sidecar Classification section (`Classification.pde` + `classification_sections` JSON) marking good right/left/zero-feather stretches and excluding ranges from the graph + all navigation. Reads the current v8.14 full-column CSVs (trailing `cpm_source` ignored positionally); backward-compatible with pre-v0.16 `.session.json` sidecars. **v0.17 (§14.5), reviewed on screen:** opaque grey wizard + Commands panels; scrollable Commands drop-down; file dialogs default to `visualisation/recordings/`; setup window hides overlays while shown; Slice 0 nudge step 5°→1°. **v0.18 (§14.6):** startup one-step saved-session loader (`J` at Step 1 → pick a `*.session.json` → loads paddle+boat+calibration+classification); stroke-average panel shows per-blade averaged entry→exit time + distance alongside the stroke count. **v0.19 (§14.7):** axis compass moved to the bottom-right corner (out of the Commands drop-down's path); stroke-average `o` toggle mirrors the right blade about the Y axis onto the left path to compare symmetry. **v0.20 (§14.8):** both side panels scale to fill the tall window — plot scale fitted to height (kayak length) not the narrow width (~1.5× bigger, kayak fills ~94% of height), larger fonts throughout. **v0.21–0.24 (§14.9): side-profile blade-immersion window + real paddle geometry (CONFIRMED on screen 7 & 12 Aug).** New full-window alternative view (screen-owning like the wizard, not an overlay), key **`x`** (wizard moved to **`w`**; F1/F2 rebound off the Fn-shifted function row, kept as alternates). Split horizontally into two boat ZY-plane side profiles: TOP left blade from port (bow left, **yellow**), BOTTOM right blade from starboard (bow right, **red**), **bow red on each**. **v0.24:** hull is now the **real 17 ft (5.1816 m) sea-kayak side outline** traced from `visualisation/seakayakside.svg` (Visio export), outline only, baked into `SideProfilePanel.HULL` (metres); its waterline sits a fixed **0.114 m (4.5 in)** above the keel on the blue mean-catch line, and the paddle shaft centre is placed **0.305 m (1 ft) forward** of the hull mid-point; the forward nose (`HULL[5..8]`) is filled red as the bow. Blade drawn as a **physical segment**: the **live blade shows only while immersed** (tip below waterline), and a **persistent band** accumulates the immersed part of the blade at every in-water frame up to the cursor (`drawImmersed`, stepped by 2) → a band of colour along the hull side (replaces v0.22's faint-at-each-deepest-point). Blue **waterline** referenced to the blade **tip** at catch; **fixed vertical scale** (no resize); footer = strokes / avg+max immersion depth; all metric. Paddle **total length + blade length** are session metadata (sidecar `paddle_total_length_m`/`blade_length_m`, shown in Detail panel), entered via an in-sketch numeric prompt (**`m`**, or on `C` build) that **pre-fills the last-used values** (persisted to `paddle_dims.json`); they scale the **3D paddle model** to the real length (`paddle60.obj` native 1.8182 m) and the **side-view blade** geometry — the catch **detector is untouched**. New `SideProfilePanel.pde` + `CatchEvents.bladeSegmentYZ/bladeTipZ/bladePointYZ`, `Model3D.drawPaddle(totalLenM)`. **v0.25 (§14.10, CONFIRMED on screen 12 Aug):** clickable **view-switch tabs** (`Tabs.pde`, top-right, `3D VIEW` / `SIDE PROFILE`) alongside the `x` key — both route through one shared `showSideProfile(boolean)` helper so key/mouse stay in sync; hidden during the wizard, menu drop-down wins; docked in the constant ~230px gap left of the right panel, compact (`TAB_W=70`) with per-label font auto-fit; room reserved for a future track-plot tab. Same release: the top-right floating **axis-definition legend** (`+X/+Y/+Z`) moved **into the Detail box** (`drawAxisDefs()`), so it only shows when Detail is open and no longer sits under the title. `PadViz7.pde` now carries a **LAST EDITED banner + title-bar `BUILD_STAMP`** (version visible at a glance). **BUILT + compiles clean** via `processing-java --build` (Processing 4.3). **Classification fully confirmed on screen 23 Jul** — all four types incl. the `d/D` exclude (section cut from graph, stays excluded on reload). **Calibration methodology flagged to revisit** (spec §14.6): a 1° yaw-datum nudge is visibly significant, so the rest-pose hold is more sensitive than the accel-rest-window procedure assumes. Build: `"/c/Program Files/processing-4.3/processing-java.exe" --sketch=<abs>/visualisation/PadViz7 --build`. **PadViz8 (v0.26, current, spec §15, 12 Aug 2026)** forks PadViz7 v0.25 (user asked for a separate sketch so the working PadViz7 stays intact through the network-fetch change): adds a **third full-window view — the Track window** (`TrackPanel.pde`, key **`t`** + a **TRACK** tab) drawing the whole boat GPS track (CSV lat/lon) georeferenced over an **OpenStreetMap** street backdrop — Web-Mercator projected, tiles fetched on a background daemon thread and disk-cached under `visualisation/PadViz8/tilecache/` (git-ignored), fetched via `HttpURLConnection` with a descriptive User-Agent + `© OpenStreetMap contributors` attribution; overlays = orange track, green start / red end / blue live-position dot, scale bar, north arrow. View selection refactored to a single `viewMode` (0=3D/1=SIDE/2=TRACK) behind one `showView(int)` helper shared by the `x`/`t` keys, Tabs bar, and Commands menu. Same release **fixed the side-profile persistence bug** (§15.3): the immersion band re-anchors its restart point to the cursor when the cursor moves behind it, so "restart, then replay from an earlier frame" rebuilds the band. **Track view + band fix both CONFIRMED on screen 12 Aug 2026.** **v0.27–0.28 (spec §15.5, 12 Aug 2026): calibration + classification made re-runnable after setup.** The wizard was a one-shot flow that reopened read-only once complete (`r/R` "did nothing", `w` just showed calibration numbers), so there was no live way to recalibrate the paddle or re-exclude a long file. **v0.28:** `w` on a completed session now reopens the wizard **live at Step 3** (recalibrate → reclassify) — 3b/4b show saved values with `Return`=keep / `r/R`=reset, graph stays zoom/scrub-able underneath (right-click zoom works), auto-switches to Slice A if in Slice 0. **Recalibration now preserves classification** (independent of roll cal; carried onto the rebuilt sidecar from the current sidecar or a stash set by the Step-3 reset) so "exclude drive-home, then recalibrate" keeps the exclusion. Standalone **`q`** (v0.27, CLASSIFICATION menu group) wipes all classification from any slice — now **single-press** in v0.28 (the v0.27 two-press confirm was confusing) — roll cal untouched. **v0.30 (spec §15.6): Track view clips to the paddling session** (supersedes v0.29's exclusion-only filter, which couldn't remove the paddle-less drive tail — the boat GPS keeps logging through the drive home after the paddle unit stops, so the drive has no paddle frames to classify). `TrackPanel.rescan` keeps a boat fix only if it falls in a run of NON-excluded paddle coverage (`keepBoat[]` mask; excluded paddle frame or paddle-file end closes a run, unmapped-but-non-excluded frame skipped) → drops the drive-home tail + any EXCLUDED middle range + boat-only lead-in; auto-zoom bounds from kept fixes so the map frames the paddling area; footer "(clipped to paddling session)"; boat-only sessions and broken-sync fall back to show-all. `rebuildSync()` + `rebuildClassificationIndex()` both call `trackView.invalidate()` so it re-filters when the paddle CSV loads after the boat or classification changes. NOTE: map now shows the track only where the paddle recorded — if the paddle logged the drive too, mark it EXCLUDED to drop it. **v0.31 (spec §15.7): wizard Step-4 `e/E` = "exclude from cursor to end of file (inclusive)"** — one-key drop of a drive-home tail without landing the end mark on the last frame (fixes the reported "left out the very last data point → tail still drawn"); works in 4a marking + 4b review, rejects only on overlap (`Wizard.excludeCursorToEnd()`). **CONFIRMED on screen 12 Aug 2026 ("excluded the tail, drive-home is gone from the map") — proves `e` exclude-cursor→end + sidecar save + the v0.30 Track clip end-to-end.** Still to confirm: v0.28 wizard re-entry/recalibration, single-press `q`. **v0.32 (spec §15.8, 14 Aug 2026): side-profile key `f` mirrors the TOP (left-blade) half so its bow sits on the right**, matching the bottom (right-blade) half for a same-way-round left/right comparison (only that half's draw direction `yDir`/title flips — geometry, waterline, band and stats unchanged; right-blade half untouched; toggles back; gated to `viewMode==1`). `SideProfilePanel.leftBowRight`/`toggleLeftBow()` + `f/F` branch in `keyPressed()` + Commands-menu row. CONFIRMED on screen. **v0.33 (spec §15.9, 14 Aug 2026): red bow triangle** added at the bow tip of the kayak outline in the two top-down blade panels (`EntryExitPanel` "Blade entry/exit" + `StrokeAveragePanel` "Blade path (avg)") — orientation cue only, plotted data unchanged; sized 24×26 px (doubled after an on-screen check), CONFIRMED on screen. **v0.34 (spec §15.10, 14 Aug 2026): per-session feather angle re-angles the 3D model's left blade.** Signed `feather_deg` stored in the sidecar + `paddle_dims.json`, entered as a 3rd step in the `m` prompt (+ right / − left / 0 straight, ±90° clamp); shown in the Detail box. `Model3D` indexes the mesh's left half (X<0) at load and `setFeather()` rotates it about the shaft X-axis by `(deg−60)×FEATHER_SIGN` with **FEATHER_SIGN=−1** (fixed from OBJ geometry: as-built left blade = −58.5°, so 0=flat/coplanar, +60=as-built right, −60=left mirror; the shaft is a perfect circle at X=0 so the twist is seamless). Loading a session now seeds last-used length/blade/feather so recalibration preserves them. Feather 0 & +60 confirmed on screen; −60 proven by offline render + geometry, real left-handed field data pending (no recording currently has a `left` classification). Detector/side-view/top-down panels untouched. **v0.35 (spec §15.11, 30 Aug 2026): sidecar "no accelerometer data" false-negative fix.** `buildSidecar()` decided a log had no accel by sniffing **frame 0's values**, but row 0 of every full-column log is legitimately `0,0,0` (the startup frame before the BNO085's first accel sample), so a valid full-column CSV (30 Aug field session) was wrongly rejected and the sidecar never built. Fix: `DataSource.hasAccel` flag detected from the header (`contains("accel_x")`, like `hasRxMs`/`hasGrv`); `buildSidecar()` tests `!pad.hasAccel`. (Same session's "boat not graphed" was NOT a bug — the strip-chart slots default to Pad roll/yaw/CPM; boat channels are in each slot's dropdown.) **v0.36 (spec §15.12, 30 Aug 2026): `y`/`Y` toggle for the relative-yaw orientation source (GRV ⇄ fused) in Slice C + `CatchEvents`.** On a 30 Aug jig session (paddle-unit X ∥ boat X, both Y forward) Slice C showed the paddle ~45° off in the XY plane and not rolling about its shaft. Root cause: GRV (auto-selected per §16.11) has no magnetic yaw lock, so the two units' yaw estimates drift apart over a session (offline: paddle-vs-boat rest yaw = 3° fused vs 78° GRV — the jig alignment was physically correct; over the paddling section GRV added ~72° of wandering shaft-swing that both was the 45° error and swamped the roll). No universal winner (GRV wins in a bad mag environment, fused in a well-calibrated one), so the source is now operator-selectable: global `orientMode` (ORIENT_GRV default / ORIENT_FUSED) gates both consumers via `useGrvActive(padHasGrv,boatHasGrv)`; key **`y`/`Y`** toggles it (gated `sliceMode != 0` so Slice-0 model-cal `y` is untouched; `v` is the camera preset), rebuilds `CatchEvents`, and updates the Slice-C HUD source line. Default behaviour unchanged; Slice A/B stay fused-only. **v0.36 CONFIRMED on screen 30 Aug 2026** — pressing `y` in Slice C on the 30 Aug jig session squared the paddle up in the XY plane and restored shaft roll (fused); setting the session feather to +60 via `m` (it had inherited −60 from the 14 Aug test) fixed the zero-feather-looking display. Caveat surfaced same session (recorded in spec §15.12): with yaw fixed, the entry/exit traces show the left blade entering further forward than the right, but that fore/aft placement is derived from relative orientation + assumed arm/geometry constants (paddle-centre translation is unobservable from two IMUs, functional_spec §8.1/§8.1.1), so a few-degrees L/R yaw-zero difference can produce it — treat the asymmetry as indicative, not measured, pending the kinematic-model check. **v0.37 (spec §15.13, 30 Aug 2026): paddle-dimension review screen before sidecar build.** The `m`/`C` dimension prompt now opens on a **review screen** (`dimStage==4`, `drawDimReview()`) listing the last-used total length / blade length / feather (handedness spelled out) with **`A`/Enter = accept all**, **`E` = edit** (drops into the existing stage 1→2→3 per-field editor), **Esc = cancel** — so a new session sidecar can no longer silently inherit the previous paddle's geometry (which had let a stale −60° feather from the 14 Aug left-blade test attach to the right-handed 30 Aug session). Accept and edit both end in `applyPaddleDims()`; nothing else in the persist/rebuild path changed. Compiles clean; on-screen confirmation pending. **v0.38 (spec §15.14, 30 Aug 2026): paddle dimensions folded into the setup wizard as a new Step 3.** The v0.37 review still lived only on `m`/`C` — the wizard never asked for dimensions, so a guided session inherited the previous paddle's geometry silently (user: "this is where I want that section so all set up is done as the files are loaded"). Wizard grows 5→6 steps: paddle → boat → **dimensions (3)** → calibration (4) → classification (5) → done (6). Step 3 shows the last-used total/blade/feather inline (handedness spelled out) with `Return`/`A` = accept, `E` = edit (opens the per-field editor via `beginDimPromptEdit(true)`, skipping the review screen; on finish `dimComplete()`→`wizard.dimsAccepted()` advances to Step 4). Placed *before* the calibration build so the sidecar is built already carrying the confirmed geometry. `C`/`m` unchanged; the `J` saved-session loader and `w`-reopen skip Step 3 (session already carries dims; reopen is the recalibrate→reclassify path). Renames: `enterStep4`→`enterClassify`, `gotoStep5`→`gotoDone`, `handleKeyStep4`→`handleKeyStep5`, + `dimsAccepted()`/`drawStep3Dims()`/`dimFromWizard`. **CONFIRMED on screen 30 Aug 2026** (user: "paddle dimensions in proper place"). NOTE: the **30 Aug 2026 session (`PadLog20260830.CSV`/`BoatLog20260830.CSV`) IS the well-calibrated forward-paddling session** (the user did the elaborate clip-on-jig calibration at its start) — this is the file for the parked kinematic-model position-estimate examination (functional_spec §8.1.1). Build: `--sketch=<abs>/visualisation/PadViz8`. Offline algorithm toolkit is the separate `visualisation/stroke_*.py` scripts (see Simulation Test section).

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

## Generated-artifact provenance

Whenever you produce a **report** (a doc/write-up/spec-style file) or an **image/figure**, record its origin so it can never be misattributed later:

1. Add a row to `PROVENANCE.md` (repo root): date, artifact path(s), **produced by**, one-line note. "Produced by" is the concrete actor — the emitting script for a figure (e.g. `stroke_foo.py`), or the model name + "(Claude Code session)" for a doc an agent wrote directly.
2. Where practical, stamp the artifact itself: a short provenance footer line in docs; for figures, ensure the emitting script is named in the surrounding text/log.
3. When a report merely **references or embeds** existing images, say so explicitly and do **not** imply you generated them. If an artifact's origin is unknown (e.g. a pre-existing file), record "unknown / not recorded" rather than guessing.

This convention exists because analysis PNGs produced by an earlier `stroke_*.py` run were nearly misattributed to the agent that only referenced them (21 Jul 2026).

## Git

Commit and push to `origin/main` (GitHub) after each meaningful change with a descriptive commit message.
