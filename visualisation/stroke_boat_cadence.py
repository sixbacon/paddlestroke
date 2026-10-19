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


if __name__ == "__main__":
    main()
