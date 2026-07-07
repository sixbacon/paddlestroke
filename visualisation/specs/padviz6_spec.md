# PadViz6 — Disciplined Orientation Specification

**Version:** 0.1
**Date:** 2026-07-07
**Status:** **Planned.** Approved 6 Jul 2026. No files created yet — folder `visualisation/PadViz6/` will be initialised at the start of Slice A.

---

## 1. Purpose

A fresh Processing 4.x visualiser that renders paddle and boat IMU data under an explicit,
documented frame-conversion discipline. PadViz4/5/5b accumulated empirical corrections
(`scale(-1,1,1)`, `corrZ = 180`, axis-cycle keys, nudge-by-5° keys) trying to make
orientation "look right." The 3 Jul 2026 field data revealed that the residual symptoms
were mirror-symmetric — determinant −1 — and cannot be represented by any rotation. All
prior tuning was chasing the wrong model. PadViz6 restarts the orientation model from first
principles and enforces one hard rule: **no correction without a physical reason.**

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

## 3. The One Legitimate Correction

The handedness bridge is **the only pre-rotation permitted in production render paths.** It
is chosen once and named in code:

```java
pushMatrix();
scale(1, 1, -1);          // ← handedness bridge: worldRH ← paddleLH  (flip Z, keep X, Y)
// … apply quaternion rotation here …
// … draw model here …
popMatrix();
```

**Why `scale(1, 1, -1)` and not one of the other two candidates?**
All three (`(-1,1,1)`, `(1,-1,1)`, `(1,1,-1)`) are physically valid — any single axis flip
converts a right-handed frame to a left-handed one. The choice matters only for the shared
mental model. `(1, 1, -1)` was locked in on 6 Jul 2026 because it leaves both horizontal
axes untouched, so on-screen +X remains starboard/right-blade and on-screen +Y remains
forward/blade-normal without further reasoning.

**Rule.** The scale is applied **outside** the quaternion rotation. Never inside. Never
combined into a modified quaternion at load time (this hides the mirror in the data
pipeline and makes the frame convention invisible to anyone reading `Model3D.pde`).

---

## 4. Slices

Slices are built in order. Each passes its rest-pose test before the next begins. **A slice
that fails its rest-pose test is not fixed by adding rotations to the sketch** — it is
diagnosed as either a missing mount rotation (documented, added, and named) or a physical
mounting issue in the source data.

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
| `PadViz6.pde` | Main: setup, draw, key/mouse routing, HUD |
| `Model3D.pde` | Handedness-flip block, quaternion applier, paddle + kayak draw |
| `DataSource.pde` | Paddle CSV parser (skeleton copied from PadViz5b; no correction code) |
| `BoatSource.pde` | Boat CSV parser (skeleton copied from PadViz5b) |
| `SyncMap.pde` | Reused from PadViz5b unchanged (rx_ms + gps_utc dual path) |
| `data/paddle60.obj` + `.mtl` | Copied from PadViz5b (post 7 Jul 2026 blade split) |

Nothing else is carried over from PadViz3/4/5/5b. In particular: **no `corrX`, `corrY`,
`corrZ`** variables; **no `tuneAxis`**; **no `A`, `-`, `=`** keys; **no `scale(-1, 1, 1)`**
anywhere.

---

## 6. Keyboard

| Key | Action |
|-----|--------|
| `1` | Slice A view (paddle only) |
| `2` | Slice B view (kayak only) |
| `3` | Slice C view (combined) |
| `O` | Open paddle CSV |
| `B` | Open boat CSV |
| `Space` | Play / pause |
| `←` / `→` | Step one frame |
| `Home` / `End` | Jump to start / end |
| `R` | Reset camera to default |

Deliberately **omitted** (from PadViz3/4/5b):

- `A` (cycle tune axis)
- `-` / `=` (nudge correction ±5°)
- `0` (normal mode) / `1..3` when overloaded for axis-isolation test modes
- Any key that mutates a correction quaternion at runtime

Test-mode axis isolation, if needed for debugging, must be gated behind a debug flag in
source and not bindable at runtime.

---

## 7. Rest-Pose Calibration Sidecar (Slice C prerequisite)

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
2. No `corrX`, `corrY`, `corrZ` variables.
3. No key that mutates a correction quaternion.
4. Per-session offsets live in sidecar JSON, applied at load, never at render.
5. Any handedness change other than the one `scale(1, 1, -1)` in Slice A/B/C is prohibited.
6. If a slice fails its rest-pose test, the fix is a documented mount rotation added at
   load, or a physical-mounting incident report — never a runtime tweak.

---

## 9. Success Criteria

PadViz6 replaces PadViz5b as the current tool when:

1. Slice A passes its rest-pose test on both the known-good 21 May 2026 session and a
   post-7 Jul 2026 session.
2. Slice B passes its rest-pose test and the COG mapping is documented.
3. Slice C passes its rest-pose test on a session that includes a rest-pose window and
   sidecar.
4. All PadViz5b features that are still wanted (bottom graph panel, dropdown fields,
   drag-to-zoom, merged CSV export, side panel filenames + Load buttons, boat quat for
   kayak) are present under the discipline rules of §8.

Until then, use PadViz5b for graph/export work and PadViz6 (as it is built) for
orientation review only.

---

## 10. Out of Scope

- Any change to firmware, ESPnow link, or CSV column layout.
- Any change to `SyncMap.pde` beyond copying it byte-for-byte from PadViz5b.
- Any attempt to auto-diagnose a physical mount inversion from data alone. The rest-pose
  calibration is user-initiated; if not captured, the session is uncorrected.
