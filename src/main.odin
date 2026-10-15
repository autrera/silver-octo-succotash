package main

import "core:math"
import "core:mem"
import "core:c"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import "core:time"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// ---- Starting Setup on Earth (Tweakable Globals) ------------------------
STARTING_EARTH_MINERS := 5
STARTING_EARTH_COMBAT := 0
STARTING_EARTH_BASES := 1
STARTING_EARTH_ORBITAL_DEFENSE := 1
STARTING_EARTH_REFINERY := true
STARTING_HQ_ORBITAL_DEFENSE := 10

ENEMY_HQ_POSITION := rl.Vector3{140, 5, 24}
GARRISON_FIGHTERS := [SECTOR_COUNT]int{30, 15, 0, 20, 75, 60, 45, 95, ENEMY_HQ_GARRISON}
GARRISON_MINERS := [SECTOR_COUNT]int{8, 4, 0, 6, 10, 14, 18, 22, 0}
GARRISON_BASE_HP := [SECTOR_COUNT]int{20, 10, 0, 15, 30, 40, 50, 60, ENEMY_HQ_BASE_HP}

planets := [PLANET_COUNT]Planet{
	{name = "MERCURY", position = {-30, 2, 8}, radius = 1.6, color = rl.Color{150, 148, 145, 255}},
	{name = "VENUS", position = {-15, 0.8, -4}, radius = 2.6, color = rl.Color{230, 200, 130, 255}},
	{name = "EARTH", position = {0, 0, 0}, radius = 3.0, color = rl.Color{45, 125, 220, 255}},
	{name = "MARS", position = {22, 1, 6}, radius = 2.2, color = rl.Color{215, 80, 55, 255}},
	{name = "JUPITER", position = {50, 2.5, -12}, radius = 4.2, color = rl.Color{215, 175, 110, 255}},
	{name = "SATURN", position = {-25, 3, 18}, radius = 3.8, color = rl.Color{225, 205, 155, 255}},
	{name = "URANUS", position = {5, 4, -20}, radius = 3.0, color = rl.Color{170, 225, 230, 255}},
	{name = "NEPTUNE", position = {35, 5, 24}, radius = 2.9, color = rl.Color{80, 110, 220, 255}},
}

// Procedural textured planet models
planet_models: [PLANET_COUNT]rl.Model
planet_textures: [PLANET_COUNT]rl.Texture2D
planet_visuals_ready := false
planet_spin: [PLANET_COUNT]f32

drone_models: [Drone_Model_Kind]rl.Model
drone_visuals_ready := false

units: [MAX_UNITS]Unit
unit_count: int
selected_units: [MAX_UNITS]bool
planet_miner_counts: [PLANET_COUNT]int
planet_combat_counts: [PLANET_COUNT]int
planet_mining_miners: [PLANET_COUNT]int
planet_unit_cache_dirty := true
selected_planet := EARTH
minerals := 350
mineral_accumulator: f32 = 0
drone_speed_level := 0
auto_build_mode: Auto_Build_Mode = .OFF
auto_build_last_mode: Auto_Build_Mode = .MINERS
autobuild_retry_timer: f32 = 0
base_counts: [PLANET_COUNT]int
production: [PLANET_COUNT][MAX_BASES]Production
pending: [PLANET_COUNT][MAX_PENDING]Unit_Type
pending_count: [PLANET_COUNT]int
base_build_progress: f32
base_build_planet := -1

refinery_built: [PLANET_COUNT]bool
refinery_building: [PLANET_COUNT]bool
refinery_progress: [PLANET_COUNT]f32

orbital_defense_level: [SECTOR_COUNT]int
orbital_defense_building: [SECTOR_COUNT]bool
orbital_defense_progress: [SECTOR_COUNT]f32
orbital_defense_hp: [SECTOR_COUNT]int
orbital_defense_angle: [SECTOR_COUNT]f32
orbital_defense_elevation: [SECTOR_COUNT]f32
orbital_defense_wave_kills: [SECTOR_COUNT]int
orbital_defense_reset_timer: [SECTOR_COUNT]f32
orbital_defense_fire_timer: [SECTOR_COUNT]f32
orbital_defense_ammo: [SECTOR_COUNT]int
orbital_defense_ammo_pending_kills: [SECTOR_COUNT]int
orbital_defense_ammo_pending: [SECTOR_COUNT][ORBITAL_DEFENSE_AMMO_MAX]int
orbital_defense_ammo_pending_count: [SECTOR_COUNT]int
orbital_defense_ammo_building: [SECTOR_COUNT]bool
orbital_defense_ammo_progress: [SECTOR_COUNT]f32
construction_seq_counter := 0
refinery_build_order: [PLANET_COUNT]int
orbital_defense_build_order: [SECTOR_COUNT]int
base_build_order: [PLANET_COUNT]int

orbital_defense_blasts: [MAX_ORBITAL_BLASTS]Orbital_Defense_Blast
camera: rl.Camera3D
camera_target := rl.Vector3{10, 0, 2}
inspector_drag_start: rl.Vector2
inspector_drag_active: bool
last_unit_click_time: time.Tick
last_unit_clicked_index := -1
last_unit_clicked_planet := -1

enemy_base_hp: [SECTOR_COUNT]int
enemy_wave_timer: f32
wave_started: bool
minor_wave_timer: f32
combat_timer: [SECTOR_COUNT]f32
miner_timer: [SECTOR_COUNT]f32
base_timer: [SECTOR_COUNT]f32
combat_vision_timer: [SECTOR_COUNT]f32

game_paused := false
controls_overlay_open := false
quit_requested := false
victory := false
defeated := false
earth_rally := NO_RALLY
last_known_intel: [PLANET_COUNT]Intel
intel_recorded: [PLANET_COUNT]bool
laser_anim_time: f32
combat_nebula_intensity: [SECTOR_COUNT]f32
minor_wave_source_nebula_intensity: [SECTOR_COUNT]f32
sector_combat_state: [SECTOR_COUNT]bool
world_sector_spots: [SECTOR_COUNT]World_Sector_Spots

// Visual intensity of Earth's manufacturing industry lights [0..1]: flares up
// when units or bases are being constructed on Earth, turning surface lights on and off.
earth_industry_intensity: f32

// Start game menu & save notification state
in_start_menu := true
start_menu_selection := 0
hud_save_notification_timer: f32
save_feedback_timer: f32

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 760, "STARFALL COMMAND: Planetary RTS Prototype")
	defer rl.CloseWindow()
	rl.ToggleBorderlessWindowed()

	// VSYNC handles refresh timing (60Hz / 120Hz). Setting target FPS to 2x the monitor
	// refresh rate acts as an upper safety cap for unconstrained runs while ensuring raylib's
	// internal WaitTime nanosleep never oversleeps into the next hardware vblank cycle (which
	// would otherwise cause the display to drop cadence from 60 FPS down to 30 FPS).
	refresh := rl.GetMonitorRefreshRate(rl.GetCurrentMonitor())
	target_fps := refresh > 0 ? max(refresh, 60) : 60
	rl.SetTargetFPS(target_fps * 2)

	rl.SetExitKey(.KEY_NULL) // ESC cancels the last queued build instead of closing the window; P/F10 pause.

	reset_world()
	initialize_game()
	init_planet_visuals()
	defer unload_planet_visuals()
	init_drone_visuals()
	defer unload_drone_visuals()
	camera = rl.Camera3D{
		position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y},
		target = camera_target,
		up = {0, 1, 0},
		fovy = 45,
		projection = .PERSPECTIVE,
	}
	in_start_menu = true
	start_menu_selection = 0

	for !rl.WindowShouldClose() && !quit_requested {
		if rl.IsKeyPressed(.F11) || ((rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)) && rl.IsKeyPressed(.ENTER)) {
			rl.ToggleBorderlessWindowed()
		}
		dt := rl.GetFrameTime()
		if in_start_menu {
			update_start_menu(dt)
		} else if victory {
			update_victory_overlay()
		} else if defeated {
			update_game_over_overlay()
		} else if controls_overlay_open {
			update_controls_overlay()
		} else {
			if pause_key_pressed() { toggle_pause() }
			if game_paused {
				update_pause_menu(dt)
			} else {
				step_simulation(dt)
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{8, 12, 24, 255})
		draw_world()
		if in_start_menu {
			draw_start_menu()
		} else {
			draw_inspector()
			if victory {
				draw_victory_overlay()
			} else if defeated {
				draw_game_over_overlay()
			} else if controls_overlay_open {
				draw_controls_overlay()
			} else if game_paused { draw_pause_menu() }
		}
		rl.EndDrawing()
	}
}

initialize_game :: proc() {
	planet_unit_cache_dirty = true
	auto_build_mode = .OFF
	auto_build_last_mode = .MINERS
	autobuild_retry_timer = 0
	base_counts = {}
	base_counts[EARTH] = STARTING_EARTH_BASES
	refinery_built = {}
	refinery_built[EARTH] = STARTING_EARTH_REFINERY
	orbital_defense_level = {}
	orbital_defense_level[EARTH] = STARTING_EARTH_ORBITAL_DEFENSE
	orbital_defense_level[ENEMY_HOME] = STARTING_HQ_ORBITAL_DEFENSE
	orbital_defense_hp = {}
	orbital_defense_hp[EARTH] = orbital_defense_max_hp(EARTH)
	orbital_defense_hp[ENEMY_HOME] = orbital_defense_max_hp(ENEMY_HOME)
	orbital_defense_ammo = {}
	orbital_defense_ammo[EARTH] = ORBITAL_DEFENSE_START_AMMO
	orbital_defense_ammo[ENEMY_HOME] = ORBITAL_DEFENSE_AMMO_MAX
orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_ammo_building = {}
	orbital_defense_ammo_progress = {}
	orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_elevation[EARTH] = ORBITAL_DEFENSE_IDLE_ELEV
	orbital_defense_elevation[ENEMY_HOME] = ORBITAL_DEFENSE_IDLE_ELEV
	enemy_base_hp = GARRISON_BASE_HP
	unit_count = 0
	for _ in 0..<STARTING_EARTH_MINERS {
		spawn_unit(.MINING, EARTH)
	}
	for i in 0..<STARTING_EARTH_COMBAT {
		angle := f32(i) * (2 * math.PI / f32(max(1, STARTING_EARTH_COMBAT)))
		pos := orbit_pos(planets[EARTH].position, planets[EARTH].radius, angle)
		units[unit_count] = Unit{
			kind = .COMBAT,
			state = .GUARDING,
			position = pos,
			home_planet = EARTH,
			affiliation = EARTH,
			target_planet = EARTH,
			orbit_angle = angle,
		}
		unit_count += 1
	}
	// Space backdrop: deterministic starfield (independent of the wave RNG).
	generate_stars()
	// Every non-Earth sector opens occupied: the GARRISON_* tables form the
	// fixed occupation ladder (Venus easiest ... Neptune hardest, HQ last) -
	// after the Earth-centered repositioning this no longer tracks distance.
	for p in 0..<SECTOR_COUNT {
		if p == EARTH { continue }
		spawn_garrison(p, GARRISON_FIGHTERS[p], GARRISON_MINERS[p])
	}
	combat_nebula_intensity[ENEMY_HOME] = 0.65
}

// Clean-slate reset shared by the victory-restart path and the test suite
// (tests call it to isolate scenarios). initialize_game rebuilds the world
// on top of this zeroed state.
reset_world :: proc() {
	unit_count = 0
	for i := 0; i < MAX_UNITS; i += 1 {
		units[i] = {}
		selected_units[i] = false
	}
	for p in 0..<SECTOR_COUNT {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
		combat_vision_timer[p] = 0
	}
	enemy_base_hp = GARRISON_BASE_HP
	base_counts = {}
	base_counts[EARTH] = STARTING_EARTH_BASES
	base_build_planet = -1
	base_build_progress = 0
	refinery_built = {}
	refinery_built[EARTH] = STARTING_EARTH_REFINERY
	refinery_building = {}
	refinery_progress = {}
	orbital_defense_level = {}
	orbital_defense_building = {}
	orbital_defense_progress = {}
	orbital_defense_hp = {}
	orbital_defense_angle = {}
	for p in 0..<SECTOR_COUNT {
		orbital_defense_elevation[p] = ORBITAL_DEFENSE_IDLE_ELEV
	}
	orbital_defense_wave_kills = {}
	orbital_defense_reset_timer = {}
	orbital_defense_fire_timer = {}
	orbital_defense_ammo = {}
	orbital_defense_ammo_building = {}
	orbital_defense_ammo_progress = {}
	orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_blasts = {}
	construction_seq_counter = 0
	refinery_build_order = {}
	orbital_defense_build_order = {}
	base_build_order = {}
	minerals = 350
	mineral_accumulator = 0
	enemy_wave_timer = 0
	wave_started = false
	minor_wave_timer = 0
	selected_planet = EARTH
	production = {}
	pending_count = {}
	last_known_intel = {}
	intel_recorded = {}
	laser_anim_time = 0
	combat_nebula_intensity = {}
	minor_wave_source_nebula_intensity = {}
	earth_industry_intensity = 0
	drone_speed_level = 0
	earth_rally = NO_RALLY
	auto_build_mode = .OFF
	auto_build_last_mode = .MINERS
	autobuild_retry_timer = 0
	planet_unit_cache_dirty = true
	victory = false
	defeated = false
	game_paused = false
	controls_overlay_open = false
	in_start_menu = false
	hud_save_notification_timer = 0
	save_feedback_timer = 0
	last_unit_clicked_index = -1
	last_unit_clicked_planet = -1
	last_unit_click_time = {}
	rl.SetRandomSeed(7)
}

// Each occupied planet opens with standing fighting and mining drones
// orbiting it, plus an enemy base. Enemy miners are static garrison units;
// they mine nothing.
// ponytail: no enemy economy, revisit if waves should scale with looted minerals
spawn_garrison :: proc(p, fighters, miners: int) {
	for i in 0..<fighters {
		angle := f32(i) * (2 * math.PI / f32(fighters))
		units[unit_count] = Unit{
			kind = .COMBAT, state = .GUARDING, position = orbit_pos(sector_pos(p), sector_radius(p), angle),
			home_planet = p, affiliation = p, target_planet = p,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
	for i in 0..<miners {
		angle := f32(i) * (2 * math.PI / f32(miners)) + 0.3
		units[unit_count] = Unit{
			kind = .MINING, state = .GUARDING, position = orbit_pos(sector_pos(p), sector_radius(p), angle),
			home_planet = p, affiliation = p, target_planet = p,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

// Position on the guarding orbit ring around any sector center (a planet
// or the enemy HQ).
sector_pos :: proc(s: int) -> rl.Vector3 {
	if s == ENEMY_HOME { return ENEMY_HQ_POSITION }
	return planets[s].position
}

sector_radius :: proc(s: int) -> f32 {
	if s == ENEMY_HOME { return ENEMY_HQ_RADIUS }
	return planets[s].radius
}

orbit_pos :: proc(center: rl.Vector3, radius, angle: f32) -> rl.Vector3 {
	return {center.x + math.cos(angle) * (radius + 1.5), center.y + 1.0, center.z + math.sin(angle) * (radius + 1.5)}
}

update_camera :: proc(dt: f32) {
	direction := rl.Vector3{}
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { direction.z -= 1 }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { direction.z += 1 }
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { direction.x -= 1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { direction.x += 1 }
	if rl.Vector3Length(direction) > 0 {
		direction = rl.Vector3Normalize(direction)
		camera_target.x += direction.x * dt * 15
		camera_target.z += direction.z * dt * 15
	}
	zoom := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.MINUS) { zoom -= dt * 3 }
	if rl.IsKeyDown(.E) || rl.IsKeyDown(.EQUAL) { zoom += dt * 3 }
	zoom_y := camera.position.y - zoom * 2.2
	zoom_y = clamp(zoom_y, 15, 200)
	camera.position.x = camera_target.x
	camera.position.y = zoom_y
	camera.position.z = camera_target.z + camera.position.y * 1.0
	camera.target = camera_target
	camera.up = {0, 1, 0}
}

update_input :: proc() {
	// ESC cancels the most recently queued unit and refunds it.
	if rl.IsKeyPressed(.ESCAPE) { cancel_last_queued() }
	// Build shortcuts use the same validation path as the inspector buttons.
	if rl.IsKeyPressed(.M) {
		if shift_down() && can_build_5_miners() {
			queue_5_miners()
		} else {
			queue_unit(.MINING)
		}
	}
	if rl.IsKeyPressed(.C) {
		if shift_down() && can_build_5_combat() {
			queue_5_combat()
		} else {
			queue_unit(.COMBAT)
		}
	}
	// [N] queues +5 mining drones (Earth only, unlocked at 5 bases).
	if !ctrl_down() && rl.IsKeyPressed(.N) {
		if can_build_5_miners() {
			queue_5_miners()
		}
	}
	// [X] queues +5 combat fighters (Earth only, unlocked at 5 bases).
	if rl.IsKeyPressed(.X) {
		if can_build_5_combat() {
			queue_5_combat()
		}
	}
	// [T] toggles autobuilder mode (Earth only, unlocked at 5 bases).
	if rl.IsKeyPressed(.T) && can_use_autobuilder() {
		toggle_autobuild_mode()
	}
	// [U] buys the next drone build-speed upgrade level (Earth only).
	if rl.IsKeyPressed(.U) { purchase_drone_speed_upgrade() }
	// [B] builds a refinery on the selected liberated planet.
	if rl.IsKeyPressed(.B) {
		if selected_planet != EARTH && selected_planet != ENEMY_HOME && can_build_refinery(selected_planet) {
			start_refinery_construction(selected_planet)
		}
	}
	// [O] builds or upgrades orbital defense on the selected planet.
	if orbital_defense_key_pressed() {
		trigger_selected_orbital_defense()
	}
	// Spacebar is a shortcut to select Earth in the inspector;
	// pressing it again when Earth is already selected centers the camera at Earth.
	if rl.IsKeyPressed(.SPACE) { select_earth() }
	// Squad control groups: Shift+digit saves the selection, digit recalls it.
	// IsKeyPressed is edge-triggered, so held-key repeat never re-triggers.
	if group := squad_key_pressed(); group > 0 {
		if shift_down() { save_squad(group) } else { recall_squad(group) }
	}
	// Debug: force the next enemy wave immediately with Ctrl+N (verify combat without waiting 3 minutes).
	if ctrl_down() && rl.IsKeyPressed(.N) { spawn_enemy_wave() }
	// F5 quick-saves the game.
	if rl.IsKeyPressed(.F5) {
		if save_game() {
			hud_save_notification_timer = 2.0
		}
	}
	mouse := rl.GetMousePosition()
	panel_x := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mouse, controls_button_rect()) {
			last_unit_clicked_index = -1
			open_controls_overlay()
			return
		}
		if mouse.x >= panel_x {
			// Sidebar presses start a potential drag; click vs box-select is
			// decided on release. World selection never sees sidebar input.
			inspector_drag_start = mouse
			inspector_drag_active = true
		} else {
			last_unit_clicked_index = -1
			if planet := pick_planet(mouse); planet >= 0 {
				selected_planet = planet
			} else if ov_p := pick_conquered_planet_overlay(mouse); ov_p >= 0 {
				selected_planet = ov_p
			} else if hq_picked(mouse) {
				selected_planet = ENEMY_HOME
			} else if !ctrl_down() {
				clear_selection()
			}
		}
	} else if rl.IsMouseButtonReleased(.LEFT) && inspector_drag_active {
		inspector_drag_active = false
		handle_inspector_release(mouse, panel_x)
	}
	if rl.IsMouseButtonPressed(.RIGHT) && mouse.x < panel_x {
		if planet := pick_planet(mouse); planet >= 0 {
			handle_planet_right_click(planet)
		} else if ov_p := pick_conquered_planet_overlay(mouse); ov_p >= 0 {
			handle_planet_right_click(ov_p)
		} else if hq_picked(mouse) {
			handle_planet_right_click(ENEMY_HOME)
		}
	}
}

ctrl_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}

// Horizontal world-space offset so Earth projects to the center of the visible
// viewport beside the right-docked planet inspector (SCREEN_PANEL_WIDTH).
earth_camera_offset_x :: proc() -> f32 {
	screen_h := f32(rl.GetScreenHeight() > 0 ? rl.GetScreenHeight() : 760)
	zoom_y := camera.position.y > 0 ? camera.position.y : CAMERA_START_Y
	return f32(SCREEN_PANEL_WIDTH) * zoom_y * (2.0 - math.sqrt(f32(2.0))) / screen_h
}

center_camera_on_earth :: proc() {
	camera_target = planets[EARTH].position
	camera_target.x += earth_camera_offset_x()
	camera.position.x = camera_target.x
	camera.position.z = camera_target.z + camera.position.y * 1.0
	camera.target = camera_target
}

// SPACE in update_input jumps the inspector straight to Earth;
// pressing it again when Earth is already selected centers the camera at Earth.
select_earth :: proc() {
	if selected_planet == EARTH {
		center_camera_on_earth()
	} else {
		selected_planet = EARTH
		last_unit_clicked_index = -1
	}
}

// Digit keys 1..9 map to control groups; 0 = no squad key this frame.
squad_key_pressed :: proc() -> int {
	for k in rl.KeyboardKey.ONE..=rl.KeyboardKey.NINE {
		if rl.IsKeyPressed(k) { return int(k) - int(rl.KeyboardKey.ONE) + 1 }
	}
	return 0
}

clear_selection :: proc() {
	for i := 0; i < MAX_UNITS; i += 1 { selected_units[i] = false }
}

orbital_defense_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.O)
}

trigger_selected_orbital_defense :: proc() -> bool {
	if selected_planet >= 0 && selected_planet < PLANET_COUNT && selected_planet != ENEMY_HOME {
		if can_build_orbital_defense(selected_planet) {
			start_orbital_defense_construction(selected_planet)
			return true
		}
		if can_build_orbital_ammo(selected_planet) {
			start_orbital_ammo_construction(selected_planet)
			return true
		}
	}
	return false
}

handle_inspector_click :: proc(mouse: rl.Vector2, panel_x: f32) {
	// The two production buttons and base button are deliberately ordinary rectangles,
	// keeping the inspector usable even when raygui styles are unavailable.
	// Base construction and unit production exist only on Earth.
	if selected_planet == EARTH {
		if base_button_visible() && rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}) {
			last_unit_clicked_index = -1
			start_base_construction()
			return
		}
		if rl.CheckCollisionPointRec(mouse, orbital_defense_button_rect(panel_x, EARTH)) {
			last_unit_clicked_index = -1
			if can_build_orbital_defense(EARTH) {
				start_orbital_defense_construction(EARTH)
			} else if rl.CheckCollisionPointRec(mouse, orbital_ammo_button_rect(panel_x, EARTH)) && can_build_orbital_ammo(EARTH) {
				start_orbital_ammo_construction(EARTH)
			}
			return
		}
		orders_y := f32(production_orders_y())
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			last_unit_clicked_index = -1
			queue_unit(.MINING)
			return
		}
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			last_unit_clicked_index = -1
			queue_unit(.COMBAT)
			return
		}
		if base_counts[EARTH] >= MAX_BASES {
			off_rect, miner_rect, combat_rect := autobuild_radio_rects(panel_x)
			if rl.CheckCollisionPointRec(mouse, off_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.OFF)
				return
			}
			if rl.CheckCollisionPointRec(mouse, miner_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.MINERS)
				return
			}
			if rl.CheckCollisionPointRec(mouse, combat_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.COMBAT)
				return
			}
			if rl.CheckCollisionPointRec(mouse, queue_5_miner_button_rect(panel_x)) {
				last_unit_clicked_index = -1
				queue_5_miners()
				return
			}
			if rl.CheckCollisionPointRec(mouse, queue_5_combat_button_rect(panel_x)) {
				last_unit_clicked_index = -1
				queue_5_combat()
				return
			}
		}
		if !drone_speed_maxed() && rl.CheckCollisionPointRec(mouse, drone_speed_button_rect(panel_x)) {
			last_unit_clicked_index = -1
			purchase_drone_speed_upgrade()
			return
		}
		// Clicking an occupied build-queue slot cancels that unit (refund included).
		for slot := 0; slot < queued_count(EARTH); slot += 1 {
			if rl.CheckCollisionPointRec(mouse, queue_slot_rect(panel_x, slot)) {
				last_unit_clicked_index = -1
				cancel_queued_at(EARTH, slot)
				return
			}
		}
	} else if selected_planet >= 0 && selected_planet < PLANET_COUNT && selected_planet != ENEMY_HOME {
		if can_build_refinery(selected_planet) && rl.CheckCollisionPointRec(mouse, refinery_button_rect(panel_x)) {
			last_unit_clicked_index = -1
			start_refinery_construction(selected_planet)
			return
		}
		if rl.CheckCollisionPointRec(mouse, orbital_defense_button_rect(panel_x, selected_planet)) {
			last_unit_clicked_index = -1
			if can_build_orbital_defense(selected_planet) {
				start_orbital_defense_construction(selected_planet)
			} else if rl.CheckCollisionPointRec(mouse, orbital_ammo_button_rect(panel_x, selected_planet)) && can_build_orbital_ammo(selected_planet) {
				start_orbital_ammo_construction(selected_planet)
			}
			return
		}
	}
	if click_unit_tiles(mouse, panel_x, .MINING) || click_unit_tiles(mouse, panel_x, .COMBAT) { return }
	last_unit_clicked_index = -1
	if !ctrl_down() { clear_selection() }
}

