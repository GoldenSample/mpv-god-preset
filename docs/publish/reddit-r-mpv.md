# r/mpv (проверить правила саба перед постом; постить руками после разлока аккаунта)

## Title
Single-graph VapourSynth+TensorRT in mpv: RIFE interpolation + 2x neural upscale, zero drops on an 8K panel (configs open, 7 pitfalls documented)

## Body
Spent a week fusing RIFE frame interpolation and AnimeJaNai 2x upscaling into mpv's --vf vapoursynth path on an RTX 5090, output to a Samsung QN900F 8K. Everything is open (public domain): https://github.com/GoldenSample/mpv-god-preset

Numbers first (zero dropped frames in all rows): RIFE 1080p24 x6 → 143.86 fps; full 4K24 x3 (v4.25_lite) → 71.93; PAL 25 and NTSC 29.97 hit exactly 144.00 via fractional multipliers (Fraction-based, vs-mlrt takes them fine); fused upscale+interpolation graph → 98 fps headroom at a 72 fps target.

The mpv-specific pitfalls, since they cost the most time:

1. **Two --vf vapoursynth bridges starve each other.** 122 fps and 104 fps filters drop to 24.8 together. One .vpy graph with a single RGB round-trip → 107 fps.
2. **The bridge hands you fps 0/0.** On the fractional path vsmlrt then skips its own AssumeFPS — without an explicit AssumeFPS after RIFE the film plays in slow motion.
3. **Frame props carry _ColorRange and _ChromaLocation but NOT _Transfer/_Matrix/_Primaries.** HDR gating can't live in the graph; it lives in a lua hook where gamma is known before the filter.
4. **Full-range content washes out silently** unless range is pinned on both YUV↔RGB conversions. Verified bit-exact round-trip with out-of-range floats through fp16 RGB.
5. **Windowed benchmarks lie.** Fullscreen 8K@60 was silently throttled to 31.8 Hz by d3d11 flip-model presentation. d3d11-flip=no (or vulkan) → jitter 1.85 → 0.005.
6. **Once-per-second microstutter on BARE video** (no filters) = NVIDIA P-state drops with mixed-refresh dual monitors. lua hook: nvidia-smi -lmc on file-loaded, -rmc on shutdown. Jitter down 650x.
7. RIFE v4.6 draws a waffle grid on film grain; v4.26 (≤1440p) and v4.25_lite (4K) are clean.

Disclosure: built pair-programming with an AI assistant, commits are trailer-signed. Measurements are one panel + one GPU — if you run this, I want your numbers, especially flip-model behavior on 8K output.
