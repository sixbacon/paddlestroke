# PadViz — Paddle Visualisation Specification

**Version:** 0.7
**Date:** 2026-07-03
**Status:** PadViz complete (Phase 3, 2 Jun 2026). PadViz2 complete (11 Jun 2026). PadViz3 complete (11 Jun 2026). PadViz4 complete (11 Jun 2026). PadViz5 complete (3 Jul 2026) — dual-log visualiser with synchronisation, bottom graph panel, and export. Phase 2 firmware (v8.8) still pending.

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

Five Processing 4.x sketches exist. **PadViz5 is the current tool for field session analysis.**
Earlier sketches are retained for reference.

| Sketch | Folder | Rotation approach | Status |
|---|---|---|---|
| PadViz | `PadViz/` | Quaternion via applyMatrix; ModelMapping tab | Complete (2 Jun 2026) |
| PadViz2 | `PadViz2/` | Euler angles: rotateZ/Y/X chain | Complete (11 Jun 2026) |
| PadViz3 | `PadViz3/` | Quaternion: quatMul + applyMatrix | Complete (11 Jun 2026) |
| PadViz4 | `PadViz4/` | PadViz3 + IMU double-integration position tracking | Complete (11 Jun 2026) |
| PadViz5 | `PadViz5/` | PadViz4 + dual-log (ImuLog + BoatLog), graph panel, export | Complete (3 Jul 2026) |

PadViz5 extends PadViz4 with simultaneous loading of an ImuLog (paddle) and BoatLog (hull unit)
CSV, synchronisation on GPS time, a full-width bottom graph panel, and merged CSV export.

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

### 6.1 ImuLog (paddle CSV) — O key

Multiple column layouts supported (auto-detected by column count):

**6-col (reduced):**
```
timestamp_ms, roll, pitch, yaw, stroke_count, cpm
```
Quaternion computed from Euler via ZYX convention (`eulerToQuat`).

**10-col:**
```
timestamp_ms, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm
```

**17-col (full, with hz — pre-3 Jul 2026):**
```
seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, hz, gps_utc_sec, gps_uk_offset
```

**16-col (full, no hz — PadDis v8.9 from 3 Jul 2026):**
```
seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, gps_utc_sec, gps_uk_offset
```

First line `# PadDis vX.Y [paddle]` and column-name header rows are skipped.
`gps_utc_sec` is used for synchronisation with BoatLog when available (17-col and 16-col only).

### 6.2 BoatLog (hull CSV) — B key (PadViz5 only)

```
seq, timestamp_ms, gps_utc_sec, gps_uk_offset, gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix,
kayak_qw, kayak_qx, kayak_qy, kayak_qz, kayak_roll, kayak_pitch, kayak_yaw
```
First line `# PadDis vX.Y boat` and column-name header are skipped.

### 6.3 Live serial (L key)

Auto-selects COM3 or COM6 at 115200 baud. Same line format as ImuLog CSV.
A debug overlay shows frame count, error count, and last raw line. (PadViz4 and earlier only.)

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

## 12. PadViz4 — Position Tracking

PadViz4 (`PadViz4/`) adds an `Integrator.pde` tab to PadViz3. All other features are
identical (same coordinate system, keyboard, kayak, strip chart, etc.).

### 12.1 How it works

1. Raw `accelX/Y/Z` (BNO085 sensor body frame, gravity included) is rotated to world
   frame using the orientation quaternion.
2. Gravity is subtracted: world-frame Z reads +9.81 m/s² at rest, so subtract `(0, 0, 9.81)`.
3. Convert to user frame: `user_X = −world_X` (left→right-hand flip); Z unchanged.
4. Double-integrate: acceleration → velocity → position.
5. High-pass drift correction removes low-frequency integration drift:
   - **X** τ = 10 s (paddle path assumed zero-mean over ~10 s)
   - **Z** τ = 30 s + ±0.5 m hard clamp (stroke height bounded)

### 12.2 Data requirement

Requires the **15-col full CSV** format (comment out `#define CSV_COLUMNS_REDUCED` in
PadDis before logging):
```
seq, timestamp_ms, accel_x, accel_y, accel_z, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm, hz
```
6-col and 10-col CSV files are still accepted; `P` key mode has no effect on them (accel
fields default to zero so no translation occurs).

### 12.3 Additional key

| Key | Action |
|---|---|
| `P` | Toggle paddle position mode (resets integrator on enable, file load, or seek) |

### 12.4 HUD additions (when position mode active)

```
posX   0.12 m
velX   0.34 m/s
posZ  -0.05 m
```

### 12.5 Accuracy notes

- Drift is severe beyond ~30 s of integration. Best used for short clips.
- The high-pass filters remove slow drift but also attenuate genuine low-frequency motion.
- For better accuracy: change firmware to report `SH2_LINEAR_ACCELERATION` (gravity
  already subtracted by BNO085 fusion engine), which eliminates the gravity-subtraction
  step and improves linearity.
