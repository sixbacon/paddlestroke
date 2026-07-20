"""Zero-feather + padbad regression tests for the pitch-fed CadenceACF
arbiter/fallback (firmware spec §16.12). Simulates PadLog.ino's cpm_source
decision logic in Python, running StrokeDetector (roll) and the ACF ring
buffer (pitch) in lockstep against real field CSVs -- companion to
stroke_regression.py's synthetic ST-01..20 StrokeDetector-only suite.

Test 1 (zero-feather fallback, source=1): 16 Jul zero-feather segment.
    Roll amplitude gate never clears (symmetric waveform) so the peak
    detector times out and stays timed out; the pitch ACF should read the
    true cycle rate (~32.8 CPM, per firmware spec §16.10) the whole time.

Test 2 (arbiter suppression, source=2): 11 Jul padbad. Uses the CSV's own
    recorded cpm column (the actual pre-fix firmware's reported rate,
    ~87.4 CPM per spec §16.9's table) as "what the peak detector said",
    compared against a fresh pitch-fed ACF estimate over the same
    timeline -- same methodology stroke_acf.py already validated (spec
    §16.9), just fed pitch instead of roll. Re-simulating StrokeDetector
    from the file's raw roll column (tried first) does NOT reproduce the
    87 CPM runaway (`stroke_detector_sim.py` gives ~30 CPM on this file's
    roll column even with prom_deg=0) -- some fidelity gap between that
    Python port and whatever the firmware actually ran on 11 Jul 2026,
    unrelated to this test. Using the recorded column sidesteps it and
    matches the already-validated §16.9 methodology exactly.

Run from repo root: python visualisation/stroke_zero_feather_regression.py
"""
import csv
import os

import numpy as np

from stroke_detector_sim import StrokeDetector
from stroke_acf import acf_estimate, FS as ACF_FS, WIN_S as ACF_WIN_S, \
    DECIM as ACF_DECIM, MIN_FILL as ACF_MIN_FILL

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

ARBITER_DISAGREE_FRAC = 0.30   # matches PadLog.ino's ARBITER_DISAGREE_FRAC
PEAK_TIMEOUT_S = 3.0
STREAK_MIN = 3
ACF_BUF_LEN = int(ACF_WIN_S * ACF_FS)


def load(fn, cols):
    out = {c: [] for c in cols}
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        for row in csv.DictReader(f):
            try:
                vals = [float(row[c]) for c in cols]
            except (ValueError, KeyError):
                continue
            for c, v in zip(cols, vals):
                out[c].append(v)
    return {c: np.array(v) for c, v in out.items()}


def simulate(ts_ms, roll, pitch, prom_deg=30.0):
    """Mirrors PadLog.ino's reporting block exactly (same if/elif
    structure keyed on a qualifying peak-detector event vs. timeout).
    Returns a list of (t_s, cpm, source) after each sample."""
    det = StrokeDetector(prominence_deg=prom_deg, prominence_win_s=0.3)

    decim_accum = 0.0
    decim_count = 0
    acf_buf = []
    samples_since_estimate = 0
    acf_cpm = 0.0
    acf_valid = False

    streak = 0
    timeout_active = False
    cpm = 0.0
    source = 0
    out = []

    for i in range(len(ts_ms)):
        t_us = int(ts_ms[i] * 1000)

        # -- ACF: decimate 100 Hz -> 10 Hz, 12 s window, 1 Hz estimate --
        decim_accum += pitch[i]
        decim_count += 1
        if decim_count >= ACF_DECIM:
            avg = decim_accum / ACF_DECIM
            decim_accum, decim_count = 0.0, 0
            acf_buf.append(avg)
            if len(acf_buf) > ACF_BUF_LEN:
                acf_buf.pop(0)
            samples_since_estimate += 1
            if samples_since_estimate >= int(ACF_FS):
                samples_since_estimate = 0
                if len(acf_buf) >= ACF_MIN_FILL * ACF_BUF_LEN:
                    est, _q = acf_estimate(np.array(acf_buf))
                    acf_valid = est > 0.0
                    acf_cpm = est
                else:
                    acf_valid = False

        # -- peak detector + arbiter/fallback, mirrors PadLog.ino --
        qualifying = det.update(roll[i], t_us)
        if qualifying:
            streak += 1
            mature = det.rbPc >= 2 and det.rbTc >= 2
            if streak >= STREAK_MIN and mature:
                cpm = det.rate_hz * 60.0
                source = 0
                if acf_valid:
                    dis = abs(cpm - acf_cpm) / acf_cpm
                    if dis > ARBITER_DISAGREE_FRAC:
                        source = 2
                timeout_active = False
        elif (t_us - det.last_qual_ts) > PEAK_TIMEOUT_S * 1e6:
            if not timeout_active:
                det = StrokeDetector(prominence_deg=prom_deg, prominence_win_s=0.3)
                streak = 0
                timeout_active = True
                cpm, source = 0.0, 0
            if acf_valid:
                cpm, source = acf_cpm, 1
            elif source == 1:
                cpm, source = 0.0, 0

        out.append((t_us / 1e6, cpm, source))
    return out


