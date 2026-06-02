// DataSource — CSV loading, serial streaming, frame store
import processing.serial.*;

// ── Frame record ──────────────────────────────────────────────────────────────
class FrameData {
    long    ts;
    float   qw, qx, qy, qz;
    float   roll, pitch, yaw;
    int     strokeCount;
    float   cpm;
    boolean hasQuat;

    FrameData() { qw = 1; qx = qy = qz = 0; hasQuat = false; }
}

// ── DataSource ────────────────────────────────────────────────────────────────
class DataSource {
    private ArrayList<FrameData> frames = new ArrayList<FrameData>();
    private String               srcName = "";

    // Live serial ring buffer (256 entries)
    private final int   LIVE_CAP = 256;
    private FrameData[] liveRing = new FrameData[LIVE_CAP];
    private int         liveHead = 0, liveTail = 0;
    private Serial      port;
    private String      serialBuf = "";

    // ── CSV load ──────────────────────────────────────────────────────────────
    void loadCSV(String path) {
        frames.clear();
        String[] lines = loadStrings(path);
        if (lines == null) { println("Cannot load: " + path); return; }
        srcName = path.substring(path.lastIndexOf(java.io.File.separatorChar) + 1);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.length() == 0 || line.charAt(0) == '#') continue;
            // Skip header rows
            if (line.startsWith("timestamp") || line.startsWith("seq")) continue;
            FrameData fd = parseLine(line);
            if (fd != null) frames.add(fd);
        }
        println("Loaded " + frames.size() + " frames from " + srcName);
    }

    // Detect column layout and parse one CSV row.
    // Old 6-col:  timestamp_ms, roll, pitch, yaw, stroke_count, cpm
    // New 10-col: timestamp_ms, q_w, q_x, q_y, q_z, roll, pitch, yaw, stroke_count, cpm
    private FrameData parseLine(String line) {
        String[] t = split(line, ',');
        FrameData fd = new FrameData();
        try {
            if (t.length >= 10) {
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

    // Roll/pitch/yaw (degrees, ZYX) → unit quaternion stored in fd
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

    // Field by index: 0=roll 1=pitch 2=yaw 3=cpm 4=stroke_count
    float fieldAt(int fi, int field) {
        FrameData fd = frameAt(fi);
        switch (field) {
            case 0: return fd.roll;
            case 1: return fd.pitch;
            case 2: return fd.yaw;
            case 3: return fd.cpm;
            case 4: return (float) fd.strokeCount;
            default: return 0;
        }
    }

    // Min/max of a field over the full dataset
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

    private void processLine(String line) {
        if (line.length() == 0 || line.charAt(0) == '#') return;
        FrameData fd = parseLine(line);
        if (fd == null) return;
        int next = (liveHead + 1) % LIVE_CAP;
        if (next != liveTail) {
            liveRing[liveHead] = fd;
            liveHead           = next;
        }
    }

    boolean   liveReady()  { return liveHead != liveTail; }
    int       liveCount()  { return (liveHead - liveTail + LIVE_CAP) % LIVE_CAP; }

    FrameData liveLatest() {
        if (!liveReady()) return new FrameData();
        return liveRing[(liveHead - 1 + LIVE_CAP) % LIVE_CAP];
    }
}