// A press in the inspector is a click when released with little movement,
// otherwise it becomes a drag box-select across unit tiles.
handle_inspector_release :: proc(mouse: rl.Vector2, panel_x: f32) {
	if rl.Vector2Distance(mouse, inspector_drag_start) < 4 {
		handle_inspector_click(mouse, panel_x)
		return
	}
	box_select(mouse, panel_x)
}

// Every unit tile intersecting the drag rectangle is selected on release.
// Plain drag replaces the selection, Shift adds to it, Ctrl toggles each tile.
box_select :: proc(mouse: rl.Vector2, panel_x: f32) {
	last_unit_clicked_index = -1
	// Ghost tiles are a frozen snapshot, not live units: nothing to select.
	if ghost_view() { return }
	rect := rect_between(inspector_drag_start, mouse)
	replace := !ctrl_down() && !shift_down()
	if replace { clear_selection() }
	m_ord := 0
	c_ord := 0
	y_mining := unit_tile_y(.MINING)
	y_combat := unit_tile_y(.COMBAT)
	for i := 0; i < unit_count; i += 1 {
		kind := units[i].kind
		if !unit_in_roster(i, kind) { continue }
		ord := kind == .MINING ? m_ord : c_ord
		y := kind == .MINING ? y_mining : y_combat
		if kind == .MINING { m_ord += 1 } else { c_ord += 1 }
		tile := unit_tile_rect(panel_x, y, ord)
		if rl.CheckCollisionRecs(tile, rect) {
			if ctrl_down() { selected_units[i] = !selected_units[i] } else { selected_units[i] = true }
		}
	}
}

rect_between :: proc(a, b: rl.Vector2) -> rl.Rectangle {
	return rl.Rectangle{min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}
}

shift_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
}

// Clicking a unit tile selects that unit; holding Ctrl toggles it.
// Double-clicking a unit tile selects all units of that type on the planet;
// holding Ctrl keeps other selected units and adds all units of that type.
click_unit_tiles :: proc(mouse: rl.Vector2, panel_x: f32, kind: Unit_Type) -> bool {
	if ghost_view() { return false }
	ordinal := 0
	y := unit_tile_y(kind)
	now := time.tick_now()
	for i := 0; i < unit_count; i += 1 {
		if !unit_in_roster(i, kind) { continue }
		if rl.CheckCollisionPointRec(mouse, unit_tile_rect(panel_x, y, ordinal)) {
			is_double_click := false
			if last_unit_clicked_index == i && last_unit_clicked_planet == selected_planet {
				elapsed := time.duration_seconds(time.tick_diff(last_unit_click_time, now))
				if elapsed >= 0 && elapsed <= DOUBLE_CLICK_TIME {
					is_double_click = true
				}
			}

			if is_double_click {
				last_unit_clicked_index = -1
				if !ctrl_down() {
					clear_selection()
				}
				for j := 0; j < unit_count; j += 1 {
					if unit_in_roster(j, kind) {
						selected_units[j] = true
					}
				}
			} else {
				last_unit_clicked_index = i
				last_unit_clicked_planet = selected_planet
				last_unit_click_time = now
				if !ctrl_down() {
					clear_selection()
					selected_units[i] = true
				} else {
					selected_units[i] = !selected_units[i]
				}
			}
			return true
		}
		ordinal += 1
	}
	return false
}

// The construct-base button disappears once Earth holds MAX_BASES bases and
// none is under construction; a lost base brings it back.
base_button_visible :: proc() -> bool {
	return base_counts[EARTH] < MAX_BASES || base_build_planet == EARTH
}

// A command base needs a liberated Earth and BASE_COST minerals; it queues
// with no crew. Miners already mining Earth join immediately; the rest
// auto-join as they finish depositing on Earth (update_miner). The
// BASE_CONSTRUCT_TIME clock runs only with a full crew, and everyone resumes
// mining after.
start_base_construction :: proc() {
	if selected_planet != EARTH { return } // Command bases build on Earth only.
	if base_counts[selected_planet] >= MAX_BASES || base_build_planet >= 0 || minerals < BASE_COST { return }
	if !planet_liberated(selected_planet) { return }
	minerals -= BASE_COST
	base_build_planet = selected_planet
	base_build_progress = 0
	construction_seq_counter += 1
	base_build_order[EARTH] = construction_seq_counter

	// Pass 1: recruit idle miners on Earth immediately
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			if u.target_planet == EARTH || u.affiliation == EARTH {
				if base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .BASE
					u.progress = 0
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	}
	// Pass 2: recruit active miners (mining or depositing) on Earth if crew still needed
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			if u.target_planet == EARTH || u.affiliation == EARTH {
				if (u.state == .MINING || u.state == .DEPOSITING) && base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .BASE
					u.progress = 0
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	}
}

// Refinery cost: amount of drones required to mine the planet times 10.
refinery_cost :: proc(planet: int) -> int {
	return planet_mining_cap(planet) * 10
}

can_build_refinery :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	if !planet_liberated(planet) { return false }
	if refinery_built[planet] || refinery_building[planet] { return false }
	return minerals >= refinery_cost(planet)
}

refinery_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, REFINERY_BTN_Y, PANEL_CONTENT_W, BASE_BTN_H}
}

refinery_button_visible :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	return planet_liberated(planet)
}

// A refinery requires a liberated planet and planet_mining_cap(planet) * 10 minerals.
// It queues with no crew; miners already present join immediately, and newly arriving
// miners auto-join (update_miner). The REFINERY_BUILD_TIME clock runs only with a full crew
// of REFINERY_CONSTRUCT_MINERS (10), and all crew members resume mining after.
start_refinery_construction :: proc(planet: int) {
	if !can_build_refinery(planet) { return }
	minerals -= refinery_cost(planet)
	refinery_building[planet] = true
	refinery_progress[planet] = 0
	construction_seq_counter += 1
	refinery_build_order[planet] = construction_seq_counter

	// Pass 1: recruit idle miners first
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state == .IDLE {
			if refinery_constructing_miners(planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.build_target = .REFINERY
				u.progress = 0
				u.mining_active = false
			}
		}
	}

	// Pass 2: recruit active mining drones if crew still needed
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state == .MINING {
			if refinery_constructing_miners(planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.build_target = .REFINERY
				u.progress = 0
				u.mining_active = false
			}
		}
	}
}

// A planet can be mined once it is liberated and has an operational refinery.
planet_can_mine :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT { return false }
	return planet_liberated(planet) && refinery_built[planet]
}

// An off-world planet has an operational refinery beam connecting to Earth once its refinery is built.
planet_has_refinery_beam :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	return refinery_built[planet]
}

// Player miners currently on a planet's build crew.
constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p { count += 1 }
	}
	return count
}

refinery_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .REFINERY || (u.build_target == .NONE && !orbital_defense_building[p] && !orbital_defense_ammo_building[p] && base_build_planet != p) {
				count += 1
			}
		}
	}
	return count
}

orbital_defense_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .ORBITAL_DEFENSE || (u.build_target == .NONE && !refinery_building[p] && !orbital_defense_ammo_building[p] && base_build_planet != p) {
				count += 1
			}
		}
	}
	return count
}

base_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .BASE || (u.build_target == .NONE && !refinery_building[p] && !orbital_defense_building[p] && !orbital_defense_ammo_building[p]) {
				count += 1
			}
		}
	}
	return count
}

planet_next_needed_build_target :: proc(p: int) -> Build_Target {
	if p < 0 || p >= PLANET_COUNT { return .NONE }

	if p == EARTH {
		needs_base := (base_build_planet == EARTH) && base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS
		needs_defense := orbital_defense_building[EARTH] && orbital_defense_constructing_miners(EARTH) < ORBITAL_DEFENSE_CONSTRUCT_MINERS
		needs_ammo := orbital_defense_ammo_building[EARTH] && orbital_ammo_constructing_miners(EARTH) < ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS

		if needs_base && needs_defense {
			if base_build_order[EARTH] <= orbital_defense_build_order[EARTH] {
				return .BASE
			} else {
				return .ORBITAL_DEFENSE
			}
		} else if needs_base {
			return .BASE
		} else if needs_defense {
			return .ORBITAL_DEFENSE
		} else if needs_ammo {
			return .ORBITAL_DEFENSE_AMMO
		}
		return .NONE
	}

	needs_refinery := refinery_building[p] && refinery_constructing_miners(p) < REFINERY_CONSTRUCT_MINERS
	needs_defense := orbital_defense_building[p] && orbital_defense_constructing_miners(p) < ORBITAL_DEFENSE_CONSTRUCT_MINERS
	needs_ammo := orbital_defense_ammo_building[p] && orbital_ammo_constructing_miners(p) < ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS

	if needs_refinery && needs_defense {
		if refinery_build_order[p] <= orbital_defense_build_order[p] {
			return .REFINERY
		} else {
			return .ORBITAL_DEFENSE
		}
	} else if needs_refinery {
		return .REFINERY
	} else if needs_defense {
		return .ORBITAL_DEFENSE
	} else if needs_ammo {
		return .ORBITAL_DEFENSE_AMMO
	}
	return .NONE
}

// True while any player miner not already on the build crew is assigned to
// Earth (route target or creation planet): base recruitment prefers these
// over foreign-route drones that merely deposit at Earth mid-route.
earth_assigned_miner_available :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state == .CONSTRUCTING { continue }
		if u.target_planet == EARTH || u.affiliation == EARTH { return true }
	}
	return false
}

// Mining drones already committed to the active build site on a planet.
constructing_miners_at :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .CONSTRUCTING && u.target_planet == p { count += 1 }
	}
	return count
}

// Resume constructing miners after a structure completes.
// If another structure on the planet still needs crew, miners transition to that project.
// When all construction completes, miners resume .MINING if the planet has an
// operational refinery (or Earth), otherwise they hold in .IDLE in orbit.
resume_constructing_miners :: proc(p: int, finished: Build_Target = .NONE) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if finished == .NONE || u.build_target == finished || u.build_target == .NONE {
				next_target := planet_next_needed_build_target(p)
				if next_target != .NONE {
					u.build_target = next_target
					u.progress = 0
					u.mining_active = false
				} else {
					u.build_target = .NONE
					u.progress = 0
					if planet_can_mine(p) && active_mining_drones_count(p) < planet_mining_cap(p) {
						u.state = .MINING
						u.mining_active = true
					} else {
						u.state = .IDLE
						u.mining_active = false
					}
				}
			}
		}
	}
}

// ---- Orbital Defense ---------------------------------------------------

orbital_defense_max_hp :: proc(planet: int) -> int {
	if planet < 0 || planet >= SECTOR_COUNT { return 0 }
	return orbital_defense_level[planet] * ORBITAL_DEFENSE_HP_PER_LEVEL
}

orbital_defense_pos :: proc(planet: int) -> rl.Vector3 {
	if planet == ENEMY_HOME {
		return ENEMY_HQ_POSITION + {0.3, 1.95, 0}
	}
	if planet < 0 || planet >= PLANET_COUNT { return {} }
	p := planets[planet]
	return rl.Vector3{
		p.position.x,
		p.position.y + p.radius,
		p.position.z,
	}
}

closest_approaching_enemy :: proc(planet: int) -> (^Unit, bool) {
	if planet < 0 || planet >= SECTOR_COUNT { return nil, false }
	target_pos := sector_pos(planet)
	max_range := sector_radius(planet) + ORBITAL_DEFENSE_TARGET_RANGE
	closest_idx := -1
	closest_dist: f32 = 1e9

	for i in 0..<unit_count {
		u := &units[i]
		// Strictly target approaching combat fighters in transit; never target units that have already reached orbit (.GUARDING)
		is_target := (planet == ENEMY_HOME) ? (!u.enemy) : (u.enemy)
		if !is_target || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != planet { continue }
		d := distance(u.position, target_pos)
		if d <= max_range && d < closest_dist {
			closest_dist = d
			closest_idx = i
		}
	}

	if closest_idx >= 0 {
		return &units[closest_idx], true
	}
	return nil, false
}

orbital_defense_aim_toward :: proc(planet_idx: int, target: rl.Vector3) -> (azimuth: f32, elev: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return 0, 0 }
	if planet_idx == ENEMY_HOME {
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		diff := target - pivot
		horiz_d := math.sqrt(diff.x * diff.x + diff.z * diff.z)
		azimuth = math.atan2(diff.z, diff.x)
		raw_elev := horiz_d > 0.001 ? math.atan2(diff.y, horiz_d) : (math.PI * 0.25)
		elev = clamp(raw_elev, 8.0 * rl.DEG2RAD, 85.0 * rl.DEG2RAD)
		return
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	pivot := pole + rl.Vector3{0, 0.58 * s, 0}
	diff := target - pivot
	horiz_d := math.sqrt(diff.x * diff.x + diff.z * diff.z)
	azimuth = math.atan2(diff.z, diff.x)
	raw_elev := horiz_d > 0.001 ? math.atan2(diff.y, horiz_d) : (math.PI * 0.25)
	elev = clamp(raw_elev, 8.0 * rl.DEG2RAD, 85.0 * rl.DEG2RAD)
	return
}

orbital_defense_muzzle_pos_toward :: proc(planet_idx: int, target: rl.Vector3) -> rl.Vector3 {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return {} }
	if planet_idx == ENEMY_HOME {
		azimuth, elev := orbital_defense_aim_toward(planet_idx, target)
		cos_az := math.cos(azimuth)
		sin_az := math.sin(azimuth)
		up := rl.Vector3{0, 1, 0}
		fwd := rl.Vector3{cos_az, 0, sin_az}
		cos_el := math.cos(elev)
		sin_el := math.sin(elev)
		barrel_dir := fwd * cos_el + up * sin_el
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		return pivot + barrel_dir * 3.25
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	azimuth, elev := orbital_defense_aim_toward(planet_idx, target)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)
	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	cos_el := math.cos(elev)
	sin_el := math.sin(elev)
	barrel_dir := fwd * cos_el + up * sin_el
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	return pivot + barrel_dir * (1.97 * s)
}

shortest_angle_diff :: proc(target, current: f32) -> f32 {
	diff := target - current
	for diff < -math.PI { diff += 2 * math.PI }
	for diff >  math.PI { diff -= 2 * math.PI }
	return diff
}

advance_orbital_defense_aim :: proc(planet_idx: int, dt: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return }
	if orbital_defense_level[planet_idx] <= 0 { return }

	// If upgrading (planets only), hold azimuth and park elevation in maintenance cradle (16 deg)
	if planet_idx < PLANET_COUNT && orbital_defense_building[planet_idx] {
		target_el: f32 = ORBITAL_DEFENSE_PARK_ELEV
		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
		return
	}

	enemy, has_enemy := closest_approaching_enemy(planet_idx)
	if has_enemy {
		// Active tracking: smoothly rotate azimuth and pitch elevation toward enemy
		target_az, target_el := orbital_defense_aim_toward(planet_idx, enemy.position)

		az_diff := shortest_angle_diff(target_az, orbital_defense_angle[planet_idx])
		max_az := ORBITAL_DEFENSE_TRACK_SPEED * dt
		if abs(az_diff) <= max_az {
			orbital_defense_angle[planet_idx] = target_az
		} else {
			orbital_defense_angle[planet_idx] += math.sign(az_diff) * max_az
		}

		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
	} else {
		// Idle scan: continue rotating forward from current azimuth without warping back
		orbital_defense_angle[planet_idx] += ORBITAL_DEFENSE_SCAN_SPEED * dt

		// Smoothly return elevation to idle resting angle
		target_el: f32 = ORBITAL_DEFENSE_IDLE_ELEV
		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
	}

	// Normalize azimuth to [-PI, PI)
	for orbital_defense_angle[planet_idx] < -math.PI {
		orbital_defense_angle[planet_idx] += 2 * math.PI
	}
	for orbital_defense_angle[planet_idx] >= math.PI {
		orbital_defense_angle[planet_idx] -= 2 * math.PI
	}
}

orbital_defense_aim :: proc(planet_idx: int) -> (azimuth: f32, elev: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return 0, 0 }
	if planet_idx < PLANET_COUNT && orbital_defense_building[planet_idx] {
		return orbital_defense_angle[planet_idx], ORBITAL_DEFENSE_PARK_ELEV
	}
	if planet_idx == ENEMY_HOME && (enemy_hq_destroyed() || orbital_defense_hp[ENEMY_HOME] <= 0) {
		return orbital_defense_angle[planet_idx], -0.32
	}
	return orbital_defense_angle[planet_idx], orbital_defense_elevation[planet_idx]
}

orbital_defense_muzzle_pos :: proc(planet_idx: int) -> rl.Vector3 {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return {} }
	if planet_idx == ENEMY_HOME {
		azimuth, elev := orbital_defense_aim(planet_idx)
		cos_az := math.cos(azimuth)
		sin_az := math.sin(azimuth)
		up := rl.Vector3{0, 1, 0}
		fwd := rl.Vector3{cos_az, 0, sin_az}
		cos_el := math.cos(elev)
		sin_el := math.sin(elev)
		barrel_dir := fwd * cos_el + up * sin_el
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		return pivot + barrel_dir * 3.25
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	azimuth, elev := orbital_defense_aim(planet_idx)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)
	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	cos_el := math.cos(elev)
	sin_el := math.sin(elev)
	barrel_dir := fwd * cos_el + up * sin_el
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	return pivot + barrel_dir * (1.97 * s)
}


spawn_orbital_defense_blast :: proc(planet: int, from, to: rl.Vector3, duration: f32 = 0.35) {
	oldest_idx := 0
	oldest_elapsed: f32 = -1.0
	for i in 0..<MAX_ORBITAL_BLASTS {
		if !orbital_defense_blasts[i].active {
			oldest_idx = i
			break
		}
		if orbital_defense_blasts[i].elapsed > oldest_elapsed {
			oldest_elapsed = orbital_defense_blasts[i].elapsed
			oldest_idx = i
		}
	}
	orbital_defense_blasts[oldest_idx] = Orbital_Defense_Blast{
		active = true,
		planet = planet,
		from = from,
		to = to,
		elapsed = 0,
		duration = duration,
	}
}

update_orbital_defense_blasts :: proc(dt: f32) {
	for i in 0..<MAX_ORBITAL_BLASTS {
		if !orbital_defense_blasts[i].active { continue }
		orbital_defense_blasts[i].elapsed += dt
		if orbital_defense_blasts[i].elapsed >= orbital_defense_blasts[i].duration {
			orbital_defense_blasts[i].active = false
		}
	}
}

draw_orbital_defense_blasts :: proc() {
	for i in 0..<MAX_ORBITAL_BLASTS {
		b := &orbital_defense_blasts[i]
		if !b.active { continue }
		if distance(b.from, b.to) < 0.05 { continue }
		if !has_vision(b.planet) && b.planet != ENEMY_HOME { continue }

		t := clamp(b.elapsed / b.duration, 0.0, 1.0)
		fade := 1.0 - t
		alpha := u8(clamp(255.0 * fade, 0, 255))
		glow_alpha := u8(clamp(180.0 * fade, 0, 255))
		shock_alpha := u8(clamp(200.0 * fade, 0, 255))

		// Distinct palettes: Crimson/amber for Enemy HQ, cyan/mint for Player Planets
		beam_color := rl.Color{0, 240, 255, glow_alpha}
		core_color := rl.Color{255, 255, 255, alpha}
		line_color := rl.Color{210, 255, 255, alpha}
		shock_color := rl.Color{130, 255, 245, shock_alpha}
		spark_color := rl.Color{255, 240, 180, alpha}

		if b.planet == ENEMY_HOME {
			beam_color = rl.Color{255, 30, 45, glow_alpha}
			core_color = rl.Color{255, 240, 220, alpha}
			line_color = rl.Color{255, 120, 100, alpha}
			shock_color = rl.Color{255, 60, 75, shock_alpha}
			spark_color = rl.Color{255, 160, 80, alpha}
		}

		// 1. Big Laser Blast Beam (from orbital defense station to target fighter)
		core_r := 0.22 * fade + 0.04
		rl.DrawCylinderEx(b.from, b.to, core_r, core_r * 0.75, 8, core_color)

		// Outer glowing plasma cylinder: wide luminous aura
		glow_r := 0.65 * fade + 0.12
		rl.DrawCylinderEx(b.from, b.to, glow_r, glow_r * 0.75, 8, beam_color)

		// Central accelerator beam core line
		rl.DrawLine3D(b.from, b.to, line_color)

		// 2. Muzzle Flash & Discharge at Orbital Defense Station (b.from)
		flash_r := 0.55 * fade + 0.08
		rl.DrawSphere(b.from, flash_r * 0.6, core_color)
		rl.DrawSphereEx(b.from, flash_r, 8, 12, beam_color)
		rl.DrawCircle3D(b.from, 0.5 + t * 1.0, {0, 1, 0}, 90, beam_color)

		// 3. Vaporization Impact & Explosion at the Enemy Fighter (b.to)
		burst_r := 0.40 + 1.5 * math.sqrt(t)
		rl.DrawSphere(b.to, 0.30 * fade, core_color)
		rl.DrawSphereEx(b.to, burst_r * 0.75, 8, 12, beam_color)

		// Expanding vector wireframe sphere shockwave
		shock_r := 0.45 + 2.4 * t
		rl.DrawSphereWires(b.to, shock_r, 6, 8, shock_color)
		// Expanding horizontal planar tactical shockwave ring
		rl.DrawCircle3D(b.to, shock_r * 1.2, {0, 1, 0}, 90, beam_color)

		// High-energy plasma sparks and debris radiating outward from the blast
		spark_dist := t * 3.4
		for k in 0..<8 {
			ang := f32(k) * (math.PI / 4.0)
			elev := (f32(k % 3) - 1.0) * 0.55
			spark_dir := rl.Vector3Normalize(rl.Vector3{math.cos(ang), elev, math.sin(ang)})
			spark_pos := b.to + spark_dir * spark_dist
			trail_pos := b.to + spark_dir * (spark_dist * 0.65)
			rl.DrawLine3D(trail_pos, spark_pos, beam_color)
			rl.DrawSphere(spark_pos, 0.08 * fade, spark_color)
		}
	}
}

player_miners_count :: proc(planet: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy {
			if planet == EARTH {
				if u.target_planet == EARTH || u.affiliation == EARTH { count += 1 }
			} else {
				if u.target_planet == planet { count += 1 }
			}
		}
	}
	return count
}

can_build_orbital_defense :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == ENEMY_HOME { return false }
	if !planet_liberated(planet) { return false }
	if orbital_defense_building[planet] { return false }
	if orbital_defense_level[planet] > 0 { return false }
	if minerals < ORBITAL_DEFENSE_COST { return false }
	if planet == EARTH {
		return player_miners_count(EARTH) >= ORBITAL_DEFENSE_CONSTRUCT_MINERS
	}
	return true
}

orbital_ammo_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p && u.build_target == .ORBITAL_DEFENSE_AMMO {
			count += 1
		}
	}
	return count
}

can_build_orbital_ammo :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == ENEMY_HOME { return false }
	if orbital_defense_level[planet] <= 0 { return false }
	if orbital_defense_building[planet] { return false }
	if orbital_defense_ammo[planet] + orbital_defense_ammo_pending_count[planet] >= ORBITAL_DEFENSE_AMMO_MAX { return false }
	if minerals < ORBITAL_DEFENSE_AMMO_COST { return false }
	return player_miners_at_planet(planet) >= ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS
}

start_orbital_ammo_construction :: proc(planet: int) {
	if !can_build_orbital_ammo(planet) { return }
	minerals -= ORBITAL_DEFENSE_AMMO_COST
	orbital_defense_ammo_pending_count[planet] += 1
	if !orbital_defense_ammo_building[planet] {
		orbital_defense_ammo_building[planet] = true
		orbital_defense_ammo_progress[planet] = 0
		recruit_build_crew(planet, .ORBITAL_DEFENSE_AMMO, ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS)
	}
}

