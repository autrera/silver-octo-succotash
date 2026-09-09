package main

import "core:math"
import "core:mem"
import "core:c"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import rl "vendor:raylib"

SCREEN_PANEL_WIDTH :: 330
MAX_BASES :: 5
// Standing garrisons number ~420 planetside plus the enemy HQ's 500
// fighters, so the pool holds those plus a full late-game player fleet.
MAX_UNITS :: 2560
// The system in solar order: Earth — the player's only starter planet — sits
// at index 2, so every hardcoded 0/1/2 planet index is gone.
PLANET_COUNT :: 8
MERCURY :: 0
VENUS :: 1
EARTH :: 2
MARS :: 3
JUPITER :: 4
SATURN :: 5
URANUS :: 6
NEPTUNE :: 7

// Sectors extend the planet list by one: sector ENEMY_HOME is the enemy HQ
// fortress (not a planet), so the per-planet combat tables (timers, base
// HP) cover it too and the combat procs work on it unchanged.
SECTOR_COUNT :: PLANET_COUNT + 1
ENEMY_HOME :: PLANET_COUNT

// The enemy HQ: a fortress at Neptune's ORIGINAL orbit {140, 5, 24} (before
// the outer planets moved in), defended by 500 fighter drones with 500
// structural HP. Every attack wave launches from here; destroying it — plus
// liberating every planet — wins the game.
ENEMY_HQ_POSITION := rl.Vector3{140, 5, 24}
ENEMY_HQ_RADIUS :: 2.6
ENEMY_HQ_GARRISON :: 500
ENEMY_HQ_BASE_HP :: 500

// Combat pacing: one 1:1 kill trade per side every COMBAT_TICK seconds. At
// 0.2s the 500-drone HQ siege and every dogfight resolves 5x faster than the
// old 1s tick.
COMBAT_TICK :: 0.2
// Uncontested enemy siege time per player command base on Earth: with no
// defenders or miners left, one base falls every BASE_SIEGE_TIME seconds.
BASE_SIEGE_TIME :: 2.0
// Enemy attack waves: first at the 3-minute mark, then every 3 minutes. The
// clock only advances while the player actively mines WAVE_MIN_MINING_PLANETS
// (2) or more worlds — a smaller footprint draws no retaliation.
WAVE_FIRST_DELAY :: 180
WAVE_INTERVAL :: 180
// Attacks only occur once the player mines at least this many worlds.
WAVE_MIN_MINING_PLANETS :: 2
// Wave size scales with liberation: (liberated planets - 1) * 15 fighters —
// 3 liberated planets send 30 fighters. Earth starts liberated, so the first
// wave only bites once a second world falls.
WAVE_FIGHTERS_PER_LIBERATED :: 15
// Every planet except Earth opens occupied: garrison fighters, garrison
// miners and enemy base HP all scale up with distance from Earth
// (Venus 10/4/10 ... Neptune 95/22/60; indexed by sector, with the enemy HQ
// as the last, heaviest entry).
GARRISON_FIGHTERS := [SECTOR_COUNT]int{30, 10, 0, 20, 45, 60, 75, 95, ENEMY_HQ_GARRISON}
GARRISON_MINERS := [SECTOR_COUNT]int{8, 4, 0, 6, 10, 14, 18, 22, 0}
GARRISON_BASE_HP := [SECTOR_COUNT]int{20, 10, 0, 15, 30, 40, 50, 60, ENEMY_HQ_BASE_HP}
// Drone production per command base line (mining 6s, combat 10s).
MINER_BUILD_TIME :: 6.0
COMBAT_BUILD_TIME :: 10.0
// Command base construction price, deducted up front when the build queues.
BASE_COST :: 500
// Drone build-speed upgrade: 5000 minerals per level; each level builds
// drones 20% faster (compounding), five levels max (~33% of base time).
DRONE_SPEED_UPGRADE_COST :: 5000
DRONE_SPEED_UPGRADE_MAX :: 5
DRONE_SPEED_UPGRADE_FACTOR :: 0.8
// A command base needs 5 mining drones present at the planet and takes one
// full minute to build; those drones stop mining until it completes.
BASE_CONSTRUCT_MINERS :: 5
BASE_CONSTRUCT_TIME :: 60.0
// Transit speeds run at 25% of the pre-warpace pace: slow enough that
// dispatches are commitments. Mining transit dropped a further 25%
// (1.75 -> 1.3125) in the war-economy rebalance.
COMBAT_TRANSIT_SPEED :: 2.5
MINING_TRANSIT_SPEED :: 1.3125
// Mining drone cycle timing (shared by the simulation and the MPS forecast).
// On-site mining takes 4s (up 33% from 3s), for ~25% slower mining overall.
MINING_DURATION :: 4.0
DEPOSIT_DURATION :: 0.5
// Scout survival: garrison defenses hold fire this long against a miner
// freshly pinned at an occupied planet (.IDLE progress doubles as the clock).
SCOUT_SURVIVAL :: 3.5
// Combat vision linger: when the player's last fighting drone at a planet is
// destroyed in combat, vision of that planet persists for this many seconds
// before falling back under fog of war.
COMBAT_VISION_LINGER :: 3.0
// Flying laser bolts: flight speed along the shooter->target ray and the
// visible bolt length.
LASER_BOLT_SPEED :: 14.0
LASER_BOLT_LEN :: 0.65

Unit_Type :: enum {MINING, COMBAT}
Unit_State :: enum {IDLE, TRANSIT, MINING, RETURNING, DEPOSITING, GUARDING, CONSTRUCTING}

Planet :: struct {
	name: cstring,
	position: rl.Vector3,
	radius: f32,
	color: rl.Color,
}

Production :: struct {
	kind: Unit_Type,
	progress: f32,
	active: bool,
}

// Last-known intel snapshot, recorded while a planet is lit; shown under fog
// once the planet has been scouted at least once. The per-unit roster feeds
// the dimmed ghost inspector view drawn while the planet is dark.
INTEL_UNIT_CAP :: 200
Intel_Unit :: struct {
	kind: Unit_Type,
	state: Unit_State,
	enemy: bool,
}
Intel :: struct {
	fighters: int,
	miners: int,
	base_hp: int,
	units: [INTEL_UNIT_CAP]Intel_Unit,
	unit_count: int,
}

MAX_PENDING :: 25
TILE_SIZE :: 16
TILE_GAP :: 6
TILES_PER_ROW :: 10

// ---- Sci-Fi Cyberpunk HUD Palette ---------------------------------------
// Vibrant teal/cyan HUD vector interface style matching reference:
// dark teal-black glass panels, razor-sharp cyan frames, amber tactical accents.
SCIFI_CYAN       :: rl.Color{0, 240, 216, 255}    // Primary vibrant laser cyan (#00F0D8)
SCIFI_MINT       :: rl.Color{140, 255, 235, 255}  // Bright highlight & glow (#8CFFEB)
SCIFI_BLUE       :: rl.Color{0, 200, 245, 255}    // Combat / wing blue (#00C8F5)
SCIFI_AMBER      :: rl.Color{255, 128, 36, 255}   // Tactical amber / warning accent (#FF8024)
SCIFI_AMBER_DIM  :: rl.Color{140, 65, 18, 255}    // Dim amber (#8C4112)
SCIFI_RED        :: rl.Color{255, 60, 75, 255}    // Hostile / alert red (#FF3C4B)
SCIFI_RED_DIM    :: rl.Color{120, 30, 40, 255}    // Dim hostile red (#781E28)
SCIFI_STEEL      :: rl.Color{18, 110, 122, 255}   // Active framing & border (#126E7A)
SCIFI_DIM        :: rl.Color{6, 58, 68, 255}      // Inactive grid & frames (#063A44)
SCIFI_PANEL      :: rl.Color{6, 16, 22, 240}      // Translucent deep teal glass (#061016)
SCIFI_PANEL_SOLID:: rl.Color{8, 22, 30, 255}      // Solid dark teal backing (#08161E)
SCIFI_TEXT       :: rl.Color{215, 245, 245, 255}  // Primary crisp text (#D7F5F5)
SCIFI_MUTED      :: rl.Color{85, 145, 155, 255}   // Secondary muted tech text (#55919B)


// ---- Inspector layout ---------------------------------------------------
// One horizontal grid for the whole side panel: headers, cards, buttons,
// production lines and rosters all align to PANEL_PAD_X with content width
// PANEL_CONTENT_W. Section tops flow from SECTION_TOP through ORDERS_BASE_Y
// into the queue/roster procs below. Render procs and click hitboxes share
// every constant, so graphics and hitboxes cannot drift apart.
PANEL_PAD_X :: 20
PANEL_CONTENT_W :: SCREEN_PANEL_WIDTH - 2 * PANEL_PAD_X
CARD_INSET :: 10
BTN_GAP :: 12
BUILD_BTN_W :: 139
BUILD_BTN_H :: 36
BASE_BTN_H :: 36
SLOT_SIZE :: 18
GRID_PITCH :: 24
PROD_PITCH :: 34
PANEL_SUB_Y :: 60
OUTPOST_CARD_Y :: PANEL_SUB_Y
BASES_Y :: 60
SECTION_TOP :: 92
CARD_H :: 54
CARD_LINE_1 :: OUTPOST_CARD_Y + 14
CARD_LINE_2 :: OUTPOST_CARD_Y + 33
REFINERY_BTN_Y :: 122
OUTPOST_LIBERATED_ROSTER_Y :: 200
BASE_PROGRESS_Y :: 134
PROD_TITLE_Y :: 166
PROD_FIRST_Y :: 189
PROD_BAR_DY :: 16
ORDERS_BASE_Y :: 260
BASE_COLLAPSE_Y :: PROD_TITLE_Y - SECTION_TOP
UPGRADE_DY :: 48
UPGRADE_H :: 36
QUEUE_DY :: 108
QUEUE_LABEL_GAP :: 23
DIALOG_PAD :: 28
DIALOG_BTN_H :: 44
HUD_PAD :: 16
PIPS_OFF :: 56
BADGE_PAD :: 8
BADGE_GAP :: 8
BADGE_Y :: 72
BADGE_H :: 20
BOTTOM_DOCK_H :: 36
ROSTER_BASE_Y :: 150
ROSTER_BELOW_QUEUE :: 206
SECTION_PAD_Y :: 26
PROD_BAR_W :: 200
BAR_H :: 8

Unit :: struct {
	kind: Unit_Type,
	state: Unit_State,
	position: rl.Vector3,
	home_planet: int,
	affiliation: int,
	target_planet: int,
	enemy: bool,
	progress: f32,
	orbit_angle: f32,
	// Control-group assignment: 0 = none, 1..9 = squad number. Living on the
	// unit itself keeps squads pruned as units are destroyed and shifted.
	squad: int,
}

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

// ---- Planet visuals -----------------------------------------------------
// Procedural textured planet models: each planet gets a 128x128 perlin-noise
// texture tinted to its base color (bands for gas giants, blobs for rocky
// worlds), mapped onto a sphere mesh so DrawModelEx can spin it slowly.
// Initialized once after InitWindow (needs a GL context); draw_world falls
// back to flat DrawSphere until ready (headless tests never init).
planet_models: [PLANET_COUNT]rl.Model
planet_textures: [PLANET_COUNT]rl.Texture2D
planet_visuals_ready := false
// Slow per-planet spin angle (radians); advanced in step_simulation so spin
// freezes on pause. Outer giants turn a touch faster for visible motion.
planet_spin: [PLANET_COUNT]f32

Drone_Model_Kind :: enum {
	PLAYER_MINER,
	ENEMY_MINER,
	PLAYER_FIGHTER,
	ENEMY_FIGHTER,
}
drone_models: [Drone_Model_Kind]rl.Model
drone_visuals_ready := false

units: [MAX_UNITS]Unit
unit_count: int
selected_units: [MAX_UNITS]bool
selected_planet := EARTH
minerals := 350
// Drone build-speed upgrade level (0..DRONE_SPEED_UPGRADE_MAX).
drone_speed_level := 0
// Player command bases exist only on Earth; set by initialize_game/reset_world.
base_counts: [PLANET_COUNT]int
production: [PLANET_COUNT][MAX_BASES]Production
pending: [PLANET_COUNT][MAX_PENDING]Unit_Type
pending_count: [PLANET_COUNT]int
base_build_progress: f32
base_build_planet := -1
REFINERY_BUILD_TIME :: 60.0
REFINERY_CONSTRUCT_MINERS :: 10
refinery_built: [PLANET_COUNT]bool
refinery_building: [PLANET_COUNT]bool
refinery_progress: [PLANET_COUNT]f32
camera: rl.Camera3D
// Framing: center of the planet extents (X -30..50, Z -20..24) after the
// Earth-centered repositioning; pan/zoom covers the far-off enemy HQ.
camera_target := rl.Vector3{10, 0, 2}
// Startup altitude: 200 - 185*0.60 so zoom_percent() opens at exactly 60% —
// high enough to frame the whole Earth-centered system (X -30..50, Z -20..24)
// beside the 330px inspector panel (all eight planets on screen at open).
CAMERA_START_Y :: 200.0 - 185.0 * 0.60
inspector_drag_start: rl.Vector2
inspector_drag_active: bool

// Enemy occupation: per-sector base HP. Every planet except Earth starts
// with an enemy command base; a planet is liberated once its base is
// destroyed (and, by the combat rules, all enemy drones are gone). The last
// entry is the enemy HQ's structural HP. Initialized from GARRISON_BASE_HP
// by initialize_game and reset_world.
enemy_base_hp: [SECTOR_COUNT]int
enemy_wave_timer: f32
wave_started: bool
// Per-planet combat pacing: 1:1 fighter trades, miner sweeps and base damage
// all tick on COMBAT_TICK.
combat_timer: [SECTOR_COUNT]f32
miner_timer: [SECTOR_COUNT]f32
base_timer: [SECTOR_COUNT]f32
combat_vision_timer: [SECTOR_COUNT]f32

game_paused := false
controls_overlay_open := false
quit_requested := false
// Victory: latched once every planet is liberated AND the enemy HQ falls;
// freezes the sim behind the victory overlay until restart.
victory := false
// Defeat: latched once no command base AND no player unit remains; freezes
// the sim behind the game-over overlay until restart.
defeated := false
// Earth rally point: NO_RALLY (-1) means no rally set. (Earth used to double
// as the 0 sentinel before the planet reindex.)
NO_RALLY :: -1
earth_rally := NO_RALLY
// Fog-of-war intel memory: per-planet snapshot plus a scouted-at-least-once bit.
last_known_intel: [PLANET_COUNT]Intel
intel_recorded: [PLANET_COUNT]bool
// Game-clock accumulator driving laser bolt flight; frozen while paused.
laser_anim_time: f32
// Visual intensity of the red palpitating combat nebula per sector [0..SECTOR_COUNT-1].
// Planets flare up when drones are actively fighting there; enemy HQ maintains an
// ominous background presence that surges to maximum intensity during an assault.
combat_nebula_intensity: [SECTOR_COUNT]f32
sector_combat_state: [SECTOR_COUNT]bool
// Pre-allocated sector rendering spots for draw_world representation pass
World_Sector_Spots :: struct {
	player_combat: [256]rl.Vector3,
	enemy_combat:  [256]rl.Vector3,
	player_miners: [256]rl.Vector3,
	enemy_miners:  [256]rl.Vector3,
	pc:  int,
	ec:  int,
	pmc: int,
	emc: int,
}
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

	// VSYNC handles refresh timing (60Hz / 120Hz). Setting target FPS to 2x the monitor
	// refresh rate acts as an upper safety cap for unconstrained runs while ensuring raylib's
	// internal WaitTime nanosleep never oversleeps into the next hardware vblank cycle (which
	// would otherwise cause the display to drop cadence from 60 FPS down to 30 FPS).
	refresh := rl.GetMonitorRefreshRate(rl.GetCurrentMonitor())
	target_fps := refresh > 0 ? max(refresh, 60) : 60
	rl.SetTargetFPS(target_fps * 2)

	rl.SetExitKey(.KEY_NULL) // ESC cancels the last queued build instead of closing the window; P/F10 pause.

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
	base_counts = {}
	base_counts[EARTH] = 1
	enemy_base_hp = GARRISON_BASE_HP
	unit_count = 0
	units[unit_count] = Unit{kind = .MINING, state = .MINING, position = {3.8, 0.4, 0}, home_planet = EARTH, affiliation = EARTH, target_planet = EARTH}
	unit_count += 1
	units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, position = {0, 3.8, 0}, home_planet = EARTH, affiliation = EARTH, target_planet = EARTH, orbit_angle = 0.5}
	unit_count += 1
	// Space backdrop: deterministic starfield (independent of the wave RNG).
	generate_stars()
	// Every non-Earth sector opens occupied: the GARRISON_* tables form the
	// fixed occupation ladder (Venus easiest ... Neptune hardest, HQ last) —
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
	base_counts[EARTH] = 1
	base_build_planet = -1
	base_build_progress = 0
	refinery_built = {}
	refinery_built[EARTH] = true
	refinery_building = {}
	refinery_progress = {}
	minerals = 350
	enemy_wave_timer = 0
	wave_started = false
	selected_planet = EARTH
	production = {}
	pending_count = {}
	last_known_intel = {}
	intel_recorded = {}
	laser_anim_time = 0
	combat_nebula_intensity = {}
	earth_industry_intensity = 0
	drone_speed_level = 0
	earth_rally = NO_RALLY
	victory = false
	defeated = false
	game_paused = false
	controls_overlay_open = false
	in_start_menu = false
	hud_save_notification_timer = 0
	save_feedback_timer = 0
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
		if shift_down() && drone_speed_level >= DRONE_SPEED_UPGRADE_MAX {
			queue_5_miners()
		} else {
			queue_unit(.MINING)
		}
	}
	if rl.IsKeyPressed(.C) {
		if shift_down() && drone_speed_level >= DRONE_SPEED_UPGRADE_MAX {
			queue_5_combat()
		} else {
			queue_unit(.COMBAT)
		}
	}
	// [N] queues +5 mining drones (Earth only).
	if !ctrl_down() && rl.IsKeyPressed(.N) {
		queue_5_miners()
	}
	// [X] queues +5 combat fighters (Earth only).
	if rl.IsKeyPressed(.X) {
		queue_5_combat()
	}
	// [U] buys the next drone build-speed upgrade level (Earth only).
	if rl.IsKeyPressed(.U) { purchase_drone_speed_upgrade() }
	// [B] builds a refinery on the selected liberated planet.
	if rl.IsKeyPressed(.B) {
		if selected_planet != EARTH && selected_planet != ENEMY_HOME && can_build_refinery(selected_planet) {
			start_refinery_construction(selected_planet)
		}
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
			open_controls_overlay()
			return
		}
		if mouse.x >= panel_x {
			// Sidebar presses start a potential drag; click vs box-select is
			// decided on release. World selection never sees sidebar input.
			inspector_drag_start = mouse
			inspector_drag_active = true
		} else {
			if planet := pick_planet(mouse); planet >= 0 {
				selected_planet = planet
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

handle_inspector_click :: proc(mouse: rl.Vector2, panel_x: f32) {
	// The two production buttons and base button are deliberately ordinary rectangles,
	// keeping the inspector usable even when raygui styles are unavailable.
	// Base construction and unit production exist only on Earth.
	if selected_planet == EARTH {
		if base_button_visible() && rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}) {
			start_base_construction()
			return
		}
		orders_y := f32(production_orders_y())
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			queue_unit(.MINING)
			return
		}
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			queue_unit(.COMBAT)
			return
		}
		if drone_speed_level < DRONE_SPEED_UPGRADE_MAX {
			if rl.CheckCollisionPointRec(mouse, drone_speed_button_rect(panel_x)) {
				purchase_drone_speed_upgrade()
				return
			}
		} else {
			if rl.CheckCollisionPointRec(mouse, queue_5_miner_button_rect(panel_x)) {
				queue_5_miners()
				return
			}
			if rl.CheckCollisionPointRec(mouse, queue_5_combat_button_rect(panel_x)) {
				queue_5_combat()
				return
			}
		}
		// Clicking an occupied build-queue slot cancels that unit (refund included).
		for slot := 0; slot < queued_count(EARTH); slot += 1 {
			if rl.CheckCollisionPointRec(mouse, queue_slot_rect(panel_x, slot)) {
				cancel_queued_at(EARTH, slot)
				return
			}
		}
	} else if selected_planet >= 0 && selected_planet < PLANET_COUNT && selected_planet != ENEMY_HOME {
		if can_build_refinery(selected_planet) && rl.CheckCollisionPointRec(mouse, refinery_button_rect(panel_x)) {
			start_refinery_construction(selected_planet)
			return
		}
	}
	if click_unit_tiles(mouse, panel_x, .MINING) || click_unit_tiles(mouse, panel_x, .COMBAT) { return }
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

