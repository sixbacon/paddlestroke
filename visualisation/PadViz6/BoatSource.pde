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
}

class BoatSource {
    private ArrayList<BoatFrameData> frames = new ArrayList<BoatFrameData>();
    private String                   srcName = "";
    boolean                          hasRxMs = false;

    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
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
                if (line.contains("rx_ms")) hasRxMs = true;
                continue;
            }
            BoatFrameData bfd = parseLine(line);
            if (bfd != null) frames.add(bfd);
        }
        println("BoatSource: loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (v8.10 rx_ms)" : "  (v8.9 or older)"));
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
        } catch (Exception e) {
            return null;
        }
        return bfd;
    }

    int           frameCount() { return frames.size(); }
    String        sourceName() { return srcName; }

    BoatFrameData frameAt(int idx) {
        if (frames.isEmpty()) return new BoatFrameData();
        return frames.get(constrain(idx, 0, frames.size() - 1));
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
}
