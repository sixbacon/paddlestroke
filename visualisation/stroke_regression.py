"""Port of firmware/test/paddlestroke_sim_test to Python.

Runs all 20 ST-01..ST-20 tests against StrokeDetector (Python port). Used to
verify (a) the Python port is faithful (baseline) and (b) proposed fixes
don't regress on any test.
"""
import math
import random
from stroke_detector_sim import StrokeDetector


SAMPLE_RATE_HZ = 100.0
SAMPLE_INTERVAL_US = 10000
RATE_TOL_HZ = 2.0 / 60.0

g_passed = 0
g_failed = 0
g_reports = []


def _feed_sine(det, amp_deg, freq_hz, num_cycles, start_us=0):
    n = int(num_cycles / freq_hz * SAMPLE_RATE_HZ)
    last = 0.0
    for i in range(n):
        t_us = start_us + i * SAMPLE_INTERVAL_US
        t_sec = t_us / 1e6
        roll = amp_deg * math.sin(2 * math.pi * freq_hz * t_sec)
        if det.update(roll, t_us):
            last = det.rate_hz
    return last


def _feed_sine_noisy(det, amp_deg, freq_hz, num_cycles, start_us, noise_frac, seed=42):
    rng = random.Random(seed)
    n = int(num_cycles / freq_hz * SAMPLE_RATE_HZ)
    last = 0.0
    noise_amp = amp_deg * noise_frac
    for i in range(n):
        t_us = start_us + i * SAMPLE_INTERVAL_US
        t_sec = t_us / 1e6
        s = amp_deg * math.sin(2 * math.pi * freq_hz * t_sec)
        noise = (rng.randint(-10000, 10000) / 10000.0) * noise_amp
        if det.update(s + noise, t_us):
            last = det.rate_hz
    return last


def _feed_sine_asym(det, base_amp, freq_hz, num_cycles, start_us, pos_excess):
    n = int(num_cycles / freq_hz * SAMPLE_RATE_HZ)
    last = 0.0
    pos_amp = base_amp * (1 + pos_excess)
    neg_amp = base_amp
    for i in range(n):
        t_us = start_us + i * SAMPLE_INTERVAL_US
        t_sec = t_us / 1e6
        s = math.sin(2 * math.pi * freq_hz * t_sec)
        roll = s * pos_amp if s >= 0 else s * neg_amp
        if det.update(roll, t_us):
            last = det.rate_hz
    return last


def _check_rate(tid, desc, reported, expected, tol):
    global g_passed, g_failed
    ok = abs(reported - expected) <= tol
    tag = 'PASS' if ok else 'FAIL'
    g_reports.append(f'[{tag}] {tid} {desc}: reported {reported*60:.1f} CPM (expected {expected*60:.0f} +/-{tol*60:.0f})')
    if ok: g_passed += 1
    else: g_failed += 1


def _check_zero(tid, desc, reported):
    global g_passed, g_failed
    ok = reported == 0.0
    tag = 'PASS' if ok else 'FAIL'
    g_reports.append(f'[{tag}] {tid} {desc}: reported {reported*60:.1f} CPM (expected 0)')
    if ok: g_passed += 1
    else: g_failed += 1


def _check_bool(tid, desc, actual, expected):
    global g_passed, g_failed
    ok = actual == expected
    tag = 'PASS' if ok else 'FAIL'
    g_reports.append(f'[{tag}] {tid} {desc}: got {actual} (expected {expected})')
    if ok: g_passed += 1
    else: g_failed += 1


def _new(prom_deg=0.0, prom_win_s=0.0):
    return StrokeDetector(prominence_deg=prom_deg, prominence_win_s=prom_win_s)


def _incr_pass_fail(ok):
    global g_passed, g_failed
    if ok: g_passed += 1
    else: g_failed += 1


