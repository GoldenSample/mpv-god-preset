// Non-Linear Stretch: scope (2.35:1 / 2.40:1) -> 16:9, vertical axis.
// The "Envy NLS" trick, free: center rows stay (almost) undistorted,
// the stretch is pushed progressively toward the top/bottom edges,
// where sky and floor live and nobody's face does.
//
// HOW TO USE — this shader alone does nothing useful. It must run
// TOGETHER with a linear stretch to 16:9. Use the [scope-fill] profile:
//
//   [scope-fill]
//   profile-restore=copy
//   video-aspect-override=16/9
//   glsl-shaders-append=~~/shaders/nls-scope.glsl
//
// mpv first stretches the whole image linearly (aspect-override),
// then this shader resamples: it compresses the center back to natural
// proportions, leaving the edges to absorb the stretch.
//
// Principle credit: sickgreg/Realtime-Superview-Stretch (horizontal
// 4:3 -> 16:9 for GoPro Superview). This is the vertical, parameterized
// sibling, rewritten as an mpv/libplacebo user shader.
//
// Tunables (mpv --glsl-shader-opts=strength=1.32,falloff=2.5):
//   strength — how much of the stretch the center is spared.
//              1.0  = no correction (plain linear stretch everywhere)
//              1.32 = center fully natural for 2.35:1 content
//              Must stay < 1.5 or the mapping stops being monotonic.
//   falloff  — how fast distortion ramps up toward the edges.
//              2.0 = classic quadratic (Superview-like), higher = flatter
//              center, harsher last rows.

//!PARAM strength
//!DESC center protection: 1.0 = none, 1.32 = full for 2.35:1
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 1.49
1.30

//!PARAM falloff
//!DESC edge ramp exponent: 2 = quadratic, higher = flatter center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
2.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC NLS vertical (scope -> 16:9)

vec4 hook() {
    vec2 uv = HOOKED_pos;
    // screen y in [-1, +1], 0 = frame center
    float t = uv.y * 2.0 - 1.0;
    // odd, endpoint-preserving warp:
    //   f(t) = t * (strength + (1 - strength) * |t|^falloff)
    //   f(0) slope = strength  -> center sampled faster = un-stretched
    //   f(±1) = ±1             -> frame edges stay exactly at the edges
    float ts = t * (strength + (1.0 - strength) * pow(abs(t), falloff));
    uv.y = ts * 0.5 + 0.5;
    return HOOKED_tex(uv);
}
