"""Per-segment verification of a field session against spec 16.8.

For each notes-defined segment: spectral ground-truth CPM, reported CPM
stats, ACF cross-check + arbiter flag rate, and time-to-correct-CPM from
segment start (16.8 recovery criterion, pass = within +/-3 CPM inside ~15 s).

Segments below are the 13 Jul 2026 session (notes20260713.txt); edit for
future sessions. Line numbers are 1-based CSV file lines (line 1 = comment,
line 2 = header, so data row = line - 3).

Run from repo root: python visualisation/stroke_field_verify.py
"""
import csv
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stroke_acf import acf_estimate, stream, DISAGREE          # noqa: E402
from stroke_spectral import spectral_rate, windowed_rates      # noqa: E402

FILE = 'visualisation/PadLog20260713.CSV'

# (name, first_line, last_line) from notes20260713.txt
SEGMENTS = [
    ('right1', 55150, 85330),
    ('left',   95100, 119000),
    ('zero',   128000, 154000),
    ('right2', 164000, 189100),
]

TOL_CPM = 3.0   # spec 16.8 recovery tolerance


def load(fn):
    ts, roll, cpm = [], [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
                cpm.append(float(row['cpm']))
            except (ValueError, KeyError):
                pass
    return np.array(ts), np.array(roll), np.array(cpm)


def recovery_time_s(ts, cpm, true_cpm):
    """Seconds from segment start until reported CPM first sits within
    TOL_CPM of truth (and is non-zero). -1 if never."""
    ok = (cpm > 0) & (np.abs(cpm - true_cpm) <= TOL_CPM)
    idx = np.argmax(ok) if ok.any() else -1
    return (ts[idx] - ts[0]) / 1000.0 if idx >= 0 else -1.0


def main():
    ts, roll, cpm = load(FILE)
    print(f'{FILE}: {len(ts)} rows, {(ts[-1] - ts[0]) / 1000.0:.0f} s span')

    hdr = (f"{'segment':8s}  {'dur':>5s}  {'true':>6s}  {'win_range':>12s}  "
           f"{'rep%>0':>6s}  {'rep_med':>7s}  {'|err|med':>8s}  "
           f"{'acf_med':>7s}  {'flag%':>5s}  {'recover_s':>9s}")
    print(hdr)
    print('-' * len(hdr))

    for name, lo_line, hi_line in SEGMENTS:
        lo, hi = lo_line - 3, hi_line - 3
        t, r, c = ts[lo:hi], roll[lo:hi], cpm[lo:hi]
        fs = 1000.0 / np.median(np.diff(t))
        dur = (t[-1] - t[0]) / 1000.0

        true = spectral_rate(r, fs)
        wr = [x for _, x in windowed_rates(t, r, 60, 30, fs)]
        wrng = f'{min(wr):.1f}..{max(wr):.1f}' if wr else '-'

        nz = c[c > 0]
        rep_pct = 100.0 * len(nz) / len(c)
        rep_med = np.median(nz) if len(nz) else 0.0
        err_med = np.median(np.abs(nz - true)) if len(nz) else -1.0

        est = stream(t, r, c)
        acf = np.array([e for _, e, _, _ in est])
        rep_s = np.array([x for _, _, _, x in est], dtype=float)
        valid = acf > 0
        both = valid & (rep_s > 0)
        flags = (np.abs(rep_s[both] - acf[both]) / acf[both] > DISAGREE)
        acf_med = np.median(acf[valid]) if valid.any() else 0.0
        flag_pct = 100.0 * flags.mean() if both.any() else 0.0

        rec = recovery_time_s(t, c, true)
        print(f'{name:8s}  {dur:5.0f}  {true:6.1f}  {wrng:>12s}  '
              f'{rep_pct:5.0f}%  {rep_med:7.1f}  {err_med:8.1f}  '
              f'{acf_med:7.1f}  {flag_pct:4.0f}%  {rec:9.1f}')


if __name__ == '__main__':
    main()
