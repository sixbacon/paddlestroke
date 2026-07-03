// Integrator — unchanged from PadViz4.

class Integrator {

    static final float TAU_X   = 10.0f;
    static final float ARM_LEN = 0.5f;

    float   posX;
    float   velX;
    boolean usingFallback;

    private float posXraw, posXlp;
    private float prevRoll;
    private long  prevTs;
    private boolean ready;

    void reset() {
        posX = 0;  velX = 0;  posXraw = 0;  posXlp = 0;
        prevRoll = 0;  prevTs = 0;  ready = false;
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
            usingFallback = false;
            float[] aw = rotByQuat(fd.accelX, fd.accelY, fd.accelZ,
                                   fd.qw, fd.qx, fd.qy, fd.qz);
            aw[2] -= 9.81f;
            float ax = -aw[0];
            velX    += ax * dt;
            posXraw += velX * dt;
        } else {
            usingFallback = true;
            float dRoll = fd.roll - prevRoll;
            if (dRoll >  180) dRoll -= 360;
            if (dRoll < -180) dRoll += 360;
            float dx = radians(dRoll) * ARM_LEN;
            velX     = dx / dt;
            posXraw += dx;
        }

        prevRoll = fd.roll;

        float alpha = dt / (TAU_X + dt);
        posXlp += alpha * (posXraw - posXlp);
        posX    = posXraw - posXlp;
    }

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
