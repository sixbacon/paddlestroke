// DataSource — ImuLog (paddle) CSV loading and frame store

class FrameData {
    long    ts;
    float   accelX, accelY, accelZ;
    float   qw, qx, qy, qz;
    float   roll, pitch, yaw;
    int     strokeCount;
    float   cpm;
    boolean hasQuat;
    long    gpsUtcSec;   // 0 if not present or no fix

    FrameData() { qw = 1; qx = qy = qz = 0; hasQuat = false; gpsUtcSec = 0; }

    void recomputeQuat() {
        float cr = cos(radians(roll)  * 0.5f);
        float sr = sin(radians(roll)  * 0.5f);
        float cp = cos(radians(pitch) * 0.5f);
        float sp = sin(radians(pitch) * 0.5f);
        float cy = cos(radians(yaw)   * 0.5f);
        float sy = sin(radians(yaw)   * 0.5f);
        qw = cr*cp*cy + sr*sp*sy;
        qx = sr*cp*cy - cr*sp*sy;
        qy = cr*sp*cy + sr*cp*sy;
        qz = cr*cp*sy - sr*sp*cy;
    }
}

class DataSource {
    private ArrayList<FrameData> frames = new ArrayList<FrameData>();
    private String               srcName = "";

    void loadCSV(String path) {
        frames.clear();
        String[] lines = loadStrings(path);
        if (lines == null) { println("Cannot load: " + path); return; }
        srcName = path.substring(path.lastIndexOf(java.io.File.separatorChar) + 1);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0 || line.charAt(0) == '#') continue;
            if (line.startsWith("timestamp") || line.startsWith("seq")) continue;
            FrameData fd = parseLine(line);
            if (fd != null) frames.add(fd);
        }
        println("ImuLog: loaded " + frames.size() + " frames from " + srcName);
    }

    // Column layouts supported:
    // 17-col (old full, with hz): seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, hz, gps_utc, gps_uk
    // 16-col (new full, no hz):   seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk
    // 15-col (no gps):            seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, hz  (or no hz)
    // 10-col:                     ts, qw..qz, roll, pitch, yaw, sc, cpm
    //  6-col:                     ts, roll, pitch, yaw, sc, cpm
    private FrameData parseLine(String line) {
        String[] t = split(line, ',');
        FrameData fd = new FrameData();
        try {
            if (t.length >= 17) {
                // 17-col: old format with hz at [14], gps at [15],[16]
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
                // t[14] = hz (ignored)
                fd.gpsUtcSec   = Long.parseLong(trim(t[15]));
                fd.hasQuat     = true;
            } else if (t.length == 16) {
                // 16-col: new format without hz, gps at [14],[15]
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
                fd.gpsUtcSec   = Long.parseLong(trim(t[14]));
                fd.hasQuat     = true;
            } else if (t.length >= 15) {
                // 15-col: full without gps
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
                fd.hasQuat     = true;
            } else if (t.length >= 10) {
                fd.ts          = Long.parseLong(trim(t[0]));
                fd.qw          = float(trim(t[1]));
                fd.qx          = float(trim(t[2]));
                fd.qy          = float(trim(t[3]));
                fd.qz          = float(trim(t[4]));
                fd.roll        = float(trim(t[5]));
                fd.pitch       = float(trim(t[6]));
                fd.yaw         = float(trim(t[7]));
                fd.strokeCount = int(trim(t[8]));
                fd.cpm         = float(trim(t[9]));
                fd.hasQuat     = true;
            } else if (t.length >= 6) {
                fd.ts          = Long.parseLong(trim(t[0]));
                fd.roll        = float(trim(t[1]));
                fd.pitch       = float(trim(t[2]));
                fd.yaw         = float(trim(t[3]));
                fd.strokeCount = int(trim(t[4]));
                fd.cpm         = float(trim(t[5]));
                eulerToQuat(fd);
                fd.hasQuat     = false;
            } else {
                return null;
            }
        } catch (Exception e) { return null; }
        return fd;
    }

    private void eulerToQuat(FrameData fd) {
        float cr = cos(radians(fd.roll)  * 0.5f);
        float sr = sin(radians(fd.roll)  * 0.5f);
        float cp = cos(radians(fd.pitch) * 0.5f);
        float sp = sin(radians(fd.pitch) * 0.5f);
        float cy = cos(radians(fd.yaw)   * 0.5f);
        float sy = sin(radians(fd.yaw)   * 0.5f);
        fd.qw = cr * cp * cy + sr * sp * sy;
        fd.qx = sr * cp * cy - cr * sp * sy;
        fd.qy = cr * sp * cy + sr * cp * sy;
        fd.qz = cr * cp * sy - sr * sp * cy;
    }

    int       frameCount() { return frames.size(); }
    String    sourceName() { return srcName; }

    FrameData frameAt(int idx) {
        if (frames.isEmpty()) return new FrameData();
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    long firstTs() { return frames.isEmpty() ? 0 : frames.get(0).ts; }
    long lastTs()  { return frames.isEmpty() ? 1 : frames.get(frames.size() - 1).ts; }

    // Field indices for graph: 0=roll, 1=pitch, 2=yaw, 3=cpm, 4=strokeCount, 5=accelX, 6=accelY, 7=accelZ
    float fieldAt(int fi, int field) {
        FrameData fd = frameAt(fi);
        switch (field) {
            case 0: return fd.roll;
            case 1: return fd.pitch;
            case 2: return fd.yaw;
            case 3: return fd.cpm;
            case 4: return (float) fd.strokeCount;
            case 5: return fd.accelX;
            case 6: return fd.accelY;
            case 7: return fd.accelZ;
            default: return 0;
        }
    }

    float[] fieldRange(int field) {
        if (frames.isEmpty()) return new float[]{-1, 1};
        float mn = Float.MAX_VALUE, mx = -Float.MAX_VALUE;
        for (int i = 0; i < frames.size(); i++) {
            float v = fieldAt(i, field);
            if (v < mn) mn = v;
            if (v > mx) mx = v;
        }
        if (mn == mx) { mn -= 1; mx += 1; }
        return new float[]{mn, mx};
    }

    // Returns the raw frame list for export
    ArrayList<FrameData> getFrames() { return frames; }
}
