@echo off
rem Double-click this file to run the read-only M0 collector.
rem Right-click > "Run as administrator" to also record whether elevation changes anything.
echo mosaicctl M0 collector (read-only: it does not change any settings)
echo.
echo Suggested labels: baseline, mosaic-on, framelock-on, framelock-off
set /p LABEL=Label for this snapshot:
if "%LABEL%"=="" set LABEL=snapshot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect-m0.ps1" -Label "%LABEL%"
echo.
pause
