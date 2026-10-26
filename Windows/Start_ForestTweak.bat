@echo off
rem Starts XP12 Forest Tweak (no admin rights needed)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0XP12_ForestTweak.ps1"
rem keep the window open only after an error, so the message can be read
if errorlevel 1 (
    echo.
    pause
)