def run_all(prom_deg=0.0, prom_win_s=0.0, label=''):
    global g_passed, g_failed, g_reports  # noqa
    g_passed = 0
    g_failed = 0
    g_reports = []

    print(f'\n=== {label} ===')

    # ST-01
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 1.0, 8)
    _check_rate('ST-01', 'Valid 1 Hz +/-60deg', r, 1.0, RATE_TOL_HZ)
    # ST-02
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 0.5, 8)
    _check_rate('ST-02', 'Valid 0.5 Hz +/-60deg', r, 0.5, RATE_TOL_HZ)
    # ST-03
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 2.0, 8)
    _check_rate('ST-03', 'Valid 2.0 Hz +/-60deg', r, 2.0, RATE_TOL_HZ)
    # ST-04
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 40, 1.0, 8)
    _check_zero('ST-04', 'Amplitude gate below 90deg (+-40deg)', r)
    # ST-05
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 46, 1.0, 8)
    _check_rate('ST-05', 'Amplitude gate above 90deg (+-46deg)', r, 1.0, RATE_TOL_HZ)
    # ST-06
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 3.0, 8)
    _check_zero('ST-06', 'Rate gate too fast 3.0 Hz', r)
    # ST-07
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 0.15, 4)
    _check_zero('ST-07', 'Rate gate too slow 0.15 Hz', r)
    # ST-08
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 0.25, 8)
    _check_rate('ST-08', 'Rate gate lower boundary 0.25 Hz', r, 0.25, RATE_TOL_HZ)
    # ST-09
    d = _new(prom_deg, prom_win_s)
    r = _feed_sine(d, 60, 2.5, 8)
    _check_rate('ST-09', 'Rate gate upper boundary 2.5 Hz', r, 2.5, RATE_TOL_HZ)
    # ST-10 rolling average step change 1->2 Hz
    d = _new(prom_deg, prom_win_s)
    t_us = 0
    nA = int(10 / 1.0 * SAMPLE_RATE_HZ)
    for i in range(nA):
        t_sec = t_us / 1e6
        d.update(60 * math.sin(2 * math.pi * 1.0 * t_sec), t_us)
        t_us += SAMPLE_INTERVAL_US
    last = 0.0
    nB = int(10 / 2.0 * SAMPLE_RATE_HZ)
    for i in range(nB):
        t_sec = t_us / 1e6
        if d.update(60 * math.sin(2 * math.pi * 2.0 * t_sec), t_us):
            last = d.rate_hz
        t_us += SAMPLE_INTERVAL_US
    _check_rate('ST-10', 'Rolling avg converges to 2 Hz after step', last, 2.0, RATE_TOL_HZ)
    # ST-11 timeout no motion at 3.1 s
    d = _new(prom_deg, prom_win_s)
    _check_bool('ST-11', 'Timeout no motion at 3.1s',
                (3100000 - d.last_qual_ts) > 3000000, True)
    # ST-12 timeout motion then stop
    d = _new(prom_deg, prom_win_s)
    t_us = 0
    n = int(4 / 1.0 * SAMPLE_RATE_HZ)
    for i in range(n):
        t_sec = t_us / 1e6
        d.update(60 * math.sin(2 * math.pi * 1.0 * t_sec), t_us)
        t_us += SAMPLE_INTERVAL_US
    last_us = t_us - SAMPLE_INTERVAL_US
    after_motion = (last_us - d.last_qual_ts) > 3000000
    after_pause = (last_us + 3100000 - d.last_qual_ts) > 3000000
    ok = (not after_motion) and after_pause
    g_reports.append(f"[{'PASS' if ok else 'FAIL'}] ST-12 Timeout motion then stop (after_motion={after_motion}, after_pause={after_pause})")
    _incr_pass_fail(ok)

    # ST-13..16 noise
    for pct, tid in [(0.01, 'ST-13'), (0.02, 'ST-14'), (0.05, 'ST-15'), (0.10, 'ST-16')]:
        d = _new(prom_deg, prom_win_s)
        r = _feed_sine_noisy(d, 60, 1.0, 8, 0, pct)
        _check_rate(tid, f'{int(pct*100)}% noise, 1 Hz +/-60deg', r, 1.0, RATE_TOL_HZ)

    # ST-17..20 asymmetry
    for pct, tid in [(0.01, 'ST-17'), (0.02, 'ST-18'), (0.05, 'ST-19'), (0.10, 'ST-20')]:
        d = _new(prom_deg, prom_win_s)
        r = _feed_sine_asym(d, 60, 1.0, 8, 0, pct)
        _check_rate(tid, f'{int(pct*100)}% asymmetry, 1 Hz +/-60deg', r, 1.0, RATE_TOL_HZ)

    for line in g_reports:
        print(line)
    print(f'\nResults: {g_passed} passed, {g_failed} failed')
    return g_passed, g_failed


if __name__ == '__main__':
    # 1. Baseline — no fixes. Should reproduce firmware's 20/0.
    p, f = run_all(prom_deg=0.0, prom_win_s=0.0,
                   label='BASELINE (no fixes) — expect 20 passed / 0 failed')

    # 2. Prominence gate at various settings.
    for prom, win in [(20, 0.3), (30, 0.3), (40, 0.3), (30, 0.5)]:
        run_all(prom_deg=prom, prom_win_s=win,
                label=f'FIX: prominence {prom}deg / {int(win*1000)}ms window')
