"""stroke_kinematic_model.py — offline examination of the seat-anchored
kinematic-model paddle-centre estimate (functional_spec 8.1.1).

Purpose
-------
The visualiser places the paddle relative to the boat from assumed constants;
locating the paddle centre *through the stroke* is unobservable from two IMUs by
integration (accel double-integration drifts in seconds). The proposed way in is
a seat-anchored kinematic model: the paddle centre is a forward-kinematics
function of the well-measured shaft orientation, anchored at the shoulders, with
torso lean/twist (which moves the anchor) as the predicted unobservable residual.

This script examines that model on a well-calibrated forward-paddling session
(the 30 Aug 2026 clip-on-jig session), quantifies how much of the real paddle
motion it reproduces, and where it breaks.

Model
-----
One-pivot arm-swing. The paddle centre c sits on a sphere of radius R about a
shoulder-centre pivot P fixed in the boat frame; its direction co-rotates with
the measured paddle-vs-boat orientation R_rel(t):

        c(t) = R * R_rel(t) * d_hat            (P at the boat-frame origin)

R_rel(t) = R_boat(t)^T R_paddle(t) maps the paddle body frame into the boat body
frame; d_hat is the fixed (paddle-body) direction from pivot to centre; R the
reach radius. This is pure forward kinematics of the measured orientation — no
per-frame free DOF, no integration. It captures arm-swing and, by construction,
cannot represent lean/twist (moving P) — exactly the spec's unobservable.

Validation (no position ground truth, no integration)
------------------------------------------------------
1. Frame check: rotate the paddle accelerometer to world; its mean must be
   ~[0,0,g] (gravity-inclusive) — confirms the quaternion/frame pipeline.
2. Acceleration space: differentiate the model position twice -> a_model;
   rotate the measured accel to the boat frame and remove gravity -> a_meas
   (the TRUE paddle-centre acceleration). Band-pass to the stroke band and report
   the fraction of measured variance the model explains (a best-fit scale absorbs
   the reach-radius/closure amplitude, so the score reflects SHAPE agreement).
   The residual = lean/twist + model error.
3. GPS pseudo-ZUPT: while the blade is immersed the planted tip is ~still in the
   world, so in the boat frame it sweeps aft at ~boat speed. Compare the model
   tip's aft sweep (while its modelled depth is in the lower third) to GPS speed.
4. Fused vs GRV: re-score with each orientation source.

Usage:  python stroke_kinematic_model.py [PadLog.CSV] [BoatLog.CSV]
Defaults to the 30 Aug 2026 recordings. Emits visualisation/kinematic_model_30aug.png.
numpy + matplotlib only (matches the rest of the stroke_*.py toolkit; no scipy).
"""
import csv, sys, json, os, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REC  = os.path.join(HERE, "recordings")
PAD  = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REC, "PadLog20260830.CSV")
BOAT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REC, "BoatLog20260830.CSV")
OUT  = os.path.join(HERE, "kinematic_model_30aug.png")
G    = 9.80665

# anthropometry / model constants
REACH_R = 0.67                                   # m, pivot -> paddle centre
                                                 # (measured 30 Aug 2026; was 0.55
                                                 # assumed. Note: the accel score is
                                                 # scale-free, so R changes only the
                                                 # metric trajectory + GPS aft-sweep,
                                                 # not any variance-explained number.)
L_HALF  = 1.05                                   # m, centre -> blade tip (2.10/2)
D_REST  = np.array([0.0, 0.97, -0.24]); D_REST /= np.linalg.norm(D_REST)


def sections_from_sidecar(pad_csv, cls="right"):
    """Return a sorted list of (start,end) paddle-frame ranges for every
    classification of type cls in the sibling .session.json (empty if none).
    The 30 Aug session is classified as FOUR separate right-handed forward-
    paddling runs with the three turns left in the unclassified gaps between
    them; each run is scored independently so no seam artefact enters the
    double-differentiation / FFT band-pass."""
    base = os.path.splitext(pad_csv)[0] + ".session.json"
    if not os.path.exists(base):
        return []
    j = json.load(open(base))
    out = [(int(s["start_frame"]), int(s["end_frame"]))
           for s in j.get("classification_sections", []) if s.get("type") == cls]
    return sorted(out)


def section_from_sidecar(pad_csv, cls="right"):
    """Back-compat: first range of type cls, or None."""
    secs = sections_from_sidecar(pad_csv, cls)
    return secs[0] if secs else None


