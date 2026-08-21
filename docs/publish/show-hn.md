# Show HN

## Title (≤80 chars)
Show HN: A free madVR Envy alternative – real-time neural video pipeline on mpv

## URL
https://github.com/GoldenSample/mpv-god-preset

## First comment (post immediately after submitting)
The madVR Envy Extreme MK2 is a $10k+ video processor box for home theaters with an RTX 4080 inside. My desktop already has a 5090, so the hardware was sitting right there — what was missing was the software. This repo is a week of closing that gap: mpv (vo=gpu-next) → VapourSynth → vs-mlrt/TensorRT running RIFE frame interpolation and AnimeJaNai 2x upscaling in real time, driving a Samsung QN900F 8K panel.

What it does, all with zero dropped frames: RIFE 1080p24 → 143.86 fps; full 4K24 → 71.93 fps; fractional multipliers land PAL 25 fps and NTSC 29.97 at exactly 144.00; upscale+interpolation fused in a single graph with headroom to spare. Envy has no frame interpolation at any price.

The pitfalls were the expensive part, and they're all documented in the README:

- Two separate VapourSynth bridges starve each other (24 fps); fusing both neural steps into one .vpy graph with a single RGB round-trip gives 107 fps. Same math, 4x faster.
- RIFE v4.6 (the SVP-era default) draws a waffle grid on film grain. Newer models (v4.26 / v4.25_lite) are clean.
- Windowed benchmarks lie: d3d11 flip-model presentation silently throttled fullscreen 8K@60 to 31.8 Hz. One line (d3d11-flip=no) took jitter from 1.85 to 0.005.
- The once-per-second microstutter wasn't the player — the NVIDIA driver drops VRAM clocks every second under light load with mixed-refresh dual monitors. An mpv lua hook locking memory clocks via nvidia-smi cut output jitter 650x.
- The mpv→VapourSynth bridge passes _ColorRange but not _Transfer/_Matrix/_Primaries, so HDR gating has to live in lua, not in the graph.

Honest disclosure: this was built pair-programming with an AI assistant; every commit is trailer-signed accordingly. The measurements are from my one panel and one GPU — bring your own numbers, especially whether flip-model chokes 8K output on other setups.
