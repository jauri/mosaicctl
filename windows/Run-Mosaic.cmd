@echo off
rem Menu for configureMosaic.exe. Uses the wall settings at the top of mosaic-cli.ps1.
rem Run as administrator if Apply or Disable report a permissions problem.
setlocal
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mosaic-cli.ps1""

:menu
echo.
echo ===== NVIDIA Mosaic (configureMosaic.exe) =====
echo  Wall: 1x9, 3840x2160 @ 60 Hz, rotate 90 (edit mosaic-cli.ps1 to change)
echo.
echo  1  Help     list the commands and options this driver supports
echo  2  Query    GPUs, displays and current grids          (no change)
echo  3  Test     check the wall layout without applying it (no change)
echo  4  Apply    set up the wall (saves current setup, tests, asks first)
echo  5  Save     print the current setup as a command line (no change)
echo  6  Disable  turn Mosaic off (asks first)
echo  Q  Quit
echo.
set "CHOICE="
set /p CHOICE=Choose:
if /i "%CHOICE%"=="1" %PS% -Action Help
if /i "%CHOICE%"=="2" %PS% -Action Query
if /i "%CHOICE%"=="3" %PS% -Action Test
if /i "%CHOICE%"=="4" %PS% -Action Apply
if /i "%CHOICE%"=="5" %PS% -Action Save
if /i "%CHOICE%"=="6" %PS% -Action Disable
if /i "%CHOICE%"=="q" goto :eof
goto menu