click_unit_tiles :: proc(mouse: rl.Vector2, panel_x: f32, kind: Unit_Type) -> bool {
	if ghost_view() { return false }
	ordinal := 0
	y := unit_tile_y(kind)
	for i := 0; i < unit_count; i += 1 {
		if !unit_in_roster(i, kind) { continue }
		if rl.CheckCollisionPointRec(mouse, unit_tile_rect(panel_x, y, ordinal)) {
			if !ctrl_down() { clear_selection(); selected_units[i] = true } else { selected_units[i] = !selected_units[i] }
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
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && (u.state == .IDLE || u.state == .MINING) {
			if constructing_miners(planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.progress = 0
			}
		}
	}
}

// A planet can be mined once it is liberated and has an operational refinery.
planet_can_mine :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT { return false }
	return planet_liberated(planet) && refinery_built[planet]
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

// Pull available Earth mining drones into the build site until n are assigned.
resume_constructing_miners :: proc(p: int) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .CONSTRUCTING && u.target_planet == p {
			u.state = .MINING
			u.progress = 0
		}
	}
}

unit_cost :: proc(kind: Unit_Type) -> int {
	if kind == .COMBAT { return 125 }
	return 50
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
purchase_drone_speed_upgrade :: proc() -> bool {
	if selected_planet != EARTH { return false }
	if drone_speed_level >= DRONE_SPEED_UPGRADE_MAX || minerals < DRONE_SPEED_UPGRADE_COST { return false }
	minerals -= DRONE_SPEED_UPGRADE_COST
	drone_speed_level += 1
	return true
}

queue_unit :: proc(kind: Unit_Type) {
	if selected_planet != EARTH { return } // All production happens at Earth command bases.
	cost := unit_cost(kind)
	if minerals < cost || queued_count(selected_planet) >= base_counts[selected_planet] * 5 { return }
	minerals -= cost
	for i := 0; i < base_counts[selected_planet]; i += 1 {
		if !production[selected_planet][i].active {
			production[selected_planet][i] = Production{kind = kind, active = true, progress = 0}
			return
		}
	}
	pending[selected_planet][pending_count[selected_planet]] = kind
	pending_count[selected_planet] += 1
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

queue_5_miners :: proc() {
	queue_units(.MINING, 5)
}

queue_5_combat :: proc() {
	queue_units(.COMBAT, 5)
}

// Screen rect of the drone build-speed upgrade button. Shared by the
// render and the click hitbox so they cannot drift apart.
drone_speed_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + UPGRADE_DY), PANEL_CONTENT_W, UPGRADE_H}
}

// Screen rects for the +5 batch build buttons that replace the upgrade button at speed level 5.
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

// Screen rect of build-queue slot `slot` (0 = queue head: active production
// lines in base order, then pending items). Shared by the queue rendering and
// the cancel-click hitboxes so they cannot drift apart.
queue_slot_rect :: proc(panel_x: f32, slot: int) -> rl.Rectangle {
	queue_y := f32(production_orders_y() + QUEUE_DY)
	row := slot / MAX_BASES
	column := slot % MAX_BASES
	return rl.Rectangle{panel_x + PANEL_PAD_X + f32(column * GRID_PITCH), queue_y + QUEUE_LABEL_GAP + f32(row * GRID_PITCH), SLOT_SIZE, SLOT_SIZE}
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

// ESC handler: cancels the most recently queued unit — the tail of pending,
// else the newest active production line — with a full refund.
cancel_last_queued :: proc() -> bool {
	if queued_count(EARTH) == 0 { return false }
	return cancel_queued_at(EARTH, queued_count(EARTH) - 1)
}

update_production :: proc(dt: f32) {
	if base_build_planet >= 0 {
		// The build clock only runs with a full crew; deposits auto-fill it.
		if constructing_miners(base_build_planet) >= BASE_CONSTRUCT_MINERS {
			base_build_progress += dt
		}
		if base_build_progress >= BASE_CONSTRUCT_TIME {
			p := base_build_planet
			base_counts[p] += 1
			resume_constructing_miners(p)
			base_build_planet = -1
			base_build_progress = 0
			// The new base's production line picks up waiting queue items at
			// once, without a new unit being queued.
			fill_production_lines(p)
		}
	}
	for p in 0..<PLANET_COUNT {
		if refinery_building[p] {
			if constructing_miners(p) >= REFINERY_CONSTRUCT_MINERS {
				refinery_progress[p] += dt
			}
			if refinery_progress[p] >= REFINERY_BUILD_TIME {
				refinery_progress[p] = 0
				refinery_building[p] = false
				refinery_built[p] = true
				resume_constructing_miners(p)
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
	pos.x += math.cos(angle) * (planets[planet].radius + 1.2)
	pos.y += 0.5
	pos.z += math.sin(angle) * (planets[planet].radius + 1.2)
	state := Unit_State.TRANSIT
	target_planet := planet
	if kind == .COMBAT { state = .GUARDING }
	if kind == .MINING { state = .MINING }
	// Earth's rally point: newly produced units auto-dispatch to the rally world.
	if planet == EARTH && earth_rally != NO_RALLY {
		target_planet = earth_rally
		state = .TRANSIT
	}
	affiliation := planet
	if kind == .MINING || target_planet != planet { affiliation = target_planet }
	units[unit_count] = Unit{kind = kind, state = state, position = pos, home_planet = planet, affiliation = affiliation, target_planet = target_planet, orbit_angle = angle}
	unit_count += 1
}

// Enemy waves: every 3 minutes (first at the 3-minute mark) a single wave
// lifts off from the enemy HQ (the old Neptune orbit) — but only while the
// player actively mines WAVE_MIN_MINING_PLANETS (2) or more worlds. The wave
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
// .MINING). Dispatched scouts or drones pinned in orbit don't count — invasion
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
	// The wave clock only advances while the player mines 2+ worlds, so a
	// smaller footprint draws no retaliation at all.
	if mined_planet_count() >= WAVE_MIN_MINING_PLANETS {
		enemy_wave_timer += dt
		interval := f32(WAVE_FIRST_DELAY)
		if wave_started { interval = f32(WAVE_INTERVAL) }
		if enemy_wave_timer >= interval {
			launch_attack_wave()
		}
	}
	for p in 0..<SECTOR_COUNT { update_planet_combat(dt, p) }
}

// One attack cycle: a single wave of attack_wave_size() fighters. While the
// player presses an assault on a weakened HQ the wave musters there as
// guarding defenders instead; otherwise it sorties against the liberated
// planet closest to the enemy HQ. A destroyed HQ launches nothing, ever.
launch_attack_wave :: proc() {
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

update_planet_combat :: proc(dt: f32, p: int) {
	players, enemies := planet_combatants(p)
	if players > 0 && enemies > 0 {
		combat_timer[p] += dt
		for combat_timer[p] >= COMBAT_TICK {
			combat_timer[p] -= COMBAT_TICK
			if !kill_fighter(p, false) { break }
			rem_players, _ := planet_combatants(p)
			if rem_players == 0 {
				combat_vision_timer[p] = COMBAT_VISION_LINGER
			}
			if !kill_fighter(p, true) { break }
		}
	} else if enemies > 0 {
		combat_timer[p] = 0
		miner_timer[p] += dt
		for miner_timer[p] >= COMBAT_TICK {
			miner_timer[p] -= COMBAT_TICK
			if !kill_player_miner(p) { break }
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
	} else if players > 0 {
		combat_timer[p] = 0
		// Occupation cleanup: with the garrison fighters gone, player fighters
		// sweep the enemy mining drones, then bring down the enemy base.
		if enemy_miner_count(p) > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= COMBAT_TICK {
				miner_timer[p] -= COMBAT_TICK
				if !kill_enemy_miner(p) { break }
			}
		} else if enemy_base_hp[p] > 0 {
			base_timer[p] += dt
			for base_timer[p] >= COMBAT_TICK {
				base_timer[p] -= COMBAT_TICK
				enemy_base_hp[p] = max(enemy_base_hp[p] - players, 0)
				if enemy_base_hp[p] == 0 { break }
			}
		}
	} else {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
	}
}

// Attack wave size: (liberated planets - 1) * WAVE_FIGHTERS_PER_LIBERATED
// fighters (3 liberated worlds send 30). Earth starts liberated, so the
// result is 0 until a second world falls — the wave musters nothing.
attack_wave_size :: proc() -> int {
	return (liberated_planet_count() - 1) * WAVE_FIGHTERS_PER_LIBERATED
}

// Liberated worlds (planets only — the HQ sector is not a planet).
liberated_planet_count :: proc() -> int {
	count := 0
	for p in 0..<PLANET_COUNT { if planet_liberated(p) { count += 1 } }
	return count
}

// The liberated planet closest to the enemy HQ — the wave's fixed target.
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
	// Every wave lifts off from the enemy HQ (the old Neptune orbit) — no
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
	if enemies > 0 && (has_player_miners || (s == EARTH && base_counts[s] > 0)) { return true }
	if players > 0 && (has_enemy_miners || enemy_base_hp[s] > 0) { return true }
	return false
}

// Shift-left removal keeps unit indices stable, so is_effective_miner ranks and
// selection flags stay consistent for the survivors.
remove_unit_at :: proc(index: int) {
	for i := index; i < unit_count - 1; i += 1 {
		units[i] = units[i + 1]
		selected_units[i] = selected_units[i + 1]
	}
	unit_count -= 1
}

// Right-click on a planet is disambiguated by selection: with units selected
// it is a move order (the Earth rally point is left untouched); with nothing
// selected and Earth as the selected planet it (re)sets the Earth rally point
// — right-clicking Earth itself clears the rally back to 0.
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
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT {
			update_combat(u, dt)
		} else {
			update_miner(u, i, dt)
		}
	}
}

// Minerals delivered per mining cycle at a planet. The inner planets
// (Mercury, Venus, Earth, Mars) pay the standard 10; the gas giants and
// beyond pay 25 — the richer prize for pushing outward. (No Earth penalty.)
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

// Per-planet hard cap on earning miners: only the first planet_mining_cap(p)
// player miners targeting planet p (by unit index) deposit minerals; extras
// still mine and deplete the planet but pay out 0. Constructing miners hold
// no slot, so the cap counts active miners only.
// ponytail: index-order cap, revisit if a weighted split is wanted
is_effective_miner :: proc(index: int) -> bool {
	if units[index].kind != .MINING || units[index].enemy { return false }
	p := units[index].target_planet
	if !planet_can_mine(p) { return false }
	rank := 0
	for j := 0; j < index; j += 1 {
		u := &units[j]
		if u.kind == .MINING && !u.enemy && u.target_planet == p && u.state != .CONSTRUCTING { rank += 1 }
	}
	return rank < planet_mining_cap(p)
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
	round_trip := 2.0 * distance(planets[planet].position, planets[EARTH].position)
	travel_time := round_trip / MINING_TRANSIT_SPEED
	cycle_time := MINING_DURATION + DEPOSIT_DURATION + travel_time
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
		round_trip := 2.0 * distance(planets[p].position, planets[EARTH].position)
		travel_time := round_trip / MINING_TRANSIT_SPEED
		cycle_time := MINING_DURATION + DEPOSIT_DURATION + travel_time
		total += f32(counts[p]) * f32(mining_rate(p)) / cycle_time
	}
	return total
}

