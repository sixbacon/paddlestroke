// CatchEvents — offline blade entry/exit detection (v0.14, spec §13.3).
//
// Port of the firmware-spec §13.5 feasibility method, validated offline on
// the 16 Jul 2026 field data (visualisation/stroke_catch_explore.py):
//
//   1. |accel| → 8–30 Hz band-pass → 50 ms RMS envelope. Blade impacts
//      (water entry) and releases (exit) appear as phase-locked bumps.
//   2. Blade-tip height from orientation (shaft = sensor X axis, ±1.05 m):
//      an event window is a run of frames where a tip is below the shaft
//      centre; the descending part holds the entry, the rising part the
//      exit. The HF-envelope peak inside each part time-stamps the event.
//   3. Blade XY in the boat frame via GRV relative yaw (firmware spec
//      §16.11: fused yaw carries an in-band cycle-periodic mag artefact;
//      GRV does not). Falls back to fused quats on pre-GRV files and to a
//      rolling heading baseline when no boat CSV is loaded.
//
// Side convention: sensor +X = shaft toward the RIGHT blade (spec §2), so
// the +X tip is the right blade. (If a session's mount is reversed — see
// project_paddle_mount_diagnosis — the colours swap; that is a mount fact,
// not a software correction to make here.)
//
// The yaw datum (step 3) is auto-computed per file/sidecar and can be off
// by tens of degrees on some sessions (found 20 Jul 2026). Sidecar.
// yawManualAdjustDeg is a user-nudged correction on top of it, saved with
// the sidecar so it persists — a stop-gap until a more reliable automatic
// method exists (spec §13.7). See PadViz6.pde's nudgeManualYawDatum() and
// the Slice 0 HUD (drawHUD_slice0()) for the interactive side.
//
// All filtering is offline forward-backward (zero phase), run once per
// CSV/sidecar change. ~µs per frame; 260 k-row files are fine.

class CatchEvent {
    int     padFrame;
    long    rxMs;
    boolean right;    // true = right blade (+X), false = left (−X)
    boolean entry;    // true = water entry (catch), false = exit (release)
    float   xB, yB;   // boat-frame blade position, metres (+X stbd, +Y fwd)
}

class CatchEvents {
    ArrayList<CatchEvent> events = new ArrayList<CatchEvent>();
    String  status  = "no data";
    boolean grvUsed = false;
    boolean boatUsed = false;
    boolean datumFromSidecar = false;

    // Auto-computed yaw datum (degrees, before any manual override) — kept
    // for the Slice 0 HUD readout (spec §13.7). The value actually used to
    // place events includes sidecar.yawManualAdjustDeg on top of this.
    float   datumAutoDeg = 0;

    static final float BLADE_L   = 1.05f;  // m, shaft centre → blade centre
    static final float LOW_T     = -0.05f; // m, tip-below-centre gate
    static final float ENV_RATIO = 1.3f;   // peak ≥ ratio × median env
    static final float ENV_FLOOR = 0.8f;   // m/s², absolute impact floor
    static final float MIN_RUN_S = 0.20f;  // shortest credible in-water run
    static final float MAX_RUN_S = 4.0f;   // longest — skips rest periods