def rest_window_from_sidecar(pad_csv):
    base = os.path.splitext(pad_csv)[0] + ".session.json"
    if not os.path.exists(base):
        return None
    rw = json.load(open(base)).get("rest_window")
    if not rw:
        return None
    return (int(rw["paddle_frame_start"]), int(rw["paddle_frame_end"]),
            int(rw["boat_frame_start"]), int(rw["boat_frame_end"]))


def load_cols(path, cols, flo=None, fhi=None):
    out = {c: [] for c in cols}; frames = []
    with open(path, newline="") as f:
        r = csv.reader(f); header = None; fi = -1
        for row in r:
            if not row or row[0].startswith("#"):
                continue
            if header is None:
                header = row; idx = {c: header.index(c) for c in cols}; continue
            fi += 1
            if flo is not None and fi < flo: continue
            if fhi is not None and fi > fhi: break
            frames.append(fi)
            for c in cols:
                try: out[c].append(float(row[idx[c]]))
                except Exception: out[c].append(np.nan)
    res = {c: np.array(v) for c, v in out.items()}; res["_frame"] = np.array(frames)
    return res


def quat_to_R(qw, qx, qy, qz):
    n = np.sqrt(qw*qw+qx*qx+qy*qy+qz*qz); qw,qx,qy,qz = qw/n,qx/n,qy/n,qz/n
    N = len(qw); R = np.empty((N, 3, 3))
    R[:,0,0]=1-2*(qy*qy+qz*qz); R[:,0,1]=2*(qx*qy-qz*qw); R[:,0,2]=2*(qx*qz+qy*qw)
    R[:,1,0]=2*(qx*qy+qz*qw); R[:,1,1]=1-2*(qx*qx+qz*qz); R[:,1,2]=2*(qy*qz-qx*qw)
    R[:,2,0]=2*(qx*qz-qy*qw); R[:,2,1]=2*(qy*qz+qx*qw); R[:,2,2]=1-2*(qx*qx+qy*qy)
    return R


def movavg(a, w):
    if w <= 1: return a
    k = np.ones(w)/w
    if a.ndim == 1: return np.convolve(a, k, mode="same")
    return np.vstack([np.convolve(a[:,j], k, mode="same") for j in range(a.shape[1])]).T


def bandpass_fft(x, fs, lo, hi):
    X = np.fft.rfft(x, axis=0); fr = np.fft.rfftfreq(x.shape[0], 1/fs)
    m = ((fr >= lo) & (fr <= hi)).astype(float)
    if x.ndim > 1: m = m[:, None]
    return np.fft.irfft(X*m, n=x.shape[0], axis=0)