update_combat :: proc(u: ^Unit, dt: f32) {
	if u.state == .TRANSIT {
		target := sector_pos(u.target_planet)
		travel(u, target, COMBAT_TRANSIT_SPEED * dt)
		if distance(u.position, target) <= sector_radius(u.target_planet) + 1.4 {
			u.state = .GUARDING
			u.orbit_angle = 0
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
			if !u.enemy && refinery_building[u.target_planet] && constructing_miners(u.target_planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.progress = 0
			} else if planet_can_mine(u.target_planet) {
				u.state = .MINING
				u.progress = 0
			} else {
				// Occupied or unrefined planet: hold in orbit until combat drones liberate it and refinery is built.
				// progress doubles as the scout survival clock (kill_player_miner).
				u.state = .IDLE
				u.progress = 0
			}
		}
	case .MINING:
		u.progress += dt
		if u.progress >= MINING_DURATION {
			u.progress = 0
			u.state = .RETURNING
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
			// A queued Earth base soaks up returning miners: after the payout
			// they join the build crew instead of transiting back out. Earth-
			// assigned drones join first; a foreign-route miner only joins once
			// no Earth-assigned miner remains available, so its route is starved last.
			if base_build_planet == EARTH && !u.enemy && constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
				if u.target_planet == EARTH || u.affiliation == EARTH || !earth_assigned_miner_available() {
					u.state = .CONSTRUCTING
					u.target_planet = EARTH
					u.affiliation = EARTH
				}
			}
		}
	case .IDLE:
		// Held at an occupied or unrefined planet: join refinery construction if building and crew needed,
		// or resume mining once it can be mined.
		// Otherwise the hold time feeds the scout survival clock.
		if !u.enemy && refinery_building[u.target_planet] && constructing_miners(u.target_planet) < REFINERY_CONSTRUCT_MINERS {
			u.state = .CONSTRUCTING
			u.progress = 0
		} else if planet_can_mine(u.target_planet) {
			u.state = .MINING
			u.progress = 0
		} else {
			u.progress += dt
		}
	case .GUARDING, .CONSTRUCTING:
		// Idle miners keep their creation planet as their affiliation.
		// Constructing miners are parked at the build site; update_production
		// resumes them when the base or refinery completes.
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

draw_world :: proc() {
	viewport_w := rl.GetScreenWidth() - SCREEN_PANEL_WIDTH
	// Stars and combat nebulae project to screen space before the 3D pass,
	// so they sit in the background behind every planet and fortress.
	draw_starfield()
	draw_combat_nebulae()
	rl.BeginMode3D(camera)
	for p in 0..<PLANET_COUNT {
		planet := planets[p]
		lit := has_vision(p)
		surface := planet.color
		if !lit {
			// Fog of war: planets the player has no presence at render shadowed.
			surface = rl.Color{58, 62, 74, 255}
		}
		if planet_visuals_ready {
			// Textured, slowly spinning sphere; fogged worlds tint grey.
			tint := rl.WHITE
			if !lit { tint = rl.Color{110, 116, 130, 255} }
			rl.DrawModelEx(planet_models[p], planet.position, {0, 1, 0}, planet_spin[p] * 57.29578, {1, 1, 1}, tint)
		} else {
			rl.DrawSphere(planet.position, planet.radius, surface)
		}
		// Atmosphere shell: faint planet-tinted halo for depth.
		atmo := rl.Color{planet.color.r, planet.color.g, planet.color.b, 255}
		if !lit { atmo = rl.Color{70, 76, 90, 255} }
		rl.DrawSphereEx(planet.position, planet.radius * 1.09, 12, 24, rl.Fade(atmo, 0.16))
		// Sun glint: small bright dot toward the fixed light direction.
		glint_dir := rl.Vector3Normalize({-0.45, 0.75, -0.35})
		glint_pos := planet.position + glint_dir * (planet.radius * 0.82)
		rl.DrawSphereEx(glint_pos, planet.radius * 0.10, 6, 8, rl.Color{255, 255, 255, 70})
		// Drone orbit path: faint ring showing the guard orbit.
		rl.DrawCircle3D(planet.position + {0, 1.0, 0}, planet.radius + 1.5, {0, 1, 0}, 90, rl.Fade(atmo, 0.30))
		// Saturn's rings: two tilted bands.
		if p == SATURN {
			ring_col := rl.Color{225, 205, 155, 255}
			if !lit { ring_col = rl.Color{70, 76, 90, 255} }
			rl.DrawCircle3D(planet.position, planet.radius * 1.55, {0.35, 1, 0.15}, 78, rl.Fade(ring_col, 0.55))
			rl.DrawCircle3D(planet.position, planet.radius * 1.95, {0.35, 1, 0.15}, 78, rl.Fade(ring_col, 0.30))
		}
		if p == selected_planet {
			pulse := 0.75 + 0.25 * math.sin(laser_anim_time * 3.0)
			// Concentric tactical rings with segmented arcs
			rl.DrawCircle3D(planet.position, planet.radius + 0.35, {0, 1, 0}, 90, rl.Fade(SCIFI_CYAN, pulse))
			rl.DrawCircle3D(planet.position, planet.radius + 0.70, {0, 1, 0}, 90, SCIFI_DIM)
			// Cardinal radial ticks
			for a in 0..<4 {
				ang := f32(a) * math.PI / 2.0 + laser_anim_time * 0.4
				p_in := planet.position + rl.Vector3{math.cos(ang) * (planet.radius + 0.35), 0, math.sin(ang) * (planet.radius + 0.35)}
				p_out := planet.position + rl.Vector3{math.cos(ang) * (planet.radius + 0.85), 0, math.sin(ang) * (planet.radius + 0.85)}
				rl.DrawLine3D(p_in, p_out, SCIFI_CYAN)
			}
		}
	}
	// The enemy HQ fortress at Neptune's old orbit: layered battlestation —
	// dark red hull (bright once scouted), a dead grey husk once destroyed.
	hq_color := rl.Color{96, 34, 40, 255}
	hq_trim := rl.Color{150, 55, 62, 255}
	hq_glow := rl.Color{255, 90, 90, 255}
	if enemy_hq_destroyed() {
		hq_color = rl.Color{58, 60, 66, 255}
		hq_trim = rl.Color{80, 84, 94, 255}
		hq_glow = rl.Color{100, 105, 115, 255}
	} else if has_vision(ENEMY_HOME) {
		hq_color = rl.Color{205, 50, 58, 255}
		hq_trim = rl.Color{255, 120, 125, 255}
	}
	draw_hq_fortress(ENEMY_HQ_POSITION, hq_color, hq_trim, hq_glow)
	if selected_planet == ENEMY_HOME {
		rl.DrawCubeWiresV(ENEMY_HQ_POSITION, {4.6, 4.6, 4.6}, SCIFI_CYAN)
	}
	draw_rally_flag()

	// Drones render representationally per side and group: one drone
	// model per up-to-10 drones (ceil(count/10)), so a 5-drone wave in
	// transit shows as one drone and the 40-strong Jupiter garrison as
	// four. This applies in orbit / on-site and in transit (per target
	// planet). Rosters, tracking and selection still use the real unit list.
	sector_vis: [SECTOR_COUNT]bool
	for p in 0..<SECTOR_COUNT {
		sector_vis[p] = has_vision(p)
		world_sector_spots[p].pc = 0
		world_sector_spots[p].ec = 0
		world_sector_spots[p].pmc = 0
		world_sector_spots[p].emc = 0
	}

	transit_counts: [SECTOR_COUNT][2]int
	miner_transit_counts: [SECTOR_COUNT][2]int
	miner_return_counts: [SECTOR_COUNT][2]int

	// Pass 1: selection rings, stationed unit spots, and transit counts.
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if selected_units[i] {
			draw_selection_ring(u.position, 0.78)
		}
		if u.kind == .COMBAT {
			if u.state == .GUARDING {
				p := u.affiliation
				if p >= 0 && p < SECTOR_COUNT && sector_vis[p] {
					s := &world_sector_spots[p]
					if u.enemy {
						if s.ec < 256 { s.enemy_combat[s.ec] = u.position }
						s.ec += 1
					} else {
						if s.pc < 256 { s.player_combat[s.pc] = u.position }
						s.pc += 1
					}
				}
			} else if u.state == .TRANSIT {
				p := u.target_planet
				if p >= 0 && p < SECTOR_COUNT {
					transit_counts[p][u.enemy ? 1 : 0] += 1
				}
			}
		} else if u.kind == .MINING {
			p := miner_stationed_planet(u)
			if p >= 0 && p < SECTOR_COUNT && sector_vis[p] {
				s := &world_sector_spots[p]
				if u.enemy {
					if s.emc < 256 { s.enemy_miners[s.emc] = u.position }
					s.emc += 1
				} else {
					if s.pmc < 256 { s.player_miners[s.pmc] = u.position }
					s.pmc += 1
				}
			} else if u.target_planet >= 0 && u.target_planet < SECTOR_COUNT {
				side := u.enemy ? 1 : 0
				if u.state == .TRANSIT {
					miner_transit_counts[u.target_planet][side] += 1
				} else if u.state == .RETURNING {
					miner_return_counts[u.target_planet][side] += 1
				}
			}
		}
	}

	// Draw stationed drones and lasers per sector.
	for p in 0..<SECTOR_COUNT {
		if !sector_vis[p] { continue }
		s := &world_sector_spots[p]
		sp := sector_pos(p)
		for d in 0..<rep_count(s.pc) { draw_fighter_drone(s.player_combat[d], false, drone_heading(s.player_combat[d], sp)) }
		for d in 0..<rep_count(s.ec) { draw_fighter_drone(s.enemy_combat[d], true, drone_heading(s.enemy_combat[d], sp)) }
		draw_combat_lasers(p, s.player_combat[:], s.enemy_combat[:], s.pc, s.ec, s.player_miners[:], s.enemy_miners[:], s.pmc, s.emc)
		for d in 0..<rep_count(s.pmc) { draw_miner_drone(s.player_miners[d], false, drone_heading(s.player_miners[d], sp)) }
		for d in 0..<rep_count(s.emc) { draw_miner_drone(s.enemy_miners[d], true, drone_heading(s.enemy_miners[d], sp)) }
	}

	vis_combat: [SECTOR_COUNT][2]int
	vis_miner_tr: [SECTOR_COUNT][2]int
	vis_miner_ret: [SECTOR_COUNT][2]int
	drawn_combat: [SECTOR_COUNT][2]int
	drawn_miner_tr: [SECTOR_COUNT][2]int
	drawn_miner_ret: [SECTOR_COUNT][2]int

	for p in 0..<SECTOR_COUNT {
		for side in 0..<2 {
			if side == 1 && !sector_vis[p] { continue }
			vis_combat[p][side] = rep_count(transit_counts[p][side])
			vis_miner_tr[p][side] = rep_count(miner_transit_counts[p][side])
			vis_miner_ret[p][side] = rep_count(miner_return_counts[p][side])
		}
	}

	// Pass 2: draw transit units and transit lines in a single pass.
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.state == .TRANSIT {
			p := u.target_planet
			if p >= 0 && p < SECTOR_COUNT {
				side := u.enemy ? 1 : 0
				can_see := !u.enemy || sector_vis[p]
				if u.kind == .COMBAT {
					if can_see && drawn_combat[p][side] < vis_combat[p][side] {
						drawn_combat[p][side] += 1
						to := sector_pos(p)
						heading := to - u.position
						draw_fighter_drone(u.position, u.enemy, heading)
						if rl.Vector3Length(heading) > 0.001 {
							trail := u.position - rl.Vector3Normalize(heading) * 1.2
							rl.DrawLine3D(u.position, trail, rl.Fade(u.enemy ? rl.RED : SCIFI_CYAN, 0.6))
						}
					}
				} else if u.kind == .MINING {
					if can_see && drawn_miner_tr[p][side] < vis_miner_tr[p][side] {
						drawn_miner_tr[p][side] += 1
						to := sector_pos(p)
						heading := to - u.position
						draw_miner_drone(u.position, u.enemy, heading)
					}
				}
				if can_see {
					rl.DrawLine3D(u.position, sector_pos(p), rl.Color{0, 225, 255, 90})
				}
			}
		} else if u.state == .RETURNING {
			p := u.target_planet
			if p >= 0 && p < SECTOR_COUNT && u.kind == .MINING {
				side := u.enemy ? 1 : 0
				if (!u.enemy || sector_vis[p]) && drawn_miner_ret[p][side] < vis_miner_ret[p][side] {
					drawn_miner_ret[p][side] += 1
					to := planets[EARTH].position
					heading := to - u.position
					draw_miner_drone(u.position, u.enemy, heading)
				}
			}
		}
	}
	rl.EndMode3D()
	// Luminous industrial manufacturing lights on Earth when units are being created
	draw_earth_industry_lights()
	if in_start_menu {
		return
	}

	// Overlay labels and optical reticles anchored to 3D celestial positions.
	for p in 0..<PLANET_COUNT {
		pos := rl.GetWorldToScreen(planets[p].position, camera)
		if pos.x < f32(viewport_w) && pos.x > 0 && pos.y > 0 && pos.y < f32(rl.GetScreenHeight()) {
			label := planets[p].name
			if p == selected_planet {
				// Optical aim reticle over the selected planet
				draw_optical_reticle_2d(pos, planets[p].radius * 5.0, SCIFI_CYAN, label)
			} else {
				rl.DrawText(label, c.int(pos.x - 28 + 1), c.int(pos.y - planets[p].radius * 5 - 14 + 1), 14, rl.Color{0, 0, 0, 170})
				rl.DrawText(label, c.int(pos.x - 28), c.int(pos.y - planets[p].radius * 5 - 14), 14, SCIFI_TEXT)
			}
		}
	}
	// Enemy HQ label / reticle
	hq_screen := rl.GetWorldToScreen(ENEMY_HQ_POSITION, camera)
	if hq_screen.x < f32(viewport_w) && hq_screen.x > 0 && hq_screen.y > 0 && hq_screen.y < f32(rl.GetScreenHeight()) {
		hq_label: cstring = "ENEMY HQ"
		if enemy_hq_destroyed() { hq_label = "ENEMY HQ (DESTROYED)" }
		if selected_planet == ENEMY_HOME {
			draw_optical_reticle_2d(hq_screen, 28.0, SCIFI_RED, hq_label)
		} else {
			rl.DrawText(hq_label, c.int(hq_screen.x - 30), c.int(hq_screen.y - 26), 13, SCIFI_RED)
		}
	}

	// Top bar: minerals plus global MPS and drone speed upgrade level
	// Two-tier aerospace winged HUD dock (inspired by Star Fox Zero top-left UI)
	tl_dock_w: f32 = 400.0
	tl_dock_h: f32 = 50.0
	tl_rect := rl.Rectangle{f32(HUD_PAD), f32(HUD_PAD), tl_dock_w, tl_dock_h}
	draw_winged_panel_left(tl_rect, 6, 20, SCIFI_PANEL, SCIFI_CYAN)

	// Column 1: Minerals (static 104px column to fit up to 999999 minerals without shifting)
	col1_x: f32 = f32(HUD_PAD + 16)
	rl.DrawText("MINERALS", i32(col1_x), i32(HUD_PAD + 7), 10, SCIFI_MINT)
	min_val := rl.TextFormat("%d", minerals)
	rl.DrawText(min_val, i32(col1_x), i32(HUD_PAD + 20), 22, SCIFI_AMBER)

	// Divider 1 (completely static position)
	div1_x: f32 = col1_x + 104.0
	rl.DrawLineV({div1_x, HUD_PAD + 10}, {div1_x, HUD_PAD + 40}, SCIFI_DIM)
	draw_diamond(div1_x, HUD_PAD + 25, 2.5, SCIFI_CYAN)

	// Column 2: MPS (static 92px column)
	col2_x: f32 = div1_x + 16.0
	rl.DrawText("PRODUCTION", i32(col2_x), i32(HUD_PAD + 7), 10, SCIFI_MUTED)
	mps_val := rl.TextFormat("+%.1f/s", global_mps())
	rl.DrawText(mps_val, i32(col2_x), i32(HUD_PAD + 22), 17, SCIFI_CYAN)

	// Divider 2 (completely static position)
	div2_x: f32 = col2_x + 92.0
	rl.DrawLineV({div2_x, HUD_PAD + 10}, {div2_x, HUD_PAD + 40}, SCIFI_DIM)
	draw_diamond(div2_x, HUD_PAD + 25, 2.5, SCIFI_CYAN)

	// Column 3: Drone Speed (completely static position)
	col3_x: f32 = div2_x + 16.0
	rl.DrawText("DRONE SPEED", i32(col3_x), i32(HUD_PAD + 7), 10, SCIFI_MUTED)
	speed_val := rl.TextFormat("LVL %d/%d", drone_speed_level, DRONE_SPEED_UPGRADE_MAX)
	rl.DrawText(speed_val, i32(col3_x), i32(HUD_PAD + 24), 11, SCIFI_MINT)
	draw_segmented_meter({col3_x + 58, HUD_PAD + 24, 48, 12}, f32(drone_speed_level) / f32(DRONE_SPEED_UPGRADE_MAX), 5, SCIFI_MINT, SCIFI_DIM)

	// Top right of viewport: telemetry dock (FPS, altitude, zoom)
	// Symmetrical aerospace winged HUD dock (inspired by Star Fox Zero top-right UI)
	tr_dock_w: f32 = 230.0
	tr_dock_h: f32 = 50.0
	tr_x := f32(viewport_w) - f32(HUD_PAD) - tr_dock_w
	tr_rect := rl.Rectangle{tr_x, HUD_PAD, tr_dock_w, tr_dock_h}
	draw_winged_panel_right(tr_rect, 6, 20, SCIFI_PANEL, SCIFI_CYAN)

	// Fighter vector glyph icon (Arwing-style silhouette)
	draw_fighter_vector_icon({tr_x + 24, HUD_PAD + 25}, 10.0, SCIFI_MINT)

	// Telemetry readouts (altitude and zoom)
	telemetry_cam := rl.TextFormat("ALT %.0f   ZOOM %d%%", camera.position.y, zoom_percent())
	rl.DrawText(telemetry_cam, i32(tr_x + 44), i32(HUD_PAD + 20), 13, SCIFI_CYAN)

	// Divider before FPS
	div_tr_x := tr_x + tr_dock_w - 60.0
	rl.DrawLineV({div_tr_x, HUD_PAD + 10}, {div_tr_x, HUD_PAD + 40}, SCIFI_DIM)
	draw_diamond(div_tr_x, HUD_PAD + 25, 2.5, SCIFI_CYAN)

	fps_str := rl.TextFormat("%d FPS", rl.GetFPS())
	rl.DrawText(fps_str, i32(div_tr_x + 10), i32(HUD_PAD + 20), 12, SCIFI_MINT)

	// Save notification chip (if active)
	if hud_save_notification_timer > 0 {
		saved_lbl: cstring = "GAME SAVED"
		saved_w := f32(rl.MeasureText(saved_lbl, 11))
		saved_x := tr_x - saved_w - 20
		draw_chamfered_panel({saved_x - 8, HUD_PAD + 12, saved_w + 16, 26}, 4, rl.Color{30, 20, 10, 240}, SCIFI_AMBER_DIM)
		rl.DrawText(saved_lbl, i32(saved_x), i32(HUD_PAD + 18), 11, SCIFI_AMBER)
	}

	// Bottom: standalone Controls button
	draw_button(controls_button_rect(), "Controls", SCIFI_PANEL_SOLID, true)

	draw_squad_hud()
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

	// Header banner: styled like the active glowing 'SOLAR' card from Star Fox Zero reference
	header_box := rl.Rectangle{x + PANEL_PAD_X, 16, PANEL_CONTENT_W, 38}
	is_enemy := selected_planet == ENEMY_HOME
	card_glow := is_enemy ? SCIFI_RED : SCIFI_CYAN
	card_bracket := is_enemy ? SCIFI_RED : SCIFI_MINT

	// Luminous outer neon bloom
	rl.DrawRectangleLinesEx({header_box.x - 2, header_box.y - 2, header_box.width + 4, header_box.height + 4}, 1, rl.Fade(card_glow, 0.45))
	draw_chamfered_panel(header_box, 6, SCIFI_PANEL_SOLID, card_glow)
	draw_corner_brackets(header_box, 2, 7, card_bracket)

	if is_enemy {
		hq_title: cstring = "ENEMY CITADEL"
		if enemy_hq_destroyed() { hq_title = "CITADEL SILENCED (DEAD)" }
		rl.DrawText(hq_title, c.int(x + PANEL_PAD_X + 14), c.int(header_box.y + 11), 17, SCIFI_RED)
	} else {
		// Celestial sphere preview disc with concentric reticle arc
		planet_pos := rl.Vector2{x + PANEL_PAD_X + 18, header_box.y + 19}
		rl.DrawCircleV(planet_pos, 8, planets[selected_planet].color)
		rl.DrawCircleLines(c.int(planet_pos.x), c.int(planet_pos.y), 12, rl.Fade(SCIFI_CYAN, 0.7))
		rl.DrawLineV({planet_pos.x - 14, planet_pos.y}, {planet_pos.x - 10, planet_pos.y}, SCIFI_MINT)
		rl.DrawLineV({planet_pos.x + 10, planet_pos.y}, {planet_pos.x + 14, planet_pos.y}, SCIFI_MINT)

		title_x := x + PANEL_PAD_X + 38
		rl.DrawText(planets[selected_planet].name, c.int(title_x), c.int(header_box.y + 11), 17, SCIFI_TEXT)

		if selected_planet == EARTH || has_vision(selected_planet) || intel_recorded[selected_planet] {
			mps_text := rl.TextFormat("▲▲▲ %.1f MPS", planet_mps(selected_planet))
			mps_w := f32(rl.MeasureText(mps_text, 11))
			pill := rl.Rectangle{x + PANEL_PAD_X + PANEL_CONTENT_W - mps_w - 16, header_box.y + 9, mps_w + 12, 20}
			draw_chamfered_panel(pill, 3, rl.Color{28, 20, 10, 240}, SCIFI_AMBER_DIM)
			rl.DrawText(mps_text, c.int(pill.x + 6), c.int(pill.y + 5), 11, SCIFI_AMBER)
		} else {
			unscouted: cstring = "▲▲▲ DARK"
			uw := f32(rl.MeasureText(unscouted, 11))
			pill := rl.Rectangle{x + PANEL_PAD_X + PANEL_CONTENT_W - uw - 16, header_box.y + 9, uw + 12, 20}
			draw_chamfered_panel(pill, 3, rl.Color{16, 20, 24, 240}, SCIFI_DIM)
			rl.DrawText(unscouted, c.int(pill.x + 6), c.int(pill.y + 5), 11, SCIFI_MUTED)
		}
	}

	// Connecting circuit bus line down from Header Card to next section
	circuit_x := x + PANEL_PAD_X + 18
	rl.DrawLineV({circuit_x, header_box.y + header_box.height}, {circuit_x, header_box.y + header_box.height + 12}, rl.Fade(SCIFI_CYAN, 0.45))
	rl.DrawCircleV({circuit_x, header_box.y + header_box.height + 12}, 2.0, SCIFI_MINT)

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
	rl.DrawText("BASES", i32(x + PANEL_PAD_X), BASES_Y + 3, 11, SCIFI_CYAN)
	for pip := 0; pip < MAX_BASES; pip += 1 {
		pip_color := SCIFI_PANEL_SOLID
		pip_border := SCIFI_DIM
		if pip < base_counts[EARTH] { pip_color = rl.Color{0, 65, 85, 255}; pip_border = SCIFI_CYAN }
		pip_rect := rl.Rectangle{x + PANEL_PAD_X + PIPS_OFF + f32(pip * GRID_PITCH), BASES_Y - 1, SLOT_SIZE, SLOT_SIZE}
		draw_chamfered_panel(pip_rect, 3, pip_color, pip_border)
		if pip < base_counts[EARTH] {
			draw_corner_brackets(pip_rect, 1, 3, SCIFI_CYAN)
			rl.DrawRectangle(i32(pip_rect.x + 5), i32(pip_rect.y + 5), 8, 8, SCIFI_CYAN)
		}
	}

	if base_button_visible() {
		base_button := rl.Rectangle{x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}
		if base_build_planet == EARTH {
			draw_chamfered_panel(base_button, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			draw_corner_brackets(base_button, 2, 6, SCIFI_CYAN)
			if constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
				rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", constructing_miners(EARTH), BASE_CONSTRUCT_MINERS), i32(x + PANEL_PAD_X + CARD_INSET), SECTION_TOP + 12, 11, SCIFI_CYAN)
			} else {
				rl.DrawText(rl.TextFormat("COMMAND BASE  %3.1fs", BASE_CONSTRUCT_TIME - base_build_progress), i32(x + PANEL_PAD_X + CARD_INSET), SECTION_TOP + 11, 13, SCIFI_CYAN)
			}
			// Construction progress runs in a segmented bar just below the button.
			draw_progress({x + PANEL_PAD_X, BASE_PROGRESS_Y, PANEL_CONTENT_W, BAR_H}, base_build_progress / BASE_CONSTRUCT_TIME, SCIFI_CYAN)
		} else {
			can_build_base := minerals >= BASE_COST && base_counts[EARTH] < MAX_BASES && base_build_planet < 0 && planet_liberated(EARTH)
			draw_button(base_button, "Command Base (500)", SCIFI_PANEL_SOLID, can_build_base)
		}
	}

	prod_title_y := production_title_y()
	prod_first_y := production_first_y()
	draw_section_header(x + PANEL_PAD_X, f32(prod_title_y), PANEL_CONTENT_W, "PRODUCTION MATRIX", SCIFI_CYAN)
	for b := 0; b < base_counts[EARTH]; b += 1 {
		line := production[EARTH][b]
		y := f32(prod_first_y + b * PROD_PITCH)
		if line.active {
			name := "MINING DRONE"
			total := drone_build_time(line.kind)
			if line.kind == .COMBAT { name = "COMBAT DRONE" }
			rl.DrawText(rl.TextFormat("BASE %d  %s", b + 1, name), i32(x + PANEL_PAD_X), i32(y), 12, SCIFI_TEXT)
			draw_progress({x + PANEL_PAD_X, y + PROD_BAR_DY, PROD_BAR_W, BAR_H}, line.progress / total, SCIFI_CYAN)
		} else {
			rl.DrawText(rl.TextFormat("BASE %d  STANDBY", b + 1), i32(x + PANEL_PAD_X), i32(y), 12, SCIFI_MUTED)
		}
	}

	orders_y := production_orders_y()
	draw_section_header(x + PANEL_PAD_X, f32(orders_y - 23), PANEL_CONTENT_W, "FLEET REQUISITION", SCIFI_AMBER)
	queue_not_full := queued_count(EARTH) < base_counts[EARTH] * 5
	can_build_miner := minerals >= unit_cost(.MINING) && queue_not_full
	can_build_combat := minerals >= unit_cost(.COMBAT) && queue_not_full
	draw_button({x + PANEL_PAD_X, f32(orders_y), BUILD_BTN_W, BUILD_BTN_H}, "[M] MINER  (50)", SCIFI_PANEL_SOLID, can_build_miner)
	draw_button({x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(orders_y), BUILD_BTN_W, BUILD_BTN_H}, "[C] COMBAT (125)", SCIFI_PANEL_SOLID, can_build_combat)

	if drone_speed_level >= DRONE_SPEED_UPGRADE_MAX {
		draw_button(queue_5_miner_button_rect(x), "[N] +5 MINERS (250)", SCIFI_PANEL_SOLID, can_build_miner)
		draw_button(queue_5_combat_button_rect(x), "[X] +5 COMBAT (625)", SCIFI_PANEL_SOLID, can_build_combat)
	} else {
		can_upgrade_speed := minerals >= DRONE_SPEED_UPGRADE_COST
		draw_button(drone_speed_button_rect(x), rl.TextFormat("[U] DRONE BUILD SPEED  LVL %d/%d (%d)", drone_speed_level, DRONE_SPEED_UPGRADE_MAX, DRONE_SPEED_UPGRADE_COST), SCIFI_PANEL_SOLID, can_upgrade_speed)
	}

	queue_y := production_orders_y() + QUEUE_DY
	queue_capacity := base_counts[EARTH] * MAX_BASES
	queue_total := queued_count(EARTH)
	draw_section_header(x + PANEL_PAD_X, f32(queue_y), PANEL_CONTENT_W, rl.TextFormat("QUEUE BUFFER (%d/%d)", queue_total, queue_capacity), SCIFI_CYAN)
	for slot := 0; slot < queue_capacity; slot += 1 {
		queued := slot < queue_total
		kind := Unit_Type.MINING
		if queued { kind = queue_kind_at(EARTH, slot) }
		draw_queue_slot(queue_slot_rect(x, slot), queued, kind)
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
		rl.DrawText(rl.TextFormat("FIGHTERS %d   INTEGRITY %d/%d", garrison, enemy_base_hp[ENEMY_HOME], ENEMY_HQ_BASE_HP), i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2 - 2, 11, SCIFI_TEXT)
		draw_progress({x + PANEL_PAD_X + CARD_INSET, CARD_LINE_2 + 13, PANEL_CONTENT_W - 2 * CARD_INSET, 6}, f32(enemy_base_hp[ENEMY_HOME]) / f32(ENEMY_HQ_BASE_HP), SCIFI_RED)
	} else {
		draw_status_card(card, SCIFI_STEEL)
		rl.DrawText("UNSCOUTED REACHES", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("DISPATCH COMBAT DRONES TO REVEAL", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	}
}

// Outpost planets host no player bases: show the mining forecast, the enemy
// stronghold status (mining is locked until it falls) and unit rosters only.
draw_outpost_inspector :: proc(x: f32) {
	card := rl.Rectangle{x + PANEL_PAD_X, OUTPOST_CARD_Y, PANEL_CONTENT_W, CARD_H}
	if has_vision(selected_planet) {
		stronghold_color := SCIFI_STEEL
		title: cstring = "UNSCOUTED SECTOR"
		status: cstring = "STATUS UNKNOWN: DISPATCH SCOUT"
		if planet_liberated(selected_planet) {
			if refinery_built[selected_planet] {
				stronghold_color = SCIFI_MINT
				title = "SECTOR LIBERATED"
				status = "REFINERY OPERATIONAL: EXTRACTION ACTIVE"
			} else if refinery_building[selected_planet] {
				stronghold_color = SCIFI_CYAN
				title = "SECTOR LIBERATED"
				status = "REFINERY UNDER CONSTRUCTION"
			} else {
				stronghold_color = SCIFI_AMBER
				title = "SECTOR LIBERATED"
				status = "REFINERY REQUIRED FOR MINING"
			}
		} else {
			stronghold_color = SCIFI_RED
			title = "ENEMY STRONGHOLD"
			_, garrison := planet_combatants(selected_planet)
			status = rl.TextFormat("%02d FIGHTERS  BASE %02d: HOSTILE OCCUPATION", garrison, enemy_base_hp[selected_planet])
		}
		draw_status_card(card, stronghold_color)
		rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, stronghold_color)
		rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	} else if intel_recorded[selected_planet] {
		card.height = CARD_H
		intel := last_known_intel[selected_planet]
		title: cstring = "ENEMY STRONGHOLD (STALE INTEL)"
		status := rl.TextFormat("%02d FIGHTERS  BASE %02d/%02d: PREVIOUS RECON", intel.fighters, intel.miners, GARRISON_BASE_HP[selected_planet])
		if intel.base_hp <= 0 {
			if refinery_built[selected_planet] {
				title = "LIBERATED (REFINERY ACTIVE)"
			} else {
				title = "LIBERATED (NO REFINERY)"
			}
		}
		draw_status_card(card, SCIFI_AMBER)
		rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_AMBER)
		rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_MUTED)
	} else {
		draw_status_card(card, SCIFI_STEEL)
		rl.DrawText("UNSCOUTED SECTOR", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("STATUS UNKNOWN: DISPATCH SCOUT", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	}

	if planet_liberated(selected_planet) {
		btn := refinery_button_rect(x)
		if refinery_building[selected_planet] {
			draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			draw_corner_brackets(btn, 2, 6, SCIFI_CYAN)
			if constructing_miners(selected_planet) < REFINERY_CONSTRUCT_MINERS {
				rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", constructing_miners(selected_planet), REFINERY_CONSTRUCT_MINERS), i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 12), 11, SCIFI_CYAN)
			} else {
				remaining := REFINERY_BUILD_TIME - refinery_progress[selected_planet]
				rl.DrawText(rl.TextFormat("REFINERY  %3.1fs", remaining), i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 11), 13, SCIFI_CYAN)
			}
			draw_progress({x + PANEL_PAD_X, btn.y + btn.height + 4, PANEL_CONTENT_W, BAR_H}, refinery_progress[selected_planet] / REFINERY_BUILD_TIME, SCIFI_CYAN)
		} else if !refinery_built[selected_planet] {
			cost := refinery_cost(selected_planet)
			can_build := can_build_refinery(selected_planet)
			draw_button(btn, rl.TextFormat("Build Refinery (%d)", cost), SCIFI_PANEL_SOLID, can_build)
		} else {
			draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
			draw_corner_brackets(btn, 2, 6, SCIFI_MINT)
			rl.DrawText("REFINERY OPERATIONAL", i32(x + PANEL_PAD_X + CARD_INSET), i32(btn.y + 11), 13, SCIFI_MINT)
		}
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
// the production sections collapse up to SECTION_TOP to avoid an empty gap.
production_title_y :: proc() -> int {
	if selected_planet == EARTH && !base_button_visible() { return SECTION_TOP }
	return PROD_TITLE_Y
}

production_first_y :: proc() -> int {
	return production_title_y() + (PROD_FIRST_Y - PROD_TITLE_Y)
}

production_orders_y :: proc() -> int {
	base_y := ORDERS_BASE_Y
	if selected_planet == EARTH && !base_button_visible() { base_y -= BASE_COLLAPSE_Y }
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
	// Outpost inspectors have no base/production/queue sections, so rosters
	// sit at a fixed height; on Earth they flow below the build queue.
	y := ROSTER_BASE_Y
	if selected_planet == EARTH {
		y = production_orders_y() + ROSTER_BELOW_QUEUE + (base_counts[selected_planet] - 1) * GRID_PITCH
	} else if selected_planet != ENEMY_HOME && planet_liberated(selected_planet) {
		y = OUTPOST_LIBERATED_ROSTER_Y
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
	rl.DrawText(symbol, c.int(rect.x + 4), c.int(rect.y + 2), 11, accent)
	rl.DrawCircle(c.int(rect.x + rect.width - 4), c.int(rect.y + 4), 2, state_color(state))
}

// Layered enemy HQ battlestation: stacked hull, command tower, corner
// turrets with barrels, emissive window band and a pulsing beacon spire.
draw_hq_fortress :: proc(center: rl.Vector3, hull, trim, glow: rl.Color) {
	dark := rl.Color{u8(f32(hull.r) * 0.55), u8(f32(hull.g) * 0.55), u8(f32(hull.b) * 0.55), 255}
	rl.DrawCubeV(center, {3.6, 2.6, 3.6}, hull)
	rl.DrawCubeV(center + {0, -1.45, 0}, {2.6, 0.5, 2.6}, dark)
	rl.DrawCubeV(center + {0, 2.3, 0}, {1.7, 2.2, 1.7}, hull)
	rl.DrawCubeV(center + {0, 2.3, 0}, {1.85, 0.35, 1.85}, trim)
	// Emissive window band around the main hull.
	rl.DrawCubeV(center + {0, 0.4, 0}, {3.66, 0.20, 3.66}, glow)
	// Corner turrets with outward barrels.
	for sx in -1..=1 {
		for sz in -1..=1 {
			if sx == 0 || sz == 0 { continue }
			base := center + {f32(sx) * 1.9, 1.0, f32(sz) * 1.9}
			rl.DrawCubeV(base, {0.55, 0.55, 0.55}, dark)
			rl.DrawCubeV(base + {0, 0.45, 0}, {0.34, 0.34, 0.34}, trim)
			out := rl.Vector3Normalize({f32(sx), 0.15, f32(sz)})
			rl.DrawCylinderEx(base + {0, 0.5, 0}, base + {0, 0.5, 0} + out * 1.1, 0.09, 0.09, 6, dark)
		}
	}
	// Beacon spire with pulsing tip.
	rl.DrawCylinderEx(center + {0, 3.4, 0}, center + {0, 5.0, 0}, 0.12, 0.05, 6, trim)
	pulse := 0.6 + 0.4 * math.sin(laser_anim_time * 4.0)
	rl.DrawSphereEx(center + {0, 5.1, 0}, 0.22 * pulse + 0.12, 8, 12, rl.Fade(glow, 0.9))
	// Rotating radar sweep off the tower.
	sweep := laser_anim_time * 1.4
	sweep_dir := rl.Vector3{math.cos(sweep), 0, math.sin(sweep)}
	rl.DrawLine3D(center + {0, 3.1, 0}, center + {0, 3.1, 0} + sweep_dir * 2.6, rl.Fade(glow, 0.7))
}

// Orbit tangent used as a fighter's forward vector while guarding.
drone_heading :: proc(pos, center: rl.Vector3) -> rl.Vector3 {
	t := rl.Vector3{-(pos.z - center.z), 0, pos.x - center.x}
	if rl.Vector3Length(t) < 0.001 { return {1, 0, 0} }
	return rl.Vector3Normalize(t)
}

// Procedural drone models: baked once into GPU VRAM at startup and drawn via
// DrawModelEx (1 draw call per drone instead of dozens of immediate-mode calls).
add_triangle :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	v1, v2, v3: rl.Vector3, color: rl.Color,
) {
	e1 := v2 - v1
	e2 := v3 - v1
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(e1, e2))
	if rl.Vector3Length(n) < 0.001 { n = {0, 1, 0} }

	pts := [3]rl.Vector3{v1, v2, v3}
	for p in pts {
		append(verts, p.x, p.y, p.z)
		append(norms, n.x, n.y, n.z)
		append(cols, color.r, color.g, color.b, color.a)
	}
}

add_cylinder :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	start, end: rl.Vector3, r_start, r_end: f32, sides: int, color: rl.Color,
) {
	dir := end - start
	dist := rl.Vector3Length(dir)
	if dist < 0.0001 { return }
	d := dir / dist

	up := rl.Vector3{0, 1, 0}
	if math.abs(rl.Vector3DotProduct(d, up)) > 0.95 {
		up = {0, 0, 1}
	}
	u := rl.Vector3Normalize(rl.Vector3CrossProduct(d, up))
	v := rl.Vector3CrossProduct(d, u)

	n_sides := max(sides, 3)
	for i in 0..<n_sides {
		a1 := f32(i) * 2.0 * math.PI / f32(n_sides)
		a2 := f32(i + 1) * 2.0 * math.PI / f32(n_sides)

		c1, s1 := math.cos(a1), math.sin(a1)
		c2, s2 := math.cos(a2), math.sin(a2)

		n1 := u * c1 + v * s1
		n2 := u * c2 + v * s2

		b1 := start + n1 * r_start
		b2 := start + n2 * r_start
		t1 := end + n1 * r_end
		t2 := end + n2 * r_end

		// Side quad (2 triangles)
		append(verts, b1.x, b1.y, b1.z,  b2.x, b2.y, b2.z,  t1.x, t1.y, t1.z)
		append(norms, n1.x, n1.y, n1.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		append(verts, b2.x, b2.y, b2.z,  t2.x, t2.y, t2.z,  t1.x, t1.y, t1.z)
		append(norms, n2.x, n2.y, n2.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		// Start cap
		if r_start > 0 {
			append(verts, start.x, start.y, start.z,  b2.x, b2.y, b2.z,  b1.x, b1.y, b1.z)
			append(norms, -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}

		// End cap
		if r_end > 0 {
			append(verts, end.x, end.y, end.z,  t1.x, t1.y, t1.z,  t2.x, t2.y, t2.z)
			append(norms, d.x, d.y, d.z,  d.x, d.y, d.z,  d.x, d.y, d.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}
	}
}

add_sphere :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	center: rl.Vector3, radius: f32, rings, slices: int, color: rl.Color,
) {
	nRings := max(rings, 3)
	nSlices := max(slices, 3)

	for r in 0..<nRings {
		phi1 := f32(r) * math.PI / f32(nRings)
		phi2 := f32(r + 1) * math.PI / f32(nRings)

		y1 := math.cos(phi1)
		y2 := math.cos(phi2)
		r1 := math.sin(phi1)
		r2 := math.sin(phi2)

		for s in 0..<nSlices {
			th1 := f32(s) * 2.0 * math.PI / f32(nSlices)
			th2 := f32(s + 1) * 2.0 * math.PI / f32(nSlices)

			x11, z11 := r1 * math.cos(th1), r1 * math.sin(th1)
			x12, z12 := r1 * math.cos(th2), r1 * math.sin(th2)
			x21, z21 := r2 * math.cos(th1), r2 * math.sin(th1)
			x22, z22 := r2 * math.cos(th2), r2 * math.sin(th2)

			n00 := rl.Vector3{x11, y1, z11}
			n01 := rl.Vector3{x12, y1, z12}
			n10 := rl.Vector3{x21, y2, z21}
			n11 := rl.Vector3{x22, y2, z22}

			p00 := center + n00 * radius
			p01 := center + n01 * radius
			p10 := center + n10 * radius
			p11 := center + n11 * radius

			// Triangle 1
			append(verts, p00.x, p00.y, p00.z,  p10.x, p10.y, p10.z,  p01.x, p01.y, p01.z)
			append(norms, n00.x, n00.y, n00.z,  n10.x, n10.y, n10.z,  n01.x, n01.y, n01.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

			// Triangle 2
			append(verts, p01.x, p01.y, p01.z,  p10.x, p10.y, p10.z,  p11.x, p11.y, p11.z)
			append(norms, n01.x, n01.y, n01.z,  n10.x, n10.y, n10.z,  n11.x, n11.y, n11.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}
	}
}

make_mesh_from_arrays :: proc(vertices: []f32, normals: []f32, colors: []u8) -> rl.Mesh {
	mesh := rl.Mesh{}
	mesh.vertexCount = c.int(len(vertices) / 3)
	mesh.triangleCount = c.int(len(vertices) / 9)

	mesh.vertices = cast([^]f32)rl.MemAlloc(c.uint(len(vertices) * size_of(f32)))
	mem.copy(mesh.vertices, raw_data(vertices), len(vertices) * size_of(f32))

	mesh.normals = cast([^]f32)rl.MemAlloc(c.uint(len(normals) * size_of(f32)))
	mem.copy(mesh.normals, raw_data(normals), len(normals) * size_of(f32))

	mesh.colors = cast([^]u8)rl.MemAlloc(c.uint(len(colors) * size_of(u8)))
	mem.copy(mesh.colors, raw_data(colors), len(colors) * size_of(u8))

	mesh.texcoords = cast([^]f32)rl.MemAlloc(c.uint(int(mesh.vertexCount) * 2 * size_of(f32)))
	mem.zero(mesh.texcoords, int(mesh.vertexCount) * 2 * size_of(f32))

	rl.UploadMesh(&mesh, false)
	return mesh
}

build_miner_model :: proc(enemy: bool) -> rl.Model {
	verts := make([dynamic]f32)
	defer delete(verts)
	norms := make([dynamic]f32)
	defer delete(norms)
	cols  := make([dynamic]u8)
	defer delete(cols)

	hull_main:   rl.Color
	hull_plate:  rl.Color
	frame_dark:  rl.Color
	metal_trim:  rl.Color
	tank_mesh:   rl.Color
	light_glow:  rl.Color

	if enemy {
		hull_main  = rl.Color{160, 42, 48, 255}
		hull_plate = rl.Color{205, 68, 76, 255}
		frame_dark = rl.Color{36, 18, 22, 255}
		metal_trim = rl.Color{135, 120, 125, 255}
		tank_mesh  = rl.Color{55, 34, 38, 255}
		light_glow = SCIFI_RED
	} else {
		hull_main  = rl.Color{230, 155, 22, 255}
		hull_plate = rl.Color{255, 190, 40, 255}
		frame_dark = rl.Color{26, 28, 34, 255}
		metal_trim = rl.Color{145, 158, 172, 255}
		tank_mesh  = rl.Color{42, 48, 58, 255}
		light_glow = rl.Color{255, 215, 95, 255}
	}

	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pos := rl.Vector3{0, 0, 0}

	// 1. Central Heavy Flatbed Chassis
	deck_f := pos + h * 0.16 - up * 0.02
	deck_b := pos - h * 0.22 - up * 0.02
	add_cylinder(&verts, &norms, &cols, deck_b, deck_f, 0.22, 0.20, 6, frame_dark)
	add_cylinder(&verts, &norms, &cols, deck_b + up * 0.04, deck_f + up * 0.04, 0.18, 0.16, 6, hull_main)

	// 2. Giant Spherical Ore Tank (Mounted High at the Rear)
	tank_pos := pos - h * 0.14 + up * 0.24
	tank_r: f32 = 0.24
	add_sphere(&verts, &norms, &cols, tank_pos, tank_r, 8, 10, tank_mesh)

	s_signs := [2]f32{-1.0, 1.0}
	for s in s_signs {
		cradle_base := pos - h * 0.18 + side * (s * 0.16) + up * 0.04
		cradle_top  := tank_pos + side * (s * 0.18) + up * 0.04
		add_cylinder(&verts, &norms, &cols, cradle_base, cradle_top, 0.030, 0.020, 4, hull_main)
	}
	add_cylinder(&verts, &norms, &cols, pos - h * 0.22 + up * 0.04, tank_pos - h * 0.16 + up * 0.04, 0.035, 0.025, 4, hull_plate)

	// 3. Operator Cabin with Visor (Front-Left Deck)
	cab_pos := pos + h * 0.14 + up * 0.08 - side * 0.07
	add_cylinder(&verts, &norms, &cols, cab_pos - h * 0.08, cab_pos + h * 0.08, 0.09, 0.07, 5, hull_main)
	add_cylinder(&verts, &norms, &cols, cab_pos + h * 0.05, cab_pos + h * 0.09, 0.06, 0.045, 5, SCIFI_CYAN)

	// 4. Heavy Halogen Work Floodlight (Front-Right Deck)
	light_pos := pos + h * 0.22 + up * 0.06 + side * 0.08
	add_cylinder(&verts, &norms, &cols, light_pos - h * 0.04, light_pos, 0.040, 0.040, 4, frame_dark)
	add_sphere(&verts, &norms, &cols, light_pos + h * 0.015, 0.030, 4, 4, light_glow)

	// 5. Four Articulated Hydraulic Outrigger Legs (Spider Stabilizers)
	leg_offsets := [4][2]f32{ {0.12, 0.18}, {0.12, -0.18}, {-0.16, 0.20}, {-0.16, -0.20} }
	leg_targets := [4][2]f32{ {0.26, 0.36}, {0.26, -0.36}, {-0.28, 0.38}, {-0.28, -0.38} }

	for l in 0..<4 {
		hip  := pos + h * leg_offsets[l][0] + side * leg_offsets[l][1] - up * 0.02
		foot := pos + h * leg_targets[l][0] + side * leg_targets[l][1] - up * 0.28
		knee := (hip + foot) * 0.5 + up * 0.08 + side * (leg_targets[l][1] > 0 ? 0.06 : -0.06)

		add_cylinder(&verts, &norms, &cols, hip, knee, 0.036, 0.026, 4, hull_main)
		add_cylinder(&verts, &norms, &cols, knee, foot, 0.026, 0.018, 4, metal_trim)
		add_cylinder(&verts, &norms, &cols, foot, foot - up * 0.035, 0.032, 0.028, 4, frame_dark)
	}

	// 6. Ventral Excavation Drill / Rotary Cutter Tool
	drill_base := pos + h * 0.08 - up * 0.12
	drill_tip  := pos + h * 0.22 - up * 0.40
	add_cylinder(&verts, &norms, &cols, drill_base, drill_base - up * 0.06, 0.05, 0.05, 5, frame_dark)
	add_cylinder(&verts, &norms, &cols, drill_base - up * 0.05, drill_tip, 0.05, 0.012, 5, metal_trim)
	add_sphere(&verts, &norms, &cols, drill_tip, 0.032, 4, 4, light_glow)

	// 7. Twin Rear Hover / Transit Thrusters
	for s in s_signs {
		nozzle_f := pos - h * 0.22 + side * (s * 0.12) - up * 0.04
		nozzle_b := nozzle_f - h * 0.08
		add_cylinder(&verts, &norms, &cols, nozzle_f, nozzle_b, 0.045, 0.035, 4, frame_dark)
		add_sphere(&verts, &norms, &cols, nozzle_b - h * 0.02, 0.045, 4, 4, light_glow)
	}

	mesh := make_mesh_from_arrays(verts[:], norms[:], cols[:])
	return rl.LoadModelFromMesh(mesh)
}

build_fighter_model :: proc(enemy: bool) -> rl.Model {
	verts := make([dynamic]f32)
	defer delete(verts)
	norms := make([dynamic]f32)
	defer delete(norms)
	cols  := make([dynamic]u8)
	defer delete(cols)

	armor_main:  rl.Color
	armor_dark:  rl.Color
	armor_plate: rl.Color
	metal_trim:  rl.Color
	energy_glow: rl.Color
	energy_core: rl.Color

	if enemy {
		armor_main  = rl.Color{78, 28, 36, 255}
		armor_dark  = rl.Color{38, 14, 18, 255}
		armor_plate = rl.Color{125, 42, 52, 255}
		metal_trim  = rl.Color{160, 125, 130, 255}
		energy_glow = SCIFI_RED
		energy_core = rl.Color{255, 190, 140, 255}
	} else {
		armor_main  = rl.Color{28, 48, 76, 255}
		armor_dark  = rl.Color{16, 26, 42, 255}
		armor_plate = rl.Color{46, 82, 126, 255}
		metal_trim  = rl.Color{135, 165, 190, 255}
		energy_glow = SCIFI_CYAN
		energy_core = SCIFI_MINT
	}

	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pos := rl.Vector3{0, 0, 0}

	// 1. Central Core & Armored Dorsal Cowling
	core_f := pos + h * 0.18
	core_b := pos - h * 0.28
	add_cylinder(&verts, &norms, &cols, core_b, core_f, 0.20, 0.18, 6, armor_dark)

	hood_f := pos + h * 0.20 + up * 0.16
	hood_b := pos - h * 0.30 + up * 0.18
	add_cylinder(&verts, &norms, &cols, hood_b, hood_f, 0.15, 0.12, 5, armor_main)

	s_signs := [2]f32{-1.0, 1.0}
	for s_sign in s_signs {
		s_vec := side * s_sign
		sh_f := pos + h * 0.18 + up * 0.06 + s_vec * 0.24
		sh_b := pos - h * 0.26 + up * 0.08 + s_vec * 0.26
		sh_tip := pos + s_vec * 0.30 - up * 0.06

		add_triangle(&verts, &norms, &cols, hood_f, sh_f, hood_b, armor_plate)
		add_triangle(&verts, &norms, &cols, hood_b, sh_f, sh_tip, armor_main)
	}

	// 2. Central Circular Ocular Sensor (The "Eye")
	eye_pos := pos + h * 0.22
	add_cylinder(&verts, &norms, &cols, eye_pos, eye_pos + h * 0.04, 0.14, 0.13, 6, metal_trim)
	add_sphere(&verts, &norms, &cols, eye_pos + h * 0.045, 0.075, 6, 6, energy_glow)
	add_sphere(&verts, &norms, &cols, eye_pos + h * 0.070, 0.035, 4, 4, energy_core)

	// Forward chin sensor probe / needle
	probe_base := pos + h * 0.18 - up * 0.11
	probe_tip  := pos + h * 0.52 - up * 0.20
	add_cylinder(&verts, &norms, &cols, probe_base, probe_tip, 0.025, 0.008, 4, metal_trim)

	// 3. Ventral Stabilizer Mandibles / Struts
	for s_sign in s_signs {
		s_vec := side * s_sign
		strut_top := pos - h * 0.06 - up * 0.10 + s_vec * 0.14
		strut_tip := pos + h * 0.04 - up * 0.34 + s_vec * 0.18
		add_cylinder(&verts, &norms, &cols, strut_top, strut_tip, 0.030, 0.014, 4, metal_trim)
	}

	// 4. Outboard Twin Heavy Weapon Sponsons (Flanking Railguns)
	for s_sign in s_signs {
		s_vec := side * s_sign
		pod_pos := pos + s_vec * 0.40 - up * 0.02

		add_cylinder(&verts, &norms, &cols, pos + s_vec * 0.20, pod_pos, 0.032, 0.032, 4, armor_dark)
		add_cylinder(&verts, &norms, &cols, pod_pos - h * 0.20, pod_pos + h * 0.10, 0.068, 0.058, 5, armor_main)

		rail_len := f32(0.36)
		p_top_start := pod_pos + h * 0.08 + up * 0.040
		p_top_end   := p_top_start + h * rail_len
		add_cylinder(&verts, &norms, &cols, p_top_start, p_top_end, 0.022, 0.014, 4, metal_trim)

		p_bot_start := pod_pos + h * 0.08 - up * 0.040
		p_bot_end   := p_bot_start + h * rail_len
		add_cylinder(&verts, &norms, &cols, p_bot_start, p_bot_end, 0.022, 0.014, 4, metal_trim)

		add_cylinder(&verts, &norms, &cols, pod_pos + h * 0.07, pod_pos + h * 0.38, 0.014, 0.014, 4, energy_glow)
	}

	// 5. Rear Propulsion & Thruster Flare
	engine_pos := pos - h * 0.32
	add_cylinder(&verts, &norms, &cols, pos - h * 0.24, engine_pos, 0.12, 0.09, 6, armor_dark)
	add_cylinder(&verts, &norms, &cols, engine_pos, engine_pos - h * 0.04, 0.09, 0.07, 6, metal_trim)

	add_sphere(&verts, &norms, &cols, engine_pos - h * 0.05, 0.075, 4, 6, energy_glow)
	add_sphere(&verts, &norms, &cols, engine_pos - h * 0.03, 0.040, 4, 4, energy_core)

	mesh := make_mesh_from_arrays(verts[:], norms[:], cols[:])
	return rl.LoadModelFromMesh(mesh)
}

init_drone_visuals :: proc() {
	if drone_visuals_ready { return }
	drone_models[.PLAYER_MINER]   = build_miner_model(false)
	drone_models[.ENEMY_MINER]    = build_miner_model(true)
	drone_models[.PLAYER_FIGHTER] = build_fighter_model(false)
	drone_models[.ENEMY_FIGHTER]  = build_fighter_model(true)
	drone_visuals_ready = true
}

unload_drone_visuals :: proc() {
	if !drone_visuals_ready { return }
	for kind in Drone_Model_Kind {
		rl.UnloadModel(drone_models[kind])
	}
	drone_visuals_ready = false
}

draw_miner_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3 = {1, 0, 0}) {
	if !drone_visuals_ready {
		rl.DrawSphere(position, 0.35, enemy ? rl.RED : rl.ORANGE)
		return
	}
	h := heading
	if rl.Vector3Length(h) < 0.001 { h = {1, 0, 0} }
	h = rl.Vector3Normalize(h)

	bob := math.sin(laser_anim_time * 3.0 + position.x * 2.1 + position.z * 1.7) * 0.04
	pos := position + {0, bob, 0}

	model := enemy ? drone_models[.ENEMY_MINER] : drone_models[.PLAYER_MINER]

	v_from := rl.Vector3{1, 0, 0}
	dot := rl.Vector3DotProduct(v_from, h)
	axis := rl.Vector3{0, 1, 0}
	angle: f32 = 0.0
	if dot < -0.9999 {
		axis = {0, 1, 0}
		angle = 180.0
	} else if dot < 0.9999 {
		axis = rl.Vector3Normalize(rl.Vector3CrossProduct(v_from, h))
		angle = math.acos(math.clamp(dot, -1.0, 1.0)) * (180.0 / math.PI)
	}

	rl.DrawModelEx(model, pos, axis, angle, {1, 1, 1}, rl.WHITE)
}

draw_fighter_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3) {
	if !drone_visuals_ready {
		rl.DrawSphere(position, 0.35, enemy ? rl.RED : SCIFI_BLUE)
		return
	}
	h := heading
	if rl.Vector3Length(h) < 0.001 { h = {1, 0, 0} }
	h = rl.Vector3Normalize(h)

	model := enemy ? drone_models[.ENEMY_FIGHTER] : drone_models[.PLAYER_FIGHTER]

	v_from := rl.Vector3{1, 0, 0}
	dot := rl.Vector3DotProduct(v_from, h)
	axis := rl.Vector3{0, 1, 0}
	angle: f32 = 0.0
	if dot < -0.9999 {
		axis = {0, 1, 0}
		angle = 180.0
	} else if dot < 0.9999 {
		axis = rl.Vector3Normalize(rl.Vector3CrossProduct(v_from, h))
		angle = math.acos(math.clamp(dot, -1.0, 1.0)) * (180.0 / math.PI)
	}

	rl.DrawModelEx(model, position, axis, angle, {1, 1, 1}, rl.WHITE)
}

// Visible laser fire during battles: short flying bolts from each shooter
// toward its target (player fire neon cyan, enemy fire RED), mirroring the
// update_planet_combat rules — dogfights, miner sweeps and base sieges.
draw_combat_lasers :: proc(p: int, player_spots, enemy_spots: []rl.Vector3, pc, ec: int, player_miner_spots, enemy_miner_spots: []rl.Vector3, pmc, emc: int) {
	num_p := min(pc, rep_count(pc))
	num_e := min(ec, rep_count(ec))
	if num_p > 0 && num_e > 0 {
		// Dogfight: visible fighters trade fire.
		for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_spots[i % num_e], f32(i) * 2.3, SCIFI_CYAN) }
		for j in 0..<num_e { draw_laser_bolt(enemy_spots[j], player_spots[j % num_p], f32(j) * 2.3 + 1.1, rl.RED) }
	} else if num_e > 0 {
		// Enemy fighters strafing unescorted player miners (kill_player_miner).
		num_tc := min(pmc, rep_count(pmc))
		for j in 0..<num_e {
			if num_tc == 0 { break }
			draw_laser_bolt(enemy_spots[j], player_miner_spots[j % num_tc], f32(j) * 2.3, rl.RED)
		}
	} else if num_p > 0 {
		// Player fighters sweeping enemy miners (kill_enemy_miner), then
		// besieging the enemy base itself.
		if emc > 0 {
			num_tc := min(emc, rep_count(emc))
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_miner_spots[i % num_tc], f32(i) * 2.3, SCIFI_CYAN) }
		} else if enemy_base_hp[p] > 0 {
			base := sector_pos(p) + rl.Vector3{0, sector_radius(p) * 0.6, 0}
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], base, f32(i) * 2.3, SCIFI_CYAN) }
		}
	}
}

