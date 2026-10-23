@echo off
rem Starts XP12 Forest Tweak (no admin rights needed)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0XP12_ForestTweak_GlobalForestsV2.ps1"
echo.
pause
