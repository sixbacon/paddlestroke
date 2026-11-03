"""stroke_boat_cadence.py — can the BOAT unit alone recover paddling cadence?

Spectral test of the boat forward-surge (hull IMU acceleration) against known
cadence. Every blade plant pushes the hull forward, so the boat surges once per
stroke regardless of paddle feather, handedness, or one-/two-piece joint — the
exact variations that complicate the paddle-side roll detector. This quantifies
how cleanly the surge fundamental tracks the true cadence, including the
zero-feather section that makes the paddle-roll algorithm read double.

Also confirms GPS speed CANNOT see cadence (its ~1 Hz update aliases the ~1 Hz
stroke surge), so cadence must come from the 100 Hz IMU; GPS gives mean speed.

Evidence for firmware/specs/boat_only_spec.md §4. numpy + csv only (matches the
rest of the stroke_*.py toolkit). The recordings are git-ignored; this prints a
SKIP line per missing file rather than failing.

Usage:  python stroke_boat_cadence.py
"""
import csv, os, sys, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REC  = os.path.join(HERE, "recordings")
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def load(path, cols, flo=None, fhi=None):
    out = {c: [] for c in cols}; fr = []
    with open(path, newline="") as f:
        r = csv.reader(f); H = None; idx = {}
        fi = -1
        for row in r:
            if not row or row[0].startswith("#"):
                continue
            if H is None:
                H = row; idx = {c: H.index(c) for c in cols if c in H}; continue
            fi += 1
            if flo is not None and fi < flo: continue
            if fhi is not None and fi > fhi: break
            fr.append(fi)
            for c in cols:
                try: out[c].append(float(row[idx[c]]))
                except Exception: out[c].append(np.nan)
    d = {c: np.array(v) for c, v in out.items()}; d["_f"] = np.array(fr)
    return d


def band_peak(sig, fs, lo, hi):
    """Dominant frequency of sig in [lo,hi] Hz, and the fraction of in-band
    energy concentrated within +-10% of that peak (a sharpness/confidence cue)."""
    sig = np.nan_to_num(sig - np.nanmean(sig))
    w = np.hanning(len(sig))
    S = np.abs(np.fft.rfft(sig * w))
    fr = np.fft.rfftfreq(len(sig), 1.0 / fs)
    m = (fr >= lo) & (fr <= hi)
    pf = fr[m][np.argmax(S[m])]
    notch = (fr >= pf * 0.9) & (fr <= pf * 1.1)
    conc = np.sum(S[notch] ** 2) / np.sum(S[m] ** 2)
    return pf, conc


# ──────────────────────────────────────────────────────────────────────────────
# Surge-ACF cadence estimator — the FIRMWARE CONTRACT.
#
# This block is a faithful offline mirror of firmware/production/BoatRate/
# SurgeCadence.* (itself adapted from PadLog/CadenceACF.*). The firmware streams
# it sample-by-sample; here we run it over windows. Keep the two in sync: the
# constants below are copied verbatim into SurgeCadence.cpp.
#
# Validated (tune_surge, 3 Nov 2026) to reproduce boat_only_spec.md §4/§6.1:
#   21 Oct SUP 30.9/min, canoe-back 29.3/min (single, surge≈sway, ratio≈1.0);
#   30 Aug 72.8 (=2× cycle 36.4), 12 Aug zero-feather 66.3 (=2× 33.1),
#   12 Aug feathered 70.3 (=2× 35.1) — all double, ratio≈2.0, surge/2 = §4.
#
# IMPORTANT correction to the spec wording: the fundamental-lock is the FIRST
# (smallest-lag) strong ACF peak after the zero-lag hill — i.e. the true period
# T. A literal "longest-period strong peak" grabs the 2T/3T sub-harmonic ACF
# peaks and reports HALF the real cadence (SUP measured 15/min that way). The
# first ACF peak already rejects the 2× FFT harmonic (a higher freq = shorter
# lag has no genuine ACF peak), so it resolves the §6.1 ambiguity correctly.
SC_DECIM     = 10        # 100 Hz -> 10 Hz block mean
SC_FS        = 10.0      # post-decimation sample rate
SC_WIN_S     = 16.0      # sliding window (s) — ~3 cycles at the 0.2 Hz floor
SC_LAG_LO    = 6         # ceiling 10/6  ≈ 1.67 Hz (100/min)
SC_LAG_HI    = 50        # floor   10/50 = 0.20 Hz (12/min) — single-blade runs slow
SC_MIN_ACF   = 0.5       # periodicity quality gate
SC_FUND_FRAC = 0.75      # a local max counts as "strong" at ≥ this × global max
SC_ZERO_HILL = 0.30      # skip the zero-lag correlation hill
SC_STD_GATE  = 0.10      # activity gate: surge/sway std (m/s²) before reporting


