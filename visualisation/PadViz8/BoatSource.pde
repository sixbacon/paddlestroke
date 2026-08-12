// BoatSource — BoatLog CSV loader for Slice B.
//
// Supports PadDis v8.10 17-col boat CSV (with rx_ms) and older 16-col
// boat CSVs. Detects layout from the header line. No orientation
// corrections applied here — parsing only.
//
// v8.10 columns (17):
//   seq, timestamp_ms, gps_utc_sec, gps_uk_offset,
//   gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix,
//   kayak_qw, kayak_qx, kayak_qy, kayak_qz,
//   kayak_roll, kayak_pitch, kayak_yaw, rx_ms

class BoatFrameData {
    long    ts;
    long    gpsUtcSec;
    float   gpsLat, gpsLon;
    float   speedMs;
    float   cogDeg;
    boolean gpsFix;
    float   qw = 1, qx, qy, qz;
    float   roll, pitch, yaw;
    long    rxMs;

    // Boat Game Rotation Vector — PadDis v8.13+ 25-col files only.
    float   grvQw = 1, grvQx, grvQy, grvQz;

    // Field indices for GraphPanel: 0=roll, 1=pitch, 2=yaw, 3=speedMs, 4=cogDeg.
    float field(int f) {
        switch (f) {
            case 0: return roll;
            case 1: return pitch;
            case 2: return yaw;
            case 3: return speedMs;
            case 4: return cogDeg;
            default: return 0;
        }
    }
}

class BoatSource {
    private ArrayList<BoatFrameData> frames = new ArrayList<BoatFrameData>();
    private String                   srcName = "";
    boolean                          hasRxMs = false;
    boolean                          hasGrv  = false;

    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
        hasGrv  = false;
        String[] lines = loadStrings(path);
        if (lines == null) {
            println("BoatSource: cannot load " + path);
            return;
        }
        int cut = max(path.lastIndexOf('\\'), path.lastIndexOf('/'));
        srcName = (cut >= 0) ? path.substring(cut + 1) : path;

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0) continue;
            if (line.charAt(0) == '﻿') line = line.substring(1);   // BOM
            if (line.length() == 0)      continue;
            if (line.charAt(0) == '#')    continue;
            if (line.startsWith("seq") || line.startsWith("timestamp")) {
                if (line.contains("rx_ms"))       hasRxMs = true;
                if (line.contains("boat_grv_qw")) hasGrv  = true;
                continue;
            }
            BoatFrameData bfd = parseLine(line);
            if (bfd != null) frames.add(bfd);
        }
        println("BoatSource: loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (rx_ms)" : "  (v8.9 or older)")
                + (hasGrv  ? " (grv)"    : ""));
    }

    private BoatFrameData parseLine(String line) {
        String[] t = split(line, ',');
        if (t.length < 16) return null;
        BoatFrameData bfd = new BoatFrameData();
        try {
            bfd.ts         = Long.parseLong(trim(t[1]));
            bfd.gpsUtcSec  = Long.parseLong(trim(t[2]));
            bfd.gpsLat     = float(trim(t[4]));
            bfd.gpsLon     = float(trim(t[5]));
            bfd.speedMs    = float(trim(t[6]));
            bfd.cogDeg     = float(trim(t[7]));
            bfd.gpsFix     = int(trim(t[8])) != 0;
            bfd.qw         = float(trim(t[9]));
            bfd.qx         = float(trim(t[10]));
            bfd.qy         = float(trim(t[11]));
            bfd.qz         = float(trim(t[12]));
            bfd.roll       = float(trim(t[13]));
            bfd.pitch      = float(trim(t[14]));
            bfd.yaw        = float(trim(t[15]));
            if (t.length >= 17) bfd.rxMs = Long.parseLong(trim(t[16]));
            // v8.13 25-col: 17..19 boat_accel, 20 mag_cal, 21..24 boat_grv.
            if (t.length >= 25) {
                bfd.grvQw = float(trim(t[21]));
                bfd.grvQx = float(trim(t[22]));
                bfd.grvQy = float(trim(t[23]));
                bfd.grvQz = float(trim(t[24]));
            }
        } catch (Exception e) {
            return null;
        }
        return bfd;
    }

    int           frameCount() { return frames.size(); }
    String        sourceName() { return srcName; }
    ArrayList<BoatFrameData> getFrames() { return frames; }

    // Whole-file min/max of the given field index (see BoatFrameData.field()).
    float[] fieldRange(int field) {
        if (frames.isEmpty()) return new float[]{-1, 1};
        float mn = Float.MAX_VALUE, mx = -Float.MAX_VALUE;
        for (BoatFrameData bfd : frames) {
            float v = bfd.field(field);
            if (v < mn) mn = v;
            if (v > mx) mx = v;
        }
        if (mn == mx) { mn -= 1; mx += 1; }
        return new float[]{mn, mx};
    }

    BoatFrameData frameAt(int idx) {
        if (frames.isEmpty()) return new BoatFrameData();
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    // A frame carries a usable GPS position: it has a fix and plausible,
    // non-null-island coordinates. Used by the Track view (v0.26, spec §15).
    boolean validFix(BoatFrameData f) {
        return f != null && f.gpsFix
            && abs(f.gpsLat) <= 90 && abs(f.gpsLon) <= 180
            && !(abs(f.gpsLat) < 1e-6 && abs(f.gpsLon) < 1e-6);
    }

    boolean hasGpsFix() {
        for (BoatFrameData f : frames) if (validFix(f)) return true;
        return false;
    }

    // Whole-file lat/lon bounds over valid-fix frames: { latMin, latMax,
    // lonMin, lonMax }, or null if there are no valid fixes. The Track view
    // scans this once (cached) to frame the map (spec §15).
    float[] latLonRange() {
        float latMn =  1e9, latMx = -1e9, lonMn =  1e9, lonMx = -1e9;
        int n = 0;
        for (BoatFrameData f : frames) {
            if (!validFix(f)) continue;
            latMn = min(latMn, f.gpsLat);  latMx = max(latMx, f.gpsLat);
            lonMn = min(lonMn, f.gpsLon);  lonMx = max(lonMx, f.gpsLon);
            n++;
        }
        if (n == 0) return null;
        return new float[]{ latMn, latMx, lonMn, lonMx };
    }

    // Mean quaternion over a window (antipodal-sign corrected, renormalised).
    float[] meanQuat(int startFrame, int endFrame) {
        int lo = max(0, startFrame);
        int hi = min(frames.size() - 1, endFrame);
        float sw = 0, sx = 0, sy = 0, sz = 0;
        int n = 0;
        for (int i = lo; i <= hi; i++) {
            BoatFrameData f = frames.get(i);
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

    // GRV counterpart of meanQuat() — see DataSource.meanQuatGrv() for the
    // rationale. Caller must check hasGrv first.
    float[] meanQuatGrv(int startFrame, int endFrame) {
        int lo = max(0, startFrame);
        int hi = min(frames.size() - 1, endFrame);
        float sw = 0, sx = 0, sy = 0, sz = 0;
        int n = 0;
        for (int i = lo; i <= hi; i++) {
            BoatFrameData f = frames.get(i);
            float qw = f.grvQw, qx = f.grvQx, qy = f.grvQy, qz = f.grvQz;
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
