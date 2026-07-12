"""Compare padnormal (good) vs padbad (3x over-count) roll waveforms and spectra."""
import csv
import numpy as np
import matplotlib.pyplot as plt


def load(name):
    fn = f'visualisation/{name}20260711.csv'
    ts, roll, pitch, cpm, sc, mc, accx, accy = [], [], [], [], [], [], [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
                pitch.append(float(row['pitch']))
                cpm.append(int(row['cpm']))
                sc.append(int(row['stroke_count']))
                mc.append(int(row['mag_cal']))
                accx.append(float(row['accel_x']))
                accy.append(float(row['accel_y']))
            except (ValueError, KeyError):
                pass
    return (np.array(ts), np.array(roll), np.array(pitch), np.array(cpm),
            np.array(sc), np.array(mc), np.array(accx), np.array(accy))


def steady_window(ts, roll, cpm, target_cpm=30, tol=8, win_s=30, fs=100.0):
    """Find a window where reported cpm is close to target_cpm and stable."""
    win = int(win_s * fs)
    best_i = None
    best_score = 1e9
    step = int(2 * fs)
    for i in range(0, len(roll) - win, step):
        c = cpm[i:i + win]
        nz = c[c > 0]
        if len(nz) < win * 0.5:
            continue
        mean = nz.mean()
        std = nz.std()
        score = abs(mean - target_cpm) + std
        if score < best_score:
            best_score = score
            best_i = i
    return best_i


def zero_crossings(x):
    return int(np.sum((x[:-1] * x[1:]) < 0))


files = ['padnormal', 'padbad']
fs = 100.0
win_s = 30
target_cpm = 30

fig, axes = plt.subplots(len(files), 2, figsize=(14, 6))
for row, name in enumerate(files):
    ts, roll, pitch, cpm, sc, mc, ax_, ay_ = load(name)
    i = steady_window(ts, roll, cpm, target_cpm=target_cpm, win_s=win_s, fs=fs)
    if i is None:
        # fallback: middle of file
        i = len(roll) // 2
    win = int(win_s * fs)
    seg_r = roll[i:i + win]
    seg_p = pitch[i:i + win]
    seg_t = (ts[i:i + win] - ts[i]) / 1000.0
    seg_cpm = cpm[i:i + win]
    seg_mc = mc[i:i + win]
    seg_r0 = seg_r - seg_r.mean()

    # zero crossings of demeaned raw roll
    zc = zero_crossings(seg_r0)
    # spectral peak on this window
    w = np.hanning(len(seg_r0))
    F = np.fft.rfft(seg_r0 * w)
    freqs = np.fft.rfftfreq(len(seg_r0), d=1 / fs)
    P = np.abs(F) ** 2
    m = (freqs >= 0.25) & (freqs <= 3.0)
    fpk = freqs[m][np.argmax(P[m])]

    print(f'{name}: window t={ts[i]/1000:.1f}s..{ts[i+win-1]/1000:.1f}s  '
          f'mag_cal={seg_mc[0]}..{seg_mc[-1]}  reported_cpm mean={seg_cpm[seg_cpm>0].mean():.1f}  '
          f'roll_span={seg_r.max()-seg_r.min():.1f}  demeaned_zc={zc} (=> {zc/win_s*30:.1f} CPM if 2 zc per cycle)  '
          f'spectral_peak={fpk*60:.1f} CPM  '
          f'harmonic_ratio 2f/f = {P[m][np.argmin(np.abs(freqs[m]-2*fpk))]/P[m].max():.2f}')

    axes[row, 0].plot(seg_t, seg_r, label='roll')
    axes[row, 0].plot(seg_t, seg_p, alpha=0.5, label='pitch')
    axes[row, 0].axhline(seg_r.mean(), color='k', ls='--', lw=0.5)
    axes[row, 0].set_title(f'{name} — roll & pitch (30 s, reported {seg_cpm[seg_cpm>0].mean():.0f} CPM)')
    axes[row, 0].set_xlabel('time (s)'); axes[row, 0].set_ylabel('deg')
    axes[row, 0].legend(loc='upper right', fontsize=8)
    axes[row, 0].grid(alpha=0.3)

    # spectrum plot 0..3 Hz
    axes[row, 1].semilogy(freqs[m], P[m])
    axes[row, 1].axvline(0.5, color='g', ls=':', lw=0.5, label='0.5 Hz (30 CPM)')
    axes[row, 1].axvline(1.0, color='orange', ls=':', lw=0.5, label='1.0 Hz (60 CPM)')
    axes[row, 1].axvline(1.5, color='r', ls=':', lw=0.5, label='1.5 Hz (90 CPM)')
    axes[row, 1].set_title(f'{name} — spectrum (peak {fpk*60:.1f} CPM)')
    axes[row, 1].set_xlabel('Hz'); axes[row, 1].set_ylabel('power')
    axes[row, 1].legend(fontsize=8)
    axes[row, 1].grid(alpha=0.3)

plt.tight_layout()
out = 'visualisation/stroke_compare.png'
plt.savefig(out, dpi=110)
print(f'\nsaved {out}')
