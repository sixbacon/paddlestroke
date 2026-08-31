# PadViz6 — Disciplined Orientation Specification

**Version:** 0.38
**Date:** 2026-07-21
**Status:** v0.39 (31 Aug 2026, §15.15) fixes the bottom-graph aliasing when the whole trace is shown — the strip now draws a **min/max amplitude envelope** (solid bands) when there are more samples than pixels and reverts to the detail line on zoom-in; **CONFIRMED on screen**. — v0.38 (30 Aug 2026, §15.14) folds the paddle-dimension review into the **setup wizard** as a new **Step 3** (paddle → boat → **dimensions** → calibration → classification → done), so a guided session sets the paddle geometry as the files are loaded instead of leaving it to a separate `m`; placed before the calibration build so the sidecar is built already carrying the confirmed geometry. **CONFIRMED on screen.** — v0.37 (30 Aug 2026, §15.13) makes the paddle-dimension prompt open on a **review screen** — it lists the last-used total length / blade length / feather (with handedness spelled out) and asks the operator to **accept all** or **edit**, so a new session sidecar can no longer silently inherit the previous paddle's geometry (which had let a stale −60° feather from a 14 Aug test attach to a right-handed 30 Aug session). Compiles clean; on-screen confirmation pending. — v0.36 (30 Aug 2026, §15.12) adds a **`y`/`Y` toggle for the relative-yaw orientation source** (GRV ⇄ fused) in Slice C + `CatchEvents`: GRV has no magnetic yaw lock so the two units' yaw estimates drift apart over a session (30 Aug jig session: fused rest alignment 3° vs GRV 78°), making a well-mag-calibrated session read cleaner under fused — no universal winner, so the source is operator-selectable. **CONFIRMED on screen** (fused squared the paddle up and restored shaft roll). — v0.35 (30 Aug 2026, §15.11) fixes a sidecar **"no accelerometer data" false-negative** — `buildSidecar()` sniffed frame 0's accel, but row 0 of every full-column log is legitimately `0,0,0`, so a valid full log was wrongly rejected; the check now uses a `DataSource.hasAccel` flag read from the header. — v0.34 (14 Aug 2026, §15.10) makes the **paddle feather angle a per-session property** (signed `feather_deg` in the sidecar + `paddle_dims.json`, entered as a 3rd step in the `m` prompt: + right-handed / − left-handed / 0 straight) and **re-angles the 3D model's left (yellow) blade** to match by rotating the mesh's left half about the shaft. Feather 0 and +60 confirmed on screen; −60 proven by offline render + geometry, real left-handed field data pending. — v0.33 (14 Aug 2026, §15.9) adds a **red bow triangle** to the two top-down blade panels (**Blade entry/exit** and **Blade path (avg)**) at the bow tip of the kayak outline, so the boat's front is unambiguous — orientation cue only, no change to plotted data. CONFIRMED on screen. — v0.32 (14 Aug 2026, §15.8) adds a side-profile key **`f`** that mirrors the TOP (left-blade) half so its bow sits on the **right**, matching the bottom (right-blade) half for a same-way-round left/right comparison — geometry unchanged, right-blade half untouched, gated to the side-profile view. CONFIRMED on screen. — v0.31 (12 Aug 2026, §15.7) adds a wizard Step-4 **`e/E` = "exclude from the cursor to the end of the file (inclusive)"** — a one-key way to drop a drive-home tail without having to land the end mark on the very last frame (the leftover last points had been staying "valid" and drawn on the Track map). Works in both the 4a marking and 4b review sub-steps; rejects only on overlap. — v0.30 (12 Aug 2026, §15.6) makes the PadViz8 **Track view clip to the paddling session**: the boat GPS often keeps logging through the drive home after the paddle unit stops, so the drive appears with no paddle frames behind it and classification alone can't remove it. The Track view now keeps a boat fix only if it falls in a run of NON-excluded paddle coverage (mapped via SyncMap) — dropping the drive-home tail, any EXCLUDED middle range, and a boat-only lead-in — and auto-zooms to the kept fixes. Supersedes v0.29's exclusion-only filter (which couldn't touch the paddle-less drive tail). Boat-only sessions (no paddle) are unchanged. — v0.28 (12 Aug 2026, §15.5) makes PadViz8 calibration + classification **re-runnable** after setup: pressing **`w`** on a completed session now reopens the wizard **live at Step 3** (recalibrate → reclassify), not the old dead read-only summary — so `r/R` (reset & recalibrate / reclassify) works again and a long file can be re-processed. Recalibration now **preserves classification** (the two are independent), so "exclude the drive-home, then recalibrate" keeps the exclusion. The standalone clear-classification key `q` is now **single-press** (was a two-press confirm — the user found it confusing). — v0.27 (12 Aug 2026) added the standalone `q` key + CLASSIFICATION menu group. — v0.26 (12 Aug 2026, §15) forks a **new sketch `PadViz8/`** from PadViz7 v0.25 — adds a third full-window view, the **Track window** (`TrackPanel.pde`, key **`t`** + a **TRACK** tab): the whole GPS track (boat CSV lat/lon) drawn georeferenced over an **OpenStreetMap** street backdrop, Web-Mercator projected, tiles fetched on a background thread and disk-cached. View selection refactored to a single `viewMode` (0=3D / 1=SIDE / 2=TRACK) behind one `showView(int)` helper. **Track view CONFIRMED on screen** (loads a boat CSV, draws the track over the OSM map). Same release fixes a **side-profile persistence bug**: the immersion band re-anchors its restart point to the cursor when the cursor moves behind it, so "restart, then replay from an earlier frame" rebuilds the band instead of showing nothing — **CONFIRMED on screen 12 Aug**. PadViz7 left untouched at v0.25. — v0.23 (7 Aug 2026, §14.9) — **real paddle geometry** is now session metadata: paddle **total length** + **blade length** stored in the sidecar (`paddle_total_length_m` / `blade_length_m`), shown in the Detail panel, entered via an in-sketch numeric prompt (**`m`**, or on `C` build) that **pre-fills the last-used values** (persisted to `paddle_dims.json`). These scale the **3D paddle model** to the real length (`paddle60.obj` native 1.8182 m) and the **side-view blade** (`visBladeCentreM`/`visBladeLenM`); the catch detector is untouched. **Side-profile window CONFIRMED on screen** (`x` opens it, `m` opens the prompt). — v0.22 (7 Aug 2026) — side-profile reworked to a **blade-immersion** view: blade drawn as a **segment** (red right / yellow left) live + faint-per-stroke-deepest; **blue waterline** referenced to the blade **tip** (`bladeTipZ`); **fixed vertical scale** (no more resize). Window keys rebound off Fn-shifted F1/F2 to **`w`** (wizard) / **`x`** (side profile), F1/F2 kept as alternates. `PadViz7.pde` gained a `LAST EDITED` banner + title-bar `BUILD_STAMP`. — v0.21 — first cut of the side-profile window: two boat **ZY**-plane profiles, bow red on each; drew tip arcs + a data-fitted scale (both replaced in v0.22). — v0.20 (23 Jul 2026, §14.8) — both side panels (`EntryExitPanel`, `StrokeAveragePanel`) now scale to fill the tall panel: plot scale fitted to the plot **height** (kayak length) instead of the narrow panel width, so the kayak fills ~94% of the height (was ~59%) — a ~1.5× enlargement bounded by keeping the whole kayak in view — with larger fonts throughout. — v0.19 (23 Jul 2026, §14.7) — axis compass moved to the bottom-**right** corner (out of the Commands drop-down's path — the drop-down still doesn't reliably occlude it in P3D), and a stroke-average **symmetry overlay**: `o` mirrors the right blade path about the Y (fore-aft) axis and overlays it on the left, so left/right asymmetry reads as a gap between the two curves. — v0.18 (23 Jul 2026, §14.6) — startup one-step **saved-session loader** (`J` at wizard Step 1 when `visualisation/recordings/` holds any `*.session.json` — picks one JSON and loads paddle CSV + boat CSV + calibration + classification in a single step) and **stroke-average panel metrics** (right-hand panel now shows, per blade, the averaged entry→exit time and straight-line distance alongside the stroke count). Classification incl. the `d/D` exclude path is now **confirmed working on screen** (excluded section cut from the graph and stayed excluded on reload). **Calibration methodology flagged for revisit** — a 1° yaw-datum nudge is visibly significant, so the rest-pose hold (paddle exactly along the kayak axis) is more sensitive than the current accel-rest-window procedure assumes (§7 note). — v0.17 (23 Jul 2026, §14.5) — UI polish on PadViz7, reviewed on screen (user: "better"): opaque grey backgrounds on the setup wizard + Commands drop-down; the Commands list is now height-capped and scrollable (slide bar + wheel + track paging) so it no longer runs off the page; file-open dialogs default to `visualisation/recordings/`; the setup/summary window hides the 3D scene + analysis overlays (side panels, HUD/detail box, axis compass + legend) while shown so it presents cleanly on a plain background (graph strip stays for cursor positioning); Slice 0 nudge default step 5°→1° for finer rest-pose correction. — v0.16 (21 Jul 2026, §14) forks a **new sketch `PadViz7/`** from PadViz6 v0.15 — guided 5-step session-setup wizard (`Wizard.pde`, replacing `Checklist.pde`) plus a Classification Section in the sidecar (`Classification.pde` + `classification_sections` JSON, §7.5) recording good right/left/zero-feather stretches and excluding ranges from the graph + all navigation. BUILT + compiles clean; on-screen walkthrough pending (§14.4). PadViz6 left untouched at v0.15. — v0.15 ACCEPTED 20 Jul 2026 ("that is enough on visualisation for this session, it is doing what I want for now" — §13.9). §13.7: four field-use fixes from the user's on-screen check of v0.14 — pitch nudge moved off the double-bound `p`/`P` to `i`/`I`; playback speed multiplier (`>` doubles, `<` resets to x1); entry/exit panel right-click clears accumulated dots; entry/exit yaw-datum manual override (`n`/`N` nudge, `g` reset, shown in Slice 0, saved in the sidecar) as an explicit stop-gap for a ~30° automatic-datum error found on replay; Slice C paddle base position moved +0.45 m toward the bow (measured average paddle-centre offset from boat centre). Slices 0–C + bottom GraphPanel with two-click zoom (right-click), double-right-click revert, `S`-key zoom reset, and merged CSV export (curated + all-fields). Corner axis compass (2D, ~1/3 the old on-screen size) with a `P`/`K`/`W` frame letter that also acts as the slice-switch shortcut. §7 expanded (v0.7) from single yaw-alignment rotation to a three-offset per-session procedure — sensor-mount roll/pitch (from accel) + magnetic-yaw datum (from mean quats) — with pre-session magnetometer figure-8 and DCD save. Requires three firmware additions listed in §7.8 (formalised in firmware spec §15, v2.7). v0.8: the three 8 Jul 2026 field-use notes (§12.10) are now DONE — `k`/`u` HUD flash, Slice B hint to `W`, and Backspace/`-` back-slice ping-pong. v0.9: free-orbit camera — left-drag orbits, wheel zooms, V snaps to side/top preset; 2D axis compass now rotates in step with the 3D camera basis. v0.10: first-pass session sidecar builder (`Sidecar.pde`, C key) — rest-window detector + mean-based mount offsets + yaw datum + JSON save per §7.5. Slice-switch letter shortcuts P/K/W dropped (Caps-Lock case ambiguity); digits 0/1/2/3 only. v0.11: startup onboarding checklist (`Checklist.pde`) in the bottom strip when no paddle CSV is loaded — three rows auto-ticked and clickable. v0.12: sidecar auto-load — on paddle-CSV open, look for a sibling `<basename>.session.json`, parse it, and reseed rest-window references so the correction is active without pressing C. Third checklist row auto-ticks in that case; boat CSV load extends the seeding to the boat side. v0.13 (9 Jul 2026): three field-use fixes driven by the 9 Jul session — (a) C-key rest-window search now starts at the current playback frame (was frame 0), so the user can seek to the intended still moment before building; (b) checklist strip hides as soon as the paddle CSV loads (was blocking the graph until sidecar built), and a yellow "SIDECAR not built — seek then press C" HUD hint appears in its place; (c) `DataSource.computePaddleCentreMotion` — accel double-integration with a three-stage HPF cascade (fc ≈ 0.3 Hz) drives a per-frame paddle-centre offset (±0.3 m clamped) that translates the mesh in Slices A + C during render, so the shaft midpoint visibly swings with the stroke. v0.14 (17 Jul 2026, §13): startup checklist becomes a floating overlay above the graph strip (graph appears on paddle-CSV load, overlay stays through seek-and-`C`); left key-list HUD replaced by a Commands pull-down menu; new `CatchEvents.pde` offline blade entry/exit detector (port of firmware spec §13.5 feasibility method); new `EntryExitPanel.pde` — left 20 % boat-frame top-down scatter of entry/exit points, red = right blade, green = left, filled = entry, hollow = exit, accumulating with playback.

---

## 1. Purpose

A fresh Processing 4.x visualiser that renders paddle and boat IMU data under an explicit,
documented frame-conversion discipline. PadViz4/5/5b accumulated empirical corrections
(`scale(-1,1,1)`, `corrZ = 180`, axis-cycle keys, nudge-by-5° keys) trying to make
orientation "look right." The 3 Jul 2026 field data revealed that the residual symptoms
were mirror-symmetric — determinant −1 — and cannot be represented by any rotation. All
prior tuning was chasing the wrong model. PadViz6 restarts the orientation model from first
principles and enforces one hard rule: **no correction without a documented physical reason.**

**Two documented physical reasons are recognised:**

1. **Frame chirality mismatch.** Sensor and OBJ model are left-handed; Processing world
   is right-handed. Requires a single fixed mirror (see §3).
2. **OBJ drawing convention.** The paddle `.obj` was drawn in Blender by a human, and its
   rest pose in Blender's own local coordinates may not align with the paddle-IMU axis
   convention (§2). This is a fact about the artwork, not the physics of paddling. It
   requires a **one-time static** yaw/pitch/roll offset baked into the model at load time,
   determined interactively against a calibration data set and captured to a config file
   (see §4). Once captured, the values do not change between sessions and are not
   adjustable at runtime.

Both corrections are load-time only. Per-session runtime tweaking — the failure mode of
PadViz3/4/5/5b — remains prohibited (see §9).

This spec supersedes the "PadViz5" flow in the main visualisation spec (§16) for all new
orientation code. PadViz5b remains the current tool for graph/export work until PadViz6 is
built and its render matches or exceeds PadViz5b's.

---

## 2. Frame Conventions

By project convention:

| Frame | Chirality | Axes |
|-------|-----------|------|
| Paddle IMU (BNO085 as mounted) | **Left-handed** | +X = shaft toward right blade; +Y = blade-normal; +Z = in-blade |
| Boat IMU (BNO085 as mounted) | **Left-handed** | +X = starboard; +Y = forward; +Z = up |
| Paddle `.obj` model | **Left-handed** | Matches paddle-IMU axes |
| Processing world (P3D) | **Right-handed** | +X = right; +Y = down (default) or up (after camera); +Z per right-hand rule |

The handedness mismatch between the sensor/model side (LH) and the render side (RH) is a
mirror. Mirrors have determinant −1. A rotation has determinant +1. A rotation cannot cancel
a mirror. Any visualiser that fails to make this bridge explicit will need "empirical
corrections" to hide the mismatch, and those corrections will disagree between test data
sets — as observed in PadViz3 through PadViz5b.

---

## 3. The Two Fixed Corrections

Two pre-rotations are permitted in the production render path. Both are fixed at build
time (values live in config, not in variables that runtime input can mutate). Both are
applied outermost-inward, before any quaternion rotation.

### 3.1 Handedness bridge (§2 chirality mismatch)

```java
pushMatrix();
scale(1, 1, -1);          // ← handedness bridge: worldRH ← paddleLH  (flip Z, keep X, Y)
// … model calibration rotation next …
// … then apply data quaternion …
// … then draw model …
popMatrix();
```

**Why `scale(1, 1, -1)` and not one of the other two candidates?**
All three (`(-1,1,1)`, `(1,-1,1)`, `(1,1,-1)`) are physically valid — any single axis flip
converts a right-handed frame to a left-handed one. The choice matters only for the shared
mental model. `(1, 1, -1)` was locked in on 6 Jul 2026 because it leaves both horizontal
axes untouched, so on-screen +X remains starboard/right-blade and on-screen +Y remains
forward/blade-normal without further reasoning.

### 3.2 Paddle model calibration (§1 OBJ drawing convention)

An intrinsic ZYX Euler triple `(modelYaw, modelPitch, modelRoll)` in degrees, applied to
the OBJ model *after* the handedness flip and *before* the data quaternion:

```java
pushMatrix();
scale(1, 1, -1);                                 // handedness bridge
rotateZ(radians(modelYaw));                      // model calibration ZYX ─┐
rotateY(radians(modelPitch));                    //                        ├─ Blender→sensor
rotateX(radians(modelRoll));                     //                        ┘
applyQuat(canvas, qImu);                         // sensor data
drawPaddle();
popMatrix();
```

Values come from the file `data/model_calibration.json`, loaded once at sketch start.
They are determined interactively in **Slice 0 — Paddle Model Calibration** (§4) using
a designated calibration data set, then written to the JSON. After Slice 0 has run once
and produced a validated triple, that triple is treated as an immutable model constant.

**Rule.** All three components live in the config file, not in code constants. If the
model file is ever re-exported from Blender with a different rest pose, Slice 0 is re-run
and the JSON is updated. No PadViz3-style axis-cycle key ever appears in production render
mode.

**Rule.** The scale is applied **outside** the quaternion rotation. Never inside. Never
combined into a modified quaternion at load time (this hides the mirror in the data
pipeline and makes the frame convention invisible to anyone reading `Model3D.pde`).

---

## 4. Slices

Slices are built in order. Each passes its acceptance test before the next begins. **A
slice that fails its acceptance test is not fixed by adding rotations to the sketch** — it
is diagnosed as one of: missing/wrong model calibration (fixed once by re-running Slice 0),
missing documented mount rotation (fixed by adding it at load with a source comment), or a
physical mounting issue in the source data (fixed by remounting, not in software).

### 4.0 Slice 0 — Paddle Model Calibration (must run first)

Slice 0 is a **one-time interactive tool**, run against a designated calibration data set,
that produces the model-calibration Euler triple used by Slices A/B/C. Once its output is
written to `data/model_calibration.json`, Slice 0 is not run again unless the OBJ file is
re-exported from Blender.

**Camera.** Fixed side-on. Camera at `(0, +D, 0)` in Processing world coords (looking along
`-Y` toward the origin), at the same Z altitude as the geometric centre of the paddle
model (Z = 0 after handedness flip if the OBJ centre is at model origin). Distance `D` is
chosen so the whole paddle is visible with margin. No mouse orbit, no zoom, no camera keys
active in calibration mode — the camera is deliberately fixed so that the visual reference
frame is unambiguous.

**What is drawn.**

1. World axes at the origin (X = red, Y = green, Z = blue, length ~1.5 × paddle half-length).
   Labels `+X`, `+Y`, `+Z` at the axis tips.
2. The handedness-flip block applied.
3. The current `(modelYaw, modelPitch, modelRoll)` applied to the model.
4. **No data quaternion applied** — the model is drawn in its calibration rest pose.
5. The paddle model, with the 7 Jul 2026 blade colour split (yellow left, red right).
6. A reference "expected" wireframe in a distinct colour (cyan, for example) at a fixed
   pose corresponding to how the paddle should look for the loaded calibration frame:
   shaft along +X, blade normals along +Y, in-blade direction +Z. This is the target the
   Slice 0 operator matches the paddle to.

**Data source.** A calibration CSV recorded specifically for this purpose: the paddle
held in a known rest pose (e.g. shaft horizontal along starboard, blades vertical,
paddle-IMU Y axis pointing to the sky). The mean quaternion over a stable window is
computed and stored in the JSON as `calibration_pose_quat`. During Slice 0 rendering,
that mean quaternion is **not** applied — the model is shown at the identity, and the
operator's task is to align the OBJ mesh (in its Blender frame) with the sensor axes.

**Interactive controls (Slice 0 mode only).**

| Key | Action |
|-----|--------|
| `Y` / `Shift+Y` | Adjust `modelYaw` by +5° / −5° |
| `P` / `Shift+P` | Adjust `modelPitch` by +5° / −5° |
| `R` / `Shift+R` | Adjust `modelRoll` by +5° / −5° |
| `[` / `]` | Fine adjust: change step size ÷2 / ×2 (default step 5°, min 0.1°, max 45°) |
| `Z` | Zero all three (reset to `0, 0, 0`) |
| `S` | Save current triple to `data/model_calibration.json` |
| `L` | Print current settings to the console in a paste-ready block (see below) |

**HUD (Slice 0 mode).**

```
SLICE 0 — MODEL CALIBRATION
calibration file:  <path>
current pose:      modelYaw =  90.0°   modelPitch =   0.0°   modelRoll = 180.0°
step size:         5.0°
save target:       data/model_calibration.json
[Y/P/R] adjust  [[/]] step size  [Z] zero  [S] save  [L] print block
```

**Console listing on `L`.**

```
// PadViz6 paddle model calibration — 2026-07-15
// Source: data/PaddleCal_20260715.csv, frames 250–450
{
  "model_yaw_deg":   90.0,
  "model_pitch_deg":  0.0,
  "model_roll_deg": 180.0
}
```

**Acceptance test.** With the operator satisfied that the yellow blade is on the −X side
of the world axes, the red blade on the +X side, blade normals along +Y, and the shaft
lying in the XY plane at the same Z as the world origin, the current triple is saved
with `S`. Slice A is then run against the same calibration CSV: with the mean calibration
quaternion applied to the model at rest, the paddle should render identical to the Slice 0
target pose. If not, Slice 0 is re-opened and the triple refined.

**Discipline note.** The `Y`/`P`/`R` keys are the *only* runtime-mutable rotation keys in
PadViz6, and they are active only in Slice 0 mode. In Slices A/B/C the same keys are
either unbound or bound to non-rotation actions (see §6). This is the one carve-out from
the "no runtime tweaking" rule, justified by the one-time calibration nature and the
config-file capture.

### 4.1 Slice A — paddle only

**Scope.** Load a paddle CSV. Draw `paddle60.obj` at the world origin, rotated by the raw
quaternion `(qw, qx, qy, qz)` inside the handedness-flip block. No translation, no bobbing,
no yaw-tracking camera. Fixed world camera looking down `−Z`.

**Data.** Any paddle CSV parseable by the existing PadViz5b `DataSource.pde` (17-col v8.10
with `rx_ms` preferred; 6/10/15/16/17-col also accepted for backwards compat).

**HUD.** Frame index, `rx_ms`, and raw `qw / qx / qy / qz` + `roll / pitch / yaw`.

**Rest-pose test.** Load a CSV recorded from a stationary "blades horizontal, shaft
horizontal" hold. Advance to a frame inside that hold. On screen: paddle level, yellow blade
on left, red blade on right (see main spec §15). **If it does not match:** the paddle
sensor mount does not match the LH paddle-IMU convention above. Add a named body-frame
rotation `qMountPaddle` to the load pipeline (not the render pipeline) and document the
physical measurement that justifies its value. Do **not** tweak until it looks right.

### 4.2 Slice B — kayak only

**Scope.** Load a boat CSV. Draw a simple procedural kayak (box or minimal OBJ) at the
origin, rotated by `kayak_qw..qz` inside the handedness-flip block. Same fixed camera.

**HUD.** GPS UTC, `rx_ms`, `speed_ms`, `gps_cog_deg`, raw kayak quaternion + Euler.

**Rest-pose tests.**
1. Boat stationary and level → screen shows level kayak, deck upward, cockpit visible.
2. Boat moving under way with GPS fix → the on-screen bow points along the direction
   corresponding to `gps_cog_deg`. A COG of 90° in the data must map to a specific,
   documented on-screen compass direction (write the mapping in the HUD).

**If either fails:** the boat sensor mount does not match the LH boat-IMU convention above.
See main spec §6.2.1 for the reference orientation (X = starboard, Y = forward, Z = up)
and §6.2.1's 3 Jul 2026 correction (Q ⊗ (0,1,0,0)) as an example of a documented mount
correction — not as a template to blindly apply.

### 4.3 Slice C — combined

**Scope.** Both objects in the same scene. The paddle rotates *relative to the kayak*:

```java
pushMatrix();
scale(1, 1, -1);                 // handedness bridge
applyQuat(canvas, qKayak);       // worldRH ← kayakLH  (kayak orientation)
drawKayak();

// Paddle sits in the kayak's frame
applyQuat(canvas, qPaddle);      // kayakLH ← paddleLH  (relative paddle orientation)
drawPaddle();
popMatrix();
```

This is what "paddle turns relative to the boat" physically means.

**Sync.** Reuse `SyncMap.pde` from PadViz5b unchanged. The `rx_ms` path is required (< 10 ms
accuracy); `gps_utc_sec` fallback is retained for cross-day file merges.

**Rest-pose test.** With the kayak level and pointing along its own body +Y (Slice B
passed), a paddle held at 90° across the kayak with left blade to port should render with
the yellow blade on the port side of the kayak. **If not:** the paddle-vs-boat magnetic
yaw datum differs — this is the per-session mount offset case. The fix is:

1. Capture a rest-pose frame (kayak and paddle both level, paddle across kayak, held still
   for ≥ 1 s) at the start of every session,
2. Derive a mount-correction quaternion offline,
3. Write it to a sidecar `.json` next to the CSV,
4. Load it at CSV-load time and apply at load, not at render.

**Not fixable by adding a `corrZ = 180` key. Not fixable by cycling axes.** If a session
lacks a rest-pose frame, the session cannot be reliably corrected — accept the residual
and document it.

---

## 5. Files

To be created under `visualisation/PadViz6/`:

| File | Role |
|------|------|
| `PadViz6.pde` | Main: setup, draw, key/mouse routing, HUD, slice-mode state machine |
| `Model3D.pde` | Handedness flip + model calibration + quaternion applier + draw |
| `Calibration.pde` | Slice 0 tool: reference wireframe, key handlers, JSON writer |
| `DataSource.pde` | Paddle CSV parser (skeleton copied from PadViz5b; no correction code) |
| `BoatSource.pde` | Boat CSV parser (skeleton copied from PadViz5b) |
| `SyncMap.pde` | Reused from PadViz5b unchanged (rx_ms + gps_utc dual path) |
| `GraphPanel.pde` | Bottom graph strip (ported from PadViz5b) + export-all-fields dialog |
| `SidePanel.pde` | Filenames + Load buttons + play/pause + speed slider |
| `data/paddle60.obj` + `.mtl` | Copied from PadViz5b (post 7 Jul 2026 blade split) |
| `data/model_calibration.json` | Output of Slice 0; input to Slices A/B/C |

Nothing else is carried over from PadViz3/4/5/5b. In particular: **no `corrX`, `corrY`,
`corrZ`** variables (values live in `model_calibration.json`, not code); **no `tuneAxis`**;
**no `A`, `-`, `=`** keys; **no `scale(-1, 1, 1)`** anywhere.

---

## 6. Keyboard

Keys are context-sensitive on the active slice. Keys not listed for a given slice are
inactive in that slice.

**Global (all slices):**

| Key | Action |
|-----|--------|
| `0` | Enter Slice 0 (model calibration mode) |
| `1` | Enter Slice A view (paddle only) |
| `2` | Enter Slice B view (kayak only) |
| `3` | Enter Slice C view (combined) |
| `O` | Open paddle CSV |
| `B` | Open boat CSV |

**Slice 0 (model calibration) — see §4.0 for full listing:**

`Y` / `Shift+Y` yaw ± step; `P` / `Shift+P` pitch ± step; `R` / `Shift+R` roll ± step;
`[` / `]` step size ÷2 / ×2; `Z` zero triple; `S` save JSON; `L` print console block.
No playback keys (no `Space`, no arrows) — Slice 0 shows only the rest-pose frame.

**Slices A / B / C (playback and review):**

| Key | Action |
|-----|--------|
| `Space` | Play / pause |
| `←` / `→` | Step one frame |
| `Home` / `End` | Jump to start / end |
| `R` | Reset camera to default (has no rotation-editing effect) |
| `E` | Export current graph selection (see §9) |

Deliberately **omitted** in Slices A/B/C (present in PadViz3/4/5b):

- `A` (cycle tune axis)
- `-` / `=` (nudge correction ±5°)
- Overloaded `0`/`1..3` for axis-isolation test modes (in PadViz6 these are slice-select
  keys and never mutate rotations)
- Any key that mutates a correction quaternion at runtime

`Y`, `P`, `R` in Slices A/B/C are unbound (or, if reused, must be for non-rotation
actions). This ensures a user cannot accidentally leave Slice 0 with rotation keys still
live in a review session.

Test-mode axis isolation, if needed for debugging, must be gated behind a debug flag in
source and not bindable at runtime.

---

## 7. Per-Session Calibration Procedure

*Distinct from the Slice 0 model calibration (§4.0). The model calibration is a one-time
per-OBJ constant; the per-session procedure below captures three offsets that vary trip-to-
trip and produces a sidecar JSON alongside each session's CSVs.*

### 7.1 What is being calibrated

Three offsets, each with a different physical origin:

1. **Sensor-mount offset (paddle)** — rotation of the paddle-IMU package about the shaft
   axis (and small deflection about the shaft-normal), because the sensor is Velcro'd
   to the shaft and its orientation is not guaranteed the same each session. Manifests
   as a non-zero accelerometer reading at rest along paddle-body Y.

2. **Sensor-mount offset (boat)** — the same for the hull-IMU package.

3. **Magnetic-yaw datum offset** — residual difference between the two sensors' estimates
   of magnetic north after each has been figure-8'd. Both BNO085s reference world +X to
   magnetic north, so in principle they align; in practice a few degrees of divergence
   remain because of different local hard-iron environments (paddle in air vs boat with
   fittings) and imperfect self-calibration.

Offsets (1) and (2) come from the accelerometer at a single rest window. Offset (3) comes
from the mean rotation vector difference over the same window (after (1) and (2) have been
removed).

### 7.2 Pre-session sensor preparation — magnetometer

Both sensors need a converged magnetometer before they'll produce reliable yaw. Steps for
each unit, done once per outing:

1. Assemble the unit fully — battery in its final mounted position, enclosure closed.
   Any ferrous material that will be near the sensor during use must be present now.
2. Wave the unit in a figure-8 pattern (three axes of rotation, not just one plane) in
   the open, away from cars/buildings/electronics. Continue until the firmware reports
   `MAG_CAL: 3` on serial (or `M3` green on the CYD if that indicator is added).
3. Save Dynamic Calibration Data to the BNO085's flash so it survives power-cycle. The
   firmware must call `sh2_saveDcdNow()` once mag status reaches 3.
4. Mount the unit in its normal position (boat unit into hull, paddle unit on shaft).
5. Verify: do a short second figure-8 in the mounted position. If mag status stays 3,
   no ferrous distortion at the mounting point — you're done. If it drops to 2 or 1,
   re-cal in-mount and re-save.

For the boat unit, step (2) can be done outside the boat if and only if the mounting point
is verified free of ferrous material within ~30 cm. Step (5) is the check for that.

### 7.3 The rest pose

At the start of every recording:

- Kayak level (deck horizontal — flat water, no wake).
- Paddle held horizontal, exactly across the kayak (shaft perpendicular to the bow-stern
  axis).
- Blades exactly vertical.
- **Blade normal pointing to bow** (right blade's power face forward). This aligns
  paddle-sensor +Y with boat-sensor +Y.
- Held still for **at least 3 s** at 100 Hz — gives 300 samples for offset estimation.

In this pose the two sensor-body frames coincide axis-for-axis (see §7.1 table analogy):
paddle +X = boat +X = starboard; paddle +Y = boat +Y = bow; paddle +Z = boat +Z = up.
Any observed difference between the two quaternions at rest is the datum offset to be
captured.

### 7.4 Rest-window detection and offset extraction

An offline pass over the paddle and boat CSVs identifies the rest window and extracts
offsets. The rest window is the first contiguous span **at or after the current playback
frame** (v0.13) where:

- `abs(||accel|| − 9.81) < 0.1 m/s²` on both sensors, and
- per-axis rolling variance of accel over 100 samples < a threshold (roughly
  `0.02 (m/s²)²`), and
- span duration ≥ 300 paddle frames (3 s).

The playback-frame anchor lets the user seek past unwanted quiet periods (paddler
sitting in the kayak before launch, pauses during setup, etc.) that would otherwise
be selected as the first "at rest" span. Frame 0 (default before any seeking)
scans from the beginning of the file.

From the rest window:

- **Paddle mount offset** — `roll_offset_pad = atan2(-mean(ay_pad), mean(az_pad))`,
  `pitch_offset_pad = atan2(mean(ax_pad), sqrt(mean(ay_pad)² + mean(az_pad)²))`.
- **Boat mount offset** — same formulae on boat accel.
- **Yaw datum offset** — take the mean quaternion of each sensor over the rest window,
  remove the mount offsets from each, then extract the yaw component of
  `q_boat_rest_conj * q_paddle_rest`.

Yaw offset is only observable via the magnetometer — offsets (1) and (2) alone cannot
resolve it (accel is symmetric about the vertical axis).

### 7.5 Sidecar schema

One sidecar per session, next to the paddle CSV: `<basename>.session.json`.

```json
{
  "session":       "2026-07-15",
  "recorded_at":   "2026-07-15T14:32:11Z",
  "paddle_csv":    "ImuLog20260715-1.CSV",
  "boat_csv":      "BoatLog20260715-1.CSV",
  "rest_window": {
    "paddle_frame_start": 187,
    "paddle_frame_end":   487,
    "boat_frame_start":    19,
    "boat_frame_end":      49,
    "duration_s":          3.0,
    "accel_var_max":       0.014,
    "confidence":          "high"
  },
  "paddle_mount_offset_deg": { "roll":  1.42, "pitch": -0.31 },
  "boat_mount_offset_deg":   { "roll":  0.08, "pitch": -0.19 },
  "yaw_datum_offset_deg":    7.6,
  "mag_cal_status_at_rest": { "paddle": 3, "boat": 3 },
  "classification_sections": [
    { "start_frame": 1200, "end_frame":  8400, "type": "right" },
    { "start_frame": 8600, "end_frame": 15200, "type": "left"  },
    { "start_frame": 15400, "end_frame": 22000, "type": "zero" },
    { "start_frame": 41000, "end_frame": 58000, "type": "excluded" }
  ],
  "notes":         "figure-8 done on beach; both sensors green before launch."
}
```

`classification_sections` (PadViz7 v0.16, §14) records which stretches of the recording are
good right/left/zero-feather paddling data, or should be excluded entirely. Absent or empty
in a pre-v0.16 sidecar; the reader treats absence as "no classification". Frames are
paddle-frame indices, ranges are inclusive and non-overlapping.

`mag_cal_status_at_rest` is read from the firmware's per-frame accuracy field (§7.8) — a
recording with either sensor below 3 during the rest window is flagged low-confidence and
Slice C draws its HUD sync line in amber.

### 7.6 Application at load

The sidecar is applied at CSV-load time, once. Nothing is mutated at render time.

- Each paddle frame quaternion is left-multiplied by the paddle mount-offset conjugate,
  bringing the shaft/blade into their true physical orientation regardless of how the
  sensor was clamped.
- Each boat frame quaternion is treated symmetrically.
- The yaw datum offset is applied to the paddle quaternion so its magnetic reference
  matches the boat's.

After these three corrections, the rest-pose sample renders at Slice 0 identity and
paddle-vs-boat orientation comparisons are meaningful.

### 7.7 Fallback and validation

**If the sidecar is missing:** PadViz6 loads uncorrected and prints
`NO SESSION SIDECAR — orientation uncorrected` in the HUD. The K/U keys remain as an
interactive equivalent for exploratory work.

**If the rest window fails detection:** the offline pass writes a sidecar with
`"confidence": "none"` and no offsets; the visualiser treats it as if missing.

**Validation:** after applying the sidecar, at any frame inside the rest window the
paddle should render exactly in the Slice 0 pose (shaft along red +X, blades vertical,
blade normal forward = green +Y). Deviation ≥ 2° at rest indicates either a bad rest
window or a mag cal that didn't converge.

### 7.8 Firmware dependencies

The per-session procedure requires Phase 10 firmware — formalised in
`firmware/specs/functional_spec.md` §15 (Magnetometer Calibration Support). Summary of
what §15 delivers to this section:

1. **Mag report enabled on both PadLog and BoatLog** — `SH2_MAGNETIC_FIELD_CALIBRATED`
   at 10 Hz, `.status` field read every loop (§15.2.1).
2. **On-change serial output** — `MAG_CAL: <0-3>` printed only when the value changes,
   so the operator can watch figure-8 convergence during warm-up (§15.2.2).
3. **DCD saved to flash on first convergence** — `sh2_saveDcdNow()` fires once per
   boot at the moment status first reaches 3, persisting calibration across power-
   cycles (§15.2.3).
4. **`mag_cal` column in both CSVs** — added after `rx_ms`, values 0–3, used by the
   rest-window detector to flag low-confidence sessions (§15.2.4).

Note that (4) is a payload struct change and requires a coordinated release of
PadLog v8.8, BoatLog v1.1, and PadDis v8.11 in a single commit (§15.6).

**Fallback for pre-Phase-10 CSVs:** rest-window detection treats missing `mag_cal`
column as "unknown" — mount offsets are still extracted from accel (which needs no
mag), but the sidecar records `"mag_cal_status_at_rest": null` and the visualiser
displays `MAG UNKNOWN` in the Slice C HUD.

---

## 8. Discipline Rules (enforced in code review)

1. Every quaternion multiplication has a `// <targetFrame> ← <sourceFrame>` comment.
2. No `corrX`, `corrY`, `corrZ` variables in Slices A/B/C. Model calibration values live
   in `data/model_calibration.json`, loaded at sketch start, held in read-only fields.
3. No key that mutates a correction quaternion in Slices A/B/C. Rotation-editing keys
   (`Y`, `P`, `R`) are legal *only* in Slice 0 mode.
4. Per-session offsets live in sidecar JSON alongside the CSV, applied at load, never at
   render.
5. Any handedness change other than the one `scale(1, 1, -1)` documented in §3.1 is
   prohibited.
6. If a slice fails its acceptance test, the fix is: (a) re-run Slice 0 if the model
   calibration is wrong, (b) add a documented mount rotation at load with a source
   comment, or (c) file a physical-mounting incident report. Never a runtime tweak in
   Slices A/B/C.
7. Slice 0 is a build-time tool. Its output (`model_calibration.json`) is committed to
   the repo. Its interactive keys are physically inaccessible from Slices A/B/C.

---

## 9. Export

The bottom graph panel (ported from PadViz5b, §14) supports zoom-window export via `E` or
the `Export` button. The export dialog offers two column sets:

- **Curated (default)** — the PadViz5b column set:
  `pad_seq, pad_ts, pad_roll, pad_pitch, pad_yaw, pad_cpm, pad_stroke, pad_accel_x,
   pad_accel_y, pad_accel_z, pad_rx_ms, pad_gps_utc, boat_ts, boat_rx_ms, boat_gps_utc,
   boat_lat, boat_lon, boat_speed_ms, boat_cog, kayak_qw, kayak_qx, kayak_qy, kayak_qz,
   kayak_roll, kayak_pitch, kayak_yaw`.
  `pad_rx_ms` and `boat_rx_ms` are additions vs. PadViz5b (which currently omits them —
  see PadViz5b spec §14.7).
- **All fields (new option)** — every column present in both loaded CSVs, unfiltered.
  Paddle columns first (all 17 columns of the v8.10 paddle log if loaded, or whichever
  subset the loaded file provides), then all boat columns (all 17 of the v8.10 boat log
  or subset). Rows outside the sync range have empty boat cells; rows with no boat file
  loaded omit boat columns entirely.

Dialog is a simple two-radio-button selector when `E` is pressed or `Export` is clicked;
choice is remembered per session (defaults to Curated on sketch start).

Header row of the exported file names every included column. First line comment records
which slice was active, which CSVs were loaded, and the sync path used
(`# rx_ms path` or `# gps_utc path`).

---

## 10. Success Criteria

PadViz6 replaces PadViz5b as the current tool when:

1. Slice 0 has produced a validated `model_calibration.json` committed to the repo.
2. Slice A passes its acceptance test on both the known-good 21 May 2026 session and a
   post-7 Jul 2026 session, using the Slice 0 calibration.
3. Slice B passes its acceptance test and the COG mapping is documented.
4. Slice C passes its acceptance test on a session that includes a rest-pose window and
   sidecar.
5. Export supports both Curated and All-fields modes and preserves `rx_ms` columns.
6. All PadViz5b features that are still wanted (bottom graph panel, dropdown fields,
   drag-to-zoom, merged CSV export, side-panel filenames + Load buttons, boat quat for
   kayak) are present under the discipline rules of §8.

Until then, use PadViz5b for graph/export work and PadViz6 (as it is built) for
orientation review only.

---

## 11. Out of Scope

- Any change to firmware, ESPnow link, or CSV column layout.
- Any change to `SyncMap.pde` beyond copying it byte-for-byte from PadViz5b.
- Any attempt to auto-diagnose a physical mount inversion from data alone. The rest-pose
  calibration is user-initiated; if not captured, the session is uncorrected.
- Automatic derivation of the model calibration triple from the OBJ file. Slice 0 is
  interactive by design — the operator's judgment of "the model matches the reference
  wireframe" is the acceptance criterion.

---

## 12. Implementation Status (8 Jul 2026)

### 12.1 Files present

| File | Purpose |
|---|---|
| `PadViz6.pde` | Main sketch — slice/view state, key routing, HUD, playback |
| `Calibration.pde` | Cal triple + JSON I/O + Slice 0 key bindings |
| `Model3D.pde` | Paddle OBJ loader, `applyQuat`, procedural kayak |
| `DataSource.pde` | Paddle CSV parser (v8.10 + v8.9), `meanQuat` window helper |
| `BoatSource.pde` | Boat CSV parser (v8.10 + v8.9), `meanQuat` window helper |
| `SyncMap.pde` | Paddle→boat frame lookup; `rx_ms` (±500 ms guard) or `gps_utc_sec` (±5 s) |
| `GraphPanel.pde` | Bottom strip — 3 traces from any paddle/boat field, drag-zoom, seek, merged CSV export |
| `Sidecar.pde` | Session sidecar builder (rest-window detector + mount offsets + yaw datum + JSON I/O) |
| `Checklist.pde` | Startup onboarding strip — three clickable rows that auto-tick from live state |
| `data/paddle60.obj`+`.mtl` | Copied from PadViz5b (post 7 Jul 2026 blade split) |
| `data/model_calibration.json` | Slice 0 output — currently `{0, 0, 0}` (see §12.3) |

Not present: `SidePanel.pde`, `Integrator.pde`.

### 12.2 What each slice does

**Slice 0 — DONE.** Interactive calibration tool. World sensor-axis reference (RGB lines) drawn at origin. Paddle drawn under handedness bridge + current calibration triple, no data quaternion. Fixed cameras (side and top-down, `V` toggles). Key bindings `y/Y P/p R/r` nudge yaw/pitch/roll by ± step; `[`/`]` change step; `Z` zero; `S` save JSON; `L` list to console.

**Slice A — DONE.** Loads a paddle CSV (`O` key; PadDis v8.10 17-col with `rx_ms` preferred, v8.9 16-col fallback). Draws paddle under handedness bridge + calibration + data quaternion. Independent frame index with Space / arrows / `,`/`.` / Home / End playback. **Reference subtraction (K/U):** `K` captures the mean quaternion over ±50 frames around the current frame; while active, each frame renders as `qRef⁻¹ * q_current` so the captured pose appears at Slice 0 identity. `U` clears. HUD shows current frame, timestamp, `rx_ms`, quat, Euler, and reference state.

**Slice B — DONE.** Loads a boat CSV (`B` key). Draws procedural kayak (see §12.4) driven by `kayak_qw..qz` through the same pipeline (no paddle cal triple — kayak is drawn in the boat-IMU frame, not the paddle-model Blender frame). Independent frame index, independent K/U reference (separate `qRefBoat`). HUD adds a GPS line (fix / speed / COG / UTC). Axis legend switches to boat conventions (+X starboard, +Y bow, +Z deck).

**Slice C — DONE (initial render; field validation pending).** Requires both CSVs loaded. Loading either CSV rebuilds `SyncMap`; loading the second one auto-enters Slice C. Paddle frame index is the timeline master; the matched boat frame is picked from `SyncMap` every draw call. Render composition (inside the handedness bridge):

```
applyQuat(qKayak_disp)     // worldRH ← kayakLH  (boat CSV drives world)
drawKayak()
applyCalTriple()           // kayakLH ← blenderLH_paddle
applyQuat(qRel_disp)       // paddle-rel-to-kayak = qConj(qKayak) * qPaddle
drawPaddle()
```

**K/U in Slice C** captures both refs simultaneously: `qRefPad` = mean paddle quat over ±50 paddle frames; `qRefBoat` = mean boat quat over the sync-matched boat window. With both refs set, the render subtracts each: `qKayak_disp = qConj(qRefBoat) * qKayak`, `qRel_disp = qConj(qConj(qRefBoat)*qRefPad) * qRel`. At the captured rest instant, both objects render at Slice 0 identity, collapsing the magnetic-yaw datum difference between the two IMUs. This is the interactive form of the per-session sidecar (§7); once a workflow is settled, the sidecar path replaces manual K captures.

**HUD (Slice C).** Both CSV names, both frame indices, sync path (rx_ms / gps_utc / NO SYNC), sync delta in ms, both raw quats, GPS line, ref-capture status. Axis legend shows boat frame (kayak drives world).

### 12.3 Calibration result

For the paddle60.obj in the repo, the calibration triple is `(model_yaw_deg = 0, model_pitch_deg = 0, model_roll_deg = 0)`. Vertex extents confirm the OBJ was drawn in the paddle-IMU convention: X ±0.909 m (shaft), Y ±0.08 m (blade normal, thin), Z ±0.09 m (in-blade, wider). No rotation is needed to map Blender frame → sensor frame.

### 12.4 Kayak model

Octagonal cross-section (eight vertices at deck level, eight at hull level), tapered to points at bow (+Y = 2.75 m) and stern (−Y = 2.75 m), widest at midship (±0.275 m). Deck at Z = +0.075 m, hull at Z = −0.075 m. Shape reused from PadViz5b `drawKayak`; Z sign inverted vs. PadViz5b because PadViz6 uses +Z = up whereas PadViz5b drew the kayak below the XY plane. Blue deck, grey hull, darker sides, dark cockpit rectangle centred on Y = 0, and a bright red bow triangle at the +Y tip for unambiguous forward indication.

### 12.5 Camera conventions (Processing P3D)

**Free-orbit camera (v0.9, 8 Jul 2026).** State: `camAzimDeg`, `camElevDeg`, `camDist`. Baseline eye position (az = 0, el = 0) is `(0, -camDist, 0)` with world up = `(0, 0, 1)` — the same side view as the pre-v0.9 preset. Elevation positive tilts the eye toward physical up (world −Z under the handedness bridge), clamped to ±89°.

Presets available via `V`:
| Preset | (az, el, dist) | Notes |
|---|---|---|
| Side | (0, 0, 1200) | Baseline. Red +X right, blue +Z up, green +Y into screen. |
| Near-top | (0, 89, 1200) | Physical top-down. Red +X right, green +Y up (bow), blue +Z out of screen. |

Mouse: left-drag orbits (0.4° per pixel), wheel zooms (12% per notch), constrained to `camDist ∈ [200, 5000]`.

The camera basis (`right`, `up`, `forward`) is computed once per frame in `getCameraBasis()` and shared between `setCamera()` and `drawAxisCompass()`. The compass therefore rotates in step with the 3D scene: each sensor axis is transformed through the handedness bridge, projected through the basis, and rendered as a coloured line if the projection has non-trivial length, or as a disc-in-ring (out of screen) / X (into screen) when near-perpendicular.

**P3D gotcha:** the `up` vector passed to `camera()` specifies the screen-**down** direction (Y-inverted from OpenGL to match 2D). Verified empirically 7 Jul 2026. The `getCameraBasis()` output already accounts for this — passing the computed `up[]` to `camera()` yields the correct physical-up-is-up-on-screen behaviour under the handedness bridge.

### 12.6 Reference subtraction (K/U) — validation aid

Slices A and B each carry an independent reference quaternion (`qRefPad`, `qRefBoat`), initially identity. `K` captures the mean quaternion of ±50 frames around the current frame index into the active-slice reference; subsequent frames render `qRef⁻¹ * q_current` instead of the raw quat, so the captured pose appears at Slice 0 identity. `U` clears the active-slice reference.

This is a **view alignment**, not a data correction, and it is deliberately per-source and non-persistent. It exists because BNO085 quaternions are expressed in a magnetically-referenced world frame — absolute yaw does not align with paddler-forward without either magnetometer calibration or a per-session body-frame reference. The validation-time subtraction here is the same math that Slice C will use via a per-session sidecar JSON (§7).

### 12.7 Physical facts captured

- **Calibration Rest A window** (`ImuLog20260706-1.CSV`, t = 22 – 38 s, frames ≈ 2200–3800): paddle held horizontal, right blade face vertical, sensor +Y toward kayak bow. Mean roll = 0° ± 2°, pitch ≈ −2.5° ± 3°, yaw ≈ 55° ± 1°. Accel `≈ (0.25, −0.4, +9.85)` confirms sensor +Z is physically up.
- **Boat mean orientation during the same window** (`BoatLog20260706-1.CSV`): kayak roll ≈ +5.9°, pitch ≈ −4°, yaw ≈ 50°, speed = 0. Note (corrected 8 Jul 2026): the boat is stationary only during the *calibration phase* at the start of the file (rows 1 – ~5000). GPS fix is solid throughout (24,791 / 24,791 rows fix = 1). Under-way paddling begins around row ~10,000 with speed ramping to 0.6 m/s, and by row ~15,000 the session is at steady paddling speed 2.2 – 2.6 m/s with COG stable near 300–310°. So both Slice C's rest-window prerequisite and Slice B's COG mapping test (§4.2 test 2) are runnable on this file — the earlier "stationary throughout" reading was of the calibration segment only.

### 12.8 Graph panel (bottom strip) — DONE 8 Jul 2026

Full-width strip along the bottom of the window (height 220 px). Visible whenever a paddle CSV is loaded and the active slice is A/B/C. Ported from `PadViz5b/GraphPanel.pde`, with the field-name differences (`kayakRoll` → `roll` etc) resolved by the data-source refactor below.

**Data-source refactor (prerequisite).** PadViz6 `FrameData` gained `accelX/Y/Z`, `strokeCount`, `cpm`, a `field(int)` helper, and `DataSource.fieldAt/fieldRange`. `BoatFrameData` gained a `field(int)` helper (0=roll, 1=pitch, 2=yaw, 3=speed, 4=cog) and `BoatSource.fieldRange`. Parser column indices moved from `t.length ≥ 12` to `t.length ≥ 14` on the paddle side to require the accel/cpm/stroke columns.

**Fields.** 13 in total, three-slot dropdowns (defaults: roll, yaw, CPM):
- Paddle: roll, pitch, yaw, CPM, strokeCount, accel_x/y/z.
- Boat: kayak_roll, kayak_pitch, kayak_yaw, speed_ms, cog_deg.

**Interaction.** Click a slot to pick its field; scroll wheel scrolls the dropdown list. Drag on the chart to zoom to a paddle-frame window; click near the yellow cursor line to seek + pause; drag the cursor to scrub. `Full` clears the zoom.

**Export.** `Cols:` toggle in the footer cycles between `curated` (default) and `all` column sets. `Export…` (or the `E` key) opens a file dialog and writes the merged CSV over the current zoom range.

- **Curated columns:** `pad_idx,pad_ts,pad_roll,pad_pitch,pad_yaw,pad_cpm,pad_stroke,pad_accel_x/y/z,pad_rx_ms,pad_gps_utc,boat_ts,boat_rx_ms,boat_gps_utc,boat_lat,boat_lon,boat_speed_ms,boat_cog_deg,kayak_qw/qx/qy/qz,kayak_roll,kayak_pitch,kayak_yaw`. Rows outside sync range emit empty boat columns.
- **All-fields columns:** every field of paddle CSV first, then every field of boat CSV (including `gps_fix`). If no boat CSV is loaded the boat columns are omitted from the header.

First line of every exported file is a comment recording mode + sync path, e.g. `# PadViz6 export — mode=curated   sync=rx_ms`.

### 12.9 Not done

- **Slice C field validation — preliminary pass 8 Jul 2026.** User ran the whole pipeline on the 6 Jul 2026 session (paddle + boat CSVs, `C` to build sidecar, then scrubbed through rest window + under-way segment). All five visual checks passed (rest pose renders horizontal + level; under-way paddle motion physically plausible; kayak yaw tracks GPS COG). **Full acceptance withheld** until (1) Phase 10 firmware exposes mag_cal status so the paddle-vs-boat yaw datum divergence can be quantified rather than assumed converged, and (2) the paddle sensor mount is re-checked (see project_paddle_mount_diagnosis memory). Retest planned on a session recorded with Phase 10 firmware and a verified mount.
- **Per-session rest-pose sidecar** (§7). ~~Not yet implemented.~~ **DONE for build + save (v0.10) and auto-load (v0.12).** `C` key runs the rest-window detector, computes mount offsets + yaw datum, and auto-saves as `<basename>.session.json` next to the paddle CSV. `onPaddleFileSelected` auto-loads any sibling sidecar file and reseeds `qRefPad`/`qRefBoat` from the CSV rest-window means; `onBoatFileSelected` extends the seeding to the boat side. Still pending: decomposed render path per §7.6 (currently the sidecar collapses to K-style subtraction — visually identical at rest, but doesn't expose the split for post-processing consumers of the JSON).
- **Side panel** (`SidePanel.pde`) — filenames, load buttons, play/pause, speed slider.
- ~~**Startup onboarding checklist**~~ — **DONE (v0.11).** `Checklist.pde` fills the bottom strip whenever no paddle CSV is loaded. Three rows, each auto-ticking from live state and each clickable as an alternative to the shortcut key:
  1. `Load paddle CSV [p]` — ticks when `paddleData` is populated.
  2. `Load boat CSV [b]` — ticks when `boatData` is populated. Dimmed until step 1 done.
  3. `Build session sidecar [C]` — ticks when `sidecar.valid`. Dimmed until step 1 done.
  Disappears the moment the paddle CSV loads (graph replaces it). Add a `☐ Mag cal M3` row once Phase 10 firmware lands.
- ~~**Adaptive side view** for Slice B (starboard-side camera).~~ — no longer needed; free-orbit camera (§12.5, v0.9) makes any angle reachable.
- **Under-way GPS COG mapping test** for Slice B acceptance — needs a new field session.

### 12.10 Field-use notes — 8 Jul 2026 — all three DONE 8 Jul 2026

These came up while driving the sketch against real data.

1. **Lowercase `k` reports as "no effect".** — **DONE.** `k` (and `u`) now trigger a top-centre HUD flash for 1.5 s (linear fade over the last 400 ms). Message text is slice-specific: `PADDLE REF CAPTURED (frame N)` in Slice A, `KAYAK REF CAPTURED (frame N)` in Slice B, `BOTH REFS CAPTURED (pad N, boat M)` in Slice C, and the matching cleared-variant on `u`.

2. **"Kayak view" that also shows the paddle."** — **DONE.** Initial fix (v0.8) kept the P/K/W Shift-letter slice-switch shortcuts and added a HUD hint in Slice B pointing to `W`. Revisited v0.10: the letter shortcuts were dropped entirely because Caps Lock on Windows silently rewrites `k` → `K`, causing users who intended to press `k` (capture reference) to jump to Slice B instead. Slice switching is now on digits `0/1/2/3` only; the compass letters `P/K/W` are pure labels. Slice B's HUD hint remains but now points at `3`.

3. **No "revert to previous slice" shortcut.** — **DONE.** `Backspace` and `-` both ping-pong to the previously-active slice. Same model as GraphPanel's double-right-click zoom revert — a single `prevSliceMode` variable is swapped, so repeated presses toggle between two most-recent slices rather than walking a full history stack. Slice changes from CSV loads (`onPaddleFileSelected`, `onBoatFileSelected`) also update the history, so loading a boat CSV while in Slice A pushes A for later revert.

### 12.11 Key bindings — current state (v0.12)

All slices:
| Key | Action |
|-----|--------|
| `0`               | Slice 0 (calibration) |
| `1` | Slice A — paddle view; compass letter `P` |
| `2` | Slice B — kayak view; compass letter `K` |
| `3` | Slice C — combined view; compass letter `W` |
| `v` / `V`         | Cycle side / near-top camera preset (also recentres az and dist) |
| Backspace or `-`  | Go back to previously-active slice (ping-pong) |
| Mouse left-drag   | Orbit camera in 3D area (0.4°/px on azim and elev) |
| Mouse wheel       | Zoom camera in 3D area (12%/notch, clamped 200-5000) |
| `p` (lowercase)   | Open paddle CSV |
| `b` / `B`         | Open boat CSV |

Slices A / B / C additional:
| Key | Action |
|-----|--------|
| Space | Play / pause |
| ← / → | Step 100 frames |
| `,` / `.` | Step 1 frame |
| `>` | Double playback speed (caps at x8) — v0.15 |
| `<` | Reset playback speed to x1 — v0.15 |
| Home / End | Jump to start / end |
| `k` (lowercase) | Capture reference — mean quat over ±50 frames |
| `u` (lowercase) | Clear reference — back to raw quat |
| `S` (Shift+s) | Reset graph zoom to full range (also pushed to history) |
| `E` (Shift+e) | Export merged CSV over current zoom |
| `C` (Shift+c) | Build session sidecar (rest-window detect + mount offsets + yaw datum) and auto-save as `<basename>.session.json` next to the paddle CSV. Search starts at the current playback frame (v0.13). |
| Mouse right-click in entry/exit panel (left 20%, slice ≥ 1) | Clear accumulated dots from current playback frame back — v0.15 |

Slice 0 (calibration) — routed through `cal.handleKey()`, plus the v0.15
entry/exit yaw-datum override (handled directly in `keyPressed()`, not
`cal.handleKey()` — it edits the sidecar, not the model triple):
| Key | Action |
|-----|--------|
| `y` / `Y` `i` / `I` `r` / `R` | Nudge model-mesh yaw / pitch / roll by ± step (pitch moved off `p`/`P` in v0.15 — `p` is the global "open paddle CSV" key and always won the dispatch, so `p` for pitch-increase was dead) |
| `[` / `]` | Halve / double step (shared by both nudge groups below) |
| `Z` | Zero all three model-triple values |
| `S` | Save `data/model_calibration.json` |
| `L` | List current triple to console |
| `n` / `N` | Nudge entry/exit yaw-datum manual override by ± step (§13.7) — requires a sidecar (`C` run first) |
| `g` | Reset entry/exit yaw-datum manual override to 0 |

Graph panel mouse gestures (Slices A/B/C only, when a paddle CSV is loaded):
- **Left-click chart** — move playback cursor to x, pause playback (drag to scrub).
- **Right-click chart** — first click places marker A, second click places B and applies zoom (moves cursor to zoom start).
- **Double right-click same spot** (< 400 ms, within ±8 px) — revert to the previous zoom range (ping-pong).
- **Full button** or `S` key — reset to full range.
- **Cols button** — toggle export column set between `curated` and `all`.
- **Export button** or `E` key — write merged CSV.
- **Slot buttons** (left click) — open field-select dropdown; scroll wheel scrolls the dropdown.

Startup checklist mouse gestures (bottom strip **only while no paddle CSV is loaded** — v0.13):
- **Click row 1** — same as pressing `p` (open paddle CSV file picker).
- **Click row 2** — same as pressing `b` (open boat CSV file picker). Dimmed and non-clickable until row 1 done.
- **Click row 3** — same as pressing `C` (build and auto-save sidecar). Dimmed and non-clickable until row 1 done.

Once the paddle CSV is loaded, the graph replaces the checklist (essential — the user needs to seek before pressing C). A yellow HUD line below the mode-name row prompts "SIDECAR not built — drag the graph cursor to the intended rest moment, then press C (search will start at paddle frame N)" until a sidecar is built or auto-loaded.

### 12.12 Paddle-centre motion (v0.13, 9 Jul 2026)

**Feature.** The paddle mesh in Slices A and C is translated per-frame by a small offset derived from the paddle IMU accelerometer, so the shaft midpoint visibly drops toward the water-side blade during the pull and rises back toward centre in the air phase. Clamped to ±0.3 m per axis.

**Pipeline** (see `DataSource.computePaddleCentreMotion`, run once at CSV-load time):

1. Rotate body-frame accel to world using the frame quaternion: `a_world = R(q) · a_body`.
2. Subtract gravity: `a_linear = a_world − (0, 0, +g)`.
3. HPF cascade — three stages: `y[n] = α · (y[n−1] + x[n] − x[n−1])` with `α = 1 − 2π·fc·Δt`, `fc = 0.3 Hz`, `Δt = 0.01 s` → α ≈ 0.981. Stage 1 filters linear accel; stage 2 filters the integrated velocity; stage 3 filters the integrated position.
4. Clamp final offset per axis to ±0.3 m.

**Why HPF cascade and not leaky integrators.** A plain leaky integrator (`v[n] = α·v[n−1] + a·Δt`) has bounded but *large* DC gain; a residual gravity-subtraction bias of just 0.1 m/s² saturates the ±0.3 m clamp within seconds. Empirically on the 9 Jul 2026 CSV, leaky integrators pinned 94.5 % of Z-axis frames to the clamp with zero roll correlation. The HPF cascade zeroes DC at each stage and passes the ~0.3–1.5 Hz stroke band cleanly — RMS output 5–8 cm during steady paddling, no clamp hits, position visibly oscillates at stroke frequency.

**Caveat — position is world-anchored.** The offset is in the sensor's magnetic-north-anchored world frame. In Slice C it is applied *in kayak body coords* (after the kayak orientation and paddle-lift translate), so the visual is close to "paddle centre swings relative to the kayak" as long as the kayak's yaw is roughly constant relative to magnetic north. It will not perfectly track the physical description "always toward the low blade" — the visual is an accel-anchored oscillation, not a paddle-body-frame kinematic model.

**Not tracked over long time scales.** By design (HPF), the position decays to zero rather than integrating true displacement. True paddle-centre tracking would require mag- and GPS-aided INS which is not attempted here.

**Render integration.** Slices A and C both translate by `(posX, posY, posZ) · MODEL_SCALE` (300 px/m — shared with paddle OBJ scale) *before* the cal triple and quaternion. In Slice C the offset is applied after the kayak orientation and paddle-lift translate, so the paddle floats in kayak body coords rather than magnetic world. As of v0.15 (§13.7 item 5) the paddle-lift translate also carries a fixed +0.45 m bow offset — the accel-derived wobble above still swings around that base position, it doesn't replace it.
- Checklist auto-dismisses 2.5 s after the last box ticks; during that window a countdown message shows at the bottom of the strip.

---

## 13. v0.14 — Catch/Release Visualisation (17 Jul 2026)

Four work items, agreed 17 Jul 2026. Motivating analysis: firmware spec
§13.5 (blade entry/exit feasibility on the 16 Jul 2026 field data —
phase-locked 8–30 Hz accel transients, tip-height gating, all four events
in every regime) and §16.11 (relative yaw must come from GRV, not fused).

### 13.1 Startup overlay (Checklist.pde rework)

The bottom-strip checklist becomes a floating panel drawn over the 3D
view, horizontally centred, sitting just above the graph strip. Rows (with
live ticks, clickable as before):

1. Load paddle CSV (`p`)
2. Load boat CSV (`b`) — dimmed until row 1 done
3. "Drag the graph cursor to the start of the calibration (rest) data,
   then press `C`" — dimmed until row 1 done

The graph strip is therefore free to appear the moment the paddle CSV
loads, and the overlay persists through the seek-and-`C` step (v0.13's
weakness: the instructions vanished exactly when the user needed them).
The overlay dismisses when a sidecar is built (`C`) or auto-loaded
(`.session.json` found at CSV open). The yellow "SIDECAR not built" HUD
hint is deleted as redundant. `C` semantics unchanged (search starts at
current playback frame).

### 13.2 Commands pull-down (Menu.pde, new)

The static left-edge key-list HUD is removed. A "Commands ▾" button in
the top-left of the 3D area opens a drop-down listing all bindings
(grouped: Files / Playback / Camera / Calibration / Export), each row
`key — description`; clicking a row invokes the same handler as the key.
Click-away or `Esc` closes. Keyboard bindings are unchanged — the menu is
for discoverability. Frees the left edge for §13.4.

### 13.3 Catch-event engine (CatchEvents.pde, new)

Offline detection at CSV-load time (pattern precedent:
`computePaddleCentreMotion`). Port of the §13.5 (firmware spec) method:

- **Signals:** |accel| → 8–30 Hz Butterworth band-pass (two cascaded
  2nd-order biquads) → 50 ms RMS envelope. Cycle anchor = 2 Hz low-passed
  roll; switch to pitch when the roll swing is below ~60° (zero feather —
  roll is half-period ambiguous, firmware spec §16.10).
- **Gating:** shaft direction = body X rotated by the paddle quaternion;
  tip height = ±1.05 m × world-z component. Entry window = blade low and
  descending; exit window = blade low and rising (windows ~±150 ms around
  the phase predicted from the previous cycle; §13.5 jitter 33–96 ms).
- **Events:** HF-envelope peak inside each gated window →
  `{frame, rx_ms, side, ENTRY|EXIT, xyBoat}`.
- **Side assignment:** +X/−X blade → paddler right/left via the pitch
  classifier at roll extrema (firmware spec §13.4, 92 % uncalibrated);
  sidecar mount data overrides when present.
- **Blade XY in boat frame:** horizontal projection of the shaft
  direction × ±1.05 m, rotated by GRV relative yaw (paddle GRV yaw −
  boat GRV yaw, yaw-datum'd by the sidecar). Shaft centre = cockpit
  origin for now. Requires `grv_*` CSV columns (PadLog v8.9+ /
  BoatLog v1.2+, 16 Jul 2026 onward); older files → §13.4 panel shows
  "no GRV data". No boat CSV loaded → fallback: paddle GRV yaw minus its
  own 30 s rolling baseline (assumes steady boat heading), flagged
  approximate in the panel.
- **Validation:** run against the 16 Jul right1 segment and compare event
  times with `visualisation/stroke_catch_explore.py` output before
  trusting the panel.

### 13.4 Entry/exit panel (EntryExitPanel.pde, new)

Left 20 % of the window, full height from top down to the graph strip;
the 3D view compresses to the right 80 % (GraphPanel untouched,
full-width). Top-down boat-frame plot, X = starboard (right on screen),
Y = forward (up on screen), kayak outline for scale. One dot per event:
**red = right blade, green = left blade; filled = entry, hollow ring =
exit.** Dots accumulate as the playback cursor passes each event's time
(scrubbing back rewinds them); a full play-through shows the whole run.
Sanity check: right-blade dots must cluster starboard.

### 13.5 Implementation order

1. §13.1 overlay + §13.2 menu (small, independent UI changes)
2. §13.3 engine (the bulk; validate against the Python reference)
3. §13.4 panel (trivial once §13.3 exists)

### 13.6 Implementation status — BUILT 17 Jul 2026, compiles clean

All four items implemented in one pass; `processing-java --build` passes.

- **Files:** `Checklist.pde` rewritten as the floating overlay (complete =
  paddle + sidecar; boat row encouraged, not required); `Menu.pde` new —
  fires each row by synthesising the keystroke, so the keyboard handler
  stays the single source of command behaviour; `CatchEvents.pde` new;
  `EntryExitPanel.pde` new; `DataSource`/`BoatSource` parse the v8.13
  `grv_*` columns (`hasGrv` from the header); `PadViz6.pde` wires layout
  (HUD/compass/overlay translate right by `leftPanelWidth()`; axis legend
  stays window-anchored), mouse priority (menu → overlay → graph → panel
  → orbit), ESC closes the menu instead of quitting, and
  `rebuildCatchEvents()` runs on paddle load / boat load / sidecar build.
- **Engine detail that differs from the Python prototype:** no cycle
  segmentation at all. Each blade's tip-height series is scanned for runs
  below −0.05 m; the run splits at its minimum — descending half holds the
  entry, rising half the exit; the HF-envelope peak in each half
  time-stamps the event, gated at ≥ max(1.3 × median env, 0.8 m/s²).
  Regime-independent (no roll-vs-pitch anchor switch needed). Filters are
  RBJ biquads run forward-backward (zero phase, offline).
- **Algorithm validated against the 16 Jul session** (Python port of the
  exact Java pipeline, biquads included): event counts within a few % of
  the theoretical 4/cycle in all four segments (right1 515/~530, left
  148/~150, zero 106/~112, right2 305/~299); calibration segment nearly
  silent (17). Boat-frame XY with GRV relative yaw and a **whole-file-mean
  datum** (no sidecar): right1 medians — right entry (+0.69, +0.64) m,
  right exit (+0.57, −0.84) m, left entry (−0.77, +0.47) m, left exit
  (−0.49, −0.91) m; y-IQRs ±3–6 cm. Entries forward, exits aft,
  starboard/port correct — the implied ~1.5 m in-water arc is the §13.3
  stroke-length measurement working. The whole-file datum is good enough
  that the panel is meaningful even before the sidecar is built.
- **Not yet done:** zero-feather XY sanity on screen; per-event
  stroke-length numbers/labels (future — the dots come first).

### 13.7 v0.15 — field-use fixes from the on-screen check (20 Jul 2026)

The user's on-screen check (flagged "not yet done" above) surfaced four
issues, all addressed:

1. **`p` was bound twice.** `keyPressed()` handles `p` = "open paddle CSV"
   globally, before slice-specific keys are dispatched — so in Slice 0 the
   pitch-increase binding (`case 'p'` in `Calibration.handleKey`) was dead
   code; every press opened the file picker instead. Fix: pitch now uses
   `i`/`I` (`Calibration.pde`); `p`/`P` stay exclusively the paddle/boat
   CSV loaders. `Menu.pde`'s Slice 0 key-list info row updated to match.

2. **No fast replay.** Added a playback-speed multiplier (`playbackSpeed`,
   default 1). `>` doubles it (capped at x8), `<` resets to x1. `stepPlayback()`
   keeps a drift-free real-time tick count (`nReal`, unchanged 100 Hz
   bookkeeping) and scales only the frame-advance count by the multiplier,
   so speed changes mid-playback don't accumulate timing error. Shown in
   the HUD mode line as `speed=x2` (and `(paused)` if stepping while
   paused) whenever it's off x1.

3. **Entry/exit panel had no way to reset the accumulated dots.**
   `EntryExitPanel` gained `clearAtFrame` (default 0) — events with
   `padFrame < clearAtFrame` are skipped in `draw()`. Right-clicking
   anywhere in the panel calls `clear(paddleFrameIdx)`, hiding everything
   before the current playback position; a `R-click: clear` hint is drawn
   top-right of the panel. The marker also resets to 0 on a fresh paddle
   CSV load and a fresh `C` sidecar build (new data record), but *not* on
   every yaw-datum nudge (item 4) — nudging only moves existing dots, it
   doesn't invalidate which ones are "cleared".

4. **Entry/exit yaw datum manual override.** On replay the user found the
   boat-frame plot's heading read **~30° anticlockwise** of the true
   orientation, and the left blade's events sat consistently farther from
   centre than the right's even during asymmetric paddling where that
   wasn't expected — both point at the automatic yaw datum (`CatchEvents`'
   circular mean of shaft-heading-minus-boat-heading, §13.3 step 3) being
   wrong on at least this session, not at a code defect in the placement
   formula itself (right and left use the identical formula with opposite
   sign — see `CatchEvents.addEventIfLoud`). Per §11's discipline (no
   empirical corrections baked into the algorithm without a physical
   basis), the fix is an explicit, visible, user-driven override rather
   than a silent nudge:
   - `Sidecar` gains `yawManualAdjustDeg` (degrees, default 0), saved/loaded
     in the sidecar JSON (`yaw_manual_adjust_deg`) so it persists with that
     data record. Distinct from the existing `yawDatumDeg` (paddle-vs-boat
     rest offset, informational, §7.6) — this new field is consumed
     directly by `CatchEvents.compute()`, added to its own auto-computed
     datum before placing every event.
   - `CatchEvents` exposes `datumAutoDeg` (the value before the manual
     adjustment) so the two can be shown side by side.
   - Slice 0 (`drawHUD_slice0()`) gained a second block, "Entry/exit yaw
     datum (data record)", showing the auto value (and whether it came
     from the sidecar rest window or a whole-file fallback mean), the
     current manual adjustment, and their wrapped sum. `n`/`N` nudge the
     manual value by the same step size as the model-triple keys
     (`cal.stepDeg`, adjustable with `[`/`]`); `g` resets it to 0. Nudging
     requires a sidecar to already exist (`C` run at least once) — the
     override lives inside it. Every nudge triggers `rebuildCatchEvents()`
     (fast — offline biquad filtering over the whole CSV, unnoticeable at
     interactive keypress rates) and a quiet re-save of the sidecar.
   - **Open question, not resolved by this change:** whether correcting the
     yaw fixes the left-deeper-than-right asymmetry too, or whether that is
     a separate, real effect (paddling style, blade geometry, or a second
     miscalibration) — to be checked once the user has re-run `C` and
     nudged the datum on a known session. This is a stated stop-gap "until
     a better calibration routine can be devised" (user, 20 Jul 2026), not
     a claimed fix for the underlying automatic-datum algorithm.

5. **n/N/g were wrongly gated to Slice 0 only.** As first written, the
   nudge/reset handling sat inside `keyPressed()`'s `if (sliceMode == 0)`
   branch alongside the model-triple keys — but the entry/exit panel that
   shows the effect is only visible in slices 1-3 (`isPanelVisible()`), so
   the user could never watch the panel move while nudging, and pressing
   n/N/g while actually in a data slice did nothing at all (found by the
   user immediately after the first v0.15 push, 20 Jul 2026). Fixed by
   moving the three keys to the always-active section of `keyPressed()`
   (with `p`/`b`/slice-switch), before the `sliceMode == 0` branch — they
   now work in every slice, while the model-mesh triple keys stay
   Slice-0-only as before. `Menu.pde`'s entries moved out of the
   slice-0-conditional block into the always-shown ENTRY/EXIT PANEL
   section, and became clickable rows rather than info-only.

6. **Paddle base position in Slice C.** The user reports the paddle's
   centre sits, on average, about 0.45 m toward the bow of the physical
   boat's centre — a measured fact, distinct from the existing
   `PADDLE_LIFT_M = 0.3` deck-clearance constant (which is a pure display
   convenience, not a measurement). `drawSliceC()`'s paddle-lift translate
   now also carries `PADDLE_BOW_OFFSET_M = 0.45` along kayak-body +Y (bow —
   `Model3D.drawKayak()`'s convention, matching the boat sensor axes). The
   accel-derived paddle-centre wobble (§12.12) is applied on top, unchanged
   — it oscillates around this new base position instead of around the
   kayak origin. Slice A (paddle alone, no kayak reference) is unaffected.

7. **The manual yaw datum didn't reach the 3D view.** User feedback after
   items 4–6 landed: the entry/exit panel now looks right, but "it is the
   visualisation of the paddle relative to the boat that is out" — i.e.
   `drawSliceC()`'s 3D paddle-vs-kayak render, not the 2D panel. These are
   two independent computations: the panel uses `CatchEvents`' own
   circular-mean datum (fixed by items 4/5); the 3D view uses `qRelDisp`,
   built from the rest-window mean-quat subtraction (`qRelRef`, §7.6) with
   no manual-correction path at all. Fixed by applying the *same*
   `sidecar.yawManualAdjustDeg` value as an extra rotation on `qRelDisp`
   about the kayak's own Z (deck-up) axis, composed on the outside so it
   spins the paddle around the kayak's vertical without touching tilt:
   `qRelDisp = qMul(qYawCorr, qRelDisp)` where `qYawCorr` is a pure-Z
   quaternion built from `-radians(yawManualAdjustDeg)` — negated to match
   the same rotational sense already validated against the entry/exit
   panel (positive nudge → clockwise correction, viewed from above).
   **Sign not independently verified for the 3D view** — if `n` moves the
   panel the right way but rotates the paddle the wrong way in Slice C,
   flip the sign in that one line. One HUD block and one manual value now
   drive both renders (relabelled "Paddle-vs-boat yaw datum" from
   "Entry/exit yaw datum").
   - **Underlying suspected cause, not yet root-caused:** the rest-window
     subtraction assumes the paddle-vs-boat relative yaw measured at rest
     stays valid through the whole session. If the paddle's magnetometer
     calibration was still converging during the rest window (field
     evidence: mag_cal reached 3 for only 75 % of one session, see
     calibration_phase10 memory), the captured rest-window relative yaw
     would carry whatever bias existed at that lower-confidence moment,
     baking a constant offset into every subsequent frame. Untested.

8. **Item 6's bow offset only reached the 3D view, not the panel.** User
   asked directly whether the +0.45 m bow offset (item 6) had been applied
   to the entry/exit panel too — it hadn't. `drawSliceC()`'s mesh translate
   and `CatchEvents.addEventIfLoud()`'s `xB`/`yB` computation are separate
   code paths (same pattern as item 7's bug): the panel's `e.yB = r *
   sin(a)` implicitly places the shaft centre at the boat's own
   centre/cockpit, with no reference to the measured offset at all.
   `PADDLE_BOW_OFFSET_M` promoted from a `drawSliceC()`-local constant to a
   global (top of `PadViz6.pde`, next to `MODEL_SCALE`) so both places read
   the same value; `addEventIfLoud` now computes `e.yB = r * sin(a) +
   PADDLE_BOW_OFFSET_M` (bow = +Y in both the 3D kayak-body frame and the
   panel's boat-frame convention, so it's the same axis both places).

9. **Root cause found and fixed: `drawSliceC()` had never switched to GRV.**
   Investigation (not-yet-implement pass, then implemented on request)
   after the user reported the panel now looked right at manual = 0 but
   the 3D paddle-vs-kayak render still needed roughly +60° to look
   correct — and that a +60° manual nudge then rotated the (already
   correct) panel by 60°, since one manual value drove both. `CatchEvents`
   had already switched to GRV (mag-free) for the shaft-heading/boat-
   heading comparison per the project's own §16.11 verdict (fused yaw
   carries an in-band cycle-periodic mag artefact for exactly this
   quantity); `drawSliceC()` was never updated to match and stayed
   entirely fused-quat-based — `qPad`/`qBoat`/`qRel`/`qRefPad`/`qRefBoat`/
   `qRelRef` all read `.qw/qx/qy/qz`, never `.grvQw` etc. A rest-window (or
   `k`-capture) instant landing while the paddle's magnetometer was still
   at low `mag_cal` (field evidence: 3 % of one full session at
   `mag_cal=0`, 31 % at `mag_cal=1` — plausible for a window taken near
   the start of a session) would bake an uncalibrated-magnetometer yaw
   bias into `qRefPad`, large enough to plausibly explain ~60°, on top of
   this render path only (the panel's GRV-based datum is immune to it).
   **Fix implemented:**
   - `DataSource.meanQuatGrv()` / `BoatSource.meanQuatGrv()` — GRV
     counterparts of the existing `meanQuat()` (same antipodal-sign
     handling, reads `grvQw/x/y/z`).
   - New globals `qRefPadGrv`/`qRefBoatGrv`, captured alongside
     `qRefPad`/`qRefBoat` everywhere the latter are set for Slice C use —
     `applySidecarToDisplay()`, `buildAndSaveSidecar()`, and
     `handleFrameNavCombined()`'s `k`/`u` (Slice A/B's own single-sensor
     `k` captures are untouched — this is Slice-C-only).
   - `drawSliceC()` computes `useGrvC = paddleData.hasGrv &&
     boatData.hasGrv` (gated on *both* files, never mixing GRV one side
     with fused the other) and switches `qPad`, `qBoat` (so the kayak's own
     displayed orientation is now GRV-based too when available, not just
     the paddle), and the rest-window references, accordingly. The
     manual-override rotation (item 7) still applies on top, now expected
     to be a small residual correction (e.g. for genuine mechanical mount
     misalignment) rather than the ~60° that was compensating for the
     fused-quat magnetic bias.
   - Slice C HUD gained a status line: `relative-yaw source: GRV
     (mag-free)` (green) or `fused (no GRV in one or both files)` (amber)
     — mirrors `CatchEvents.status`'s transparency for the panel.
   - **Confirmed by the user, 20 Jul 2026** ("that sorted the problem") —
     the fused-vs-GRV mismatch was the actual root cause, not a
     coincidental fudge that happened to also work. Both views now agree
     without the ~60° manual override. §13.7's investigation is closed;
     items 4/7's manual yaw-datum override remains in place as a small
     residual-adjustment mechanism, not as the primary fix.

10. **CSV-filtered file pickers — three attempts, reverted to the
    zero-risk option.** `p`/`b` used Processing's `selectInput()`, which
    has no extension-filter option — the dialog listed every file in the
    folder. Wanted: restrict the OS dialog's listing to `.csv`/`.CSV`.
    - **v1** — custom `java.awt.FileDialog` + `FilenameFilter`, callback
      via `getClass().getMethod(name, File.class)` reflection.
      **Broke `p`/`b` entirely**: `getMethod()` only finds *public*
      methods, and a `.pde` function with no explicit `public` compiles
      to package-private, so the lookup always threw
      `NoSuchMethodException` — silently caught by a
      `catch (Exception e) { println(...); }` that only wrote to the
      console.
    - **v2** — same custom dialog, callback fixed to a direct call
      (`boolean isPaddle` instead of reflection). **Still didn't work**
      (user, same day) — the dialog was created/shown on a raw background
      `Thread`; AWT/Swing components are only reliably created off the
      Event Dispatch Thread when marshalled there deliberately, and a
      native dialog built off-EDT can fail to display with no exception
      to report, especially alongside a JOGL/P3D window.
    - **v3** — same dialog, callback now via `EventQueue.invokeLater()`
      (matching how Processing's own `selectInput()` avoids exactly this
      problem internally) plus a try/catch around dialog creation that
      flashes an on-screen error instead of only logging to console.
      **Not deployed** — after two consecutive failures on something this
      environment cannot run and observe directly, continuing to guess at
      a third native-dialog variant was the wrong call.
    - **Final: reverted to `selectInput()`.** `selectCsvInput()` now just
      calls Processing's own `selectInput(prompt, "onPaddleFileSelected"
      | "onBoatFileSelected")` — proven reliable for this sketch's entire
      history. The `.csv`-only requirement is met differently: a new
      `isCsv(File)` check inside `onPaddleFileSelected`/
      `onBoatFileSelected` rejects a non-`.csv` selection with an
      on-screen flash (`"PADDLE CSV — please choose a .csv file"` /
      `"BOAT CSV — ..."`) instead of loading it. Trade-off: the OS dialog
      once again lists every file in the folder (not just `.csv`), but
      loading is guaranteed to work, which is the higher priority. See
      [[feedback_processing_compile_vs_runtime]].

### 13.8 v0.15 continued — collapsible detail panel + stroke-average panel

Requested after the yaw-fix round: the scattered HUD text (file details,
sidecar/yaw-datum corrections, current-data-point readout) was cluttering
the main view with no way to hide it, and a companion to the entry/exit
panel was wanted — an averaged stroke-shape trace, symmetric on the right.

1. **`DetailPanel.pde`** (new) — collapsible box for everything `drawHUD()`
   used to draw straight onto the 3D view below the title line: the
   sidecar/yaw-datum indicator and the per-slice `drawHUD_slice0/A/B/C()`
   readout. Minimised shows only a `Detail ▾` button; expanded shows the
   button plus a bordered box containing that content, unchanged
   internally — the existing `drawHUD_sliceX()` functions weren't
   rewritten, just wrapped: `drawHUD()` shifts the whole block down by a
   fixed offset (`pushMatrix(); translate(0, 40); ... popMatrix();`) so
   the pre-existing hardcoded y-coordinates land inside the box instead of
   under the new button. The model-calibration-file footer moved from the
   literal window bottom to the bottom of the box. Toggled by clicking the
   button; state isn't persisted (always starts expanded).
   - **Layout fix, same day.** First version put the title line and the
     Commands button on the same row (the pre-existing v0.14 layout) and
     the new Detail button on its own row below — user asked for the
     title on its own top line, with Commands and Detail side by side on
     the row below. Moved the title to `(20, 10)` (no longer needs to
     dodge Commands horizontally now they're on different rows); `Menu.
     BTN_Y` and `DetailPanel.BTN_Y` both became `38`, `DetailPanel.BTN_X`
     became `148` (Commands' local x 20 + its width 118 + a 10 px gap) and
     `DetailPanel.BTN_H` became `26` to match `Menu.BTN_H` so both buttons'
     tops and bottoms line up. `DetailPanel.BOX_Y` (`BTN_Y+BTN_H+6`) comes
     out to `70` either way, so the box position and the content
     `translate(0, 40)` offset needed no change.
2. **`StrokeAveragePanel.pde`** (new) — right-hand mirror of
   `EntryExitPanel`, same width (`rightPanelWidth()`, same 20% formula and
   visibility condition as `leftPanelWidth()`/`isPanelVisible()`), height
   (stops above the graph strip), and top-down boat-frame grid/kayak
   outline. `CatchEvents` now also collects `rightRuns`/`leftRuns` (the
   same `runStart`/`runEnd` pairs the entry/exit events are built from,
   same `MIN_RUN_S`/`MAX_RUN_S` gate). A run counts once the playback
   cursor passes its end frame — mirrors `EntryExitPanel`'s dot
   accumulation, so play-through builds the picture and scrubbing back
   removes strokes again. Right-click restarts the accumulation from the
   current frame; independent of the left panel's reset (each panel's
   `mousePressed()` branch only checks clicks inside its own bounds).
   - **First version plotted roll vs. normalised stroke phase** (a line
     chart, not an XY-plane view) — the user then asked for "the average
     position of each blade in the xy plane between the entry and exit
     points" instead, i.e. the averaged *path* the blade tip takes through
     the water, in the same boat-frame coordinates as the entry/exit
     panel. Redesigned: `CatchEvents` exposes `phi`/`psiRef`/`hMag`/
     `datumEff` as fields (were locals inside `compute()`) plus a new
     `bladeXY(frame, rightBlade)` method — the same boat-frame position
     formula `addEventIfLoud()` already used for one event frame, now
     callable for any frame in a run so the *whole path* between entry and
     exit can be traced, not just its two endpoints. Each run's path is
     resampled to 24 points and averaged per blade; drawn as a connected
     curve on the same grid/kayak-outline the entry/exit panel uses, with
     a filled dot at the averaged entry point and a hollow ring at the
     averaged exit point (same convention as the dots on the left panel).
     Green = left, red = right.
3. **Layout knock-on effects** — `drawAxisLegend()`'s x-position now
   subtracts `rightPanelWidth()` so its text doesn't sit behind the new
   panel; the graph strip is unaffected (it already spans the full window
   width beneath both side panels, which only occupy the region above it —
   same pattern the entry/exit panel established in v0.14). `Menu.pde`
   gained entries for both panels' right-click behaviour and the Detail
   button.
4. **Error flashes now persist until dismissed.** The top-centre HUD flash
   (`triggerRefFlash`/`drawRefFlash`) auto-faded after 1.5 s regardless of
   message — too short to reliably read an error before it vanished (user,
   20 Jul 2026). New `triggerErrorFlash(msg)` sets `refFlashIsError=true`
   instead of a timeout; `drawRefFlash()` renders it in a red-tinted style
   with a `[click to dismiss]` suffix and stores its on-screen bounds
   (`flashBoxL/R/T/B`); `mousePressed()` checks `dismissFlashClicked()`
   first, ahead of every other overlay, since the flash draws on top of
   everything. Applied to the genuinely error/blocker-toned triggers
   (non-`.csv` file rejection, "load paddle CSV first", sidecar build
   failure/save failure, "build sidecar before nudging yaw datum") — plain
   confirmations (ref captured, sidecar built, playback speed, panel
   reset, etc.) keep the original short auto-fade.

### 13.9 v0.15 session close (20 Jul 2026)

User: "that is enough on visualisation for this session, it is doing what
I want for now." PadViz6 v0.15 accepted at this state — the round of
fixes in §13.7–13.8 (pitch key, playback speed, panel clear, manual
yaw-datum override, bow offset, the GRV root-cause fix, CSV-picker
reliability, layout, persistent error flashes, and the blade-path
redesign) is considered done for this session, not still-open work.
Remaining items are tracked separately, not blocking: zero-feather XY
sanity on screen, per-event stroke-length labels, decomposed sidecar
rendering (§7.6), the Slice C field-validation retest noted in §12.9.
Attention moves to firmware next (spec §16.12, zero-feather CPM).

Compiles clean via `processing-java --build`. User's first on-screen check
found the two issues above (layout, p/b regression); both addressed same
day. The stroke-average panel then went through the roll-trace →
XY-path redesign and the error-flash change, also same day; none of this
round re-confirmed on screen yet.

---

## 14. PadViz7 (v0.16) — session-setup wizard + classification (21 Jul 2026)

PadViz7 is a **new sketch** (`visualisation/PadViz7/`), forked from PadViz6 at
v0.15 per the user's 21 Jul request ("make this rewrite a new version of
padviz" — following the project's PadViz → … → PadViz6 lineage). PadViz6 is
left untouched. PadViz7 adds two things asked for in
`instructions20260721.txt`:

1. A **guided session-setup wizard** replacing the free-floating
   `Checklist.pde` overlay, walking the user step-by-step through loading
   files and calibrating a session, with the instructions and error messages
   collected into one docked panel.
2. A **Classification Section** in the per-session sidecar recording which
   stretches of the recording are good right-handed / left-handed /
   zero-feather paddling, or should be excluded entirely (e.g. the drive home
   with the units still logging). This replaces the note file the user kept
   by hand; it supersedes the hardcoded `SEGMENTS` dict at the top of
   `visualisation/stroke_catch_explore.py` as the source of truth for future
   sessions.

### 14.1 Files

- **`Wizard.pde` (new)** — the 5-step state machine and the docked
  instructions/status panel. Absorbs all instructions and error messages;
  `triggerErrorFlash()` routes into this panel while the wizard is active,
  falling back to the old top-centre click-to-dismiss flash otherwise.
- **`Classification.pde` (new)** — `ClassificationSection` (persisted record:
  inclusive `start_frame`/`end_frame`, `type` ∈ right/left/zero/excluded), the
  in-progress marking mini-state-machine, the graph shading, and the
  frame-visibility index (`visiblePos`/`rawForVisiblePos`/`stepVisible`/
  `nearestVisible`) that makes EXCLUDED ranges occupy no pixels and be
  unreachable by any navigation path.
- **`Sidecar.pde`** — gains `ArrayList<ClassificationSection> classification`
  with JSON save/load of the `classification_sections` array (§7.5). The
  rest-window / offsets / yaw-datum fields are unchanged.
- **`GraphPanel.pde`** — chart pixel↔frame math is now exclusion-aware
  (interpolates in visible-position space); new public `chartXForFrame()`
  (inverse of `frameFromChartX`). With zero exclusions the behaviour is
  bit-identical to PadViz6 (the zero-exclusion special case, not a separate
  code path).
- **`PadViz7.pde`** — `Wizard`/`Classification` wired in place of `Checklist`;
  `stepPlayback()` and the `,`/`.`/arrow/Home/End branches in
  `handleFrameNavPaddle`/`handleFrameNavCombined` route through
  `classify.stepVisible()`; `buildAndSaveSidecar()` now returns a boolean;
  Detail panel gains a classification summary line.
- **`Checklist.pde` (removed)** — the wizard is a strict superset.

### 14.2 Steps

Keys are step-scoped: while the wizard is active it consumes only the keys
meaningful to the current step (Return, `X`, `r/R`, `l/L`, `z/Z`, `d/D`,
`a/A`, `f/F`); everything else — digits, Space, arrows, `,`/`.` — falls
through so the user can still move the graph cursor to position for Steps 3
and 4. **F1** shows/hides the panel at any time.

- **Step 1 — paddle CSV.** `Return` = choose. File must start `pad`, end
  `.csv`. Auto-advances on load.
- **Step 2 — boat CSV (optional).** `Return` = choose (must start `boat`, end
  `.csv`); `X` = skip (paddle-only session, sidecar confidence "medium").
- **Step 3 — roll calibration.**
  - *3a* (no saved rest window): "position the cursor at the start of a still
    moment, press Return" → `buildAndSaveSidecar()` (unchanged `C`-key path,
    search from the current frame). Failure shows in the panel, stays on 3a.
  - *3b* (saved rest window, e.g. auto-loaded): shows its summary. `Return` =
    use it → Step 4. `r/R` = discard the whole sidecar → falls back to 3a.
- **Step 4 — classification.**
  - *4a* (no entries): `Return` marks the section **start** (yellow cursor);
    `Return` again marks the **end** (red cursor); then classify: `r/R` right,
    `l/L` left, `z/Z` zero-feather, `d/D` exclude, `a/A` abort the pair, `f/F`
    finish. Overlap check (`a ≤ end_b && start_b ≤ b`, any two sections any
    type) — an overlap raises a click-to-dismiss warning and clears the
    pending pair. Each commit quiet-saves the sidecar and re-shades; `d/D`
    also rebuilds the exclusion index so the range is cut immediately.
  - *4b* (entries loaded from file): shows a summary. `Return` = use them →
    Step 5. `r/R` = clear and restart 4a.
- **Step 5 — done.** Short dismiss delay, then hides. `C`/`n`/`N`/`g` and the
  other expert keys remain live afterward, unchanged. F1 re-opens Step 0 as a
  read-only summary and never restarts the wizard.

### 14.3 Excluding data from graph + navigation

`Classification` maintains, rebuilt whenever `sidecar.classification` or the
paddle CSV changes: `posOf[raw]` (monotonic visible position, next-visible for
excluded frames), `rawOf[vpos]` (inverse), `excl[raw]`. `GraphPanel`
interpolates the chart in visible-position space, so excluded stretches occupy
no pixels and can never be clicked into — the literal "delete it from the
graph" the user asked for. A single `stepVisible(raw, deltaVisiblePositions)`
helper centralises "move N steps, skipping excluded ranges" and is used by
autoplay and every arrow/`,`/`.`/Home/End nav path in Slice A and Slice C
(Slice B, boat-only, is out of scope — classification is paddle-anchored).
`zoomA`/`zoomB`/`selPendingA/B`/export keep storing **raw** paddle-frame
indices, so zoom-to-range and CSV export are unchanged and the data file is
never modified. The Detail panel gains a summary line (counts per type + total
excluded seconds).

### 14.4 Status

BUILT 21 Jul 2026, compiles clean via `processing-java --build` (Processing
4.3). **Not yet confirmed on screen** — per `feedback_processing_compile_vs_runtime`,
`--build` does not exercise the keyboard/click flow of the wizard, the graph
exclusion geometry, or the shading/cursor rendering. The concentrated
runtime risk is: the Step-4 marking state machine (yellow→red→classify→
overlap→commit), the exclusion-aware pixel↔frame mapping, and F1 toggle
behaviour. Hand-back item: an on-screen walkthrough against a real CSV pair
(fresh session with no sidecar, then a re-open to exercise 3b/4b).

**On-screen check 23 Jul 2026 (§14.5):** the wizard was run against a real
session — Step 3b (saved calibration found → "use it") reached, the setup
window / Commands menu / Slice-0 nudge exercised and refined, and the **Step-4
classification marking flow (4a) confirmed working**: right / left / zero
sections were marked and persisted correctly to the sidecar
`classification_sections` array (verified in `PadLog20260716.session.json` —
four sections). The `d/D` **exclude** type is also **confirmed working** — an
excluded section was cut out of the graph and stayed excluded on reload. So the
wizard + classification feature (all four types + exclusion geometry) is fully
validated on screen.

### 14.6 v0.18 — saved-session loader + stroke-average metrics (23 Jul 2026)

1. **One-step saved-session load.** If `visualisation/recordings/` holds any
   `*.session.json` at startup (`g_sessionsAvailable`, checked once in
   `setup()`), wizard Step 1 offers `J` = pick a saved session. `J` opens a
   file dialog (starting in `recordings/`); `onSessionJsonSelected()` reads the
   JSON's `paddle_csv` / `boat_csv` (bare names next to it), loads the paddle
   CSV (which auto-loads the sibling sidecar), then the boat CSV, forces the
   picked sidecar (calibration + classification) as the active one, and jumps
   straight to the ready view (`Wizard.gotoStep5()`) — no further wizard input.
   Falls back gracefully with an on-screen message if the JSON or a named CSV
   is missing.
2. **Stroke-average panel metrics.** `StrokeAveragePanel` footer now shows, per
   blade (colour-coded), the number of strokes in the average **plus** the
   averaged entry→exit **time** (from paddle-frame timestamps at run
   start/end) and the straight-line entry→exit **distance** (boat-frame gap
   between the entry and exit blade positions), over the same qualifying runs
   the averaged path uses. `right: 4 strokes  1.23 s  0.85 m`.
3. **Calibration methodology — flagged to revisit.** A 1° yaw-datum nudge
   (§14.5 item 5) produces a visibly significant change, meaning the rest-pose
   alignment (paddle held exactly along the kayak axis) matters more than the
   current three-offset accel-rest-window procedure (§7) captures — the
   magnetic yaw datum in particular is sensitive to a slightly off hold. To
   revisit: whether the rest-pose instructions/tolerances are tight enough,
   whether a second (deliberately-aligned) reference capture would pin the yaw
   datum better, or whether GRV relative yaw should drive the datum directly.

### 14.5 v0.17 — UI polish (23 Jul 2026)

On-screen review of PadViz7 produced a round of presentation fixes (all built
+ compile clean; grey/scroll/setup-screen confirmed on screen, user "better"):

1. **Opaque grey panels.** The setup wizard panel (`Wizard.pde`) and the
   Commands drop-down (`Menu.pde`) use an opaque neutral grey (`fill(80,80,80)`)
   instead of the dark blue-black. The earlier translucent alpha let the busy
   scene behind wash out the text.
2. **Scrollable Commands drop-down.** The full command list ran off the bottom
   of the window. The drop-down is now height-capped to the space above the
   graph strip (full window height in Slice 0) with a right-edge slide bar —
   draggable thumb, mouse-wheel scroll, and click-the-track paging; rows are
   culled to the viewport. `clip()` was tried first but in P3D it flushes the
   pipeline and re-enables the depth test, so the axis compass behind the menu
   punched through the drop-down text — dropped in favour of row-culling.
3. **File dialogs start in `visualisation/recordings/`.** `selectCsvInput()`
   passes a placeholder child of that folder as the default selection (its
   parent is the opening directory under Processing's FileDialog path); the
   placeholder has no `.csv` extension so an accidental "open" is rejected by
   the existing `isCsv()` guard. Falls back to the sketch folder if the
   directory is missing.
4. **Setup window owns the screen.** A compact panel cannot physically cover
   full-height side panels, the bottom compass, or the legend, and in P3D even
   an opaque fill let them bleed. So while the setup/summary window is shown,
   `PadViz7.draw()` skips the 3D scene and every analysis overlay (side panels,
   HUD + detail box, axis compass + legend); only the graph strip stays (needed
   for cursor positioning in Steps 3 and 4). Full view returns on dismiss.
5. **Slice 0 nudge step 5°→1°.** `Calibration.stepDeg` default lowered for
   finer correction of an imprecise rest-pose hold; `[` / `]` still
   halve/double at runtime, `g` resets the yaw-datum adjust.

### 14.7 v0.19 — compass moved right + stroke symmetry overlay (23 Jul 2026)

(Subsection numbering runs 14.4 → 14.6 → 14.5 → 14.7 in the file; each is
version-tagged — read by the vN.N tag, not the ordinal.)

1. **Axis compass moved to the bottom-RIGHT corner** (`drawAxisCompass()`,
   `ox = width - leftPanelWidth() - rightPanelWidth() - 100`), just left of the
   right stroke-average panel. It was bottom-left, under the Commands
   drop-down, which in P3D still doesn't reliably occlude it (the depth-test
   bleed the menu clip-removal only partly addressed). Moving it sidesteps the
   overlap rather than fully solving the occlusion.
2. **Stroke-average symmetry overlay.** `o` (free key; also in the Commands
   menu's stroke-average section) toggles `StrokeAveragePanel.mirrorOverlay`:
   the right blade's averaged path is reflected about the Y (fore-aft) axis
   (x→−x) and drawn on top of the left path, so left/right asymmetry reads as
   the gap between the two curves. Off = the original side-by-side plot. The
   per-blade time/distance/count footer (§14.6) is unchanged either way. Driven
   by the user noticing the two blade traces are not symmetric.

### 14.8 v0.20 — side panels scaled to fill the window (23 Jul 2026)

Both side panels drew a small plot in the middle of an otherwise-empty tall
column because the plot scale was tied to the narrow panel **width**
(`(w-26)/(2·RANGE_X_M)`). Now the scale is fitted to the plot **height** so the
kayak length fills the vertical space:
`scale = min((plotBot-plotTop)/(2·VIEW_HALF_LEN_M), (w-12)/(2·MIN_HALF_X_M))`,
with `VIEW_HALF_LEN_M = 2.45` (kayak half-length + margin) and `MIN_HALF_X_M =
1.0` (a horizontal cap so blade paths can't overflow the width). Result: the
kayak fills ~94% of the plot height (was ~59%), a **~1.5×** enlargement — not a
literal 2× because that's the most zoom that keeps the whole kayak in view; a
true 2× would need to crop the bow/stern. Grid rings reduced to 0.5 m / 1 m (the
2 m ring would overflow at the larger scale). Fonts increased throughout
(titles 14→18, legends 10→13, footers/axes 9→11), event dots 7→9 px, footer
laid out with more vertical room. Applies to both `EntryExitPanel` and
`StrokeAveragePanel` identically.

### 14.9 side-profile blade-immersion window + real paddle geometry (v0.21–0.24, 7–12 Aug 2026)

A second full-window **alternative** view (like the setup wizard, it owns the
screen rather than drawing on top — `draw()` skips the 3D scene, both side
panels, the HUD, the axis compass and the legend while it's shown; only the
bottom graph strip stays, so playback still scrubs it). New file
`SideProfilePanel.pde`. **Confirmed working on screen 7 Aug** (`x` opens it,
`m` opens the dimension prompt).

**Keys (v0.23).** Toggled with **`x`** (session wizard moved to **`w`**);
F1/F2 kept as alternates. The window keys were rebound off the function row
because the F-keys are Fn-shifted on the user's laptop and weren't reaching the
sketch. Both letter cases are handled (Caps-Lock-safe). Both are on the Commands
menu under an "ANALYSIS WINDOWS" header. Opening it from a non-paddle slice
(0 or 2) switches to Slice A (or C if a boat CSV is loaded) so the paddle
timeline drives it; opening with no paddle CSV flashes a hint.

**Layout.** Split **horizontally** into two side-on (boat **ZY** plane)
profiles, each showing ONE blade edge-on down the boat's across-boat (X) axis:

- **TOP — LEFT blade**, viewed from the **port** side (looking +X, from −X) →
  bow (+Y) on the screen **left**, blade drawn **yellow**.
- **BOTTOM — RIGHT blade**, viewed from the **starboard** side (looking −X,
  from +X) → bow (+Y) on the screen **right**, blade drawn **red**.

The two halves look at the boat from **opposite** sides, so +Y falls on
opposite screen sides — hence the **bow is marked red** on each: it removes the
L/R ambiguity.

**Real hull outline (v0.24).** The kayak is drawn as the **real sea-kayak side
profile** traced from `visualisation/seakayakside.svg` (a Visio SVG export the
user supplied), scaled to its true **5.1816 m (17 ft)** length — **outline
only**, no deck/cockpit detail. The 13-vertex outline is baked into
`SideProfilePanel.HULL` in metres (SVG units × 0.0107526; y flipped, keel
datum). It is positioned so:
- its **waterline** — a fixed **0.1143 m (4.5 in)** above the keel, the hull's
  real draft — coincides with the blue mean-catch waterline; and
- the paddle **shaft centre sits 0.3048 m (1 ft) forward** of the hull
  mid-point (`boatCentreY = PADDLE_BOW_OFFSET_M − 0.3048`), so the blade band
  lands where the paddler actually reaches.
The forward **nose** of that outline (forefoot → bow tip → deck, `HULL[5..8]`)
is filled **red** as the bow marker, so the coloured area overlays the real
hull rather than floating past its tip. `VIEW_HALF_LEN_M` raised 2.45→2.90 to
fit the 17 ft hull with the forward offset.

**Blade-immersion rendering (v0.22, band v0.24).** The blade is drawn as a
**physical segment** (`CatchEvents.bladeSegmentYZ`) throat→tip:
- the **live blade** at the playback cursor (bold) is drawn **only while it is
  in the water** — its tip below the waterline, immersed to any extent
  (`bladeTipZ < waterM`); on the out-of-water recovery it isn't shown;
- **persistent immersion band (v0.24):** at **every** in-water frame up to the
  cursor (stepped by 2 for cost), the **immersed part** of the blade — clipped
  at the waterline down to the tip (`drawImmersed`) — is drawn faintly, so the
  marks accumulate into a **band of colour along the hull side** showing where
  and how deep the blade works across the whole session. (This replaces v0.22's
  faint-blade-at-each-stroke's-deepest-point; right-click still restarts the
  accumulation via `resetAtFrame`.)
- a **blue waterline** referenced to the blade **tip** (`bladeTipZ`, the leading
  edge that enters first), averaged over all catches of that blade — this fixed
  the earlier error of referencing the blade *centre* (~10–14 cm too high);
- footer: stroke count + average / max **immersion depth** below the water.

The **vertical scale is fixed** (`Z_TOP_M..Z_BOT_M` vs the hands/shaft centre),
so the panels don't resize as strokes accumulate (they did in v0.21). Fore/aft
(Y) is a fixed scale fitting the whole kayak length across the width; the two
axes have different px/metre, so both carry metre tick labels. All lengths in
this view are **metric**. **Confirmed working on screen 12 Aug** (hull, red bow,
accumulating band, in-water-only live blade; not sluggish).

**Real paddle geometry (v0.23).** The paddle **total length** and **blade
length** are now session metadata, stored in the sidecar
(`paddle_total_length_m` / `blade_length_m`) and shown in the metadata (Detail)
panel. They drive two things: the **3D paddle model is scaled to the total
length** (`paddle60.obj` is 1.8182 m native tip-to-tip; `Model3D.drawPaddle`
applies `MODEL_SCALE · total / native`), and the **side-view blade geometry**
(`CatchEvents.visBladeCentreM = (total − blade)/2`, `visBladeLenM = blade`; tip
radius = total/2). The **catch detector is untouched** (keeps `BLADE_L`), so
changing the recorded length re-sizes the drawing but never shifts which catches
are detected. Defaults 2.10 m / 0.32 m.

**Dimension entry (v0.23).** Pressing **`m`** (or building a sidecar with `C`)
opens a small **in-sketch numeric prompt** — paddle total length, then blade
length — each **pre-filled with the last-used value** (blank = keep last), so
the common case is Enter, Enter. No AWT dialog (OS dialogs unreliable on this
setup). Values persist to `paddle_dims.json` in the sketch folder and become
the default for the next session; on accept they're pushed into the loaded
sidecar and the catch events rebuilt. (The wizard's own Step-3 build uses the
last-used values silently; `m`/`C` are the interactive path.)

**Version stamp.** `PadViz7.pde` now carries a `LAST EDITED` banner at the top
and a `BUILD_STAMP` fed to the window title bar, so the running/open version is
identifiable at a glance (added after real confusion over whether the IDE was
running stale code).

### 14.10 view-switch tabs + axis-definition relocation (v0.25, 12 Aug 2026)

**View-switch tabs (`Tabs.pde`).** A clickable tab bar switches between the two
mutually-exclusive full-window views — **3D VIEW** and **SIDE PROFILE** — as an
alternative to the `x` key. The active view's tab is highlighted (the highlight
reads the real view state, so it's correct however the view was last changed).
Clicks route through a single shared helper `showSideProfile(boolean)` that the
`x` key and the Commands menu also call, so keyboard and mouse never drift out of
sync. The bar is hidden while the setup **Wizard** owns the screen, drawn last in
`draw()`, and hit-tested **after** the Commands drop-down (so an open menu wins).
Room is reserved for a third **track plot** tab later.

*Placement.* The top row is crowded — the HUD title runs left-of-centre — so the
bar is docked into the constant-width (~230 px) gap just left of the right-hand
panel, right-aligned via `barX() = width − rightPanelWidth() − margin − barW()`.
That slot is clear in both views. Tabs are compact (`TAB_W = 70`); each label's
font auto-shrinks (`fitSize()`, floor 8 pt) so "SIDE PROFILE" fits the narrow tab
while "3D VIEW" stays full size.

**Axis definitions moved into the Detail box.** The old top-right floating axis
legend (`+X/+Y/+Z` sensor-axis definitions) sat under the HUD title on the main
view. It's now a single colour-coded line **inside the Detail box**
(`drawAxisDefs()`, just above the classification/footer lines), so it only shows
when the Detail panel is open and no longer clutters the 3D view. It still
follows the slice (boat-frame axes for B/C, paddle-frame otherwise). Confirmed on
screen 12 Aug.

---

## 15. PadViz8 (v0.26) — GPS track window over an OpenStreetMap backdrop (12 Aug 2026)

v0.26 forks a **new sketch `PadViz8/`** from PadViz7 v0.25 (per the user: "Create
new sketch PadViz8 and don't overwrite the working PadViz7" — the network fetch
carried a slight risk, so the working sketch is preserved). PadViz7 stays at v0.25.

### 15.1 Track window (`TrackPanel.pde`, key `t` + TRACK tab)

A **third** full-window alternative view alongside 3D and SIDE PROFILE, in the same
screen-owning style (draws over the whole window above the graph strip; the graph
strip still scrubs). It plots the **whole boat GPS track** — every valid lat/lon row
of the loaded boat CSV — as a polyline, georeferenced over a live **OpenStreetMap**
street backdrop.

- **Bounds scan.** On first show (and on boat-CSV reload via `invalidate()`), the
  panel scans the boat frames once for the lat/lon bounding box (`BoatSource
  .latLonRange()`), skipping invalid fixes (`gpsFix` false, |lat|>90, |lon|>180,
  or the 0,0 null-island). No GPS → the view flashes "load a boat CSV with GPS
  first" and stays on the current view.
- **Projection.** Web Mercator (EPSG:3857), the OSM slippy-map convention:
  `worldX = (lon+180)/360·S`, `worldY = (0.5 − ln((1+sin φ)/(1−sin φ))/4π)·S`,
  `S = 256·2^z`. North is up (smaller Y). Zoom `z` is the highest level (3..18) at
  which the track's bbox still fits `FILL = 0.90` of the plot rectangle.
- **Backdrop tiles.** `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, fetched on a
  daemon **background thread** (a `LinkedBlockingQueue` of tile keys, results in a
  `ConcurrentHashMap`) so the sketch never blocks on the network. Each tile is
  disk-cached under `visualisation/PadViz8/tilecache/` (git-ignored) and reused on
  later runs — a paddled area is fetched once. Fetch uses `HttpURLConnection` with a
  descriptive **User-Agent** (`loadImage(URL)` sends the default Java UA, which OSM
  blocks) and honours OSM's usage policy: low volume, cache, attribution. Missing
  tiles show a grey placeholder + "loading map…" until they arrive.
- **Overlays.** Orange track polyline; **green** start marker, **red** end marker,
  and a **blue live dot** at the current playback position (`sync.boatIdxFor(padFrame)`
  when a paddle CSV is loaded, else the boat cursor). Scale bar (nice 1/2/5 m→km),
  north arrow, and the required `© OpenStreetMap contributors` attribution.

Provider was chosen with the user (AskUserQuestion): **OpenStreetMap street tiles**
— free, no API key. Google/Mapbox were rejected (key + billing).

### 15.2 View selection refactor (`viewMode`, `showView(int)`)

The two-way side/3D toggle is generalised to a single `int viewMode` (0=3D,
1=SIDE, 2=TRACK). One helper `showView(int which)` sets the mode, flips each
panel's `shown` flag, runs the per-view data-availability check + slice switch,
and is the single path the **`x`/`t` keys**, the **Tabs** bar, and the **Commands
menu** all call, so keyboard and mouse never drift out of sync (`showSideProfile
(boolean)` is kept as a thin wrapper). `sideActive()`/`trackActive()` gate the
draw and input routing; the tab bar gains a third **TRACK** label (the slot
reserved in v0.25).

### 15.3 Side-profile persistence fix

The immersion band (§14.9) is redrawn each frame over `resetAtFrame..cursor`.
Right-click "restart" set `resetAtFrame` to the current frame, so restarting near
the end of a file and then rewinding to replay left the restart point *ahead* of
the cursor and the band drew nothing. Fix: when the cursor moves behind the
restart point, re-anchor the restart point to the cursor, so "restart, then run
again from an earlier frame" rebuilds the band as playback advances. **Confirmed
on screen 12 Aug** ("band rebuilds now").

### 15.4 Status

BUILT + compiles clean (`processing-java --build`, Processing 4.3). **Track view
and the side-profile persistence fix both CONFIRMED on screen 12 Aug 2026.** The
track plot is now implemented (the tab slot reserved in v0.25 §14.10 is filled).

## 15.5 Re-runnable calibration + classification, and clear-classification key `q`

**Problem (field use, 12 Aug 2026):** the session-setup wizard (§14) was a
one-shot flow. After it auto-completes at Step 5 it reopened **read-only** —
`w`/F1 just displayed the calibration numbers with no way to act. So there was
no live way to **recalibrate the paddle** or **re-classify** (e.g. exclude a
long drive-home tail, then zoom to find the rest window and rebuild the roll
calibration). `r/R` "did nothing" because the read-only summary never routed
keys into the wizard's step handlers.

**Fix (v0.28):** `Wizard.toggle()` now reopens a *completed* wizard as a **live
flow at Step 3**, not a read-only summary. Steps 3b/4b already display the saved
calibration / classification *with* "use it (`Return`) / reset (`r/R`)"
options, so re-entry gives status **and** actionability:

- **Step 3 (calibration):** 3b shows the current mount offsets + yaw datum +
  rest window; `Return` keeps them → Step 4, `r/R` discards them → 3a. In 3a,
  scrub/zoom the graph (right-click zoom-to-span still works with the wizard
  panel up — it only consumes clicks inside its own top panel) to the start of a
  still moment, then `Return` rebuilds the sidecar (`buildAndSaveSidecar()`).
- **Step 4 (classification):** 4b shows saved sections; `Return` keeps them,
  `r/R` clears + re-marks; 4a marks right/left/zero/**exclude** (`d/D`).

On re-entry the sketch also switches to Slice A if it was in Slice 0, so the
paddle graph strip (needed to position the cursor) is present.

**Recalibration now preserves classification.** `buildAndSaveSidecar()` builds a
brand-new `Sidecar` (no classification), which previously wiped the user's
markings on every rebuild. Since classification is independent of the roll cal,
the rebuild now copies the existing sections onto the new sidecar — from the
current sidecar (plain `C`-key rebuild) or from a stash saved when the wizard's
Step-3 reset nulled the sidecar (`stashedClassification` in `PadViz8.pde`,
populated by `Wizard.resetRollCal()`). So "exclude the drive-home, **then**
recalibrate" keeps the exclusion.

**Standalone `q` key** (also `Q`) — a quick, global (any-slice) **single-press**
wipe of all classification: clears `sidecar.classification`, rewrites the
sidecar (`saveSidecarQuiet()`), and rebuilds the exclusion/visibility index so
frames previously excluded by a `d/D` section become navigable again. **Roll
calibration is untouched.** Nothing classified → flashes
`NO CLASSIFICATION TO CLEAR`; otherwise `CLASSIFICATION CLEARED (N removed)`.
It was a two-press confirm in v0.27 but the confirm was confusing (and, because
right/left/zero shading only renders during Step 4, the arming press looked like
it had already cleared), so v0.28 makes it single-press — matching the wizard's
own single-press Step-4 reset, and recoverable by re-classifying. A
**CLASSIFICATION** group in the Commands menu carries the `q` row.

Implementation: `Wizard.toggle()` / `Wizard.resetRollCal()` in `Wizard.pde`;
`clearClassificationRequested()`, `stashedClassification`, and the
classification-carry in `buildAndSaveSidecar()` in `PadViz8.pde`; menu row in
`Menu.pde`. BUILT + compiles clean; the re-entry flow, recalibration, exclusion
survival, and single-press `q` are **runtime behaviour still to be confirmed on
screen** (compile-vs-runtime caveat — `--build` does not exercise key dispatch).

**Alternative undo paths (also valid):** reload the session and use wizard
Step-4 `r/R`; or hand-edit the sidecar `<paddle>.session.json`
`classification_sections` array. **Redo calibration without the wizard:** press
`C` in a graph slice at a rest moment (rebuilds + saves the sidecar cal, now
also preserving classification).

## 15.6 Track view clips to the paddling session (v0.30, 12 Aug 2026)

The Track view (§15.1) drew **every** valid GPS fix in the boat CSV, so a long
session's drive-home tail both cluttered the map and stretched the auto-zoom
bounding box until the actual paddling area was a tiny knot.

**Why classification alone isn't enough (the v0.29 → v0.30 correction).** v0.29
tried to honour classification directly: map each boat fix to its paddle frame
and drop the ones in an EXCLUDED range. But the boat unit's GPS commonly keeps
logging **through the drive home after the paddle unit has stopped**, so the
drive appears on the map with **no paddle frames behind it at all** —
classification is paddle-frame based and simply can't mark data that isn't in
the paddle timeline. v0.29 kept any boat fix with no paddle mapping, so the
paddle-less drive tail stayed on the map (the reported symptom: "the excluded
bit is still included").

**v0.30 — clip to paddle coverage.** `TrackPanel.rescan()` now keeps a boat fix
only if it falls inside a run of **non-excluded paddle coverage**. Because
`SyncMap.boatIdxFor` is monotonic in the paddle frame, each contiguous run of
non-excluded paddle frames maps to a contiguous boat range; the scan walks the
paddle frames building a `keepBoat[]` mask, where an EXCLUDED paddle frame (or
the end of the paddle file) **closes** the current run and an unmapped-but-
non-excluded frame (a mid-paddling sync hole) is skipped so it doesn't fragment
the range. A boat fix is drawn only if `keepBoat[i]`. This removes, in one rule:

- the **drive-home tail** after the paddle stops (boat frames beyond the last
  paddle-mapped one — the case v0.29 missed);
- any explicitly **EXCLUDED** range in the middle (run split);
- a **boat-only lead-in** before the paddle starts.

The **bounds are recomputed from the kept fixes**, so the auto-zoom frames the
paddling area; the live-position dot and green start / red end markers reference
the clipped track. The filter engages whenever paddle data + sync are present
(not gated on `hasExclusions` — the paddle-less drive tail has no exclusion to
gate on); a boat-only session (no paddle/sync) is unchanged ("every valid boat
fix"), and a totally broken sync (nothing maps) falls back to show-all rather
than blanking the map. Footer shows `N fixes (clipped to paddling session)`
when anything was dropped; the empty case reads "No GPS fixes inside the
paddling session".

Note this means the map now shows the boat track **only where the paddle was
recording** — if the paddle unit logged through the drive too, mark that stretch
EXCLUDED (wizard Step 4 `d`) to drop it, since non-excluded paddle coverage is
by definition "kept".

Cache: `rescan()` is memoised on the boat frame count, so a paddle CSV loading
*after* the boat, or a classification change, wouldn't re-filter on their own —
`rebuildSync()` and `rebuildClassificationIndex()` both call
`trackView.invalidate()` so the scan is redone whenever sync or the sections
change (paddle/boat load, wizard edit, `q` clear, session load).

Implementation: `TrackPanel.rescan(BoatSource, SyncMap)` (keep-run mask) +
`filteredByClass` flag in `TrackPanel.pde`; `trackView.invalidate()` from
`rebuildSync()` and `rebuildClassificationIndex()` in `PadViz8.pde`. **CONFIRMED
on screen 12 Aug 2026** — once the drive-home tail was excluded (§15.7) the clip
dropped it and the map framed the paddling area ("drive-home is gone from the
map").

## 15.7 Classification "exclude cursor → end of file" (v0.31, 12 Aug 2026)

Marking an EXCLUDED section that stops even one frame short of the file end
leaves the trailing frames classified as valid paddle coverage — so §15.6's
Track clip keeps drawing that leftover tail. Landing the end mark exactly on the
last frame is fiddly, so the wizard's Step 4 gains a one-key shortcut.

**`e` / `E`** excludes `[cursor .. last paddle frame]` inclusive in a single
press: it adds one `CLASS_EXCLUDED` section from the current graph cursor to
`paddleData.frameCount() - 1`, saves the sidecar, and rebuilds the exclusion
index. It works in **both** Step-4 sub-modes — 4a (mid-marking, any phase: it
abandons any half-marked pair) and 4b (reviewing saved sections: it adds to them
and drops into 4a so you can finish or mark more) — and leaves all existing
sections untouched. It is rejected (with a flash) only if the range would
overlap an existing section, i.e. position the cursor **past** the previous
exclusion first. On success it flashes `EXCLUDED frame S → end (N)`.

Typical fix for the reported case: reopen the wizard (`w`) → Step 3 `Return` →
Step 4, scrub to the first still-drawn leftover point after the short exclusion,
press `e`. The tail is excluded to the file end and the Track map's clip
(§15.6) then drops it.

Implementation: `Wizard.excludeCursorToEnd()` + the `e/E` branch at the top of
`Wizard.handleKeyStep4()` in `Wizard.pde`; Step-4 instruction lines updated.
**CONFIRMED on screen 12 Aug 2026** ("excluded the tail, drive-home is gone from
the map") — end-to-end proof of `e` exclude-cursor→end + sidecar save + the
§15.6 Track clip on real data.

## 15.8 Side-profile: flip the left-blade view (`f`, v0.32, 14 Aug 2026)

The side-profile window (`x`) splits into two boat ZY-plane views seen from
**opposite** sides — the TOP left-blade view from port (bow on the **left**), the
BOTTOM right-blade view from starboard (bow on the **right**). That opposite
orientation is deliberate (each blade is shown from its own working side, bow
marked red on both to disambiguate), but it makes a direct left-vs-right shape
comparison awkward because the two halves run mirror-image to each other.

**`f` / `F`** (side-profile view only) mirrors just the **TOP (left-blade)** half
horizontally so its bow sits on the **right**, giving both halves the same
orientation for a side-by-side comparison. It only flips the drawing direction
(`yDir` for that half, and its title becomes `LEFT blade — mirrored (bow
right)`); the geometry, waterline, immersion band and stats are unchanged, and
the right-blade half is never touched. Toggles back on a second press. The key
is gated to `viewMode == 1`, so it is inert outside the side-profile view.

Implementation: `SideProfilePanel.leftBowRight` + `toggleLeftBow()`, applied when
`draw()` picks the top half's `yDir`/title; the `f/F` branch in `PadViz8.pde`
`keyPressed()` (after the `x` handler, gated on `viewMode == 1`) with a
`triggerRefFlash`; Commands-menu row added under the side-profile entry.
**Compiles clean** (`processing-java --build`); **CONFIRMED on screen 14 Aug 2026**
(the left-blade half flips so its bow reads on the right, matching the bottom
half).

## 15.9 Bow marker on the top-down blade panels (v0.33, 14 Aug 2026)

The two left-hand/right-hand top-down panels — **Blade entry/exit**
(`EntryExitPanel`) and **Blade path (avg)** (`StrokeAveragePanel`) — both draw a
kayak outline for scale with the bow pointing **up** (+Y forward), but nothing
marked which end was the bow, so the orientation had to be inferred. Each panel
now draws a small **red filled triangle at the bow tip** (`(cxp, cyp − halfLen)`,
apex up), so the boat's front is unambiguous. Purely a scale/orientation cue —
no change to the plotted events, averaged paths, scale, or stats. Identical
marker in both panels for consistency.

Implementation: a `triangle(...)` in red (`230,40,40`) added right after the
kayak-outline block in `EntryExitPanel.draw()` and `StrokeAveragePanel.draw()`;
sized 24 px wide × 26 px tall (doubled from the first cut after an on-screen
check — the smaller marker read too small). **CONFIRMED on screen 14 Aug 2026.**

## 15.10 Session feather angle — re-angling the model's left blade (v0.34, 14 Aug 2026)

The 3D paddle model (`paddle60.obj`) was built with the left (yellow) blade
feathered at +60° relative to the right (red) blade. For a zero-feather or
left-handed session the model was therefore wrong — the left blade sat at the
wrong angle. (The side-profile and top-down blade views were already correct;
they compute blade geometry from data, not from the OBJ.)

**A single signed feather angle is now a per-session paddle property**, stored in
the sidecar next to the paddle dimensions and entered in the same numeric prompt:

- Sidecar field **`feather_deg`** (`Sidecar.featherDeg`), and a matching
  `feather_deg` in the per-machine `paddle_dims.json` last-used store.
- The **`m` prompt gains a 3rd step** — "Feather angle (deg): **+** right-handed
  **−** left-handed **0** straight". The field accepts a leading sign; blank
  keeps the last value; the value is clamped to ±90°. Shown in the Detail box
  alongside paddle/blade length.
- **One value per session** — the physical paddle setting, not per-section. (The
  user only changes it mid-session for testing.)
- Loading a session now **seeds the last-used geometry** (length/blade/feather)
  from the sidecar, so a later recalibration preserves it rather than resetting
  to whatever was last typed (also fixes a pre-existing length-reset-on-recal gap).

**Model re-angling** (`Model3D`): at load the mesh's **left half (X<0)** triangles
are indexed with a copy of their original vertices. `setFeather(deg)` rebuilds
those vertices by rotating them about the shaft (X) axis by
`(deg − 60) × FEATHER_SIGN`, so the whole left blade (yellow front, grey back,
edges) turns as a unit. Processing explodes the OBJ into one un-shared triangle
per face, so this needs no vertex-sharing care; the shaft cross-section is a
perfect circle at X=0, so rotating the left half only twists the round half of
the shaft — no seam. `FEATHER_SIGN = −1`, fixed from the OBJ geometry: the
as-built left blade measures −58.5° (≈ −60°) in the +X-rotation sense, so −1 makes
**feather 0 = flat/coplanar, +60 = as-built right-handed, −60 = left-handed
mirror**. The catch detector, side view, and top-down panels are untouched.

**Verification.** Feather **0 and +60 CONFIRMED on screen** (14 Aug 2026). **−60
proven by an offline render** of the model at 60/0/−60 (looking at the whole
paddle — 0 gives both blades coplanar, −60 the clean mirror of +60) **and by the
geometry measurement** above; the on-screen −60 check was inconclusive to the eye
(the blade visibly moved but the direction was hard to judge without genuine
left-handed strokes underneath). **Left-handed field data is pending** — none of
the current recordings has a `left` classification section — and will be recorded
to confirm −60 against real motion. The render harness lives in the session
scratchpad; preview PNGs (`feather_preview_*.png`) are untracked scratch.

## 15.11 Sidecar "no accelerometer data" false-negative fix (v0.35, 30 Aug 2026)

**Symptom (field, 30 Aug 2026 session — `PadLog20260830.CSV` / `BoatLog20260830.CSV`):**
building the calibration sidecar aborted with *"Paddle CSV has no accelerometer
data — need PadDis v8.10 full-column log"*, even though the paddle CSV was a
correct full-column v8.14 log with good accel on all but the first row.

**Root cause.** `buildSidecar()` decided whether the log carried accelerometer
data by inspecting **frame 0's values** (`getFrames().get(0).accelX/Y/Z == 0`).
But **row 0 of every full-column log is legitimately `0,0,0`** — it is the startup
frame emitted before the BNO085 delivers its first accel sample. The check was
only ever meant to catch *reduced-column* CSVs (which have no accel columns at
all), so sampling one frame's values was the wrong test.

**Fix.** `DataSource` now records a **`hasAccel`** flag detected from the header
line (`line.contains("accel_x")`), exactly as `hasRxMs`/`hasGrv` are already
detected. `buildSidecar()` tests `!pad.hasAccel` instead of frame 0's values —
a reduced-column log (no `accel_x` column) is correctly rejected, while a
full-column log with a zero startup row now builds normally. Load log gains an
`(accel)` / `(reduced/no-accel)` tag.

**Not a bug (same session report):** the bottom strip-chart "only graphed the
paddle, not the boat". That is the default — the three trace slots default to
Pad roll / yaw / CPM (§ `GraphPanel.slotField = {0,2,3}`); the boat channels
(`Boat: kayak_roll/pitch/yaw/speed/cog`) are in each slot's dropdown and plot
via the paddle↔boat sync when selected. The boat 3D model renders in the
combined slice regardless. No change made.

**Verification.** Compiles clean (`processing-java --build`). On-screen
confirmation pending: re-open the 30 Aug session, position the cursor at a still
moment, build the sidecar, and confirm it now succeeds.

## 15.12 Relative-yaw orientation source toggle — GRV ⇄ fused (v0.36, 30 Aug 2026)

**Symptom (30 Aug 2026 jig session).** With the paddle held in a clip-on frame
aligned to the boat (paddle-unit X ∥ boat X, both Y forward), Slice C showed the
paddle **~45° off in the XY (horizontal) plane** and **not rolling about its
shaft** — it moved like a zero-feather paddle even though the section was
classified right-handed and the model geometry was right-handed.

**Root cause — GRV yaw drift, not a mounting or geometry error.** `drawSliceC()`
and `CatchEvents` render the paddle-vs-boat *relative* orientation, and both
auto-select the **GRV (Game Rotation Vector)** quaternions whenever both files
carry them (spec §16.11 preferred GRV because fused yaw once showed an in-band
cycle-periodic magnetometer artefact). GRV is gyro+accel only — **it has no
magnetic yaw reference, so each unit's yaw zero is arbitrary at power-up and the
two units' yaw estimates drift apart over a session.** The single rest-window
reference cancels the offset only at that instant. Measured on this session
(offline, from the CSVs):

| relative paddle-vs-boat at rest | roll | pitch | **yaw (XY)** | total |
|---|---|---|---|---|
| **Fused** (mag-referenced) | −9° | 6° | **3°** | 11° |
| **GRV** | −6° | 9° | **78°** | 79° |

So the **jig alignment was physically correct** (fused ≈ 3° in yaw); the GRV 78°
is the arbitrary power-up offset. Over the right-handed section, decomposing the
*displayed* rotation (swing–twist about the model shaft) gave fused = clean shaft
roll (twist std 27°, p-p 163°) with a stable shaft swing (std 11°), versus GRV =
**~72° of wandering shaft swing** (std 38°) that both *is* the reported ~45° XY
error and swamps the roll so it reads as "no roll". Paddle `mag_cal` was 2–3 for
~96% of the file, so fused is trustworthy here. There is **no universal winner** —
GRV wins when the mag environment is bad (the §16.11 case); fused wins for a
well-mag-calibrated session — so the source must be **operator-selectable**, not
a flipped default.

**Change.** A global orientation source (`orientMode` = `ORIENT_GRV` default /
`ORIENT_FUSED`) gates the GRV selection in both consumers via one helper,
`useGrvActive(padHasGrv, boatHasGrv)` = `orientMode==GRV && padHasGrv &&
boatHasGrv`. `CatchEvents` gates each sensor's GRV use by the same mode (its
`boatUsed` rule still forbids mixing fused-vs-GRV across the two sensors). Key
**`y`/`Y`** toggles it (gated to `sliceMode != 0` so Slice 0's model-cal `y`
in `cal.handleKey` is untouched; `v` was already the camera preset), rebuilds
`CatchEvents` (which bakes its heading reference at compute time), and flashes
the new source. The Slice-C HUD line now reads *"GRV (mag-free) [v = fused]"* /
*"fused (forced) [v = GRV]"* / *"fused (no GRV in one or both files)"*. Default
behaviour is unchanged (GRV preferred); Slice A/B remain fused-only as before.

**Verification.** Compiles clean (`processing-java --build`). **CONFIRMED on
screen 30 Aug 2026** — on the 30 Aug jig session, pressing `y` in Slice C
squared the paddle up in the XY plane and restored roll about the shaft (the
fused solution). Setting the session feather to +60 via `m` (it had inherited
−60 from the 14 Aug test) fixed the paddle-showing-as-zero-feather display.

**Caveat surfaced by the same session (recorded, not yet resolved).** With the
relative-yaw source corrected, the entry/exit traces show the blade entering the
water *further forward on the left than the right*. Whether that is a real
stroke asymmetry or a residual calibration/geometry artefact is **not currently
decidable** from this data: the fore/aft blade placement in the boat frame is
derived from the relative orientation plus assumed arm/geometry constants
(`PADDLE_BOW_OFFSET_M`, `PADDLE_FWD_OF_CENTRE_M`) — the paddle-centre translation
relative to the boat is *not observable from two IMUs* (functional_spec §8.1 /
§8.1.1). A left/right yaw-zero difference of only a few degrees maps to a visible
fore/aft difference at the blade tip, so an apparent L/R "further forward" can be
produced by calibration alone. This is the same unobservability the clip-on-jig
kinematic-model note addresses; treat the L/R fore/aft asymmetry as *indicative,
not measured* until the well-calibrated forward-paddling session lets the
kinematic-model estimate be checked (functional_spec §8.1.1).

**Resolution — measured 31 Aug 2026: the varying L/R fore/aft lead is a
yaw-zero artefact, not real.** After the 30 Aug session was re-classified into
four turn-free right-handed runs, the user observed that *which* blade appears to
enter further forward **varies between runs**. Quantified offline (per-blade catch
detection, entry-Y bucketed by boat side; scratch `entryYcheck.py`, fused
orientation):

| Run | port entry-Y | stbd entry-Y | lead (port−stbd) | run yaw-zero |
|---|---|---|---|---|
| 1 | 0.945 m | 0.861 m | **+8.4 cm** | −5.1° |
| 2 | 0.840 m | 0.969 m | **−12.9 cm** | +6.4° |
| 3 | 0.943 m | 0.891 m | **+5.3 cm** | −3.2° |
| 4 | 0.833 m | 0.985 m | **−15.2 cm** | +4.6° |

The lead **flips sign every run** and tracks the calibration almost perfectly:
**corr(lead, per-run yaw-zero) = −0.98**. The paddle-vs-boat yaw-zero itself
wanders ±~5–6° between runs (spread 11.4°); at **2.1 cm of tip fore/aft per 1°**
(blade tip ~1.2 m from the yaw axis) that ~11° alone produces **~24 cm** of
phantom fore/aft swing — larger than the ~10 cm lead. Even the *same* side's
entry-Y shifts ~12 cm between runs, which cannot be real technique. So the L/R
"further forward" difference is **dominated by fused yaw-zero drift** over the
session (consistent with the known 1° yaw-datum sensitivity, §7 revisit); any
genuine catch asymmetry is smaller than the artefact and is not separable with
two IMUs. This closes the caveat: **not real, measured to be calibration drift.**
(Offline catch detection is cruder than PadViz's, so the per-stroke scatter is
not authoritative, but the −0.98 correlation and between-run shifts are driven by
orientation medians and are robust.)

## 15.13 Paddle-dimension review screen before sidecar build (v0.37, 30 Aug 2026)

**Motivation (user, 30 Aug 2026).** Building a new session sidecar silently
inherited the previous paddle's total length, blade length and feather angle
(the last-used values persisted to `paddle_dims.json`). On the 30 Aug session
that meant the sidecar inherited feather −60° from a 14 Aug left-blade test even
though the paddle was right-handed, so the model displayed as zero/wrong-feather
until the operator re-entered `m`. Inheriting geometry *without question* is a
foot-gun; the operator should see the values and choose.

**Change.** The dimension prompt (opened by `m`, or automatically as part of the
`C` sidecar build) now opens on a **review screen** (`dimStage == 4`,
`drawDimReview()`) listing the three last-used parameters —

```
PADDLE DIMENSIONS — last used
  Total length    2.10 m
  Blade length    0.32 m
  Feather         +60°  (right-handed)
  A / Enter = accept all      E = edit      Esc = cancel
```

`A`/`Enter` accepts the last-used values as-is (and proceeds to build when
invoked from `C`); `E` drops into the existing per-field editor (stages 1→2→3,
each pre-filled with the last value so an individual field is type-over-Enter);
`Esc` cancels. Handedness is spelled out (right / left / straight) so a stale
feather sign is obvious at a glance. Nothing else in the entry/persist/rebuild
path changed — accept and edit both end in `applyPaddleDims()`.

**Verification.** Compiles clean (`processing-java --build`). On-screen
confirmation pending: press `m` (or run a `C` build) and confirm the review
screen shows the last values with working `A` / `E` / `Esc`.

## 15.14 Paddle dimensions folded into the setup wizard (v0.38, 30 Aug 2026)

**Motivation (user, 30 Aug 2026).** The v0.37 review screen still lived only on
`m` / the `C` build — the **setup wizard never asked for paddle dimensions**, so
a user walking the guided flow (load paddle → load boat → calibrate → classify →
done) completed setup with the previous paddle's geometry silently inherited and
had to remember to press `m` afterwards. The user wants *all* setup done as the
files are loaded: **"this is where I want that section."**

**Change.** The wizard grows from five steps to six, with paddle dimensions
inserted as **Step 3** (right after the files are loaded, before calibration):

```
1  paddle CSV
2  boat CSV (optional)
3  paddle dimensions   ← NEW — review last-used total/blade/feather, A = accept / E = edit
4  roll calibration    (was 3)
5  classification       (was 4)
6  done                 (was 5)
```

Step 3 shows the three last-used values inline in the wizard panel (feather with
its handedness spelled out, and a reminder to check the sign matches this
session's paddle). **`Return`/`A`** accepts them; **`E`** opens the existing
per-field numeric editor (`beginDimPromptEdit(true)` → stages 1→2→3, skipping the
`m`-style review screen since the wizard panel already showed it). On accept or
after editing, the editor calls `dimComplete()` which routes back via
`wizard.dimsAccepted()` to advance to Step 4. Placing dimensions *before* the
Step-4 calibration build means the sidecar is built (`buildAndSaveSidecar()`
seeds from the last-used values) already carrying the confirmed geometry — no
transient wrong-feather model.

The `C`-key standalone build and `m` are unchanged (they still open the v0.37
review screen). The one-step saved-session loader (`J`) and the `w`-reopen of a
completed wizard both **skip** Step 3 — a saved session already carries its
dimensions (`applySidecarToDisplay()` seeds the last-used globals from it), and
reopen is specifically the recalibrate → reclassify path (`m` covers a later
standalone dimension change). Internally: `dimFromWizard` flag +
`beginDimPromptEdit()` + `dimComplete()` in `PadViz8.pde`; wizard step machine
renumbered (`enterStep4`→`enterClassify`, `gotoStep5`→`gotoDone`,
`handleKeyStep4`→`handleKeyStep5`, new `dimsAccepted()` + `drawStep3Dims()`).

**Verification.** Compiles clean (`processing-java --build`). **CONFIRMED on
screen 30 Aug 2026** — the paddle-dimensions step is in its proper place in the
wizard flow (user: "paddle dimensions in proper place").

## 15.15 Bottom-graph min/max envelope — zoomed-out anti-aliasing (v0.39, 31 Aug 2026)

**Symptom (user, 31 Aug 2026).** With the whole trace shown (the full session,
excluded ranges removed), the bottom `GraphPanel` strip drew a visibly *wrong*
waveform; zooming in restored the real detail. Diagnosis: **aliasing**. The chart
walked one pixel column at a time and read a **single** sample per column
(`padIdx = viewA + t*(viewB−viewA)`, `v = ds.fieldAt(padIdx, …)`), so with ~340 k
frames across ~1.5 k pixels it point-sampled ~1 in 200 frames and connected them
with lines — folding the ~0.6 Hz roll into a false low-frequency beat. The user
accepted that a fully-drawn trace would just be a solid band per section, but
wanted to keep seeing where major events (turns) occur, and floated a warning
message as a fallback.

**Change — min/max (envelope) decimation.** When more than ~1.5 samples map to a
pixel column (`DECIMATE_SPP`), each column is rendered as a **vertical line
spanning the min..max of every visible sample in that column** (scan capped at
`ENV_SCAN_CAP = 160` samples/column) — the standard oscilloscope/waveform
envelope. Zoomed out, each channel becomes a **solid band of its true peak-to-
trough amplitude**; turns and quiet stretches read *clearly* as the band
collapsing or shifting (event visibility is preserved — improved, even). Below the
threshold (zoomed in) it falls back to the **unchanged** point-to-point detail
line (`drawDetailTraces`, extracted verbatim from the old loop). The envelope is
**cached** (`envSig` = view range + width + fields + frame counts) and recomputed
only when that changes, so per-frame redraw stays cheap; a quiet
*"envelope — zoom in for detail"* caption shows top-right while decimated (the
warning idea, folded in as a hint). Pixel→frame mapping is shared by both paths
(`rawIdxForPixel`), so exclusions still occupy no pixels in either mode, and boat
channels decimate via the same per-column `SyncMap` lookup. New in `GraphPanel`:
`buildEnvelope()`, `drawEnvelope()`, `drawDetailTraces()`, `rawIdxForPixel()` +
the `envSig`/`envTopY`/`envBotY`/`envHas` cache.

**Verification.** Compiles clean (`processing-java --build`). **CONFIRMED on
screen 31 Aug 2026** — the full-trace view now shows amplitude bands instead of
the aliased squiggle, and zooming in reverts to the real detail line.
