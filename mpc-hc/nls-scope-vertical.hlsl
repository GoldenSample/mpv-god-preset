// nls-scope-vertical.hlsl — non-linear VERTICAL stretch: scope (2.35:1) -> 16:9
// Drop-in for MPC-HC, works with madVR as the renderer too.
//
//   1. Right-click -> Video Frame -> Override Aspect Ratio -> 16:9
//   2. Options -> Playback -> Shaders -> add this file to "Pre-resize"
//
// The player's forced 16:9 does the linear stretch; this shader then keeps
// the CENTER rows (faces) at natural proportions and pushes the distortion
// progressively into the top/bottom edges (sky and floor).
//
// Sibling of sickgreg/Realtime-Superview-Stretch (which is the horizontal
// 4:3 -> 16:9 case). Same endpoint-preserving warp, other axis, tunable.

sampler s0 : register(s0);

// 1.0 = plain linear stretch everywhere; 1.32 = center fully natural for
// 2.35:1 content. Keep below 1.5 or the mapping folds over itself.
#define STRENGTH 1.30
// Edge ramp exponent: 2.0 = classic quadratic (Superview-like);
// higher = flatter protected center, harsher last rows.
#define FALLOFF  2.0

float4 main(float2 tex : TEXCOORD0) : COLOR
{
    // screen y in [-1, +1], 0 = frame center
    float t = tex.y * 2.0 - 1.0;
    // odd, endpoint-preserving warp: f(0) slope = STRENGTH (un-stretches
    // the center), f(+-1) = +-1 (frame edges stay put)
    t *= STRENGTH + (1.0 - STRENGTH) * pow(abs(t), FALLOFF);
    tex.y = t * 0.5 + 0.5;
    return tex2D(s0, tex);
}
