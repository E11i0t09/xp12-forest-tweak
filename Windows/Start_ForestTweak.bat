@echo off
rem Starts the XP12 Forest Tweak window (no admin rights needed). Console menu: Start_ForestTweak_Console.bat
rem (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0XP12_ForestTweak_Gui.ps1"
rem keep this window open only after an error, so the message can be read
if errorlevel 1 (
    echo.
    pause
)
