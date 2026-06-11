// Integrator — double-integration of IMU acceleration to estimate paddle position.
//
// Inputs:  FrameData.accelX/Y/Z (raw sensor body frame, gravity included)
//          FrameData.qw/qx/qy/qz (orientation quaternion)
// Outputs: posX, posZ in user coordinates (metres; X right, Z up).
//
// Method:
//   1. Rotate raw accel from BNO085 body frame to BNO085 world frame via quaternion.
//   2. Subtract gravity: world-frame Z reads +9.81 m/s² at rest → subtract (0,0,9.81).
//   3. Convert to user frame: user_X = −world_X (left→right-hand flip), user_Z = world_Z.
//   4. Double-integrate: accel → velocity → position.
//   5. High-pass filter to remove integration drift:
//        X: τ=10 s  (zero-mean assumption — paddle traces closed path)
//        Z: τ=30 s  + ±0.5 m hard clamp (bounded stroke height)
//
// Accuracy notes:
//   Integration drift is severe without GPS or periodic resets. The high-pass
//   filters remove slow drift but attenuate true low-frequency motion.
//   Works best for short replays (<30 s). For quantitative use, switch the
//   firmware to SH2_LINEAR_ACCELERATION (gravity already removed by BNO085).

class Integrator {

    static final float TAU_X   = 10.0f;    // X high-pass time constant (s)
    static final float TAU_Z   = 30.0f;    // Z high-pass time constant (s)
    static final float Z_CLAMP = 0.5f;     // ±0.5 m clamp on filtered Z

    // Public: read after each update()
    float posX, posZ;
    float velX, velZ;

    private float posXraw, posZraw;
    private float posXlp,  posZlp;
    private long  prevTs;
    private boolean ready;

    void reset() {
        posX = posZ = 0;
        velX = velZ = 0;
        posXraw = posZraw = 0;
        posXlp  = posZlp  = 0;
        prevTs  = 0;
        ready   = false;
    }

    // Call once per frame in sequence. Does nothing if accelX/Y/Z are all zero
    // (6-col or 10-col CSV without acceleration data).
    void update(FrameData fd) {
        if (!ready) { prevTs = fd.ts; ready = true; return; }

        float dt = (fd.ts - prevTs) / 1000.0f;   // seconds
        prevTs = fd.ts;
        if (dt <= 0 || dt > 0.5f) return;         // skip bad/large gaps

        if (fd.accelX == 0 && fd.accelY == 0 && fd.accelZ == 0) return;  // no accel data

        // Step 1: rotate raw accel from body frame to BNO085 world frame (left-handed)
        float[] aw = rotByQuat(fd.accelX, fd.accelY, fd.accelZ,
                               fd.qw, fd.qx, fd.qy, fd.qz);

        // Step 2: subtract gravity (+9.81 on world Z when sensor is level)
        aw[2] -= 9.81f;

        // Step 3: convert to user frame — flip X (left-handed → right-handed)
        float ax = -aw[0];
        float az =  aw[2];

        // Step 4: integrate
        velX    += ax * dt;
        velZ    += az * dt;
        posXraw += velX * dt;
        posZraw += velZ * dt;

        // Step 5: high-pass filter X
        float alphaX = dt / (TAU_X + dt);
        posXlp += alphaX * (posXraw - posXlp);
        posX    = posXraw - posXlp;

        // Step 5: high-pass filter Z + clamp
        float alphaZ = dt / (TAU_Z + dt);
        posZlp += alphaZ * (posZraw - posZlp);
        posZ    = constrain(posZraw - posZlp, -Z_CLAMP, Z_CLAMP);
    }

    // Rotate vector (vx,vy,vz) by quaternion [qw,qx,qy,qz] using rotation matrix.
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
