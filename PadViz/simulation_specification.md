# PadViz — Paddle Visualisation Specification

**Version:** 0.3
**Date:** 2026-06-02
**Status:** Phase 2 ready to implement. Phase 3 ready to implement (all questions resolved).

---

## 1. Purpose

A desktop visualisation tool for the kayak paddle stroke monitor. Displays a 3D paddle model
driven by live IMU orientation data or replayed from a recorded CSV file. Intended for:

- Technique analysis (stroke shape, symmetry, entry/exit angles)
- Algorithm development and validation
- Detailed replay of field sessions: zoom to a specific section, step frame-by-frame or
  play back at up to 4× speed

---

## 2. Technology

**Runtime:** Processing 4.x (processing.org, free, Java-based, cross-platform)

**Libraries used (all bundled with Processing unless noted):**

| Library | Purpose |
|---|---|
| `processing.serial` | Live serial port input |
| `processing.data` (Table) | CSV file loading and parsing |
| P3D renderer (built-in) | Hardware-accelerated 3D |
| `loadShape()` (built-in) | OBJ model loading |

---

## 3. Implementation Phases

### Phase 2 — Firmware (PadLog + PadDis)

Modify the production sketches to output data in the format PadViz requires.
This is identical to the planned v8.8 firmware changes (already documented in
`functional_spec.md §8 roadmap`):

| Change | Sketch(es) | Detail |
|---|---|---|
| Add `q_w, q_x, q_y, q_z` to `CSV_COLUMNS_REDUCED` | PadDis | Enables quaternion-based 3D rotation in file replay mode |
| `cpm` field: `uint32_t` → `float` | Both | Transmit `hz × 60.0` directly; 1 dp in display and CSV |
| Remove `hz` field from payload | Both | Redundant once `cpm` is float; payload 60 → 56 bytes; update `static_assert` |
| Add structured serial output line to `loop()` | PadDis | Enables live serial mode in PadViz (see §4.2) |

Version bump: **v8.8**. Both sketches must be updated together (payload struct must match).

### Phase 3 — Processing sketch (PadViz)

Write the Processing visualisation sketch. All blocking questions are now resolved — see §8.

---

## 4. Data Sources

### 4.1 Source selection

A boolean constant at the top of the sketch selects the active source:

```java
boolean USE_SERIAL = false;   // false = file replay, true = live serial
```

### 4.2 Live serial — PadDis tap

Modify PadDis to emit one structured line per received packet on COM6 (USB-C, stable).
Both production units run normally; the laptop listens on COM6.

Output format — one line per packet at 100 Hz:

```
timestamp_ms,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm\n
```

Example:
```
183420,0.99710,-0.01234,0.07543,0.00021,-14.23,4.51,87.32,42,34.1
```

Baud rate: 115200.

---

## 5. Data Format — File Replay

### 5.1 CSV columns (v8.8 format)

```
# PadDis v8.8
timestamp_ms,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm
```

The header line (`# PadDis vX.Y`) and column-name line are skipped during parsing.

### 5.2 Zoom / subset replay

The user selects a time-range window from the full file (see §7.2). Only rows within
that window are used for replay. The full file is always held in memory so the window
can be changed without reloading.

---

## 6. Layout

The window is divided into two panels:

```
+-------------------------------+---------------------+
|                               |  Speed slider       |
|   3D paddle model             |  Zoom range         |
|   (orbit camera)              |                     |
|                               |  Strip chart        |
|   HUD overlay                 |  (selected vars)    |
|   (CPM, stroke, time, speed)  |                     |
|                               |  Variable select    |
+-------------------------------+---------------------+
```

Approximate split: 65 % left (3D), 35 % right (side panel). Window size: 1400 × 800 px.

---

## 7. Replay Controls (file mode)

### 7.1 Speed

A **slider in the side panel** controls replay speed. Range:

| Slider position | Behaviour |
|---|---|
| Maximum | 4× (four times real-time) |
| Mid-range | 1× (real-time) |
| Minimum (above zero) | Step-by-step — each press of `→` or Play advances exactly one frame |
| `Space` / Pause button | Freeze at current frame |

Inter-frame delay is derived from consecutive `timestamp_ms` values, divided by the
speed multiplier. This preserves the original cadence — gaps at rest play at the same
relative speed as active paddling sections.

### 7.2 Zoom — selecting a replay window

The user can restrict replay to a sub-range of the file:

- **Strip chart drag:** click and drag on the strip chart time axis to define start and
  end time. The selected range highlights. Replay loops within the window.
- **Side panel inputs:** numeric start / end time fields (seconds) mirror the strip chart
  selection and can be edited directly.
- **Reset:** a "Full file" button clears the zoom and restores the full session.

The strip chart always displays the full session; the zoom window is shown as a shaded
overlay. The cursor line moves within the window during replay.

### 7.3 Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `→` | Step one frame forward (while paused or in step mode) |
| `←` | Step one frame back (while paused or in step mode) |
| `R` | Reset camera to default view |

---

## 8. 3D Visualisation

### 8.1 Model

**File:** `PadViz/data/paddle60.obj` with `paddle60.mtl` (already present).
**Format:** OBJ + MTL — natively supported by Processing `loadShape()`, no extra library needed.

**Visual convention:** The red-coloured blade face is the **drive side** — the face that
pushes against the water, oriented towards the rear of the kayak during a stroke.

### 8.2 Model coordinate system and IMU axis mapping

The model uses the following axes (confirmed by user):

| Axis | Direction |
|---|---|
| **X** | Normal to the plane of the right-hand blade (points out of the blade face) |
| **Y** | Along the shaft, towards the right-hand blade |
| **Z** | In the plane of the right-hand blade (blade vertical) |

The BNO085 **roll** (rotation about the shaft long axis) therefore maps to **rotation about
the model Y axis**. The full quaternion from the IMU is applied via `applyMatrix()` to
orient the model. Because the physical mounting angle of the IMU on the shaft may differ
from the model's rest pose, a fixed correction rotation (determined during first-run
calibration) may be applied before the quaternion to align the model to the real-world
resting orientation.

### 8.3 Camera / viewpoint

Mouse interaction:

| Interaction | Action |
|---|---|
| Left-drag | Orbit (azimuth + elevation) |
| Right-drag / scroll | Zoom |
| Middle-drag | Pan |
| `R` key | Reset to default view |

Default view: isometric, paddle horizontal, red (drive) blade facing right, blades fully
visible.

---

## 9. Side Panel

The right-hand panel contains, from top to bottom:

1. **Speed slider** — label shows current multiplier (e.g. `2.0×`) or `STEP` at minimum
2. **Pause / Play button**
3. **Zoom range** — start time field, end time field, "Full file" reset button
4. **Strip chart** — full session width
   - Vertical cursor line = current playback position
   - Shaded overlay = active zoom window
   - Up to 3 variables plotted simultaneously (different colours)
   - Y-axis auto-scales to visible data range
5. **Variable selector** — click to toggle on/off:
   `roll`, `pitch`, `yaw`, `cpm`, `stroke_count`, `q_w`, `q_x`, `q_y`, `q_z`

---

## 10. HUD Overlay (3D panel)

Displayed in the top-left corner of the 3D panel:

```
Time:   183.4 s
CPM:    34.1
Stroke: 42
Speed:  2.0×       [file mode only — shows STEP at minimum speed]
Source: FILE        or  SERIAL
```

---

## 11. Out of Scope

- Stroke detection algorithm changes (PadLog / StrokeDetector)
- Wireless link modifications
- Real-time network streaming (serial only)
- VR / headset output
- Audio feedback
