"""Phase 9 feasibility: detect blade entry (catch) / exit (release) from
field data (spec 13.5; first run on the 16 Jul 2026 right1 segment).

Ensemble-averages candidate impact signals over stroke cycles:
  - high-frequency (8-30 Hz) paddle accel envelope  (impact 'thud')
  - jerk magnitude (d|a|/dt)
  - world-frame vertical linear accel of shaft centre
  - boat surge (boat_accel_y, high-passed), synced via rx_ms
  - blade-tip heights from orientation (shaft = sensor X axis, +/-1.05 m)
Cycles segmented by low-passed roll peaks (side A) and troughs (side B).
Writes catch_ensemble.png / catch_strip.png / tip_height.png next to this
script. Run from repo root: python visualisation/stroke_catch_explore.py
"""
import csv
import os
import sys

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
FS = 100.0

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

def fft_band(x, fs, f1, f2):
    """Brickwall band-pass via FFT (offline use only)."""
    X = np.fft.rfft(x - x.mean())
    f = np.fft.rfftfreq(len(x), 1 / fs)
    X[(f < f1) | (f > f2)] = 0
    return np.fft.irfft(X, len(x))

def envelope(x, fs, win_s=0.05):
    n = max(1, int(win_s * fs))
    k = np.ones(n) / n
    return np.sqrt(np.convolve(x * x, k, mode='same'))

def find_extrema(lp, min_sep, thresh):
    """Indices of local maxima of lp above thresh, separated by min_sep."""
    idx = []
    i = 1
    while i < len(lp) - 1:
        if lp[i] >= lp[i - 1] and lp[i] >= lp[i + 1] and lp[i] > thresh:
            if idx and i - idx[-1] < min_sep:
                if lp[i] > lp[idx[-1]]:
                    idx[-1] = i
            else:
                idx.append(i)
        i += 1
    return np.array(idx)

# ---------- segment selection ----------
# (first_line, last_line, anchor_channel, extremum_threshold_deg)
# Zero feather must anchor on PITCH: roll is half-period ambiguous there
# (spec 16.10), so roll extrema come at stroke rate, not cycle rate.
SEGMENTS = {
    'right1': (3548, 25542, 'roll', 30.0),
    'left':   (29548, 36146, 'roll', 30.0),
    'zero':   (40252, 45369, 'pitch', 15.0),
    'right2': (48110, 60533, 'roll', 30.0),
}
seg = sys.argv[1] if len(sys.argv) > 1 else 'right1'
lo_line, hi_line, anchor_ch, thresh = SEGMENTS[seg]

p = load(os.path.join(REPO, 'visualisation', 'PadLog20260716.csv'),
         ['timestamp_ms', 'accel_x', 'accel_y', 'accel_z', 'roll', 'pitch',
          'q_w', 'q_x', 'q_y', 'q_z', 'rx_ms'])
lo, hi = lo_line - 3, hi_line - 3
sl = slice(lo, hi)
t = p['timestamp_ms'][sl] / 1000.0
ax, ay, az = p['accel_x'][sl], p['accel_y'][sl], p['accel_z'][sl]
roll, pitch = p['roll'][sl], p['pitch'][sl]
q = np.stack([p['q_w'], p['q_x'], p['q_y'], p['q_z']], 1)[sl]
rx = p['rx_ms'][sl]

b = load(os.path.join(REPO, 'visualisation', 'BoatLog20260716.csv'),
         ['rx_ms', 'boat_accel_x', 'boat_accel_y', 'boat_accel_z'])

# ---------- candidate signals ----------
amag = np.sqrt(ax * ax + ay * ay + az * az)
hif = envelope(fft_band(amag, FS, 8, 30), FS)          # impact band envelope
jerk = np.abs(np.gradient(amag, 1 / FS))
jerk = np.convolve(jerk, np.ones(5) / 5, mode='same')

# world vertical linear accel: v_w = q (x) a (x) q*
w_, x_, y_, z_ = q.T
# rotate body vector a by quat (vectorised rotation matrix rows for z only)
# world_z component of rotated a:
r20 = 2 * (x_ * z_ - w_ * y_)
r21 = 2 * (y_ * z_ + w_ * x_)
r22 = 1 - 2 * (x_ * x_ + y_ * y_)
a_wz = r20 * ax + r21 * ay + r22 * az - 9.80665

# boat surge resampled to paddle rx timeline
order = np.argsort(b['rx_ms'])
brx = b['rx_ms'][order]
surge_raw = b['boat_accel_y'][order]
surge_b = fft_band(surge_raw, FS, 0.3, 5.0)
surge = np.interp(rx, brx, surge_b)

# ---------- cycle segmentation ----------
anchor_sig = roll if anchor_ch == 'roll' else pitch
lp = fft_band(anchor_sig, FS, 0.2, 2.0)
peaks = find_extrema(lp, int(1.0 * FS), thresh)
troughs = find_extrema(-lp, int(1.0 * FS), thresh)
print(f'{seg}: {len(peaks)} {anchor_ch} peaks, {len(troughs)} troughs, '
      f'{ (t[-1]-t[0])/60:.1f} min')

def ensemble(sig, anchors, nb=200):
    """Resample sig between consecutive anchors to nb phase bins."""
    rows = []
    for i in range(len(anchors) - 1):
        a0, a1 = anchors[i], anchors[i + 1]
        if not (0.8 * FS < a1 - a0 < 3.0 * FS):
            continue
        ph = np.linspace(a0, a1, nb)
        rows.append(np.interp(ph, np.arange(len(sig)), sig))
    return np.array(rows)

