// TrackPanel — full-window GPS track over an OpenStreetMap backdrop
// (v0.26, spec §15). A third screen-owning alternative view (like the side
// profile and the wizard): while shown, draw() skips the 3D scene and every
// main-view overlay and draws only the bottom graph strip, so playback still
// scrubs. Toggled with the TRACK tab or the t key.
//
// Georeferencing. OSM "slippy map" tiles are in Web Mercator (EPSG:3857). We
// project every boat GPS fix into Web-Mercator world pixels at a chosen zoom,
// fetch the tiles covering the track's bounding box, and draw the track with
// the SAME projection — so the polyline lands exactly on the streets. Steps:
//   1. scan the boat file once for the lat/lon bounding box (cached);
//   2. pick the highest zoom whose bbox still fits the plot rectangle;
//   3. fetch + disk-cache the covering tiles on a background thread;
//   4. draw tiles, then overlay the track, start/end + live markers, a metric
//      scale bar, a north arrow, and the required OSM attribution.
//
// Networking notes (OSM tile usage policy): tiles are fetched with a proper
// User-Agent, cached to disk (visualisation/PadViz8/tilecache/z/x/y.png) so the
// network is hit only once per tile, and volume is tiny (a track bbox is a
// handful of tiles). No internet / a failed fetch degrades gracefully to a
// blank backdrop with the track still drawn.

import java.net.HttpURLConnection;
import java.net.URL;
import java.io.File;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

class TrackPanel {
    boolean shown = false;

    static final int   ZMIN = 3;
    static final int   ZMAX = 18;          // cap: tile count + float precision
    static final float FILL = 0.90f;       // fraction of the plot the bbox fills
    static final double EARTH_R = 6378137.0;

    static final String TILE_URL = "https://tile.openstreetmap.org/";
    static final String USER_AGENT =
        "PadViz8/0.26 (kayak paddlestroke visualiser; contact sixbacon@gmail.com)";
    static final String ATTRIB = "© OpenStreetMap contributors";

    final int COL_TRACK = color(255, 90, 40);    // track polyline
    final int COL_START = color(70, 220, 90);     // start marker (green)
    final int COL_END   = color(235, 60, 60);     // end marker (red)
    final int COL_NOW   = color(60, 150, 255);    // live position (blue)

    // Cached scan of the boat file — recomputed when the frame count changes or
    // (via invalidate()) when the classification changes.
    int              cachedCount = -1;
    float[]          bounds;                       // {latMin,latMax,lonMin,lonMax}
    ArrayList<float[]> pts;                        // valid, non-excluded fixes: {lat, lon, frameIdx}
    boolean          filteredByClass = false;      // true when excluded ranges were dropped

    // Tile store + background fetch.
    ConcurrentHashMap<String, PImage> tiles = new ConcurrentHashMap<String, PImage>();
    Set<String> requested = Collections.synchronizedSet(new HashSet<String>());
    Set<String> failed    = Collections.synchronizedSet(new HashSet<String>());
    LinkedBlockingQueue<String> queue = new LinkedBlockingQueue<String>();
    Thread worker;

    void invalidate() { cachedCount = -1; bounds = null; pts = null; }

