// Sidecar — per-session calibration record. See padviz6_spec.md §7.
//
// Contents (spec §7.5):
//   - Paddle mount offset (roll, pitch degrees).
//   - Boat   mount offset (roll, pitch degrees).
//   - Yaw datum offset — paddle-vs-boat yaw at rest, degrees.
//   - Rest window bounds (frame indices on both sensors), duration, accel-var max.
//   - Confidence tag: "high" | "medium" | "low" | "none".
//   - mag_cal at rest (paddle, boat) — null until Phase 10 firmware lands.
//
// Build path (this file): detect rest window in paddle accel → compute means
// of roll/pitch/yaw over the window on each sensor → derive offsets.
//
// Note on yaw datum. Spec §7.6 keeps mount and yaw datum separate at
// application time. This first-pass builder stores them decomposed in the
// JSON but, for the interactive view, populates PadViz6's qRefPad / qRefBoat
// with the raw mean rest quats so the K-subtraction pipeline renders the
// correction immediately. That gives the same visual result at rest and one
// less code path to validate; the decomposed values in the JSON remain
// authoritative for any post-processing that needs the split.

class Sidecar {
    boolean valid = false;

    float rollOffsetPadDeg   = 0;
    float pitchOffsetPadDeg  = 0;
    float rollOffsetBoatDeg  = 0;
    float pitchOffsetBoatDeg = 0;
    float yawDatumDeg        = 0;    // paddle yaw − boat yaw at rest (wrapped ±180°)

    int   restPadStart  = -1, restPadEnd  = -1;
    int   restBoatStart = -1, restBoatEnd = -1;
    float restDurationS   = 0;
    float restAccelVarMax = 0;
    String confidence = "none";

    int magCalPad  = -1;             // −1 = unknown (pre-Phase-10)
    int magCalBoat = -1;

    // Cached mean rest quats — populated by the builder, consumed by the
    // caller to seed qRefPad / qRefBoat so the display shows the correction
    // straight after build. Not persisted; can be reconstructed from the
    // window bounds + CSV if needed.
    float[] qRestPad  = null;
    float[] qRestBoat = null;

    String sessionDate   = "";
    String recordedAt    = "";
    String paddleCsvName = "";
    String boatCsvName   = "";
    String notes         = "";

    void save(String path) {
        JSONObject root = new JSONObject();
        root.setString("session",     sessionDate);
        root.setString("recorded_at", recordedAt);
        root.setString("paddle_csv",  paddleCsvName);
        root.setString("boat_csv",    boatCsvName);

        JSONObject rw = new JSONObject();
        rw.setInt("paddle_frame_start", restPadStart);
        rw.setInt("paddle_frame_end",   restPadEnd);
        rw.setInt("boat_frame_start",   restBoatStart);
        rw.setInt("boat_frame_end",     restBoatEnd);
        rw.setFloat("duration_s",       restDurationS);
        rw.setFloat("accel_var_max",    restAccelVarMax);
        rw.setString("confidence",      confidence);
        root.setJSONObject("rest_window", rw);

        JSONObject padOff = new JSONObject();
        padOff.setFloat("roll",  rollOffsetPadDeg);
        padOff.setFloat("pitch", pitchOffsetPadDeg);
        root.setJSONObject("paddle_mount_offset_deg", padOff);

        JSONObject boatOff = new JSONObject();
        boatOff.setFloat("roll",  rollOffsetBoatDeg);
        boatOff.setFloat("pitch", pitchOffsetBoatDeg);
        root.setJSONObject("boat_mount_offset_deg", boatOff);

        root.setFloat("yaw_datum_offset_deg", yawDatumDeg);

        // Only set the sub-keys we actually know. Missing = unknown; the
        // reader treats absence and null the same way (see loadFromFile).
        JSONObject mag = new JSONObject();
        if (magCalPad  >= 0) mag.setInt("paddle", magCalPad);
        if (magCalBoat >= 0) mag.setInt("boat",   magCalBoat);
        root.setJSONObject("mag_cal_status_at_rest", mag);

        root.setString("notes", notes);
        saveJSONObject(root, path);
    }

