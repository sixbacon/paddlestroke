// DataSource — paddle CSV loader for Slice A.
//
// Supports PadDis v8.10 17-col (with rx_ms) and v8.9 16-col (no rx_ms).
// Detects layout from the header line. No orientation corrections are
// applied here — parsing only. The disciplined pipeline is (in
// Model3D.drawWithData): handedness flip → model calibration triple →
// data quaternion → draw.

class FrameData {
    long  ts;
    float accelX, accelY, accelZ;
    float qw = 1, qx, qy, qz;
    float roll, pitch, yaw;
    int   strokeCount;
    float cpm;
    long  gpsUtcSec;
    long  rxMs;

    // Game Rotation Vector (mag-free quaternion) — PadDis v8.13+ 22-col
    // files only (identity otherwise). Used by CatchEvents for the
    // relative-yaw path (firmware spec §16.11: fused yaw carries an
    // in-band cycle-periodic mag artefact; GRV does not).
    float grvQw = 1, grvQx, grvQy, grvQz;

    // Paddle centre offset from the shaft rest position (metres, world_LH
    // = sensor Z-up frame). Populated by DataSource.computePaddleCentreMotion
    // as a post-pass over the loaded frames. Consumed by the render code in
    // Slices A / C to translate the paddle mesh so its centre visually drops
    // toward the in-water blade and lifts back toward centre in the air.
    float posX = 0, posY = 0, posZ = 0;

    // Field indices — mirror GraphPanel FIELD_NAMES order (paddle side).
    // 0=roll 1=pitch 2=yaw 3=cpm 4=strokeCount 5=accelX 6=accelY 7=accelZ
    float field(int f) {
        switch (f) {
            case 0: return roll;
            case 1: return pitch;
            case 2: return yaw;
            case 3: return cpm;
            case 4: return (float) strokeCount;
            case 5: return accelX;
            case 6: return accelY;
            case 7: return accelZ;
            default: return 0;
        }
    }
}

