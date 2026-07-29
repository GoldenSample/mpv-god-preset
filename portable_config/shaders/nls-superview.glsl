// Non-Linear Stretch: 4:3 -> 16:9, horizontal axis (GoPro Superview style).
// Same math as nls-scope.glsl, other axis. Center columns stay natural,
// stretch is pushed toward the left/right edges.
//
// Use together with a linear stretch to 16:9:
//
//   [superview]
//   profile-restore=copy
//   video-aspect-override=16/9
//   glsl-shaders-append=~~/shaders/nls-superview.glsl
//
// strength=1.333 makes the center fully natural for 4:3 content.
// Principle credit: sickgreg/Realtime-Superview-Stretch.

//!PARAM strength
//!DESC center protection: 1.0 = none, 1.333 = full for 4:3
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 1.49
1.333

//!PARAM falloff
//!DESC edge ramp exponent: 2 = quadratic, higher = flatter center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
2.0

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