def sc_decimate(sig, fs_in=100.0):
    """100 Hz → 10 Hz block mean (SC_DECIM-sample average), matching firmware."""
    step = int(round(fs_in / SC_FS))
    n = (len(sig) // step) * step
    return sig[:n].reshape(-1, step).mean(axis=1)


def sc_acf_cpm(win):
    """One estimate over a ~SC_WIN_S window of 10 Hz samples.
    Returns (cpm, acf_peak, valid). Mirrors SurgeCadence::_estimate()."""
    n = len(win)
    x = win - win.mean()
    std = float(np.sqrt(np.mean(x * x)))
    if std < SC_STD_GATE:
        return 0.0, 0.0, False
    lag_hi = min(SC_LAG_HI, n - 4)
    if lag_hi < SC_LAG_LO:
        return 0.0, 0.0, False
    r = np.zeros(lag_hi + 1)
    for lag in range(1, lag_hi + 1):
        a = x[:n - lag]; b = x[lag:]
        denom = np.sqrt(np.dot(a, a) * np.dot(b, b))
        r[lag] = np.dot(a, b) / denom if denom > 0 else 0.0
    start = 1
    while start <= lag_hi and r[start] > SC_ZERO_HILL:
        start += 1
    if start > lag_hi:
        return 0.0, 0.0, False
    if start < SC_LAG_LO:
        start = SC_LAG_LO
    rmax = float(r[start:lag_hi + 1].max())
    if rmax < SC_MIN_ACF:
        return 0.0, rmax, False
    best = 0                                    # first strong local max = fundamental
    for lag in range(start + 1, lag_hi):
        if r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1] and r[lag] >= SC_FUND_FRAC * rmax:
            best = lag; break
    if best == 0:
        best = start + int(np.argmax(r[start:lag_hi + 1]))
    delta = 0.0                                 # parabolic sub-lag refine
    if start < best < lag_hi:
        y0, y1, y2 = r[best - 1], r[best], r[best + 1]
        den = y0 - 2 * y1 + y2
        if abs(den) > 1e-12:
            delta = max(-0.5, min(0.5, 0.5 * (y0 - y2) / den))
    period = (best + delta) / SC_FS
    if period <= 0:
        return 0.0, rmax, False
    return 60.0 / period, rmax, True


def sc_track(sig100):
    """Sliding surge-ACF over a 100 Hz signal. Returns (median_cpm, median_peak,
    n_windows) over the confident windows, or (nan, nan, 0)."""
    d = sc_decimate(np.nan_to_num(sig100 - np.nanmean(sig100)))
    w = int(SC_WIN_S * SC_FS); hop = int(4 * SC_FS)
    cpms = []; peaks = []
    for s in range(0, len(d) - w, hop):
        cpm, peak, ok = sc_acf_cpm(d[s:s + w])
        if ok:
            cpms.append(cpm); peaks.append(peak)
    if not cpms:
        return float("nan"), float("nan"), 0
    return float(np.median(cpms)), float(np.median(peaks)), len(cpms)


def test_boat_only(name, boat_csv, legs, note):
    """Boat-ONLY cadence test — no paddle unit, no paddle CSV. Selects rows by a
    time window (minutes from the start of the file) and runs the surge-ACF
    estimator on the forward (surge) and starboard (sway) axes, reporting the
    surge:sway ratio as the mode discriminator (≈1 single blade / ≈2 double).
    This is the spec §9 Phase-A 'boat-only + time-window' mode."""
    boat_path = boat_csv if os.path.isabs(boat_csv) else os.path.join(REC, boat_csv)
    if not os.path.exists(boat_path):
        print("\n=== %s ===\n  SKIP — %s not present" % (name, boat_csv))
        return
    print("\n=== %s ===" % name)
    print("  (%s)" % note)
    bo = load(boat_path, ["timestamp_ms", "boat_accel_x", "boat_accel_y", "gps_speed_ms"])
    t = (bo["timestamp_ms"] - bo["timestamp_ms"][0]) / 1000.0
    for lbl, lo, hi in legs:
        m = (t / 60 >= lo) & (t / 60 < hi) if hi is not None else (t / 60 >= lo)
        surge, sp_pk, sn = sc_track(bo["boat_accel_y"][m])
        sway,  sw_pk, wn = sc_track(bo["boat_accel_x"][m])
        spd = np.nanmean(bo["gps_speed_ms"][m])
        if sn == 0:
            print("    %-14s [%4.1f–%4.1f min]  no confident windows (glide/handling)" % (lbl, lo, hi))
            continue
        ratio = surge / sway if wn and sway > 0 else float("nan")
        mode = "double ~2:1" if ratio > 1.5 else "single ~1:1"
        print("    %-14s [%4.1f–%4.1f min]  surge %.1f/min (ACF %.2f, n=%d)  "
              "sway %.1f/min (n=%d)  ratio %.2f → %s  speed %.2f m/s"
              % (lbl, lo, hi, surge, sp_pk, sn, sway, wn, ratio, mode, spd))


