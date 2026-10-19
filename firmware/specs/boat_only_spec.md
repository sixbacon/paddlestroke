# Boat-Only Unit — Functional Specification

**Project:** paddlestroke
**Date:** 2026-10-19
**Version:** 0.2 (adds the phased test plan §9, companion-app choice §10, and the
phone-GPS-optional hardware variants §3; feasibility from the 12 Aug / 30 Aug 2026 sessions)
**Status:** concept + offline feasibility proven for cadence & speed; firmware not started.

---

## 1. Purpose and scope

A **standalone hull-mounted unit** that reports **paddling cadence, speed, and
location** to a mobile phone over Bluetooth — with **no paddle unit and no
display/receiver unit**. It reuses the existing boat-unit hardware (ESP32 +
BNO085 IMU + GPS), drops the ESP-NOW link, the CYD display, and the SD logger
(the phone logs), and adds a BLE link to the phone.

It is deliberately a *reduced* product. It does **not** attempt any per-blade
measurement — asymmetry, feather, blade path, or per-side catch/exit timing — all
of which require the paddle unit. What it does give is the two numbers a paddler
most wants in real time (**cadence and speed**) plus the **track**, in one sealed
box, for a kayak, and — notably — for a **single-bladed craft (Canadian/open canoe
or stand-up paddleboard)** where this architecture is actually a better fit than
the full two-unit system.

This spec is a sibling of `firmware/specs/functional_spec.md` (the full kayak
system). Shared hardware and conventions are referenced, not repeated.

---

## 2. How it works (principle)

Two independent, well-understood signals carry everything this unit reports:

- **Speed and location** come straight from **GPS** — independent of the paddle
  entirely (feather, handedness, blade count all irrelevant).
- **Cadence** comes from the **hull's forward-surge acceleration**. Every blade
  plant drives the boat forward, so the hull surges once per stroke. The surge
  fundamental *is* the stroke rate, recovered from the 100 Hz IMU by a spectral /
  autocorrelation method.

The key property: the surge is produced by the **propulsion**, not by the paddle's
orientation. So it is **robust to exactly the paddle-setup variations that
complicate the paddle-side roll detector** — feather angle, zero-feather symmetry,
two-piece joint play — because none of those change the fact that a stroke pushes
the boat forward.

---

## 3. Hardware (reused from the boat unit)

| Item | Part | Notes |
|---|---|---|
| MCU | ESP32 (WEMOS LOLIN32 Lite class, `esp32:esp32:lolin32-lite`) | Classic ESP32 — **BLE and BT Classic built in**, no extra radio. |
| IMU | BNO085 via SPI (`Adafruit_BNO08x`) | Orientation (quaternion + roll/pitch/yaw), GRV, linear accel at 100 Hz. |
| GPS | the receiver used on the current boat unit | Lat/lon, speed, course, UTC time, fix flag at ~1 Hz. |
| Power | LiPo + regulator | No display/SD load, so budget is lower than the CYD. |
| Enclosure | sealed, hull-mounted | Mounting convention retained: **X = starboard, Y = forward, Z = up**. |

**Removed vs the full system:** ESP-NOW transmit, the CYD receiver/display, and
on-board SD logging. Because Wi-Fi/ESP-NOW is gone, the Wi-Fi↔Bluetooth
coexistence problem on the shared 2.4 GHz radio **does not arise** — the radio is
BLE-only.

**Two variants — and with a phone app the GPS is optional:**

- **Minimal (phone-paired) variant — ESP32 + IMU + BLE + battery, NO GPS.** The
  phone already has GPS, so **speed and location come from the phone**; cadence is
  derived from the hull IMU surge (GPS never sees cadence — §4), so the hull needs
  to send only the one thing the phone cannot derive itself. This is the cheapest,
  smallest, lowest-power build and the recommended shape for the phone-app product.
- **Standalone-logger variant — add GPS (+ optional SD).** Only needed if the unit
  must record speed/track *without* a phone present. The **validation rig** should
  carry GPS regardless, to provide an independent speed reference.

---