def main():
    runs = sections_from_sidecar(PAD) or [(58966, 197628)]
    print("Right-handed forward-paddling runs (paddle frames):")
    for a, b in runs: print("  %d..%d" % (a, b))

    pc = ["timestamp_ms","accel_x","accel_y","accel_z","q_w","q_x","q_y","q_z",
          "cpm","rx_ms","grv_qw","grv_qx","grv_qy","grv_qz"]
    bc = ["gps_speed_ms","gps_fix","kayak_qw","kayak_qx","kayak_qy","kayak_qz",
          "rx_ms","boat_grv_qw","boat_grv_qx","boat_grv_qy","boat_grv_qz"]
    boat = load_cols(BOAT, bc)
    order = np.argsort(boat["rx_ms"]); brx = boat["rx_ms"][order]
    lab = ["X(stbd)","Y(fwd)","Z(up)"]

    # Each run is processed independently (own fs, stroke band, differentiation
    # and FFT band-pass) so no discontinuity at a run boundary leaks into the
    # double derivative. Per-axis energies are then POOLED across runs and a
    # single global scale per axis gives the combined variance-explained.
    R = {"amaM":np.zeros(3), "aM2":np.zeros(3), "am2":np.zeros(3)}   # fused
    Rg = {"amaM":np.zeros(3), "aM2":np.zeros(3), "am2":np.zeros(3)}  # GRV
    aft_all=[]; gsp_all=[]; store=[]; Ntot=0

    for (f0f, f1f) in runs:
        pad = load_cols(PAD, pc, f0f, f1f)
        N = len(pad["_frame"]); t = (pad["timestamp_ms"]-pad["timestamp_ms"][0])/1000.0
        fs = 1.0/np.median(np.diff(t)); Ntot += N
        j = np.clip(np.searchsorted(brx, pad["rx_ms"]), 0, len(brx)-1)
        bs = lambda n: boat[n][order][j]

        Rp = quat_to_R(pad["q_w"],pad["q_x"],pad["q_y"],pad["q_z"])
        Rb = quat_to_R(bs("kayak_qw"),bs("kayak_qx"),bs("kayak_qy"),bs("kayak_qz"))
        Rrel = np.einsum("nji,njk->nik", Rb, Rp)
        u = Rrel @ np.array([1.0,0,0])
        swing = np.degrees(np.arctan2(u[:,0], u[:,1]))
        elev  = np.degrees(np.arcsin(np.clip(u[:,2],-1,1)))
        c   = REACH_R * (Rrel @ D_REST); tip = c + L_HALF * u

        a_body  = np.stack([pad["accel_x"],pad["accel_y"],pad["accel_z"]], axis=1)
        a_world = np.einsum("nij,nj->ni", Rp, a_body)
        a_meas_world = a_world - np.array([0,0,a_world[:,2].mean()])
        a_meas_boat  = np.einsum("nji,nj->ni", Rb, a_meas_world)

        d2 = lambda x, fs=fs, t=t: movavg(np.gradient(np.gradient(
                movavg(x, max(1,int(fs*0.05))), t, axis=0), t, axis=0),
                max(1,int(fs*0.05)))
        cpm = np.median(pad["cpm"][pad["cpm"]>0]); ff = cpm/60.0; lo,hi = 0.5*ff, 4.0*ff
        am = bandpass_fft(a_meas_boat, fs, lo, hi)
        aM = bandpass_fft(d2(c), fs, lo, hi)
        Rrg = np.einsum("nji,njk->nik",
                quat_to_R(bs("boat_grv_qw"),bs("boat_grv_qx"),bs("boat_grv_qy"),bs("boat_grv_qz")),
                quat_to_R(pad["grv_qw"],pad["grv_qx"],pad["grv_qy"],pad["grv_qz"]))
        aMg = bandpass_fft(d2(REACH_R*(Rrg @ D_REST)), fs, lo, hi)

        ve_run=[]
        for k in range(3):
            R["amaM"][k]+=np.sum(am[:,k]*aM[:,k]); R["aM2"][k]+=np.sum(aM[:,k]**2); R["am2"][k]+=np.sum(am[:,k]**2)
            Rg["amaM"][k]+=np.sum(am[:,k]*aMg[:,k]); Rg["aM2"][k]+=np.sum(aMg[:,k]**2); Rg["am2"][k]+=np.sum(am[:,k]**2)
            s = np.sum(am[:,k]*aM[:,k])/np.sum(aM[:,k]**2)
            ve_run.append(1 - np.sum((am[:,k]-s*aM[:,k])**2)/np.sum(am[:,k]**2))
        corr = np.corrcoef(am.ravel(), aM.ravel())[0,1]
        store.append(dict(N=N, t=t, swing=swing, elev=elev, c=c, am=am, aM=aM,
                          fs=fs, cpm=cpm, Rrel=Rrel, lo=lo, hi=hi, d2=d2,
                          a_world_mean=a_world.mean(axis=0)))
        tsm = movavg(tip, max(1,int(fs*0.05))); vtip = np.gradient(tsm, t, axis=0)
        imm = tsm[:,2] < np.percentile(tsm[:,2], 33); aft_all.append(-vtip[imm,1])
        gsp_all.append(bs("gps_speed_ms")[bs("gps_fix")>0])
        print("  run %d..%d N=%d %.0fCPM  VE=[%s] mean %.2f  corr %.2f  swing p2p %.0f°"
              % (f0f,f1f,N,cpm," ".join("%+.2f"%v for v in ve_run),
                 np.mean(ve_run),corr,np.percentile(swing,97)-np.percentile(swing,3)))

    # frame check (last run's world-accel mean is representative)
    print("  frame check: mean world accel = %s (expect ~[0,0,%.1f])"
          % (np.round(store[-1]["a_world_mean"],2), G))

    def pool(D):
        ve=[]
        for k in range(3):
            s=D["amaM"][k]/D["aM2"][k]
            ve.append(1 - (D["am2"][k]-2*s*D["amaM"][k]+s*s*D["aM2"][k])/D["am2"][k])
        return ve
    ve_all = pool(R); veg = pool(Rg)
    print("  POOLED (%d frames, %.0f min, single global scale/axis):" % (Ntot, Ntot/6000))
    for k in range(3):
        print("    %-8s fused VE %+.2f   GRV VE %+.2f" % (lab[k], ve_all[k], veg[k]))
    print("  MEAN fused VE %.2f   GRV VE %.2f" % (np.mean(ve_all), np.mean(veg)))

    aft = np.concatenate(aft_all); gspeed = np.mean(np.concatenate(gsp_all))
    print("  pseudo-ZUPT (R=%.2f): model tip aft-sweep median %.2f m/s (boat %.2f m/s)"
          % (REACH_R, np.median(aft), gspeed))

    # pick the longest run for the illustrative time-series/trajectory panels
    rep = max(store, key=lambda d: d["N"])
    t, swing, elev, c, am, aM, fs, cpm = (rep["t"], rep["swing"], rep["elev"],
        rep["c"], rep["am"], rep["aM"], rep["fs"], rep["cpm"])

    # ---- calibrate the body constants from the jig pose --------------------
    # The jig held the paddle in a known pose relative to the boat; its rest
    # window gives the orientation BORESIGHT (the constant sensor-mount skew).
    # Referencing the relative orientation to it, and fitting the reach
    # DIRECTION d_hat to the measured acceleration, replaces the two assumed
    # constants that ARE recoverable. The reach MAGNITUDE R is not recoverable
    # from inertial+GPS data (see note below), so it stays anthropometric.
    def dvec(az, dp):
        a, d = np.radians(az), np.radians(dp)
        return np.array([np.sin(a)*np.cos(d), np.cos(a)*np.cos(d), -np.sin(d)])

    def score_d_pooled(dh, Qoff=None):
        """Pooled (over all runs) variance-explained for reach-direction dh,
        optionally boresight-referencing R_rel by Qoff. Scale-free (R absent)."""
        amaM=np.zeros(3); aM2=np.zeros(3); am2=np.zeros(3)
        for r in store:
            Rr = r["Rrel"] if Qoff is None else np.einsum("ji,njk->nik", Qoff, r["Rrel"])
            aa = bandpass_fft(r["d2"](Rr @ dh), r["fs"], r["lo"], r["hi"])
            for k in range(3):
                amaM[k]+=np.sum(r["am"][:,k]*aa[:,k]); aM2[k]+=np.sum(aa[:,k]**2)
                am2[k]+=np.sum(r["am"][:,k]**2)
        return np.mean([amaM[k]**2/(aM2[k]*am2[k]) for k in range(3)])

    rw = rest_window_from_sidecar(PAD)
    if rw is not None:
        prw = load_cols(PAD, ["q_w","q_x","q_y","q_z"], rw[0], rw[1])
        brw = load_cols(BOAT, ["kayak_qw","kayak_qx","kayak_qy","kayak_qz"], rw[2], rw[3])
        def mean_R(q):
            q = q/np.linalg.norm(q,axis=1,keepdims=True)
            q = q*np.sign(np.sum(q*q[0],1,keepdims=True)); m = q.mean(0); m/=np.linalg.norm(m)
            return quat_to_R(*[np.array([x]) for x in m])[0]
        Rp0 = mean_R(np.stack([prw["q_w"],prw["q_x"],prw["q_y"],prw["q_z"]],1))
        Rb0 = mean_R(np.stack([brw["kayak_qw"],brw["kayak_qx"],brw["kayak_qy"],brw["kayak_qz"]],1))
        Q_OFFSET = Rb0.T @ Rp0
        resid = np.degrees(np.arccos(np.clip((np.trace(Q_OFFSET)-1)/2, -1, 1)))

        # fit d_hat over a physically-sensible forward/down grid, pooled over runs
        best = None
        for azd in np.arange(-40,41,4):
            for dipd in np.arange(-5,61,4):
                v = score_d_pooled(dvec(azd, dipd), Q_OFFSET)
                if best is None or v > best[0]: best = (v, azd, dipd, dvec(azd, dipd))
        vC, azC, dipC, dhC = best
        nb = max(score_d_pooled(dvec(a, dp)) for a in np.arange(-40,41,8)
                 for dp in np.arange(-5,61,8))
        print("\n  -- calibration from the jig pose (pooled over runs) --")
        print("     jig boresight residual (mount skew) = %.1f deg" % resid)
        print("     assumed constants               : var-explained %.2f" % np.mean(ve_all))
        print("     + jig boresight (assumed d_hat)  : var-explained %.2f" % score_d_pooled(D_REST, Q_OFFSET))
        print("     + fitted d_hat (no boresight)    : var-explained %.2f" % nb)
        print("     + boresight + fitted d_hat       : var-explained %.2f   "
              "d_hat=%s (az %.0f, dip %.0f)" % (vC, np.round(dhC,3), azC, dipC))
        print("     reach magnitude R: NOT recoverable from inertial+GPS (tip velocity is")
        print("       dominated by measured blade rotation; the accel score is scale-free).")
        print("       Keep R anthropometric, or set it from the jig's measured geometry.")

    _figure(t, swing, elev, c, am, aM, ve_all, aft, gspeed, fs, cpm)