queued_ammo_at :: proc(p: int, slot: int) -> bool {
	return slot >= orbital_defense_ammo[p] && slot < orbital_defense_ammo[p] + orbital_defense_ammo_pending_count[p]
}

// queued ammo helper moved lower

// Shared single-miner or multi-miner recruitment used by ammo construction:
// idle miners first, then active mining/depositing miners.
recruit_build_crew :: proc(planet: int, target: Build_Target, need: int) {
	count_crew := proc(p: int, t: Build_Target) -> int {
		n := 0
		for i := 0; i < unit_count; i += 1 {
			u := &units[i]
			if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p && u.build_target == t { n += 1 }
		}
		return n
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
			} else {
				is_match = (u.target_planet == planet)
			}
			if is_match && count_crew(planet, target) < need {
				u.state = .CONSTRUCTING
				u.build_target = target
				u.progress = 0
				u.target_planet = planet
				u.affiliation = planet
				u.mining_active = false
			}
		}
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH) && (u.state == .MINING || u.state == .DEPOSITING)
			} else {
				is_match = (u.target_planet == planet) && (u.state == .MINING)
			}
			if is_match && count_crew(planet, target) < need {
				u.state = .CONSTRUCTING
				u.build_target = target
				u.progress = 0
				u.target_planet = planet
				u.affiliation = planet
				u.mining_active = false
			}
		}
	}
}

// Miners physically available at a planet for a 1-drone ammo crew (idle,
// mining, depositing or already constructing there).
player_miners_at_planet :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		count += 1
	}
	return count
}

start_orbital_defense_construction :: proc(planet: int) {
	if !can_build_orbital_defense(planet) { return }
	minerals -= ORBITAL_DEFENSE_COST
	orbital_defense_building[planet] = true
	orbital_defense_progress[planet] = 0
	orbital_defense_elevation[planet] = ORBITAL_DEFENSE_PARK_ELEV
	construction_seq_counter += 1
	orbital_defense_build_order[planet] = construction_seq_counter

	// Pass 1: recruit idle miners first
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
			} else {
				is_match = (u.target_planet == planet)
			}
			if is_match {
				if orbital_defense_constructing_miners(planet) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .ORBITAL_DEFENSE
					u.progress = 0
					u.target_planet = planet
					u.affiliation = planet
					u.mining_active = false
				}
			}
		}
	}

	// Pass 2: recruit active miners (mining or depositing) if crew still needed
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH) && (u.state == .MINING || u.state == .DEPOSITING)
			} else {
				is_match = (u.target_planet == planet) && (u.state == .MINING)
			}
			if is_match {
				if orbital_defense_constructing_miners(planet) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .ORBITAL_DEFENSE
					u.progress = 0
					u.target_planet = planet
					u.affiliation = planet
					u.mining_active = false
				}
			}
		}
	}
}

destroy_orbital_defense :: proc(planet: int) {
	orbital_defense_level[planet] = 0
	orbital_defense_hp[planet] = 0
	orbital_defense_building[planet] = false
	orbital_defense_progress[planet] = 0
	orbital_defense_ammo[planet] = 0
	orbital_defense_ammo_building[planet] = false
	orbital_defense_ammo_progress[planet] = 0
	orbital_defense_angle[planet] = 0
	orbital_defense_elevation[planet] = (planet == ENEMY_HOME) ? -0.32 : ORBITAL_DEFENSE_IDLE_ELEV
	orbital_defense_wave_kills[planet] = 0
	orbital_defense_reset_timer[planet] = 0
	for i := unit_count - 1; i >= 0; i -= 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state != .TRANSIT {
			remove_unit_at(i)
		}
	}
	if planet != EARTH && planet < PLANET_COUNT {
		refinery_built[planet] = false
		refinery_building[planet] = false
		refinery_progress[planet] = 0
	}
}

earth_orbital_defense_y :: proc() -> f32 {
	if !base_button_visible() {
		return SECTION_TOP
	}
	y: f32 = SECTION_TOP + BASE_BTN_H + 8
	return y
}

earth_orbital_defense_bottom_y :: proc() -> f32 {
	return earth_orbital_defense_y() + orbital_defense_section_height(EARTH)
}

orbital_defense_section_height :: proc(p: int) -> f32 {
	if p >= 0 && p < SECTOR_COUNT && orbital_defense_level[p] > 0 && !orbital_defense_building[p] {
		return GRID_PITCH + QUEUE_SLOT_H
	}
	return BASE_BTN_H
}

outpost_orbital_defense_y :: proc(planet: int) -> f32 {
	return ORBITAL_DEFENSE_BTN_Y
}

outpost_orbital_defense_bottom_y :: proc(planet: int) -> f32 {
	return outpost_orbital_defense_y(planet) + orbital_defense_section_height(planet)
}

outpost_liberated_roster_y :: proc(planet: int) -> int {
	return int(outpost_orbital_defense_bottom_y(planet) + 10 + 23)
}

orbital_defense_button_rect :: proc(panel_x: f32, planet: int) -> rl.Rectangle {
	if planet == EARTH {
		return rl.Rectangle{panel_x + PANEL_PAD_X, earth_orbital_defense_y(), PANEL_CONTENT_W, BASE_BTN_H}
	} else {
		return rl.Rectangle{panel_x + PANEL_PAD_X, outpost_orbital_defense_y(planet), PANEL_CONTENT_W, BASE_BTN_H}
	}
}

orbital_defense_base_y :: proc(planet: int) -> f32 {
	if planet == EARTH { return earth_orbital_defense_y() }
	return outpost_orbital_defense_y(planet)
}

orbital_ammo_button_rect :: proc(panel_x: f32, planet: int) -> rl.Rectangle {
	base_y := orbital_defense_base_y(planet)
	half := (PANEL_CONTENT_W - PANEL_PAD_X) / 2
	return rl.Rectangle{panel_x + PANEL_PAD_X, base_y, f32(half), BASE_BTN_H}
}

orbital_ammo_slot_rect :: proc(panel_x: f32, planet: int, slot: int) -> rl.Rectangle {
	half := (PANEL_CONTENT_W - PANEL_PAD_X) / 2
	base_x := panel_x + PANEL_PAD_X + f32(half) + f32(PANEL_PAD_X)
	base_y := orbital_defense_base_y(planet)
	row := slot / 5
	column := slot % 5
	return rl.Rectangle{base_x + f32(column * 28), base_y + f32(row * GRID_PITCH), 24, QUEUE_SLOT_H}
}

orbital_ammo_queue_head :: proc(p: int) -> int {
	return orbital_defense_ammo[p]
}

draw_orbital_ammo_slot :: proc(rect: rl.Rectangle, filled: bool, progress: f32 = -1) {
	color := SCIFI_PANEL_SOLID
	border := SCIFI_DIM
	if filled {
		color = rl.Color{0, 65, 85, 255}
		border = SCIFI_CYAN
	}
	draw_chamfered_panel(rect, 3, color, border)
	if progress >= 0 {
		fill_rect := rl.Rectangle{rect.x, rect.y, rect.width * clamp(progress, 0, 1), rect.height}
		rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 140})
	}
	if filled || progress >= 0 {
		draw_corner_brackets(rect, 1, 3, border)
		symbol: cstring = "A"
		tw := f32(rl.MeasureText(symbol, 12))
		tx := rect.x + (rect.width - tw) / 2
		ty := rect.y + (rect.height - 12) / 2
		accent := SCIFI_AMBER
		rl.DrawText(symbol, c.int(tx + 1), c.int(ty + 1), 12, rl.Color{0, 0, 0, 160})
		rl.DrawText(symbol, c.int(tx), c.int(ty), 12, accent)
	}
}

draw_orbital_defense_inspector_section :: proc(x: f32, btn: rl.Rectangle, p: int) {
	if orbital_defense_building[p] {
		progress := orbital_defense_progress[p] / ORBITAL_DEFENSE_BUILD_TIME
		draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
		fill_rect := rl.Rectangle{btn.x, btn.y, btn.width * progress, btn.height}
		rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 120})
		draw_corner_brackets(btn, 2, 6, SCIFI_CYAN)
		if orbital_defense_constructing_miners(p) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
			rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", orbital_defense_constructing_miners(p), ORBITAL_DEFENSE_CONSTRUCT_MINERS), i32(btn.x + CARD_INSET), i32(btn.y + 12), 11, rl.WHITE)
		} else {
			remaining := ORBITAL_DEFENSE_BUILD_TIME - orbital_defense_progress[p]
			rl.DrawText(rl.TextFormat("BUILDING DEFENSE  %3.1fs", remaining), i32(btn.x + CARD_INSET), i32(btn.y + 11), 12, rl.WHITE)
		}
	} else if orbital_defense_level[p] == 0 {
		can_build := can_build_orbital_defense(p)
		draw_button(btn, rl.TextFormat("[O] BUILD ORBITAL DEFENSE (%d)", ORBITAL_DEFENSE_COST), SCIFI_PANEL_SOLID, can_build)
	} else {
		can_ammo := can_build_orbital_ammo(p)
		ammo_btn := orbital_ammo_button_rect(x, p)
		draw_button(ammo_btn, "[O] +1 Ammo (200)", SCIFI_PANEL_SOLID, can_ammo)
		for slot in 0..<ORBITAL_DEFENSE_AMMO_MAX {
			completed := slot < orbital_defense_ammo[p]
			queued := slot >= orbital_defense_ammo[p] && slot < orbital_defense_ammo[p] + orbital_defense_ammo_pending_count[p]
			active := orbital_defense_ammo_building[p] && slot == orbital_defense_ammo[p]
			progress: f32 = -1
			if active {
				progress = orbital_defense_ammo_progress[p] / ORBITAL_DEFENSE_AMMO_BUILD_TIME
			} else if queued {
				progress = 0
			}
			draw_orbital_ammo_slot(orbital_ammo_slot_rect(x, p, slot), completed, progress)
		}
	}
}

update_orbital_defenses :: proc(dt: f32) {
	update_orbital_defense_blasts(dt)
	for p in 0..<SECTOR_COUNT {
		if orbital_defense_level[p] > 0 {
			advance_orbital_defense_aim(p, dt)
		}
		if orbital_defense_fire_timer[p] > 0 {
			orbital_defense_fire_timer[p] = max(orbital_defense_fire_timer[p] - dt, 0)
		}
		if orbital_defense_reset_timer[p] > 0 {
			orbital_defense_reset_timer[p] = max(orbital_defense_reset_timer[p] - dt, 0)
			if orbital_defense_reset_timer[p] == 0 {
				orbital_defense_wave_kills[p] = 0
			}
		}

		is_building := (p < PLANET_COUNT) && orbital_defense_building[p]
		inbound_count := transit_fighters_at(p, p < PLANET_COUNT)
		if inbound_count == 0 {
			if orbital_defense_ammo_pending_kills[p] > 0 && orbital_defense_ammo[p] > 0 {
				orbital_defense_ammo[p] -= 1
			}
			orbital_defense_ammo_pending_kills[p] = 0
			orbital_defense_wave_kills[p] = 0
			orbital_defense_reset_timer[p] = 0
		} else if p == ENEMY_HOME {
			if orbital_defense_level[p] > 0 {
				max_kills := orbital_defense_level[p] * ORBITAL_DEFENSE_KILLS_PER_LEVEL
				if orbital_defense_wave_kills[p] < max_kills {
					target_pos := sector_pos(p)
					r := sector_radius(p)
					engage_dist := r + 3.8
					arrival_dist := r + 1.65

					for i := unit_count - 1; i >= 0; i -= 1 {
						u := &units[i]
						if u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
						d := distance(u.position, target_pos)
						if d <= engage_dist {
							if orbital_defense_fire_timer[p] <= 0 || d <= arrival_dist {
								orbital_defense_wave_kills[p] += 1
								orbital_defense_reset_timer[p] = ORBITAL_DEFENSE_WAVE_RESET_DELAY
								orbital_defense_fire_timer[p] = 0.06
								muzzle_pos := orbital_defense_muzzle_pos_toward(p, u.position)
								spawn_orbital_defense_blast(p, muzzle_pos, u.position, 0.35)
								remove_unit_at(i)
								if orbital_defense_wave_kills[p] >= max_kills { break }
							}
						}
					}
				}
			}
		} else if orbital_defense_level[p] > 0 && !is_building {
			// Ammo batteries: each shot consumes 1 ammo and kills up to
			// KILLS_PER_SHOT inbound fighters. Empty batteries hold fire.
			// Fire every shot needed in one update so inbound fighters never
			// reach the planet while ammo is still available.
			target_pos := sector_pos(p)
			r := sector_radius(p)
			engage_dist := r + 3.8
			for orbital_defense_ammo[p] > 0 {
				kills := 0
				shot_fired := false
				for i := unit_count - 1; i >= 0; i -= 1 {
					u := &units[i]
					if !u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
					d := distance(u.position, target_pos)
					if d <= engage_dist {
						muzzle_pos := orbital_defense_muzzle_pos_toward(p, u.position)
						spawn_orbital_defense_blast(p, muzzle_pos, u.position, 0.35)
						remove_unit_at(i)
						kills += 1
						orbital_defense_wave_kills[p] += 1
						orbital_defense_ammo_pending_kills[p] += 1
						shot_fired = true
						if kills >= ORBITAL_DEFENSE_KILLS_PER_SHOT { break }
					}
				}
				if !shot_fired { break }
				if orbital_defense_ammo_pending_kills[p] >= ORBITAL_DEFENSE_KILLS_PER_SHOT {
					orbital_defense_ammo[p] -= 1
					orbital_defense_ammo_pending_kills[p] -= ORBITAL_DEFENSE_KILLS_PER_SHOT
				}
				orbital_defense_reset_timer[p] = ORBITAL_DEFENSE_WAVE_RESET_DELAY
			}
			// Charge any partial final shot once the inbound wave clears.
		}
	}
}

unit_cost :: proc(kind: Unit_Type) -> int {
	if kind == .COMBAT { return COMBAT_COST }
	return MINER_COST
}

// Effective drone build time at the current upgrade level: every level
// multiplies the base time by DRONE_SPEED_UPGRADE_FACTOR.
drone_build_time :: proc(kind: Unit_Type) -> f32 {
	base: f32 = MINER_BUILD_TIME
	if kind == .COMBAT { base = COMBAT_BUILD_TIME }
	return base * math.pow(DRONE_SPEED_UPGRADE_FACTOR, f32(drone_speed_level))
}

// Buy the next drone build-speed level: 5000 minerals, capped at
// DRONE_SPEED_UPGRADE_MAX. Purchases live in the Earth inspector.
drone_speed_maxed :: proc() -> bool {
	return drone_speed_level >= DRONE_SPEED_UPGRADE_MAX
}

purchase_drone_speed_upgrade :: proc() -> bool {
	if selected_planet != EARTH { return false }
	if drone_speed_maxed() || minerals < DRONE_SPEED_UPGRADE_COST { return false }
	minerals -= DRONE_SPEED_UPGRADE_COST
	drone_speed_level += 1
	return true
}

queue_unit_on_earth :: proc(kind: Unit_Type) -> bool {
	cost := unit_cost(kind)
	if minerals < cost || queued_count(EARTH) >= base_counts[EARTH] * 5 { return false }
	minerals -= cost
	for i := 0; i < base_counts[EARTH]; i += 1 {
		if !production[EARTH][i].active {
			production[EARTH][i] = Production{kind = kind, active = true, progress = 0}
			return true
		}
	}
	pending[EARTH][pending_count[EARTH]] = kind
	pending_count[EARTH] += 1
	return true
}

queue_unit :: proc(kind: Unit_Type) {
	if selected_planet != EARTH { return } // All production happens at Earth command bases.
	queue_unit_on_earth(kind)
}

// Directly queue up to 5 units on Earth (used by autobuilder regardless of selected planet)
queue_5_units_on_earth :: proc(kind: Unit_Type) {
	for _ in 0..<BATCH_BUILD_COUNT {
		if !queue_unit_on_earth(kind) { break }
	}
}

can_use_autobuilder :: proc() -> bool {
	return base_counts[EARTH] >= MAX_BASES
}

toggle_autobuild_mode :: proc() {
	if !can_use_autobuilder() { return }
	if auto_build_mode != .OFF {
		auto_build_last_mode = auto_build_mode
		auto_build_mode = .OFF
	} else {
		target := auto_build_last_mode
		if target == .OFF { target = .MINERS }
		auto_build_mode = target
	}
	autobuild_retry_timer = 0
}

set_autobuild_mode :: proc(mode: Auto_Build_Mode) {
	if !can_use_autobuilder() && mode != .OFF { return }
	auto_build_mode = mode
	if mode != .OFF {
		auto_build_last_mode = mode
	}
	autobuild_retry_timer = 0
}

autobuild_radio_rects :: proc(panel_x: f32) -> (off_rect, miner_rect, combat_rect: rl.Rectangle) {
	btn_h: f32 = 20.0
	y := f32(earth_queue_y() - 2)
	right := panel_x + PANEL_PAD_X + PANEL_CONTENT_W
	w_off: f32 = 36.0
	w_m: f32 = 26.0
	w_c: f32 = 26.0
	total_w := w_off + w_m + w_c
	x0 := right - total_w

	off_rect = rl.Rectangle{x0, y, w_off, btn_h}
	miner_rect = rl.Rectangle{x0 + w_off, y, w_m, btn_h}
	combat_rect = rl.Rectangle{x0 + w_off + w_m, y, w_c, btn_h}
	return
}

autobuild_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	off_r, _, combat_r := autobuild_radio_rects(panel_x)
	return rl.Rectangle{off_r.x, off_r.y, (combat_r.x + combat_r.width) - off_r.x, off_r.height}
}

update_autobuilder :: proc(dt: f32) {
	if !can_use_autobuilder() || auto_build_mode == .OFF {
		autobuild_retry_timer = 0
		return
	}

	// Autobuilder only triggers when the queue buffer is completely empty
	if queued_count(EARTH) > 0 {
		autobuild_retry_timer = 0
		return
	}

	cost := auto_build_mode == .MINERS ? BATCH_MINER_COST : BATCH_COMBAT_COST

	if autobuild_retry_timer > 0 {
		autobuild_retry_timer -= dt
		if autobuild_retry_timer > 0 {
			return
		}
	}

	// Queue buffer is completely empty: check resources
	if minerals >= cost {
		unit_type := auto_build_mode == .MINERS ? Unit_Type.MINING : Unit_Type.COMBAT
		auto_build_last_mode = auto_build_mode
		queue_5_units_on_earth(unit_type)
		autobuild_retry_timer = 0
	} else {
		// Not enough resources: retry every second until there are enough resources
		autobuild_retry_timer = 1.0
	}
}

// Batch queue up to `count` units as long as minerals and queue space allow.
queue_units :: proc(kind: Unit_Type, count: int) {
	for _ in 0..<count {
		if minerals < unit_cost(kind) || queued_count(selected_planet) >= base_counts[selected_planet] * 5 {
			break
		}
		queue_unit(kind)
	}
}

can_build_5_miners :: proc() -> bool {
	return selected_planet == EARTH && base_counts[EARTH] >= MAX_BASES && minerals >= BATCH_MINER_COST && queued_count(EARTH) < base_counts[EARTH] * 5
}

can_build_5_combat :: proc() -> bool {
	return selected_planet == EARTH && base_counts[EARTH] >= MAX_BASES && minerals >= BATCH_COMBAT_COST && queued_count(EARTH) < base_counts[EARTH] * 5
}

queue_5_miners :: proc() {
	if !can_build_5_miners() { return }
	queue_units(.MINING, BATCH_BUILD_COUNT)
}

queue_5_combat :: proc() {
	if !can_build_5_combat() { return }
	queue_units(.COMBAT, BATCH_BUILD_COUNT)
}

// Screen rect of the drone build-speed upgrade button. Shared by the
// render and the click hitbox so they cannot drift apart. Sits below the
// +1 buttons when under 5 bases, or below the +5 buttons when 5 bases are built.
// Hidden once maxed: callers must check drone_speed_maxed() first, and the
// queue/roster layout below collapses up by UPGRADE_DY so no gap remains.
drone_speed_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	dy := UPGRADE_DY
	if base_counts[EARTH] >= MAX_BASES {
		dy += UPGRADE_DY
	}
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + dy), PANEL_CONTENT_W, UPGRADE_H}
}

// Screen rects for the +5 batch build buttons that unlock at 5 command bases on Earth.
// Positioned below the +1 buttons and above the build-speed upgrade button.
queue_5_miner_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

queue_5_combat_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

// Screen rect for the Controls button docked at the bottom of the screen.
controls_button_rect :: proc() -> rl.Rectangle {
	dock_y := f32(rl.GetScreenHeight() - BOTTOM_DOCK_H - 12)
	return rl.Rectangle{HUD_PAD, dock_y, 110, BOTTOM_DOCK_H}
}

earth_queue_y :: proc() -> int {
	dy := QUEUE_DY
	if base_counts[EARTH] >= MAX_BASES {
		dy += UPGRADE_DY
	}
	if drone_speed_maxed() {
		dy -= UPGRADE_DY
	}
	return production_orders_y() + dy
}

// Screen rect of build-queue slot `slot` (0 = queue head: active production
// lines in base order, then pending items). Shared by the queue rendering and
// the cancel-click hitboxes so they cannot drift apart.
queue_slot_rect :: proc(panel_x: f32, slot: int) -> rl.Rectangle {
	queue_y := f32(earth_queue_y())
	rows := base_counts[EARTH]
	if rows < 1 { rows = 1 }
	row := slot % rows
	column := slot / rows
	return rl.Rectangle{panel_x + PANEL_PAD_X + f32(column * (QUEUE_SLOT_W + QUEUE_SLOT_GAP)), queue_y + QUEUE_LABEL_GAP + f32(row * GRID_PITCH), QUEUE_SLOT_W, QUEUE_SLOT_H}
}

// Cancel the unit at queue position `index` (same ordering as
// queue_kind_at) with a full mineral refund. Cancelling an active production
// line promotes the first pending item into the freed line.
cancel_queued_at :: proc(planet, index: int) -> bool {
	b := 0
	found := -1
	i := index
	for b < base_counts[planet] {
		if !production[planet][b].active { b += 1; continue }
		if i == 0 { found = b; break }
		i -= 1
		b += 1
	}
	if found >= 0 {
		line := &production[planet][found]
		minerals += unit_cost(line.kind)
		line.active = false
		line.progress = 0
		if pending_count[planet] > 0 {
			line.kind = pending[planet][0]
			line.active = true
			for q := 1; q < pending_count[planet]; q += 1 { pending[planet][q-1] = pending[planet][q] }
			pending_count[planet] -= 1
		}
		return true
	}
	if i < pending_count[planet] {
		minerals += unit_cost(pending[planet][i])
		for q := i; q < pending_count[planet] - 1; q += 1 { pending[planet][q] = pending[planet][q+1] }
		pending_count[planet] -= 1
		return true
	}
	return false
}

// ESC handler: cancels the most recently queued unit - the tail of pending,
// else the newest active production line - with a full refund.
cancel_last_queued :: proc() -> bool {
	if queued_count(EARTH) == 0 { return false }
	return cancel_queued_at(EARTH, queued_count(EARTH) - 1)
}

