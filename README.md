# Raylib Quickstart (Odin)

A 3D planetary drone mining RTS prototype built with [Odin](https://odin-lang.org) and [raylib](https://www.raylib.com).

This project uses Odin, importing raylib via the bindings bundled with the Odin toolchain (`import "vendor:raylib"`).

## Requirements

- **Odin Compiler**: `odin` must be installed and available on your `PATH`. Visit [odin-lang.org](https://odin-lang.org) for installation instructions.
- **Make**: `make` (or `mingw32-make` on Windows).
- **Raylib**: Raylib bindings ship directly with Odin (`vendor:raylib`).
  - On macOS, ensure Raylib is installed (e.g. via `brew install raylib`).
  - On Windows, Odin automatically links the prebuilt static `vendor/raylib/windows/raylib.lib`.
  - On Linux, ensure standard Raylib dependencies (X11, GL, etc.) are present.

## Building and Running

### Using Make

Run commands from the repository root:

- **Build (Debug)**:
  ```sh
  make
  ```
  Builds the binary to `bin/debug/odin-raylib-test` (or `bin/debug/odin-raylib-test.exe` on Windows).

- **Run**:
  ```sh
  make run
  ```
  Builds and runs the game.

- **Build (Release)**:
  ```sh
  make release
  ```
  Builds an optimized binary (`-o:speed`) to `bin/release/odin-raylib-test`.

- **Clean**:
  ```sh
  make clean
  ```
  Removes the `bin/` build directory.

### Direct Odin Commands

You can also build directly using the Odin CLI:

```sh
# Debug build
odin build src -out:bin/debug/odin-raylib-test -debug

# Optimized release build
odin build src -out:bin/release/odin-raylib-test -o:speed
```

### Running Tests

Unit and logic tests live in `src/main_test.odin` and can be run via:

```sh
odin test src -define:ODIN_TEST_THREADS=1
```

*(Single-threaded execution is required as tests mutate shared simulation state).*

## Platform Notes

### Windows
- Install Odin and add it to your `PATH`.
- Use a terminal such as w64devkit, Git Bash, or standard Command Prompt with `mingw32-make`.
- Alternatively, double-click `build-MinGW-W64.bat`, which verifies `odin` is in `PATH` and calls `mingw32-make`.
- Odin automatically links `vendor/raylib/windows/raylib.lib`. No external C/C++ compiler or Premake setup is required.

### macOS
- Install Odin (e.g., `brew install odin`).
- Install raylib if needed (`brew install raylib`).
- Run `make` or `make run`.

### Linux
- Install Odin from the official package or repository.
- Ensure development libraries for OpenGL/X11 are present.
- Run `make` or `make run`.

### VSCode
- Open the project folder in VSCode.
- Recommended extension: `Odin Language Support` (OLS).
- The default build task (`Ctrl+Shift+B` or `Cmd+Shift+B`) will execute `make`.

> [!WARNING]
> Do not run `premake5` or attempt to regenerate C/C++ project files. This repository contains only Odin source code; running premake would overwrite the handwritten `Makefile`.

## Game Overview & Controls

Starfall Command is an RTS prototype where you manage planetary mining operations across the solar system (Mercury through Neptune) while defending against and ultimately assaulting an enemy fortress sector.

### Controls

- **Left-Click**: Select planet, unit, or enemy HQ fortress
- **Right-Click**:
  - With units selected: Issue move/attack order to destination planet or sector
  - With no units selected and Earth selected: Set Earth rally point (right-clicking Earth clears it)
- **Space**: Select Earth in inspector (press again when Earth is selected to center camera on Earth)
- **M / C**: Queue 1 mining drone / 1 combat fighter (Earth selected)
- **N / X**: Queue +5 mining drones / +5 combat fighters (Earth selected)
- **1 - 9**: Recall saved squad
- **Shift + 1 - 9**: Save current unit selection to squad
- **P / F10**: Open Pause Menu
- **F5**: Quick-save game to `savegame.txt`
- **ESC**: Cancel most recently queued unit build / dismiss modal overlays
- **U**: Purchase drone build speed upgrade (Earth command base)
- **Shift + M / Shift + C**: Batch-queue 5 miners / 5 combat drones (available at max build speed)

## Project Structure

- `src/main.odin`: Game simulation, rendering, audio, UI, and save system
- `src/main_test.odin`: Logic and regression test suite
- `Makefile`: Hand-written cross-platform build script for Odin
- `build-MinGW-W64.bat`: Windows batch launcher for `make`
- `savegame.txt`: Saved game state file (gitignored)

## License

Raylib-Quickstart base by Jeffery Myers is marked with CC0 1.0. To view a copy of this license, visit https://creativecommons.org/publicdomain/zero/1.0/
