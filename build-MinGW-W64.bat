@echo off
rem Build the Odin project. Do NOT run premake here: this is an Odin port, and
rem regenerating the C/C++ quickstart makefiles would overwrite the Makefile.
where odin >nul 2>nul
if errorlevel 1 (
    echo odin was not found in PATH.
    echo Install Odin for Windows (https://odin-lang.org) and add it to your PATH.
    pause
    exit /b 1
)
mingw32-make
pause