update_production :: proc(dt: f32) {
	if base_build_planet >= 0 {
		// The build clock only runs with a full crew; deposits auto-fill it.
		if base_constructing_miners(base_build_planet) >= BASE_CONSTRUCT_MINERS {
			base_build_progress += dt
		}
		if base_build_progress >= BASE_CONSTRUCT_TIME {
			p := base_build_planet
			base_counts[p] += 1
			base_build_planet = -1
			base_build_progress = 0
			resume_constructing_miners(p, .BASE)
			// The new base's production line picks up waiting queue items at
			// once, without a new unit being queued.
			fill_production_lines(p)
		}
	}
	for p in 0..<PLANET_COUNT {
		if refinery_building[p] {
			if refinery_constructing_miners(p) >= REFINERY_CONSTRUCT_MINERS {
				refinery_progress[p] += dt
			}
			if refinery_progress[p] >= REFINERY_BUILD_TIME {
				refinery_progress[p] = 0
				refinery_building[p] = false
				refinery_built[p] = true
				resume_constructing_miners(p, .REFINERY)
			}
		}
	}
	for p in 0..<PLANET_COUNT {
		if orbital_defense_building[p] {
			if orbital_defense_constructing_miners(p) >= ORBITAL_DEFENSE_CONSTRUCT_MINERS {
				orbital_defense_progress[p] += dt
			}
			if orbital_defense_progress[p] >= ORBITAL_DEFENSE_BUILD_TIME {
				orbital_defense_progress[p] = 0
				orbital_defense_building[p] = false
				orbital_defense_level[p] = 1
				orbital_defense_hp[p] = orbital_defense_max_hp(p)
				orbital_defense_elevation[p] = ORBITAL_DEFENSE_IDLE_ELEV
				orbital_defense_ammo[p] = ORBITAL_DEFENSE_START_AMMO
				resume_constructing_miners(p, .ORBITAL_DEFENSE)
			}
		}
		if orbital_defense_ammo_building[p] {
			if orbital_ammo_constructing_miners(p) >= ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS {
				orbital_defense_ammo_progress[p] += dt
			}
			if orbital_defense_ammo_progress[p] >= ORBITAL_DEFENSE_AMMO_BUILD_TIME {
				orbital_defense_ammo_progress[p] = 0
				orbital_defense_ammo_building[p] = false
				orbital_defense_ammo[p] = min(orbital_defense_ammo[p] + 1, ORBITAL_DEFENSE_AMMO_MAX)
				// Remove one queued slot.
				if orbital_defense_ammo_pending_count[p] > 0 {
					orbital_defense_ammo_pending_count[p] -= 1
				}
				resume_constructing_miners(p, .ORBITAL_DEFENSE_AMMO)
				// Start next queued build if any and capacity remains.
				if orbital_defense_ammo_pending_count[p] > 0 && orbital_defense_ammo[p] < ORBITAL_DEFENSE_AMMO_MAX {
					orbital_defense_ammo_building[p] = true
					orbital_defense_ammo_progress[p] = 0
					recruit_build_crew(p, .ORBITAL_DEFENSE_AMMO, ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS)
				}
			}
		}
	}
	for p := 0; p < PLANET_COUNT; p += 1 {
		for b := 0; b < base_counts[p]; b += 1 {
			line := &production[p][b]
			if !line.active { continue }
			build_time := drone_build_time(line.kind)
			line.progress += dt
			if line.progress >= build_time {
				spawn_unit(line.kind, p)
				line.progress = 0
				if pending_count[p] > 0 {
					line.kind = pending[p][0]
					for q := 1; q < pending_count[p]; q += 1 { pending[p][q-1] = pending[p][q] }
					pending_count[p] -= 1
				} else { line.active = false }
			}
		}
	}
	update_autobuilder(dt)
}

// Move pending queue items into idle production lines: a line freed by a
// newly completed base starts building immediately instead of waiting for
// the next queue_unit call.
fill_production_lines :: proc(p: int) {
	for b := 0; b < base_counts[p]; b += 1 {
		if pending_count[p] == 0 { return }
		line := &production[p][b]
		if line.active { continue }
		line.kind = pending[p][0]
		line.active = true
		line.progress = 0
		for q := 1; q < pending_count[p]; q += 1 { pending[p][q-1] = pending[p][q] }
		pending_count[p] -= 1
	}
}

spawn_unit :: proc(kind: Unit_Type, planet: int) {
	if unit_count >= MAX_UNITS { return }
	angle := f32(unit_count) * 1.8
	pos := planets[planet].position
	if kind == .COMBAT {
		pos.x += math.cos(angle) * (planets[planet].radius + 1.2)
		pos.y += 0.5
		pos.z += math.sin(angle) * (planets[planet].radius + 1.2)
	}
	state := Unit_State.TRANSIT
	target_planet := planet
	if kind == .COMBAT { state = .GUARDING }
	if kind == .MINING { state = .MINING }
	// Earth's rally point: newly produced units auto-dispatch to the rally world.
	if planet == EARTH && earth_rally != NO_RALLY {
		target_planet = earth_rally
		state = .TRANSIT
	}
	build_target := Build_Target.NONE
	mining_active := false
	if kind == .MINING {
		if state != .TRANSIT {
			target_project := planet_next_needed_build_target(target_planet)
			if target_project != .NONE {
				state = .CONSTRUCTING
				build_target = target_project
			} else if planet_can_mine(target_planet) && active_mining_drones_count(target_planet) < planet_mining_cap(target_planet) {
				state = .MINING
				mining_active = true
			} else {
				state = .IDLE
			}
		}
	}
	affiliation := planet
	if kind == .MINING || target_planet != planet { affiliation = target_planet }
	units[unit_count] = Unit{kind = kind, state = state, position = pos, home_planet = planet, affiliation = affiliation, target_planet = target_planet, orbit_angle = angle, build_target = build_target, mining_active = mining_active}
	unit_count += 1
	planet_unit_cache_dirty = true
}

// Enemy waves: every 3 minutes (first at the 3-minute mark) a single wave
// lifts off from the enemy HQ (the old Neptune orbit) - but only while the
// player has liberated WAVE_MIN_LIBERATED_PLANETS (2) or more worlds. The wave
// is never random: it strikes the liberated planet closest to the enemy HQ
// with (liberated planets - 1) * WAVE_FIGHTERS_PER_LIBERATED fighters (3
// liberated worlds send 30). While the player presses an assault on a
// weakened HQ, the wave instead musters there as guarding defenders;
// planet attacks resume once the garrison is replenished.
// Combat pacing is planet-general: while both sides have guarding fighters at a
// planet, one drone on each side is destroyed every COMBAT_TICK seconds. With
// no player defenders left, enemies destroy one mining drone every COMBAT_TICK.
// Player fleets sweeping an occupied planet kill its garrison miners first,
// then damage the enemy base by one per player fighter per tick until it falls.
// Distinct planets currently being mined by the player: a planet counts only
// while at least one non-enemy mining drone is actively MINING it (state
// .MINING). Dispatched scouts or drones pinned in orbit don't count - invasion
// waves answer production, not travel.
mined_planets :: proc(seen: ^[PLANET_COUNT]bool) -> int {
	for p in 0..<PLANET_COUNT { seen[p] = false }
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state != .MINING { continue }
		seen[u.target_planet] = true
	}
	count := 0
	for p in 0..<PLANET_COUNT { if seen[p] { count += 1 } }
	return count
}

mined_planet_count :: proc() -> int {
	seen := [PLANET_COUNT]bool{}
	return mined_planets(&seen)
}

update_combat_vision :: proc(dt: f32) {
	for p in 0..<SECTOR_COUNT {
		if combat_vision_timer[p] > 0 {
			combat_vision_timer[p] = max(combat_vision_timer[p] - dt, 0)
		}
	}
}

update_enemy_waves :: proc(dt: f32) {
	update_combat_vision(dt)
	update_orbital_defenses(dt)
	update_minor_wave(dt)
	update_wave(dt)
	for p in 0..<SECTOR_COUNT { update_planet_combat(dt, p) }
}

// Minor wave: every 75 seconds, concurrent minor waves launch against liberated planets.
// Every liberated planet is attacked from the closest not liberated planet.
// Each not liberated planet only attacks one liberated planet, its closest.
// These attacks run independently of the 180s wave.
update_minor_wave :: proc(dt: f32) {
	minor_wave_timer += dt
	if minor_wave_timer >= MINOR_WAVE_INTERVAL {
		launch_minor_wave()
	}
}

// Computes the minor wave attack pairs for all liberated planets.
// Pairs unliberated planets with liberated planets greedily by distance:
// each liberated planet is attacked from the closest available unliberated planet,
// and each unliberated planet attacks at most one liberated planet (its closest
// available liberated planet).
collect_minor_wave_attacks :: proc() -> (sources: [PLANET_COUNT]int, targets: [PLANET_COUNT]int, count: int) {
	Pair :: struct {
		u: int,
		l: int,
		d: f32,
	}

	pairs: [PLANET_COUNT * PLANET_COUNT]Pair
	pair_count := 0

	for u in 0..<PLANET_COUNT {
		if planet_liberated(u) { continue }
		for l in 0..<PLANET_COUNT {
			if !planet_liberated(l) { continue }
			d := distance(planets[u].position, planets[l].position)
			pairs[pair_count] = Pair{u = u, l = l, d = d}
			pair_count += 1
		}
	}

	// Sort pairs ascending by distance (insertion sort on at most 16 pairs)
	for i in 1..<pair_count {
		key := pairs[i]
		j := i - 1
		for j >= 0 && pairs[j].d > key.d {
			pairs[j + 1] = pairs[j]
			j -= 1
		}
		pairs[j + 1] = key
	}

	used_u: [PLANET_COUNT]bool
	used_l: [PLANET_COUNT]bool

	for i in 0..<pair_count {
		p := pairs[i]
		if !used_u[p.u] && !used_l[p.l] {
			used_u[p.u] = true
			used_l[p.l] = true
			sources[count] = p.u
			targets[count] = p.l
			count += 1
		}
	}

	return
}

launch_minor_wave :: proc() {
	minor_wave_timer = 0
	sources, targets, count := collect_minor_wave_attacks()
	for i in 0..<count {
		spawn_minor_wave(sources[i], targets[i], MINOR_WAVE_SIZE)
	}
}

// Warning before minor wave: 3 seconds before launch, targeted planets
// receive an ominous red glow at half battle intensity.
planet_is_minor_wave_target :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	_, targets, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if targets[i] == p { return true }
	}
	return false
}

// Warning before minor wave: 3 seconds before launch, attacking source planets
// receive an ominous yellow aura at half battle intensity.
planet_is_minor_wave_source :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	sources, _, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if sources[i] == p { return true }
	}
	return false
}

minor_wave_warning_planet :: proc() -> int {
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return -1 }
	sources, targets, count := collect_minor_wave_attacks()
	if count == 0 { return -1 }
	for i in 0..<count {
		if targets[i] == EARTH { return EARTH }
	}
	return targets[0]
}

minor_wave_warning_source_planet :: proc() -> int {
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return -1 }
	sources, targets, count := collect_minor_wave_attacks()
	if count == 0 { return -1 }
	for i in 0..<count {
		if targets[i] == EARTH { return sources[i] }
	}
	return sources[0]
}

minor_wave_source_warning_planet :: proc() -> int {
	return minor_wave_warning_source_planet()
}

// A planet is the source of an impending minor wave within 3s of launching.
planet_attack_source_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	return planet_is_minor_wave_source(p)
}

// A planet is under attack warning if an impending minor wave is within 3s
// of launching against it, or if enemy combat drones are currently in transit
// toward it. The warning red glow persists during transit and transitions to
// full battle glow once combat begins.
planet_under_attack_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if planet_is_minor_wave_target(p) { return true }
	return transit_fighters_at(p, true) > 0
}

closest_unliberated_planet_to_earth :: proc() -> (int, bool) {
	best := -1
	best_d: f32 = 1e9
	earth_pos := planets[EARTH].position
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		if planet_liberated(p) { continue }
		d := distance(planets[p].position, earth_pos)
		if best < 0 || d < best_d {
			best = p
			best_d = d
		}
	}
	return best, best >= 0
}

closest_liberated_planet_to :: proc(attacker: int) -> int {
	attacker_pos := planets[attacker].position
	best_other := -1
	best_other_d: f32 = 1e9

	for p in 0..<PLANET_COUNT {
		if p == EARTH || p == attacker { continue }
		if !planet_liberated(p) { continue }
		d := distance(planets[p].position, attacker_pos)
		if best_other < 0 || d < best_other_d {
			best_other = p
			best_other_d = d
		}
	}

	earth_d := distance(planets[EARTH].position, attacker_pos)
	if best_other >= 0 && best_other_d <= earth_d {
		return best_other
	}
	return EARTH
}

spawn_minor_wave :: proc(source, target: int, count: int = MINOR_WAVE_SIZE) {
	spawn_count := min(count, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	src_pos := planets[source].position
	src_rad := planets[source].radius
	target_pos := sector_pos(target)

	to_target := target_pos - src_pos
	dist := rl.Vector3Length(to_target)
	dir := dist > 0.001 ? to_target / dist : rl.Vector3{1, 0, 0}

	world_up := rl.Vector3{0, 1, 0}
	right := rl.Vector3CrossProduct(dir, world_up)
	if rl.Vector3Length(right) < 0.01 {
		right = rl.Vector3CrossProduct(dir, {0, 0, 1})
	}
	right = rl.Vector3Normalize(right)
	up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, dir))

	launch_dist := dist - (src_rad + 1.5)
	launch_origin := src_pos + dir * (src_rad + 1.5)

	formation_offsets := [5][2]f32{
		{ 0.0,  0.0},
		{-1.3,  0.4},
		{ 1.3,  0.4},
		{-2.6, -0.3},
		{ 2.6, -0.3},
	}

	for i in 0..<spawn_count {
		angle := f32(i) * (2 * math.PI / f32(spawn_count))
		ox := formation_offsets[i % 5][0]
		oy := formation_offsets[i % 5][1]
		if i >= 5 {
			ox += f32((i / 5) * 2) * (i % 2 == 0 ? 1.0 : -1.0)
		}
		raw_pos := launch_origin + right * ox + up * oy
		pos := target_pos - rl.Vector3Normalize(target_pos - raw_pos) * launch_dist
		units[unit_count] = Unit{
			kind = .COMBAT,
			state = .TRANSIT,
			position = pos,
			home_planet = source,
			affiliation = target,
			target_planet = target,
			enemy = true,
			orbit_angle = angle,
		}
		unit_count += 1
	}
}

// Wave: every 180 seconds, advancing while 2+ worlds are liberated.
update_wave :: proc(dt: f32) {
	if liberated_planet_count() >= WAVE_MIN_LIBERATED_PLANETS {
		enemy_wave_timer += dt
		interval := f32(WAVE_FIRST_DELAY)
		if wave_started { interval = f32(WAVE_INTERVAL) }
		if enemy_wave_timer >= interval {
			launch_wave()
		}
	}
}

// One attack cycle: a single wave of attack_wave_size() fighters. While the
// player presses an assault on a weakened HQ the wave musters there as
// guarding defenders instead; otherwise it sorties against the liberated
// planet closest to the enemy HQ. A destroyed HQ launches nothing, ever.
launch_wave :: proc() {
	size := attack_wave_size()
	enemy_wave_timer = 0
	wave_started = true
	if size <= 0 || enemy_hq_destroyed() { return }
	_, defenders := planet_combatants(ENEMY_HOME)
	if player_attacking_hq() && defenders < ENEMY_HQ_GARRISON {
		spawn_hq_defenders(size)
		return
	}
	spawn_n_enemies_to(closest_liberated_planet_to_hq(), size)
}

launch_attack_wave :: proc() {
	launch_wave()
}

// Combat tick for a sector: HQ battles resolve 5x faster than planet battles.
combat_tick_for :: proc(p: int) -> f32 {
	if p == ENEMY_HOME {
		return HQ_COMBAT_TICK
	}
	return COMBAT_TICK
}
combat_tick :: combat_tick_for
planet_combat_tick :: combat_tick_for

update_planet_combat :: proc(dt: f32, p: int) {
	tick := combat_tick_for(p)
	players, enemies := planet_combatants(p)
	if players > 0 && enemies > 0 {
		combat_timer[p] += dt
		for combat_timer[p] >= tick {
			combat_timer[p] -= tick
			if !kill_fighter(p, false) { break }
			rem_players, _ := planet_combatants(p)
			if rem_players == 0 {
				combat_vision_timer[p] = COMBAT_VISION_LINGER
			}
			if !kill_fighter(p, true) { break }
		}
	} else if enemies > 0 {
		combat_timer[p] = 0
		if p < PLANET_COUNT && orbital_defense_level[p] > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				orbital_defense_hp[p] -= enemies
				if orbital_defense_hp[p] <= 0 {
					destroy_orbital_defense(p)
					break
				}
			}
		} else {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				if !kill_player_miner(p) { break }
			}
			if p < PLANET_COUNT && p != EARTH && !player_miners_at(p) {
				refinery_built[p] = false
				refinery_building[p] = false
				refinery_progress[p] = 0
			}
			// Earth siege: once no defenders or miners are left, the occupying
			// fighters tear down the command bases, one per BASE_SIEGE_TIME.
			if p == EARTH && !player_miners_at(p) {
				base_timer[p] += dt
				for base_timer[p] >= BASE_SIEGE_TIME {
					base_timer[p] -= BASE_SIEGE_TIME
					destroy_player_base(p)
					if base_counts[p] == 0 { break }
				}
			} else {
				base_timer[p] = 0
			}
		}
	} else if players > 0 {
		combat_timer[p] = 0
		// Occupation cleanup: with the garrison fighters gone, player fighters
		// sweep the enemy mining drones, then bring down the enemy base.
		if enemy_miner_count(p) > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				if !kill_enemy_miner(p) { break }
			}
		} else if p == ENEMY_HOME && orbital_defense_level[p] > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				orbital_defense_hp[p] -= players
				if orbital_defense_hp[p] <= 0 {
					destroy_orbital_defense(p)
					break
				}
			}
		} else if enemy_base_hp[p] > 0 {
			base_timer[p] += dt
			for base_timer[p] >= tick {
				base_timer[p] -= tick
				enemy_base_hp[p] = max(enemy_base_hp[p] - players, 0)
				if enemy_base_hp[p] == 0 { break }
			}
		} else {
			miner_timer[p] = 0
			base_timer[p] = 0
		}
	} else {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
	}
}

// Attack wave size: (liberated planets - 1) * WAVE_FIGHTERS_PER_LIBERATED
// fighters (3 liberated worlds send 30). Earth starts liberated, so the
// result is 0 until a second world falls - the wave musters nothing.
attack_wave_size :: proc() -> int {
	return (liberated_planet_count() - 1) * WAVE_FIGHTERS_PER_LIBERATED
}

// Liberated worlds (planets only - the HQ sector is not a planet).
liberated_planet_count :: proc() -> int {
	count := 0
	for p in 0..<PLANET_COUNT { if planet_liberated(p) { count += 1 } }
	return count
}

// The liberated planet closest to the enemy HQ - the wave's fixed target.
// Earth starts liberated, so there is always at least one candidate.
closest_liberated_planet_to_hq :: proc() -> int {
	best := EARTH
	best_d := distance(planets[EARTH].position, ENEMY_HQ_POSITION)
	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) { continue }
		d := distance(planets[p].position, ENEMY_HQ_POSITION)
		if d < best_d { best_d = d; best = p }
	}
	return best
}

// True while player fighters press the HQ: stationed there (affiliation) or
// already inbound (transit with the HQ as target).
player_attacking_hq :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.enemy { continue }
		if u.affiliation == ENEMY_HOME { return true }
		if u.state == .TRANSIT && u.target_planet == ENEMY_HOME { return true }
	}
	return false
}

// Muster `count` fighters as guarding defenders of the HQ (capped by free
// unit slots), placed on the guard orbit like the opening garrison.
spawn_hq_defenders :: proc(count: int) {
	if enemy_hq_destroyed() { return }
	spawn_count := min(count, MAX_UNITS - unit_count)
	for i in 0..<spawn_count {
		angle := f32(unit_count + i) * 1.26
		units[unit_count] = Unit{
			kind = .COMBAT, state = .GUARDING, position = orbit_pos(ENEMY_HQ_POSITION, ENEMY_HQ_RADIUS, angle),
			home_planet = NEPTUNE, affiliation = ENEMY_HOME, target_planet = ENEMY_HOME,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

// Debug: force the next attack wave immediately (verify combat without
// waiting 3 minutes).
spawn_enemy_wave :: proc() { launch_attack_wave() }

// Spawns `count` enemy fighters (capped by free unit slots) lifting off from
// the enemy HQ toward `target`. A destroyed HQ launches nothing, ever.
spawn_n_enemies_to :: proc(target: int, count: int) {
	if enemy_hq_destroyed() { return }
	spawn_count := min(count, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	// Every wave lifts off from the enemy HQ (the old Neptune orbit) - no
	// longer from Jupiter space.
	for i in 0..<spawn_count {
		angle := f32(i) * 1.26
		pos := ENEMY_HQ_POSITION + rl.Vector3{math.cos(angle) * 1.5, 0.5, math.sin(angle) * 1.5}
		units[unit_count] = Unit{
			kind = .COMBAT, state = .TRANSIT, position = pos,
			home_planet = NEPTUNE, affiliation = target, target_planet = target,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

// A planet is liberated once its enemy base is destroyed (the combat rules
// only damage the base after every enemy drone there is gone).
planet_liberated :: proc(p: int) -> bool {
	return enemy_base_hp[p] <= 0
}

// Counts of guarding fighters at a planet: player units vs enemy units.
planet_combatants :: proc(p: int) -> (players, enemies: int) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.state != .GUARDING || u.affiliation != p { continue }
		if u.enemy { enemies += 1 } else { players += 1 }
	}
	return
}

kill_fighter :: proc(p: int, enemy_side: bool) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.enemy == enemy_side && u.state == .GUARDING && u.affiliation == p {
			remove_unit_at(i)
			return true
		}
	}
	return false
}

// Garrison defenses only engage miners physically at the planet: transit
// across space is safe. A scout freshly pinned at an occupied planet keeps
// a SCOUT_SURVIVAL grace window (its .IDLE progress) before it becomes a
// target, so the player can peek at the garrison before losing the drone.
kill_player_miner :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		if u.state == .IDLE && !planet_liberated(p) && u.progress < SCOUT_SURVIVAL { continue }
		remove_unit_at(i)
		return true
	}
	return false
}

// Any player mining drone physically at p (transit legs are elsewhere and
// safe). Mirrors kill_player_miner's target set without killing anything.
player_miners_at :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		return true
	}
	return false
}

// Enemy siege tears down one command base: drop its production line (the
// highest-index line), then redistribute pending items across the survivors.
destroy_player_base :: proc(p: int) {
	if base_counts[p] <= 0 { return }
	production[p][base_counts[p] - 1] = Production{}
	base_counts[p] -= 1
	fill_production_lines(p)
}

enemy_miner_count :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].kind == .MINING && units[i].enemy && units[i].affiliation == p { count += 1 }
	}
	return count
}

kill_enemy_miner :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.enemy && u.affiliation == p {
			remove_unit_at(i)
			return true
		}
	}
	return false
}

// Drones actively fighting at sector s (dogfight, miner sweep, or base siege).
sector_in_combat :: proc(s: int) -> bool {
	players := 0
	enemies := 0
	has_player_miners := false
	has_enemy_miners := false
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.state == .GUARDING && u.affiliation == s {
			if u.enemy { enemies += 1 } else { players += 1 }
			if players > 0 && enemies > 0 { return true }
		} else if u.kind == .MINING {
			if u.enemy && u.affiliation == s {
				has_enemy_miners = true
			} else if !u.enemy && u.target_planet == s && u.state != .TRANSIT {
				has_player_miners = true
			}
		}
	}
	if players > 0 && enemies > 0 { return true }
	if enemies > 0 && (has_player_miners || (s == EARTH && base_counts[s] > 0) || (s < PLANET_COUNT && orbital_defense_level[s] > 0)) { return true }
	if players > 0 && (has_enemy_miners || enemy_base_hp[s] > 0 || (s == ENEMY_HOME && orbital_defense_level[s] > 0)) { return true }
	return false
}

// Shift-left removal keeps unit indices stable, so is_effective_miner ranks and
// selection flags stay consistent for the survivors.
remove_unit_at :: proc(index: int) {
	if last_unit_clicked_index == index {
		last_unit_clicked_index = -1
	} else if last_unit_clicked_index > index {
		last_unit_clicked_index -= 1
	}
	for i := index; i < unit_count - 1; i += 1 {
		units[i] = units[i + 1]
		selected_units[i] = selected_units[i + 1]
	}
	unit_count -= 1
	planet_unit_cache_dirty = true
}

// Right-click on a planet is disambiguated by selection: with units selected
// it is a move order (the Earth rally point is left untouched); with nothing
// selected and Earth as the selected planet it (re)sets the Earth rally point
// - right-clicking Earth itself clears the rally back to 0.
handle_planet_right_click :: proc(planet: int) {
	if selection_count() > 0 {
		issue_group_order(planet)
	} else if selected_planet == EARTH {
		set_earth_rally(planet)
	}
}

issue_group_order :: proc(planet: int) {
	for i := 0; i < unit_count; i += 1 {
		if !selected_units[i] { continue }
		// The enemy HQ is a combat target only: mining drones never sortie
		// there (nothing to mine, and the sector is not a planet).
		if units[i].kind == .MINING && planet == ENEMY_HOME { continue }
		units[i].target_planet = planet
		units[i].affiliation = planet
		units[i].progress = 0
		units[i].build_target = .NONE
		units[i].mining_active = false
		if units[i].kind == .MINING {
			units[i].state = .TRANSIT
		} else {
			if distance(units[i].position, sector_pos(planet)) < sector_radius(planet) + 1.5 {
				units[i].state = .GUARDING
			} else {
				units[i].state = .TRANSIT
			}
		}
	}
}

