# PadViz6 — Disciplined Orientation Specification

**Version:** 0.3
**Date:** 2026-07-07
**Status:** **Slices 0, A, B implemented and validated** on 7 Jul 2026 against the `ImuLog20260706-1.CSV` + `BoatLog20260706-1.CSV` calibration recording. Slice C (combined) and the graph/export panels are pending. Files in `visualisation/PadViz6/`. See §12 (implementation status) for the current file list and what each slice does.

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

## 7. Per-Session Rest-Pose Sidecar (Slice C prerequisite)

*Distinct from the Slice 0 model calibration (§4.0). The model calibration is a one-time
per-OBJ constant; the rest-pose sidecar below is a per-session paddle-vs-kayak yaw
alignment captured at the start of each recording.*


Sidecar file next to the paddle CSV: `<basename>.rest.json`.

```json
{
  "session":      "2026-07-15",
  "recorded_at":  "2026-07-15T14:32:11Z",
  "rest_pose": {
    "description":     "Paddle held horizontal across kayak; kayak level; still for 2 s.",
    "paddle_frame_index_start": 187,
    "paddle_frame_index_end":   387,
    "boat_frame_index_start":   19,
    "boat_frame_index_end":     39
  },
  "q_mount_paddle_kayak": { "w": 0.7071, "x": 0.0, "y": 0.0, "z": -0.7071 }
}
```

`q_mount_paddle_kayak` is derived from the mean paddle and mean kayak quaternions over the
rest window. It is applied at CSV load time to every paddle frame before rendering. It is
**never** hard-coded and **never** adjusted at runtime.

**If the sidecar is missing:** PadViz6 loads without a mount correction and prints a HUD
warning `NO REST-POSE SIDECAR — orientation uncorrected`. This is preferable to silently
applying a stale correction.

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

## 12. Implementation Status (7 Jul 2026)

### 12.1 Files present

| File | Purpose |
|---|---|
| `PadViz6.pde` | Main sketch — slice/view state, key routing, HUD, playback |
| `Calibration.pde` | Cal triple + JSON I/O + Slice 0 key bindings |
| `Model3D.pde` | Paddle OBJ loader, `applyQuat`, procedural kayak |
| `DataSource.pde` | Paddle CSV parser (v8.10 + v8.9), `meanQuat` window helper |
| `BoatSource.pde` | Boat CSV parser (v8.10 + v8.9), `meanQuat` window helper |
| `data/paddle60.obj`+`.mtl` | Copied from PadViz5b (post 7 Jul 2026 blade split) |
| `data/model_calibration.json` | Slice 0 output — currently `{0, 0, 0}` (see §12.3) |

Not present (planned for Slice C and beyond): `SyncMap.pde`, `GraphPanel.pde`, `SidePanel.pde`, `Integrator.pde`.

### 12.2 What each slice does

**Slice 0 — DONE.** Interactive calibration tool. World sensor-axis reference (RGB lines) drawn at origin. Paddle drawn under handedness bridge + current calibration triple, no data quaternion. Fixed cameras (side and top-down, `V` toggles). Key bindings `y/Y P/p R/r` nudge yaw/pitch/roll by ± step; `[`/`]` change step; `Z` zero; `S` save JSON; `L` list to console.

**Slice A — DONE.** Loads a paddle CSV (`O` key; PadDis v8.10 17-col with `rx_ms` preferred, v8.9 16-col fallback). Draws paddle under handedness bridge + calibration + data quaternion. Independent frame index with Space / arrows / `,`/`.` / Home / End playback. **Reference subtraction (K/U):** `K` captures the mean quaternion over ±50 frames around the current frame; while active, each frame renders as `qRef⁻¹ * q_current` so the captured pose appears at Slice 0 identity. `U` clears. HUD shows current frame, timestamp, `rx_ms`, quat, Euler, and reference state.

**Slice B — DONE.** Loads a boat CSV (`B` key). Draws procedural kayak (see §12.4) driven by `kayak_qw..qz` through the same pipeline. Independent frame index, independent K/U reference (separate `qRefBoat`). HUD adds a GPS line (fix / speed / COG / UTC). Axis legend switches to boat conventions (+X starboard, +Y bow, +Z deck).

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
- **Boat mean orientation during the same window** (`BoatLog20260706-1.CSV`): kayak roll ≈ +5.9°, pitch ≈ −4°, yaw ≈ 50°, speed = 0. Boat stationary throughout the session, so the COG-mapping acceptance test (§4.2 test 2) is not possible on this file — needs an under-way session.

### 12.8 Not done

- **Slice C** — combined paddle + kayak with `rx_ms` sync from `SyncMap.pde` (byte-for-byte port from PadViz5b) and per-session paddle-vs-kayak yaw sidecar JSON.
- **Bottom graph panel** (`GraphPanel.pde`) with dropdown field selection, drag-to-zoom, and merged CSV export (curated + all-fields modes per §9).
- **Side panel** (`SidePanel.pde`) — filenames, load buttons, play/pause, speed slider.
- **Adaptive side view** for Slice B (starboard-side camera) if desired.
- **Under-way GPS COG mapping test** for Slice B acceptance — needs a new field session.
