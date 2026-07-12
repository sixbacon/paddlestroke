"""Python port of PadLog StrokeDetector.cpp, run against padbad roll.

Baseline: match the firmware algorithm exactly and confirm ~87 CPM output.
Fix A: prominence gate — peak must be N° above running min of last W ms (and vice versa).
Fix B: low-pass pre-filter — 1-pole Butterworth at various fc.
Fix C: both.

Report reported-CPM statistics for each variant so we can pick the best fix.
"""
import csv
import numpy as np


PERIOD_MIN_S = 0.4
PERIOD_MAX_S = 4.0
MIN_EXTREMA_INTERVAL_S = 0.2
AMPLITUDE_GATE_DEG = 90.0
DC_ALPHA = 0.002


class StrokeDetector:
    """1:1 port of firmware/production/PadLog/StrokeDetector.cpp,
    plus optional 'prominence-since-last-same-type-extremum' gate.

    Prominence gate rationale: the production algorithm's amplitude check compares
    a new peak against the last accepted trough (which may be seconds ago). A
    small notch at the top of a real stroke can create a phantom local maximum
    that still clears the 90 deg gate. Requiring the signal to have descended by
    prom_deg since the last accepted peak (or ascended by prom_deg since the last
    accepted trough) rejects such shoulder wiggles without adding a fixed time
    window, so it works across the full 0.25-2.5 Hz operational range.
    """

    def __init__(self, prominence_deg=0.0, prominence_win_s=0.0):
        # prominence_win_s retained for API compatibility; only prominence_deg is
        # used by the since-last-same-type gate.
        self.prom_deg = prominence_deg

        self.in_buf = [0.0, 0.0, 0.0]
        self.in_fill = 0

        self.dc_offset = 0.0
        self.dc_initialized = False

        self.prev2 = self.prev1 = self.curr = 0.0
        self.samples_seen = 0
        self.prev_ts = 0

        self.last_peak_val = 0.0
        self.last_peak_ts = 0
        self.has_peak = False
        self.last_trough_val = 0.0
        self.last_trough_ts = 0
        self.has_trough = False

        self.rbP = [0.0] * 4
        self.rbT = [0.0] * 4
        self.rbPc = 0
        self.rbPh = 0
        self.rbTc = 0
        self.rbTh = 0

        self.last_qual_ts = 0
        self.rate_hz = 0.0

        # Running min-since-last-accepted-peak and max-since-last-accepted-trough,
        # used by the prominence gate.
        self.min_since_peak = 0.0
        self.max_since_trough = 0.0

    def update(self, roll_deg, ts_us):
        # 3-sample moving average
        self.in_buf[2] = self.in_buf[1]
        self.in_buf[1] = self.in_buf[0]
        self.in_buf[0] = roll_deg
        if self.in_fill < 3:
            self.in_fill += 1
        roll_deg = sum(self.in_buf[:self.in_fill]) / self.in_fill

        # EMA HPF
        if not self.dc_initialized:
            self.dc_offset = roll_deg
            self.dc_initialized = True
        else:
            self.dc_offset += DC_ALPHA * (roll_deg - self.dc_offset)
        roll_deg -= self.dc_offset

        # Track excursion since last accepted extremum (for prominence gate).
        if self.has_peak and roll_deg < self.min_since_peak:
            self.min_since_peak = roll_deg
        if self.has_trough and roll_deg > self.max_since_trough:
            self.max_since_trough = roll_deg

        candidate_ts = self.prev_ts
        self.prev2 = self.prev1
        self.prev1 = self.curr
        self.curr = roll_deg
        self.prev_ts = ts_us

        if self.samples_seen < 3:
            self.samples_seen += 1
            return False
        if self.samples_seen < 3:
            return False

        if self.prev2 < self.prev1 >= self.curr:
            return self._on_extrema(True, self.prev1, candidate_ts)
        if self.prev2 > self.prev1 <= self.curr:
            return self._on_extrema(False, self.prev1, candidate_ts)
        return False

    def _prominence_ok(self, is_peak, val):
        if self.prom_deg <= 0:
            return True
        if is_peak:
            # Peak must be prom_deg above the min the signal reached since the
            # last accepted peak. Blocks shoulder wiggles that never actually
            # descend.
            if not self.has_peak:
                return True  # first peak — nothing to compare against
            return (val - self.min_since_peak) >= self.prom_deg
        else:
            if not self.has_trough:
                return True
            return (self.max_since_trough - val) >= self.prom_deg

    def _on_extrema(self, is_peak, val, ts_us):
        qualified = False
        if is_peak:
            if self.has_peak and (ts_us - self.last_peak_ts) < MIN_EXTREMA_INTERVAL_S * 1e6:
                return False
            if not self._prominence_ok(True, val):
                return False
            if not self.has_trough:
                self.last_peak_val = val
                self.last_peak_ts = ts_us
                self.has_peak = True
                return False
            amp = val - self.last_trough_val
            if amp < AMPLITUDE_GATE_DEG:
                return False
            if self.has_peak:
                period_s = (ts_us - self.last_peak_ts) / 1e6
                if PERIOD_MIN_S <= period_s <= PERIOD_MAX_S:
                    self._push_rate(1.0 / period_s, True)
                    self._compute_avg()
                    self.last_qual_ts = ts_us
                    qualified = True
            self.last_peak_val = val
            self.last_peak_ts = ts_us
            self.has_peak = True
            self.min_since_peak = val  # reset tracker for next peak's prominence check
        else:
            if self.has_trough and (ts_us - self.last_trough_ts) < MIN_EXTREMA_INTERVAL_S * 1e6:
                return False
            if not self._prominence_ok(False, val):
                return False
            if not self.has_peak:
                self.last_trough_val = val
                self.last_trough_ts = ts_us
                self.has_trough = True
                return False
            amp = self.last_peak_val - val
            if amp < AMPLITUDE_GATE_DEG:
                return False
            if self.has_trough:
                period_s = (ts_us - self.last_trough_ts) / 1e6
                if PERIOD_MIN_S <= period_s <= PERIOD_MAX_S:
                    self._push_rate(1.0 / period_s, False)
                    self._compute_avg()
                    self.last_qual_ts = ts_us
                    qualified = True
            self.last_trough_val = val
            self.last_trough_ts = ts_us
            self.has_trough = True
            self.max_since_trough = val
        return qualified

    def _push_rate(self, rate_hz, is_peak):
        if is_peak:
            self.rbP[self.rbPh] = rate_hz
            self.rbPh = (self.rbPh + 1) % 4
            if self.rbPc < 4:
                self.rbPc += 1
        else:
            self.rbT[self.rbTh] = rate_hz
            self.rbTh = (self.rbTh + 1) % 4
            if self.rbTc < 4:
                self.rbTc += 1

    def _compute_avg(self):
        s = 0.0
        n = 0
        for i in range(self.rbPc):
            s += self.rbP[i]; n += 1
        for i in range(self.rbTc):
            s += self.rbT[i]; n += 1
        self.rate_hz = s / n if n > 0 else 0.0


