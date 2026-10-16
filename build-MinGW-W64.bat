@echo off
where odin >nul 2>nul
if errorlevel 1 (
    echo odin was not found in PATH.
    echo Install Odin for Windows (https://odin-lang.org) and add it to your PATH.
    pause
    exit /b 1
)
mingw32-make
pause