    boolean loadFromFile(String path) {
        try {
            JSONObject root = loadJSONObject(path);
            if (root == null) return false;
            sessionDate   = root.hasKey("session")     ? root.getString("session")     : "";
            recordedAt    = root.hasKey("recorded_at") ? root.getString("recorded_at") : "";
            paddleCsvName = root.hasKey("paddle_csv")  ? root.getString("paddle_csv")  : "";
            boatCsvName   = root.hasKey("boat_csv")    ? root.getString("boat_csv")    : "";

            JSONObject rw = root.getJSONObject("rest_window");
            restPadStart    = rw.getInt("paddle_frame_start");
            restPadEnd      = rw.getInt("paddle_frame_end");
            restBoatStart   = rw.getInt("boat_frame_start");
            restBoatEnd     = rw.getInt("boat_frame_end");
            restDurationS   = rw.getFloat("duration_s");
            restAccelVarMax = rw.getFloat("accel_var_max");
            confidence      = rw.getString("confidence");

            JSONObject pad = root.getJSONObject("paddle_mount_offset_deg");
            rollOffsetPadDeg  = pad.getFloat("roll");
            pitchOffsetPadDeg = pad.getFloat("pitch");
            JSONObject boat = root.getJSONObject("boat_mount_offset_deg");
            rollOffsetBoatDeg  = boat.getFloat("roll");
            pitchOffsetBoatDeg = boat.getFloat("pitch");
            yawDatumDeg = root.getFloat("yaw_datum_offset_deg");

            if (root.hasKey("mag_cal_status_at_rest")) {
                JSONObject mag = root.getJSONObject("mag_cal_status_at_rest");
                magCalPad  = (mag.hasKey("paddle") && !mag.isNull("paddle"))
                              ? mag.getInt("paddle") : -1;
                magCalBoat = (mag.hasKey("boat")   && !mag.isNull("boat"))
                              ? mag.getInt("boat")   : -1;
            }
            notes = root.hasKey("notes") ? root.getString("notes") : "";
            valid = true;
            return true;
        } catch (Exception e) {
            println("Sidecar load failed: " + e.getMessage());
            return false;
        }
    }
}

// ── Rest-window detection ──────────────────────────────────────────────────
//
// Sliding 1-s (100-frame) window over paddle accel. A window is "at rest" if
// the vector magnitude of its mean is within MAG_TOL of g and per-axis
// variance is below VAR_TOL. First contiguous run of "at rest" flags with
// duration >= MIN_DUR frames is the rest window.

final float G           = 9.81;
final float MAG_TOL     = 0.15;    // m/s²   — real data noisier than spec's 0.1
final float VAR_TOL     = 0.05;    // (m/s²)² — same rationale
final int   WIN_SIZE    = 100;     // 1 s at 100 Hz
final int   MIN_REST_DUR = 300;    // 3 s at 100 Hz

// Returns { start, end } in paddle-frame indices, or null if no window found.
// Also writes the max per-axis variance encountered inside the found window
// into out[2] (0 if null).
//
// `searchStart` is the earliest frame the scan will consider — set from the
// current playback frame so the user can seek to the intended rest moment
// before pressing C. 0 restores the "scan from beginning" behaviour.
int[] detectRestWindow(DataSource pad, int searchStart, float[] outMaxVar) {
    ArrayList<FrameData> frames = pad.getFrames();
    int n = frames.size();
    if (n < WIN_SIZE + MIN_REST_DUR) return null;

    int runStart = -1;
    float maxVarInRun = 0;

    int i0 = max(WIN_SIZE / 2, searchStart);
    for (int i = i0; i < n - WIN_SIZE / 2; i++) {
        float[] mv = windowMeanAndVar(frames, i, WIN_SIZE);
        float mx = mv[0], my = mv[1], mz = mv[2];
        float vx = mv[3], vy = mv[4], vz = mv[5];
        float mag = sqrt(mx*mx + my*my + mz*mz);

        boolean atRest = (abs(mag - G) < MAG_TOL)
                      && (vx < VAR_TOL) && (vy < VAR_TOL) && (vz < VAR_TOL);
        if (atRest) {
            if (runStart < 0) { runStart = i; maxVarInRun = 0; }
            float mvMax = max(max(vx, vy), vz);
            if (mvMax > maxVarInRun) maxVarInRun = mvMax;
            if (i - runStart >= MIN_REST_DUR) {
                outMaxVar[0] = maxVarInRun;
                return new int[]{ runStart, i };
            }
        } else {
            runStart = -1;
            maxVarInRun = 0;
        }
    }
    return null;
}

// Returns { mx, my, mz, vx, vy, vz } for the accel window centred on i.
float[] windowMeanAndVar(ArrayList<FrameData> frames, int i, int w) {
    int lo = i - w / 2, hi = i + w / 2;
    float sx = 0, sy = 0, sz = 0;
    for (int j = lo; j < hi; j++) {
        FrameData f = frames.get(j);
        sx += f.accelX; sy += f.accelY; sz += f.accelZ;
    }
    float mx = sx / w, my = sy / w, mz = sz / w;
    float vx = 0, vy = 0, vz = 0;
    for (int j = lo; j < hi; j++) {
        FrameData f = frames.get(j);
        vx += (f.accelX - mx) * (f.accelX - mx);
        vy += (f.accelY - my) * (f.accelY - my);
        vz += (f.accelZ - mz) * (f.accelZ - mz);
    }
    return new float[]{ mx, my, mz, vx / w, vy / w, vz / w };
}

// ── Mean roll / pitch / yaw over a window ─────────────────────────────────
//
// Roll and pitch use straight arithmetic mean (small magnitudes, no wrap).
// Yaw uses vector mean (sum of cos, sin components → atan2) because it wraps
// at ±180°.

