---
name: ui-capture
description: Take deterministic screenshots of the running game (inspector panel, HUD, menus, any state) to verify UI or rendering changes visually. Use whenever you need to see what the game looks like, check a UI change, compare before/after, or reproduce a visual bug, instead of writing a throwaway capture harness.
---

# ui-capture

A reusable screenshot harness for this Odin/raylib game. You write a small scenario (a step function that puts the game into a state and requests shots), and `capture.sh` temporarily injects the harness into `src/`, builds a separate binary, runs the real game window, writes PNGs, and restores the source tree byte-for-byte, even when the build or run fails.

## Files

- `capture.sh` - the driver. Usage: `bash .claude/skills/ui-capture/capture.sh <scenario.odin> [out_dir]`.
- `capture.odin` - the engine (step sequencer, shot cropping/export, mouse override, state helpers). Copied to `src/zz_capture.odin` during a run.
- `scenario_template.odin` - a working example scenario. Copy it, never edit it for a one-off task.

## Workflow

1. Copy the template to a scratch path outside the repo, e.g. `cp .claude/skills/ui-capture/scenario_template.odin "$TMP/scenario.odin"`, and edit the `capture_scenario` switch.
2. Run `bash .claude/skills/ui-capture/capture.sh "$TMP/scenario.odin"`. Default output dir is `$TMP/ui-capture` (cleared of PNGs at start). It prints a `CAPTURE_SHOT <path> <w>x<h> step=<n>` line per image and `OUT_DIR <dir>` at the end.
3. Look at each PNG with the Read tool using the printed path.

The game opens a real borderless window on the primary monitor for a second or two; that is expected. The build goes to `bin/capture/` (gitignored), so `bin/debug/` is untouched. Exit codes: 2 bad args, 3 a hook anchor changed, 4 the run did not reach `CAPTURE_DONE` (log tail is printed; the full log is `<out_dir>/run.log`), other non-zero is the Odin compile error.

## Scenario API

A scenario is `package main` and defines `capture_scenario :: proc(step: int) -> (done: bool)`. Steps run in order starting at 0; return `true` from the first step that has nothing left to do. Shots requested in a step are taken after the state has rendered for the settle frames, so set state and request the shot in the same step.

- `capture_shot(name, region = .PANEL, rect = {})` - queue a PNG named `<name>.png`. Regions: `.FULL` whole screen; `.PANEL` the right inspector, full height or `rect.height` if given (e.g. `{height = 520}`); `.RECT` any rect in virtual UI coordinates (the same coordinates the draw code uses). Up to 32 shots per step.
- `capture_wait(frames)` - override the settle time for this step (default 2 frames after a 3-frame warmup). Use it to let animations, fades, or the simulation advance.
- `capture_hover(rect)` / `capture_hover_point(p)` - move the virtual mouse (also produces a non-zero `ui_mouse_delta`, so `menu_hover_index` reacts). `capture_park_mouse()` moves it off-screen. The mouse is parked by default, so the real OS cursor never leaks into a shot.
- `capture_enter_game()` - same as NEW GAME from the start menu (`restart_game`, leaves the start menu, unpauses). Step 0 without it shows the start menu.
- `capture_liberate(planet)` - zero the planet's base HP and remove its enemy units. `capture_clear_enemies(sector)` only removes enemies (stops combat from undoing state you set, e.g. a refinery under construction).
- `capture_panel_x()` - the inspector's panel x, for the rect helpers (`miner_button_rect(capture_panel_x())`, `queue_slot_rect`, etc.). `capture_dock_rect()` - the bottom-left area with the TUTORIAL button.

Anything else is plain game state: assign globals (`minerals`, `selected_planet`, `base_counts[EARTH]`, `refinery_building[p]`, `orbital_defense_level[p]`, ...) or call game procs (`toggle_pause()`, `open_manual()`, `queue_unit(.MINING)`, `start_refinery_construction(p)`). Call `units_changed()` after adding, removing, or moving units yourself.

## Timing model

`capture_tick` runs once per frame after everything is drawn and before `rl.EndDrawing()`. It first waits for the boot loading screen to finish fading (`loading_overlay_alpha() > 0`), so step 0 sees the start menu. To shoot the loading screen itself, add `@(init) capture_scenario_init :: proc "contextless" () { capture_wait_loading = false }` to the scenario. After the warmup it flushes queued shots, then calls the next step, then waits the settle frames. The simulation keeps running (unpaused) during settle frames, so state can drift: combat kills miners, an unpaused clock advances. Keep settle short, clear enemies where combat would interfere, or pause and accept the pause overlay. `CAPTURE_TIMEOUT_FRAMES` (20000) and a 300s `timeout` stop a stuck run.

## Limitations

- No synthetic keyboard input and no synthetic mouse button state: `rl.IsMouseButtonDown` / `IsKeyPressed` read the real device. Reach pressed or key-driven states by setting state or calling the procs directly.
- Only `ui_mouse` and `ui_mouse_delta` are overridden. Code that calls `rl.GetMousePosition` directly bypasses the override (project rule says it should not exist).
- Screen size is whatever the primary monitor gives the borderless window; the first log line `CAPTURE_SCREEN w h ui_scale dpi` records it. On the current dev box that is 1536x960 logical at 125% DPI, so PNGs are 1.25x the virtual size.

## How it works (for maintenance)

- `capture.sh` backs up `src/main.odin` and `src/ui_scale.odin`, copies the engine and scenario into `src/zz_capture*.odin`, and inserts three hook lines with `sed`: `capture_tick()` before the `rl.EndDrawing()` line in `main.odin`, and an early `if capture_mouse_override { return ... }` at the top of `ui_mouse` and `ui_mouse_delta` in `ui_scale.odin`. Each hook must match exactly once or the script aborts with exit 3 - if one of those anchor lines is renamed or reformatted, update the `sed` patterns. An `EXIT` trap copies the backups back and deletes the injected files.
- The engine reads one frame with `rlgl.DrawRenderBatchActive()` + `rl.LoadImageFromScreen()` (raylib does not flush the batch itself, so late 2D draws would be missing otherwise), converts to `UNCOMPRESSED_R8G8B8` (otherwise translucent UI leaves alpha holes that read as a grey wash), and crops per request with `ImageCopy` + `ImageCrop`.
- Virtual UI coordinates map to image pixels with `k = image.width / GetScreenWidth() * ui_scale`. Crop rects are floored/ceiled to whole pixels and clamped to the image: fractional crop rects crashed raylib's `ImageCrop` silently (the process just died with exit 127).
- Project rules apply to the harness files too: no comments in `capture.odin`, `capture.sh`, or scenarios; put knowledge in this file.

## Extending

Add reusable helpers to `capture.odin` when a scenario needed something non-trivial that will recur (a new region preset, a state setup like "outpost with refinery and battery", synthetic input via another hook). New hooks go in `capture.sh` next to the existing three, each with a `check_hook` line. Re-run the template scenario afterwards to confirm the harness still works and the source tree comes back clean (`git status`).