    void compute(DataSource pad, BoatSource boat, SyncMap sync, Sidecar sc) {
        events.clear();
        if (pad == null || pad.frameCount() < 200) {
            status = "no paddle data";
            return;
        }
        int n = pad.frameCount();
        ArrayList<FrameData> fr = pad.getFrames();

        // Sample rate from median timestamp delta.
        float fs = estimateFs(fr);

        grvUsed = pad.hasGrv;
        boolean boatGrv = (boat != null && boat.frameCount() > 0 && boat.hasGrv);
        boatUsed = (boat != null && boat.frameCount() > 0
                    && sync != null && (boatGrv || !grvUsed));

        // ── per-frame signals ───────────────────────────────────────────
        float[] amag = new float[n];
        float[] uzRaw = new float[n];   // world-z of shaft dir (body X)
        float[] phi  = new float[n];    // world heading of shaft dir (rad)
        float[] hMag = new float[n];    // horizontal magnitude of shaft dir
        for (int i = 0; i < n; i++) {
            FrameData f = fr.get(i);
            amag[i] = sqrt(f.accelX*f.accelX + f.accelY*f.accelY + f.accelZ*f.accelZ);
            float qw = grvUsed ? f.grvQw : f.qw;
            float qx = grvUsed ? f.grvQx : f.qx;
            float qy = grvUsed ? f.grvQy : f.qy;
            float qz = grvUsed ? f.grvQz : f.qz;
            // Shaft direction = first column of R(q): body X in world.
            float ux = 1 - 2*(qy*qy + qz*qz);
            float uy = 2*(qx*qy + qw*qz);
            float uz = 2*(qx*qz - qw*qy);
            uzRaw[i] = uz;
            phi[i]   = atan2(uy, ux);
            hMag[i]  = sqrt(ux*ux + uy*uy);
        }

        // HF impact envelope: band-pass 8–30 Hz then 50 ms RMS.
        float[] hf = bandpass(amag, fs, 8, 30);
        float[] env = rmsEnvelope(hf, max(1, round(0.05f * fs)));
        float envMed = medianOf(env);
        float envGate = max(ENV_RATIO * envMed, ENV_FLOOR);

        // Smoothed tip height driver (uz low-passed at 3 Hz, zero phase).
        float[] uzLp = lowpassFB(uzRaw, fs, 3.0f);

        // ── heading reference per frame ────────────────────────────────
        // psiRef[i] = boat GRV/fused yaw at the synced boat frame, or (no
        // boat) a ±15 s rolling circular mean of the shaft heading itself.
        float[] psiRef = new float[n];
        if (boatUsed) {
            float last = 0;
            ArrayList<BoatFrameData> bf = boat.getFrames();
            for (int i = 0; i < n; i++) {
                int bi = sync.boatIdxFor(i);
                if (bi >= 0 && bi < bf.size()) {
                    BoatFrameData b = bf.get(bi);
                    float qw = boatGrv ? b.grvQw : b.qw;
                    float qx = boatGrv ? b.grvQx : b.qx;
                    float qy = boatGrv ? b.grvQy : b.qy;
                    float qz = boatGrv ? b.grvQz : b.qz;
                    last = atan2(2*(qw*qz + qx*qy), 1 - 2*(qy*qy + qz*qz));
                }
                psiRef[i] = last;
            }
        } else {
            psiRef = rollingCircularMean(phi, round(15 * fs));
        }

        // ── yaw datum: shaft +X must read as boat +X (starboard) at rest ──
        // Circular mean of (phi − psiRef) over the sidecar rest window when
        // available, else over the whole file (approximate — assumes the
        // mean paddling pose is shaft-across-boat, which steady paddling
        // satisfies to a few degrees).
        int dLo = 0, dHi = n - 1;
        datumFromSidecar = (sc != null && sc.valid
                            && sc.restPadStart >= 0 && sc.restPadEnd > sc.restPadStart);
        if (datumFromSidecar) {
            dLo = constrain(sc.restPadStart, 0, n - 1);
            dHi = constrain(sc.restPadEnd,   0, n - 1);
        }
        float sC = 0, sS = 0;
        for (int i = dLo; i <= dHi; i++) {
            float d = phi[i] - psiRef[i];
            sC += cos(d);  sS += sin(d);
        }
        float datum = atan2(sS, sC);
        datumAutoDeg = degrees(datum);

        // Manual override on top of the auto datum (spec §13.7) — saved in
        // the sidecar so it persists with this data record. 0 if no sidecar
        // or it hasn't been nudged.
        float manualDeg = (sc != null) ? sc.yawManualAdjustDeg : 0;
        float datumEff  = datum + radians(manualDeg);

        // ── event scan per blade ───────────────────────────────────────
        int minRun = round(MIN_RUN_S * fs);
        int maxRun = round(MAX_RUN_S * fs);
        for (int side = 0; side < 2; side++) {
            boolean rightBlade = (side == 0);   // +X tip = right blade (§2)
            float sgn = rightBlade ? 1 : -1;
            int i = 0;
            while (i < n) {
                if (sgn * uzLp[i] * BLADE_L >= LOW_T) { i++; continue; }
                int runStart = i;
                int minIdx = i;
                float minTip = sgn * uzLp[i] * BLADE_L;
                while (i < n && sgn * uzLp[i] * BLADE_L < LOW_T) {
                    float tip = sgn * uzLp[i] * BLADE_L;
                    if (tip < minTip) { minTip = tip; minIdx = i; }
                    i++;
                }
                int runEnd = i - 1;
                int len = runEnd - runStart + 1;
                if (len < minRun || len > maxRun) continue;

                // Entry = strongest impact while descending; exit while rising.
                addEventIfLoud(fr, env, envGate, phi, psiRef, datumEff, hMag,
                               runStart, minIdx, rightBlade, true);
                addEventIfLoud(fr, env, envGate, phi, psiRef, datumEff, hMag,
                               minIdx, runEnd, rightBlade, false);
            }
        }

        // Sort by frame so the panel can draw incrementally with playback.
        java.util.Collections.sort(events, new java.util.Comparator<CatchEvent>() {
            public int compare(CatchEvent a, CatchEvent b) {
                return Integer.compare(a.padFrame, b.padFrame);
            }
        });

        String src   = grvUsed ? "GRV" : "fused (pre-GRV file — approx)";
        String headR = boatUsed ? (boatGrv ? "boat GRV" : "boat fused")
                                : "rolling baseline (no boat — approx)";
        String dat   = datumFromSidecar ? "sidecar rest" : "whole-file mean (approx)";
        String man   = (manualDeg != 0) ? String.format("  manual=%+.1f°", manualDeg) : "";
        status = events.size() + " events | quat: " + src + " | heading: " + headR
               + " | datum: " + dat + man;
        println("CatchEvents: " + status);
    }

