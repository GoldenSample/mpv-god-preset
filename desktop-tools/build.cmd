@echo off
REM Сборка кнопок панели. Никаких зависимостей: csc есть в любой Windows
REM с .NET Framework (стоит из коробки).
set CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
set OUT=%~dp0

"%CSC%" /nologo /target:winexe /out:"%OUT%SetDisplay.exe" /r:System.Windows.Forms.dll "%OUT%SetDisplay.cs"
"%CSC%" /nologo /target:winexe /out:"%OUT%HdrSwitch.exe" /r:System.Windows.Forms.dll "%OUT%HdrSwitch.cs"

echo.
echo Готово. Проверка:
echo   SetDisplay.exe list          - режимы панели
echo   HdrSwitch.exe status         - код 0=выкл 1=вкл 2=не поддерживается
echo.
echo Ярлыки на рабочий стол делать с аргументами, например:
echo   SetDisplay.exe 7680 4320 60
echo   SetDisplay.exe 3840 2160 165
echo   HdrSwitch.exe on  ^|  HdrSwitch.exe off
pause
