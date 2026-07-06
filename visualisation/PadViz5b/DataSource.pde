// DataSource — CSV loading, serial streaming, frame store
// (import processing.serial.* is in PadViz5b.pde — must stay in main tab)

// ── Frame record ──────────────────────────────────────────────────────────────
class FrameData {
    long    ts;
    float   accelX, accelY, accelZ;
    float   qw, qx, qy, qz;
    float   roll, pitch, yaw;
    int     strokeCount;
    float   cpm;
    boolean hasQuat;
    long    gpsUtcSec;   // 0 = no fix or column absent
    long    rxMs;        // CYD-side ESPnow reception ms; 0 if column absent (pre-v8.10)

    FrameData() { qw = 1; qx = qy = qz = 0; hasQuat = false; gpsUtcSec = 0; rxMs = 0; }

    // Recompute quaternion from current roll/pitch/yaw (used after test-mode masking).
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

// ── DataSource ────────────────────────────────────────────────────────────────
class DataSource {
    private ArrayList<FrameData> frames = new ArrayList<FrameData>();
    private String               srcName = "";
    boolean                      hasRxMs = false;   // v8.10+ paddle CSVs

    // Live serial ring buffer (256 entries)
    private final int   LIVE_CAP = 256;
    private FrameData[] liveRing = new FrameData[LIVE_CAP];
    private int         liveHead = 0, liveTail = 0;
    private Serial      port;
    private String      serialBuf = "";

    // ── CSV load ──────────────────────────────────────────────────────────────
    void loadCSV(String path) {
        frames.clear();
        hasRxMs = false;
        String[] lines = loadStrings(path);
        if (lines == null) { println("Cannot load: " + path); return; }
        srcName = path.substring(path.lastIndexOf(java.io.File.separatorChar) + 1);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0 || line.charAt(0) == '#') continue;
            if (line.startsWith("timestamp") || line.startsWith("seq")) {
                // Column-header line — inspect it to pick the right parser branch.
                if (line.contains("rx_ms")) hasRxMs = true;
                continue;
            }
            FrameData fd = parseLine(line);
            if (fd != null) frames.add(fd);
        }
        println("Loaded " + frames.size() + " frames from " + srcName
                + (hasRxMs ? "  (rx_ms sync)" : "  (gps_utc sync)"));
    }

    // Detect column layout and parse one CSV row.
    // v8.10 17-col (rx_ms):       seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk, rx_ms
    // v8.7  17-col (old with hz): seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, hz, gps_utc, gps_uk
    // v8.9  16-col (no hz):       seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, gps_utc, gps_uk
    // v8.5  15-col (no gps):      seq, ts, ax, ay, az, qw..qz, roll, pitch, yaw, sc, cpm, hz
    //       10-col:               ts, qw, qx, qy, qz, roll, pitch, yaw, sc, cpm
    //        6-col:               ts, roll, pitch, yaw, sc, cpm
    // Two 17-col layouts are disambiguated by `hasRxMs`, set from header.
    private FrameData parseLine(String line) {
        String[] t = split(line, ',');
        FrameData fd = new FrameData();
        try {
            if (t.length >= 17 && hasRxMs) {
                // v8.10: rx_ms is the trailing column, no hz
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
                // t[15] = gps_uk_offset (ignored)
                fd.rxMs        = Long.parseLong(trim(t[16]));
                fd.hasQuat     = true;
            } else if (t.length >= 17) {
                // v8.7 old-with-hz
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

    // ── Accessors ─────────────────────────────────────────────────────────────
    int       frameCount() { return frames.size(); }
    String    sourceName() { return srcName; }

    FrameData frameAt(int idx) {
        if (frames.isEmpty()) return new FrameData();
        return frames.get(constrain(idx, 0, frames.size() - 1));
    }

    long firstTs() { return frames.isEmpty() ? 0 : frames.get(0).ts; }
    long lastTs()  { return frames.isEmpty() ? 1 : frames.get(frames.size() - 1).ts; }

    // Raw frame list — needed by SyncMap for the paddle→boat GPS-sec sweep.
    ArrayList<FrameData> getFrames() { return frames; }

    // Field indices — mirror GraphPanel FIELD_NAMES order for paddle source.
    // 0=roll 1=pitch 2=yaw 3=cpm 4=strokeCount 5=accelX 6=accelY 7=accelZ
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

    // ── Live serial ───────────────────────────────────────────────────────────
    void openSerial(PApplet app, String portName, int baud) {
        try { port = new Serial(app, portName, baud); }
        catch (Exception e) { println("Serial error: " + e.getMessage()); }
    }

    void closeSerial() {
        if (port != null) { port.stop(); port = null; }
        serialBuf = "";
    }

    void drainSerial() {
        if (port == null) return;
        while (port.available() > 0) {
            char c = (char) port.read();
            if (c == '\n') {
                processLine(serialBuf.trim());
                serialBuf = "";
            } else {
                serialBuf += c;
            }
        }
    }

    String    lastRawLine    = "";
    int       liveFrameTotal = 0;
    int       liveParseErrors = 0;
    FrameData latestLive     = new FrameData();

    private void processLine(String line) {
        lastRawLine = line;
        if (line.length() == 0 || line.charAt(0) == '#') return;
        FrameData fd = parseLine(line);
        if (fd == null) { liveParseErrors++; return; }
        liveFrameTotal++;
        latestLive = fd;
        int next = (liveHead + 1) % LIVE_CAP;
        if (next == liveTail) liveTail = (liveTail + 1) % LIVE_CAP;
        liveRing[liveHead] = fd;
        liveHead           = next;
    }

    boolean   liveReady()  { return liveHead != liveTail; }
    int       liveCount()  { return (liveHead - liveTail + LIVE_CAP) % LIVE_CAP; }
    FrameData liveLatest() { return latestLive; }
}
