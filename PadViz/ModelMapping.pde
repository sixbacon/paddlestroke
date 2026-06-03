// ModelMapping — model-specific frame alignment for paddle60.obj
//
// To use a different model, copy this block and adjust these values:
//   CORR_*   — correction quaternion: rotates the model's rest pose so the shaft
//               aligns with the IMU reference frame before live rotation is applied
//   SIGN_*   — per-axis mirror (1.0 = normal, -1.0 = mirror that axis)
//              use when a pure quaternion can't fix handedness (det = -1 case)
//   SCALE    — uniform scale to fit model in view at default camera distance

// ── paddle60.obj ──────────────────────────────────────────────────────────────
// OBJ shaft runs along X (±0.909 m).
// Previous [0,0,-0.707,0.707] with additional Rx(+90°) world-space to match
// sensor mounting orientation → combined = [0, 0, -1, 0] (180° around Y).
// SIGN_X=-1 corrects handedness. 3 Jun 2026.

float MAP_CORR_W =  0.0f;
float MAP_CORR_X =  0.0f;
float MAP_CORR_Y = -1.0f;
float MAP_CORR_Z =  0.0f;

float MAP_SIGN_X = -1.0f;   // mirror X to correct handedness
float MAP_SIGN_Y =  1.0f;
float MAP_SIGN_Z =  1.0f;

float MAP_SCALE  = 150.0f;
