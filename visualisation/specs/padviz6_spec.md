# PadViz6 — Disciplined Orientation Specification

**Version:** 0.15
**Date:** 2026-07-20
**Status:** v0.15 (20 Jul 2026, §13.7): four field-use fixes from the user's on-screen check of v0.14 — pitch nudge moved off the double-bound `p`/`P` to `i`/`I`; playback speed multiplier (`>` doubles, `<` resets to x1); entry/exit panel right-click clears accumulated dots; entry/exit yaw-datum manual override (`n`/`N` nudge, `g` reset, shown in Slice 0, saved in the sidecar) as an explicit stop-gap for a ~30° automatic-datum error found on replay; Slice C paddle base position moved +0.45 m toward the bow (measured average paddle-centre offset from boat centre). Slices 0–C + bottom GraphPanel with two-click zoom (right-click), double-right-click revert, `S`-key zoom reset, and merged CSV export (curated + all-fields). Corner axis compass (2D, ~1/3 the old on-screen size) with a `P`/`K`/`W` frame letter that also acts as the slice-switch shortcut. §7 expanded (v0.7) from single yaw-alignment rotation to a three-offset per-session procedure — sensor-mount roll/pitch (from accel) + magnetic-yaw datum (from mean quats) — with pre-session magnetometer figure-8 and DCD save. Requires three firmware additions listed in §7.8 (formalised in firmware spec §15, v2.7). v0.8: the three 8 Jul 2026 field-use notes (§12.10) are now DONE — `k`/`u` HUD flash, Slice B hint to `W`, and Backspace/`-` back-slice ping-pong. v0.9: free-orbit camera — left-drag orbits, wheel zooms, V snaps to side/top preset; 2D axis compass now rotates in step with the 3D camera basis. v0.10: first-pass session sidecar builder (`Sidecar.pde`, C key) — rest-window detector + mean-based mount offsets + yaw datum + JSON save per §7.5. Slice-switch letter shortcuts P/K/W dropped (Caps-Lock case ambiguity); digits 0/1/2/3 only. v0.11: startup onboarding checklist (`Checklist.pde`) in the bottom strip when no paddle CSV is loaded — three rows auto-ticked and clickable. v0.12: sidecar auto-load — on paddle-CSV open, look for a sibling `<basename>.session.json`, parse it, and reseed rest-window references so the correction is active without pressing C. Third checklist row auto-ticks in that case; boat CSV load extends the seeding to the boat side. v0.13 (9 Jul 2026): three field-use fixes driven by the 9 Jul session — (a) C-key rest-window search now starts at the current playback frame (was frame 0), so the user can seek to the intended still moment before building; (b) checklist strip hides as soon as the paddle CSV loads (was blocking the graph until sidecar built), and a yellow "SIDECAR not built — seek then press C" HUD hint appears in its place; (c) `DataSource.computePaddleCentreMotion` — accel double-integration with a three-stage HPF cascade (fc ≈ 0.3 Hz) drives a per-frame paddle-centre offset (±0.3 m clamped) that translates the mesh in Slices A + C during render, so the shaft midpoint visibly swings with the stroke. v0.14 (17 Jul 2026, §13): startup checklist becomes a floating overlay above the graph strip (graph appears on paddle-CSV load, overlay stays through seek-and-`C`); left key-list HUD replaced by a Commands pull-down menu; new `CatchEvents.pde` offline blade entry/exit detector (port of firmware spec §13.5 feasibility method); new `EntryExitPanel.pde` — left 20 % boat-frame top-down scatter of entry/exit points, red = right blade, green = left, filled = entry, hollow = exit, accumulating with playback.

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
  "notes":         "figure-8 done on beach; both sensors green before launch."
}
```

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
   visibility condition as `leftPanelWidth()`/`isPanelVisible()`) and
   height (stops above the graph strip). Plots the average roll trace over
   each blade's in-water run — `CatchEvents` now also collects
   `rightRuns`/`leftRuns` (the same `runStart`/`runEnd` pairs the entry/exit
   events are built from, same `MIN_RUN_S`/`MAX_RUN_S` gate) alongside the
   events themselves. Each run is resampled to 40 points (linear
   interpolation) and averaged in; roll is plain-arithmetic-averaged, not
   circular-mean, matching `Sidecar.meanRPYFromFrames`' existing
   convention (a single stroke's roll swing doesn't cross the ±180° wrap).
   A run counts once the playback cursor passes its end frame — mirrors
   `EntryExitPanel`'s dot accumulation, so play-through builds the trace
   and scrubbing back removes strokes again. Right-click restarts the
   accumulation from the current frame; independent of the left panel's
   reset (each panel's `mousePressed()` branch only checks clicks inside
   its own bounds). Green = left, red = right (same convention as the
   entry/exit panel).
3. **Layout knock-on effects** — `drawAxisLegend()`'s x-position now
   subtracts `rightPanelWidth()` so its text doesn't sit behind the new
   panel; the graph strip is unaffected (it already spans the full window
   width beneath both side panels, which only occupy the region above it —
   same pattern the entry/exit panel established in v0.14). `Menu.pde`
   gained entries for both panels' right-click behaviour and the Detail
   button.

Compiles clean via `processing-java --build`. User's first on-screen check
found the two issues above (layout, p/b regression); both addressed same
day, not yet re-confirmed.
