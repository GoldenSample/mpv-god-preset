@echo off
if not exist "C:\Users\Administrator\AppData\Roaming\vapoursynth" mkdir "C:\Users\Administrator\AppData\Roaming\vapoursynth"
copy /Y "C:\Apps\mpv\vapoursynth.toml" "C:\Users\Administrator\AppData\Roaming\vapoursynth\vapoursynth.toml"
dir "C:\Users\Administrator\AppData\Roaming\vapoursynth" > "C:\Apps\mpv\_toml_deployed.txt" 2>&1