    void addEventIfLoud(ArrayList<FrameData> fr, float[] env, float envGate,
                        float[] phi, float[] psiRef, float datum, float[] hMag,
                        int lo, int hi, boolean rightBlade, boolean entry) {
        if (hi <= lo) return;
        int best = lo;
        for (int i = lo + 1; i <= hi; i++) if (env[i] > env[best]) best = i;
        if (env[best] < envGate) return;

        CatchEvent e = new CatchEvent();
        e.padFrame = best;
        e.rxMs     = fr.get(best).rxMs;
        e.right    = rightBlade;
        e.entry    = entry;
        float sgn  = rightBlade ? 1 : -1;
        float a    = phi[best] - psiRef[best] - datum;
        float r    = BLADE_L * hMag[best] * sgn;
        // xB/yB are blade position relative to the shaft centre in the
        // boat frame (+X stbd, +Y bow — matches EntryExitPanel). The shaft
        // centre itself sits PADDLE_BOW_OFFSET_M forward of the boat's own
        // centre/cockpit (PadViz6.pde, global — same value drawSliceC()'s
        // 3D mesh uses), so that offset carries into yB too, or the panel
        // would silently assume the paddler sits with the shaft directly
        // over the boat's centre (found 20 Jul 2026 — the 3D view moved
        // when this constant was added, the panel didn't).
        e.xB = r * cos(a);
        e.yB = r * sin(a) + PADDLE_BOW_OFFSET_M;
        events.add(e);
    }

    // ── numeric helpers ─────────────────────────────────────────────────