    // ── projection helpers (Web Mercator) ───────────────────────────────────
    double mapSize(int z) { return 256.0 * (1L << z); }
    double worldX(double lon, double size) { return (lon + 180.0) / 360.0 * size; }
    double worldY(double lat, double size) {
        double s = sin(radians((float) lat));
        return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * PI)) * size;
    }

    int pickZoom(float plotW, float plotH) {
        for (int z = ZMAX; z >= ZMIN; z--) {
            double size = mapSize(z);
            double wpx = worldX(bounds[3], size) - worldX(bounds[2], size);
            double hpx = worldY(bounds[0], size) - worldY(bounds[1], size);
            if (wpx <= plotW * FILL && hpx <= plotH * FILL) return z;
        }
        return ZMIN;
    }

    // ── main draw ────────────────────────────────────────────────────────────
    void draw(BoatSource boat, SyncMap sync, int padFrame, int boatFrame) {
        int H = height - GRAPH_H;
        noStroke();  fill(24, 26, 32);  rect(0, 0, width, H);

        rescan(boat, sync);
        if (bounds == null || pts == null || pts.size() == 0) {
            fill(200);  textAlign(CENTER, CENTER);  textSize(15);
            text(filteredByClass ? "No GPS fixes left after classification (all excluded?)"
                                 : "No GPS fixes in this boat CSV",
                 width / 2, H / 2);
            return;
        }

        float plotX = 0, plotY = 0, plotW = width, plotH = H;
        int z = pickZoom(plotW, plotH);
        double size = mapSize(z);
        double cLon = (bounds[2] + bounds[3]) / 2.0;
        double cLat = (bounds[0] + bounds[1]) / 2.0;
        double offX = plotX + plotW / 2 - worldX(cLon, size);
        double offY = plotY + plotH / 2 - worldY(cLat, size);

        drawTiles(z, size, offX, offY, plotX, plotY, plotW, plotH);
        drawTrack(size, offX, offY);
        drawMarkers(boat, sync, padFrame, boatFrame, size, offX, offY);
        drawScaleBar(cLat, size, plotH);
        drawNorthArrow();
        drawChrome(z, plotH);
    }

    // Recompute the bounds + valid-point list if the boat data or the
    // classification changed (invalidate() forces the latter).
    //
    // Classification filtering: classification is defined in PADDLE frames, so
    // when any EXCLUDED range is marked (e.g. the drive home) we map each boat
    // fix back to its paddle frame via SyncMap and drop the fixes that land in
    // an excluded range. The bounds — and therefore the auto-zoom — are computed
    // from the KEPT fixes only, so the map frames the paddling area instead of
    // the whole drive. With no exclusions (or no paddle/sync) this reduces to
    // "every valid boat fix", exactly as before.
    void rescan(BoatSource boat, SyncMap syncMap) {
        int n = (boat == null) ? 0 : boat.frameCount();
        if (n == cachedCount && bounds != null) return;
        cachedCount = n;
        pts = new ArrayList<float[]>();
        bounds = null;
        filteredByClass = false;
        if (boat == null) return;

        boolean filter = classify != null && classify.hasExclusions()
                      && paddleData != null && paddleData.frameCount() > 0
                      && syncMap != null;

        // Map boat frame → excluded? A boat frame is excluded only if an
        // excluded paddle frame maps to it AND no NON-excluded paddle frame
        // also does (so a boundary boat fix straddling the edge is kept).
        boolean[] boatExcl = null, boatKeep = null;
        if (filter) {
            boatExcl = new boolean[n];
            boatKeep = new boolean[n];
            int pc = paddleData.frameCount();
            for (int p = 0; p < pc; p++) {
                int bi = syncMap.boatIdxFor(p);
                if (bi < 0 || bi >= n) continue;
                if (classify.isExcluded(p)) boatExcl[bi] = true;
                else                        boatKeep[bi] = true;
            }
        }

        ArrayList<BoatFrameData> fr = boat.getFrames();
        for (int i = 0; i < fr.size(); i++) {
            BoatFrameData f = fr.get(i);
            if (!boat.validFix(f)) continue;
            if (filter && boatExcl[i] && !boatKeep[i]) { filteredByClass = true; continue; }
            pts.add(new float[]{ f.gpsLat, f.gpsLon, i });
        }

        // Bounds from the kept fixes, so the auto-zoom frames the valid track.
        if (pts.size() > 0) {
            float latMin = 1e9f, latMax = -1e9f, lonMin = 1e9f, lonMax = -1e9f;
            for (float[] p : pts) {
                latMin = min(latMin, p[0]);  latMax = max(latMax, p[0]);
                lonMin = min(lonMin, p[1]);  lonMax = max(lonMax, p[1]);
            }
            bounds = new float[]{ latMin, latMax, lonMin, lonMax };
        }
    }

    // ── tiles ────────────────────────────────────────────────────────────────
    void drawTiles(int z, double size, double offX, double offY,
                   float plotX, float plotY, float plotW, float plotH) {
        ensureWorker();
        int nT = 1 << z;
        int txMin = (int) Math.floor((plotX - offX) / 256.0);
        int txMax = (int) Math.floor((plotX + plotW - offX) / 256.0);
        int tyMin = (int) Math.floor((plotY - offY) / 256.0);
        int tyMax = (int) Math.floor((plotY + plotH - offY) / 256.0);
        int pending = 0, gone = 0;
        imageMode(CORNER);
        for (int tx = txMin; tx <= txMax; tx++) {
            for (int ty = tyMin; ty <= tyMax; ty++) {
                if (tx < 0 || ty < 0 || tx >= nT || ty >= nT) continue;
                float sx = (float) (tx * 256 + offX);
                float sy = (float) (ty * 256 + offY);
                String key = z + "/" + tx + "/" + ty;
                PImage img = tiles.get(key);
                if (img != null && img.width > 0) {
                    tint(255);  image(img, sx, sy, 256, 256);
                } else {
                    noStroke();  fill(34, 38, 46);  rect(sx, sy, 256, 256);
                    if (failed.contains(key)) gone++;
                    else { pending++; enqueue(key); }
                }
            }
        }
        if (pending > 0 || gone > 0) {
            fill(210);  textAlign(LEFT, TOP);  textSize(12);
            String msg = pending > 0 ? "loading map… " + pending + " tiles"
                                     : "map unavailable (offline?) — track shown without backdrop";
            text(msg, 12, 12);
        }
    }

    void enqueue(String key) {
        if (requested.contains(key)) return;
        requested.add(key);
        queue.offer(key);
    }

    void ensureWorker() {
        if (worker != null) return;
        worker = new Thread(new Runnable() {
            public void run() {
                while (true) {
                    String key;
                    try { key = queue.take(); } catch (InterruptedException e) { return; }
                    PImage img = loadTile(key);
                    if (img != null && img.width > 0) tiles.put(key, img);
                    else failed.add(key);
                }
            }
        });
        worker.setDaemon(true);
        worker.start();
    }

    // Load a tile: disk cache first, else HTTP GET (with User-Agent) → cache.
    PImage loadTile(String key) {
        String cache = sketchPath("tilecache/" + key + ".png");
        File cf = new File(cache);
        if (cf.exists() && cf.length() > 0) {
            PImage img = loadImage(cache, "png");
            if (img != null && img.width > 0) return img;
        }
        byte[] data = httpGet(TILE_URL + key + ".png");
        if (data == null) return null;
        try {
            cf.getParentFile().mkdirs();
            saveBytes(cache, data);
        } catch (Exception e) { /* fall through — try to decode anyway */ }
        return loadImage(cache, "png");
    }

    byte[] httpGet(String urlStr) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(urlStr).openConnection();
            c.setRequestProperty("User-Agent", USER_AGENT);
            c.setConnectTimeout(6000);
            c.setReadTimeout(9000);
            if (c.getResponseCode() != 200) return null;
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];  int r;
            while ((r = in.read(buf)) > 0) bo.write(buf, 0, r);
            in.close();
            return bo.toByteArray();
        } catch (Exception e) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    // ── overlays ───────────────────────────────────────────────────────────────
    void drawTrack(double size, double offX, double offY) {
        noFill();  stroke(COL_TRACK, 230);  strokeWeight(3);
        beginShape();
        for (float[] p : pts)
            vertex((float) (worldX(p[1], size) + offX), (float) (worldY(p[0], size) + offY));
        endShape();
        strokeWeight(1);
    }

    void drawMarkers(BoatSource boat, SyncMap sync, int padFrame, int boatFrame,
                     double size, double offX, double offY) {
        // Start (green) and end (red).
        float[] a = pts.get(0), b = pts.get(pts.size() - 1);
        marker(a, size, offX, offY, COL_START, 11);
        marker(b, size, offX, offY, COL_END,   11);

        // Live position — the last valid fix at or before the playback cursor.
        int curBoat = currentBoatFrame(sync, padFrame, boatFrame);
        float[] now = pointAtOrBefore(curBoat);
        if (now != null) {
            float sx = (float) (worldX(now[1], size) + offX);
            float sy = (float) (worldY(now[0], size) + offY);
            noFill();  stroke(COL_NOW);  strokeWeight(3);  ellipse(sx, sy, 18, 18);
            noStroke();  fill(COL_NOW);  ellipse(sx, sy, 7, 7);
            strokeWeight(1);
        }
    }

    void marker(float[] p, double size, double offX, double offY, int col, float d) {
        float sx = (float) (worldX(p[1], size) + offX);
        float sy = (float) (worldY(p[0], size) + offY);
        noStroke();  fill(col);            ellipse(sx, sy, d, d);
        noFill();    stroke(0, 160);       strokeWeight(1.5);  ellipse(sx, sy, d, d);
        strokeWeight(1);
    }

    // Boat frame index that matches the playback cursor.
    int currentBoatFrame(SyncMap sync, int padFrame, int boatFrame) {
        if (paddleData != null && paddleData.frameCount() > 0 && sync != null) {
            int bi = sync.boatIdxFor(padFrame);
            if (bi >= 0) return bi;
        }
        return boatFrame;
    }

    // Last cached valid fix whose frame index is <= f (so the dot sits at the
    // most recent known position even between fixes).
    float[] pointAtOrBefore(int f) {
        float[] best = null;
        for (float[] p : pts) {
            if ((int) p[2] <= f) best = p;
            else break;
        }
        return (best != null) ? best : pts.get(0);
    }

    // ── chrome ─────────────────────────────────────────────────────────────────
    void drawScaleBar(double cLat, double size, float plotH) {
        double res = cos(radians((float) cLat)) * 2 * PI * EARTH_R / size;  // m/px
        float target = (float) (120 * res);
        float e = floor(log(target) / log(10));
        float base = pow(10, e);
        float f = target / base;
        float niceM = (f >= 5 ? 5 : f >= 2 ? 2 : 1) * base;
        float barPx = (float) (niceM / res);

        float x0 = 20, y0 = plotH - 26;
        stroke(0, 180);  strokeWeight(4);  line(x0, y0, x0 + barPx, y0);
        stroke(255);     strokeWeight(2);  line(x0, y0, x0 + barPx, y0);
        line(x0, y0 - 4, x0, y0 + 4);
        line(x0 + barPx, y0 - 4, x0 + barPx, y0 + 4);
        strokeWeight(1);  noStroke();
        String lbl = (niceM >= 1000) ? nf(niceM / 1000f, 0, (niceM % 1000 == 0) ? 0 : 1) + " km"
                                     : (int) niceM + " m";
        fill(255);  textAlign(LEFT, BOTTOM);  textSize(12);
        text(lbl, x0, y0 - 6);
    }

    void drawNorthArrow() {
        float x = width - 34, y = 46;
        stroke(255);  strokeWeight(2);  fill(255);
        line(x, y, x, y - 26);
        triangle(x, y - 32, x - 5, y - 22, x + 5, y - 22);
        strokeWeight(1);  noStroke();
        textAlign(CENTER, TOP);  textSize(12);  text("N", x, y + 2);
    }

    void drawChrome(int z, float plotH) {
        // Title (top-left, clear of the loading line at 12).
        fill(210, 225, 250);  textAlign(LEFT, TOP);  textSize(15);
        text("TRACK — GPS over OpenStreetMap   (z" + z + ")", 12, 30);
        // Footer: point count + attribution (attribution is required by OSM).
        fill(200);  textSize(11);  textAlign(LEFT, BOTTOM);
        text(pts.size() + " fixes" + (filteredByClass ? "  (excluded ranges hidden)" : ""),
             12, plotH - 6);
        textAlign(RIGHT, BOTTOM);
        text(ATTRIB, width - 10, plotH - 6);
    }
}