float[] meanRollPitchYawPaddle(DataSource pad, int lo, int hi) {
    ArrayList<FrameData> frames = pad.getFrames();
    return meanRPYFromFrames(frames.subList(lo, hi + 1), 0);
}

float[] meanRollPitchYawBoat(BoatSource boat, int lo, int hi) {
    ArrayList<BoatFrameData> frames = boat.getFrames();
    return meanRPYFromFrames(frames.subList(lo, hi + 1), 1);
}

// src = 0 (paddle FrameData) or 1 (boat BoatFrameData).
float[] meanRPYFromFrames(java.util.List<?> frames, int src) {
    float rollSum = 0, pitchSum = 0;
    float yc = 0, ys = 0;
    int n = 0;
    for (Object o : frames) {
        float roll, pitch, yaw;
        if (src == 0) {
            FrameData f = (FrameData) o;
            roll = f.roll; pitch = f.pitch; yaw = f.yaw;
        } else {
            BoatFrameData f = (BoatFrameData) o;
            roll = f.roll; pitch = f.pitch; yaw = f.yaw;
        }
        rollSum  += roll;
        pitchSum += pitch;
        yc       += cos(radians(yaw));
        ys       += sin(radians(yaw));
        n++;
    }
    if (n == 0) return new float[]{ 0, 0, 0 };
    return new float[] {
        rollSum  / n,
        pitchSum / n,
        degrees(atan2(ys, yc))
    };
}

// ── Builder entry point ────────────────────────────────────────────────────

Sidecar buildSidecar(DataSource pad, BoatSource boat, SyncMap sync, int searchStart) {
    Sidecar s = new Sidecar();
    s.paddleCsvName = (pad  != null) ? pad.sourceName()  : "";
    s.boatCsvName   = (boat != null) ? boat.sourceName() : "";
    s.recordedAt    = nowIsoLocal();
    s.sessionDate   = s.recordedAt.substring(0, 10);

    if (pad == null || pad.frameCount() == 0) {
        s.notes = "No paddle CSV loaded.";
        return s;
    }
    if (pad.getFrames().get(0).accelX == 0 && pad.getFrames().get(0).accelY == 0
        && pad.getFrames().get(0).accelZ == 0) {
        // Very rough sanity check: reduced-column CSVs don't populate accel.
        s.notes = "Paddle CSV has no accelerometer data — need PadDis v8.10 full-column log.";
        return s;
    }

    float[] outMaxVar = new float[]{ 0 };
    int[]   rw = detectRestWindow(pad, searchStart, outMaxVar);
    if (rw == null) {
        s.notes = "No rest window detected after frame " + searchStart
                + " (need >= 3 s of |a|~9.81 and low variance in paddle accel).";
        return s;
    }
    s.restPadStart    = rw[0];
    s.restPadEnd      = rw[1];
    s.restDurationS   = (rw[1] - rw[0]) * 0.01f;   // 100 Hz assumption
    s.restAccelVarMax = outMaxVar[0];

    float[] padMean = meanRollPitchYawPaddle(pad, rw[0], rw[1]);
    s.rollOffsetPadDeg  = padMean[0];
    s.pitchOffsetPadDeg = padMean[1];
    float padYawAtRest  = padMean[2];

    s.qRestPad = pad.meanQuat(rw[0], rw[1]);

    if (boat == null || boat.frameCount() == 0 || sync == null) {
        s.confidence = "medium";
        s.notes = "Paddle rest window OK but no boat CSV loaded — mount offset only, no yaw datum.";
        s.valid = true;
        return s;
    }

    int bLo = sync.boatIdxFor(rw[0]);
    int bHi = sync.boatIdxFor(rw[1]);
    if (bLo < 0 || bHi < 0 || bHi <= bLo) {
        s.confidence = "medium";
        s.notes = "Paddle rest window OK but boat sync unavailable in that range — no yaw datum.";
        s.valid = true;
        return s;
    }
    s.restBoatStart = bLo;
    s.restBoatEnd   = bHi;

    float[] boatMean = meanRollPitchYawBoat(boat, bLo, bHi);
    s.rollOffsetBoatDeg  = boatMean[0];
    s.pitchOffsetBoatDeg = boatMean[1];
    float boatYawAtRest  = boatMean[2];

    s.qRestBoat = boat.meanQuat(bLo, bHi);

    float d = padYawAtRest - boatYawAtRest;
    while (d >  180) d -= 360;
    while (d < -180) d += 360;
    s.yawDatumDeg = d;

    s.confidence = "high";
    s.valid = true;
    return s;
}

// Local-time timestamp in ISO-8601 form. Not UTC (uses local zone) — good
// enough for a session record. Suffix uses no offset.
String nowIsoLocal() {
    return String.format("%04d-%02d-%02dT%02d:%02d:%02d",
                         year(), month(), day(), hour(), minute(), second());
}
