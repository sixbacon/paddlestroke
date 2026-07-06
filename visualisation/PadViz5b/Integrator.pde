// Integrator — estimates paddle X position from IMU data.
//
// Two modes, selected automatically:
//
// ACCEL mode (15-col CSV with accelX/Y/Z):
//   1. Rotate raw accel from BNO085 body frame to world frame via quaternion.
//   2. Subtract gravity: world Z reads +9.81 m/s² at rest.
//   3. Convert to user frame: user_X = −world_X (left→right-hand flip).
//   4. Double-integrate: accel → velX → posX.
//   5. High-pass drift correction: τ = TAU_X.
//
// ROLL FALLBACK mode (6-col / 10-col CSV without accel):
//   Estimates X from the roll angle: at the paddle IMU (centre of shaft),
//   a change in roll corresponds to lateral motion of the paddle ends.
//   posX ≈ integral of (roll_rate × ARM_LEN).
//   This is a proxy — useful for visual testing, not quantitative.
//   ARM_LEN = 0.5 m (approximate half shaft length at IMU).
//
// Only X is tracked here. Z (height) is a separate future step.

class Integrator {

    static final float TAU_X   = 10.0f;   // high-pass time constant (s)
    static final float ARM_LEN = 0.5f;    // roll-fallback arm length (m)

    // Public: read after each update()
    float   posX;
    float   velX;
    boolean usingFallback;   // true when using roll estimate, false when using accel

    private float posXraw, posXlp;
    private float prevRoll;
    private long  prevTs;
    private boolean ready;

    void reset() {
        posX     = 0;
        velX     = 0;
        posXraw  = 0;
        posXlp   = 0;
        prevRoll = 0;
        prevTs   = 0;
        ready    = false;
    }

    void update(FrameData fd) {
        if (!ready) {
            prevTs   = fd.ts;
            prevRoll = fd.roll;
            ready    = true;
            return;
        }

        float dt = (fd.ts - prevTs) / 1000.0f;
        prevTs = fd.ts;
        if (dt <= 0 || dt > 0.5f) { prevRoll = fd.roll; return; }

        boolean hasAccel = (fd.accelX != 0 || fd.accelY != 0 || fd.accelZ != 0);

        if (hasAccel) {
            // ── Accel path ────────────────────────────────────────────────────
            usingFallback = false;

            float[] aw = rotByQuat(fd.accelX, fd.accelY, fd.accelZ,
                                   fd.qw, fd.qx, fd.qy, fd.qz);
            aw[2] -= 9.81f;            // subtract gravity (world Z, +9.81 at rest)
            float ax = -aw[0];         // flip X: BNO085 left-handed → user right-handed

            velX    += ax * dt;
            posXraw += velX * dt;

        } else {
            // ── Roll-rate fallback ────────────────────────────────────────────
            usingFallback = true;

            float dRoll = fd.roll - prevRoll;
            // Wrap-correct across ±180° boundary
            if (dRoll >  180) dRoll -= 360;
            if (dRoll < -180) dRoll += 360;

            // X displacement ≈ angular change (rad) × arm length
            float dx = radians(dRoll) * ARM_LEN;
            velX     = dx / dt;        // instantaneous velocity estimate
            posXraw += dx;
        }

        prevRoll = fd.roll;

        // High-pass filter: removes DC drift (assumes paddle path is zero-mean)
        float alpha = dt / (TAU_X + dt);
        posXlp += alpha * (posXraw - posXlp);
        posX    = posXraw - posXlp;
    }

    // Rotate vector (vx,vy,vz) by quaternion [qw,qx,qy,qz].
    private float[] rotByQuat(float vx, float vy, float vz,
                               float qw, float qx, float qy, float qz) {
        float m00 = 1 - 2*(qy*qy + qz*qz);
        float m01 =     2*(qx*qy - qw*qz);
        float m02 =     2*(qx*qz + qw*qy);
        float m10 =     2*(qx*qy + qw*qz);
        float m11 = 1 - 2*(qx*qx + qz*qz);
        float m12 =     2*(qy*qz - qw*qx);
        float m20 =     2*(qx*qz - qw*qy);
        float m21 =     2*(qy*qz + qw*qx);
        float m22 = 1 - 2*(qx*qx + qy*qy);
        return new float[]{
            m00*vx + m01*vy + m02*vz,
            m10*vx + m11*vy + m12*vz,
            m20*vx + m21*vy + m22*vz
        };
    }
}
