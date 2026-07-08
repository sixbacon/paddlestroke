// SyncMap — for every paddle frame, precompute the nearest boat frame.
//
// Two sync paths, chosen at build() time:
//
//   RX_MS path (preferred): both CSVs are PadDis v8.10+ and carry rx_ms — the
//   CYD-side ESPnow reception timestamp captured in the receive callback.
//   Same clock domain for both files, so a nearest-rx_ms match is < 10 ms
//   accurate. tolerance = 500 ms (well outside the ~few-ms send-side jitter,
//   safe against dropped packets).
//
//   GPS_UTC path (fallback): older CSVs use gps_utc_sec (whole seconds), with
//   ±5 s tolerance. Same two-pointer sweep as before.
//
// Called every time either CSV is (re)loaded. O(n_paddle + n_boat) either way.
//
// Ported byte-for-byte from PadViz5b/SyncMap.pde per padviz6_spec.md §4.3.

class SyncMap {
    private int[] padToBoat;
    private int   padCount;
    private BoatSource dsBoatRef;

    // Diagnostic — set by build(), inspected by callers if useful.
    boolean usedRxMs = false;

    void build(DataSource ds, BoatSource dsBoat) {
        dsBoatRef = dsBoat;
        padCount  = ds.frameCount();
        padToBoat = new int[max(1, padCount)];
        usedRxMs  = false;

        if (dsBoat.frameCount() == 0 || padCount == 0) {
            for (int i = 0; i < padCount; i++) padToBoat[i] = -1;
            return;
        }

        if (ds.hasRxMs && dsBoat.hasRxMs) {
            buildRxMs(ds, dsBoat);
            usedRxMs = true;
        } else {
            buildGpsUtc(ds, dsBoat);
        }
    }

    // rx_ms path
    private void buildRxMs(DataSource ds, BoatSource dsBoat) {
        ArrayList<BoatFrameData> bFrames = dsBoat.getFrames();
        ArrayList<FrameData>     pFrames = ds.getFrames();
        int bi = 0, bLen = bFrames.size();

        for (int pi = 0; pi < padCount; pi++) {
            long pMs = pFrames.get(pi).rxMs;

            if (pMs == 0) { padToBoat[pi] = -1; continue; }

            while (bi + 1 < bLen) {
                long d0 = Math.abs(bFrames.get(bi    ).rxMs - pMs);
                if (d0 == 0) break;
                long d1 = Math.abs(bFrames.get(bi + 1).rxMs - pMs);
                if (d1 <= d0) bi++;
                else break;
            }

            long delta = Math.abs(bFrames.get(bi).rxMs - pMs);
            padToBoat[pi] = (delta <= 500) ? bi : -1;   // 500 ms guard
        }
        println("SyncMap: built for " + padCount + " paddle frames  (rx_ms path, +-500 ms guard)");
    }

    // gps_utc_sec path (fallback for pre-v8.10 CSVs)
    private void buildGpsUtc(DataSource ds, BoatSource dsBoat) {
        ArrayList<BoatFrameData> bFrames = dsBoat.getFrames();
        ArrayList<FrameData>     pFrames = ds.getFrames();
        int bi = 0, bLen = bFrames.size();

        for (int pi = 0; pi < padCount; pi++) {
            long pSec = pFrames.get(pi).gpsUtcSec;

            if (pSec == 0) { padToBoat[pi] = -1; continue; }

            while (bi + 1 < bLen) {
                long d0 = Math.abs(bFrames.get(bi    ).gpsUtcSec - pSec);
                if (d0 == 0) break;
                long d1 = Math.abs(bFrames.get(bi + 1).gpsUtcSec - pSec);
                if (d1 <= d0) bi++;
                else break;
            }

            long delta = Math.abs(bFrames.get(bi).gpsUtcSec - pSec);
            padToBoat[pi] = (delta <= 5) ? bi : -1;
        }
        println("SyncMap: built for " + padCount + " paddle frames  (gps_utc path, +-5 s guard)");
    }

    BoatFrameData boatFrameFor(int paddleIdx) {
        int bi = boatIdxFor(paddleIdx);
        if (bi < 0 || dsBoatRef == null) return null;
        return dsBoatRef.frameAt(bi);
    }

    int boatIdxFor(int paddleIdx) {
        if (padToBoat == null || paddleIdx < 0 || paddleIdx >= padCount) return -1;
        return padToBoat[paddleIdx];
    }

    // Signed delta in ms between paddle rx_ms and boat rx_ms for a mapped pair.
    // Returns Long.MAX_VALUE if unmapped or not on rx_ms path.
    long syncDeltaMs(DataSource ds, int paddleIdx) {
        int bi = boatIdxFor(paddleIdx);
        if (bi < 0 || dsBoatRef == null || !usedRxMs) return Long.MAX_VALUE;
        long pMs = ds.frameAt(paddleIdx).rxMs;
        long bMs = dsBoatRef.frameAt(bi).rxMs;
        return bMs - pMs;
    }
}
