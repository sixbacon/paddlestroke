"""Prototype autocorrelation (ACF) CPM estimator for the 11 Jul session files.

Mirrors what PadLog firmware would do (spec 16.6 cross-check candidate):
  - downsample roll 100 Hz -> 10 Hz by 10-sample block average (anti-alias)
  - keep a 12 s ring buffer (120 samples, 480 B as float)
  - once per second: mean-remove, normalised ACF over lags 0.7-4.0 s,
    pick fundamental, refine with 3-point parabolic interpolation
  - quality gates: buffer >= 80% full, window std >= 10 deg, peak ACF >= 0.5
  - arbiter rule: flag when reported CPM disagrees with ACF CPM by > 30%

Run from repo root: python visualisation/stroke_acf.py
"""
import csv
import numpy as np

FILES = ['padcal', 'padnormal', 'padleft', 'padzero', 'padbad']

FS_IN        = 100.0   # CSV sample rate
DECIM        = 10      # 100 Hz -> 10 Hz
FS           = FS_IN / DECIM
WIN_S        = 12.0    # ring buffer length
LAG_MIN_S    = 0.7     # shortest period considered (86 CPM)
LAG_MAX_S    = 4.0     # longest period considered (15 CPM)
MIN_FILL     = 0.8     # buffer fill fraction before estimating
MIN_STD_DEG  = 10.0    # roll activity gate (substitute for amplitude gate)
MIN_ACF      = 0.5     # periodicity quality gate
FUND_FRAC    = 0.75    # local maxima within this fraction of global max
                       # are fundamental candidates; smallest lag wins
ZERO_HILL    = 0.30    # search for peaks only after ACF first drops below
                       # this: smooth signals correlate trivially at short
                       # lags, pinning naive argmax to the lag_lo boundary
DISAGREE     = 0.30    # arbiter threshold: |rep - acf| / acf


def load(name):
    fn = 'visualisation/{}20260711.csv'.format(name)
    ts, roll, cpm = [], [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
                cpm.append(int(row['cpm']))
            except (ValueError, KeyError):
                pass
    return np.array(ts), np.array(roll), np.array(cpm)


def acf_estimate(win):
    """One CPM estimate from a window of 10 Hz roll samples.

    Returns (cpm, quality) -- cpm 0.0 when no reliable estimate.
    Pure loops + one normalised dot product per lag: ports directly to C++.
    """
    x = win - win.mean()
    if x.std() < MIN_STD_DEG:
        return 0.0, 0.0

    n = len(x)
    lag_lo = int(round(LAG_MIN_S * FS))
    lag_hi = int(round(LAG_MAX_S * FS))
    lag_hi = min(lag_hi, n - 4)   # keep some overlap

    r = np.zeros(lag_hi + 1)
    for lag in range(1, lag_hi + 1):
        a = x[:n - lag]
        b = x[lag:]
        denom = np.sqrt(np.dot(a, a) * np.dot(b, b))
        r[lag] = np.dot(a, b) / denom if denom > 0 else 0.0

    # Skip the zero-lag correlation hill: peaks are only meaningful after
    # the ACF has first decorrelated. If it never drops the window has no
    # oscillation at all (slow manoeuvring) -- report nothing.
    start = 1
    while start <= lag_hi and r[start] > ZERO_HILL:
        start += 1
    if start > lag_hi:
        return 0.0, 0.0
    start = max(start, lag_lo)

    seg = r[start:lag_hi + 1]
    if len(seg) < 3:
        return 0.0, 0.0
    rmax = seg.max()
    if rmax < MIN_ACF:
        return 0.0, rmax

    # Fundamental pick: smallest-lag local maximum within FUND_FRAC of the
    # global max. For an asymmetric (feathered) waveform the half-period lag
    # correlates weakly, so this lands on the full period. For a symmetric
    # (zero-feather) waveform the half period genuinely dominates -- roll
    # alone cannot disambiguate that case (documented limitation).
    best = 0
    for lag in range(start + 1, lag_hi):
        if r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1] and r[lag] >= FUND_FRAC * rmax:
            best = lag
            break
    if best == 0:
        best = start + int(np.argmax(seg))

    # 3-point parabolic interpolation for sub-lag period precision
    if start < best < lag_hi:
        y0, y1, y2 = r[best - 1], r[best], r[best + 1]
        denom = y0 - 2 * y1 + y2
        delta = 0.5 * (y0 - y2) / denom if abs(denom) > 1e-12 else 0.0
        delta = max(-0.5, min(0.5, delta))
    else:
        delta = 0.0

    period_s = (best + delta) / FS
    return 60.0 / period_s, r[best]


def stream(ts, roll, cpm):
    """Simulate the firmware loop: fill ring buffer, estimate once per second.

    Returns list of (t_s, acf_cpm, quality, reported_cpm)."""
    n_ds = len(roll) // DECIM
    ds = roll[:n_ds * DECIM].reshape(n_ds, DECIM).mean(axis=1)
    ts_ds = ts[:n_ds * DECIM:DECIM]

    buf_len = int(WIN_S * FS)
    out = []
    step = int(FS)   # one estimate per second
    for i in range(step, n_ds, step):
        lo = max(0, i - buf_len)
        win = ds[lo:i]
        if len(win) < MIN_FILL * buf_len:
            continue
        est, q = acf_estimate(win)
        rep = cpm[min(i * DECIM, len(cpm) - 1)]
        out.append(((ts_ds[i - 1] - ts[0]) / 1000.0, est, q, rep))
    return out


def main():
    hdr = ('{:10s}  {:>5s}  {:>8s}  {:>12s}  {:>6s}  {:>8s}  {:>6s}  {:>7s}'
           .format('file', 'dur', 'acf_med', 'acf_10-90pct',
                   'valid%', 'rep_mean', 'flag%', 'first_s'))
    print(hdr)
    print('-' * len(hdr))

    for name in FILES:
        ts, roll, cpm = load(name)
        est = stream(ts, roll, cpm)
        acf = np.array([e for _, e, _, _ in est])
        rep = np.array([r for _, _, _, r in est], dtype=float)
        t = np.array([t0 for t0, _, _, _ in est])

        valid = acf > 0
        acf_v = acf[valid]
        # arbiter: both sides reporting, and they disagree by > 30%
        both = valid & (rep > 0)
        flags = np.abs(rep[both] - acf[both]) / acf[both] > DISAGREE
        first = t[valid][0] if valid.any() else -1.0

        dur = (ts[-1] - ts[0]) / 1000.0
        med = np.median(acf_v) if len(acf_v) else 0.0
        p10 = np.percentile(acf_v, 10) if len(acf_v) else 0.0
        p90 = np.percentile(acf_v, 90) if len(acf_v) else 0.0
        rep_nz = rep[rep > 0]
        rep_mean = rep_nz.mean() if len(rep_nz) else 0.0
        flag_pct = 100.0 * flags.mean() if both.any() else 0.0

        print('{:10s}  {:5.0f}  {:8.1f}  {:>12s}  {:5.0f}%  {:8.1f}  {:5.0f}%  {:7.1f}'
              .format(name, dur, med,
                      '{:.1f}..{:.1f}'.format(p10, p90),
                      100.0 * valid.mean(), rep_mean, flag_pct, first))


if __name__ == '__main__':
    main()
