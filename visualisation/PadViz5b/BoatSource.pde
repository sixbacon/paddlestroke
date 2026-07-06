// BoatSource — BoatLog CSV loading and frame store.
//
// BoatLog v1.0 columns (see CLAUDE.md):
//   seq, timestamp_ms, gps_utc_sec, gps_uk_offset,
//   gps_lat, gps_lon, gps_speed_ms, gps_cog_deg, gps_fix,
//   kayak_qw, kayak_qx, kayak_qy, kayak_qz,
//   kayak_roll, kayak_pitch, kayak_yaw

class BoatFrameData {
    long  ts;
    long  gpsUtcSec;
    float gpsLat, gpsLon;
    float speedMs;
    float cogDeg;
    boolean gpsFix;
    float kayakQw, kayakQx, kayakQy, kayakQz;
    float kayakRoll, kayakPitch, kayakYaw;
    long  rxMs;    // CYD-side ESPnow reception ms; 0 if column absent (pre-v8.10)

    BoatFrameData() { kayakQw = 1; rxMs = 0; }

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
    boolean                          hasRxMs = false;   // v8.10+ boat CSVs

    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
        String[] lines = loadStrings(path);
        if (lines == null) { println("Cannot load boat CSV: " + path); return; }
        srcName = path.substring(path.lastIndexOf(java.io.File.separatorChar) + 1);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0 || line.charAt(0) == '#') continue;
            if (line.startsWith("seq")) {
                if (line.contains("rx_ms")) hasRxMs = true;
                continue;
            }
            BoatFrameData bfd = parseLine(line);
            if (bfd != null) frames.add(bfd);
        }
        println("BoatLog: loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (rx_ms sync)" : "  (gps_utc sync)"));
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
            bfd.kayakQw    = float(trim(t[9]));
            bfd.kayakQx    = float(trim(t[10]));
            bfd.kayakQy    = float(trim(t[11]));
            bfd.kayakQz    = float(trim(t[12]));
            bfd.kayakRoll  = float(trim(t[13]));
            bfd.kayakPitch = float(trim(t[14]));
            bfd.kayakYaw   = float(trim(t[15]));
            if (t.length >= 17) bfd.rxMs = Long.parseLong(trim(t[16]));
        } catch (Exception e) { return null; }
        return bfd;
    }

    int          frameCount() { return frames.size(); }
    String       sourceName() { return srcName; }

    BoatFrameData frameAt(int idx) {
        if (frames.isEmpty()) return null;
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    // Whole-file range for auto-scaling a graph trace.
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