// A short laser bolt flying along the shooter->target ray: its head advances
// at LASER_BOLT_SPEED on the game clock (laser_anim_time, frozen on pause)
// with a per-shooter phase offset, wrapping at the target. Two half-cycle
// phased bolts per ray read as sustained fire.
draw_laser_bolt :: proc(from, to: rl.Vector3, offset: f32, color: rl.Color) {
	diff := rl.Vector3{to.x - from.x, to.y - from.y, to.z - from.z}
	dist := rl.Vector3Length(diff)
	if dist < 0.05 { return }
	dir := diff * (1.0 / dist)
	for phase in 0..<2 {
		head := math.mod(laser_anim_time * LASER_BOLT_SPEED + offset + f32(phase) * dist * 0.5, dist)
		tail := clamp(head - LASER_BOLT_LEN, 0, dist)
		rl.DrawLine3D(from + dir * tail, from + dir * head, color)
	}
}

// One rendered cube per up-to-10 units: ceil(count / 10).
rep_count :: proc(count: int) -> int { return (count + 9) / 10 }

// Fighting drones in transit to a planet, grouped by side — the unit side of
// the transit representational rendering.
transit_fighters_at :: proc(target_planet: int, enemy: bool) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.state == .TRANSIT && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Mining drones in transit to a planet, grouped by side — the unit side of
// the transit representational rendering.
transit_miners_at :: proc(target_planet: int, enemy: bool = false) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .TRANSIT && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Mining drones returning from a planet to Earth.
returning_miners_at :: proc(target_planet: int, enemy: bool = false) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .RETURNING && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Planet a stationed (non-transit) miner is physically located at.
miner_stationed_planet :: proc(u: ^Unit) -> int {
	if u.state == .TRANSIT || u.state == .RETURNING { return -1 }
	if u.state == .DEPOSITING { return EARTH }
	if u.enemy { return u.affiliation }
	if u.target_planet >= 0 && u.target_planet < SECTOR_COUNT { return u.target_planet }
	if u.affiliation >= 0 && u.affiliation < SECTOR_COUNT { return u.affiliation }
	return EARTH
}

