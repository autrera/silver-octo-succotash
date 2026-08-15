# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Project state

- This project is an Odin port of the raylib C quickstart (converted from `src/main.c`); there is no C source left.
- Build with `make` (debug binary in `bin/debug/`); `make release`, `make run`, `make clean` also work. See the Makefile.
- The Odin source imports raylib via the bindings bundled with the Odin toolchain (`import "vendor:raylib"`), which links the prebuilt static lib from `$ODIN_ROOT/vendor/raylib/macos/`.
- Raygui (since the GuiButton/GuiMessageBox integration in `src/main.odin`) is NOT a separate `vendor:raylib/raygui` import: `raygui.odin` ships inside the `vendor:raylib/` package dir, so `rl.GuiButton()`, `rl.GuiMessageBox()` etc. come from the same `rl` import and link `vendor/raylib/macos/libraygui-arm64.a`.
- `GuiMessageBox` returns -1 while open, 0 when closed via the window X, 1/2/... for the Nth button in the `;`-separated buttons string (raygui 4.0). Modal pattern in `src/main.odin`: draw only the message box while open so the trigger button is not clickable.
- On macOS the vendor `libraylib.a` symlink resolves through Homebrew's `/opt/homebrew/opt/raylib`; `libraygui-arm64.a` must be linked before `libraylib.a`, which Odin does automatically.
- On Windows, Odin links the prebuilt static `vendor/raylib/windows/raylib.lib` and `raygui.lib` automatically; no system libs or premake needed. `odin` must be on PATH (e.g. in the w64devkit terminal).
- DANGER: do not run `premake5 gmake` or the old `build/*.bat` regenerate step — it overwrites the hand-written Odin `Makefile` with the C/C++ quickstart makefiles and `make` then fails with `undefined reference to WinMain` (no C source to provide an entry point). `build-MinGW-W64.bat` is already fixed to just run `make`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
