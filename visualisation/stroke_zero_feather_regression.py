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

Test 3 (zero-feather field, 12 Aug 2026): the deployed PadLog v8.10/PadDis
    v8.14 build's OWN field recording (PadLog20260812.CSV, which carries the
    cpm / cpm_source columns). On the PadViz-classified 'zero' section
    (sidecar frames 33470-50499) the firmware's recorded cpm_source is 1 for
    ~98% at cpm ~33.0, and a fresh offline sim over the same rows agrees
    (source=1 100%, ~32.8). Real-world confirmation of the source=1 fallback.

Test 4 (white + arbiter field, 12 Aug 2026): the right-handed (feathered)
    section (frames 65766-341749) of the same file. Feathered = asymmetric,
    so roll AND pitch spectral both give the true rate (~35, no 2x). Firmware
    recorded cpm_source=0 (white peak detector) ~98% at cpm ~35, and the
    arbiter (source=2) fires only ~0.3% -- the key false-positive check. The
    offline sim (bounded sub-window) cross-checks that the arbiter stays quiet
    and the rate is right; it is NOT asserted to keep source=0 dominant
    offline, because the stroke_detector_sim port times out more eagerly than
    the firmware (the Test-2 fidelity gap again) and drops to ACF more often.

Tests 1, 3, 4 read large, git-ignored field CSVs; each SKIPs (rather than
failing the suite) when its file isn't present locally.

