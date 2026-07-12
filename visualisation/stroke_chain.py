"""Chain padzero -> padbad through the detector, preserving state.

If firmware state-carryover from Part 3 is the true cause of padbad's 87 CPM,
running padzero followed by padbad through a single detector instance should
reproduce the firmware's 87 CPM on the padbad portion.
"""
import csv
import numpy as np
from stroke_detector_sim import StrokeDetector, load_csv


def run_chained(files, prom_deg=0.0, prom_win_s=0.0):
    d = StrokeDetector(prominence_deg=prom_deg, prominence_win_s=prom_win_s)
    all_cpm = []
    boundaries = [0]
    ts_all = []
    for name in files:
        ts, roll = load_csv(name)
        for i in range(len(roll)):
            d.update(float(roll[i]), int(ts[i]) * 1000)
            all_cpm.append(d.rate_hz * 60.0)
            ts_all.append(int(ts[i]))
        boundaries.append(len(all_cpm))
    return np.array(all_cpm), boundaries, np.array(ts_all), files


def summarise_range(name, cpm, lo, hi):
    seg = cpm[lo:hi]
    nz = seg[seg > 0]
    if len(nz) == 0:
        return f'{name}: no output'
    return f'{name}: mean={nz.mean():5.1f}  median={np.median(nz):5.1f}  min={nz.min():5.1f}  max={nz.max():5.1f}  n={len(nz)}'


if __name__ == '__main__':
    # Fresh replay of just padbad
    ts_b, roll_b = load_csv('padbad')
    d = StrokeDetector()
    cpm_fresh = []
    for i in range(len(roll_b)):
        d.update(float(roll_b[i]), int(ts_b[i]) * 1000)
        cpm_fresh.append(d.rate_hz * 60.0)
    cpm_fresh = np.array(cpm_fresh)

    # Chained: padzero then padbad
    cpm_chain, bounds, ts_all, files = run_chained(['padzero', 'padbad'])
    print(f'chain files: {files}')
    print(f'boundaries: {bounds}')

    print()
    print(summarise_range('fresh padbad only          ', cpm_fresh, 0, len(cpm_fresh)))
    print(summarise_range('chained padzero segment    ', cpm_chain, bounds[0], bounds[1]))
    print(summarise_range('chained padbad segment     ', cpm_chain, bounds[1], bounds[2]))
    # First 60 s of chained padbad
    dur_s = 60
    n60 = int(dur_s * 100)
    print(summarise_range('chained padbad first  60 s ', cpm_chain, bounds[1], bounds[1] + n60))
    print(summarise_range('chained padbad first 120 s ', cpm_chain, bounds[1], bounds[1] + 2 * n60))