// Stationed mining drones at a planet, grouped by side.
stationed_miners_at :: proc(p: int, enemy: bool) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy != enemy { continue }
		if miner_stationed_planet(u) == p { count += 1 }
	}
	return count
}

draw_selection_ring :: proc(center: rl.Vector3, radius: f32) {
	segments :: 24
	pulse := 0.65 + 0.35 * math.sin(laser_anim_time * 5.0)
	for segment := 0; segment < segments; segment += 1 {
		a := f32(segment) * 2 * math.PI / f32(segments)
		b := f32(segment + 1) * 2 * math.PI / f32(segments)
		rl.DrawLine3D(
			{center.x + math.cos(a) * radius, center.y - 0.25, center.z + math.sin(a) * radius},
			{center.x + math.cos(b) * radius, center.y - 0.25, center.z + math.sin(b) * radius},
			rl.Fade(SCIFI_CYAN, pulse),
		)
		// Outer halo ring for depth.
		or_ := radius + 0.22
		rl.DrawLine3D(
			{center.x + math.cos(a) * or_, center.y - 0.25, center.z + math.sin(a) * or_},
			{center.x + math.cos(b) * or_, center.y - 0.25, center.z + math.sin(b) * or_},
			rl.Fade(SCIFI_CYAN, 0.25 * pulse),
		)
	}
}

// ---- Sci-Fi Vector Drawing Primitives -----------------------------------

// Draws a panel with 45-degree chamfered corners matching futuristic HUD frames.
draw_chamfered_panel :: proc(rect: rl.Rectangle, chamfer: f32, fill: rl.Color, border: rl.Color) {
	c := clamp(chamfer, 0, min(rect.width, rect.height) * 0.5)
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	if c <= 0 {
		rl.DrawRectangleRec(rect, fill)
		rl.DrawRectangleLinesEx(rect, 1, border)
		return
	}
	// Center and side rectangular spans
	rl.DrawRectangleRec({x + c, y, w - 2 * c, h}, fill)
	rl.DrawRectangleRec({x, y + c, c, h - 2 * c}, fill)
	rl.DrawRectangleRec({x + w - c, y + c, c, h - 2 * c}, fill)
	// Corner triangles (counter-clockwise winding)
	rl.DrawTriangle({x, y + c}, {x + c, y + c}, {x + c, y}, fill)
	rl.DrawTriangle({x + w - c, y}, {x + w - c, y + c}, {x + w, y + c}, fill)
	rl.DrawTriangle({x + w, y + h - c}, {x + w - c, y + h - c}, {x + w - c, y + h}, fill)
	rl.DrawTriangle({x + c, y + h}, {x + c, y + h - c}, {x, y + h - c}, fill)

	// 8-edge border loop
	v0 := rl.Vector2{x + c, y}
	v1 := rl.Vector2{x + w - c, y}
	v2 := rl.Vector2{x + w, y + c}
	v3 := rl.Vector2{x + w, y + h - c}
	v4 := rl.Vector2{x + w - c, y + h}
	v5 := rl.Vector2{x + c, y + h}
	v6 := rl.Vector2{x, y + h - c}
	v7 := rl.Vector2{x, y + c}

	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)
}

// Sci-fi outer corner L-brackets framing tactical windows, buttons, and reticles.
draw_corner_brackets :: proc(rect: rl.Rectangle, offset: f32, length: f32, color: rl.Color) {
	x := rect.x - offset
	y := rect.y - offset
	w := rect.width + 2 * offset
	h := rect.height + 2 * offset
	l := min(length, min(w * 0.4, h * 0.4))
	if l <= 0 { return }

	// Top-Left
	rl.DrawLineV({x, y}, {x + l, y}, color)
	rl.DrawLineV({x, y}, {x, y + l}, color)
	// Top-Right
	rl.DrawLineV({x + w - l, y}, {x + w, y}, color)
	rl.DrawLineV({x + w, y}, {x + w, y + l}, color)
	// Bottom-Left
	rl.DrawLineV({x, y + h}, {x + l, y + h}, color)
	rl.DrawLineV({x, y + h - l}, {x, y + h}, color)
	// Bottom-Right
	rl.DrawLineV({x + w - l, y + h}, {x + w, y + h}, color)
	rl.DrawLineV({x + w, y + h - l}, {x + w, y + h}, color)
}

// Draws an aerospace HUD dock for the top-left with an angled 45° wing cut on its bottom-right corner,
// multi-layer glowing neon borders, and detached corner bracket accents (inspired by Star Fox Zero cockpit HUD).
draw_winged_panel_left :: proc(rect: rl.Rectangle, chamfer: f32, wing_cut: f32, fill: rl.Color, border: rl.Color) {
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	ch := clamp(chamfer, 2, 8)
	wing := clamp(wing_cut, 8, min(w * 0.4, h * 0.8))

	v0 := rl.Vector2{x + ch, y}
	v1 := rl.Vector2{x + w - ch, y}
	v2 := rl.Vector2{x + w, y + ch}
	v3 := rl.Vector2{x + w, y + h - wing}
	v4 := rl.Vector2{x + w - wing, y + h}
	v5 := rl.Vector2{x + ch, y + h}
	v6 := rl.Vector2{x, y + h - ch}
	v7 := rl.Vector2{x, y + ch}

	// Ambient soft cyan glow backing
	glow_col := rl.Fade(border, 0.12)
	rl.DrawRectangleGradientV(i32(x), i32(y), i32(w), i32(h), glow_col, rl.Color{0, 0, 0, 0})

	// Fill convex polygon using triangle fan from v0
	rl.DrawTriangle(v0, v1, v2, fill)
	rl.DrawTriangle(v0, v2, v3, fill)
	rl.DrawTriangle(v0, v3, v4, fill)
	rl.DrawTriangle(v0, v4, v5, fill)
	rl.DrawTriangle(v0, v5, v6, fill)
	rl.DrawTriangle(v0, v6, v7, fill)

	// Primary outer neon stroke
	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)

	// Inner subtle secondary rail (inset by 3px)
	inner_border := SCIFI_STEEL
	iv0 := rl.Vector2{x + ch + 2, y + 3}
	iv1 := rl.Vector2{x + w - ch - 2, y + 3}
	iv2 := rl.Vector2{x + w - 3, y + ch + 2}
	iv3 := rl.Vector2{x + w - 3, y + h - wing}
	iv4 := rl.Vector2{x + w - wing, y + h - 3}
	iv5 := rl.Vector2{x + ch + 2, y + h - 3}
	iv6 := rl.Vector2{x + 3, y + h - ch - 2}
	iv7 := rl.Vector2{x + 3, y + ch + 2}
	rl.DrawLineV(iv0, iv1, inner_border)
	rl.DrawLineV(iv2, iv3, inner_border)
	rl.DrawLineV(iv3, iv4, inner_border)
	rl.DrawLineV(iv4, iv5, inner_border)
	rl.DrawLineV(iv6, iv7, inner_border)

	// Outer detached tactical brackets
	bracket_col := SCIFI_MINT
	// Top-left bracket
	rl.DrawLineV({x - 3, y - 3}, {x + 12, y - 3}, bracket_col)
	rl.DrawLineV({x - 3, y - 3}, {x - 3, y + 12}, bracket_col)
	// Top-right bracket
	rl.DrawLineV({x + w + 3, y - 3}, {x + w - 10, y - 3}, bracket_col)
	rl.DrawLineV({x + w + 3, y - 3}, {x + w + 3, y + 10}, bracket_col)
	// Wing cut accent tick
	rl.DrawLineV({x + w - wing + 4, y + h + 3}, {x + w + 3, y + h - wing - 4}, rl.Fade(bracket_col, 0.7))
}

