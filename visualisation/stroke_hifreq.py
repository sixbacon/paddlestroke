"""Quantify high-frequency roll content in padnormal vs padbad steady windows.

If padbad has extra energy above the fundamental stroke frequency, that explains
why the algorithm's peak/trough detector triggers 2-3 times per real stroke.
"""
import csv
import numpy as np
import matplotlib.pyplot as plt


def load(name):
    fn = f'visualisation/{name}20260711.csv'
    ts, roll, ax_, ay_, az_ = [], [], [], [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
                ax_.append(float(row['accel_x']))
                ay_.append(float(row['accel_y']))
                az_.append(float(row['accel_z']))
            except (ValueError, KeyError):
                pass
    return np.array(ts), np.array(roll), np.array(ax_), np.array(ay_), np.array(az_)


def hpf(x, fs, fc):
    """Simple 1-pole high-pass filter"""
    alpha = 1.0 / (1.0 + 2 * np.pi * fc / fs)
    y = np.zeros_like(x)
    prev = 0.0
    prev_x = x[0]
    for i in range(len(x)):
        y[i] = alpha * (prev + x[i] - prev_x)
        prev = y[i]
        prev_x = x[i]
    return y


def band_power(x, fs, lo, hi):
    w = np.hanning(len(x))
    F = np.fft.rfft((x - x.mean()) * w)
    freqs = np.fft.rfftfreq(len(x), d=1 / fs)
    P = np.abs(F) ** 2
    m = (freqs >= lo) & (freqs <= hi)
    return P[m].sum()


def count_extrema(x):
    """Count local maxima and minima."""
    dx = np.diff(x)
    sign = np.sign(dx)
    # zero-crossings of derivative = extrema
    zc = np.sum(np.abs(np.diff(sign)) > 0)
    return zc


fs = 100.0
# Use windows from the previous run
windows = {'padnormal': (2315.0, 30), 'padbad': (5145.0, 30)}

fig, axes = plt.subplots(3, 2, figsize=(14, 9))
for col, (name, (start_s, dur_s)) in enumerate(windows.items()):
    ts, roll, ax_, ay_, az_ = load(name)
    t0_ms = start_s * 1000
    i0 = np.searchsorted(ts, t0_ms)
    i1 = i0 + int(dur_s * fs)
    seg_r = roll[i0:i1]
    seg_t = (ts[i0:i1] - ts[i0]) / 1000.0

    seg_r0 = seg_r - seg_r.mean()

    # bandpower breakdown
    p_low = band_power(seg_r0, fs, 0.25, 1.0)    # fundamental
    p_mid = band_power(seg_r0, fs, 1.0, 2.5)     # 2nd/3rd harmonic
    p_hi  = band_power(seg_r0, fs, 2.5, 10.0)    # wobble/vibration
    total = p_low + p_mid + p_hi
    print(f'\n{name}:')
    print(f'  band power 0.25-1.0 Hz (stroke):  {p_low/total*100:5.1f}%')
    print(f'  band power 1.0-2.5 Hz (2f/3f):    {p_mid/total*100:5.1f}%')
    print(f'  band power 2.5-10 Hz (wobble):    {p_hi/total*100:5.1f}%')

    # Simulate the algorithm's high-pass and count extrema (approx of production code)
    # PadLog uses an EMA HPF — fc roughly 0.15 Hz. See StrokeDetector.
    r_hp = hpf(seg_r, fs, fc=0.15)
    n_ex = count_extrema(r_hp)
    print(f'  HPF(0.15 Hz) extrema in 30 s: {n_ex}  => implied CPM (2/cycle) = {n_ex/dur_s*30:.1f}')

    # Also compute peak-count using rolling max/min gates similar to production
    axes[0, col].plot(seg_t, seg_r, label='raw roll')
    axes[0, col].plot(seg_t, r_hp + seg_r.mean(), alpha=0.6, label='HPF(0.15Hz)')
    axes[0, col].set_title(f'{name} — raw vs HPF roll')
    axes[0, col].legend(fontsize=8); axes[0, col].grid(alpha=0.3)
    axes[0, col].set_ylabel('deg')

    # Derivative to show wobble
    d = np.diff(seg_r) * fs
    axes[1, col].plot(seg_t[:-1], d)
    axes[1, col].axhline(0, color='k', lw=0.5)
    axes[1, col].set_title(f'{name} — d(roll)/dt (deg/s)')
    axes[1, col].grid(alpha=0.3); axes[1, col].set_ylabel('deg/s')

    # Spectrum out to 10 Hz
    w = np.hanning(len(seg_r0))
    F = np.fft.rfft(seg_r0 * w)
    freqs = np.fft.rfftfreq(len(seg_r0), d=1 / fs)
    P = np.abs(F) ** 2
    m = (freqs >= 0.1) & (freqs <= 10.0)
    axes[2, col].semilogy(freqs[m], P[m])
    for f, lbl in [(0.5, '0.5'), (1.0, '1.0'), (1.5, '1.5'), (2.5, '2.5'), (5.0, '5.0')]:
        axes[2, col].axvline(f, color='r', ls=':', lw=0.5)
    axes[2, col].set_title(f'{name} — spectrum 0.1..10 Hz')
    axes[2, col].set_xlabel('Hz'); axes[2, col].set_ylabel('power'); axes[2, col].grid(alpha=0.3)

plt.tight_layout()
out = 'visualisation/stroke_hifreq.png'
plt.savefig(out, dpi=110)
print(f'\nsaved {out}')
