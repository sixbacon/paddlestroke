// Calibration — model calibration state, key handling, JSON I/O.
//
// The three values (yawDeg, pitchDeg, rollDeg) are the intrinsic ZYX
// Euler triple applied to the paddle .obj model after the handedness
// bridge and before the data quaternion. Determined interactively in
// Slice 0 against a calibration data set, saved to a JSON file, and
// treated as an immutable model constant thereafter.

class Calibration {
    float yawDeg   = 0.0;
    float pitchDeg = 0.0;
    float rollDeg  = 0.0;
    float stepDeg  = 5.0;

    final float MIN_STEP = 0.1;
    final float MAX_STEP = 45.0;

    String savePath = "data/model_calibration.json";

    void load(String path) {
        savePath = path;
        try {
            JSONObject j = loadJSONObject(path);
            if (j != null) {
                yawDeg   = j.getFloat("model_yaw_deg",   0);
                pitchDeg = j.getFloat("model_pitch_deg", 0);
                rollDeg  = j.getFloat("model_roll_deg",  0);
                println("Calibration: loaded from " + path
                        + "  (y=" + nf(yawDeg,0,2)
                        + " p=" + nf(pitchDeg,0,2)
                        + " r=" + nf(rollDeg,0,2) + ")");
                return;
            }
        } catch (Exception e) {
            // File missing or unreadable — start at zero.
        }
        println("Calibration: no existing file at " + path + "; starting at (0, 0, 0)");
    }

    void save() {
        JSONObject j = new JSONObject();
        j.setFloat("model_yaw_deg",   yawDeg);
        j.setFloat("model_pitch_deg", pitchDeg);
        j.setFloat("model_roll_deg",  rollDeg);
        saveJSONObject(j, savePath);
        println("Calibration: saved to " + savePath);
    }

    void printBlock() {
        println("// PadViz6 paddle model calibration");
        println("{");
        println("  \"model_yaw_deg\":   " + nf(yawDeg,   0, 2) + ",");
        println("  \"model_pitch_deg\": " + nf(pitchDeg, 0, 2) + ",");
        println("  \"model_roll_deg\":  " + nf(rollDeg,  0, 2));
        println("}");
    }

    void zero() {
        yawDeg = pitchDeg = rollDeg = 0;
    }

    void handleKey(char k) {
        switch (k) {
            // Lowercase = increase, uppercase (Shift) = decrease.
            case 'y': yawDeg   += stepDeg; break;
            case 'Y': yawDeg   -= stepDeg; break;
            case 'p': pitchDeg += stepDeg; break;
            case 'P': pitchDeg -= stepDeg; break;
            case 'r': rollDeg  += stepDeg; break;
            case 'R': rollDeg  -= stepDeg; break;

            case '[': stepDeg = max(MIN_STEP, stepDeg / 2); break;
            case ']': stepDeg = min(MAX_STEP, stepDeg * 2); break;

            case 'z': case 'Z': zero(); break;
            case 's': case 'S': save(); break;
            case 'l': case 'L': printBlock(); break;
        }
    }
}
