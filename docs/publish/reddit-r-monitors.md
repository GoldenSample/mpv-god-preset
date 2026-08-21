# r/Monitors (проверить правила саба; постить руками)

## Title
Samsung QN900F 75" as a 165 Hz PC monitor, three weeks in: bloom mitigation that actually worked, HGiG hidden under a localized name, and what the community consensus got right

## Body
Running the 2025 8K flagship as my only monitor off an RTX 5090 (PC label + Game Mode + Input Signal Plus for 4:4:4, 4K@165 daily). Collected the owner-community consensus, then tested it on the panel. What survived contact:

- **Local Dimming: Standard, not Low.** On this generation Low *reduces zone aggression*, which floods dark-gray windows with a milky glow around text. RTINGS' black-uniformity note ("considerably more haloing in Low") matches what I see. High helps nobody on desktop.
- **Text halo has TWO separate causes.** Move your head sideways 5-10 cm: if the shadow moves with the angle it's the wide-viewing-angle layer (hardware, only fix is centering text windows); if it stays put it's the FALD zones (fixable with settings).
- **Dark themes: never pure black.** #1a1a1a instead of #000 keeps the dimming algorithm asleep. A light theme is the only true zero-bloom mode on mini-LED.
- **HGiG exists but is renamed in localized firmware.** On the Russian firmware it's Game Bar → game settings → Expert → "HDR for games" → "Basic", identified only by a tooltip citing HGiG guidelines. Not present in the normal picture menu at all.
- **Anti-bloom HDR gaming profile that works:** HGiG + in-game peak deliberately below panel max (400-600 nits evenings) + paper white 80-100 + bias light behind the panel. Halo starves when you stop feeding it highlights.
- **Burn-in fear is misplaced on LCD** — the real long-term lottery is DSE/banding. Test gray field uniformity while your return window is alive.

Full write-up, profiles and the mpv/TensorRT pipeline that goes with it: https://github.com/GoldenSample/mpv-god-preset

Disclosure: research and docs were AI-assisted (commits trailer-signed). Panel observations are from my one unit — n=1, bring yours.
