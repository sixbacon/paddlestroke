# PadViz — Paddle Visualisation Specification

**Version:** 0.5
**Date:** 2026-06-11
**Status:** PadViz complete (Phase 3, 2 Jun 2026). PadViz2 complete (11 Jun 2026). PadViz3 complete (11 Jun 2026). Phase 2 firmware (v8.8) still pending.

---

## 1. Purpose

A desktop visualisation tool for the kayak paddle stroke monitor. Displays a 3D paddle
model and kayak driven by live IMU orientation data or replayed from a recorded CSV file.
Intended for:

- Technique analysis (stroke shape, symmetry, entry/exit angles)
- Algorithm development and validation
- Detailed replay of field sessions: zoom to a specific section, step frame-by-frame or
  play back at up to 4× speed

---

## 2. Sketch Versions

Three Processing 4.x sketches exist. PadViz2 and PadViz3 are the current tools; PadViz is
retained for reference.

| Sketch | Folder | Rotation approach | Status |
|---|---|---|---|
| PadViz | `PadViz/` | Quaternion via applyMatrix; ModelMapping tab | Complete (2 Jun 2026) |
| PadViz2 | `PadViz2/` | Euler angles: rotateZ/Y/X chain | Complete (11 Jun 2026) |
| PadViz3 | `PadViz3/` | Quaternion: quatMul + applyMatrix | Complete (11 Jun 2026) |

PadViz2 and PadViz3 are functionally identical; PadViz3 uses the BNO085 quaternion output
directly (no Euler round-trip for 10-col CSV) and is the preferred sketch for new work.

---

## 3. Technology

**Runtime:** Processing 4.x (processing.org, free, Java-based, cross-platform)

| Library | Purpose |
|---|---|
| `processing.serial` | Live serial port input |
| P3D renderer (built-in) | Hardware-accelerated 3D |
| `loadShape()` (built-in) | OBJ paddle model loading |

---

## 4. Coordinate System (PadViz2 / PadViz3)

**User coordinate system:** X right, Y into screen, Z up.

Achieved in Processing P3D by:
```java
camera(eye, centre, up=(0,0,-1));   // makes -Z = screen-up
scale(-1, 1, 1);                     // mirrors X: left-handed IMU → right-handed Processing
```

The BNO085 and Blender both use left-handed axis sets. The `scale(-1,1,1)` mirror is the
only handedness correction needed — no correction quaternion or per-axis sign flags required
(contrast with original PadViz).

**Scale:** S = 150 (1 m = 150 px).
**Camera default:** eye at (0, −3.5 m, 1.3 m) — 0.75 m behind stern, 20° elevation.
camDist = 560, camEl = 20°.

---

## 5. Implementation — PadViz2 / PadViz3

### 5.1 Tabs

| Tab | Role |
|---|---|
| `PadViz2.pde` / `PadViz3.pde` | Main: layout, keyboard/mouse, test modes, yaw EMA, CSV auto-load |
| `Model3D.pde` | P3D sub-canvas, kayak, paddle OBJ, orbit + deck camera |
| `DataSource.pde` | CSV loader (6-col and 10-col), live serial ring buffer |
| `SidePanel.pde` | Speed slider, play/pause, strip chart with zoom, variable selector |

### 5.2 Paddle rotation

**PadViz2 (Euler):**
```java
canvas.rotateZ(radians(corrZ)); canvas.rotateY(radians(corrY)); canvas.rotateX(radians(corrX));
canvas.rotateZ(radians(fd.yaw)); canvas.rotateY(radians(fd.pitch)); canvas.rotateX(radians(fd.roll));
```

**PadViz3 (quaternion):**
```java
float[] qCorr = eulerToQuat(corrX, corrY, corrZ);   // ZYX convention
float[] q     = quatMul(qCorr, new float[]{fd.qw, fd.qx, fd.qy, fd.qz});
applyQuat(canvas, q);   // 3×3 rotation matrix via applyMatrix()
```

Both produce identical results for 6-col CSV. PadViz3 avoids the Euler round-trip for
10-col CSV files that carry raw quaternions.

### 5.3 Kayak model (procedural)

Drawn in `drawKayak()`. Eight-vertex procedural hull in user coordinates:

| Feature | Value |
|---|---|
| Long axis | Y (bow at y = +2.75 m, stern at y = −2.75 m) |
| Deck (blue) | z = −0.5 m — nearest to XY plane, visible from above |
| Hull bottom (grey) | z = −0.65 m |
| Cockpit | Dark rectangle at deck surface, centred at origin |
| Width | ±0.275 m at midship |

