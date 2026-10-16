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

earth_industry_intensity: f32

in_start_menu := true
start_menu_selection := 0
hud_save_notification_timer: f32
save_feedback_timer: f32

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 760, "STARFALL COMMAND: Planetary RTS Prototype")
	defer rl.CloseWindow()
	rl.ToggleBorderlessWindowed()

	refresh := rl.GetMonitorRefreshRate(rl.GetCurrentMonitor())
	target_fps := refresh > 0 ? max(refresh, 60) : 60
	rl.SetTargetFPS(target_fps * 2)

	rl.SetExitKey(.KEY_NULL)

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