update_units :: proc(dt: f32) {
	update_mining_income(dt)
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT {
			update_combat(u, dt)
		} else {
			update_miner(u, i, dt)
		}
	}
	planet_unit_cache_dirty = true
}

// Minerals delivered per mining cycle at a planet. The inner planets
// (Mercury, Venus, Earth, Mars) pay the standard 10; the gas giants and
// beyond pay 25 - the richer prize for pushing outward. (No Earth penalty.)
mining_rate :: proc(planet: int) -> int {
	if planet >= JUPITER { return 25 }
	return 10
}

// Active mining drone cap per planet (planet size): only this many player
// miners per planet count as effective and earn minerals.
planet_mining_cap :: proc(planet: int) -> int {
	switch planet {
	case MERCURY: return 15
	case VENUS: return 35
	case EARTH: return 10
	case MARS: return 50
	case JUPITER: return 100
	case SATURN: return 90
	case URANUS: return 60
	case NEPTUNE: return 60
	}
	return 10
}

active_mining_drones_count :: proc(planet: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state == .CONSTRUCTING { continue }
		is_match := false
		if planet == EARTH {
			is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
		} else {
			is_match = (u.target_planet == planet)
		}
		if is_match && u.mining_active {
			count += 1
		}
	}
	return count
}

// Per-planet hard cap on earning miners: only active miners within planet_mining_cap(p)
// participate in the mining route. Extra drones idle on the planet.
is_effective_miner :: proc(index: int) -> bool {
	if units[index].kind != .MINING || units[index].enemy { return false }
	p := units[index].target_planet
	if !planet_can_mine(p) { return false }
	rank := 0
	for j := 0; j < index; j += 1 {
		u := &units[j]
		if u.kind == .MINING && !u.enemy && u.target_planet == p && u.state != .CONSTRUCTING && u.state != .IDLE {
			rank += 1
		}
	}
	return rank < planet_mining_cap(p)
}

refresh_planet_unit_cache :: proc() {
	planet_miner_counts = {}
	planet_combat_counts = {}
	planet_mining_miners = {}
	for i in 0..<unit_count {
		u := &units[i]
		if u.enemy { continue }
		if u.kind == .MINING {
			target := u.target_planet
			if target == EARTH || (target < 0 && u.affiliation == EARTH) {
				planet_miner_counts[EARTH] += 1
				if u.state != .CONSTRUCTING {
					planet_mining_miners[EARTH] += 1
				}
			} else if target >= 0 && target < PLANET_COUNT {
				planet_miner_counts[target] += 1
				if u.state != .CONSTRUCTING {
					planet_mining_miners[target] += 1
				}
			}
		} else if u.kind == .COMBAT {
			p := u.affiliation
			if p >= 0 && p < PLANET_COUNT {
				planet_combat_counts[p] += 1
			}
		}
	}
	planet_unit_cache_dirty = false
}

// Player miners assigned/targeting planet p (matches inspector live roster logic)
planet_miner_drone_count :: proc(p: int) -> int {
	if p < 0 || p >= PLANET_COUNT { return 0 }
	if planet_unit_cache_dirty { refresh_planet_unit_cache() }
	return planet_miner_counts[p]
}

// Player combat drones stationed at/assigned to planet p (matches inspector fighting drones count)
planet_combat_drone_count :: proc(p: int) -> int {
	if p < 0 || p >= PLANET_COUNT { return 0 }
	if planet_unit_cache_dirty { refresh_planet_unit_cache() }
	return planet_combat_counts[p]
}

planet_cycle_time :: proc(planet: int) -> f32 {
	round_trip := 2.0 * distance(planets[planet].position, planets[EARTH].position)
	travel_time := round_trip / MINING_TRANSIT_SPEED
	return MINING_DURATION + DEPOSIT_DURATION + travel_time
}

// Minerals per second delivered by a planet's effective mining drones
// (planet_mining_cap already applied; constructing drones contribute nothing). One full
// cycle is: transit out, mine MINING_DURATION, transit back to Earth, deposit
// DEPOSIT_DURATION - the round trip at MINING_TRANSIT_SPEED dominates for
// distant planets, so MPS falls with distance.
planet_mps :: proc(planet: int) -> f32 {
	if !planet_can_mine(planet) { return 0 }
	cap := planet_mining_cap(planet)
	effective := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.target_planet == planet {
			effective += 1
			if effective >= cap { break }
		}
	}
	cycle_time := planet_cycle_time(planet)
	if cycle_time <= 0 { return 0 }
	return f32(effective) * f32(mining_rate(planet)) / cycle_time
}

// Empire-wide income: the sum of every planet's MPS, shown on Earth.
global_mps :: proc() -> f32 {
	counts: [PLANET_COUNT]int
	caps: [PLANET_COUNT]int
	for p in 0..<PLANET_COUNT { caps[p] = planet_mining_cap(p) }
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.target_planet >= 0 && u.target_planet < PLANET_COUNT {
			p := u.target_planet
			if !planet_can_mine(p) { continue }
			if counts[p] < caps[p] { counts[p] += 1 }
		}
	}
	total: f32 = 0
	for p in 0..<PLANET_COUNT {
		if !planet_can_mine(p) { continue }
		total += f32(counts[p]) * f32(mining_rate(p)) / planet_cycle_time(p)
	}
	return total
}

// Streams mining income per second based on empire-wide MPS.
update_mining_income :: proc(dt: f32) {
	mps := global_mps()
	if mps <= 0 { return }
	mineral_accumulator += mps * dt
	payout := int(mineral_accumulator)
	if payout > 0 {
		minerals += payout
		mineral_accumulator -= f32(payout)
	}
}

update_combat :: proc(u: ^Unit, dt: f32) {
	if u.state == .TRANSIT {
		target := sector_pos(u.target_planet)
		travel(u, target, COMBAT_TRANSIT_SPEED * dt)
		if distance(u.position, target) <= sector_radius(u.target_planet) + 1.4 {
			u.state = .GUARDING
			u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
		}
	} else if u.state == .GUARDING {
		u.orbit_angle += dt * 0.9
		u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
	}
}

update_miner :: proc(u: ^Unit, index: int, dt: f32) {
	target := planets[u.target_planet].position
	earth := planets[EARTH].position
	switch u.state {
	case .TRANSIT:
		travel(u, target, MINING_TRANSIT_SPEED * dt)
		if distance(u.position, target) <= planets[u.target_planet].radius + 1.0 {
			u.position = target
			target_project := planet_next_needed_build_target(u.target_planet)
			if !u.enemy && target_project != .NONE {
				u.state = .CONSTRUCTING
				u.build_target = target_project
				u.progress = 0
				u.mining_active = false
			} else if planet_can_mine(u.target_planet) {
				can_mine := false
				if u.mining_active {
					can_mine = active_mining_drones_count(u.target_planet) <= planet_mining_cap(u.target_planet)
				} else {
					can_mine = active_mining_drones_count(u.target_planet) < planet_mining_cap(u.target_planet)
				}
				if can_mine {
					u.state = .MINING
					u.progress = 0
					u.mining_active = true
				} else {
					u.state = .IDLE
					u.progress = 0
					u.mining_active = false
				}
			} else {
				// Occupied or unrefined planet: hold in orbit until combat drones liberate it and refinery is built.
				// progress doubles as the scout survival clock (kill_player_miner).
				u.state = .IDLE
				u.progress = 0
				u.mining_active = false
			}
		}
	case .MINING:
		u.progress += dt
		u.position = target
		if !planet_can_mine(u.target_planet) {
			u.state = .IDLE
			u.mining_active = false
			u.progress = 0
		}
	case .RETURNING:
		travel(u, earth, MINING_TRANSIT_SPEED * dt)
		if distance(u.position, earth) <= planets[EARTH].radius + 1.0 {
			u.position = earth
			u.state = .DEPOSITING
			u.progress = 0
		}
	case .DEPOSITING:
		u.progress += dt
		if u.progress >= DEPOSIT_DURATION {
			if is_effective_miner(index) { minerals += mining_rate(u.target_planet) }
			u.progress = 0
			u.state = .TRANSIT
			// A queued Earth base or orbital defense soaks up returning miners: after the payout
			// they join the build crew instead of transiting back out. Earth-
			// assigned drones join first; a foreign-route miner only joins once
			// no Earth-assigned miner remains available, so its route is starved last.
			target_project := planet_next_needed_build_target(EARTH)
			if target_project != .NONE && !u.enemy {
				if u.target_planet == EARTH || u.affiliation == EARTH || !earth_assigned_miner_available() {
					u.state = .CONSTRUCTING
					u.build_target = target_project
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	case .IDLE:
		// Held at an occupied or unrefined planet: join refinery or orbital defense construction if building and crew needed,
		// or resume mining once it can be mined and under the hard cap.
		// Otherwise the hold time feeds the scout survival clock.
		u.position = target
		target_project := planet_next_needed_build_target(u.target_planet)
		if !u.enemy && target_project != .NONE {
			u.state = .CONSTRUCTING
			u.build_target = target_project
			u.progress = 0
			u.mining_active = false
		} else if planet_can_mine(u.target_planet) && active_mining_drones_count(u.target_planet) < planet_mining_cap(u.target_planet) {
			u.state = .MINING
			u.progress = 0
			u.mining_active = true
		} else {
			u.progress += dt
		}
	case .CONSTRUCTING:
		u.position = target
	case .GUARDING:
		// Idle miners keep their creation planet as their affiliation.
	}
}

travel :: proc(u: ^Unit, target: rl.Vector3, amount: f32) {
	dx := target.x - u.position.x
	dy := target.y - u.position.y
	dz := target.z - u.position.z
	d := math.sqrt(dx*dx + dy*dy + dz*dz)
	if d <= amount || d == 0 { u.position = target; return }
	u.position.x += dx / d * amount
	u.position.y += dy / d * amount
	u.position.z += dz / d * amount
}

// Procedural 3D oriented quad (double-wound so it renders from front and back).
draw_quad_3d :: proc(v1, v2, v3, v4: rl.Vector3, col: rl.Color) {
	rl.DrawTriangle3D(v1, v2, v3, col)
	rl.DrawTriangle3D(v1, v3, v4, col)
	rl.DrawTriangle3D(v3, v2, v1, col)
	rl.DrawTriangle3D(v4, v3, v1, col)
}

// Procedural 3D oriented box aligned to an arbitrary orthonormal basis (fwd, up, right).
draw_oriented_box :: proc(
	center: rl.Vector3,
	half_w, half_h, half_l: f32,
	fwd, up, right: rl.Vector3,
	col: rl.Color,
) {
	p0 := center - right * half_w - up * half_h - fwd * half_l
	p1 := center + right * half_w - up * half_h - fwd * half_l
	p2 := center + right * half_w + up * half_h - fwd * half_l
	p3 := center - right * half_w + up * half_h - fwd * half_l
	p4 := center - right * half_w - up * half_h + fwd * half_l
	p5 := center + right * half_w - up * half_h + fwd * half_l
	p6 := center + right * half_w + up * half_h + fwd * half_l
	p7 := center - right * half_w + up * half_h + fwd * half_l

	// Rear face (-fwd)
	draw_quad_3d(p0, p1, p2, p3, col)
	// Front face (+fwd)
	draw_quad_3d(p4, p5, p6, p7, col)
	// Bottom face (-up)
	draw_quad_3d(p0, p1, p5, p4, col)
	// Top face (+up)
	draw_quad_3d(p3, p2, p6, p7, col)
	// Left face (-right)
	draw_quad_3d(p0, p3, p7, p4, col)
	// Right face (+right)
	draw_quad_3d(p1, p2, p6, p5, col)
}

// Pulsating red emergency hazard lights (ambulance-style alternating dual strobes)
// used for orbital defenses undergoing construction or upgrade refits.
draw_ambulance_hazard_lights :: proc(p_left, p_right: rl.Vector3, s: f32) {
	// Alternating high-cadence strobe pulse (ambulance emergency light bar effect)
	t := laser_anim_time * 12.0
	phase := math.sin(t)
	pulse_l := clamp((phase - 0.1) * 2.2, 0.0, 1.0)
	pulse_r := clamp((-phase - 0.1) * 2.2, 0.0, 1.0)

	// Crossbar bracket connecting the lights
	rl.DrawCylinderEx(p_left, p_right, 0.016 * s, 0.016 * s, 6, rl.Color{45, 48, 55, 255})

	// Left red strobe
	rl.DrawCylinderEx(p_left - {0, 0.05 * s, 0}, p_left, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_l > 0.05 {
		rl.DrawSphere(p_left, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_left, 0.09 * s * pulse_l + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_l)})
		rl.DrawSphereEx(p_left, 0.18 * s * pulse_l + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_l)})
	} else {
		rl.DrawSphere(p_left, 0.032 * s, rl.Color{110, 20, 25, 255})
	}

	// Right red strobe
	rl.DrawCylinderEx(p_right - {0, 0.05 * s, 0}, p_right, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_r > 0.05 {
		rl.DrawSphere(p_right, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_right, 0.09 * s * pulse_r + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_r)})
		rl.DrawSphereEx(p_right, 0.18 * s * pulse_r + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_r)})
	} else {
		rl.DrawSphere(p_right, 0.032 * s, rl.Color{110, 20, 25, 255})
	}
}