Run from repo root: python visualisation/stroke_zero_feather_regression.py
"""
import csv
import os
import sys

import numpy as np

from stroke_detector_sim import StrokeDetector
from stroke_acf import acf_estimate, FS as ACF_FS, WIN_S as ACF_WIN_S, \
    DECIM as ACF_DECIM, MIN_FILL as ACF_MIN_FILL
from stroke_spectral import spectral_rate

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


def find_file(*candidates):
    """First existing path among candidates, else None. Field CSVs are large
    and git-ignored, and move between visualisation/ , data/<date>/ and
    visualisation/recordings/ over a session -- so a test that can't find its
    file SKIPs rather than crashing the whole suite."""
    for c in candidates:
        if c and os.path.isfile(c):
            return c
    return None


def load_rows(fn, cols, lo, hi):
    """Read only data rows [lo, hi] inclusive for the named columns (0 = first
    data row, after the comment + header lines -- matches PadViz frame
    indexing). Column positions come from the header, not hard-coded, and only
    the wanted slice is parsed so a 90 MB file loads a small section fast."""
    out = {c: [] for c in cols}
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()                                  # comment line
        header = f.readline().rstrip('\n').split(',')
        idx = {c: header.index(c) for c in cols}
        for i, line in enumerate(f):
            if i < lo:
                continue
            if i > hi:
                break
            p = line.rstrip('\n').split(',')
            try:
                vals = [float(p[idx[c]]) for c in cols]
            except (ValueError, IndexError):
                continue
            for c, v in zip(cols, vals):
                out[c].append(v)
    return {c: np.array(v) for c, v in out.items()}


# 12 Aug 2026 field session (the deployed PadLog v8.10 / PadDis v8.14 build's
# own recording, with cpm + cpm_source columns). Large + git-ignored; sections
# are the PadViz sidecar's classification frame ranges.
PAD_12AUG = [
    os.path.join(REPO, 'visualisation', 'recordings', 'PadLog20260812.CSV'),
    os.path.join(REPO, 'data', '2026-08-12', 'PadLog20260812.CSV'),
]


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
    fn = find_file(os.path.join(REPO, 'visualisation', 'PadLog20260716.csv'),
                   os.path.join(REPO, 'data', '2026-07-16', 'PadLog20260716.csv'),
                   os.path.join(REPO, 'visualisation', 'recordings', 'PadLog20260716.csv'))
    if fn is None:
        print('[SKIP] 16 Jul zero-feather: PadLog20260716.csv not found (large, git-ignored)')
        return None
    p = load(fn, ['timestamp_ms', 'roll', 'pitch'])
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

    fn = find_file(os.path.join(REPO, 'data', '2026-07-11', 'padbad20260711.csv'),
                   os.path.join(REPO, 'visualisation', 'padbad20260711.csv'))
    if fn is None:
        print('[SKIP] 11 Jul padbad arbiter: padbad20260711.csv not found (large, git-ignored)')
        return None
    p = load(fn, ['timestamp_ms', 'pitch', 'cpm'])
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


def test_zero_feather_field_12aug():
    """Field confirmation of the zero-feather fallback (source=1) on the
    12 Aug 2026 session -- the deployed build's OWN recording. Checks both the
    firmware's recorded cpm_source column and a fresh offline sim over the
    PadViz-classified 'zero' section (sidecar frames 33470-50499)."""
    fn = find_file(*PAD_12AUG)
    if fn is None:
        print('[SKIP] 12 Aug zero-feather field: PadLog20260812.CSV not found (large, git-ignored)')
        return None
    lo, hi = 33470, 50499
    d = load_rows(fn, ['timestamp_ms', 'roll', 'pitch', 'cpm', 'cpm_source'], lo, hi)
    ts, roll, pitch, rec_cpm, rec_src = (d['timestamp_ms'], d['roll'], d['pitch'],
                                         d['cpm'], d['cpm_source'])

    out = simulate(ts, roll, pitch)
    settled = [(t, c, s) for t, c, s in out if t - out[0][0] > 13.0]
    srcs = np.array([s for _, _, s in settled])
    acf = [c for _, c, s in settled if s == 1]
    sim_frac1 = float(np.mean(srcs == 1)) if len(srcs) else 0.0
    sim_med = float(np.median(acf)) if acf else 0.0

    rec_frac1 = float(np.mean(rec_src == 1))
    rec1 = rec_cpm[(rec_src == 1) & (rec_cpm > 0)]
    rec_med = float(np.median(rec1)) if len(rec1) else 0.0

    ok = (sim_frac1 > 0.8 and abs(sim_med - 33.0) < 3.0
          and rec_frac1 > 0.8 and abs(rec_med - 33.0) < 3.0)
    tag = 'PASS' if ok else 'FAIL'
    print(f'[{tag}] 12 Aug zero-feather field (frames {lo}-{hi}): '
          f'firmware source=1 {rec_frac1*100:.0f}% @ {rec_med:.1f} CPM, '
          f'offline sim source=1 {sim_frac1*100:.0f}% @ {sim_med:.1f} CPM '
          f'(expect both >80% source=1, CPM ~33)')
    return ok


def test_white_arbiter_field_12aug():
    """Field confirmation of the white peak-detector path (source=0) and the
    arbiter false-positive rate (source=2) on the 12 Aug 2026 right-handed
    (feathered) section (sidecar frames 65766-341749). Feathered = asymmetric,
    so roll/pitch spectral both give the TRUE rate (no 2x half-period). Primary
    assertion is on the firmware's own recorded columns over the full section;
    an offline sim on a bounded sub-window cross-checks that the arbiter stays
    quiet and the rate is right (NOT that source=0 dominates offline -- the
    stroke_detector_sim Python port times out more eagerly than the firmware, a
    known fidelity gap, so it drops to ACF more often)."""
    fn = find_file(*PAD_12AUG)
    if fn is None:
        print('[SKIP] 12 Aug white+arbiter field: PadLog20260812.CSV not found (large, git-ignored)')
        return None
    lo, hi = 65766, 341749
    d = load_rows(fn, ['timestamp_ms', 'roll', 'pitch', 'cpm', 'cpm_source'], lo, hi)
    ts, roll, pitch, rec_cpm, rec_src = (d['timestamp_ms'], d['roll'], d['pitch'],
                                         d['cpm'], d['cpm_source'])
    fs = 1000.0 / np.median(np.diff(ts))

    truth = spectral_rate(roll, fs, band=(0.25, 1.5))          # ground truth

    rec_white = float(np.mean(rec_src == 0))                   # firmware, full section
    rec_arb   = float(np.mean(rec_src == 2))
    nz = rec_cpm[rec_cpm > 0]
    rec_med = float(np.median(nz)) if len(nz) else 0.0

    SUB = 90000                                                # offline sim ~15 min
    out = simulate(ts[:SUB], roll[:SUB], pitch[:SUB])
    settled = [(t, c, s) for t, c, s in out if t - out[0][0] > 13.0]
    ssrc = np.array([s for _, _, s in settled])
    scpm = [c for _, c, s in settled if s in (0, 1) and c > 0]
    sim_arb = float(np.mean(ssrc == 2)) if len(ssrc) else 0.0
    sim_med = float(np.median(scpm)) if scpm else 0.0

    ok = (rec_white > 0.8 and rec_arb < 0.02 and abs(rec_med - 35.0) < 3.0
          and abs(truth - 35.0) < 3.0
          and sim_arb < 0.03 and abs(sim_med - 35.0) < 3.0)
    tag = 'PASS' if ok else 'FAIL'
    print(f'[{tag}] 12 Aug right white+arbiter (frames {lo}-{hi}): '
          f'firmware source=0 {rec_white*100:.0f}% @ {rec_med:.1f} CPM, '
          f'arbiter source=2 {rec_arb*100:.1f}%; roll-spectral {truth:.1f}; '
          f'offline arbiter {sim_arb*100:.1f}% @ {sim_med:.1f} CPM '
          f'(expect white >80%, arbiter <2%, CPM ~35)')
    return ok


if __name__ == '__main__':
    results = [
        test_zero_feather(),
        test_padbad_arbiter(),
        test_zero_feather_field_12aug(),
        test_white_arbiter_field_12aug(),
    ]
    n_skip = sum(1 for r in results if r is None)
    done   = [r for r in results if r is not None]   # numpy bools -> use truthiness
    n_pass = sum(1 for r in done if r)
    n_fail = sum(1 for r in done if not r)
    print(f'\nResults: {n_pass} passed, {n_fail} failed, {n_skip} skipped')
    sys.exit(1 if n_fail else 0)
