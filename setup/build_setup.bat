@echo off
rem Builds XP12_ForestTweak_v1.6.0_Setup.exe with Inno Setup 7 (out\ next to this file)
setlocal
set "ISCC="
rem ISCC.exe: from the uninstall entry of Inno Setup in the registry, else in the usual folders
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$k = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'); $l = @(Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Inno Setup*' } | ForEach-Object { $_.InstallLocation }); $l += @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }; $l | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'ISCC.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1"`) do set "ISCC=%%I"
if not defined ISCC (
    echo Inno Setup 7 not found - ISCC.exe was not found in the registry or in Program Files.
    echo Please send a screenshot of the folder where Inno Setup was installed.
    pause
    exit /b 1
)
echo Using %ISCC%
"%ISCC%" "%~dp0XP12_ForestTweak.iss"
echo.
if errorlevel 1 (echo BUILD FAILED - please send a screenshot of the text above.) else (echo Done: %~dp0out)
pause
