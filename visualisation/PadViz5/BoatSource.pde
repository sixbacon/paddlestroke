// BoatSource — BoatLog CSV loading and frame store

class BoatFrameData {
    long  ts;
    long  gpsUtcSec;
    float gpsLat, gpsLon;
    float speedMs;
    float cogDeg;
    boolean gpsFix;
    float kayakQw, kayakQx, kayakQy, kayakQz;
    float kayakRoll, kayakPitch, kayakYaw;

    BoatFrameData() { kayakQw = 1; }

    // Field indices for graph: 0=kayakRoll, 1=kayakPitch, 2=kayakYaw, 3=speedMs, 4=cogDeg
    float field(int f) {
        switch (f) {
            case 0: return kayakRoll;
            case 1: return kayakPitch;
            case 2: return kayakYaw;
            case 3: return speedMs;
            case 4: return cogDeg;
            default: return 0;
        }
    }
}

class BoatSource {
    private ArrayList<BoatFrameData> frames = new ArrayList<BoatFrameData>();
    private String                   srcName = "";

    void loadCSV(String path) {
        frames.clear();
        String[] lines = loadStrings(path);
        if (lines == null) { println("Cannot load boat CSV: " + path); return; }
        srcName = path.substring(path.lastIndexOf(java.io.File.separatorChar) + 1);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0 || line.charAt(0) == '#') continue;
            if (line.startsWith("seq")) continue;
            BoatFrameData bfd = parseLine(line);
            if (bfd != null) frames.add(bfd);
        }
        println("BoatLog: loaded " + frames.size() + " frames from " + srcName);
    }

    // BoatLog columns: seq(0), timestamp_ms(1), gps_utc_sec(2), gps_uk_offset(3),
    //   gps_lat(4), gps_lon(5), gps_speed_ms(6), gps_cog_deg(7), gps_fix(8),
    //   kayak_qw(9), kayak_qx(10), kayak_qy(11), kayak_qz(12),
    //   kayak_roll(13), kayak_pitch(14), kayak_yaw(15)
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
            bfd.kayakQw    = float(trim(t[9]));
            bfd.kayakQx    = float(trim(t[10]));
            bfd.kayakQy    = float(trim(t[11]));
            bfd.kayakQz    = float(trim(t[12]));
            bfd.kayakRoll  = float(trim(t[13]));
            bfd.kayakPitch = float(trim(t[14]));
            bfd.kayakYaw   = float(trim(t[15]));
        } catch (Exception e) { return null; }
        return bfd;
    }

    int          frameCount() { return frames.size(); }
    String       sourceName() { return srcName; }

    BoatFrameData frameAt(int idx) {
        if (frames.isEmpty()) return null;
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    long firstGpsUtc() { return frames.isEmpty() ? 0 : frames.get(0).gpsUtcSec; }
    long lastGpsUtc()  { return frames.isEmpty() ? 0 : frames.get(frames.size()-1).gpsUtcSec; }

    // Field range over the whole file
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

    ArrayList<BoatFrameData> getFrames() { return frames; }
}
