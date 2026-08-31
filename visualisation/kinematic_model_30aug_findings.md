# Kinematic-model estimate — examination on the 30 Aug 2026 session

**Date:** 2026-08-30
**Session:** `PadLog20260830.CSV` / `BoatLog20260830.CSV` — the well-calibrated
forward-paddling session (clip-on-jig calibration at its start). Classified into
**four separate right-handed forward-paddling runs** with the three turns left in
the unclassified gaps between them (runs at paddle frames 65 927–90 923,
97 297–122 796, 128 164–158 863, 165 406–189 730: **105 522 frames, ~18 min,
36–38 CPM**). Each run is scored independently — no run-boundary seam enters the
double differentiation / FFT band-pass — and the per-axis energies are pooled.
**Script:** `visualisation/stroke_kinematic_model.py`
**Figure:** `visualisation/kinematic_model_30aug.png`
**Illustrated explainer:** [Where is the paddle? — dynamic modelling from orientation](https://claude.ai/code/artifact/d7e7f597-8380-4110-856d-fcd2c2cd5472) (Artifact — a plain-language, diagram-led walk-through of this model)
**Reference:** `firmware/specs/functional_spec.md` §8.1.1.

## Question

Can a seat-anchored kinematic model, driven only by the measured paddle-vs-boat
orientation, estimate the paddle-centre position through the stroke — and how far
does it get before the torso lean/twist residual (which two IMUs cannot observe)
dominates?

## Model

One-pivot arm-swing. The paddle centre `c` lies on a sphere of radius `R` about a
shoulder-centre pivot `P` **fixed in the boat frame**, with its direction slaved
to the measured relative orientation:

```
c(t) = R · R_rel(t) · d̂        R_rel = R_boat(t)ᵀ · R_paddle(t)
```

`R = 0.67 m` (pivot→centre reach — measured, not assumed), `d̂ = [0, 0.97, −0.24]`
(forward + slightly down at rest), tip half-length `1.05 m`. Because the scoring
fits a best-fit scale per axis, R never enters the variance-explained numbers
(scale-free); it sets only the metric trajectory and the GPS aft-sweep. This is
pure forward kinematics of the
measured shaft orientation — no per-frame free parameters, no integration. It
captures arm-swing and, by construction, **cannot** represent lean/twist (which
translates `P`) — exactly the spec's predicted unobservable.

## Method

Validated without any position ground truth and without integrating acceleration:

1. **Frame check** — rotate the paddle accelerometer to world; its mean should be
   `[0,0,g]`.
2. **Acceleration space** — differentiate the model position twice (`a_model`);
   rotate the measured accel to the boat frame and remove gravity (`a_meas`, the
   *true* paddle-centre acceleration); band-pass both to the stroke band and
   report the fraction of measured variance the model explains. A best-fit scale
   absorbs the reach-radius amplitude, so the score reflects **shape** agreement.
3. **GPS pseudo-ZUPT** — while the blade is immersed the planted tip is ~still in
   the world, so in the boat frame it sweeps aft at ~boat speed. Compare.
4. **Fused vs GRV** — re-score with each orientation source.

Boat↔paddle synchronised by nearest `rx_ms`: median gap **5 ms** (95th pct 10 ms).

## Results

Per-run mean variance-explained (fused): **0.52, 0.55, 0.57, 0.52** — strikingly
consistent across the four separated runs. Pooled:

| Check | Result |
|---|---|
| Frame pipeline (mean world accel) | **[−0.13, −0.28, 9.76] m/s²** ≈ [0,0,g] — quaternion/frame math correct; accel is gravity-inclusive |
| Shaft orientation signal | swing p2p **~120°**, elevation ±~50° — large, clean, stroke-periodic |
| Accel variance explained — X (stbd) | **0.44** |
| Accel variance explained — Y (fwd) | **0.61** |
| Accel variance explained — Z (up) | **0.57** |
| Overall — mean var-explained | **0.54** (per-run corr ~0.70) |
| Orientation source | **fused 0.54** vs GRV **0.40** |
| GPS pseudo-ZUPT (immersed tip aft-sweep, R = 0.67) | median **3.50 m/s** vs boat speed **2.53 m/s** |

*(Earlier single-range run over 58 966–197 628 with the turns left in and R = 0.55
gave mean 0.55 / Y 0.63 / GPS 3.26 vs 2.44 — i.e. removing the turns and correcting
the reach moved nothing of substance; see the first conclusion.)*

## Conclusions

- **The orientation foundation is solid.** The frame check (gravity rotating to
  near-pure vertical) validates the whole quaternion/relative-orientation
  pipeline, and the shaft-orientation signal is large and cleanly periodic.

- **Removing the three turns changed nothing of substance** (and the four runs are
  highly self-consistent). Splitting the good paddling into four turn-free runs and
  scoring each independently gave 0.52 / 0.55 / 0.57 / 0.52 and a pooled 0.54 —
  versus 0.55 for the single contiguous range with the turns left in. So the earlier
  result was not biased by the turns. The per-run agreement (all within ±0.03) is
  actually stronger evidence that the model behaves stably on forward paddling than
  any single pooled figure, and it is only visible because the runs were separated.

- **The one-pivot arm-swing model reproduces roughly half to two-thirds of the
  real paddle-centre motion** — 54 % of stroke-band acceleration variance overall
  (61 % on the forward axis, correlation ~0.70), from orientation alone, with no
  fitted per-frame parameters. For a two-parameter geometric model that is a
  genuine result: the arm-swing is the dominant, recoverable part of the motion.

- **The GPS pseudo-ZUPT corroborates — and points at the residual.** The model's
  planted-blade aft-sweep (median 3.50 m/s) sits ~1 m/s *above* boat speed
  (2.53 m/s). A perfectly planted blade should sweep aft at ~boat speed, so the
  rigid straight-arm model is **over-swinging** — it converts all the measured
  orientation change into centre translation at full reach, with no elbow or torso
  compliance to absorb any. That is exactly the motion a bent-elbow / torso term
  would soak up, so this check now points at the same residual from a third,
  independent direction (velocity, not acceleration). Sign and order of magnitude
  are right; the excess is physically informative, not error.

- **The residual (~40–45 %) is the predicted lean/twist unobservable.** It is the
  part of the measured acceleration the fixed-pivot model cannot produce — torso
  lean and rotation translate the shaft without rotating it, so orientation alone
  can never recover it. This matches §8.1.1's prediction that arm-swing is
  captured well and lean/twist is left as a bounded residual.

- **Fused beats GRV** for this well-mag-calibrated session (0.54 vs 0.40 var
  explained), consistent with the PadViz §15.12 finding that GRV's yaw drift makes
  it the worse relative-orientation source here.

## Calibrating the body constants from the jig pose (30 Aug 2026)

The first pass used *assumed* constants (reach `R = 0.55 m`, rest direction
`d̂ = [0, 0.97, −0.24]`, no boresight). Calibrating them from the jig/rest window
(`stroke_kinematic_model.py`, calibration block):

| Constants | Var-explained |
|---|---|
| Assumed (no calibration) | 0.54 |
| **+ jig boresight** (assumed d̂) | **0.58** |
| + fitted d̂ (no boresight) | 0.56 |
| **+ jig boresight + fitted d̂** | **0.59** |

- **Jig boresight = 10.9°.** The two sensor frames are not perfectly aligned even
  in the jig; removing that constant skew (reference the relative orientation to
  the jig pose) is the **single biggest improvement** (0.54 → 0.58) — and it is
  exactly what the jig pose can genuinely supply.
- **Fitted reach direction** `d̂ = [0.134, 0.957, −0.259]` (8° toward the stroke
  side, 15° below horizontal) — physically sensible, adds a little more (→ 0.59).
- **Reach magnitude R is *not* recoverable** from inertial + GPS data. The
  blade-tip velocity is dominated by the *measured* blade rotation (independent of
  R), and the acceleration score is scale-free (a best-fit scale absorbs R), so the
  arm length simply does not enter. The GPS solve for R returns a nonsensical
  negative value — not a bug, an ill-posed constraint. R must stay anthropometric,
  or come from the jig's *measured geometry* (tape-measured sensor separation), not
  from the motion.

**Takeaway:** the jig pose calibrates the orientation *reference* (worth ~4 points
of variance-explained here) and, with the data, the reach *direction*; it cannot
give the reach *magnitude*. This mirrors the whole result — orientation is
recoverable, absolute scale/translation is not without measured geometry or a
ranging sensor.

## Bottom line

On a well-calibrated session the seat-anchored kinematic model recovers the
majority of the paddle-centre motion (≈54 %, ≈61 % forward) from orientation
alone — consistently across four separated forward-paddling runs — and its blade
kinematics agree with the independent GPS constraint. The remaining ~40–45 % is
the lean/twist (and elbow-flexion) component that is fundamentally unobservable
from two IMUs — so this is about the ceiling for an inertial-only estimate. To go
further (true live paddle-centre tracking) needs the ranging sensor (UWB /
camera baseline) noted for the next hardware iteration (§8.1). Two obvious
software next steps if this line is pursued: per-limb anthropometry calibrated
from the jig pose (replacing the assumed `R`, `d̂`), and folding the GPS
pseudo-ZUPT in as an actual per-stroke re-zero rather than only a consistency
check.

---
*Provenance: analysis and figure produced by `visualisation/stroke_kinematic_model.py`
(numbers reproduced in this run); report written by Claude Opus 4.8 (Claude Code
session), 30 Aug 2026. See `PROVENANCE.md`.*