// Cyberpunk space version of a sand-colored Flak 88 battery mounted on the
// planet surface at the north pole.
draw_cyberpunk_flak88 :: proc(planet_idx: int) {
	if planet_idx < 0 || planet_idx >= PLANET_COUNT { return }
	planet := planets[planet_idx]
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	lit := has_vision(planet_idx)
	level := orbital_defense_level[planet_idx]
	is_upgrading := orbital_defense_building[planet_idx]

	// Scale subtly with planet radius for consistent planetary presence
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)

	// Azimuth and elevation dynamically track approaching enemies when active,
	// or scan gracefully when idle, or park in maintenance cradle when upgrading.
	azimuth, elev := orbital_defense_aim(planet_idx)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)

	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	right := rl.Vector3{-sin_az, 0, cos_az}

	cos_el := math.cos(elev)
	sin_el := math.sin(elev)

	barrel_dir := fwd * cos_el + up * sin_el
	barrel_normal := -fwd * sin_el + up * cos_el

	// Palette: sand military armor contrasted with gunmetal chassis & cyan energy
	sand_base    := rl.Color{214, 182, 134, 255}
	sand_dark    := rl.Color{160, 132, 92, 255}
	sand_light   := rl.Color{240, 215, 175, 255}
	gunmetal     := rl.Color{36, 40, 46, 255}
	frame_mid    := rl.Color{65, 72, 82, 255}
	steel_bright := rl.Color{155, 165, 180, 255}
	cyan_glow    := SCIFI_CYAN
	mint_core    := SCIFI_MINT
	amber_lens   := SCIFI_AMBER

	if !lit {
		sand_base = rl.Color{105, 100, 92, 255}
		sand_dark = rl.Color{75, 72, 68, 255}
		sand_light = rl.Color{125, 120, 112, 255}
		gunmetal = rl.Color{45, 47, 52, 255}
		frame_mid = rl.Color{55, 58, 64, 255}
		steel_bright = rl.Color{90, 95, 102, 255}
		cyan_glow = rl.Color{0, 120, 130, 200}
		mint_core = rl.Color{70, 130, 120, 200}
		amber_lens = rl.Color{120, 70, 30, 200}
	} else if is_upgrading {
		// Powered-down coils and dark energy conduits while disabled during upgrade
		cyan_glow = rl.Color{55, 50, 45, 255}
		mint_core = rl.Color{80, 70, 60, 255}
	}

	// 1. Kreuzlafette: Central base collar & 4 cruciform outrigger legs on surface
	base_b := pole + up * (0.01 * s)
	base_m := pole + up * (0.12 * s)
	base_t := pole + up * (0.22 * s)
	rl.DrawCylinderEx(base_b, base_m, 0.44 * s, 0.40 * s, 12, gunmetal)
	rl.DrawCylinderEx(base_m, base_t, 0.40 * s, 0.36 * s, 12, sand_dark)

	for d_idx in 0..<4 {
		leg_ang := planet_spin[planet_idx] + f32(d_idx) * (math.PI / 2.0)
		ldir := rl.Vector3{math.cos(leg_ang), 0, math.sin(leg_ang)}
		l_start := pole + up * (0.08 * s) + ldir * (0.30 * s)
		l_end   := pole + up * (0.05 * s) + ldir * (0.80 * s)

		// Tapered girder outrigger
		rl.DrawCylinderEx(l_start, l_end, 0.085 * s, 0.060 * s, 6, sand_base)
		rl.DrawCylinderEx(l_start, l_start + ldir * (0.10 * s), 0.095 * s, 0.090 * s, 6, gunmetal)

		// Conduit line along the top spine of each leg
		c_s := l_start + up * (0.065 * s)
		c_e := l_end + up * (0.045 * s)
		rl.DrawLine3D(c_s, c_e, cyan_glow)

		// Outrigger footpad / leveling jack
		pad_b := pole + up * (0.01 * s) + ldir * (0.80 * s)
		pad_t := pole + up * (0.09 * s) + ldir * (0.80 * s)
		rl.DrawCylinderEx(pad_b, pad_t, 0.15 * s, 0.13 * s, 8, gunmetal)
		rl.DrawCylinderEx(pad_t, pad_t + up * (0.08 * s), 0.045 * s, 0.045 * s, 6, steel_bright)
		rl.DrawCylinderEx(pad_t, pad_t + up * (0.01 * s), 0.13 * s, 0.13 * s, 8, rl.Fade(cyan_glow, 0.7))
	}

	// 2. Azimuth Turntable Ring & Traversing Platform Deck
	tt_b := pole + up * (0.22 * s)
	tt_t := pole + up * (0.30 * s)
	rl.DrawCylinderEx(tt_b, tt_t, 0.35 * s, 0.35 * s, 16, gunmetal)
	rl.DrawCylinderEx(tt_t, tt_t + up * (0.01 * s), 0.34 * s, 0.34 * s, 16, cyan_glow)

	deck_b := tt_t
	deck_t := pole + up * (0.38 * s)
	rl.DrawCylinderEx(deck_b, deck_t, 0.33 * s, 0.31 * s, 8, sand_base)

	// 3. Twin Trunnion Stanchions (Mounting Cheeks) & Pivot Axle
	ch_h: f32 = 0.28 * s
	ch_w: f32 = 0.09 * s
	ch_l: f32 = 0.26 * s
	ch_y := 0.51 * s
	pos_left := pole + up * ch_y - right * (0.16 * s)
	pos_right := pole + up * ch_y + right * (0.16 * s)
	draw_oriented_box(pos_left, ch_w * 0.5, ch_h * 0.5, ch_l * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(pos_right, ch_w * 0.5, ch_h * 0.5, ch_l * 0.5, fwd, up, right, sand_base)

	axle_y := 0.58 * s
	axle_l := pole + up * axle_y - right * (0.23 * s)
	axle_r := pole + up * axle_y + right * (0.23 * s)
	rl.DrawCylinderEx(axle_l, axle_r, 0.055 * s, 0.055 * s, 8, steel_bright)
	rl.DrawCylinderEx(axle_l, axle_l - right * (0.03 * s), 0.08 * s, 0.075 * s, 8, gunmetal)
	rl.DrawCylinderEx(axle_r, axle_r + right * (0.03 * s), 0.08 * s, 0.075 * s, 8, gunmetal)

	// Hydraulic elevation ram under cradle
	ram_b := pole + up * (0.37 * s) + fwd * (0.10 * s)
	ram_t := pole + up * (0.53 * s) + fwd * (0.03 * s) - barrel_normal * (0.07 * s)
	rl.DrawCylinderEx(ram_b, ram_t, 0.045 * s, 0.035 * s, 6, steel_bright)
	rl.DrawCylinderEx(ram_b, (ram_b + ram_t) * 0.5, 0.058 * s, 0.058 * s, 6, gunmetal)

	// 4. Sloped Gun Shield (Schutzschild) & Targeting Optronics
	sh_center := pole + up * (0.58 * s) + fwd * (0.19 * s)
	pl_w: f32 = 0.14 * s
	pl_h: f32 = 0.44 * s
	pl_th: f32 = 0.03 * s
	draw_oriented_box(sh_center - right * (0.14 * s), pl_w * 0.5, pl_h * 0.5, pl_th * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(sh_center + right * (0.14 * s), pl_w * 0.5, pl_h * 0.5, pl_th * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(sh_center + up * (0.19 * s), 0.22 * s, 0.06 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_light)

	// Angled side cheek wings (bent backwards along -fwd)
	h_half := up * (0.21 * s)
	w_l_root := sh_center - right * (0.21 * s)
	w_l_tip  := w_l_root - right * (0.16 * s) - fwd * (0.14 * s)
	draw_quad_3d(w_l_root - h_half, w_l_tip - h_half, w_l_tip + h_half, w_l_root + h_half, sand_dark)

	w_r_root := sh_center + right * (0.21 * s)
	w_r_tip  := w_r_root + right * (0.16 * s) - fwd * (0.14 * s)
	draw_quad_3d(w_r_root - h_half, w_r_tip - h_half, w_r_tip + h_half, w_r_root + h_half, sand_dark)

	// Optronic sensor pod on left shield
	pod_pos := sh_center - right * (0.15 * s) + up * (0.10 * s) + fwd * (0.04 * s)
	draw_oriented_box(pod_pos, 0.055 * s, 0.065 * s, 0.075 * s, fwd, up, right, gunmetal)
	rl.DrawSphereEx(pod_pos + fwd * (0.08 * s) + up * (0.022 * s), 0.024 * s, 6, 6, cyan_glow)
	rl.DrawSphereEx(pod_pos + fwd * (0.08 * s) - up * (0.022 * s), 0.028 * s, 6, 6, amber_lens)

	// Communications mast on right shield
	mast_b := sh_center + right * (0.19 * s) + up * (0.22 * s)
	mast_t := mast_b + up * (0.30 * s) - fwd * (0.04 * s)
	rl.DrawCylinderEx(mast_b, mast_t, 0.016 * s, 0.007 * s, 4, steel_bright)
	beacon_pulse := 0.75 + 0.25 * math.sin(laser_anim_time * 8.0 + f32(planet_idx))
	rl.DrawSphere(mast_t, 0.022 * s, rl.Fade(cyan_glow, beacon_pulse))

	// If upgrading: Pulsating Red Ambulance Lights on top of the shield!
	if is_upgrading {
		light_l := sh_center - right * (0.16 * s) + up * (0.26 * s)
		light_r := sh_center + right * (0.16 * s) + up * (0.26 * s)
		draw_ambulance_hazard_lights(light_l, light_r, s)
	}

	// 5. Gun Cradle & Breech Mechanism
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	breech_c := pivot - barrel_dir * (0.16 * s)
	draw_oriented_box(breech_c, 0.10 * s, 0.09 * s, 0.15 * s, barrel_dir, barrel_normal, right, gunmetal)
	draw_oriented_box(breech_c + barrel_normal * (0.08 * s), 0.09 * s, 0.025 * s, 0.14 * s, barrel_dir, barrel_normal, right, sand_base)

	// Heatsink slats with cyan thermal channels
	draw_oriented_box(breech_c + right * (0.105 * s), 0.008 * s, 0.045 * s, 0.11 * s, barrel_dir, barrel_normal, right, cyan_glow)
	draw_oriented_box(breech_c - right * (0.105 * s), 0.008 * s, 0.045 * s, 0.11 * s, barrel_dir, barrel_normal, right, cyan_glow)

	// Upper recoil cylinder
	rc_s := pivot - barrel_dir * (0.18 * s) + barrel_normal * (0.11 * s)
	rc_e := pivot + barrel_dir * (0.35 * s) + barrel_normal * (0.11 * s)
	rl.DrawCylinderEx(rc_s, rc_e, 0.045 * s, 0.045 * s, 8, steel_bright)
	rl.DrawCylinderEx(rc_s, rc_s + barrel_dir * (0.06 * s), 0.058 * s, 0.058 * s, 8, gunmetal)

	// Lower recuperator cylinder
	rp_s := pivot - barrel_dir * (0.14 * s) - barrel_normal * (0.09 * s)
	rp_e := pivot + barrel_dir * (0.28 * s) - barrel_normal * (0.09 * s)
	rl.DrawCylinderEx(rp_s, rp_e, 0.038 * s, 0.038 * s, 8, steel_bright)

	// 6. Stepped Barrel with Magnetic Rail Accelerator Coils & Double-Baffle Muzzle Brake
	// Stage 1: Base Thermal Sleeve
	s1_s := pivot
	s1_e := pivot + barrel_dir * (0.45 * s)
	rl.DrawCylinderEx(s1_s, s1_e, 0.088 * s, 0.076 * s, 10, sand_base)
	rl.DrawCylinderEx(s1_s, s1_s + barrel_dir * (0.09 * s), 0.10 * s, 0.10 * s, 10, gunmetal)

	// Stage 2: Accelerator Section
	s2_s := s1_e
	s2_e := pivot + barrel_dir * (1.25 * s)
	rl.DrawCylinderEx(s2_s, s2_e, 0.070 * s, 0.058 * s, 10, gunmetal)

	for c_i in 0..<4 {
		c_t: f32 = 0.12 + f32(c_i) * 0.25
		c_pos := s2_s + barrel_dir * ((0.75 * c_t) * s)
		c_len := c_pos + barrel_dir * (0.038 * s)
		rl.DrawCylinderEx(c_pos, c_len, 0.082 * s, 0.082 * s, 10, cyan_glow)
		rl.DrawCylinderEx(c_pos, c_pos + barrel_dir * (0.008 * s), 0.086 * s, 0.086 * s, 10, mint_core)
		rl.DrawCylinderEx(c_len - barrel_dir * (0.008 * s), c_len, 0.086 * s, 0.086 * s, 10, mint_core)
	}

	// Stage 3: Forward Barrel
	s3_s := s2_e
	s3_e := pivot + barrel_dir * (1.75 * s)
	rl.DrawCylinderEx(s3_s, s3_e, 0.054 * s, 0.044 * s, 10, sand_base)

	// Stage 4: Double-Baffle Muzzle Brake
	mb_s := s3_e
	mb_e := s3_e + barrel_dir * (0.22 * s)
	rl.DrawCylinderEx(mb_s, mb_e, 0.074 * s, 0.074 * s, 8, gunmetal)
	baf1 := mb_s + barrel_dir * (0.06 * s)
	rl.DrawCylinderEx(baf1, baf1 + barrel_dir * (0.03 * s), 0.092 * s, 0.092 * s, 8, frame_mid)
	baf2 := mb_s + barrel_dir * (0.13 * s)
	rl.DrawCylinderEx(baf2, baf2 + barrel_dir * (0.03 * s), 0.092 * s, 0.092 * s, 8, frame_mid)

	rl.DrawCylinderEx(mb_e - barrel_dir * (0.015 * s), mb_e, 0.048 * s, 0.048 * s, 8, mint_core)
	rl.DrawSphereEx(mb_e, 0.032 * s, 6, 6, cyan_glow)

	// 7. Tech upgrades for higher defense levels
	if level >= 2 {
		cap_l := pole + up * (0.40 * s) - right * (0.24 * s) - fwd * (0.08 * s)
		cap_r := pole + up * (0.40 * s) + right * (0.24 * s) - fwd * (0.08 * s)
		rl.DrawCylinderEx(cap_l, cap_l + up * (0.16 * s), 0.060 * s, 0.060 * s, 8, sand_dark)
		rl.DrawCylinderEx(cap_r, cap_r + up * (0.16 * s), 0.060 * s, 0.060 * s, 8, sand_dark)
		rl.DrawLine3D(cap_l + up * (0.02 * s), cap_l + up * (0.14 * s), cyan_glow)
		rl.DrawLine3D(cap_r + up * (0.02 * s), cap_r + up * (0.14 * s), cyan_glow)

		rail_s := s1_e + barrel_normal * (0.085 * s)
		rail_e := s2_e + barrel_normal * (0.075 * s)
		rl.DrawLine3D(rail_s, rail_e, cyan_glow)
	}

	if level >= 3 {
		radar_b := pole + up * (0.40 * s) + right * (0.24 * s) - fwd * (0.14 * s)
		radar_t := radar_b + up * (0.24 * s)
		rl.DrawCylinderEx(radar_b, radar_t, 0.02 * s, 0.015 * s, 4, steel_bright)

		radar_sweep := laser_anim_time * 2.2 + f32(planet_idx)
		r_dir := rl.Vector3{math.cos(radar_sweep), 0.35, math.sin(radar_sweep)}
		rl.DrawCylinderEx(radar_t, radar_t + r_dir * (0.025 * s), 0.12 * s, 0.08 * s, 8, sand_light)
		rl.DrawLine3D(radar_t, radar_t + r_dir * (0.13 * s), cyan_glow)
		rl.DrawSphere(radar_t + r_dir * (0.035 * s), 0.022 * s, cyan_glow)
	}

	if level >= 4 {
		p_pulse := 0.65 + 0.35 * math.sin(laser_anim_time * 6.0 + f32(planet_idx))
		rl.DrawSphereEx(breech_c, 0.08 * s * p_pulse, 6, 8, rl.Fade(cyan_glow, 0.85))
	}

	if level >= 6 {
		bcap_l := pole + up * (0.32 * s) - right * (0.28 * s) - fwd * (0.22 * s)
		bcap_r := pole + up * (0.32 * s) + right * (0.28 * s) - fwd * (0.22 * s)
		rl.DrawCylinderEx(bcap_l, bcap_l + up * (0.20 * s), 0.075 * s, 0.075 * s, 8, gunmetal)
		rl.DrawCylinderEx(bcap_r, bcap_r + up * (0.20 * s), 0.075 * s, 0.075 * s, 8, gunmetal)
		rl.DrawCylinderEx(bcap_l + up * (0.05 * s), bcap_l + up * (0.15 * s), 0.082 * s, 0.082 * s, 8, cyan_glow)
		rl.DrawCylinderEx(bcap_r + up * (0.05 * s), bcap_r + up * (0.15 * s), 0.082 * s, 0.082 * s, 8, cyan_glow)
	}

	if level >= 8 {
		draw_oriented_box(sh_center - right * (0.34 * s), 0.10 * s, 0.36 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_dark)
		draw_oriented_box(sh_center + right * (0.34 * s), 0.10 * s, 0.36 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_dark)
		rl.DrawLine3D(sh_center - right * (0.38 * s) - up * (0.16 * s), sh_center - right * (0.38 * s) + up * (0.16 * s), cyan_glow)
		rl.DrawLine3D(sh_center + right * (0.38 * s) - up * (0.16 * s), sh_center + right * (0.38 * s) + up * (0.16 * s), cyan_glow)
	}

	if level >= 10 {
		under_s := s1_e - barrel_normal * (0.085 * s)
		under_e := s3_e - barrel_normal * (0.065 * s)
		rl.DrawLine3D(under_s, under_e, mint_core)
		corona_pulse := 0.70 + 0.30 * math.sin(laser_anim_time * 9.0 + f32(planet_idx))
		corona_r: f32 = 0.16 * s * corona_pulse
		rl.DrawCircle3D(mb_e + barrel_dir * (0.06 * s), corona_r, barrel_dir, 32, rl.Fade(cyan_glow, 0.85))
		rl.DrawCircle3D(mb_e + barrel_dir * (0.09 * s), corona_r * 0.7, barrel_dir, 24, rl.Fade(mint_core, 0.95))
	}
}

// Visual construction site for an orbital defense battery being assembled by miners
draw_cyberpunk_flak88_construction_site :: proc(planet_idx: int) {
	if planet_idx < 0 || planet_idx >= PLANET_COUNT { return }
	planet := planets[planet_idx]
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	up := rl.Vector3{0, 1, 0}
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)

	gunmetal := rl.Color{40, 44, 52, 255}
	cyan_glow := SCIFI_CYAN
	mint_core := SCIFI_MINT

	// Base outriggers & pads
	for d_idx in 0..<4 {
		ang := f32(d_idx) * (math.PI / 2.0)
		ldir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		l_start := pole + up * (0.05 * s)
		l_end := pole + up * (0.04 * s) + ldir * (0.75 * s)
		rl.DrawLine3D(l_start, l_end, cyan_glow)

		pad_b := pole + up * (0.01 * s) + ldir * (0.75 * s)
		pad_t := pole + up * (0.07 * s) + ldir * (0.75 * s)
		rl.DrawCylinderEx(pad_b, pad_t, 0.13 * s, 0.11 * s, 8, gunmetal)
	}

	// Staging pylons with alternating ambulance pulsating hazard lights
	st_l := pole + up * (0.65 * s) - rl.Vector3{0.35 * s, 0, 0}
	st_r := pole + up * (0.65 * s) + rl.Vector3{0.35 * s, 0, 0}
	rl.DrawCylinderEx(pole - rl.Vector3{0.35 * s, 0, 0}, st_l, 0.02 * s, 0.015 * s, 6, gunmetal)
	rl.DrawCylinderEx(pole + rl.Vector3{0.35 * s, 0, 0}, st_r, 0.02 * s, 0.015 * s, 6, gunmetal)
	draw_ambulance_hazard_lights(st_l, st_r, s)

	rl.DrawCylinderEx(pole + up * (0.02 * s), pole + up * (0.03 * s), 0.38 * s, 0.38 * s, 16, cyan_glow)
	rl.DrawCylinderEx(pole + up * (0.18 * s), pole + up * (0.19 * s), 0.34 * s, 0.34 * s, 16, cyan_glow)

	pulse := 0.70 + 0.30 * math.sin(laser_anim_time * 3.5)
	rl.DrawSphereWires(pole + up * (0.45 * s), 0.85 * s, 6, 10, rl.Fade(cyan_glow, pulse * 0.45))
	rl.DrawCylinderEx(pole + up * (0.035 * s), pole + up * (0.045 * s), 0.95 * s, 0.95 * s, 24, rl.Fade(cyan_glow, 0.55))

	prog: f32 = 0.0
	if ORBITAL_DEFENSE_BUILD_TIME > 0 {
		prog = clamp(orbital_defense_progress[planet_idx] / ORBITAL_DEFENSE_BUILD_TIME, 0.05, 0.95)
	}
	ring_y := 0.08 + prog * 0.70
	rl.DrawCylinderEx(pole + up * (ring_y * s), pole + up * ((ring_y + 0.015) * s), 0.65 * s * (1.05 - prog * 0.3), 0.65 * s * (1.05 - prog * 0.3), 20, mint_core)

	spark_ang := laser_anim_time * 6.5 + f32(planet_idx) * 2.0
	spark_pt := pole + up * (ring_y * s) + rl.Vector3{math.cos(spark_ang) * 0.45 * s, 0, math.sin(spark_ang) * 0.45 * s}
	spark_target := pole + up * (0.15 * s)
	rl.DrawLine3D(spark_pt, spark_target, rl.Color{255, 255, 200, 255})
	rl.DrawSphere(spark_pt, 0.045 * s, rl.Color{255, 255, 220, 255})
}

// Renders the intense energy beam from operational planetary refineries to Earth,
// with a brilliant white core transitioning to deep blue at the edges,
// carrying beamed mineral packets directly to the homeworld.
draw_refinery_mineral_beams :: proc() {
	has_any := false
	for p in 0..<PLANET_COUNT {
		if planet_has_refinery_beam(p) { has_any = true; break }
	}
	if !has_any { return }

	earth_pos := planets[EARTH].position
	earth_rad := planets[EARTH].radius

	// Disable depth write so additive layers blend seamlessly without occluding each other,
	// while keeping depth test enabled so planets in front still occlude the beam.
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	defer {
		rl.EndBlendMode()
		rlgl.EnableDepthMask()
	}

	for p in 0..<PLANET_COUNT {
		if !planet_has_refinery_beam(p) { continue }

		p_pos := planets[p].position
		p_rad := planets[p].radius
		diff := earth_pos - p_pos
		dist := rl.Vector3Length(diff)
		if dist < 0.1 { continue }
		dir := diff * (1.0 / dist)

		// Terminals on celestial surfaces
		start_pos := p_pos + dir * (p_rad + 0.1)
		end_pos := earth_pos - dir * (earth_rad + 0.1)
		beam_len := rl.Vector3Length(end_pos - start_pos)
		if beam_len < 0.1 { continue }

		// Dynamic high-energy beam pulse
		pulse := 0.85 + 0.15 * math.sin(laser_anim_time * 6.0 + f32(p) * 1.5)
		outer_alpha := u8(clamp(150.0 * pulse, 110, 180))
		mid_alpha := u8(clamp(190.0 * pulse, 150, 220))
		inner_alpha := u8(clamp(220.0 * pulse, 180, 255))
		core_alpha := u8(clamp(255.0 * pulse, 240, 255))

		// Concentric additive gradient:
		// Searing pure white at center, smoothly transitioning outward to deep electric blue
		// 1. Outer rich royal blue halo (radius 0.23, 8 sides)
		rl.DrawCylinderEx(start_pos, end_pos, 0.23, 0.23, 8, rl.Color{0, 65, 255, outer_alpha})

		// 2. Mid vivid electric blue layer (radius 0.14, 6 sides)
		rl.DrawCylinderEx(start_pos, end_pos, 0.14, 0.14, 6, rl.Color{0, 150, 255, mid_alpha})

		// 3. Inner cyan-white transition zone (radius 0.07, 6 sides)
		rl.DrawCylinderEx(start_pos, end_pos, 0.07, 0.07, 6, rl.Color{70, 210, 255, inner_alpha})

		// 4. White-hot central core cylinder (radius 0.035, 4 sides)
		rl.DrawCylinderEx(start_pos, end_pos, 0.035, 0.035, 4, rl.Color{255, 255, 255, core_alpha})

		// 5. Intense pure white center spine line
		rl.DrawLine3D(start_pos, end_pos, rl.Color{255, 255, 255, 255})

		// 6. Emitter terminal glow halos at planet and receiver on Earth (low-poly spheres)
		glow_rad: f32 = 0.30 * pulse
		rl.DrawSphereEx(start_pos, glow_rad, 6, 8, rl.Color{0, 90, 255, 160})
		rl.DrawSphereEx(start_pos, glow_rad * 0.45, 4, 6, rl.Color{255, 255, 255, 255})

		rl.DrawSphereEx(end_pos, glow_rad, 6, 8, rl.Color{0, 90, 255, 160})
		rl.DrawSphereEx(end_pos, glow_rad * 0.45, 4, 6, rl.Color{255, 255, 255, 255})

		// 7. Beamed mineral packets streaming from planet to Earth along the beam
		if planet_can_mine(p) && planet_miner_drone_count(p) > 0 {
			num_packets := clamp(int(beam_len / 25.0), 3, 6)
			packet_speed: f32 = 18.0
			for k in 0..<num_packets {
				travel := math.mod(laser_anim_time * packet_speed + f32(k) * (beam_len / f32(num_packets)), beam_len)
				pkt_pos := start_pos + dir * travel
				trail_pos := pkt_pos - dir * 1.5
				rl.DrawLine3D(trail_pos, pkt_pos, rl.Color{140, 230, 255, 240})
				rl.DrawSphereEx(pkt_pos, 0.16, 4, 6, rl.Color{0, 130, 255, 200})
				rl.DrawSphereEx(pkt_pos, 0.07, 4, 4, rl.Color{255, 255, 255, 255})
			}
		}
	}
}

draw_inspector :: proc() {
	panel_orig_x := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	h := f32(rl.GetScreenHeight())

	// Floating tactical console container inset by 8px from screen edges (inspired by Star Fox Zero map console)
	container_x := panel_orig_x + 4.0
	container_y: f32 = 12.0
	container_w := f32(SCREEN_PANEL_WIDTH) - 8.0
	container_h := h - 24.0

	draw_tactical_container({container_x, container_y, container_w, container_h})

	x := panel_orig_x

	// Header: clean planet name on the left, MPS on the right (no borders, no corners)
	header_y: c.int = 26
	is_enemy := selected_planet == ENEMY_HOME

	if is_enemy {
		hq_title: cstring = "ENEMY CITADEL"
		if enemy_hq_destroyed() { hq_title = "CITADEL SILENCED (DEAD)" }
		rl.DrawText(hq_title, c.int(x + PANEL_PAD_X), header_y, 17, SCIFI_RED)
	} else {
		rl.DrawText(planets[selected_planet].name, c.int(x + PANEL_PAD_X), header_y, 17, SCIFI_TEXT)

		if selected_planet == EARTH || has_vision(selected_planet) || intel_recorded[selected_planet] {
			mps_text := rl.TextFormat("%.1f MPS", planet_mps(selected_planet))
			mps_w := f32(rl.MeasureText(mps_text, 14))
			rl.DrawText(mps_text, c.int(x + PANEL_PAD_X + PANEL_CONTENT_W - mps_w), header_y + 2, 14, SCIFI_AMBER)
		} else {
			unscouted: cstring = "DARK"
			uw := f32(rl.MeasureText(unscouted, 14))
			rl.DrawText(unscouted, c.int(x + PANEL_PAD_X + PANEL_CONTENT_W - uw), header_y + 2, 14, SCIFI_MUTED)
		}
	}

	if selected_planet == EARTH {
		draw_earth_inspector(x)
	} else if selected_planet == ENEMY_HOME {
		draw_hq_inspector(x)
	} else {
		draw_outpost_inspector(x)
	}

	// Scouted-but-dark planets draw dimmed ghost rosters from the frozen intel
	// snapshot instead of any live section; lit planets draw live rosters.
	if ghost_view() {
		draw_ghost_rosters(x)
	} else if selected_planet == EARTH || has_vision(selected_planet) {
		mining_count := roster_count(.MINING)
		mining_hdr := selected_planet != ENEMY_HOME ? rl.TextFormat("MINING DRONES (%d/%d)", mining_count, planet_mining_cap(selected_planet)) : rl.TextFormat("MINING DRONES (%d)", mining_count)
		y_mining := unit_tile_y(.MINING)
		draw_section_header(x + PANEL_PAD_X, f32(y_mining - 23), PANEL_CONTENT_W, mining_hdr, SCIFI_AMBER)
		m_ord := 0
		for i := 0; i < unit_count; i += 1 {
			if unit_in_roster(i, .MINING) {
				draw_unit_tile(i, x, y_mining, m_ord, false)
				m_ord += 1
			}
		}
		combat_count := roster_count(.COMBAT)
		y_combat := unit_tile_y(.COMBAT)
		draw_section_header(x + PANEL_PAD_X, f32(y_combat - 23), PANEL_CONTENT_W, rl.TextFormat("FIGHTING DRONES (%d)", combat_count), SCIFI_BLUE)
		c_ord := 0
		for i := 0; i < unit_count; i += 1 {
			if unit_in_roster(i, .COMBAT) {
				draw_unit_tile(i, x, y_combat, c_ord, false)
				c_ord += 1
			}
		}
		if has_vision(selected_planet) {
			enemy_mining := enemy_roster_count(.MINING)
			if enemy_mining > 0 {
				y_em := enemy_tile_y(.MINING)
				draw_section_header(x + PANEL_PAD_X, f32(y_em - 23), PANEL_CONTENT_W, rl.TextFormat("HOSTILE MINING (%d)", enemy_mining), SCIFI_RED)
				em_ord := 0
				for i := 0; i < unit_count; i += 1 {
					if enemy_in_roster(i, .MINING) {
						draw_unit_tile(i, x, y_em, em_ord, true)
						em_ord += 1
					}
				}
			}
			enemy_combat := enemy_roster_count(.COMBAT)
			if enemy_combat > 0 {
				y_ec := enemy_tile_y(.COMBAT)
				draw_section_header(x + PANEL_PAD_X, f32(y_ec - 23), PANEL_CONTENT_W, rl.TextFormat("HOSTILE FIGHTERS (%d)", enemy_combat), SCIFI_RED)
				ec_ord := 0
				for i := 0; i < unit_count; i += 1 {
					if enemy_in_roster(i, .COMBAT) {
						draw_unit_tile(i, x, y_ec, ec_ord, true)
						ec_ord += 1
					}
				}
			}
		}
	}
	if h > 700 {
		sel_y := f32(rl.GetScreenHeight() - 36)
		sel_rect := rl.Rectangle{x + PANEL_PAD_X, sel_y, PANEL_CONTENT_W, 22}
		sel_count := selection_count()
		if sel_count > 0 {
			draw_chamfered_panel(sel_rect, 4, rl.Color{10, 30, 40, 240}, SCIFI_CYAN)
			draw_corner_brackets(sel_rect, 1, 4, SCIFI_MINT)
			rl.DrawText(rl.TextFormat("ACTIVE SQUAD: %d UNITS SELECTED", sel_count), i32(sel_rect.x + 10), i32(sel_rect.y + 5), 11, SCIFI_MINT)
		} else {
			draw_chamfered_panel(sel_rect, 4, SCIFI_PANEL_SOLID, SCIFI_DIM)
			rl.DrawText("NO UNITS SELECTED", i32(sel_rect.x + 10), i32(sel_rect.y + 5), 11, SCIFI_MUTED)
		}
	}
	// Live drag rectangle for the inspector box-select.
	if inspector_drag_active {
		rect := rect_between(inspector_drag_start, rl.GetMousePosition())
		rl.DrawRectangleRec(rect, rl.Fade(SCIFI_CYAN, 0.18))
		rl.DrawRectangleLinesEx(rect, 1, SCIFI_CYAN)
		draw_corner_brackets(rect, 0, 6, SCIFI_MINT)
	}
}

// Earth owns the command bases: base pips, base construction, production
// lines and the build queue all live here and nowhere else.
draw_earth_inspector :: proc(x: f32) {
	if base_button_visible() {
		base_button := rl.Rectangle{x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}
		if base_build_planet == EARTH {
			progress := base_build_progress / BASE_CONSTRUCT_TIME
			draw_chamfered_panel(base_button, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			// Construction progress now fills the button itself, left to right,
			// instead of a separate bar beneath it. The text is drawn on top so
			// it stays legible as the green fill advances.
			fill_w := base_button.width * progress
			fill_rect := rl.Rectangle{base_button.x, base_button.y, fill_w, base_button.height}
			rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 120})
			draw_corner_brackets(base_button, 2, 6, SCIFI_CYAN)
			if base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
				rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", base_constructing_miners(EARTH), BASE_CONSTRUCT_MINERS), i32(x + PANEL_PAD_X + CARD_INSET), SECTION_TOP + 12, 11, rl.WHITE)
			} else {
				rl.DrawText(rl.TextFormat("COMMAND BASE  %3.1fs", BASE_CONSTRUCT_TIME - base_build_progress), i32(x + PANEL_PAD_X + CARD_INSET), SECTION_TOP + 11, 13, rl.WHITE)
			}
		} else {
			can_build_base := minerals >= BASE_COST && base_counts[EARTH] < MAX_BASES && base_build_planet < 0 && planet_liberated(EARTH)
			draw_button(base_button, "Command Base (+1 parallel build) (500)", SCIFI_PANEL_SOLID, can_build_base)
		}
	}

	draw_orbital_defense_inspector_section(x, orbital_defense_button_rect(x, EARTH), EARTH)

	orders_y := production_orders_y()
	draw_section_header(x + PANEL_PAD_X, f32(orders_y - 23), PANEL_CONTENT_W, "FLEET REQUISITION", SCIFI_AMBER)
	queue_not_full := queued_count(EARTH) < base_counts[EARTH] * 5
	can_build_miner := minerals >= unit_cost(.MINING) && queue_not_full
	can_build_combat := minerals >= unit_cost(.COMBAT) && queue_not_full
	draw_button({x + PANEL_PAD_X, f32(orders_y), BUILD_BTN_W, BUILD_BTN_H}, rl.TextFormat("[M] MINER  (%d)", MINER_COST), SCIFI_PANEL_SOLID, can_build_miner)
	draw_button({x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(orders_y), BUILD_BTN_W, BUILD_BTN_H}, rl.TextFormat("[C] COMBAT (%d)", COMBAT_COST), SCIFI_PANEL_SOLID, can_build_combat)

	if base_counts[EARTH] >= MAX_BASES {
		draw_button(queue_5_miner_button_rect(x), rl.TextFormat("[N] +5 MINERS (%d)", BATCH_MINER_COST), SCIFI_PANEL_SOLID, can_build_5_miners())
		draw_button(queue_5_combat_button_rect(x), rl.TextFormat("[X] +5 COMBAT (%d)", BATCH_COMBAT_COST), SCIFI_PANEL_SOLID, can_build_5_combat())
	}

	if !drone_speed_maxed() {
		can_upgrade_speed := minerals >= DRONE_SPEED_UPGRADE_COST
		draw_button(drone_speed_button_rect(x), rl.TextFormat("[U] DRONE BUILD SPEED (%d)", DRONE_SPEED_UPGRADE_COST), SCIFI_PANEL_SOLID, can_upgrade_speed)
	}

	queue_y := earth_queue_y()
	queue_capacity := base_counts[EARTH] * MAX_BASES
	queue_total := queued_count(EARTH)
	draw_section_header(x + PANEL_PAD_X, f32(queue_y), PANEL_CONTENT_W, rl.TextFormat("QUEUE BUFFER (%d/%d)", queue_total, queue_capacity), SCIFI_CYAN)
	if base_counts[EARTH] >= MAX_BASES {
		draw_autobuild_radio_buttons(x)
	}
	for slot := 0; slot < queue_capacity; slot += 1 {
		queued := slot < queue_total
		kind := Unit_Type.MINING
		progress: f32 = -1
		if queued { kind = queue_kind_at(EARTH, slot); progress = queue_progress_at(EARTH, slot) }
		draw_queue_slot(queue_slot_rect(x, slot), queued, kind, progress)
	}
}