// Draws a symmetrical aerospace HUD dock for the top-right with an angled 45° wing cut on its bottom-left corner,
// multi-layer glowing neon borders, and detached corner bracket accents.
draw_winged_panel_right :: proc(rect: rl.Rectangle, chamfer: f32, wing_cut: f32, fill: rl.Color, border: rl.Color) {
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	ch := clamp(chamfer, 2, 8)
	wing := clamp(wing_cut, 8, min(w * 0.4, h * 0.8))

	v0 := rl.Vector2{x + ch, y}
	v1 := rl.Vector2{x + w - ch, y}
	v2 := rl.Vector2{x + w, y + ch}
	v3 := rl.Vector2{x + w, y + h - ch}
	v4 := rl.Vector2{x + w - ch, y + h}
	v5 := rl.Vector2{x + wing, y + h}
	v6 := rl.Vector2{x, y + h - wing}
	v7 := rl.Vector2{x, y + ch}

	// Ambient soft cyan glow backing
	glow_col := rl.Fade(border, 0.12)
	rl.DrawRectangleGradientV(i32(x), i32(y), i32(w), i32(h), glow_col, rl.Color{0, 0, 0, 0})

	// Fill convex polygon using triangle fan from v1
	rl.DrawTriangle(v1, v2, v3, fill)
	rl.DrawTriangle(v1, v3, v4, fill)
	rl.DrawTriangle(v1, v4, v5, fill)
	rl.DrawTriangle(v1, v5, v6, fill)
	rl.DrawTriangle(v1, v6, v7, fill)
	rl.DrawTriangle(v1, v7, v0, fill)

	// Primary outer neon stroke
	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)

	// Inner subtle secondary rail (inset by 3px)
	inner_border := SCIFI_STEEL
	iv0 := rl.Vector2{x + ch + 2, y + 3}
	iv1 := rl.Vector2{x + w - ch - 2, y + 3}
	iv2 := rl.Vector2{x + w - 3, y + ch + 2}
	iv3 := rl.Vector2{x + w - 3, y + h - ch - 2}
	iv4 := rl.Vector2{x + w - ch - 2, y + h - 3}
	iv5 := rl.Vector2{x + wing, y + h - 3}
	iv6 := rl.Vector2{x + 3, y + h - wing}
	iv7 := rl.Vector2{x + 3, y + ch + 2}
	rl.DrawLineV(iv0, iv1, inner_border)
	rl.DrawLineV(iv2, iv3, inner_border)
	rl.DrawLineV(iv4, iv5, inner_border)
	rl.DrawLineV(iv5, iv6, inner_border)
	rl.DrawLineV(iv7, iv0, inner_border)

	// Outer detached tactical brackets
	bracket_col := SCIFI_MINT
	// Top-right bracket
	rl.DrawLineV({x + w + 3, y - 3}, {x + w - 12, y - 3}, bracket_col)
	rl.DrawLineV({x + w + 3, y - 3}, {x + w + 3, y + 12}, bracket_col)
	// Bottom-right bracket
	rl.DrawLineV({x + w + 3, y + h + 3}, {x + w - 12, y + h + 3}, bracket_col)
	rl.DrawLineV({x + w + 3, y + h + 3}, {x + w + 3, y + h - 12}, bracket_col)
	// Wing cut accent tick
	rl.DrawLineV({x + wing - 4, y + h + 3}, {x - 3, y + h - wing - 4}, rl.Fade(bracket_col, 0.7))
}

// Draws a sleek Arwing / fighter tactical vector silhouette icon (matching the ship icon next to '5' in reference image).
draw_fighter_vector_icon :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
	nose := rl.Vector2{center.x, center.y - size * 1.1}
	wing_l := rl.Vector2{center.x - size * 1.0, center.y + size * 0.7}
	wing_r := rl.Vector2{center.x + size * 1.0, center.y + size * 0.7}
	tail := rl.Vector2{center.x, center.y + size * 0.2}

	rl.DrawTriangle(nose, wing_l, tail, rl.Fade(color, 0.35))
	rl.DrawTriangle(nose, tail, wing_r, rl.Fade(color, 0.35))

	rl.DrawLineV(nose, wing_l, color)
	rl.DrawLineV(wing_l, tail, color)
	rl.DrawLineV(tail, wing_r, color)
	rl.DrawLineV(wing_r, nose, color)
	rl.DrawLineV(nose, tail, SCIFI_MINT)
}

// Draws an aerospace tactical console container for the planet inspector
// (matching the bottom-center container in the reference image).
// Features 45° chamfers, dual glowing neon rails, precision ruler tick notches,
// and ambient cyan edge glow.
draw_tactical_container :: proc(rect: rl.Rectangle) {
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	ch: f32 = 18.0

	// Soft drop shadow and ambient neon cyan bloom spilling into the viewport to the left
	rl.DrawRectangleGradientH(i32(x - 28), i32(y), 28, i32(h), rl.Color{0, 0, 0, 0}, rl.Color{0, 0, 0, 160})
	rl.DrawRectangleGradientH(i32(x - 10), i32(y), 10, i32(h), rl.Color{0, 0, 0, 0}, rl.Fade(SCIFI_CYAN, 0.14))

	// 8-vertex chamfered polygon for container housing
	v0 := rl.Vector2{x + ch, y}
	v1 := rl.Vector2{x + w - ch, y}
	v2 := rl.Vector2{x + w, y + ch}
	v3 := rl.Vector2{x + w, y + h - ch}
	v4 := rl.Vector2{x + w - ch, y + h}
	v5 := rl.Vector2{x + ch, y + h}
	v6 := rl.Vector2{x, y + h - ch}
	v7 := rl.Vector2{x, y + ch}

	fill := SCIFI_PANEL
	rl.DrawTriangle(v0, v1, v2, fill)
	rl.DrawTriangle(v0, v2, v3, fill)
	rl.DrawTriangle(v0, v3, v4, fill)
	rl.DrawTriangle(v0, v4, v5, fill)
	rl.DrawTriangle(v0, v5, v6, fill)
	rl.DrawTriangle(v0, v6, v7, fill)

	// Primary outer neon cyan stroke
	border := SCIFI_CYAN
	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)

	// Secondary inner rail (inset by 3px)
	inner := SCIFI_STEEL
	rl.DrawLineV({x + ch + 2, y + 3}, {x + w - ch - 2, y + 3}, inner)
	rl.DrawLineV({x + w - 3, y + ch + 2}, {x + w - 3, y + h - ch - 2}, inner)
	rl.DrawLineV({x + w - ch - 2, y + h - 3}, {x + ch + 2, y + h - 3}, inner)
	rl.DrawLineV({x + 3, y + h - ch - 2}, {x + 3, y + ch + 2}, inner)

	// Outer corner bracket accents
	draw_corner_brackets(rect, 3, 12, SCIFI_MINT)

	// Precision tactical ruler tick marks along the vertical left border
	tick_step: f32 = 32.0
	for ty := y + ch + 16; ty < y + h - ch - 16; ty += tick_step {
		major := math.mod(ty - y, 64.0) < tick_step * 0.5
		tick_len: f32 = major ? 7.0 : 4.0
		tick_col := major ? SCIFI_CYAN : SCIFI_STEEL
		rl.DrawLineV({x - tick_len, ty}, {x, ty}, tick_col)
	}

	// Precision tick notches along the top border line (matching modular top brackets in reference image)
	for tx := x + ch + 24; tx < x + w - ch - 24; tx += 40.0 {
		rl.DrawLineV({tx - 5, y}, {tx - 5, y - 3}, SCIFI_CYAN)
		rl.DrawLineV({tx - 5, y - 3}, {tx + 5, y - 3}, SCIFI_MINT)
		rl.DrawLineV({tx + 5, y - 3}, {tx + 5, y}, SCIFI_CYAN)
	}
}

// High-tech tactical section header with title text and glowing dividing rail.
draw_section_header :: proc(x, y, w: f32, title: cstring, color: rl.Color) {
	rl.DrawText(title, i32(x), i32(y), 12, color)
	tw := f32(rl.MeasureText(title, 12))
	line_x := x + tw + 8
	if line_x < x + w - 4 {
		rl.DrawLineV({line_x, y + 6}, {x + w - 4, y + 6}, rl.Fade(color, 0.35))
		rl.DrawLineV({x + w - 4, y + 3}, {x + w - 4, y + 9}, color)
	}
}

// Status card body with depth: chamfered corners, dark glass fill,
// top highlight, and corner brackets.
draw_status_card :: proc(card: rl.Rectangle, border: rl.Color) {
	draw_chamfered_panel(card, 6, SCIFI_PANEL_SOLID, border)
	draw_corner_brackets(card, 2, 8, border)
	rl.DrawLineV({card.x + 8, card.y + 1}, {card.x + card.width - 8, card.y + 1}, rl.Color{255, 255, 255, 30})
}

// Digital segmented progress/meter bar (blocks ■ ■ ■ □ □).
draw_segmented_meter :: proc(rect: rl.Rectangle, value: f32, segments: int, filled_color: rl.Color, empty_color: rl.Color = SCIFI_DIM) {
	v := clamp(value, 0, 1)
	if segments <= 0 { return }
	gap: f32 = 2.0
	seg_w := (rect.width - gap * f32(segments - 1)) / f32(segments)
	if seg_w < 1 { seg_w = 1 }
	active_count := int(math.round(v * f32(segments)))
	if v > 0 && active_count == 0 { active_count = 1 }
	for s in 0..<segments {
		sx := rect.x + f32(s) * (seg_w + gap)
		s_rect := rl.Rectangle{sx, rect.y, seg_w, rect.height}
		if s < active_count {
			rl.DrawRectangleRec(s_rect, filled_color)
			rl.DrawLineV({s_rect.x, s_rect.y}, {s_rect.x + s_rect.width, s_rect.y}, SCIFI_MINT)
		} else {
			rl.DrawRectangleRec(s_rect, rl.Color{8, 18, 24, 220})
			rl.DrawRectangleLinesEx(s_rect, 1, empty_color)
		}
	}
}

// 2D optical aim reticle with concentric arcs, cardinal crosshair ticks,
// and corner brackets, matching the vector optical aim in the reference image.
draw_optical_reticle_2d :: proc(center: rl.Vector2, radius: f32, color: rl.Color, label: cstring = "") {
	r := max(radius, 20.0)
	pulse := 0.8 + 0.2 * math.sin(laser_anim_time * 4.0)
	col := rl.Fade(color, pulse)

	// Inner segmented arc ring (4 quadrants with 20-degree gaps)
	segments :: 32
	for i in 0..<segments {
		quad_idx := i % 8
		if quad_idx == 0 || quad_idx == 7 { continue }

		a1 := f32(i) * 2 * math.PI / f32(segments) + laser_anim_time * 0.3
		a2 := f32(i + 1) * 2 * math.PI / f32(segments) + laser_anim_time * 0.3
		p1 := rl.Vector2{center.x + math.cos(a1) * r, center.y + math.sin(a1) * r}
		p2 := rl.Vector2{center.x + math.cos(a2) * r, center.y + math.sin(a2) * r}
		rl.DrawLineV(p1, p2, col)
	}

	// Outer concentric ring
	rl.DrawCircleLines(c.int(center.x), c.int(center.y), r + 6.0, rl.Fade(SCIFI_STEEL, 0.6))

	// Cardinal crosshair ticks
	tick_len: f32 = 7.0
	rl.DrawLineV({center.x, center.y - r - 2}, {center.x, center.y - r - 2 - tick_len}, col)
	rl.DrawLineV({center.x, center.y + r + 2}, {center.x, center.y + r + 2 + tick_len}, col)
	rl.DrawLineV({center.x - r - 2, center.y}, {center.x - r - 2 - tick_len, center.y}, col)
	rl.DrawLineV({center.x + r + 2, center.y}, {center.x + r + 2 + tick_len, center.y}, col)

	// Outer square target brackets [  ]
	bracket_rect := rl.Rectangle{center.x - r - 8, center.y - r - 8, 2 * (r + 8), 2 * (r + 8)}
	draw_corner_brackets(bracket_rect, 0, 8, SCIFI_CYAN)

	// Center target dot
	rl.DrawCircle(c.int(center.x), c.int(center.y), 2.0, SCIFI_AMBER)

	// Optional label tag
	if len(label) > 0 {
		tw := f32(rl.MeasureText(label, 13))
		lbl_x := center.x - tw / 2
		lbl_y := center.y - r - 24
		rl.DrawRectangleRec({lbl_x - 6, lbl_y - 2, tw + 12, 17}, SCIFI_PANEL_SOLID)
		rl.DrawRectangleLinesEx({lbl_x - 6, lbl_y - 2, tw + 12, 17}, 1, SCIFI_STEEL)
		rl.DrawText(label, c.int(lbl_x), c.int(lbl_y), 13, SCIFI_MINT)
	}
}

// High-tech tactile button: 45° chamfered corners, centered label,
// and hover corner brackets.
draw_button :: proc(rect: rl.Rectangle, label: cstring, color: rl.Color = SCIFI_PANEL_SOLID, enabled: bool = true) {
	hovered := enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	pressed := enabled && hovered && rl.IsMouseButtonDown(.LEFT)

	chamfer: f32 = 6.0
	fill := SCIFI_PANEL_SOLID
	border := SCIFI_STEEL
	text_col := SCIFI_TEXT

	if !enabled {
		fill = rl.Color{6, 14, 20, 240}
		border = SCIFI_DIM
		text_col = SCIFI_MUTED
	} else if pressed {
		fill = rl.Color{0, 60, 75, 255}
		border = SCIFI_MINT
		text_col = SCIFI_MINT
	} else if hovered {
		fill = rl.Color{10, 36, 46, 255}
		border = SCIFI_CYAN
		text_col = SCIFI_CYAN
	}

	draw_chamfered_panel(rect, chamfer, fill, border)

	// Corner brackets when hovered
	if hovered && enabled {
		draw_corner_brackets(rect, 2, 6, SCIFI_CYAN)
	}

	// Label centered horizontally and vertically
	tw := f32(rl.MeasureText(label, 12))
	text_x := rect.x + (rect.width - tw) / 2
	if text_x < rect.x + 8 { text_x = rect.x + 8 }
	text_y := rect.y + (rect.height - 12) / 2 + (pressed ? 1.0 : 0.0)
	rl.DrawText(label, c.int(text_x), c.int(text_y), 12, text_col)
}


// High-tech build queue slot with chamfered edges and glowing symbols.
draw_queue_slot :: proc(rect: rl.Rectangle, queued: bool, kind: Unit_Type) {
	color := SCIFI_PANEL_SOLID
	border := SCIFI_DIM
	symbol: cstring = ""
	accent := SCIFI_AMBER
	if queued {
		color = rl.Color{0, 65, 85, 255}
		if kind == .COMBAT { color = rl.Color{15, 45, 90, 255}; accent = SCIFI_BLUE }
		border = SCIFI_CYAN
		symbol = "M"
		if kind == .COMBAT { symbol = "C" }
	}
	draw_chamfered_panel(rect, 3, color, border)
	if queued {
		draw_corner_brackets(rect, 1, 3, border)
		rl.DrawText(symbol, c.int(rect.x + 6), c.int(rect.y + 4), 12, rl.Color{0, 0, 0, 160})
		rl.DrawText(symbol, c.int(rect.x + 5), c.int(rect.y + 3), 12, accent)
	}
}

// Digital segmented progress bar replacing continuous solid bars.
draw_progress :: proc(rect: rl.Rectangle, value: f32, color: rl.Color) {
	segments := int(rect.width / 14)
	if segments < 8 { segments = 8 }
	draw_segmented_meter(rect, value, segments, color, SCIFI_DIM)
}

state_color :: proc(state: Unit_State) -> rl.Color {
	switch state {
	case .IDLE: return rl.GRAY
	case .TRANSIT: return SCIFI_BLUE
	case .MINING: return rl.GREEN
	case .RETURNING: return rl.ORANGE
	case .DEPOSITING: return SCIFI_CYAN
	case .GUARDING: return rl.RED
	case .CONSTRUCTING: return SCIFI_CYAN
	}
	return rl.WHITE
}

selection_count :: proc() -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if selected_units[i] { count += 1 } }
	return count
}

// ---- Planet visuals -------------------------------------------------------

planet_spin_speed :: proc(p: int) -> f32 {
	switch p {
	case JUPITER: return 0.22
	case SATURN: return 0.20
	case URANUS, NEPTUNE: return 0.16
	case MERCURY, VENUS: return 0.10
	}
	return 0.12
}

update_planet_spin :: proc(dt: f32) {
	for p in 0..<PLANET_COUNT {
		planet_spin[p] += dt * planet_spin_speed(p)
		if planet_spin[p] > 2 * math.PI { planet_spin[p] -= 2 * math.PI }
	}
}

// Linear blend between two opaque colors (t = 0 keeps a, t = 1 takes b).
mix_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	return rl.Color{
		u8(f32(a.r) * (1 - t) + f32(b.r) * t),
		u8(f32(a.g) * (1 - t) + f32(b.g) * t),
		u8(f32(a.b) * (1 - t) + f32(b.b) * t),
		255,
	}
}

PLANET_TEX_SIZE :: 128

// One deterministic surface blob (center + radius, in texels).
planet_blob :: struct { x, y, r: f32 }