## 4. Cadence from hull surge — measured feasibility

Offline spectral test of the boat forward-surge acceleration against known
cadence, on recorded sessions. Script: `visualisation/stroke_boat_cadence.py`
(reproduces the table below; recordings are git-ignored). Each blade plant surges
the hull once, so for an **alternating double blade** the surge fundamental sits at
**2× the left-right cycle rate** (the stroke rate); dividing by two recovers the
"CPM" cycle-rate convention.

| Section | True cycle | Surge → cadence | Energy conc. | Paddle-roll detector |
|---|---|---|---|---|
| 30 Aug feathered RH | 36.0 CPM | **36.4** | 95 % | works |
| 12 Aug feathered RH | 35.0 CPM | **35.0** | 88 % | works |
| **12 Aug zero-feather** | 32.5 CPM | **33.0** | 94 % | **fails — reads 65 (2×)** |

**The decisive row is the zero-feather one.** The paddle's own roll detector reads
double there (65 CPM) because a symmetric roll waveform is half-period ambiguous;
the hull surge gets it right (33.0 vs true 32.5) because **every plant genuinely
produces a surge — there is no "which peak is which" ambiguity**.

**A second, independent cadence signal — sway.** The hull's *sideways* axis
(`accel_x`) peaks at the **cycle** rate on feathered sessions (0.60–0.61 Hz ≈ 36
CPM) while the *forward* axis peaks at the **stroke** rate (1.17–1.21 Hz = 2×).
Physically clean — the hull snakes once per left-right cycle but surges twice — and
it gives the unit a cross-check and a way to **infer the paddling mode** (see §6).

**GPS cannot see cadence.** GPS speed updates at ~1 Hz (Nyquist ≈ 0.5 Hz), below
the ~1.1–1.2 Hz stroke surge, so it aliases — confirmed on every section
("ALIASED"). GPS gives **mean speed** only; **cadence must come from the IMU**.

---

## 5. Cadence algorithm (design)

On-device, a short sliding window over the forward-surge channel, not a
whole-session FFT:

1. Rotate the hull IMU accel to level the gravity component (or high-pass the
   forward body axis — pitch is small), to isolate the surge.
2. Over a rolling window (~8–16 s at 100 Hz) estimate the dominant surge
   frequency. Two viable estimators, both already in the codebase's lineage:
   - **Autocorrelation** — reuse the firmware `CadenceACF` building block
     (`firmware/production/PadLog/CadenceACF.*`, ported for the zero-feather fix)
     applied to the surge signal; robust and cheap.
   - **FFT** — a 1024-point real FFT (arduinoFFT / ESP-DSP) is well within the
     ESP32's budget at this rate; peak-pick within the plausible band.
3. Gate to a plausible cadence band and require a minimum surge amplitude and
   peak sharpness (cf. the §4 "concentration" metric) before reporting, so glides
   and chop don't produce spurious numbers.
4. Report the stroke rate; convert to the display convention per the detected
   paddling mode (§6).

The **sway channel** (`accel_x`) runs the same estimator in parallel as a
cross-check / mode discriminator.

---

## 6. Single-blade craft (canoe / SUP) — applicability

Physical reasoning (the recorded evidence in §4 is double-blade kayak; **no
single-blade data has been tested yet** — see §9):

- A single blade plants **once per stroke on one side**, so the hull surges
  **once per stroke** — the surge fundamental **is the stroke rate directly**. No
  ×2 cycle structure, no halving, and the half-period ambiguity that defeats the
  paddle roll detector cannot arise. **Detection is simpler than the kayak case.**
- A single-blade stroke also **yaws/sways the hull to the off-side once per
  stroke** (the reason canoeists use J-strokes and SUP paddlers switch sides),
  landing at the **same frequency** as the surge — a second strong cadence-rate
  signal that likely improves SNR rather than hurting it.
- **Mode inference:** double-blade gives surge:sway frequency ≈ **2:1**;
  fixed-side single-blade gives ≈ **1:1**. The unit can likely infer whether to
  report the surge rate directly (single blade) or halve it (double blade) from
  this ratio, rather than being told.