signals = [('HF 8-30 Hz envelope (m/s^2)', hif),
           ('jerk |d|a||/dt (m/s^3)', jerk),
           ('world vertical lin. accel (m/s^2)', a_wz),
           ('boat surge (m/s^2)', surge)]

fig, axes = plt.subplots(len(signals) + 1, 2, figsize=(13, 12), sharex='col')
fig.suptitle(f'{seg} segment - stroke-phase ensembles (peak-anchored = side A, '
             'trough-anchored = side B)', fontsize=11)

for col, anchors in enumerate((peaks, troughs)):
    ens_roll = ensemble(lp, anchors)
    phx = np.linspace(0, 1, 200)
    axq = axes[0, col]
    md = np.median(ens_roll, 0)
    axq.plot(phx, md, 'k')
    axq.set_ylabel(f'{anchor_ch} (deg)' if col == 0 else '')
    axq.set_title(f'{"side A (" + anchor_ch + " peak)" if col==0 else "side B (" + anchor_ch + " trough)"} '
                  f'n={len(ens_roll)}')
    for rown, (name, sig) in enumerate(signals, start=1):
        ens = ensemble(sig, anchors)
        md = np.median(ens, 0)
        q25, q75 = np.percentile(ens, 25, 0), np.percentile(ens, 75, 0)
        axp = axes[rown, col]
        axp.fill_between(phx, q25, q75, alpha=0.3)
        axp.plot(phx, md)
        if col == 0:
            axp.set_ylabel(name, fontsize=8)
axes[-1, 0].set_xlabel(f'stroke phase (0 = {anchor_ch} peak)')
axes[-1, 1].set_xlabel(f'stroke phase (0 = {anchor_ch} trough)')
plt.tight_layout()
out = os.path.join(HERE, f'catch_ensemble_{seg}.png')
plt.savefig(out, dpi=110)
print('wrote', out)

# ---------- timing sharpness of the HF envelope events ----------
for name, anchors in (('side A', peaks), ('side B', troughs)):
    ens = ensemble(hif, anchors)
    if not len(ens):
        continue
    md = np.median(ens, 0)
    # locate up to two dominant bumps in the median profile
    pk_bins = find_extrema(md, 20, md.mean() + 0.5 * md.std())
    per_cycle_jitter = []
    for pb in pk_bins[:4]:
        wlo, whi = max(0, pb - 25), min(200, pb + 25)
        locs = np.argmax(ens[:, wlo:whi], axis=1) + wlo
        per_cycle_jitter.append((pb / 200, np.std(locs) / 200))
    period = np.median(np.diff(anchors)) / FS
    print(f'{name}: cycle {period:.2f}s | HF bumps at phase ' +
          ', '.join(f'{ph:.2f} (jitter +/-{j*period*1000:.0f} ms)'
                    for ph, j in per_cycle_jitter))

# ---------- raw 12 s example strip for the plot's sanity ----------
fig2, ax2 = plt.subplots(3, 1, figsize=(13, 7), sharex=True)
w0 = min(int(60 * FS), max(0, len(t) - int(12 * FS)))
w1 = min(w0 + int(12 * FS), len(t))
tt = t[w0:w1] - t[w0]
ax2[0].plot(tt, roll[w0:w1], 'k', lw=0.8); ax2[0].set_ylabel('roll deg')
ax2[1].plot(tt, hif[w0:w1], 'r', lw=0.8); ax2[1].set_ylabel('HF env')
ax2[2].plot(tt, surge[w0:w1], 'b', lw=0.8); ax2[2].set_ylabel('boat surge')
ax2[2].set_xlabel('s')
out2 = os.path.join(HERE, f'catch_strip_{seg}.png')
plt.tight_layout(); plt.savefig(out2, dpi=110)
print('wrote', out2)

# ---------- blade-tip height vs stroke phase, HF bumps overlaid ----------
# world-z component of the shaft direction (body X axis): R[2,0] = 2(xz - wy)
L = 1.05  # m, shaft centre to blade centre
uz = 2 * (x_ * z_ - w_ * y_)
e_tip = ensemble(uz, peaks) * L
e_hf = ensemble(hif, peaks)
e_rl = ensemble(lp, peaks)
phx = np.linspace(0, 1, 200)
md_tip = np.median(e_tip, 0)

fig3, ax3 = plt.subplots(3, 1, figsize=(12, 8), sharex=True)
ax3[0].plot(phx, np.median(e_rl, 0), 'k'); ax3[0].set_ylabel(f'{anchor_ch} deg')
ax3[1].plot(phx, md_tip, 'g', label='blade end +X')
ax3[1].plot(phx, -md_tip, 'm', label='blade end -X')
ax3[1].axhline(0, color='grey', lw=0.5)
ax3[1].set_ylabel('tip height rel. shaft centre (m)')
ax3[1].legend(fontsize=8)
ax3[2].plot(phx, np.median(e_hf, 0), 'r'); ax3[2].set_ylabel('HF 8-30 Hz env')
ax3[2].set_xlabel(f'stroke phase (0 = {anchor_ch} peak)')
plt.tight_layout()
out3 = os.path.join(HERE, f'tip_height_{seg}.png')
plt.savefig(out3, dpi=110)
print('wrote', out3)