// The enemy HQ sector inspector: fortress status card plus the shared unit
// rosters. Drawn for ENEMY_HOME instead of the outpost card.
draw_hq_inspector :: proc(x: f32) {
	card := rl.Rectangle{x + PANEL_PAD_X, OUTPOST_CARD_Y, PANEL_CONTENT_W, CARD_H}
	if enemy_hq_destroyed() {
		draw_status_card(card, SCIFI_DIM)
		rl.DrawText("CITADEL SILENCED - HUSK", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("NO WAVES LAUNCH FROM A DEAD HQ", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	} else if has_vision(ENEMY_HOME) {
		_, garrison := planet_combatants(ENEMY_HOME)
		draw_status_card(card, SCIFI_RED)
		rl.DrawText("HOSTILE CITADEL", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_RED)
		if orbital_defense_level[ENEMY_HOME] > 0 {
			max_hp := orbital_defense_max_hp(ENEMY_HOME)
			cur_hp := orbital_defense_hp[ENEMY_HOME]
			rl.DrawText(rl.TextFormat("GARRISON %d   DEF LVL %d (HP %d/%d)", garrison, orbital_defense_level[ENEMY_HOME], cur_hp, max_hp), i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2 - 2, 11, SCIFI_TEXT)
			draw_progress({x + PANEL_PAD_X + CARD_INSET, CARD_LINE_2 + 13, PANEL_CONTENT_W - 2 * CARD_INSET, 6}, f32(cur_hp) / f32(max(1, max_hp)), SCIFI_RED)
		} else {
			rl.DrawText(rl.TextFormat("FIGHTERS %d   INTEGRITY %d/%d (DEF OFFLINE)", garrison, enemy_base_hp[ENEMY_HOME], ENEMY_HQ_BASE_HP), i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2 - 2, 11, SCIFI_TEXT)
			draw_progress({x + PANEL_PAD_X + CARD_INSET, CARD_LINE_2 + 13, PANEL_CONTENT_W - 2 * CARD_INSET, 6}, f32(enemy_base_hp[ENEMY_HOME]) / f32(ENEMY_HQ_BASE_HP), SCIFI_RED)
		}
	} else {
		draw_status_card(card, SCIFI_STEEL)
		rl.DrawText("UNSCOUTED REACHES", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("DISPATCH COMBAT DRONES TO REVEAL", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	}
}

// Outpost planets host no player bases: show the mining forecast, the enemy
// stronghold status (mining is locked until it falls) and unit rosters only.
draw_outpost_inspector :: proc(x: f32) {
	if !planet_liberated(selected_planet) {
		card := rl.Rectangle{x + PANEL_PAD_X, OUTPOST_CARD_Y, PANEL_CONTENT_W, CARD_H}
		if has_vision(selected_planet) {
			stronghold_color := SCIFI_RED
			title: cstring = "ENEMY STRONGHOLD"
			_, garrison := planet_combatants(selected_planet)
			status := rl.TextFormat("%02d FIGHTERS  BASE %02d: HOSTILE OCCUPATION", garrison, enemy_base_hp[selected_planet])
			draw_status_card(card, stronghold_color)
			rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, stronghold_color)
			rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
		} else if intel_recorded[selected_planet] {
			intel := last_known_intel[selected_planet]
			title: cstring = "ENEMY STRONGHOLD (STALE INTEL)"
			status := rl.TextFormat("%02d FIGHTERS  BASE %02d/%02d: PREVIOUS RECON", intel.fighters, intel.miners, GARRISON_BASE_HP[selected_planet])
			draw_status_card(card, SCIFI_AMBER)
			rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_AMBER)
			rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_MUTED)
		} else {
			draw_status_card(card, SCIFI_STEEL)
			rl.DrawText("UNSCOUTED SECTOR", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
			rl.DrawText("STATUS UNKNOWN: DISPATCH SCOUT", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
		}
	}

	if planet_liberated(selected_planet) {
		btn := refinery_button_rect(x)
		if refinery_building[selected_planet] {
			draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			fill_rect := rl.Rectangle{btn.x, btn.y, btn.width * (refinery_progress[selected_planet] / REFINERY_BUILD_TIME), btn.height}
			rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 120})
			draw_corner_brackets(btn, 2, 6, SCIFI_CYAN)
			if refinery_constructing_miners(selected_planet) < REFINERY_CONSTRUCT_MINERS {
				rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", refinery_constructing_miners(selected_planet), REFINERY_CONSTRUCT_MINERS), i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 12), 11, SCIFI_CYAN)
			} else {
				remaining := REFINERY_BUILD_TIME - refinery_progress[selected_planet]
				rl.DrawText(rl.TextFormat("REFINERY  %3.1fs", remaining), i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 11), 13, SCIFI_CYAN)
			}
		} else if !refinery_built[selected_planet] {
			cost := refinery_cost(selected_planet)
			can_build := can_build_refinery(selected_planet)
			draw_button(btn, rl.TextFormat("Build Refinery (%d)", cost), SCIFI_PANEL_SOLID, can_build)
		} else {
			draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			draw_corner_brackets(btn, 2, 6, SCIFI_MINT)
			rl.DrawText("REFINERY OPERATIONAL", i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 11), 13, SCIFI_MINT)
		}
		def_btn := orbital_defense_button_rect(x, selected_planet)
		draw_orbital_defense_inspector_section(x, def_btn, selected_planet)
	}
}

// Ghost rosters for a scouted-but-dark planet: header + tiles per section,
// all from the frozen intel snapshot, then a translucent grey-out over the
// whole roster area so it reads as stale.
draw_ghost_rosters :: proc(x: f32) {
	enemy_header := rl.Color{235, 110, 110, 255}
	intel := last_known_intel[selected_planet]

	// Player mining section (with cap) + fighting section. Section kinds come
	// from the same table for both loops: a defaulted kind that only the
	// mining branch overrides once drew every section as .MINING, stacking the
	// two enemy headers/tiles on one origin (and dropping fighters entirely).
	kinds := [2]Unit_Type{.MINING, .COMBAT}
	for section in 0..<2 {
		kind := kinds[section]
		label: cstring = "FIGHTING DRONES"
		color := SCIFI_BLUE
		if section == 0 { label = "MINING DRONES"; color = SCIFI_AMBER }
		count := ghost_count(kind, false)
		if count == 0 { continue }
		y := unit_tile_y(kind)
		hdr := section == 0 ? rl.TextFormat("%s (%d/%d) [STALE]", label, count, planet_mining_cap(selected_planet)) : rl.TextFormat("%s (%d) [STALE]", label, count)
		draw_section_header(x + PANEL_PAD_X, f32(y - 23), PANEL_CONTENT_W, hdr, color)
		ordinal := 0
		for i := 0; i < intel.unit_count; i += 1 {
			u := &intel.units[i]
			if u.kind != kind || u.enemy { continue }
			draw_unit_tile_data(u.kind, u.state, false, x, y, ordinal, false)
			ordinal += 1
		}
	}

	// Enemy mining + fighting sections.
	for section in 0..<2 {
		kind := kinds[section]
		label: cstring = "HOSTILE FIGHTERS"
		if section == 0 { label = "HOSTILE MINING" }
		count := ghost_count(kind, true)
		if count == 0 { continue }
		y := enemy_tile_y(kind)
		draw_section_header(x + PANEL_PAD_X, f32(y - 23), PANEL_CONTENT_W, rl.TextFormat("%s (%d) [STALE]", label, count), SCIFI_RED)
		ordinal := 0
		for i := 0; i < intel.unit_count; i += 1 {
			u := &intel.units[i]
			if u.kind != kind || !u.enemy { continue }
			draw_unit_tile_data(u.kind, u.state, false, x, y, ordinal, true)
			ordinal += 1
		}
	}

	// Grey-out overlay across the roster area: stale snapshot, not live units.
	top := f32(unit_tile_y(.MINING) - 22)
	rl.DrawRectangleRec(rl.Rectangle{x, top, SCREEN_PANEL_WIDTH - 6, f32(rl.GetScreenHeight() - 40) - top}, rl.Color{6, 16, 22, 160})
}

// When all bases are built on Earth, the Command Base button disappears and
// orbital defense collapses up to SECTION_TOP; the production sections flow
// dynamically below orbital defense and any active construction progress bars.
production_title_y :: proc() -> int {
	if selected_planet == EARTH {
		return int(earth_orbital_defense_bottom_y() + 10)
	}
	return PROD_TITLE_Y
}

production_first_y :: proc() -> int {
	return production_title_y() + 23
}

production_orders_y :: proc() -> int {
	base_y := ORDERS_BASE_Y
	if selected_planet == EARTH {
		return int(earth_orbital_defense_bottom_y()) + 44
	}
	return base_y + max(base_counts[selected_planet] - 1, 0) * PROD_PITCH
}

queued_count :: proc(planet: int) -> int {
	count := pending_count[planet]
	for b := 0; b < base_counts[planet]; b += 1 { if production[planet][b].active { count += 1 } }
	return count
}

queue_kind_at :: proc(planet, index: int) -> Unit_Type {
	queue_index := index
	for b := 0; b < base_counts[planet]; b += 1 {
		if !production[planet][b].active { continue }
		if queue_index == 0 { return production[planet][b].kind }
		queue_index -= 1
	}
	return pending[planet][queue_index]
}

// Returns the build progress (0..1) for the queue slot at `index`, or -1 when
// that slot is a pending (not-yet-building) unit.
queue_progress_at :: proc(planet, index: int) -> f32 {
	queue_index := index
	for b := 0; b < base_counts[planet]; b += 1 {
		if !production[planet][b].active { continue }
		if queue_index == 0 {
			total := drone_build_time(production[planet][b].kind)
			return production[planet][b].progress / total
		}
		queue_index -= 1
	}
	return -1
}

unit_in_roster :: proc(index: int, kind: Unit_Type) -> bool {
	if units[index].enemy { return false }
	if units[index].kind != kind { return false }
	if kind == .MINING { return units[index].target_planet == selected_planet }
	return units[index].affiliation == selected_planet
}

roster_count :: proc(kind: Unit_Type) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if unit_in_roster(i, kind) { count += 1 } }
	return count
}

// Y of the first unit-tile row for a kind, derived so the MINING DRONES header
// and tiles always sit below every build queue row: the queue grid is
// base_counts rows tall (capacity = bases * MAX_BASES slots, 5 per row, 22px
// pitch) and must be cleared even with a full queue. Used by rendering, tile
// rects and click hitboxes alike, so they can never drift apart.
unit_tile_y :: proc(kind: Unit_Type) -> int {
	mining_rows := (view_count(.MINING, false) + TILES_PER_ROW - 1) / TILES_PER_ROW
	// Outpost inspectors dynamically position rosters below the refinery and
	// orbital defense sections (flowing with active progress bars); on Earth they flow below the build queue.
	y := ROSTER_BASE_Y
	if selected_planet == EARTH {
		extra_dy := 0
		if base_counts[EARTH] >= MAX_BASES {
			extra_dy = UPGRADE_DY
		}
		if drone_speed_maxed() {
			extra_dy -= UPGRADE_DY
		}
		y = production_orders_y() + ROSTER_BELOW_QUEUE + extra_dy + (base_counts[selected_planet] - 1) * GRID_PITCH
	} else if selected_planet != ENEMY_HOME && planet_liberated(selected_planet) {
		y = outpost_liberated_roster_y(selected_planet)
	}
	if kind == .COMBAT { y += SECTION_PAD_Y + mining_rows * (TILE_SIZE + TILE_GAP) }
	return y
}

// Enemy mirror of the roster predicates: garrison drones and attackers bound
// for the selected planet, counted for the ENEMY inspector sections.
enemy_in_roster :: proc(index: int, kind: Unit_Type) -> bool {
	u := &units[index]
	if !u.enemy || u.kind != kind { return false }
	if kind == .MINING { return u.target_planet == selected_planet }
	return u.affiliation == selected_planet
}

enemy_roster_count :: proc(kind: Unit_Type) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if enemy_in_roster(i, kind) { count += 1 } }
	return count
}

enemy_roster_ordinal :: proc(index: int, kind: Unit_Type) -> int {
	ordinal := 0
	for i := 0; i < index; i += 1 { if enemy_in_roster(i, kind) { ordinal += 1 } }
	return ordinal
}

// Y of the enemy unit-tile rows: directly below the player fighting roster,
// with the enemy mining section (when present) stacked above the fighters.
// If no enemy mining drones exist, enemy fighters collapse up to avoid an empty gap.
enemy_tile_y :: proc(kind: Unit_Type) -> int {
	combat_rows := (view_count(.COMBAT, false) + TILES_PER_ROW - 1) / TILES_PER_ROW
	y := unit_tile_y(.COMBAT) + SECTION_PAD_Y + combat_rows * (TILE_SIZE + TILE_GAP)
	if kind == .COMBAT {
		enemy_mining_count := view_count(.MINING, true)
		if enemy_mining_count > 0 {
			enemy_mining_rows := (enemy_mining_count + TILES_PER_ROW - 1) / TILES_PER_ROW
			y += SECTION_PAD_Y + enemy_mining_rows * (TILE_SIZE + TILE_GAP)
		}
	}
	return y
}

// Ghost view: a previously scouted planet currently under fog renders its
// rosters from the frozen intel snapshot instead of live units (Earth is
// always lit; the HQ has its own card).
ghost_view :: proc() -> bool {
	return selected_planet != EARTH && selected_planet != ENEMY_HOME && !has_vision(selected_planet) && intel_recorded[selected_planet]
}

// Count of one section inside the frozen intel snapshot.
ghost_count :: proc(kind: Unit_Type, enemy: bool) -> int {
	count := 0
	intel := last_known_intel[selected_planet]
	for i := 0; i < intel.unit_count; i += 1 {
		u := &intel.units[i]
		if u.kind == kind && u.enemy == enemy { count += 1 }
	}
	return count
}

// Roster size driving headers and tile layout: live counts while lit, the
// frozen snapshot counts in ghost view, so tiles never jump between frames.
view_count :: proc(kind: Unit_Type, enemy: bool) -> int {
	if ghost_view() { return ghost_count(kind, enemy) }
	if enemy { return enemy_roster_count(kind) }
	return roster_count(kind)
}

unit_tile_rect :: proc(x: f32, y: int, ordinal: int) -> rl.Rectangle {
	column := ordinal % TILES_PER_ROW
	row := ordinal / TILES_PER_ROW
	return rl.Rectangle{x + PANEL_PAD_X + f32(column * (TILE_SIZE + TILE_GAP)), f32(y + row * (TILE_SIZE + TILE_GAP)), TILE_SIZE, TILE_SIZE}
}

draw_unit_tile :: proc(index: int, x: f32, y: int, ordinal: int, enemy: bool) {
	draw_unit_tile_data(units[index].kind, units[index].state, selected_units[index], x, y, ordinal, enemy)
}

// Core tile renderer; the ghost view calls it directly with snapshot data.
draw_unit_tile_data :: proc(kind: Unit_Type, state: Unit_State, selected: bool, x: f32, y: int, ordinal: int, enemy: bool) {
	rect := unit_tile_rect(x, y, ordinal)
	if rect.y > f32(rl.GetScreenHeight()) || rect.y + rect.height < 0 { return }
	fill := rl.Color{10, 24, 34, 255}
	border := SCIFI_STEEL
	if enemy {
		fill = rl.Color{48, 18, 22, 255}
		border = SCIFI_RED_DIM
	} else if selected {
		fill = rl.Color{0, 60, 75, 255}
		border = SCIFI_CYAN
	}
	draw_chamfered_panel(rect, 3, fill, border)
	if selected && !enemy {
		draw_corner_brackets(rect, 1, 3, SCIFI_CYAN)
	}
	symbol: cstring = "M"
	accent := SCIFI_AMBER
	if kind == .COMBAT { symbol = "C"; accent = SCIFI_BLUE }
	if enemy { accent = SCIFI_RED }
	rl.DrawText(symbol, c.int(rect.x + 5), c.int(rect.y + 4), 11, accent)
	rl.DrawCircle(c.int(rect.x + rect.width - 4), c.int(rect.y + 4), 2, state_color(state))
}

// Layered enemy HQ dreadnought battlestation: inverted ventral keel with pulsating
// fusion core, heavy octagonal citadel foundation with armor applique panels and
// VLS missile grids, four cantilevered outrigger bastions with drone hangar launch
// bays, point-defense autocannons, and wingtip strobes, mid-deck superstructure
// with command bridge observation visor, towering sensor mast with rotating radar
// dish, and an integrated traversing Level 10 Orbital Defense heavy railgun battery.
// ---- Control-group squads ------------------------------------------------

SQUAD_COUNT :: 9

// Save the current selection as control group `group` (1..9), releasing the
// group's previous members. Saving with nothing selected clears the group.
save_squad :: proc(group: int) {
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group { units[i].squad = 0 }
		if selected_units[i] && !units[i].enemy { units[i].squad = group }
	}
}

// Recall a control group: replaces the selection with the group's living
// members (dead members were pruned on removal). Returns the selected count;
// 0 means an empty/dead squad cleanly selects nothing.
recall_squad :: proc(group: int) -> int {
	clear_selection()
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group && !units[i].enemy {
			selected_units[i] = true
			count += 1
		}
	}
	return count
}

squad_count :: proc(group: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group && !units[i].enemy { count += 1 }
	}
	return count
}

// Global HUD squad badges: `[n:count]` per assigned squad, under the top bar.
draw_squad_hud :: proc() {
	counts: [SQUAD_COUNT + 1]int
	for i := 0; i < unit_count; i += 1 {
		sq := units[i].squad
		if sq >= 1 && sq <= SQUAD_COUNT && !units[i].enemy {
			counts[sq] += 1
		}
	}
	x := f32(HUD_PAD)
	for g in 1..=SQUAD_COUNT {
		count := counts[g]
		if count == 0 { continue }
		label := rl.TextFormat("[%d:%d]", g, count)
		w := f32(rl.MeasureText(label, 13))
		badge := rl.Rectangle{x, BADGE_Y, w + 2 * BADGE_PAD, BADGE_H}
		draw_chamfered_panel(badge, 4, SCIFI_PANEL_SOLID, SCIFI_STEEL)
		draw_corner_brackets(badge, 1, 3, SCIFI_CYAN)
		rl.DrawText(label, c.int(x + BADGE_PAD), BADGE_Y + 4, 13, SCIFI_CYAN)
		x += badge.width + BADGE_GAP
	}
}

// ---- Pause menu ----------------------------------------------------------

// P or F10 toggles the pause menu (ESC is the build-cancel key).
pause_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.P) || rl.IsKeyPressed(.F10)
}

// Keyboard focus for the pause menu: 0 = CONTINUE, 1 = SAVE GAME, 2 = LOAD GAME, 3 = NEW GAME, 4 = QUIT.
// Reopening the menu always resets focus to CONTINUE.
PAUSE_MENU_OPTIONS :: 5
pause_menu_selection := 0

toggle_pause :: proc() {
	game_paused = !game_paused
	if game_paused {
		pause_menu_selection = 0
		save_feedback_timer = 0
	}
}

// Arrow-key focus movement: dir -1 = up, +1 = down, wrapping around.
advance_pause_selection :: proc(dir: int) {
	pause_menu_selection = (pause_menu_selection + dir + PAUSE_MENU_OPTIONS) % PAUSE_MENU_OPTIONS
}

// ENTER/KP_ENTER on the focused option - the same actions the mouse path takes.
activate_pause_selection :: proc() {
	switch pause_menu_selection {
	case 0:
		game_paused = false
	case 1:
		if save_game() {
			save_feedback_timer = 2.0
		}
	case 2:
		if load_game() {
			game_paused = false
		}
	case 3:
		restart_game()
		game_paused = false
	case 4:
		quit_requested = true
	}
}

// Small diamond glyph for the resource dock: four thin lines (the default
// raylib font lacks a unicode gem character, which rendered as '?').
draw_diamond :: proc(cx, cy, r: f32, color: rl.Color) {
	rl.DrawLineV({cx, cy - r}, {cx + r, cy}, color)
	rl.DrawLineV({cx + r, cy}, {cx, cy + r}, color)
	rl.DrawLineV({cx, cy + r}, {cx - r, cy}, color)
	rl.DrawLineV({cx - r, cy}, {cx, cy - r}, color)
}

// One unpaused simulation tick. The main loop skips this entirely while the
// pause menu is open, freezing camera, input, production and units.
step_simulation :: proc(dt: f32) {
	if hud_save_notification_timer > 0 {
		hud_save_notification_timer -= dt
	}
	update_camera(dt)
	update_input()
	update_production(dt)
	update_units(dt)
	update_enemy_waves(dt)
	update_planet_spin(dt)
	update_intel()
	// Wrapping the laser clock keeps f32 precision stable across long sessions.
	laser_anim_time = math.mod(laser_anim_time + dt, 3600.0)
	// Earth manufacturing activity indicator: smooth ramp-up when units are in production, graceful fade-out when idle.
	is_earth_producing := false
	for b in 0..<base_counts[EARTH] {
		if production[EARTH][b].active {
			is_earth_producing = true
			break
		}
	}
	if is_earth_producing || base_build_planet == EARTH {
		earth_industry_intensity = min(earth_industry_intensity + dt * 2.8, 1.0)
	} else {
		earth_industry_intensity = max(earth_industry_intensity - dt * 1.8, 0.0)
	}
	update_combat_nebula_intensity(dt)
	// Victory latch: every planet liberated AND the enemy HQ destroyed.
	if !victory && victory_achieved() { victory = true }
	// Defeat latch (edge-triggered; reset_world clears it): no bases AND no units.
	if !victory && !defeated && defeat_condition() { defeated = true }
}

// Smooth transition of combat nebula intensity: rapid flare-up in battle,
// graceful fade-out on victory, and warning red glow at half battle intensity
// starting 3 seconds before launch and persisting through enemy transit until
// the battle begins (transitioning smoothly from warning glare to battle glare).
// In addition, the source planet of an impending minor wave receives a yellow
// aura at half battle intensity starting 3 seconds before launch.
update_combat_nebula_intensity :: proc(dt: f32) {
	for s in 0..<SECTOR_COUNT {
		in_combat := sector_in_combat(s)
		sector_combat_state[s] = in_combat
		target: f32 = 0.0
		is_warning := planet_under_attack_warning(s)
		if is_warning {
			target = 0.5
		}
		if s == ENEMY_HOME {
			if !enemy_hq_destroyed() {
				target = in_combat ? 1.0 : 0.65
			}
		} else if in_combat {
			target = 1.0
		}
		rate: f32 = (in_combat || is_warning) ? 3.5 : 1.2
		combat_nebula_intensity[s] += (target - combat_nebula_intensity[s]) * clamp(dt * rate, 0.0, 1.0)

		is_src_warning := planet_attack_source_warning(s)
		src_target: f32 = is_src_warning ? 0.5 : 0.0
		src_rate: f32 = is_src_warning ? 3.5 : 1.2
		minor_wave_source_nebula_intensity[s] += (src_target - minor_wave_source_nebula_intensity[s]) * clamp(dt * src_rate, 0.0, 1.0)
	}
}

// Fog-of-war intel memory: while a planet is lit, keep snapshotting its
// enemy fighters, enemy miners and base HP. Once it goes dark the outpost
// inspector shows the last snapshot (last_known_intel) instead of nothing.
update_intel :: proc() {
	vis: [PLANET_COUNT]bool
	any_vis := false
	for p in 0..<PLANET_COUNT {
		if has_vision(p) {
			vis[p] = true
			any_vis = true
			last_known_intel[p] = Intel{base_hp = enemy_base_hp[p]}
			intel_recorded[p] = true
		}
	}
	if !any_vis { return }

	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT {
			p := u.affiliation
			if p >= 0 && p < PLANET_COUNT && vis[p] {
				intel := &last_known_intel[p]
				if u.enemy && u.state == .GUARDING {
					intel.fighters += 1
				}
				if intel.unit_count < INTEL_UNIT_CAP {
					intel.units[intel.unit_count] = Intel_Unit{kind = u.kind, state = u.state, enemy = u.enemy}
					intel.unit_count += 1
				}
			}
		} else if u.kind == .MINING {
			if u.enemy {
				p_aff := u.affiliation
				if p_aff >= 0 && p_aff < PLANET_COUNT && vis[p_aff] {
					last_known_intel[p_aff].miners += 1
				}
			}
			p_tgt := u.target_planet
			if p_tgt >= 0 && p_tgt < PLANET_COUNT && vis[p_tgt] {
				intel := &last_known_intel[p_tgt]
				if intel.unit_count < INTEL_UNIT_CAP {
					intel.units[intel.unit_count] = Intel_Unit{kind = u.kind, state = u.state, enemy = u.enemy}
					intel.unit_count += 1
				}
			}
		}
	}
}

