@echo off
REM Build the desktop buttons. Zero dependencies: csc ships with every
REM Windows that has .NET Framework (installed out of the box).
set CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
set OUT=%~dp0

"%CSC%" /nologo /target:winexe /out:"%OUT%SetDisplay.exe" /r:System.Windows.Forms.dll "%OUT%SetDisplay.cs"
"%CSC%" /nologo /target:winexe /out:"%OUT%HdrSwitch.exe" /r:System.Windows.Forms.dll "%OUT%HdrSwitch.cs"

echo.
echo Done. Quick check:
echo   SetDisplay.exe list          - panel modes
echo   HdrSwitch.exe status         - exit code 0=off 1=on 2=unsupported
echo.
echo Make desktop shortcuts with arguments, for example:
echo   SetDisplay.exe 7680 4320 60
echo   SetDisplay.exe 3840 2160 165
echo   HdrSwitch.exe on  ^|  HdrSwitch.exe off
pause
