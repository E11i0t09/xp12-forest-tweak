@echo off
rem Starts XP12 Forest Tweak (no admin rights needed)
rem (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0XP12_ForestTweak.ps1"
rem keep the window open only after an error, so the message can be read
if errorlevel 1 (
    echo.
    pause
)