The kayak rotates to face the **average yaw** direction (5 s EMA, wrap-safe sin/cos).
This keeps the kayak aligned with the paddling direction while ignoring stroke-to-stroke
yaw oscillation.

### 5.4 Camera modes

Two camera modes toggled with the `C` key:

**Orbit (default):** Camera orbits the world origin. Mouse drag = azimuth/elevation,
scroll = zoom, `R` = reset to default.

**Deck:** Camera pinned 3.25 m behind the stern at deck height (0.1 m above deck),
looking toward the cockpit. Eye position rotates with average yaw so it always follows
the stern as the kayak turns. Mouse drag has no effect in this mode.

### 5.5 Correction nudge

Rest-pose alignment is not needed in practice (Blender and BNO085 both left-handed,
so no correction is required). Controls are present for future use if a different model
is loaded:

- `A` — cycle tune axis: X → Y → Z
- `-` / `=` — nudge −5° / +5° about current axis
- Values shown in HUD as `corr Rx=… Ry=… Rz=…`

---

## 6. Data Sources

### 6.1 CSV file (O key)

Two column formats supported:

**6-col (reduced, field default):**
```
timestamp_ms, roll, pitch, yaw, stroke_count, cpm
```
Quaternion computed from Euler via ZYX convention (`eulerToQuat`).

**10-col (full):**
```
timestamp_ms, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm
```
Quaternion used directly in PadViz3. First line `# PadDis vX.Y` and column-name header
are skipped.

### 6.2 Live serial (L key)

Auto-selects COM3 or COM6 at 115200 baud. Same line format as CSV (6-col or 10-col).
A debug overlay shows frame count, error count, and last raw line.

---

## 7. Layout

```
+-------------------------------+---------------------+
|                               |  Source / filename  |
|   3D view                     |  Play/pause button  |
|   - world axes (RGB)          |  Speed slider       |
|   - kayak (avg yaw heading)   |                     |
|   - paddle (IMU orientation)  |  Variable selector  |
|                               |  (roll/pitch/yaw/   |
|   HUD overlay (top-left)      |   CPM/strokes)      |
|                               |                     |
|                               |  Strip chart        |
|                               |  + zoom footer      |
+-------------------------------+---------------------+
```

Window: 1400 × 800 px. 3D view: 900 px wide. Side panel: 500 px wide.

---

## 8. Keyboard Reference (PadViz2 / PadViz3)

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `→` / `←` | Step one frame |
| `Home` / `End` | Jump to start / end |
| `O` | Open CSV file dialog |
| `L` | Connect / disconnect live serial |
| `R` | Reset camera to default orbit |
| `0` | Normal mode (all axes) |
| `1` / `2` / `3` | Test mode: isolate roll / pitch / yaw only |
| `A` | Cycle correction tune axis (X → Y → Z) |
| `-` / `=` | Nudge correction −5° / +5° about tune axis |
| `C` | Toggle deck camera / orbit camera |

---

## 9. HUD Overlay (3D panel, top-left)

```
t       183.4 s
roll    −14.2°
pitch     4.5°
yaw      87.3°
CPM      34.1
sc       42
corr  Rx=0.0  Ry=0.0  Rz=0.0   tune:X (A to cycle, -/= to nudge)
cam   ORBIT  (C to toggle)
```

In test modes an additional red line shows e.g. `TEST: ROLL ONLY`.

---

## 10. Side Panel

Top to bottom:

1. **Source name** — filename or `(no file — press O to open)`
2. **Play / Pause button** — green when playing, red when paused
3. **Speed slider** — `STEP` at left end, `1×` at mid, `4×` at right
4. **Variable selector** — click to assign to a colour slot (up to 3 simultaneously):
   `roll`, `pitch`, `yaw`, `CPM`, `strokes`
5. **Strip chart** — full session; yellow cursor = current frame; drag cursor to seek;
   drag elsewhere to set zoom window
6. **Zoom footer** — `Full` button resets zoom; shows current time window

---

## 11. Phase 2 — Firmware (PadLog + PadDis) — PENDING

Modify the production sketches to output data in the format PadViz requires (v8.8):

| Change | Sketch(es) | Detail |
|---|---|---|
| Add `q_w, q_x, q_y, q_z` to `CSV_COLUMNS_REDUCED` | PadDis | Direct quaternion in file replay |
| `cpm` field: `uint32_t` → `float` | Both | Transmit `hz × 60.0` directly |
| Remove `hz` field from payload | Both | Redundant; payload 60 → 56 bytes |
| Add structured serial output line | PadDis | Enables live serial mode |

---

## 12. Out of Scope

- Stroke detection algorithm changes (PadLog / StrokeDetector)
- Wireless link modifications
- Real-time network streaming (serial only)
- VR / headset output
- Audio feedback
