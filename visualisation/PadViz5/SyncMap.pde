// SyncMap — links each paddle frame index to the nearest boat frame index
// using gps_utc_sec as the common wall-clock reference.

class SyncMap {
    private int[] padToBoat;   // padToBoat[paddleIdx] = boatIdx, or -1
    private int   padCount;

    void build(DataSource ds, BoatSource dsBoat) {
        padCount  = ds.frameCount();
        padToBoat = new int[max(1, padCount)];

        if (dsBoat.frameCount() == 0 || padCount == 0) {
            for (int i = 0; i < padCount; i++) padToBoat[i] = -1;
            return;
        }

        // Two-pointer sweep: both arrays are time-ordered by gpsUtcSec.
        // For each paddle frame, find the boat frame with nearest gpsUtcSec.
        ArrayList<BoatFrameData> bFrames = dsBoat.getFrames();
        ArrayList<FrameData>     pFrames = ds.getFrames();

        int bi = 0;
        int bLen = bFrames.size();

        for (int pi = 0; pi < padCount; pi++) {
            long pSec = pFrames.get(pi).gpsUtcSec;

            if (pSec == 0) {
                // No GPS fix on this paddle frame — skip sync
                padToBoat[pi] = -1;
                continue;
            }

            // Advance bi while the next boat frame is closer
            while (bi + 1 < bLen) {
                long d0 = Math.abs(bFrames.get(bi).gpsUtcSec     - pSec);
                long d1 = Math.abs(bFrames.get(bi + 1).gpsUtcSec - pSec);
                if (d1 < d0) bi++;
                else break;
            }

            // Accept match only if within 5 seconds
            long delta = Math.abs(bFrames.get(bi).gpsUtcSec - pSec);
            padToBoat[pi] = (delta <= 5) ? bi : -1;
        }

        println("SyncMap: built for " + padCount + " paddle frames");
    }

    // Returns the BoatFrameData matching the given paddle frame, or null.
    BoatFrameData boatFrameFor(int paddleIdx) {
        if (padToBoat == null || paddleIdx < 0 || paddleIdx >= padCount) return null;
        int bi = padToBoat[paddleIdx];
        if (bi < 0) return null;
        return dsBoat.frameAt(bi);
    }

    // Returns the boat frame index for a paddle frame (-1 if none).
    int boatIdxFor(int paddleIdx) {
        if (padToBoat == null || paddleIdx < 0 || paddleIdx >= padCount) return -1;
        return padToBoat[paddleIdx];
    }
}
