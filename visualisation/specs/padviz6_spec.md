# PadViz6 — Disciplined Orientation Specification

**Version:** 0.8
**Date:** 2026-07-08
**Status:** Slices 0–C + bottom GraphPanel with two-click zoom (right-click), double-right-click revert, `S`-key zoom reset, and merged CSV export (curated + all-fields). Corner axis compass (2D, ~1/3 the old on-screen size) with a `P`/`K`/`W` frame letter that also acts as the slice-switch shortcut. §7 expanded (v0.7) from single yaw-alignment rotation to a three-offset per-session procedure — sensor-mount roll/pitch (from accel) + magnetic-yaw datum (from mean quats) — with pre-session magnetometer figure-8 and DCD save. Requires three firmware additions listed in §7.8 (formalised in firmware spec §15, v2.7). v0.8: the three 8 Jul 2026 field-use notes (§12.10) are now DONE — `k`/`u` HUD flash, Slice B hint to `W`, and Backspace/`-` back-slice ping-pong.

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
offsets. The rest window is the first contiguous span where:

- `abs(||accel|| − 9.81) < 0.1 m/s²` on both sensors, and
- per-axis rolling variance of accel over 100 samples < a threshold (roughly
  `0.02 (m/s²)²`), and
- span duration ≥ 300 paddle frames (3 s).

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

| View | `camera()` call | On-screen axes |
|---|---|---|
| Side (`viewMode = 0`) | `camera(0, -1200, 0,  0, 0, 0,  0, 0, 1)` | +X right, +Z up, +Y into screen |
| Top-down (`viewMode = 1`) | `camera(0, 0, -1200,  0, 0, 0,  0, -1, 0)` | +X right, +Y up, +Z out of screen |

**P3D gotcha:** the camera `up` vector actually specifies the screen-**down** direction (Y-inverted from OpenGL to match 2D). That's why the `up` vectors above look like they point down. Verified empirically 7 Jul 2026 across two rounds of camera tuning.

The side view uses camera along −Y, which is a good side profile for the paddle (long axis along X) but shows the kayak stern-on (kayak long axis along Y). For Slice B use the top-down view for orientation review; a starboard-side camera can be added later if a side profile of the kayak is wanted.

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

- **Slice C field validation.** Runnable on the 6 Jul 2026 file (calibration rest at rows 1 – ~5000, then paddling under way from row ~15000 onward at 2.2 – 2.6 m/s with COG stable). Also runnable on the longer paddling session the user has on hand if it turns out to be more useful. Test per §4.3.
- **Per-session rest-pose sidecar** (§7). Currently the K/U keys serve as the interactive equivalent; the offline sidecar workflow (compute mean-of-window paddle-vs-kayak offset from a marked rest window in the CSV, write `<basename>.rest.json`, auto-load at CSV-load time) is not yet implemented.
- **Side panel** (`SidePanel.pde`) — filenames, load buttons, play/pause, speed slider.
- **Adaptive side view** for Slice B (starboard-side camera) if desired.
- **Under-way GPS COG mapping test** for Slice B acceptance — needs a new field session.

### 12.10 Field-use notes — 8 Jul 2026 — all three DONE 8 Jul 2026

These came up while driving the sketch against real data.

1. **Lowercase `k` reports as "no effect".** — **DONE.** `k` (and `u`) now trigger a top-centre HUD flash for 1.5 s (linear fade over the last 400 ms). Message text is slice-specific: `PADDLE REF CAPTURED (frame N)` in Slice A, `KAYAK REF CAPTURED (frame N)` in Slice B, `BOTH REFS CAPTURED (pad N, boat M)` in Slice C, and the matching cleared-variant on `u`.

2. **"Kayak view" that also shows the paddle."** — **DONE (hint approach).** Compass letters unchanged (`P`/`K`/`W`) to preserve the "letter you see is letter you press" invariant. Instead, Slice B's HUD adds a cyan hint line — `Paddle CSV also loaded — press W (or 3) for combined kayak+paddle view` — but only when a paddle CSV is currently loaded. If no paddle CSV is loaded, no hint (the combined view isn't yet meaningful).

3. **No "revert to previous slice" shortcut.** — **DONE.** `Backspace` and `-` both ping-pong to the previously-active slice. Same model as GraphPanel's double-right-click zoom revert — a single `prevSliceMode` variable is swapped, so repeated presses toggle between two most-recent slices rather than walking a full history stack. Slice changes from CSV loads (`onPaddleFileSelected`, `onBoatFileSelected`) also update the history, so loading a boat CSV while in Slice A pushes A for later revert.

### 12.11 Key bindings — current state (8 Jul 2026)

All slices:
| Key | Action |
|-----|--------|
| `0`               | Slice 0 (calibration) |
| `1` or Shift+`P` (`P`) | Slice A — paddle view; compass letter `P` |
| `2` or Shift+`K` (`K`) | Slice B — kayak view; compass letter `K` |
| `3` or Shift+`W` (`W`) | Slice C — combined view; compass letter `W` |
| `v` / `V`         | Toggle side / top-down camera |
| Backspace or `-`  | Go back to previously-active slice (ping-pong) |
| `p` (lowercase)   | Open paddle CSV |
| `b` / `B`         | Open boat CSV |

Slices A / B / C additional:
| Key | Action |
|-----|--------|
| Space | Play / pause |
| ← / → | Step 100 frames |
| `,` / `.` | Step 1 frame |
| Home / End | Jump to start / end |
| `k` (lowercase) | Capture reference — mean quat over ±50 frames |
| `u` (lowercase) | Clear reference — back to raw quat |
| `S` (Shift+s) | Reset graph zoom to full range (also pushed to history) |
| `E` (Shift+e) | Export merged CSV over current zoom |

Slice 0 (calibration) — routed through `cal.handleKey()`:
| Key | Action |
|-----|--------|
| `y` / `Y` `p` / `P` `r` / `R` | Nudge yaw / pitch / roll by ± step |
| `[` / `]` | Halve / double step |
| `Z` | Zero all three |
| `S` | Save `data/model_calibration.json` |
| `L` | List current triple to console |

Graph panel mouse gestures (Slices A/B/C only, when a paddle CSV is loaded):
- **Left-click chart** — move playback cursor to x, pause playback (drag to scrub).
- **Right-click chart** — first click places marker A, second click places B and applies zoom (moves cursor to zoom start).
- **Double right-click same spot** (< 400 ms, within ±8 px) — revert to the previous zoom range (ping-pong).
- **Full button** or `S` key — reset to full range.
- **Cols button** — toggle export column set between `curated` and `all`.
- **Export button** or `E` key — write merged CSV.
- **Slot buttons** (left click) — open field-select dropdown; scroll wheel scrolls the dropdown.