// Build one procedural surface texture per planet. Deterministic per planet
// (offsets derive from the index), independent of the gameplay RNG. The whole
// pipeline is RGBA from the first pixel: the base image is GenImageColor and
// every texel is shaded in code from the perlin luminance, so no grayscale
// image op can ever drop the hue (which rendered as grey surface gores).
init_planet_visuals :: proc() {
	if planet_visuals_ready { return }
	for p in 0..<PLANET_COUNT {
		base := planets[p].color
		img := rl.GenImageColor(PLANET_TEX_SIZE, PLANET_TEX_SIZE, base)
		noise := rl.GenImagePerlinNoise(PLANET_TEX_SIZE, PLANET_TEX_SIZE, c.int(p * 17 + 3), c.int(p * 29 + 7), 6.0)
		lum := rl.LoadImageColors(noise)
		// Deterministic blotches via a tiny LCG (no gameplay RNG use).
		seed := u32(0x9E3779B9 + u32(p) * 0x85EBCA6B)
		next := proc(seed: ^u32) -> f32 {
			seed^ = seed^ * 1664525 + 1013904223
			return f32((seed^ >> 8) & 0xFFFF) / f32(0xFFFF)
		}
		blobs: [9]planet_blob
		for b in 0..<9 {
			blobs[b] = {next(&seed) * PLANET_TEX_SIZE, next(&seed) * PLANET_TEX_SIZE, 4 + next(&seed) * 11}
		}
		oceans: [6]planet_blob
		for b in 0..<6 {
			oceans[b] = {next(&seed) * PLANET_TEX_SIZE, next(&seed) * PLANET_TEX_SIZE, 6 + next(&seed) * 13}
		}
		blotch := rl.Color{u8(min(int(base.r) + 34, 255)), u8(min(int(base.g) + 34, 255)), u8(min(int(base.b) + 34, 255)), 255}
		ocean := rl.Color{18, 60, 150, 255}
		for y in 0..<PLANET_TEX_SIZE {
			for x in 0..<PLANET_TEX_SIZE {
				l := f32(lum[y * PLANET_TEX_SIZE + x].r) / 255.0
				shade := 0.70 + l * 0.60
				col := rl.Color{
					u8(min(f32(base.r) * shade, 255)),
					u8(min(f32(base.g) * shade, 255)),
					u8(min(f32(base.b) * shade, 255)),
					255,
				}
				if p >= JUPITER {
					// Planetary latitude cloud bands for gas giants.
					// In par_shapes sphere, x is latitude (0 = North Pole, 127 = South Pole).
					// Subtle perlin perturbation (l) adds atmospheric turbulence.
					x_lat := f32(x) + (l - 0.5) * 5.0
					band_freq: f32 = 0.38
					band_phase: f32 = f32(p * 13)
					if p == JUPITER { band_freq = 0.42 }
					else if p == SATURN { band_freq = 0.32 }
					else if p == URANUS { band_freq = 0.22 }
					else if p == NEPTUNE { band_freq = 0.28 }

					band_val := math.sin(x_lat * band_freq + band_phase) + 0.35 * math.sin(x_lat * band_freq * 2.1 + band_phase * 1.5)

					contrast: f32 = 0.26
					if p == JUPITER { contrast = 0.32 }
					else if p == SATURN { contrast = 0.18 }
					else if p == URANUS { contrast = 0.12 }
					else if p == NEPTUNE { contrast = 0.22 }

					if band_val > 0.1 {
						boost := 1.0 + contrast * (band_val * 0.7)
						col = rl.Color{
							u8(min(f32(col.r) * boost + 8 * boost, 255)),
							u8(min(f32(col.g) * boost + 8 * boost, 255)),
							u8(min(f32(col.b) * boost + 8 * boost, 255)),
							255,
						}
					} else {
						darken := 1.0 + contrast * band_val
						darken = max(darken, 0.65)
						if p == JUPITER {
							col = rl.Color{
								u8(min(f32(col.r) * darken * 1.08, 255)),
								u8(f32(col.g) * darken * 0.90),
								u8(f32(col.b) * darken * 0.80),
								255,
							}
						} else {
							col = rl.Color{
								u8(f32(col.r) * darken),
								u8(f32(col.g) * darken),
								u8(f32(col.b) * darken),
								255,
							}
						}
					}

					if p == JUPITER {
						spot_x: f32 = 82.0
						spot_y: f32 = 55.0
						dx := (f32(x) - spot_x) / 5.5
						dy_val := f32(y) - spot_y
						if dy_val > f32(PLANET_TEX_SIZE) / 2.0 { dy_val -= f32(PLANET_TEX_SIZE) }
						if dy_val < -f32(PLANET_TEX_SIZE) / 2.0 { dy_val += f32(PLANET_TEX_SIZE) }
						dy := dy_val / 11.0
						dist_sq := dx * dx + dy * dy
						if dist_sq <= 1.0 {
							spot_col := rl.Color{205, 68, 48, 255}
							col = mix_color(col, spot_col, 0.78 * (1.0 - dist_sq * 0.25))
						}
					} else if p == NEPTUNE {
						spot_x: f32 = 75.0
						spot_y: f32 = 60.0
						dx := (f32(x) - spot_x) / 6.0
						dy_val := f32(y) - spot_y
						if dy_val > f32(PLANET_TEX_SIZE) / 2.0 { dy_val -= f32(PLANET_TEX_SIZE) }
						if dy_val < -f32(PLANET_TEX_SIZE) / 2.0 { dy_val += f32(PLANET_TEX_SIZE) }
						dy := dy_val / 12.0
						dist_sq := dx * dx + dy * dy
						if dist_sq <= 1.0 {
							spot_col := rl.Color{35, 55, 140, 255}
							col = mix_color(col, spot_col, 0.70)
						}
					}
				} else {
					fx, fy := f32(x), f32(y)
					for b in 0..<9 {
						dx, dy := fx - blobs[b].x, fy - blobs[b].y
						if dx * dx + dy * dy <= blobs[b].r * blobs[b].r {
							col = mix_color(col, blotch, 0.5)
							break
						}
					}
					// Earth oceans: deep-blue patches over the marble.
					if p == EARTH {
						for b in 0..<6 {
							dx, dy := fx - oceans[b].x, fy - oceans[b].y
							if dx * dx + dy * dy <= oceans[b].r * oceans[b].r {
								col = mix_color(col, ocean, 0.65)
								break
							}
						}
						if x < 8 || x > 120 {
							col = mix_color(col, rl.Color{240, 245, 255, 255}, 0.85)
						}
					} else if p == MARS {
						if x < 6 || x > 122 {
							col = mix_color(col, rl.Color{240, 230, 225, 255}, 0.80)
						}
					}
				}
				rl.ImageDrawPixel(&img, c.int(x), c.int(y), col)
			}
		}
		rl.UnloadImageColors(lum)
		rl.UnloadImage(noise)
		tex := rl.LoadTextureFromImage(img)
		rl.SetTextureWrap(tex, .REPEAT)
		rl.SetTextureFilter(tex, .BILINEAR)
		rl.UnloadImage(img)
		planet_textures[p] = tex
		model := rl.LoadModelFromMesh(rl.GenMeshSphere(planets[p].radius, 32, 32))
		model.transform = rl.MatrixRotateX(rl.DEG2RAD * -90)
		rl.SetMaterialTexture(&model.materials[0], .ALBEDO, tex)
		planet_models[p] = model
	}
	planet_visuals_ready = true
}

unload_planet_visuals :: proc() {
	if !planet_visuals_ready { return }
	for p in 0..<PLANET_COUNT {
		rl.UnloadModel(planet_models[p])
		rl.UnloadTexture(planet_textures[p])
	}
	planet_visuals_ready = false
}

// ---- Starfield ----------------------------------------------------------

STAR_COUNT :: 280

stars: [STAR_COUNT]rl.Vector3
star_sizes: [STAR_COUNT]f32
star_alphas: [STAR_COUNT]f32

// Deterministic sky: a wide disc well below the play plane, so panning and
// zooming parallax-scrolls it. A tiny LCG keeps the starfield identical every
// run and independent of the gameplay RNG.
generate_stars :: proc() {
	seed := u32(0x5F3759DF)
	for i in 0..<STAR_COUNT {
		seed = seed * 1664525 + 1013904223
		angle := f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 2 * math.PI
		seed = seed * 1664525 + 1013904223
		dist := 20.0 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 420.0
		seed = seed * 1664525 + 1013904223
		depth := f32((seed >> 8) & 0xFFFF) / f32(0xFFFF)
		stars[i] = {math.cos(angle) * dist, -14.0 - depth * 60.0, math.sin(angle) * dist}
		seed = seed * 1664525 + 1013904223
		star_sizes[i] = 0.9 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 1.1
		seed = seed * 1664525 + 1013904223
		star_alphas[i] = 0.35 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 0.6
	}
}

// Cool-tinted pixel stars in screen space, drawn before the 3D pass so they
// stay behind everything. Every 4th star carries a faint cyan tint for a
// colder deep-space feel; the tint derives from the star index so the field
// stays deterministic. The >= bounds form also discards NaN projections of
// points behind the camera.
draw_starfield :: proc() {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	for i in 0..<STAR_COUNT {
		pos := rl.GetWorldToScreen(stars[i], camera)
		if !(pos.x >= 0 && pos.x <= w && pos.y >= 0 && pos.y <= h) { continue }
		tint := rl.WHITE
		if i % 4 == 0 { tint = rl.Color{170, 230, 255, 255} }
		rl.DrawCircleV(pos, star_sizes[i], rl.Fade(tint, star_alphas[i]))
	}
}