def test(name, pad_csv, boat_csv, sec, true_cpm, note):
    pad_path  = os.path.join(REC, pad_csv)
    boat_path = os.path.join(REC, boat_csv)
    if not (os.path.exists(pad_path) and os.path.exists(boat_path)):
        print("\n=== %s ===\n  SKIP — recordings not present (git-ignored)" % name)
        return
    print("\n=== %s ===" % name)
    print("  (%s)" % note)
    pad = load(pad_path, ["rx_ms"], *sec)
    rx0, rx1 = pad["rx_ms"].min(), pad["rx_ms"].max()
    boat = load(boat_path, ["rx_ms", "boat_accel_x", "boat_accel_y",
                            "gps_speed_ms", "gps_fix", "timestamp_ms"])
    sel = (boat["rx_ms"] >= rx0) & (boat["rx_ms"] <= rx1)
    t = boat["timestamp_ms"][sel]
    order = np.argsort(t); t = (t[order] - t[order][0]) / 1000.0
    fs = 1.0 / np.median(np.diff(t))
    ay = boat["boat_accel_y"][sel][order]        # forward (surge)
    ax = boat["boat_accel_x"][sel][order]        # starboard (sway)
    amag = np.sqrt(ax ** 2 + ay ** 2)            # horizontal magnitude (frame-robust)

    cyc = true_cpm / 60.0
    strokef = 2 * cyc                            # hull surges once per blade
    print("  boat rows %d  fs=%.0f Hz  dur %.0fs" % (sel.sum(), fs, t[-1]))
    print("  true cycle %.1f CPM (%.2f Hz) -> expect surge peak at STROKE rate %.2f Hz"
          % (true_cpm, cyc, strokef))
    for lbl, sig in [("accel_y(fwd/surge)", ay),
                     ("accel_x(stbd/sway)", ax),
                     ("|a_horiz|", amag)]:
        pf, conc = band_peak(sig, fs, 0.6, 2.2)
        print("    %-20s peak %.2f Hz  (= %.1f CPM as cycle)  conc %.0f%%"
              % (lbl, pf, pf / 2 * 60, 100 * conc))

    gs = boat["gps_speed_ms"][sel][order]; gf = boat["gps_fix"][sel][order]
    chg = np.sum(np.abs(np.diff(gs)) > 1e-6)
    gps_hz = chg / max(1e-9, t[-1])
    vis = "VISIBLE" if gps_hz / 2 > strokef else "ALIASED (invisible)"
    print("  GPS speed mean %.2f m/s; update ~%.1f Hz -> Nyquist %.2f Hz; stroke %.2f Hz: %s"
          % (np.nanmean(gs[gf > 0]), gps_hz, gps_hz / 2, strokef, vis))


def main():
    # Baseline: feathered right-handed (paddle-roll detector works here)
    test("30 Aug 2026 feathered RH (longest run)",
         "PadLog20260830.CSV", "BoatLog20260830.CSV", (128164, 158863), 36.0,
         "paddle-roll algorithm works fine here — baseline")
    # Killer case: zero-feather, where the paddle ROLL detector reads 2x
    test("12 Aug 2026 ZERO-FEATHER section",
         "PadLog20260812.CSV", "BoatLog20260812.CSV", (33470, 50499), 32.5,
         "paddle roll reads 65 CPM (2x); pitch truth 32.5 — the decisive test")
    # Feathered RH on the same outing, for comparison
    test("12 Aug 2026 feathered RH section",
         "PadLog20260812.CSV", "BoatLog20260812.CSV", (65766, 120000), 35.0,
         "feathered RH, paddle works")

    # ── Boat-ONLY single-blade (no paddle unit) — spec §6.1 / §9 A-2,A-3 ──────
    # The 21 Oct file lives in data/ (git-ignored), not recordings/; pass the
    # absolute path. Leg boundaries (minutes) are from the session note (§6.1).
    oct21 = os.path.join(HERE, os.pardir, "data", "2026-10-21", "BoatLog29.CSV")
    test_boat_only(
        "21 Oct 2026 boat-only (canoe + SUP) — first single-blade",
        os.path.abspath(oct21),
        [("canoe slow", 9.0, 14.5), ("canoe back", 15.0, 21.0),
         ("transition", 22.0, 30.5), ("SUP", 31.0, 43.0)],
        "surge-ACF fundamental-lock; surge≈sway (≈1:1) confirms single blade; "
        "canoe-slow is the gentle-catch leg where sway reads cleaner than surge")


if __name__ == "__main__":
    main()
