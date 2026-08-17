# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Project state

- This project is an Odin port of the raylib C quickstart (converted from `src/main.c`); there is no C source left.
- Build with `make` (debug binary in `bin/debug/`); `make release`, `make run`, `make clean` also work. See the Makefile.
- The Odin source imports raylib via the bindings bundled with the Odin toolchain (`import "vendor:raylib"`), which links the prebuilt static lib from `$ODIN_ROOT/vendor/raylib/macos/`.
- Raygui (since the GuiButton/GuiMessageBox integration in `src/main.odin`) is NOT a separate `vendor:raylib/raygui` import: `raygui.odin` ships inside the `vendor:raylib/` package dir, so `rl.GuiButton()`, `rl.GuiMessageBox()` etc. come from the same `rl` import and link `vendor/raylib/macos/libraygui-arm64.a`.
- `GuiMessageBox` returns -1 while open, 0 when closed via the window X, 1/2/... for the Nth button in the `;`-separated buttons string (raygui 4.0). Modal pattern in `src/main.odin`: draw only the message box while open so the trigger button is not clickable.
- Combat is planet-general: `update_enemy_waves` runs `update_planet_combat` per planet; guarding fighters trade 1:1 every `COMBAT_TICK` (2s); undefended player miners die every 2s; enemy waves spawn from Jupiter (`planets[2]`) and target Mars. Jupiter opens as an enemy stronghold (40 fighters + 10 miners + 20 HP base); conquest: clear fighters → sweep enemy miners → damage the base (1 HP per player fighter per 2s) → `jupiter_liberated()` unlocks base construction. Enemy miners are static garrison units that mine nothing.
- Guarding fighters render representationally PER SIDE (`rep_count` = ceil(count/10)): 5 enemies show as 1 red cube even alongside player cubes; lasers are pulsing bolts between the visible cubes of engaged sides. `main_test.odin` drives `update_enemy_waves`/`update_planet_combat` with `COMBAT_TICK`-sized steps; `reset_world` must restore `enemy_base_hp`, `base_counts`, timers and minerals for isolation.
- On macOS the vendor `libraylib.a` symlink resolves through Homebrew's `/opt/homebrew/opt/raylib`; `libraygui-arm64.a` must be linked before `libraylib.a`, which Odin does automatically.
- On Windows, Odin links the prebuilt static `vendor/raylib/windows/raylib.lib` and `raygui.lib` automatically; no system libs or premake needed. `odin` must be on PATH (e.g. in the w64devkit terminal).
- Enemy waves (`update_enemy_waves` in `src/main.odin`): every `WAVE_INTERVAL` (120s) a wave of `WAVE_SIZE` (5) enemy fighters transits to Mars. Combat pacing at Mars: with both sides' fighters guarding there, one drone on each side is destroyed per second (5v5 lasts ~5s, 1:1 trade); with no player defenders left, one Mars mining drone dies per 2s. Surviving enemies then orbit Mars until the player dispatches fighters to retake it. `N` forces a wave immediately (debug affordance, shown in the HUD status line).
- DANGER: do not run `premake5 gmake` or the old `build/*.bat` regenerate step — it overwrites the hand-written Odin `Makefile` with the C/C++ quickstart makefiles and `make` then fails with `undefined reference to WinMain` (no C source to provide an entry point). `build-MinGW-W64.bat` is already fixed to just run `make`.
- Logic tests live in `src/main_test.odin` (same package, excluded from `make` builds because Odin skips `*_test.odin` files) and run with `odin test src -define:ODIN_TEST_THREADS=1`. The single-threaded define is required: the tests mutate shared globals (`units`, timers) and the default parallel runner races them.
- Visual verification on this dev box: `screencapture` lacks screen-recording permission and window-compositor captures are stale. For headless visual checks, temporarily render into `rl.LoadRenderTexture` + `rl.LoadImageFromTexture` + `rl.ExportImage` (framebuffer export, no window server involved); pass relative filenames — raylib resolves them against the working directory.
- `Unit` carries an `enemy: bool` flag: player combat drones render sky-blue, enemy combat drones red, player mining drones orange (`draw_fighter`). Enemies are excluded from the inspector roster and selection (`unit_in_roster`).
- Mining drones work their home planet by default: `spawn_unit(.MINING, planet)` starts `.MINING` with `target_planet = affiliation = planet`, so Earth drones mine Earth (1 mineral/3s cycle) instead of heading to Mars; right-click orders can still dispatch them.
- Camera pans only via WASD/arrows + Q/E/mouse-wheel zoom; mouse screen-edge panning was removed and must not be re-added.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