// Red palpitating combat nebula in screen space behind planets with active combat
// and behind the enemy HQ. Rendered before BeginMode3D so 3D textured planet
// spheres and fortress models occlude the nebula core, creating an organic backlit
// cosmic warzone atmosphere. Uses additive blending for luminous gas clouds.
// Size scaled down by half for a tighter, more focused warzone halo.
draw_combat_nebulae :: proc() {
	has_any := false
	for s in 0..<SECTOR_COUNT {
		if combat_nebula_intensity[s] > 0.005 {
			has_any = true
			break
		}
	}
	if !has_any { return }

	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for s in 0..<SECTOR_COUNT {
		intensity := combat_nebula_intensity[s]
		if intensity <= 0.005 { continue }

		pos_3d := sector_pos(s)
		cam_to_pos := pos_3d - camera.position
		if rl.Vector3DotProduct(cam_to_pos, cam_forward) <= 0.1 { continue }

		screen_pos := rl.GetWorldToScreen(pos_3d, camera)
		if screen_pos.x < -250 || screen_pos.x > viewport_w + 250 || screen_pos.y < -250 || screen_pos.y > screen_h + 250 {
			continue
		}

		rad := sector_radius(s)
		limb_3d := pos_3d + cam_right * rad
		limb_screen := rl.GetWorldToScreen(limb_3d, camera)
		base_r := max(rl.Vector2Distance(screen_pos, limb_screen), 14.0)

		// Palpitating rhythm: organic multi-frequency heartbeat pulse
		// Combines fundamental throb with secondary harmonic for an authentic heart-palpitation cadence
		t := laser_anim_time
		pulse_speed: f32 = sector_combat_state[s] ? 3.8 : 2.4
		pulse1 := math.sin(t * pulse_speed + f32(s) * 1.8)
		pulse2 := math.sin(t * (pulse_speed * 2.0) + f32(s) * 2.5 + 0.45)
		palpitation := 0.85 + 0.28 * pulse1 + 0.16 * pulse2
		radius_pulse := 1.0 + 0.14 * math.sin(t * (pulse_speed * 0.7) + f32(s))

		effective_intensity := clamp(intensity * palpitation, 0.0, 1.6)

		// 1. Grand Outer Ambient Nebula Shroud (deep cosmic space haze)
		// Scaled down by half for a cleaner, tighter atmospheric halo
		grand_r := max(base_r * 5.5, 120.0) * radius_pulse
		grand_alpha := u8(clamp(75.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, grand_r, rl.Color{160, 12, 35, grand_alpha}, rl.Color{0, 0, 0, 0})

		secondary_grand_pos := rl.Vector2{
			screen_pos.x + math.cos(t * 0.3 + f32(s)) * (base_r * 1.4),
			screen_pos.y + math.sin(t * 0.25 + f32(s)) * (base_r * 1.0),
		}
		secondary_r := max(base_r * 4.75, 100.0) * radius_pulse
		rl.DrawCircleGradient(secondary_grand_pos, secondary_r, rl.Color{190, 20, 50, u8(clamp(60.0 * effective_intensity, 0, 255))}, rl.Color{0, 0, 0, 0})

		// 2. Multi-tiered Asymmetric Billowing Gas Clouds (12 organic lobes across 3 tiers)
		// Tier 1: Outer billowing wisps (4 lobes)
		for i in 0..<4 {
			fi := f32(i)
			ang := fi * (math.PI * 0.5) + math.sin(t * 0.35 + fi * 1.7 + f32(s)) * 0.45 + f32(s) * 0.8
			dist := max(base_r * (1.9 + 0.3 * math.sin(t * 0.6 + fi * 2.2 + f32(s))), 35.0)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.82}
			r := max(base_r * (1.9 + 0.25 * math.cos(t * 1.0 + fi * 1.5)) * radius_pulse, 32.5)
			alpha := u8(clamp(65.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{195, 18, 42, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 2: Mid-range turbulent cloud banks (5 lobes)
		for i in 0..<5 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 5.0) + math.sin(t * 0.45 + fi * 1.5 + f32(s)) * 0.38 + f32(s) * 1.3
			dist := max(base_r * (1.15 + 0.225 * math.sin(t * 0.75 + fi * 1.9 + f32(s))), 22.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.84}
			r := max(base_r * (1.5 + 0.225 * math.cos(t * 1.2 + fi * 1.8)) * radius_pulse, 25.0)
			alpha := u8(clamp(90.0 * effective_intensity, 0, 255))
			r_val := u8(clamp(235.0 + 20.0 * math.sin(fi * 2.0), 0, 255))
			g_val := u8(clamp(35.0 + 25.0 * math.cos(fi * 1.6), 0, 255))
			b_val := u8(clamp(30.0 + 20.0 * math.sin(fi * 3.0), 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{r_val, g_val, b_val, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 3: Dense inner plasma clouds (3 lobes)
		for i in 0..<3 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 3.0) + math.sin(t * 0.5 + fi * 2.1 + f32(s)) * 0.3 + f32(s) * 0.4
			dist := max(base_r * (0.65 + 0.15 * math.sin(t * 0.9 + fi * 2.5)), 12.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.86}
			r := max(base_r * (1.2 + 0.175 * math.cos(t * 1.3 + fi * 2.0)) * radius_pulse, 20.0)
			alpha := u8(clamp(110.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{255, 60, 32, alpha}, rl.Color{0, 0, 0, 0})
		}

		// 3. Hot Inner Combat Corona & Shockwave Disc (backlighting the body silhouette)
		corona_r := max(base_r * 1.4, 22.5) * radius_pulse
		corona_alpha := u8(clamp(135.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, corona_r, rl.Color{255, 55, 28, corona_alpha}, rl.Color{0, 0, 0, 0})

		// Scorching inner core ring right behind planet edge
		inner_core_r := max(base_r * 1.2, 16.0) * (0.95 + 0.1 * palpitation)
		inner_alpha := u8(clamp(115.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, inner_core_r, rl.Color{255, 125, 45, inner_alpha}, rl.Color{0, 0, 0, 0})

		// 4. Ionization Tendrils / Plasma Streamers (fine drifting filaments)
		for k in 0..<8 {
			fk := f32(k)
			spark_angle := fk * 0.785 + t * 0.55 + f32(s) * 1.4
			spark_dist := max(base_r * (1.4 + 0.25 * math.sin(t * 1.4 + fk * 2.2)), 22.5)
			spark_pos := rl.Vector2{
				screen_pos.x + math.cos(spark_angle) * spark_dist,
				screen_pos.y + math.sin(spark_angle) * spark_dist * 0.88,
			}
			spark_r := max(base_r * (0.7 + 0.175 * math.cos(t * 2.1 + fk)), 12.5)
			spark_alpha := u8(clamp(50.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(spark_pos, spark_r, rl.Color{255, 135, 50, spark_alpha}, rl.Color{0, 0, 0, 0})
		}
	}
}

// ---- Earth industrial manufacturing indicator ----------------------------

// Surface coordinates for major industrial complexes across Earth's continents.
Earth_Industry_Hub :: struct {
	lat: f32,
	lon: f32,
	theme: int, // 0 = foundry/forge, 1 = assembly/shipyard, 2 = laser/welding
}

EARTH_INDUSTRY_HUBS := [10]Earth_Industry_Hub{
	{lat = 38.0,  lon = 30.0,  theme = 0},
	{lat = 42.0,  lon = 85.0,  theme = 1},
	{lat = 52.0,  lon = 135.0, theme = 2},
	{lat = 35.0,  lon = 185.0, theme = 1},
	{lat = 15.0,  lon = 225.0, theme = 0},
	{lat = -25.0, lon = 275.0, theme = 2},
	{lat = -18.0, lon = 320.0, theme = 1},
	{lat = 8.0,   lon = 0.0,   theme = 0},
	{lat = 30.0,  lon = 350.0, theme = 2},
	{lat = -32.0, lon = 60.0,  theme = 1},
}

// Indicator on Earth when units are being created: industrial manufacturing
// complexes light up across Earth's surface with lights turning on and off,
// rhythmic assembly bay shifts, high-frequency robotic welding sparks, hazard
// strobes, and vertical shipyard gantry beacons, rotating naturally with the planet.
// Rendered in screen space with additive blending for pure radiant luminous glow.
draw_earth_industry_lights :: proc() {
	if earth_industry_intensity <= 0.005 { return }

	earth := planets[EARTH]
	spin := planet_spin[EARTH]
	cos_s := math.cos(spin)
	sin_s := math.sin(spin)
	t := laser_anim_time

	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())

	// Earth projected silhouette radius in screen space
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	earth_screen := rl.GetWorldToScreen(earth.position, camera)
	limb_screen := rl.GetWorldToScreen(earth.position + cam_right * earth.radius, camera)
	screen_r := max(rl.Vector2Distance(earth_screen, limb_screen), 12.0)

	// Active lines scale the number of active manufacturing hubs
	active_lines := 0
	for b in 0..<base_counts[EARTH] {
		if production[EARTH][b].active { active_lines += 1 }
	}
	if base_build_planet == EARTH { active_lines += 1 }
	hubs_count := min(5 + active_lines * 2, 10)

	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for h in 0..<hubs_count {
		hub := EARTH_INDUSTRY_HUBS[h]
		lat_rad := hub.lat * (math.PI / 180.0)
		lon_rad := hub.lon * (math.PI / 180.0)

		hub_u := rl.Vector3{
			math.cos(lat_rad) * math.cos(lon_rad),
			math.sin(lat_rad),
			math.cos(lat_rad) * math.sin(lon_rad),
		}

		// Rotate with Earth's planetary spin
		hub_rot := rl.Vector3{
			hub_u.x * cos_s - hub_u.z * sin_s,
			hub_u.y,
			hub_u.x * sin_s + hub_u.z * cos_s,
		}

		hub_3d := earth.position + hub_rot * (earth.radius * 1.002)

		// Occlusion check against Earth globe: hide lights on the far hemisphere
		cam_to_hub := camera.position - hub_3d
		cam_dist := rl.Vector3Length(cam_to_hub)
		if cam_dist <= 0.01 { continue }
		to_cam := cam_to_hub / cam_dist
		facing := rl.Vector3DotProduct(hub_rot, to_cam)
		if facing <= 0.02 { continue }
		limb_fade := clamp((facing - 0.02) / 0.18, 0.0, 1.0)
		net_intensity := earth_industry_intensity * limb_fade

		hub_screen := rl.GetWorldToScreen(hub_3d, camera)
		if hub_screen.x < -60 || hub_screen.x > viewport_w + 60 || hub_screen.y < -60 || hub_screen.y > screen_h + 60 {
			continue
		}

		// Local tangent vectors for spreading out facilities across each industrial zone
		up := rl.Vector3{0, 1, 0}
		if abs(hub_rot.y) > 0.90 { up = rl.Vector3{1, 0, 0} }
		tangent_u := rl.Vector3Normalize(rl.Vector3CrossProduct(up, hub_rot))
		tangent_v := rl.Vector3Normalize(rl.Vector3CrossProduct(hub_rot, tangent_u))

		fh := f32(h)

		// Radii scaled to projected planet radius with minimum visibility clamps
		core_r := max(screen_r * 0.045, 2.2)
		glow_r := max(screen_r * 0.12, 5.5)

		// 1. Soft industrial city / factory light bloom spill
		halo_r := max(screen_r * 0.22, 10.0)
		halo_alpha := u8(clamp(95.0 * net_intensity, 0, 255))
		halo_col := hub.theme == 1 ? rl.Color{0, 230, 215, halo_alpha} : rl.Color{255, 140, 25, halo_alpha}
		rl.DrawCircleGradient(hub_screen, halo_r, halo_col, rl.Color{0, 0, 0, 0})

		// 2. Main Foundry Core / Forge Furnace (warm golden-amber pulsing heart)
		foundry_pulse := 0.65 + 0.35 * math.sin(t * 3.0 + fh * 1.5)
		foundry_alpha := u8(clamp(foundry_pulse * 255.0 * net_intensity, 0, 255))
		rl.DrawCircleGradient(hub_screen, glow_r, rl.Color{255, 145, 20, foundry_alpha}, rl.Color{0, 0, 0, 0})
		rl.DrawCircleV(hub_screen, core_r, rl.Color{255, 225, 120, foundry_alpha})

		// Tangent screen offsets for satellite industrial nodes
		pos1_3d := hub_3d + tangent_u * 0.28 + tangent_v * 0.14
		pos1_screen := rl.GetWorldToScreen(pos1_3d, camera)

		pos2_3d := hub_3d + tangent_u * -0.25 + tangent_v * -0.16
		pos2_screen := rl.GetWorldToScreen(pos2_3d, camera)

		pos3_3d := hub_3d + tangent_u * -0.22 + tangent_v * 0.22
		pos3_screen := rl.GetWorldToScreen(pos3_3d, camera)

		pos4_3d := hub_3d + tangent_u * 0.18 + tangent_v * -0.24
		pos4_screen := rl.GetWorldToScreen(pos4_3d, camera)

		// 3. Automated Assembly Bay (electric cyan - turning on and off in distinct shift cycles)
		bay_cycle := math.mod(t * 1.4 + fh * 0.85, 2.0)
		bay_on := bay_cycle < 1.25
		bay_bright: f32 = bay_on ? (0.85 + 0.15 * math.sin(t * 9.0 + fh)) : 0.0
		bay_alpha := u8(clamp(bay_bright * 255.0 * net_intensity, 0, 255))
		if bay_alpha > 5 {
			rl.DrawCircleGradient(pos1_screen, glow_r * 0.9, rl.Color{0, 240, 220, bay_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos1_screen, core_r * 0.9, rl.Color{200, 255, 245, bay_alpha})
		}

		// Secondary assembly bay node (alternating shift)
		bay2_cycle := math.mod(t * 1.2 + fh * 1.4 + 0.8, 1.8)
		bay2_on := bay2_cycle < 1.05
		bay2_bright: f32 = bay2_on ? (0.80 + 0.20 * math.sin(t * 8.0 + fh * 2.0)) : 0.0
		bay2_alpha := u8(clamp(bay2_bright * 255.0 * net_intensity, 0, 255))
		if bay2_alpha > 5 {
			rl.DrawCircleGradient(pos2_screen, glow_r * 0.85, rl.Color{40, 255, 210, bay2_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos2_screen, core_r * 0.85, rl.Color{220, 255, 240, bay2_alpha})
		}

		// 4. Robotic Arc Welding / Laser Fabrication (high-frequency brilliant white-blue sparks)
		weld_cycle := math.mod(t * 1.6 + fh * 1.9, 2.3)
		weld_bright: f32 = 0.0
		if weld_cycle < 1.15 {
			spark := math.sin(t * 36.0 + fh * 7.3)
			if spark > 0.0 {
				weld_bright = 0.95 + 0.05 * math.sin(t * 60.0)
			}
		}
		weld_alpha := u8(clamp(weld_bright * 255.0 * net_intensity, 0, 255))
		if weld_alpha > 10 {
			rl.DrawCircleGradient(pos3_screen, glow_r * 0.95, rl.Color{200, 240, 255, weld_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos3_screen, core_r * 0.95, rl.Color{255, 255, 255, weld_alpha})
		}

		// 5. Strobe Hazard Beacon (sharp periodic warning flash)
		strobe_cycle := math.mod(t * 1.5 + fh * 0.4, 1.0)
		strobe_bright: f32 = strobe_cycle < 0.18 ? (1.0 - (strobe_cycle / 0.18) * 0.85) : 0.0
		strobe_alpha := u8(clamp(strobe_bright * 255.0 * net_intensity, 0, 255))
		if strobe_alpha > 10 {
			rl.DrawCircleGradient(pos4_screen, glow_r * 0.75, rl.Color{255, 195, 20, strobe_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos4_screen, core_r * 0.75, rl.Color{255, 240, 140, strobe_alpha})
		}

		// 6. Shipyard Gantry Spire / Launch Laser Beam (rising above surface)
		spire_3d := hub_3d + hub_rot * (earth.radius * 0.25)
		spire_screen := rl.GetWorldToScreen(spire_3d, camera)
		beam_alpha := u8(clamp(190.0 * net_intensity, 0, 255))
		beam_col := hub.theme == 1 ? rl.Color{0, 245, 220, beam_alpha} : rl.Color{255, 160, 40, beam_alpha}
		rl.DrawLineEx(hub_screen, spire_screen, max(screen_r * 0.03, 1.8), beam_col)

		// Pulsing tip beacon at the top of the gantry tower
		beacon_on := math.mod(t * 2.2 + fh * 0.5, 1.0) < 0.25
		beacon_alpha := u8(clamp((beacon_on ? 255.0 : 40.0) * net_intensity, 0, 255))
		rl.DrawCircleV(spire_screen, max(screen_r * 0.04, 2.2), rl.Color{255, 60, 50, beacon_alpha})
	}
}

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

// ENTER/KP_ENTER on the focused option — the same actions the mouse path takes.
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
	// Smooth transition of combat nebula intensity: rapid flare-up in battle, graceful fade-out on victory.
	for s in 0..<SECTOR_COUNT {
		in_combat := sector_in_combat(s)
		sector_combat_state[s] = in_combat
		target: f32 = 0.0
		if s == ENEMY_HOME {
			if !enemy_hq_destroyed() {
				target = in_combat ? 1.0 : 0.65
			}
		} else if in_combat {
			target = 1.0
		}
		rate: f32 = in_combat ? 3.5 : 1.2
		combat_nebula_intensity[s] += (target - combat_nebula_intensity[s]) * clamp(dt * rate, 0.0, 1.0)
	}
	// Victory latch: every planet liberated AND the enemy HQ destroyed.
	if !victory && victory_achieved() { victory = true }
	// Defeat latch (edge-triggered; reset_world clears it): no bases AND no units.
	if !victory && !defeated && defeat_condition() { defeated = true }
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
	box_h: f32 = 470.0
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

	// Column 2: Requisition, Simulation & Sensors
	cy2 := box.y + 84
	rl.DrawText("EARTH BASE REQUISITION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "M / CLICK", "Build Mining Drone (50)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "N", "Build +5 Miners (250)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "C / CLICK", "Build Combat Fighter (125)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "X", "Build +5 Fighters (625)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "U / SPEED", "Upgrade Build Speed (5,000)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "ESC", "Cancel last build (Refund)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CLICK SLOT", "Cancel specific queue slot")

	cy2 += 26
	rl.DrawText("SYSTEM AND SIMULATION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "P / F10", "Pause game / Mission menu")
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

// ---- Save & Load system -------------------------------------------------

save_game_path :: proc(custom_path: string = "", allocator := context.temp_allocator) -> string {
	if len(custom_path) > 0 {
		return custom_path
	}
	exe_dir, err := os.get_executable_directory(allocator)
	if err == nil && len(exe_dir) > 0 {
		p, _ := filepath.join({exe_dir, "savegame.txt"}, allocator)
		return p
	}
	return "savegame.txt"
}

save_game_exists :: proc(custom_path: string = "") -> bool {
	p := save_game_path(custom_path)
	if os.exists(p) {
		return true
	}
	if len(custom_path) == 0 && os.exists("savegame.txt") {
		return true
	}
	return false
}

unit_type_to_string :: proc(k: Unit_Type) -> string {
	switch k {
	case .MINING: return "MINING"
	case .COMBAT: return "COMBAT"
	}
	return "MINING"
}

unit_state_to_string :: proc(s: Unit_State) -> string {
	switch s {
	case .IDLE: return "IDLE"
	case .TRANSIT: return "TRANSIT"
	case .MINING: return "MINING"
	case .RETURNING: return "RETURNING"
	case .DEPOSITING: return "DEPOSITING"
	case .GUARDING: return "GUARDING"
	case .CONSTRUCTING: return "CONSTRUCTING"
	}
	return "IDLE"
}

parse_unit_type :: proc(s: string) -> (Unit_Type, bool) {
	switch s {
	case "MINING": return .MINING, true
	case "COMBAT": return .COMBAT, true
	case: return .MINING, false
	}
}

parse_unit_state :: proc(s: string) -> (Unit_State, bool) {
	switch s {
	case "IDLE": return .IDLE, true
	case "TRANSIT": return .TRANSIT, true
	case "MINING": return .MINING, true
	case "RETURNING": return .RETURNING, true
	case "DEPOSITING": return .DEPOSITING, true
	case "GUARDING": return .GUARDING, true
	case "CONSTRUCTING": return .CONSTRUCTING, true
	case: return .IDLE, false
	}
}

serialize_game_state :: proc(allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)

	fmt.sbprintf(&b, "# STARFALL COMMAND SAVE\n")
	fmt.sbprintf(&b, "VERSION 1\n")
	fmt.sbprintf(&b, "MINERALS %d\n", minerals)
	fmt.sbprintf(&b, "DRONE_SPEED_LEVEL %d\n", drone_speed_level)
	fmt.sbprintf(&b, "EARTH_RALLY %d\n", earth_rally)
	fmt.sbprintf(&b, "SELECTED_PLANET %d\n", selected_planet)
	fmt.sbprintf(&b, "BASE_BUILD %d %.4f\n", base_build_planet, base_build_progress)
	fmt.sbprintf(&b, "WAVES %.4f %d\n", enemy_wave_timer, wave_started ? 1 : 0)
	fmt.sbprintf(&b, "CAMERA_TARGET %.4f %.4f %.4f\n", camera_target.x, camera_target.y, camera_target.z)
	fmt.sbprintf(&b, "CAMERA_POS %.4f %.4f %.4f\n", camera.position.x, camera.position.y, camera.position.z)

	for p in 0..<PLANET_COUNT {
		fmt.sbprintf(&b, "BASE_COUNT %d %d\n", p, base_counts[p])
		for l in 0..<MAX_BASES {
			prod := production[p][l]
			if prod.active || prod.progress > 0 {
				fmt.sbprintf(&b, "PROD %d %d %s %.4f %d\n",
					p, l,
					unit_type_to_string(prod.kind),
					prod.progress,
					prod.active ? 1 : 0)
			}
		}
		for slot in 0..<pending_count[p] {
			fmt.sbprintf(&b, "PENDING %d %d %s\n",
				p, slot,
				unit_type_to_string(pending[p][slot]))
		}
		if refinery_built[p] || refinery_building[p] || refinery_progress[p] > 0 {
			fmt.sbprintf(&b, "REFINERY %d %d %d %.4f\n",
				p,
				refinery_built[p] ? 1 : 0,
				refinery_building[p] ? 1 : 0,
				refinery_progress[p])
		}
	}

	for s in 0..<SECTOR_COUNT {
		fmt.sbprintf(&b, "SECTOR %d %d %.4f %.4f %.4f %.4f\n",
			s,
			enemy_base_hp[s],
			combat_timer[s],
			miner_timer[s],
			base_timer[s],
			combat_vision_timer[s])
	}

	for p in 0..<PLANET_COUNT {
		intel := last_known_intel[p]
		if intel_recorded[p] {
			fmt.sbprintf(&b, "INTEL %d %d %d %d %d %d\n",
				p,
				1,
				intel.fighters,
				intel.miners,
				intel.base_hp,
				intel.unit_count)
			for i in 0..<intel.unit_count {
				u := intel.units[i]
				fmt.sbprintf(&b, "INTEL_UNIT %d %s %s %d\n",
					p,
					unit_type_to_string(u.kind),
					unit_state_to_string(u.state),
					u.enemy ? 1 : 0)
			}
		}
	}

	fmt.sbprintf(&b, "UNITS %d\n", unit_count)
	for i in 0..<unit_count {
		u := units[i]
		fmt.sbprintf(&b, "UNIT %s %s %.4f %.4f %.4f %d %d %d %d %.4f %.4f %d\n",
			unit_type_to_string(u.kind),
			unit_state_to_string(u.state),
			u.position.x, u.position.y, u.position.z,
			u.home_planet, u.affiliation, u.target_planet,
			u.enemy ? 1 : 0,
			u.progress, u.orbit_angle, u.squad)
	}

	return strings.to_string(b)
}

deserialize_game_state :: proc(content: string) -> bool {
	lines := strings.split_lines(content, context.temp_allocator)
	if len(lines) == 0 {
		return false
	}

	reset_world()
	base_counts = {}
	pending_count = {}

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}
		fields := strings.fields(trimmed, context.temp_allocator)
		if len(fields) < 2 {
			continue
		}

		switch fields[0] {
		case "MINERALS":
			if val, ok := strconv.parse_int(fields[1]); ok {
				minerals = val
			}
		case "DRONE_SPEED_LEVEL":
			if val, ok := strconv.parse_int(fields[1]); ok {
				drone_speed_level = val
			}
		case "EARTH_RALLY":
			if val, ok := strconv.parse_int(fields[1]); ok {
				earth_rally = val
			}
		case "SELECTED_PLANET":
			if val, ok := strconv.parse_int(fields[1]); ok {
				selected_planet = val
			}
		case "BASE_BUILD":
			if len(fields) >= 3 {
				p, _ := strconv.parse_int(fields[1])
				prog, _ := strconv.parse_f32(fields[2])
				base_build_planet = p
				base_build_progress = prog
			}
		case "REFINERY":
			if len(fields) >= 5 {
				p, _ := strconv.parse_int(fields[1])
				built := fields[2] == "1"
				bld := fields[3] == "1"
				prog, _ := strconv.parse_f32(fields[4])
				if p >= 0 && p < PLANET_COUNT {
					refinery_built[p] = built
					refinery_building[p] = bld
					refinery_progress[p] = prog
				}
			}
		case "WAVES":
			if len(fields) >= 3 {
				tm, _ := strconv.parse_f32(fields[1])
				st := fields[2] == "1"
				enemy_wave_timer = tm
				wave_started = st
			}
		case "CAMERA_TARGET":
			if len(fields) >= 4 {
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				camera_target = {x, y, z}
				camera.target = camera_target
			}
		case "CAMERA_POS":
			if len(fields) >= 4 {
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				camera.position = {x, y, z}
			}
		case "PLANET_MINERALS":
			// Ignored: planets have infinite minerals in Starfall Command.
		case "BASE_COUNT":
			if len(fields) >= 3 {
				p, _ := strconv.parse_int(fields[1])
				c, _ := strconv.parse_int(fields[2])
				if p >= 0 && p < PLANET_COUNT {
					base_counts[p] = c
				}
			}
		case "PROD":
			if len(fields) >= 6 {
				p, _ := strconv.parse_int(fields[1])
				l, _ := strconv.parse_int(fields[2])
				kind, _ := parse_unit_type(fields[3])
				prog, _ := strconv.parse_f32(fields[4])
				act := fields[5] == "1"
				if p >= 0 && p < PLANET_COUNT && l >= 0 && l < MAX_BASES {
					production[p][l] = Production{kind = kind, progress = prog, active = act}
				}
			}
		case "PENDING":
			if len(fields) >= 4 {
				p, _ := strconv.parse_int(fields[1])
				slot, _ := strconv.parse_int(fields[2])
				kind, _ := parse_unit_type(fields[3])
				if p >= 0 && p < PLANET_COUNT && slot >= 0 && slot < MAX_PENDING {
					pending[p][slot] = kind
					if slot + 1 > pending_count[p] {
						pending_count[p] = slot + 1
					}
				}
			}
		case "SECTOR":
			if len(fields) >= 6 {
				s, _ := strconv.parse_int(fields[1])
				hp, _ := strconv.parse_int(fields[2])
				ct, _ := strconv.parse_f32(fields[3])
				mt, _ := strconv.parse_f32(fields[4])
				bt, _ := strconv.parse_f32(fields[5])
				if s >= 0 && s < SECTOR_COUNT {
					enemy_base_hp[s] = hp
					combat_timer[s] = ct
					miner_timer[s] = mt
					base_timer[s] = bt
				}
				if len(fields) >= 7 {
					cvt, _ := strconv.parse_f32(fields[6])
					if s >= 0 && s < SECTOR_COUNT {
						combat_vision_timer[s] = cvt
					}
				}
			}
		case "INTEL":
			if len(fields) >= 7 {
				p, _ := strconv.parse_int(fields[1])
				rec := fields[2] == "1"
				f, _ := strconv.parse_int(fields[3])
				m, _ := strconv.parse_int(fields[4])
				hp, _ := strconv.parse_int(fields[5])
				if p >= 0 && p < PLANET_COUNT {
					intel_recorded[p] = rec
					last_known_intel[p].fighters = f
					last_known_intel[p].miners = m
					last_known_intel[p].base_hp = hp
					last_known_intel[p].unit_count = 0
				}
			}
		case "INTEL_UNIT":
			if len(fields) >= 5 {
				p, _ := strconv.parse_int(fields[1])
				kind, _ := parse_unit_type(fields[2])
				state, _ := parse_unit_state(fields[3])
				enemy := fields[4] == "1"
				if p >= 0 && p < PLANET_COUNT {
					cnt := last_known_intel[p].unit_count
					if cnt < INTEL_UNIT_CAP {
						last_known_intel[p].units[cnt] = Intel_Unit{kind = kind, state = state, enemy = enemy}
						last_known_intel[p].unit_count += 1
					}
				}
			}
		case "UNIT":
			if len(fields) >= 13 {
				kind, _ := parse_unit_type(fields[1])
				state, _ := parse_unit_state(fields[2])
				x, _ := strconv.parse_f32(fields[3])
				y, _ := strconv.parse_f32(fields[4])
				z, _ := strconv.parse_f32(fields[5])
				home, _ := strconv.parse_int(fields[6])
				affil, _ := strconv.parse_int(fields[7])
				target, _ := strconv.parse_int(fields[8])
				enemy := fields[9] == "1"
				prog, _ := strconv.parse_f32(fields[10])
				orbit, _ := strconv.parse_f32(fields[11])
				squad, _ := strconv.parse_int(fields[12])
				if unit_count < MAX_UNITS {
					units[unit_count] = Unit{
						kind = kind,
						state = state,
						position = {x, y, z},
						home_planet = home,
						affiliation = affil,
						target_planet = target,
						enemy = enemy,
						progress = prog,
						orbit_angle = orbit,
						squad = squad,
					}
					unit_count += 1
				}
			}
		}
	}

	camera.target = camera_target
	camera.up = {0, 1, 0}
	camera.fovy = 45
	camera.projection = .PERSPECTIVE
	in_start_menu = false
	game_paused = false
	controls_overlay_open = false
	return true
}

save_game :: proc(path: string = "") -> bool {
	content := serialize_game_state(context.temp_allocator)
	if len(path) > 0 {
		err := os.write_entire_file(path, content)
		return err == nil
	}
	err_root := os.write_entire_file("savegame.txt", content)
	exe_target := save_game_path("")
	if exe_target != "savegame.txt" {
		_ = os.write_entire_file(exe_target, content)
	}
	return err_root == nil
}

load_game :: proc(path: string = "") -> bool {
	target_path := path
	if len(target_path) == 0 {
		if os.exists("savegame.txt") {
			target_path = "savegame.txt"
		} else {
			target_path = save_game_path("")
		}
	}
	data, err := os.read_entire_file(target_path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return false
	}
	return deserialize_game_state(string(data))
}

delete_save_game :: proc(custom_path: string = "") -> bool {
	if len(custom_path) > 0 {
		if os.exists(custom_path) {
			return os.remove(custom_path) == nil
		}
		return false
	}
	removed := false
	if os.exists("savegame.txt") {
		if os.remove("savegame.txt") == nil {
			removed = true
		}
	}
	exe_target := save_game_path("")
	if exe_target != "savegame.txt" && os.exists(exe_target) {
		if os.remove(exe_target) == nil {
			removed = true
		}
	}
	return removed
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

// Dynamic, presence-based vision: a planet is visible while at least one
// player unit is physically near it — stationed in orbit, mining, guarding or
// passing within radius + 2.0. Earth is always lit. When the last player
// fighting drone at a planet is destroyed in combat, vision lingers for
// COMBAT_VISION_LINGER seconds before the planet falls back under fog.
has_vision :: proc(p: int) -> bool {
	if p < 0 || p >= SECTOR_COUNT { return false }
	if p == EARTH { return true }
	if combat_vision_timer[p] > 0 { return true }
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
