# PadViz — Paddle Visualisation Specification

**Version:** 0.1 (draft)
**Date:** 2026-05-20
**Status:** Pre-implementation — awaiting model format and serial source decision

---

## 1. Purpose

A desktop visualisation tool for the kayak paddle stroke monitor. Displays a 3D paddle model
driven by live IMU orientation data or replayed from a recorded CSV file. Intended for:

- Technique analysis (stroke shape, symmetry, entry/exit angles)
- Algorithm development and validation
- Replay of field sessions at variable speed with variable selection

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

## 3. Data Sources

### 3.1 Source selection

A boolean constant at the top of the sketch selects the active source:

```java
boolean USE_SERIAL = false;   // false = file replay, true = live serial
```

### 3.2 Option A — Dedicated `PadLogSerial` sketch (decision pending)

A new Arduino sketch derived from PadLog with ESPnow removed. The LOLIN32 Lite USB
becomes unstable when ESPnow runs at 100 Hz; without ESPnow the serial link is
rock-solid at 100 Hz.

- Hardware: PadLog unit (LOLIN32 Lite, COM3) — standalone, no CYD needed
- Output: one CSV line per IMU packet at 100 Hz to serial (see §4.2)
- Maintenance: StrokeDetector copies must be kept in sync with PadLog

### 3.3 Option B — PadDis serial tap (decision pending)

Add a single `Serial.printf` line to PadDis's packet-received block. The CYD uses
USB-C and ESPnow receive does not disrupt USB serial. Both production units run
normally; laptop listens on COM6.

- Hardware: both units (PadLog + PadDis) running production firmware
- Output: same CSV line format as Option A, on COM6
- Maintenance: one extra line in PadDis.ino — minimal

**Decision:** TBD. Spec will be updated when chosen.

---

## 4. Data Format

### 4.1 File replay — CSV

Existing `ImuLog*.CSV` files logged by PadDis. The reduced column set (`CSV_COLUMNS_REDUCED`)
currently omits quaternions. **A firmware change is required** to add quaternion columns:

**Current reduced columns:**
```
timestamp_ms, roll, pitch, yaw, stroke_count, cpm
```

**Required extended columns (new format, requires PadDis firmware update and version bump):**
```
timestamp_ms, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm
```

File header line (`# PadDis vX.Y`) is skipped during parsing.

### 4.2 Live serial — line format

One line per packet, matching the CSV column order (no header):

```
timestamp_ms,q_w,q_x,q_y,q_z,roll,pitch,yaw,stroke_count,cpm\n
```

Example:
```
183420,0.99710,-0.01234,0.07543,0.00021,-14.23,4.51,87.32,42,34
```

Baud rate: 115200.

---

## 5. Layout

The window is divided into two panels:

```
+---------------------------+-------------------+
|                           |                   |
|   3D paddle model         |  Strip chart      |
|   (orbit camera)          |  (selected vars)  |
|                           |                   |
|   HUD overlay             |  Variable select  |
|   (CPM, stroke, time)     |  (click to plot)  |
+---------------------------+-------------------+
```

Approximate split: 65 % left (3D), 35 % right (chart). Window size: 1400 × 800 px.

---

## 6. 3D Visualisation

### 6.1 Model

User-supplied 3D model of the paddle. Format: **TBD** (OBJ preferred — natively supported
by Processing's `loadShape()`; STL requires an additional library).

Model file placed in `PadViz/data/paddle.obj` (or equivalent).

### 6.2 Orientation — quaternion method

Orientation is applied via the IMU quaternion (`q_w, q_x, q_y, q_z`) rather than
sequential Euler rotations. Reasons:

- BNO085 outputs quaternions natively; Euler angles are derived and lose information
- Avoids gimbal lock (pitch ±90° is reachable during aggressive strokes)
- No angle-wrapping artefacts (eliminates the ±180° yaw wrap seen in Phase 7)
- Applied via `applyMatrix()` from the quaternion-to-rotation-matrix conversion (no trig at runtime)

The shaft axis mapping (which model axis aligns with the paddle shaft) is **TBD** — to be
confirmed once the model is provided.

### 6.3 Camera / viewpoint

Mouse interaction (Processing arcball pattern):

| Interaction | Action |
|---|---|
| Left-drag | Orbit (azimuth + elevation) |
| Right-drag / scroll | Zoom |
| Middle-drag | Pan |
| `R` key | Reset to default view |

Default view: isometric-ish, paddle horizontal, blades visible.

---

## 7. Replay Controls (file mode)

| Control | Action |
|---|---|
| `Space` | Play / pause |
| `←` / `→` arrow keys | Step one frame back / forward |
| `[` / `]` | Decrease / increase replay speed (0.1× … 10×) |
| Click on strip chart | Jump playback to that time position |

Speed indicator displayed in HUD. Real-time is 1.0×.

Inter-frame delay is computed from consecutive `timestamp_ms` values, scaled by the speed
multiplier. Preserves the original cadence — pauses at rest, runs faster during active
paddling.

---

## 8. Strip Chart

- Scrolling time-series plot, right-hand panel
- Up to **3 variables** plotted simultaneously (different colours)
- Variables available for plotting: `roll`, `pitch`, `yaw`, `cpm`, `stroke_count`, `q_w/x/y/z`
- Click a variable name in a legend list to toggle it on/off
- Vertical red cursor line tracks current playback position
- Y-axis auto-scales to visible data range
- Time axis shows last N seconds (N configurable, default 10 s)

---

## 9. HUD Overlay (3D panel)

Displayed in the top-left corner of the 3D panel:

```
Time:   183.4 s
CPM:    34
Stroke: 42
Speed:  1.0×       [file mode only]
Source: FILE        or  SERIAL
```

---

## 10. Outstanding Questions

| # | Question | Needed for |
|---|---|---|
| Q1 | 3D model file format (OBJ / STL / other)? | Library selection, §6.1 |
| Q2 | Paddle shaft axis in model coordinate system (X / Y / Z)? | Quaternion axis mapping, §6.2 |
| Q3 | Serial source: Option A (PadLogSerial) or Option B (PadDis tap)? | §3, firmware changes |

---

## 11. Firmware Changes Required

| Change | Sketch | When |
|---|---|---|
| Add `q_w, q_x, q_y, q_z` to `CSV_COLUMNS_REDUCED` columns | PadDis | Before first file-mode test |
| Add structured serial output line (§4.2) | PadDis (Option B) or new PadLogSerial (Option A) | Before first serial-mode test |

Version bump required for PadDis when CSV format changes (v8.8).

---

## 12. Out of Scope

- Stroke detection algorithm changes (PadLog / StrokeDetector)
- Wireless link modifications
- Real-time network streaming (serial only)
- VR / headset output
