// Non-Linear Stretch: 4:3 -> 16:9, horizontal axis (GoPro Superview style).
// Same math as nls-scope.glsl, other axis: the center columns keep
// natural proportions, the stretch is pushed into the left/right edges.
//
// Drive it from scripts/nls.lua (key `n`). Manual use:
//
//   mpv --video-aspect-override=16/9 \
//       --glsl-shader=~~/shaders/nls-superview.glsl \
//       --glsl-shader-opts=strength=1.333,falloff=2.5
//
// strength = 1.333 keeps the center fully natural for 4:3 content.
// Lower it toward 1.0 to spread some stretch across the whole frame
// (madVR Envy calls this "Center Stretch"), which softens the edges.
// falloff = how fast distortion ramps toward the edge (Envy's "Area").
// See nls-scope.glsl for the full notes and the measured numbers.

//!PARAM strength
//!DESC center correction: = stretch factor for a fully natural center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 1.49
1.333

//!PARAM falloff
//!DESC edge ramp exponent: 2 = quadratic, higher = flatter center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
2.5

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC NLS horizontal (4:3 -> 16:9)

vec4 hook() {
    vec2 uv = HOOKED_pos;
    float t = uv.x * 2.0 - 1.0;
    float ts = t * (strength + (1.0 - strength) * pow(abs(t), falloff));
    uv.x = ts * 0.5 + 0.5;
    return HOOKED_tex(uv);
}