class DataSource {
    private ArrayList<FrameData> frames = new ArrayList<FrameData>();
    private String               srcName = "";
    private String               srcPath = "";
    boolean                      hasRxMs = false;
    boolean                      hasGrv  = false;

    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
        hasGrv  = false;
        String[] lines = loadStrings(path);
        if (lines == null) {
            println("DataSource: cannot load " + path);
            return;
        }
        srcPath = path;
        // Windows path separator handling.
        int cut = max(path.lastIndexOf('\\'), path.lastIndexOf('/'));
        srcName = (cut >= 0) ? path.substring(cut + 1) : path;

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0) continue;
            // Strip a UTF-8 BOM if present (Windows exports include one).
            if (line.charAt(0) == '﻿') line = line.substring(1);
            if (line.length() == 0)      continue;
            if (line.charAt(0) == '#')    continue;
            if (line.startsWith("seq") || line.startsWith("timestamp")) {
                if (line.contains("rx_ms"))  hasRxMs = true;
                if (line.contains("grv_qw")) hasGrv  = true;
                continue;
            }
            FrameData fd = parseLine(line);
            if (fd != null) frames.add(fd);
        }
        println("DataSource: loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (rx_ms)" : "  (v8.9 or older)")
                + (hasGrv  ? " (grv)"    : ""));
        computePaddleCentreMotion();
    }

    // Estimate the paddle-shaft-centre displacement (metres, sensor world_LH
    // frame with Z up) from the accelerometer stream. Pipeline per axis:
    //
    //   1. Rotate body-frame accel to world using the frame quaternion.
    //   2. Subtract gravity (0, 0, +g).
    //   3. First-order HPF the linear accel  — kills any residual bias so
    //      the integrators can't run away.
    //   4. Integrate to velocity.
    //   5. HPF the velocity — kills the accumulated bias from step 4.
    //   6. Integrate to position.
    //   7. HPF the position — the final safety net against slow drift.
    //   8. Clamp each axis to ±MAX_OFFSET.
    //
    // Filter cutoff (~0.3 Hz) sits below the ~0.5–1 Hz stroke band, so the
    // AC swing passes through cleanly while DC and slow drift are removed.
    // Naive leaky integrators fail here: their DC gain is bounded but
    // large, and gravity-subtraction residuals of a fraction of a m/s²
    // saturate the ±0.3 m clamp within seconds.
    //
    // This is a display-only estimate. Over long timescales it decays to
    // zero rather than tracking true position (which would need mag- and
    // GPS-aided INS). For visualising the centre swing paired with the
    // stroke, the AC-band behaviour is what matters.
    void computePaddleCentreMotion() {
        if (frames.isEmpty()) return;
        final float G          = 9.81f;
        final float FC_HZ      = 0.3f;     // HPF cutoff below stroke band
        final float DT_NOM     = 0.01f;    // 100 Hz nominal
        final float ALPHA      = 1 - TWO_PI * FC_HZ * DT_NOM;   // ~0.981
        final float MAX_OFFSET = 0.3f;     // metres, per user spec

        // First-order HPF state: y[n] = ALPHA * (y[n-1] + x[n] - x[n-1]).
        // Three cascade stages: linear-accel HPF, velocity HPF, position HPF.
        float[] laPrev = {0,0,0}, haPrev = {0,0,0};
        float[] v      = {0,0,0}, vPrev  = {0,0,0}, hvPrev = {0,0,0};
        float[] p      = {0,0,0}, pPrev  = {0,0,0}, hpPrev = {0,0,0};

        long prevTs = frames.get(0).ts;
        for (FrameData f : frames) {
            float dt = (f.ts - prevTs) * 0.001f;
            if (dt <= 0 || dt > 0.05f) dt = DT_NOM;
            prevTs = f.ts;

            // R(q) * a_body  — same rotation matrix used in Model3D.applyQuat.
            float xx = f.qx*f.qx, yy = f.qy*f.qy, zz = f.qz*f.qz;
            float xy = f.qx*f.qy, xz = f.qx*f.qz, yz = f.qy*f.qz;
            float wx = f.qw*f.qx, wy = f.qw*f.qy, wz = f.qw*f.qz;
            float wAx = (1 - 2*(yy + zz))*f.accelX
                      +      2*(xy - wz) *f.accelY
                      +      2*(xz + wy) *f.accelZ;
            float wAy =      2*(xy + wz) *f.accelX
                      + (1 - 2*(xx + zz))*f.accelY
                      +      2*(yz - wx) *f.accelZ;
            float wAz =      2*(xz - wy) *f.accelX
                      +      2*(yz + wx) *f.accelY
                      + (1 - 2*(xx + yy))*f.accelZ;

            float[] la = { wAx, wAy, wAz - G };

            for (int i = 0; i < 3; i++) {
                float ha = ALPHA * (haPrev[i] + la[i] - laPrev[i]);
                laPrev[i] = la[i];
                haPrev[i] = ha;

                v[i] += ha * dt;
                float hv = ALPHA * (hvPrev[i] + v[i] - vPrev[i]);
                vPrev[i]  = v[i];
                hvPrev[i] = hv;

                p[i] += hv * dt;
                float hp = ALPHA * (hpPrev[i] + p[i] - pPrev[i]);
                pPrev[i]  = p[i];
                hpPrev[i] = hp;

                float clamped = constrain(hp, -MAX_OFFSET, MAX_OFFSET);
                if      (i == 0) f.posX = clamped;
                else if (i == 1) f.posY = clamped;
                else             f.posZ = clamped;
            }
        }
    }

    // v8.10 17-col:  seq, ts, ax, ay, az, qw, qx, qy, qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk, rx_ms
    // v8.9  16-col:  seq, ts, ax, ay, az, qw, qx, qy, qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk
    private FrameData parseLine(String line) {
        String[] t = split(line, ',');
        if (t.length < 14) return null;
        FrameData fd = new FrameData();
        try {
            fd.ts          = Long.parseLong(trim(t[1]));
            fd.accelX      = float(trim(t[2]));
            fd.accelY      = float(trim(t[3]));
            fd.accelZ      = float(trim(t[4]));
            fd.qw          = float(trim(t[5]));
            fd.qx          = float(trim(t[6]));
            fd.qy          = float(trim(t[7]));
            fd.qz          = float(trim(t[8]));
            fd.roll        = float(trim(t[9]));
            fd.pitch       = float(trim(t[10]));
            fd.yaw         = float(trim(t[11]));
            fd.strokeCount = int(trim(t[12]));
            fd.cpm         = float(trim(t[13]));
            if (t.length >= 15) fd.gpsUtcSec = Long.parseLong(trim(t[14]));
            if (t.length >= 17) fd.rxMs      = Long.parseLong(trim(t[16]));
            // v8.13 22-col: 17 = mag_cal, 18..21 = grv_qw..grv_qz.
            if (t.length >= 22) {
                fd.grvQw = float(trim(t[18]));
                fd.grvQx = float(trim(t[19]));
                fd.grvQy = float(trim(t[20]));
                fd.grvQz = float(trim(t[21]));
            }
        } catch (Exception e) {
            return null;
        }
        return fd;
    }

    int       frameCount() { return frames.size(); }
    String    sourceName() { return srcName; }
    String    sourcePath() { return srcPath; }
    ArrayList<FrameData> getFrames() { return frames; }

    // Whole-file min/max of the given field index (see FrameData.field()).
    // Used by GraphPanel for auto-scaling.
    float fieldAt(int frameIdx, int field) { return frameAt(frameIdx).field(field); }

    float[] fieldRange(int field) {
        if (frames.isEmpty()) return new float[]{-1, 1};
        float mn = Float.MAX_VALUE, mx = -Float.MAX_VALUE;
        for (int i = 0; i < frames.size(); i++) {
            float v = frames.get(i).field(field);
            if (v < mn) mn = v;
            if (v > mx) mx = v;
        }
        if (mn == mx) { mn -= 1; mx += 1; }
        return new float[]{mn, mx};
    }

    FrameData frameAt(int idx) {
        if (frames.isEmpty()) return new FrameData();
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    // Mean quaternion over [startFrame..endFrame] inclusive.
    // Simple element-wise mean with antipodal-sign correction (flip q if
    // its dot with the running mean is negative). Adequate for near-rest
    // windows where the spread is a few degrees; not suitable for large
    // angular ranges. Returns identity if the window is empty.
    float[] meanQuat(int startFrame, int endFrame) {
        int lo = max(0, startFrame);
        int hi = min(frames.size() - 1, endFrame);
        float sw = 0, sx = 0, sy = 0, sz = 0;
        int n = 0;
        for (int i = lo; i <= hi; i++) {
            FrameData f = frames.get(i);
            float qw = f.qw, qx = f.qx, qy = f.qy, qz = f.qz;
            if (n > 0 && (sw*qw + sx*qx + sy*qy + sz*qz) < 0) {
                qw = -qw; qx = -qx; qy = -qy; qz = -qz;
            }
            sw += qw; sx += qx; sy += qy; sz += qz;
            n++;
        }
        float mag = sqrt(sw*sw + sx*sx + sy*sy + sz*sz);
        if (mag < 1e-6) return new float[] { 1, 0, 0, 0 };
        return new float[] { sw/mag, sx/mag, sy/mag, sz/mag };
    }
}