    float estimateFs(ArrayList<FrameData> fr) {
        int m = min(fr.size() - 1, 2000);
        float[] d = new float[m];
        for (int i = 0; i < m; i++) d[i] = fr.get(i + 1).ts - fr.get(i).ts;
        java.util.Arrays.sort(d);
        float med = d[m / 2];
        if (med <= 0 || med > 100) med = 10;
        return 1000.0f / med;
    }

    float medianOf(float[] x) {
        float[] c = x.clone();
        java.util.Arrays.sort(c);
        return c[c.length / 2];
    }

    // 2nd-order Butterworth biquad (RBJ cookbook), applied forward then
    // backward for zero phase — offline use only.
    float[] biquadFB(float[] x, float b0, float b1, float b2, float a1, float a2) {
        float[] y = biquad(x, b0, b1, b2, a1, a2);
        reverse(y);
        y = biquad(y, b0, b1, b2, a1, a2);
        reverse(y);
        return y;
    }

    float[] biquad(float[] x, float b0, float b1, float b2, float a1, float a2) {
        float[] y = new float[x.length];
        float x1 = 0, x2 = 0, y1 = 0, y2 = 0;
        for (int i = 0; i < x.length; i++) {
            float v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1;  x1 = x[i];
            y2 = y1;  y1 = v;
            y[i] = v;
        }
        return y;
    }

    void reverse(float[] a) {
        for (int i = 0, j = a.length - 1; i < j; i++, j--) {
            float t = a[i];  a[i] = a[j];  a[j] = t;
        }
    }

    float[] lowpassFB(float[] x, float fs, float fc) {
        float w = TWO_PI * fc / fs;
        float alpha = sin(w) / (2 * 0.7071f);
        float cw = cos(w);
        float a0 = 1 + alpha;
        return biquadFB(x, ((1 - cw) / 2) / a0, (1 - cw) / a0, ((1 - cw) / 2) / a0,
                        (-2 * cw) / a0, (1 - alpha) / a0);
    }

    float[] highpassFB(float[] x, float fs, float fc) {
        float w = TWO_PI * fc / fs;
        float alpha = sin(w) / (2 * 0.7071f);
        float cw = cos(w);
        float a0 = 1 + alpha;
        return biquadFB(x, ((1 + cw) / 2) / a0, (-(1 + cw)) / a0, ((1 + cw) / 2) / a0,
                        (-2 * cw) / a0, (1 - alpha) / a0);
    }

    float[] bandpass(float[] x, float fs, float f1, float f2) {
        return lowpassFB(highpassFB(x, fs, f1), fs, f2);
    }

    float[] rmsEnvelope(float[] x, int win) {
        int n = x.length;
        double[] prefix = new double[n + 1];
        for (int i = 0; i < n; i++) prefix[i + 1] = prefix[i] + (double) x[i] * x[i];
        float[] env = new float[n];
        for (int i = 0; i < n; i++) {
            int lo = max(0, i - win / 2);
            int hi = min(n, i + win / 2 + 1);
            env[i] = sqrt((float) ((prefix[hi] - prefix[lo]) / (hi - lo)));
        }
        return env;
    }

    // Rolling circular mean of an angle array over ±halfWin samples.
    float[] rollingCircularMean(float[] ang, int halfWin) {
        int n = ang.length;
        double[] pc = new double[n + 1];
        double[] ps = new double[n + 1];
        for (int i = 0; i < n; i++) {
            pc[i + 1] = pc[i] + Math.cos(ang[i]);
            ps[i + 1] = ps[i] + Math.sin(ang[i]);
        }
        float[] out = new float[n];
        for (int i = 0; i < n; i++) {
            int lo = max(0, i - halfWin);
            int hi = min(n, i + halfWin + 1);
            out[i] = atan2((float) (ps[hi] - ps[lo]), (float) (pc[hi] - pc[lo]));
        }
        return out;
    }
}
