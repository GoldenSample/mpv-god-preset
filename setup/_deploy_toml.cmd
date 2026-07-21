@echo off
REM Deploys vapoursynth.toml to %APPDATA%\vapoursynth.
REM Run this OUTSIDE any MSIX container (e.g. as a one-shot Task Scheduler
REM job): inside a container, %APPDATA% writes are virtualized and mpv
REM never sees the file ("Failed to initialize VSScript").
if not exist "%APPDATA%\vapoursynth" mkdir "%APPDATA%\vapoursynth"
copy /Y "C:\Apps\mpv\vapoursynth.toml" "%APPDATA%\vapoursynth\vapoursynth.toml"
dir "%APPDATA%\vapoursynth" > "C:\Apps\mpv\_toml_deployed.txt" 2>&1