pause_menu_rects :: proc() -> (box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	title_w := f32(rl.MeasureText("PAUSED", 36))
	box_w := max(title_w, f32(280)) + 60
	box_h: f32 = 352.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}
	btn_w := box.width - 2 * DIALOG_PAD
	continue_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 82, btn_w, DIALOG_BTN_H}
	save_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 134, btn_w, DIALOG_BTN_H}
	load_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 186, btn_w, DIALOG_BTN_H}
	new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 238, btn_w, DIALOG_BTN_H}
	quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 290, btn_w, DIALOG_BTN_H}
	return
}

update_pause_menu :: proc(dt: f32 = 0) {
	if save_feedback_timer > 0 {
		save_feedback_timer -= dt
	}
	if rl.IsKeyPressed(.UP) { advance_pause_selection(-1) }
	if rl.IsKeyPressed(.DOWN) { advance_pause_selection(1) }
	if rl.IsKeyPressed(.C) {
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.S) {
		if save_game() {
			save_feedback_timer = 2.0
		}
		return
	}
	if rl.IsKeyPressed(.L) {
		if load_game() {
			game_paused = false
		}
		return
	}
	if rl.IsKeyPressed(.N) {
		restart_game()
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.Q) {
		quit_requested = true
		return
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		activate_pause_selection()
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	_, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()
	mouse := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse, continue_rect) {
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, save_rect) {
		if save_game() {
			save_feedback_timer = 2.0
		}
	} else if rl.CheckCollisionPointRec(mouse, load_rect) {
		if load_game() {
			game_paused = false
		}
	} else if rl.CheckCollisionPointRec(mouse, new_game_rect) {
		restart_game()
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
		quit_requested = true
	}
}

draw_pause_menu :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 220})
	box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()

	draw_chamfered_panel(box, 12, SCIFI_PANEL, SCIFI_STEEL)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "MISSION PAUSED"
	title_w := f32(rl.MeasureText(title, 26))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 26), 26, SCIFI_CYAN)

	if save_feedback_timer > 0 {
		saved_txt: cstring = "GAME SAVED TO DISK"
		st_w := f32(rl.MeasureText(saved_txt, 12))
		rl.DrawText(saved_txt, c.int(box.x + (box.width - st_w) / 2), c.int(box.y + 58), 12, SCIFI_AMBER)
	}

	has_save := save_game_exists()
	draw_button(continue_rect, "[C] CONTINUE", SCIFI_PANEL_SOLID)
	draw_button(save_rect, "[S] SAVE GAME", SCIFI_PANEL_SOLID)
	if has_save {
		draw_button(load_rect, "[L] LOAD GAME", SCIFI_PANEL_SOLID)
	} else {
		draw_button(load_rect, "[L] LOAD GAME (NO SAVE)", rl.Color{10, 20, 28, 255}, false)
	}
	draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)

	focused_rect: rl.Rectangle
	switch pause_menu_selection {
	case 0: focused_rect = continue_rect
	case 1: focused_rect = save_rect
	case 2: focused_rect = load_rect
	case 3: focused_rect = new_game_rect
	case 4: focused_rect = quit_rect
	}
	draw_pause_focus(focused_rect)
}

// Keyboard focus highlight: outer corner brackets and subtle glow ring
draw_pause_focus :: proc(rect: rl.Rectangle) {
	if rect.width <= 0 { return }
	draw_corner_brackets(rect, 4, 8, SCIFI_CYAN)
	rl.DrawRectangleLinesEx({rect.x - 2, rect.y - 2, rect.width + 4, rect.height + 4}, 1, rl.Fade(SCIFI_CYAN, 0.45))
}

// ---- Controls overlay ---------------------------------------------------

open_controls_overlay :: proc() {
	controls_overlay_open = true
	game_paused = true
}

close_controls_overlay :: proc() {
	controls_overlay_open = false
	game_paused = false
}

controls_overlay_rects :: proc() -> (box: rl.Rectangle, close_btn: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box_w: f32 = 740.0
	box_h: f32 = 490.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}
	close_btn_w: f32 = 200.0
	close_btn_h: f32 = 36.0
	close_btn = rl.Rectangle{box.x + (box.width - close_btn_w) / 2, box.y + box.height - 50, close_btn_w, close_btn_h}
	return
}

update_controls_overlay :: proc() {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.C) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) || pause_key_pressed() {
		close_controls_overlay()
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mouse := rl.GetMousePosition()
		box, close_btn := controls_overlay_rects()
		if rl.CheckCollisionPointRec(mouse, close_btn) || !rl.CheckCollisionPointRec(mouse, box) {
			close_controls_overlay()
			return
		}
	}
}

draw_control_row :: proc(x, y: f32, key, desc: cstring) {
	rl.DrawText(key, c.int(x), c.int(y), 12, SCIFI_MINT)
	rl.DrawText(desc, c.int(x + 115), c.int(y), 12, SCIFI_TEXT)
}

draw_controls_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	box, close_btn := controls_overlay_rects()

	draw_chamfered_panel(box, 14, SCIFI_PANEL, SCIFI_CYAN)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "TACTICAL CONTROLS DIRECTIVE"
	title_w := f32(rl.MeasureText(title, 22))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 22), 22, SCIFI_CYAN)

	sub: cstring = "OPERATIONAL KEYBINDS AND COMMAND PROTOCOLS"
	sub_w := f32(rl.MeasureText(sub, 12))
	rl.DrawText(sub, c.int(box.x + (box.width - sub_w) / 2), c.int(box.y + 50), 12, SCIFI_MUTED)

	rl.DrawLineV({box.x + 24, box.y + 70}, {box.x + box.width - 24, box.y + 70}, SCIFI_DIM)

	col1_x := box.x + 32
	col2_x := box.x + 376

	// Column 1: Camera & Fleet Management
	cy1 := box.y + 84
	rl.DrawText("CAMERA AND NAVIGATION", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "WASD / ARROWS", "Pan tactical view")
	cy1 += 18
	draw_control_row(col1_x, cy1, "Q / E / SCROLL", "Zoom altitude in and out")
	cy1 += 18
	draw_control_row(col1_x, cy1, "SPACE", "Select Earth / Center view")

	cy1 += 26
	rl.DrawText("FLEET SELECTION AND SQUADS", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "LEFT CLICK", "Select planet, citadel, or drone")
	cy1 += 18
	draw_control_row(col1_x, cy1, "DRAG BOX", "Box-select unit tiles in panel")
	cy1 += 18
	draw_control_row(col1_x, cy1, "CTRL + CLICK", "Toggle individual units")
	cy1 += 18
	draw_control_row(col1_x, cy1, "SHIFT + 1-9", "Assign selection to Squad 1-9")
	cy1 += 18
	draw_control_row(col1_x, cy1, "1-9", "Recall assigned Squad 1-9")

	cy1 += 26
	rl.DrawText("TACTICAL DIRECTIVES", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "RIGHT CLICK", "Dispatch units to planet / HQ")
	cy1 += 18
	draw_control_row(col1_x, cy1, "R-CLICK EARTH", "Set or clear Earth rally flag")
	cy1 += 18
	draw_control_row(col1_x, cy1, "B / CLICK", "Build Refinery on outpost")
	cy1 += 18
	draw_control_row(col1_x, cy1, "O / CLICK", "Build / Upgrade Orbital Defense")

	// Column 2: Requisition, Simulation & Sensors
	cy2 := box.y + 84
	rl.DrawText("EARTH BASE REQUISITION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "M / CLICK", rl.TextFormat("Build Mining Drone (%d)", MINER_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "N", rl.TextFormat("Build +5 Miners (%d)", BATCH_MINER_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "C / CLICK", rl.TextFormat("Build Combat Fighter (%d)", COMBAT_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "X", rl.TextFormat("Build +5 Fighters (%d)", BATCH_COMBAT_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "U / SPEED", "Upgrade Build Speed (5,000)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "T", "Toggle Autobuild On / Off")
	cy2 += 18
	draw_control_row(col2_x, cy2, "ESC", "Cancel last build (Refund)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CLICK SLOT", "Cancel specific queue slot")

	cy2 += 26
	rl.DrawText("SYSTEM AND SIMULATION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "P / F10", "Pause game / Mission menu")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F11", "Toggle fullscreen window")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F5", "Quick-save game state")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CTRL + N", "Debug: force enemy wave")

	cy2 += 26
	rl.DrawText("TACTICAL SENSORS", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "FOG OF WAR", "Presence required to scout")
	cy2 += 18
	draw_control_row(col2_x, cy2, "GHOST VIEW", "Stale intel retained dark")

	rl.DrawLineV({box.x + 24, box.y + box.height - 64}, {box.x + box.width - 24, box.y + box.height - 64}, SCIFI_DIM)

	draw_button(close_btn, "[C] RESUME GAME", SCIFI_PANEL_SOLID, true)
}

// ---- Start game menu ----------------------------------------------------

start_menu_options_count :: proc(has_save: bool) -> int {
	return has_save ? 3 : 2
}

advance_start_menu_selection :: proc(dir: int) {
	has_save := save_game_exists()
	count := start_menu_options_count(has_save)
	start_menu_selection = (start_menu_selection + dir + count) % count
}

activate_start_menu_selection :: proc() {
	has_save := save_game_exists()
	if has_save {
		switch start_menu_selection {
		case 0:
			if load_game() {
				in_start_menu = false
				game_paused = false
			}
		case 1:
			restart_game()
			in_start_menu = false
			game_paused = false
		case 2:
			quit_requested = true
		}
	} else {
		switch start_menu_selection {
		case 0:
			restart_game()
			in_start_menu = false
			game_paused = false
		case 1:
			quit_requested = true
		}
	}
}

start_menu_rects :: proc(has_save: bool) -> (box, continue_rect, new_game_rect, quit_rect: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box_w: f32 = 380.0
	box_h: f32 = has_save ? 270.0 : 218.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}

	btn_w := box.width - 2 * DIALOG_PAD
	if has_save {
		continue_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 78, btn_w, DIALOG_BTN_H}
		new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 130, btn_w, DIALOG_BTN_H}
		quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 182, btn_w, DIALOG_BTN_H}
	} else {
		continue_rect = rl.Rectangle{}
		new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 78, btn_w, DIALOG_BTN_H}
		quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 130, btn_w, DIALOG_BTN_H}
	}
	return
}

update_start_menu :: proc(dt: f32) {
	update_planet_spin(dt)
	laser_anim_time = math.mod(laser_anim_time + dt, 3600.0)
	has_save := save_game_exists()
	count := start_menu_options_count(has_save)
	if start_menu_selection >= count {
		start_menu_selection = 0
	}

	if rl.IsKeyPressed(.UP) { advance_start_menu_selection(-1) }
	if rl.IsKeyPressed(.DOWN) { advance_start_menu_selection(1) }

	if has_save && rl.IsKeyPressed(.C) {
		if load_game() {
			in_start_menu = false
			game_paused = false
		}
		return
	}
	if rl.IsKeyPressed(.N) {
		restart_game()
		in_start_menu = false
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) {
		quit_requested = true
		return
	}

	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		activate_start_menu_selection()
		return
	}

	if !rl.IsMouseButtonPressed(.LEFT) { return }
	mouse := rl.GetMousePosition()
	_, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)
	if has_save && rl.CheckCollisionPointRec(mouse, continue_rect) {
		if load_game() {
			in_start_menu = false
			game_paused = false
		}
	} else if rl.CheckCollisionPointRec(mouse, new_game_rect) {
		restart_game()
		in_start_menu = false
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
		quit_requested = true
	}
}

draw_start_menu :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 220})
	has_save := save_game_exists()
	box, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)

	draw_chamfered_panel(box, 14, SCIFI_PANEL, SCIFI_STEEL)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "STARFALL COMMAND"
	title_w := f32(rl.MeasureText(title, 26))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 26), 26, SCIFI_CYAN)

	sub: cstring = "STRATEGIC SPACE DEFENSE"
	sub_w := f32(rl.MeasureText(sub, 10))
	rl.DrawText(sub, c.int(box.x + (box.width - sub_w) / 2), c.int(box.y + 56), 10, SCIFI_MUTED)

	focused_rect: rl.Rectangle
	if has_save {
		draw_button(continue_rect, "[C] CONTINUE", SCIFI_PANEL_SOLID)
		draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
		draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
		switch start_menu_selection {
		case 0: focused_rect = continue_rect
		case 1: focused_rect = new_game_rect
		case 2: focused_rect = quit_rect
		}
	} else {
		draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
		draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
		switch start_menu_selection {
		case 0: focused_rect = new_game_rect
		case 1: focused_rect = quit_rect
		}
	}
	draw_pause_focus(focused_rect)

	footer: cstring = "UP/DOWN: SELECT   ENTER: CONFIRM"
	footer_w := f32(rl.MeasureText(footer, 10))
	rl.DrawText(footer, c.int(box.x + (box.width - footer_w) / 2), c.int(box.y + box.height - 22), 10, SCIFI_MUTED)
}

// ---- Victory & restart --------------------------------------------------

// The enemy HQ falls once its structural HP hits 0 (planet_liberated covers
// planets; the HQ is a separate sector).
enemy_hq_destroyed :: proc() -> bool { return enemy_base_hp[ENEMY_HOME] <= 0 }

// The game is won once every planet is liberated AND the enemy HQ falls.
victory_achieved :: proc() -> bool {
	if !enemy_hq_destroyed() { return false }
	for p in 0..<PLANET_COUNT { if !planet_liberated(p) { return false } }
	return true
}

// Full clean restart: reset_world zeroes every global, initialize_game
// rebuilds the starting layout (Earth drones, garrisons, enemy HQ).
restart_game :: proc() {
	reset_world()
	initialize_game()
	camera_target = rl.Vector3{10, 0, 2}
	camera.position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y}
	camera.target = camera_target
}

// Shared by the render and the click hitboxes so they cannot drift apart.
// play = [R] PLAY AGAIN, quit = [Q] QUIT.
victory_button_rects :: proc() -> (play, quit: rl.Rectangle) {
	cy := f32(rl.GetScreenHeight() / 2 + 66)
	play = rl.Rectangle{f32(rl.GetScreenWidth() / 2 - 144), cy, 140, 44}
	quit = rl.Rectangle{f32(rl.GetScreenWidth() / 2 + 4), cy, 140, 44}
	return
}

// Q / ESC on the victory overlay request a clean exit (ESC is the build-cancel
// key during play, but the sim is frozen on victory so it is free to bind here).
victory_quit_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE)
}

// R / ENTER restart; Q / ESC quit. Clicks hit whichever button is under the
// cursor (a miss is a no-op so a stray click cannot end the run).
update_victory_overlay :: proc() {
	if rl.IsKeyPressed(.R) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) { restart_game(); return }
	if victory_quit_key_pressed() { quit_requested = true; return }
	if rl.IsMouseButtonPressed(.LEFT) {
		play_rect, quit_rect := victory_button_rects()
		mouse := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mouse, play_rect) {
			restart_game()
		} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
			quit_requested = true
		}
	}
}

draw_victory_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box := rl.Rectangle{w/2 - 280, h/2 - 130, 560, 270}
	draw_chamfered_panel(box, 16, SCIFI_PANEL, SCIFI_CYAN)
	draw_corner_brackets(box, 4, 16, SCIFI_CYAN)

	title: cstring = "SYSTEM LIBERATED"
	title_w := f32(rl.MeasureText(title, 32))
	rl.DrawText(title, c.int(w/2 - title_w/2), c.int(box.y + 36), 32, SCIFI_CYAN)

	sub: cstring = "ALL 8 PLANETS LIBERATED   ENEMY HQ DESTROYED"
	sub_w := f32(rl.MeasureText(sub, 14))
	rl.DrawText(sub, c.int(w/2 - sub_w/2), c.int(box.y + 78), 14, SCIFI_MINT)

	stats: cstring = "CAMPAIGN OBJECTIVE ACHIEVED   SOLAR SECTOR SECURED"
	stats_w := f32(rl.MeasureText(stats, 11))
	rl.DrawText(stats, c.int(w/2 - stats_w/2), c.int(box.y + 104), 11, SCIFI_MUTED)

	hint: cstring = "R / ENTER: PLAY AGAIN   Q / ESC: QUIT"
	hint_w := f32(rl.MeasureText(hint, 10))
	rl.DrawText(hint, c.int(w/2 - hint_w/2), c.int(box.y + 140), 10, SCIFI_MUTED)

	play_rect, quit_rect := victory_button_rects()
	draw_button(play_rect, "[R] PLAY AGAIN", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
}

// ---- Game over -----------------------------------------------------------

// Defeat: no command base left on the map AND no player unit left anywhere
// (enemy garrisons and waves do not count). Pure so the test suite can drive
// it directly.
defeat_condition :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		if !units[i].enemy { return false }
	}
	for p in 0..<PLANET_COUNT {
		if base_counts[p] != 0 { return false }
	}
	return true
}

// R / ENTER restart; Q / ESC quit. Clicks hit whichever button is under the
// cursor (same layout as the victory overlay).
update_game_over_overlay :: proc() {
	if rl.IsKeyPressed(.R) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) { restart_game(); return }
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) { quit_requested = true; return }
	if rl.IsMouseButtonPressed(.LEFT) {
		play_rect, quit_rect := victory_button_rects()
		mouse := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mouse, play_rect) {
			restart_game()
		} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
			quit_requested = true
		}
	}
}

draw_game_over_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box := rl.Rectangle{w/2 - 280, h/2 - 130, 560, 270}
	draw_chamfered_panel(box, 16, SCIFI_PANEL, SCIFI_RED)
	draw_corner_brackets(box, 4, 16, SCIFI_RED)

	title: cstring = "CRITICAL DEFEAT"
	title_w := f32(rl.MeasureText(title, 32))
	rl.DrawText(title, c.int(w/2 - title_w/2), c.int(box.y + 36), 32, SCIFI_RED)

	sub: cstring = "ALL COMMAND BASES AND DRONES DESTROYED"
	sub_w := f32(rl.MeasureText(sub, 14))
	rl.DrawText(sub, c.int(w/2 - sub_w/2), c.int(box.y + 78), 14, SCIFI_TEXT)

	stats: cstring = "SECTOR DEFENSE COLLAPSED   HOSTILE FORCES PREVAIL"
	stats_w := f32(rl.MeasureText(stats, 11))
	rl.DrawText(stats, c.int(w/2 - stats_w/2), c.int(box.y + 104), 11, SCIFI_MUTED)

	hint: cstring = "R / ENTER: RESTART   Q / ESC: QUIT"
	hint_w := f32(rl.MeasureText(hint, 10))
	rl.DrawText(hint, c.int(w/2 - hint_w/2), c.int(box.y + 140), 10, SCIFI_MUTED)

	play_rect, quit_rect := victory_button_rects()
	draw_button(play_rect, "[R] RESTART", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
}

// ---- Fog of war ----------------------------------------------------------

// True if the player has a structure on planet p (operational or under construction):
// refinery, orbital defense, or command base.
has_player_structure :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if refinery_built[p] || refinery_building[p] { return true }
	if orbital_defense_level[p] > 0 || orbital_defense_building[p] { return true }
	if base_counts[p] > 0 || base_build_planet == p { return true }
	return false
}

// Dynamic vision: a planet is visible while the player has a structure on it
// (refinery, orbital defense, command base), or at least one player unit is
// in or near the planet - stationed in orbit, mining, guarding, constructing,
// idle on site, or passing within radius + 2.0. Earth is always lit. When the
// last player fighting drone at a planet is destroyed in combat, vision lingers
// for COMBAT_VISION_LINGER seconds before the planet falls back under fog.
has_vision :: proc(p: int) -> bool {
	if p < 0 || p >= SECTOR_COUNT { return false }
	if p == EARTH { return true }
	if combat_vision_timer[p] > 0 { return true }
	if has_player_structure(p) { return true }
	r := sector_radius(p) + 2.0
	r2 := r * r
	sp := sector_pos(p)
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.enemy { continue }
		dx := u.position.x - sp.x
		dy := u.position.y - sp.y
		dz := u.position.z - sp.z
		if dx*dx + dy*dy + dz*dz <= r2 {
			return true
		}
	}
	return false
}

// Per-unit fog gate for rendering: player units are always visible; enemy
// units are concealed while the player has no vision of the planet they are
// at (guarding/stationed) or heading to (transit).
is_concealed :: proc(u: ^Unit) -> bool {
	if !u.enemy { return false }
	p := u.affiliation
	if u.state == .TRANSIT { p = u.target_planet }
	return !has_vision(p)
}

// ---- Earth rally point ---------------------------------------------------

// Right-clicking Earth itself clears the rally: rallying to the home world
// is the same as having no rally at all. The enemy HQ is never a rally
// point (drones produced there would have nothing to do).
set_earth_rally :: proc(target: int) {
	if target == EARTH { earth_rally = NO_RALLY } else if target != ENEMY_HOME { earth_rally = target }
}

// Planet the rally flag flies over; 0 = no rally point set.
rally_flag_planet :: proc() -> int { return earth_rally }

// 3D rally flag (pole + pennant) above the rally world.
draw_rally_flag :: proc() {
	if earth_rally == NO_RALLY { return }
	p := planets[earth_rally]
	base := rl.Vector3{p.position.x, p.position.y + p.radius, p.position.z}
	top := rl.Vector3{p.position.x, p.position.y + p.radius + 3.4, p.position.z}
	rl.DrawCylinderEx(base, top, 0.07, 0.07, 6, rl.Color{205, 208, 218, 255})
	// Pennant: two windings so it reads from either side.
	tip := rl.Vector3{p.position.x + 1.7, top.y - 0.55, p.position.z}
	rl.DrawTriangle3D({p.position.x, top.y, p.position.z}, {p.position.x, top.y - 1.3, p.position.z}, tip, SCIFI_CYAN)
	rl.DrawTriangle3D({p.position.x, top.y - 1.3, p.position.z}, {p.position.x, top.y, p.position.z}, tip, SCIFI_CYAN)
}

// ---- Camera zoom ---------------------------------------------------------

// camera.position.y spans [15, 200] (clamped in update_camera); 15 = 100%.
zoom_percent :: proc() -> int {
	return int(clamp((200 - camera.position.y) / 185.0 * 100.0, 0, 100))
}

// Ray-sphere hit test for the enemy HQ (pick_planet covers planets only).
// Left-click selects the HQ sector in the inspector; right-click issues
// orders to it.
hq_picked :: proc(mouse: rl.Vector2) -> bool {
	ray := rl.GetScreenToWorldRay(mouse, camera)
	oc := rl.Vector3{ray.position.x - ENEMY_HQ_POSITION.x, ray.position.y - ENEMY_HQ_POSITION.y, ray.position.z - ENEMY_HQ_POSITION.z}
	b := rl.Vector3DotProduct(oc, ray.direction)
	c := rl.Vector3DotProduct(oc, oc) - ENEMY_HQ_RADIUS * ENEMY_HQ_RADIUS
	disc := b*b - c
	if disc < 0 { return false }
	return -b - math.sqrt(disc) >= 0
}

pick_planet :: proc(mouse: rl.Vector2) -> int {
	ray := rl.GetScreenToWorldRay(mouse, camera)
	closest := f32(999999)
	hit := -1
	for p := 0; p < PLANET_COUNT; p += 1 {
		planet := planets[p]
		oc := rl.Vector3{ray.position.x - planet.position.x, ray.position.y - planet.position.y, ray.position.z - planet.position.z}
		b := rl.Vector3DotProduct(oc, ray.direction)
		c := rl.Vector3DotProduct(oc, oc) - planet.radius * planet.radius
		disc := b*b - c
		if disc < 0 { continue }
		t := -b - math.sqrt(disc)
		if t >= 0 && t < closest { closest = t; hit = p }
	}
	return hit
}

distance :: rl.Vector3Distance