def load_csv(name):
    fn = f'visualisation/{name}20260711.csv'
    ts, roll = [], []
    with open(fn, encoding='utf-8-sig') as f:
        f.readline()
        r = csv.DictReader(f)
        for row in r:
            try:
                ts.append(int(row['timestamp_ms']))
                roll.append(float(row['roll']))
            except (ValueError, KeyError):
                pass
    return np.array(ts), np.array(roll)


def lpf(x, fs, fc):
    """1-pole IIR low-pass filter."""
    alpha = 2 * np.pi * fc / (2 * np.pi * fc + fs)
    y = np.zeros_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = y[i-1] + alpha * (x[i] - y[i-1])
    return y


def run_detector(ts_ms, roll, prom_deg=0.0, prom_win_s=0.0, log_events=False):
    d = StrokeDetector(prominence_deg=prom_deg, prominence_win_s=prom_win_s)
    cpm_series = []
    events = []
    for i in range(len(roll)):
        qual = d.update(float(roll[i]), int(ts_ms[i]) * 1000)
        cpm = d.rate_hz * 60.0
        cpm_series.append(cpm)
        if qual and log_events:
            events.append(int(ts_ms[i]))
    return np.array(cpm_series), events


def summarise(name, cpm_series, ts_ms, skip_s=60):
    # skip startup so we don't average during buffer fill
    t0 = ts_ms[0] + skip_s * 1000
    mask = (ts_ms >= t0) & (cpm_series > 0)
    if not mask.any():
        return f'{name}: no qualifying output'
    nz = cpm_series[mask]
    return f'{name}: mean={nz.mean():.1f}  median={np.median(nz):.1f}  min={nz.min():.1f}  max={nz.max():.1f}  n={len(nz)}'


if __name__ == '__main__':
    ts, roll = load_csv('padbad')
    fs = 1000.0 / np.median(np.diff(ts))
    print(f'padbad loaded: {len(roll)} samples, fs~{fs:.1f} Hz\n')
    print('True rate (spectral peak): ~30 CPM\n')

    variants = [
        ('baseline (production algorithm)',    roll, 0.0, 0.0),
        ('Fix A: prominence 20°, window 300ms', roll, 20.0, 0.3),
        ('Fix A: prominence 30°, window 300ms', roll, 30.0, 0.3),
        ('Fix A: prominence 40°, window 300ms', roll, 40.0, 0.3),
        ('Fix A: prominence 30°, window 500ms', roll, 30.0, 0.5),
        ('Fix B: LPF fc=2.0 Hz',                lpf(roll, fs, 2.0), 0.0, 0.0),
        ('Fix B: LPF fc=1.5 Hz',                lpf(roll, fs, 1.5), 0.0, 0.0),
        ('Fix B: LPF fc=1.0 Hz',                lpf(roll, fs, 1.0), 0.0, 0.0),
        ('Fix C: LPF 2Hz + prominence 30°/300ms', lpf(roll, fs, 2.0), 30.0, 0.3),
        ('Fix C: LPF 1.5Hz + prominence 30°/300ms', lpf(roll, fs, 1.5), 30.0, 0.3),
    ]

    for label, r_in, prom, win in variants:
        cpm, events = run_detector(ts, r_in, prom_deg=prom, prom_win_s=win, log_events=True)
        dur_s = (ts[-1] - ts[0]) / 1000
        events_per_min = len(events) / (dur_s / 60) if dur_s > 0 else 0
        print(f'  events/min={events_per_min:5.1f}  {summarise(label, cpm, ts)}')

    # Also run baseline against padnormal for sanity — should give ~30 CPM
    print()
    tsN, rollN = load_csv('padnormal')
    cpmN, evN = run_detector(tsN, rollN, log_events=True)
    dur_s = (tsN[-1] - tsN[0]) / 1000
    print(f'  events/min={len(evN)/(dur_s/60):.1f}  {summarise("SANITY padnormal (expect ~30)", cpmN, tsN)}')