def _figure(t, swing, elev, c, am, aM, ve_all, aft, gspeed, fs, cpm):
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    i0 = int(len(t)*0.45); w = slice(i0, i0+int(24*fs))
    fig = plt.figure(figsize=(13,9)); fig.patch.set_facecolor("white")
    fig.suptitle("Seat-anchored kinematic-model estimate — 30 Aug 2026, four RH forward-paddling "
                 "runs (turns excluded)\npanels A–C: longest run (%d frames, %.0f min, %.0f CPM); "
                 "C/D var-explained + GPS are POOLED over all four\n"
                 "model: c(t)=R·R_rel(t)·" r"$\hat{d}$"
                 "  (paddle centre swings on a sphere about a fixed shoulder pivot)"
                 % (len(t), t[-1]/60, cpm), fontsize=10)
    ax=fig.add_subplot(2,2,1)
    ax.plot(t[w],swing[w],lw=.9,label="swing (about vertical)")
    ax.plot(t[w],elev[w],lw=.9,label="elevation")
    ax.set_title("A · Measured shaft orientation (boat frame) — clean & stroke-periodic")
    ax.set_xlabel("time (s)"); ax.set_ylabel("degrees"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    ax=fig.add_subplot(2,2,2)
    ax.plot(c[w,1],c[w,0],lw=.7,color="tab:purple",label="centre XY (top-down)")
    ax.plot(c[w,1],c[w,2],lw=.7,color="tab:green",label="centre YZ (side)")
    ax.scatter([0],[0],c="k",s=40,marker="+")
    ax.annotate("shoulder pivot", (0,0), xytext=(-0.45,-0.03), fontsize=7,
                ha="left", va="center", color="dimgray",
                arrowprops=dict(arrowstyle="-", lw=.5, color="dimgray"))
    ax.set_title("B · Model paddle-centre trajectory (arm-swing arc)")
    ax.set_xlabel("boat +Y forward (m)"); ax.set_ylabel("boat +X stbd / +Z up (m)")
    ax.axis("equal"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    ax=fig.add_subplot(2,2,3)
    s=np.sum(am[w,1]*aM[w,1])/np.sum(aM[w,1]*aM[w,1])
    ax.plot(t[w],am[w,1],lw=1,color="k",label="measured (accelerometer, gravity removed)")
    ax.plot(t[w],s*aM[w,1],lw=1,color="tab:red",label="model prediction (scaled)")
    ax.set_title("C · Forward-axis stroke-band acceleration: model explains %.0f%% of variance"
                 % (100*ve_all[1]))
    ax.set_xlabel("time (s)"); ax.set_ylabel("a_fwd (m/s²)"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    ax=fig.add_subplot(2,2,4)
    ax.hist(aft,bins=50,range=(-2,7),color="tab:blue",alpha=.7,
            label="model tip aft-sweep while immersed\n(median %.2f m/s)"%np.median(aft))
    ax.axvline(gspeed,color="tab:orange",lw=2,label="GPS boat speed (%.2f m/s)"%gspeed)
    ax.axvline(np.median(aft),color="tab:blue",lw=1,ls="--")
    ax.set_title("D · GPS pseudo-ZUPT: planted-blade aft-sweep vs boat speed")
    ax.set_xlabel("aft sweep of right-blade tip while immersed (m/s)"); ax.set_ylabel("count")
    ax.legend(fontsize=8); ax.grid(alpha=.3)
    fig.tight_layout(rect=[0,0,1,0.94]); fig.savefig(OUT, dpi=130)
    print("saved figure:", OUT)


if __name__ == "__main__":
    main()
