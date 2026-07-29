# Home theater preset: RTX 3060 Ti + AVR + 4K TV

A complete `portable_config` for mpv, built for a specific setup — RTX 3060 Ti,
i5-12400, a 4K TV behind an AV receiver — and for a specific set of habits
formed by years of MPC-HC + madVR. Everything madVR did for this setup is
covered, without the abandoned binary and without a $10k appliance:

| madVR habit | What does it here |
|---|---|
| Bitstream Dolby/DTS to the AVR | `audio-spdif` + WASAPI exclusive, on by default |
| Display mode switching (23.976 for movies) | `scripts/auto-refresh.lua` + `tools/set-refresh.ps1` (pure Win32, no nircmd) |
| Per-content profiles (anime vs movies) | `[auto-anime]` — release-group tags in the filename switch deband on; movies stay untouched |
| Envy's non-linear stretch (2.35:1 → 16:9) | `[scope-fill]` profile + `shaders/nls-scope.glsl`, key `n` |
| Debanding | mpv's native deband, keys 1/2/3 = the same values as the "Deband MPV" HLSL shaders (that shader was a port of mpv's deband in the first place) |
| HDR to the TV untouched | `target-colorspace-hint=yes` |

Deliberately NOT here: RIFE interpolation and AnimeJaNai neural upscaling.
They live in the main preset of this repo and want more GPU than a 3060 Ti
has at 4K. `video-sync=display-resample` at a matched refresh gives
judder-free 24p without any of that.

## Install

1. Get mpv for Windows (shinchiro build): https://mpv.io/installation/
2. Unpack it anywhere, e.g. `C:\Apps\mpv\`.
3. Copy this `portable_config` folder next to `mpv.exe` (that activates
   portable mode — no registry, no AppData).
4. Play any file with `mpv.exe`. Done.

If mpv picks the wrong audio device (TV instead of AVR), run
`mpv --audio-device=help` and pin the right one in `mpv.conf` (`audio-device=`).

## Keys

| Key | Action |
|---|---|
| `n` / `N` | NLS scope-fill on / off (2.35:1 fills the screen, faces stay round) |
| `1` `2` `3` | deband light / medium / strong |
| `5` | deband for HDR (near-zero grain) |
| `0` | deband off — also the escape hatch when anime autodetect guesses wrong |
| `b` | deband toggle with current values |
| `a` | audio passthrough toggle (off = PCM decode in mpv) |
| `H` | auto refresh switching on / off |
| `TAB` | stats: fps, drops, filters, whether passthrough is active |

## The 23.976 note (read once)

`auto-refresh.lua` switches the display to 23 Hz (= 23.976) or 24 Hz when a
film-cadence file loads, and restores your desktop rate on quit. NVIDIA
usually does NOT expose 23.976 out of the box — create it once in NVIDIA
Control Panel → Change resolution → Customize → 3840x2160 @ 23 Hz. True
24.000 usually exists already; the script tries both.

## Anime autodetect

`[auto-anime]` matches release-group tags (`SubsPlease`, `Erai-raws`,
`HorribleSubs`, `EMBER`, `ASW`, `Judas`, `Commie`, `nyaa`) and any `anime`
folder in the path. Hit — deband on with anime-tuned values. Miss — nothing
is touched, movies play clean. Extend the list in `mpv.conf`, one string per
tag. Wrong guess on a specific file: key `0`.

## Still on MPC-HC?

The NLS stretch works there too, today, without switching players:
`../../mpc-hc/nls-scope-vertical.hlsl` — instructions in the file header.
Two steps: force 16:9 aspect, add the shader as pre-resize. Works with madVR
as the renderer.

## Porting your exact madVR taste

madVR keeps its settings in the registry (not in `settings.bin`, unless you
put one there yourself). Export them with:

```
reg export "HKCU\Software\madshi\madVR" madvr_settings.reg
```

— and the deband/sharpen values can be translated into this config's terms.