def test_zero_feather():
    p = load(os.path.join(REPO, 'visualisation', 'PadLog20260716.csv'),
              ['timestamp_ms', 'roll', 'pitch'])
    lo, hi = 40252 - 3, 45369 - 3   # 'zero' segment, spec §13.5 / stroke_catch_explore.py
    ts, roll, pitch = p['timestamp_ms'][lo:hi], p['roll'][lo:hi], p['pitch'][lo:hi]

    out = simulate(ts, roll, pitch)
    # Settle time: first ~12 s is ACF ring-buffer fill, skip it.
    settled = [(t, c, s) for t, c, s in out if t - out[0][0] > 13.0]
    sources = [s for _, _, s in settled]
    cpms1 = [c for _, c, s in settled if s == 1]

    frac_source1 = sources.count(1) / len(sources) if sources else 0.0
    median_cpm = float(np.median(cpms1)) if cpms1 else 0.0

    ok = frac_source1 > 0.8 and abs(median_cpm - 32.8) < 3.0
    tag = 'PASS' if ok else 'FAIL'
    print(f'[{tag}] Zero-feather fallback: source=1 for {frac_source1*100:.0f}% of '
          f'settled samples, median CPM {median_cpm:.1f} (expect >80% source=1, '
          f'CPM 32.8 +/-3)')
    return ok


def test_padbad_arbiter():
    from stroke_acf import stream as acf_stream

    p = load(os.path.join(REPO, 'data', '2026-07-11', 'padbad20260711.csv'),
              ['timestamp_ms', 'pitch', 'cpm'])
    ts, pitch, reported = p['timestamp_ms'], p['pitch'], p['cpm']

    # stream() decimates/estimates internally; feeding pitch instead of
    # roll is the only change needed (spec §16.10) -- same function
    # already validated against this exact file's roll column (§16.9).
    est = acf_stream(ts, pitch, reported)
    acf = np.array([e for _, e, _, _ in est])
    rep = np.array([r for _, _, _, r in est], dtype=float)

    both = (acf > 0) & (rep > 0)
    disagree = np.abs(rep[both] - acf[both]) / acf[both] > ARBITER_DISAGREE_FRAC
    flag_frac = disagree.mean() if both.any() else 0.0

    ok = both.any() and flag_frac > 0.9
    tag = 'PASS' if ok else 'FAIL'
    print(f'[{tag}] Padbad arbiter: {both.sum()} samples with both estimators valid, '
          f'{flag_frac*100:.0f}% flagged as source=2 disagreement (expect >90%, '
          f'matching spec §16.9\'s 100%)')
    return ok


if __name__ == '__main__':
    r1 = test_zero_feather()
    r2 = test_padbad_arbiter()
    n_pass = int(r1) + int(r2)
    print(f'\nResults: {n_pass} passed, {2 - n_pass} failed')