- Left/right sign may require empirical verification; negate `posX` in `Integrator.pde`
  if the paddle moves in the wrong direction on screen.

---

## 13. PadViz5 — Dual-Log Visualiser

PadViz5 (`PadViz5/`) is the current production visualisation tool. It extends PadViz4 with
simultaneous dual-file loading, time synchronisation, a bottom graph panel, and CSV export.

### 13.1 Tabs

| Tab | Role |
|---|---|
| `PadViz5.pde` | Main: layout, keyboard/mouse routing, HUD, playback |
| `DataSource.pde` | ImuLog parser; supports 6/10/16/17-col; `gps_utc_sec` field |
| `BoatSource.pde` | BoatLog parser; `BoatFrameData` (kayak quaternion, GPS, speed) |
| `SyncMap.pde` | Links paddle frame indices to boat frame indices via `gps_utc_sec` |
| `SidePanel.pde` | File names, sync status, play/pause, speed slider, GPS clock, export button |
| `GraphPanel.pde` | Full-width bottom graph: field dropdowns, traces, zoom, export |
| `Model3D.pde` | P3D sub-canvas; kayak oriented by boat quaternion when BoatLog loaded |
| `Integrator.pde` | Unchanged from PadViz4 |

### 13.2 Layout

```
+-------------------------------+-----------+
|                               |  PAD: ... |
|   3D view (900 × 700 px)      |  BOAT:... |
|   - paddle (IMU quaternion)   |  SYNCED   |
|   - kayak (boat quaternion    |  Play/Pause|
|     when BoatLog loaded,      |  Speed    |
|     else avgYaw fallback)     |  Frame/t  |
|                               |  GPS time |
|   HUD (top-left)              |  [Export] |
+-------------------------------+-----------+
|  Graph panel  (1200 × 300 px, full width) |
|  [Slot 1 ▼] [Slot 2 ▼] [Slot 3 ▼]       |
|  Time-series traces — drag to zoom        |
|  [Full]  42.3s – 67.8s  (25.5s)          |
+-------------------------------------------+
```

Window: 1200 × 1000 px. 3D view: 900 × 700 px. Side panel: 300 × 700 px. Graph: 1200 × 300 px.

### 13.3 Synchronisation

Both files are synchronised on `gps_utc_sec` (integer GPS UTC seconds). A two-pointer sweep
in `SyncMap.build()` maps each paddle frame to the nearest boat frame within ±5 seconds.

**Current limitation:** GPS time has 1-second resolution; many paddle frames share the same
boat frame. Boat-source traces on the graph appear as step functions at ~1 Hz.

**Planned improvement:** Use `timestamp_ms` linear clock-offset model (GPS tick pairs as
anchors) to achieve sub-10 ms sync accuracy. See `SyncMap.pde` for implementation point.

### 13.4 Graph Panel

- **Field selector:** three colour-coded slot buttons (red / green / blue). Click a button
  to open a dropdown listing 13 fields:
  - Paddle: `roll`, `pitch`, `yaw`, `CPM`, `strokeCount`, `accel_x`, `accel_y`, `accel_z`
  - Boat: `kayak_roll`, `kayak_pitch`, `kayak_yaw`, `speed_ms`, `cog_deg`
- **Zoom:** drag on the chart area to set a zoom window; drag the yellow cursor line to seek.
  Field selection can be changed at any zoom level.
- **Full button:** resets zoom to full session.
- **Time labels:** show start and end time of the current view in seconds from device start.

### 13.5 Keyboard (PadViz5 additions over PadViz4)

| Key | Action |
|---|---|
| `O` | Open ImuLog (paddle) CSV |
| `B` | Open BoatLog CSV |
| `E` | Export zoomed region to merged CSV (also available via Export button) |

All PadViz4 keys (`Space`, `←/→`, `Home/End`, `R`, `C`, `P`, `A`, `-/=`, `0–3`) are unchanged.

### 13.6 Export (E key)

Writes a merged CSV covering the current zoom window (full session if no zoom set).
One row per paddle frame; matching boat columns appended. Rows with no boat match
(outside sync range or no GPS fix) have empty boat columns.

**Export columns:**
```
pad_seq, pad_ts, pad_roll, pad_pitch, pad_yaw, pad_cpm, pad_stroke,
pad_accel_x, pad_accel_y, pad_accel_z, pad_gps_utc,
boat_ts, boat_gps_utc, boat_lat, boat_lon, boat_speed_ms, boat_cog,
kayak_roll, kayak_pitch, kayak_yaw
```

### 13.7 Kayak 3D orientation

When a BoatLog is loaded, the kayak model is rotated by the full `kayak_qw/qx/qy/qz`
quaternion from the matched boat frame (replaces the paddle avgYaw-only fallback used in
PadViz3/4). The deck-camera heading also follows the boat yaw when boat data is present.

---

## 14. Out of Scope

- Stroke detection algorithm changes (PadLog / StrokeDetector)
- Wireless link modifications
- Real-time network streaming (serial only)
- VR / headset output
- Audio feedback
