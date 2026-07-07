// DataSource — paddle CSV loader for Slice A.
//
// Supports PadDis v8.10 17-col (with rx_ms) and v8.9 16-col (no rx_ms).
// Detects layout from the header line. No orientation corrections are
// applied here — parsing only. The disciplined pipeline is (in
// Model3D.drawWithData): handedness flip → model calibration triple →
// data quaternion → draw.

class FrameData {
    long  ts;
    float qw = 1, qx, qy, qz;
    float roll, pitch, yaw;
    long  gpsUtcSec;
    long  rxMs;
}

class DataSource {
    private ArrayList<FrameData> frames = new ArrayList<FrameData>();
    private String               srcName = "";
    boolean                      hasRxMs = false;

    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
        String[] lines = loadStrings(path);
        if (lines == null) {
            println("DataSource: cannot load " + path);
            return;
        }
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
                if (line.contains("rx_ms")) hasRxMs = true;
                continue;
            }
            FrameData fd = parseLine(line);
            if (fd != null) frames.add(fd);
        }
        println("DataSource: loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (v8.10 rx_ms)" : "  (v8.9 or older)"));
    }

    // v8.10 17-col:  seq, ts, ax, ay, az, qw, qx, qy, qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk, rx_ms
    // v8.9  16-col:  seq, ts, ax, ay, az, qw, qx, qy, qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk
    private FrameData parseLine(String line) {
        String[] t = split(line, ',');
        if (t.length < 12) return null;
        FrameData fd = new FrameData();
        try {
            fd.ts    = Long.parseLong(trim(t[1]));
            fd.qw    = float(trim(t[5]));
            fd.qx    = float(trim(t[6]));
            fd.qy    = float(trim(t[7]));
            fd.qz    = float(trim(t[8]));
            fd.roll  = float(trim(t[9]));
            fd.pitch = float(trim(t[10]));
            fd.yaw   = float(trim(t[11]));
            if (t.length >= 15) fd.gpsUtcSec = Long.parseLong(trim(t[14]));
            if (t.length >= 17) fd.rxMs      = Long.parseLong(trim(t[16]));
        } catch (Exception e) {
            return null;
        }
        return fd;
    }

    int       frameCount() { return frames.size(); }
    String    sourceName() { return srcName; }

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
