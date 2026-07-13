"""Compare true stroke rate (FFT peak of roll) vs reported CPM for the 11 Jul session files."""
import csv
import numpy as np

FILES = ['padcal', 'padnormal', 'padleft', 'padzero', 'padbad']


def load(name):
    fn = f'visualisation/{name}20260711.csv'
    ts, roll, cpm, sc = [], [], [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
                cpm.append(int(row['cpm']))
                sc.append(int(row['stroke_count']))
            except (ValueError, KeyError):
                pass
    return np.array(ts), np.array(roll), np.array(cpm), np.array(sc)


def spectral_rate(roll, fs=100.0, band=(0.25, 1.5)):
    x = roll - roll.mean()
    n = len(x)
    if n < 512:
        return 0.0
    w = np.hanning(n)
    F = np.fft.rfft(x * w)
    freqs = np.fft.rfftfreq(n, d=1 / fs)
    P = np.abs(F) ** 2
    m = (freqs >= band[0]) & (freqs <= band[1])
    if not m.any():
        return 0.0
    idx = np.argmax(P[m])
    return freqs[m][idx] * 60.0


def windowed_rates(ts, roll, win_s=60, step_s=30, fs=100.0):
    win = int(win_s * fs)
    step = int(step_s * fs)
    out = []
    for i in range(0, len(roll) - win, step):
        r = spectral_rate(roll[i:i + win], fs)
        t_mid = (ts[i] + ts[i + win - 1]) / 2000.0
        out.append((t_mid, r))
    return out


if __name__ == '__main__':
    header = f"{'file':10s}  {'dur':>5s}  {'global':>7s}  {'win_mean':>9s}  {'win_range':>14s}  {'rep_mean':>9s}  {'rep_range':>10s}"
    print(header)
    print('-' * len(header))
    for name in FILES:
        ts, roll, cpm, _ = load(name)
        fs = 1000.0 / np.median(np.diff(ts))
        global_rate = spectral_rate(roll, fs)
        wr = windowed_rates(ts, roll, 60, 30, fs)
        rates = [r for _, r in wr]
        nz = cpm[cpm > 0]
        rep_mean = float(nz.mean()) if len(nz) else 0.0
        rep_rng = f'{int(nz.min())}..{int(nz.max())}' if len(nz) else '-'
        tw_mean = np.mean(rates) if rates else 0
        tw_rng = f'{min(rates):.1f}..{max(rates):.1f}' if rates else '-'
        dur = (ts[-1] - ts[0]) / 1000
        print(f'{name:10s}  {dur:5.0f}  {global_rate:7.1f}  {tw_mean:9.1f}  {tw_rng:>14s}  {rep_mean:9.1f}  {rep_rng:>10s}')