**Net:** for cadence and speed the boat-only unit should serve a canoe or SUP at
least as well as a kayak, and more cleanly. The frontier item is confirming it on
real single-blade logs (§9).

---

## 7. Connectivity — Bluetooth to a phone

**Bandwidth is not a constraint.** The dashboard payload is tiny:

| Field | Size | Rate |
|---|---|---|
| cadence | 4 B | ~1/stroke |
| speed | 4 B | ~1 Hz |
| lat / lon | 8 B | ~1 Hz |
| UTC time + status flags | ~5 B | ~1 Hz |

≈ **20–25 bytes/second**. A BLE link on the ESP32 realistically carries
5–50 kB/s (up to ~175 kB/s with the 2 M PHY), so the dashboard uses **< 0.1 %** of
the link; even the full 100 Hz IMU stream (~8 kB/s) would fit comfortably.

Design choices:

- **Use BLE (not BT Classic).** BLE reaches **both iOS and Android** and is
  low-power; BT Classic/SPP is Android-friendly but iOS restricts it to licensed
  accessories.
- **Standard GATT profiles where possible.** The Bluetooth SIG **Running Speed
  and Cadence (RSC)** and **Location and Navigation (LN)** services already carry
  these quantities, so existing fitness apps may read the unit without a bespoke
  app.
- **Phone GPS option.** The phone has its own GPS; if the app uses that for
  speed/position, BLE need only carry **cadence** — the one thing the phone cannot
  derive itself — shrinking the link to a few bytes. Sending the hull GPS too is
  optional (antenna placement, consistent logging) and still free on bandwidth.
- **Range** ~10–30 m — ample for a phone in a dry bag on the same craft.
- **Logging** moves to the phone app (or a standard-profile recorder), removing
  the SD card from the unit.

---

## 8. What it cannot do (by design)

Everything per-blade needs the paddle unit and is **out of scope** here:

- which blade / left-vs-right **asymmetry**;
- **feather** angle and blade orientation;
- **blade path**, catch/exit position, immersion depth;
- the 3D paddle-vs-boat picture the visualiser renders.

The boat-only unit answers "how fast, how far, how often" — not "how".

---

## 9. Test plan

Four phases, cheapest first. Each test has a pass criterion; cadence accuracy uses
the project's existing field-verification standard (median |err| ≤ 1 CPM steady).
**Ground truth for cadence** = a stroke count from video over a timed interval,
and — on a kayak only — the existing paddle unit run in parallel as a reference.

### Phase A — Offline data analysis (extends §4; no new firmware)

Needs recorded hull IMU (+ GPS) logs; run through `stroke_boat_cadence.py` and
small extensions of it.

| ID | Test | Pass criterion |
|---|---|---|
| A-1 | Generalise the kayak result over **more sessions** (varied pace, several outings) | surge→cadence median \|err\| ≤ 1 CPM vs reference |
| A-2 | **Single-blade: canoe** log vs video count | ≤ 1 CPM; surge fundamental = stroke rate directly (no ×2) |
| A-3 | **Single-blade: SUP** log vs video count | ≤ 1 CPM; paddler body-motion does not mask the surge |
| A-4 | **Rough water** (chop / wake / wind / swell) | either ≤ 2 CPM, **or** the confidence metric correctly flags low-confidence (no confident wrong number) |
| A-5 | **Sliding window** (8–16 s rolling ACF/FFT, not whole-session) tracks cadence incl. ramps and rest→paddle | ≤ 2 CPM during changes; settles ≤ ~1 window after a step change |
| A-6 | **Glide / rest** produces no cadence | reports "no cadence" when surge below the amplitude/sharpness gate |
| A-7 | **Mode discriminator** — surge:sway ratio over mixed single/double-blade data | correctly classifies 1:1 (single) vs 2:1 (double) ≥ 95 % of windows |
| A-8 | **Side-switching** (canoe "hut", SUP side change) | cadence continuous through the switch; recovers ≤ 1 window |

