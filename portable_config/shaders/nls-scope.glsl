// Non-Linear Stretch: scope (2.35:1 / 2.40:1) -> 16:9, vertical axis.
// The "Envy NLS" trick, free: the center of the frame keeps natural
// proportions, and the stretch is pushed progressively into the top and
// bottom edges, where sky and floor live and nobody's face does.
//
// HOW TO USE: this shader alone does nothing useful. It resamples an
// already-stretched image. Drive it from scripts/nls.lua (key `n`),
// which sets video-crop, video-aspect-override and these options
// consistently. Manual use:
//
//   mpv --video-aspect-override=16/9 \
//       --glsl-shader=~~/shaders/nls-scope.glsl \
//       --glsl-shader-opts=strength=1.15,falloff=2.5
//
// MAPPING TO madVR ENVY, whose OSD exposes "Center Stretch", "Vert NLS
// Area" and "Vert NLS Strength":
//   Envy "Crop"           -> video-crop, done by nls.lua before this runs
//   Envy "Center Stretch" -> lowering `strength` below the full factor
//   Envy "Area"           -> `falloff` (lower = wider, gentler ramp)
//   Envy "Strength"       -> always "as much as needed to fill", like
//                            Envy's own auto-clamping behaviour
//
// WHY A SMOOTH CURVE AND NOT A STRICTLY LINEAR CENTER BAND: a hard
// linear center forces the remaining edge band to absorb everything, and
// the math is brutal — measured on this exact geometry, a strictly
// linear center with Envy's recommended Area 33 reaches ~14x local
// stretch at the rim, and even Area 50 reaches ~4.2x, where this smooth
// curve stays at ~1.8x for the same overall factor. That matches the
// one Envy user who published numbers: at Area 33 with Center Stretch 0
// he found pans unwatchable and had to widen the Area and add Center
// Stretch. So: no hard seam, and the distortion budget is spent evenly.
//
// strength — how much of the linear pre-stretch to undo at the center.
//            Equal to the stretch factor (e.g. 1.15 after a zoom has
//            taken half the work) = fully natural center, Envy's
//            "Center Stretch = 0". Lower it toward 1.0 to leave some
//            stretch spread across the whole frame, which softens the
//            edges and, per Envy users, helps on camera pans.
//            Must stay below 1.5 or the mapping stops being monotonic.
// falloff  — how fast the distortion ramps toward the edge.
//            2.0 = classic quadratic (Superview-like), higher = flatter
//            protected center in exchange for harsher last rows.

//!PARAM strength
//!DESC center correction: = stretch factor for a fully natural center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 1.49
1.15

//!PARAM falloff
//!DESC edge ramp exponent: 2 = quadratic, higher = flatter center
//!TYPE float
//!MINIMUM 1.0
//!MAXIMUM 8.0
2.5

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC NLS vertical (scope -> 16:9)

vec4 hook() {
    vec2 uv = HOOKED_pos;
    // screen y in [-1, +1], 0 = frame center
    float t = uv.y * 2.0 - 1.0;
    // odd, endpoint-preserving warp:
    //   f(t) = t * (strength + (1 - strength) * |t|^falloff)
    //   f'(0) = strength -> center sampled faster = un-stretched
    //   f(+-1) = +-1     -> frame edges stay exactly at the edges
    float ts = t * (strength + (1.0 - strength) * pow(abs(t), falloff));
    uv.y = ts * 0.5 + 0.5;
    return HOOKED_tex(uv);
}