### Phase B — On-device firmware (bench)

| ID | Test | Pass criterion |
|---|---|---|
| B-1 | Port the chosen estimator (ACF — reuse `CadenceACF` — vs FFT) to the ESP32 | runs in real time at 100 Hz within CPU/RAM budget |
| B-2 | Feed recorded surge data (or a controlled manual/shaker oscillation) on-device | on-device cadence matches the offline result to ≤ 1 CPM |
| B-3 | BLE advertise → phone connects → cadence streams | connect ≤ 5 s; update ≥ 1 Hz; latency < 1 s |
| B-4 | BLE reconnection after link drop / unit power-cycle | auto-reconnects ≤ 5 s, no phone-app restart |
| B-5 | Range | usable to ≥ 5 m (phone in a dry bag on the same craft) |
| B-6 | Battery life (BLE-only, no GPS/SD in the minimal variant) | meets a target session length (e.g. ≥ 4 h) |

### Phase C — On-water system (the real proof)

| ID | Test | Pass criterion |
|---|---|---|
| C-1 | **Kayak, feathered** — live phone cadence vs reference | median \|err\| ≤ 1 CPM |
| C-2 | **Kayak, zero-feather** — the case that breaks the paddle-roll detector | ≤ 1 CPM (confirms the §4 headline live) |
| C-3 | **Kayak, two-piece paddle** (joint play) | ≤ 1 CPM (unaffected, unlike the paddle-side algorithm) |
| C-4 | **Canoe** and **SUP** — live cadence vs reference | ≤ 2 CPM |
| C-5 | **Phone GPS vs hull GPS** speed (validation rig carries both) | agree within GPS noise (≈ ±0.2 m/s) → confirms the hull GPS can be dropped |
| C-6 | **Real conditions** — turns, stops/starts, chop, side-switches | no spurious cadence at rest; graceful recovery; no runaway |
| C-7 | **Endurance** — a full-length outing | stable cadence, no dropouts, battery holds |

### Phase D — Companion app

| ID | Test | Pass criterion |
|---|---|---|
| D-1 | App reads the BLE characteristic(s) and displays cadence (+ speed/track) | values correct vs the unit's serial/log |
| D-2 | Logging (phone-side) produces a usable session file | re-openable; timestamps sane |
| D-3 | Platform coverage + backgrounding / screen-lock behaviour | per chosen platform (see §10) |

---

## 10. Companion app — platform choice

The dashboard is trivial to drive (a few BLE reads), so the choice is about who
builds it and which phones it must reach:

| Option | Reach | Notes |
|---|---|---|
| **Web Bluetooth page** (HTML/JS, single file) | **Android + desktop Chrome** (not iOS — Apple blocks Web Bluetooth) | Zero install, nothing to publish — **fastest path for the validation phase**. Can be authored in full as code. |
| **Flutter** (Dart) | **iOS + Android** | Mature BLE (`flutter_blue_plus`); the choice for a shippable cross-platform product. Full source can be authored; needs a build/deploy toolchain. |
| **MIT App Inventor** | Android (iOS support limited) | Block-based/visual — capable (has a BluetoothLE extension) and easy to **build yourself**, but not authorable as code by an assistant, so help there is GATT + block-logic design, not source. |

**Recommendation:** use a **Web Bluetooth page for validation** (immediate, Android,
no install), move to **Flutter** if it becomes a product. App Inventor is a fine
self-build alternative for an Android-only tool.

**BLE service shape (all three can consume this):** expose cadence either on the
standard **RSC** service (so off-the-shelf fitness apps may read it) or on a small
custom GATT service — one notify characteristic carrying `{cadence, confidence,
mode}` at ~1 Hz; optionally a second for hull speed/position if the
standalone-logger variant is used.

---

*Provenance: feasibility numbers in §4 produced by
`visualisation/stroke_boat_cadence.py` on the 12 Aug / 30 Aug 2026 recordings;
this spec written by Claude Opus 4.8 (Claude Code session), 19 Oct 2026. See
`PROVENANCE.md`.*
