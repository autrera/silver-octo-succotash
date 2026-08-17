package main

import "core:math"
import "core:c"
import rl "vendor:raylib"

SCREEN_PANEL_WIDTH :: 330
MAX_BASES :: 5
MAX_UNITS :: 64
PLANET_COUNT :: 2

Unit_Type :: enum {MINING, COMBAT}
Unit_State :: enum {IDLE, TRANSIT, MINING, RETURNING, DEPOSITING, GUARDING}

Planet :: struct {
	name: cstring,
	position: rl.Vector3,
	radius: f32,
	color: rl.Color,
	minerals: int,
}

Production :: struct {
	kind: Unit_Type,
	progress: f32,
	active: bool,
}

MAX_PENDING :: 25
TILE_SIZE :: 52
TILE_GAP :: 6
TILES_PER_ROW :: 5
DRILL_CAP :: 50

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
}

planets := [PLANET_COUNT]Planet{
	{name = "EARTH", position = {0, 0, 0}, radius = 3.0, color = rl.Color{45, 125, 220, 255}, minerals = 80},
	{name = "MARS", position = {15, 1, -5}, radius = 2.2, color = rl.Color{215, 80, 55, 255}, minerals = 80},
}

units: [MAX_UNITS]Unit
unit_count: int
selected_units: [MAX_UNITS]bool
selected_planet := 0
minerals := 350
base_counts := [PLANET_COUNT]int{1, 1}
production: [PLANET_COUNT][MAX_BASES]Production
pending: [PLANET_COUNT][MAX_PENDING]Unit_Type
pending_count: [PLANET_COUNT]int
base_build_progress: f32
base_build_planet := -1
camera: rl.Camera3D
camera_target := rl.Vector3{7.5, 0, -2.5}

WAVE_INTERVAL :: 120
WAVE_SIZE :: 5
enemy_wave_timer: f32
mars_combat_timer: f32
mars_miner_timer: f32

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 760, "STARFALL COMMAND // Planetary RTS Prototype")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	initialize_game()
	camera = rl.Camera3D{
		position = {camera_target.x, 100, camera_target.z + 100},
		target = camera_target,
		up = {0, 1, 0},
		fovy = 45,
		projection = .PERSPECTIVE,
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		update_camera(dt)
		update_input()
		update_production(dt)
		update_units(dt)
		update_enemy_waves(dt)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{8, 12, 24, 255})
		draw_world()
		draw_inspector()
		rl.EndDrawing()
	}
}

initialize_game :: proc() {
	unit_count = 2
	units[0] = Unit{kind = .MINING, state = .MINING, position = {3.8, 0.4, 0}, home_planet = 0, affiliation = 0, target_planet = 0}
	units[1] = Unit{kind = .COMBAT, state = .GUARDING, position = {0, 3.8, 0}, home_planet = 0, affiliation = 0, target_planet = 0, orbit_angle = 0.5}
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
	zoom_y = clamp_f32(zoom_y, 15, 200)
	camera.position.x = camera_target.x
	camera.position.y = zoom_y
	camera.position.z = camera_target.z + camera.position.y * 1.0
	camera.target = camera_target
	camera.up = {0, 1, 0}
}

update_input :: proc() {
	// Build shortcuts use the same validation path as the inspector buttons.
	if rl.IsKeyPressed(.M) { queue_unit(.MINING) }
	if rl.IsKeyPressed(.C) { queue_unit(.COMBAT) }
	// Debug: force the next enemy wave immediately (verify combat without waiting 2 minutes).
	if rl.IsKeyPressed(.N) { spawn_enemy_wave() }
	mouse := rl.GetMousePosition()
	panel_x := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	if rl.IsMouseButtonPressed(.LEFT) {
		if mouse.x >= panel_x {
			// Sidebar clicks are consumed here and never reach world selection.
			handle_inspector_click(mouse, panel_x)
		} else {
			if planet := pick_planet(mouse); planet >= 0 {
				selected_planet = planet
			} else if !ctrl_down() {
				clear_selection()
			}
		}
	}
	if rl.IsMouseButtonPressed(.RIGHT) && mouse.x < panel_x {
		if planet := pick_planet(mouse); planet >= 0 {
			issue_group_order(planet)
		}
	}
}

ctrl_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}

clear_selection :: proc() {
	for i := 0; i < MAX_UNITS; i += 1 { selected_units[i] = false }
}

handle_inspector_click :: proc(mouse: rl.Vector2, panel_x: f32) {
	// The two production buttons and base button are deliberately ordinary rectangles,
	// keeping the inspector usable even when raygui styles are unavailable.
	if rl.CheckCollisionPointRec(mouse, {panel_x + 18, 106, 294, 32}) {
		start_base_construction()
		return
	}
	orders_y := f32(production_orders_y())
	if rl.CheckCollisionPointRec(mouse, {panel_x + 18, orders_y, 141, 34}) {
		queue_unit(.MINING)
		return
	}
	if rl.CheckCollisionPointRec(mouse, {panel_x + 171, orders_y, 141, 34}) {
		queue_unit(.COMBAT)
		return
	}
	if click_unit_tiles(mouse, panel_x, .MINING) || click_unit_tiles(mouse, panel_x, .COMBAT) { return }
	if !ctrl_down() { clear_selection() }
}

click_unit_tiles :: proc(mouse: rl.Vector2, panel_x: f32, kind: Unit_Type) -> bool {
	ordinal := 0
	for i := 0; i < unit_count; i += 1 {
		if !unit_in_roster(i, kind) { continue }
		if rl.CheckCollisionPointRec(mouse, unit_tile_rect(panel_x, unit_tile_y(kind), ordinal)) {
			if !ctrl_down() { clear_selection(); selected_units[i] = true } else { selected_units[i] = !selected_units[i] }
			return true
		}
		ordinal += 1
	}
	return false
}

start_base_construction :: proc() {
	if base_counts[selected_planet] >= MAX_BASES || base_build_planet >= 0 || minerals < 200 { return }
	minerals -= 200
	base_build_planet = selected_planet
	base_build_progress = 0
}

queue_unit :: proc(kind: Unit_Type) {
	cost := 50
	if kind == .COMBAT { cost = 125 }
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

update_production :: proc(dt: f32) {
	if base_build_planet >= 0 {
		base_build_progress += dt
		if base_build_progress >= 6 {
			base_counts[base_build_planet] += 1
			base_build_planet = -1
			base_build_progress = 0
		}
	}
	for p := 0; p < PLANET_COUNT; p += 1 {
		for b := 0; b < base_counts[p]; b += 1 {
			line := &production[p][b]
			if !line.active { continue }
			build_time: f32 = 3.0
			if line.kind == .COMBAT { build_time = 5.0 }
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
	// Mining drones work their home planet by default: Earth drones mine Earth.
	affiliation := planet
	units[unit_count] = Unit{kind = kind, state = state, position = pos, home_planet = planet, affiliation = affiliation, target_planet = target_planet, orbit_angle = angle}
	unit_count += 1
}

// Every 2 minutes a wave of WAVE_SIZE enemy fighters arrives at Mars to attack it.
// Combat pacing at Mars: while both sides have fighters there, one drone on each
// side is destroyed per second (5v5 lasts ~5s, a 1:1 attrition trade). With no
// player defenders left, enemies destroy one Mars mining drone every 2s.
update_enemy_waves :: proc(dt: f32) {
	enemy_wave_timer += dt
	if enemy_wave_timer >= WAVE_INTERVAL {
		spawn_enemy_wave()
		enemy_wave_timer = 0
	}
	defenders, attackers := mars_combatants()
	if attackers > 0 && defenders > 0 {
		mars_combat_timer += dt
		for mars_combat_timer >= 1 {
			mars_combat_timer -= 1
			if !kill_player_defender() || !kill_enemy_attacker() { break }
		}
	} else if attackers > 0 {
		mars_combat_timer = 0
		mars_miner_timer += dt
		for mars_miner_timer >= 2 {
			mars_miner_timer -= 2
			if !kill_mars_miner() { break }
		}
	} else {
		mars_combat_timer = 0
		mars_miner_timer = 0
	}
}

spawn_enemy_wave :: proc() {
	spawn_count := min(WAVE_SIZE, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	spawn_pos := planets[1].position + rl.Vector3{40, 0.5, -25}
	for i in 0..<spawn_count {
		angle := f32(i) * 1.26
		pos := spawn_pos + rl.Vector3{math.cos(angle) * 1.5, 0, math.sin(angle) * 1.5}
		units[unit_count] = Unit{
			kind = .COMBAT, state = .TRANSIT, position = pos,
			home_planet = 1, affiliation = 1, target_planet = 1,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

// Counts of guarding fighters at Mars: player defenders vs enemy attackers.
mars_combatants :: proc() -> (defenders, attackers: int) {
	for i in 0..<unit_count {
		u := &units[i]
		if u.kind != .COMBAT || u.state != .GUARDING || u.affiliation != 1 { continue }
		if u.enemy { attackers += 1 } else { defenders += 1 }
	}
	return
}

kill_player_defender :: proc() -> bool {
	for i in 0..<unit_count {
		u := &units[i]
		if u.kind == .COMBAT && !u.enemy && u.state == .GUARDING && u.affiliation == 1 {
			remove_unit_at(i)
			return true
		}
	}
	return false
}

kill_enemy_attacker :: proc() -> bool {
	for i in 0..<unit_count {
		u := &units[i]
		if u.kind == .COMBAT && u.enemy && u.state == .GUARDING && u.affiliation == 1 {
			remove_unit_at(i)
			return true
		}
	}
	return false
}

kill_mars_miner :: proc() -> bool {
	for i in 0..<unit_count {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == 1 {
			remove_unit_at(i)
			return true
		}
	}
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

issue_group_order :: proc(planet: int) {
	for i := 0; i < unit_count; i += 1 {
		if !selected_units[i] { continue }
		units[i].target_planet = planet
		units[i].affiliation = planet
		units[i].progress = 0
		if units[i].kind == .MINING {
			units[i].state = .TRANSIT
		} else {
			if distance(units[i].position, planets[planet].position) < planets[planet].radius + 1.5 {
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

// Minerals delivered per 3s mining cycle at a planet. Earth is deliberately
// poor: drones there mine at 10% of the Mars rate (1 vs 10 per cycle).
mining_rate :: proc(planet: int) -> int {
	if planet == 0 { return 1 }
	return 10
}

// Global hard cap on earning miners: only the first DRILL_CAP mining drones
// (by unit index) deposit minerals. Extra drones still mine and deplete the
// planet but pay out 0, so income never exceeds the cap.
// ponytail: index-order cap, revisit if a per-planet or weighted split is wanted
is_effective_miner :: proc(index: int) -> bool {
	if units[index].kind != .MINING { return false }
	rank := 0
	for j := 0; j < index; j += 1 {
		if units[j].kind == .MINING { rank += 1 }
	}
	return rank < DRILL_CAP
}

// Minerals per second delivered by a planet's effective mining drones
// (rate per 3s cycle, DRILL_CAP already applied).
planet_mps :: proc(planet: int) -> f32 {
	effective := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].kind == .MINING && units[i].target_planet == planet && is_effective_miner(i) {
			effective += 1
		}
	}
	return f32(effective) * f32(mining_rate(planet)) / 3.0
}

update_combat :: proc(u: ^Unit, dt: f32) {
	if u.state == .TRANSIT {
		target := planets[u.target_planet].position
		travel(u, target, 10 * dt)
		if distance(u.position, target) <= planets[u.target_planet].radius + 1.4 {
			u.state = .GUARDING
			u.orbit_angle = 0
			center := planets[u.target_planet].position
			u.position = {center.x + math.cos(u.orbit_angle) * (planets[u.target_planet].radius + 1.5), center.y + 1.0, center.z + math.sin(u.orbit_angle) * (planets[u.target_planet].radius + 1.5)}
		}
	} else if u.state == .GUARDING {
		u.orbit_angle += dt * 0.9
		center := planets[u.affiliation].position
		u.position = {center.x + math.cos(u.orbit_angle) * (planets[u.affiliation].radius + 1.5), center.y + 1.0, center.z + math.sin(u.orbit_angle) * (planets[u.affiliation].radius + 1.5)}
	}
}

update_miner :: proc(u: ^Unit, index: int, dt: f32) {
	target := planets[u.target_planet].position
	earth := planets[0].position
	switch u.state {
	case .TRANSIT:
		travel(u, target, 7 * dt)
		if distance(u.position, target) <= planets[u.target_planet].radius + 1.0 {
			u.position = target
			u.state = .MINING
			u.progress = 0
		}
	case .MINING:
		u.progress += dt
		if u.progress >= 3 {
			planets[u.target_planet].minerals = max_int(planets[u.target_planet].minerals - mining_rate(u.target_planet), 0)
			u.progress = 0
			u.state = .RETURNING
		}
	case .RETURNING:
		travel(u, earth, 7 * dt)
		if distance(u.position, earth) <= planets[0].radius + 1.0 {
			u.position = earth
			u.state = .DEPOSITING
			u.progress = 0
		}
	case .DEPOSITING:
		u.progress += dt
		if u.progress >= 0.5 {
			if is_effective_miner(index) { minerals += mining_rate(u.target_planet) }
			u.progress = 0
			u.state = .TRANSIT
		}
	case .IDLE, .GUARDING:
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

draw_world :: proc() {
	viewport_w := rl.GetScreenWidth() - SCREEN_PANEL_WIDTH
	rl.BeginMode3D(camera)
	rl.DrawGrid(40, 1)
	rl.DrawLine3D({-40, 0, 0}, {40, 0, 0}, rl.Color{40, 45, 65, 255})
	for p in 0..<PLANET_COUNT {
		planet := planets[p]
		rl.DrawSphere(planet.position, planet.radius, planet.color)
		rl.DrawSphereWires(planet.position, planet.radius + 0.04, 12, 16, rl.Color{220, 230, 245, 180})
		if p == selected_planet {
			rl.DrawCircle3D(planet.position, planet.radius + 0.35, {0, 1, 0}, 90, rl.GOLD)
			rl.DrawCircle3D(planet.position, planet.radius + 0.55, {0, 1, 0}, 90, rl.SKYBLUE)
		}
	}
	for i := 0; i < unit_count; i += 1 {
		u := units[i]
		if u.kind == .MINING {
			rl.DrawCubeV(u.position, {0.55, 0.55, 0.55}, rl.ORANGE)
		} else if u.state != .GUARDING {
			// Transit combat drones render 1:1; guarding crowds are representational below.
			draw_fighter(u.position, u.enemy)
		}
		if selected_units[i] { draw_selection_ring(u.position, 0.78) }
	}
	// Guarding combat drones render representationally: one cube per 10 drones
	// (ceil(count / 10)), so fleets stay readable. Rosters, tracking and
	// selection still use the real unit list.
	for p in 0..<PLANET_COUNT {
		visible := 0
		for i := 0; i < unit_count; i += 1 {
			u := units[i]
			if u.kind == .COMBAT && u.affiliation == p && u.state == .GUARDING { visible += 1 }
		}
		visible = (visible + 9) / 10
		drawn := 0
		for i := 0; i < unit_count; i += 1 {
			u := units[i]
			if u.kind != .COMBAT || u.affiliation != p || u.state != .GUARDING { continue }
			if drawn >= visible { break }
			draw_fighter(u.position, u.enemy)
			drawn += 1
		}
	}
	// Lasers: while both sides have fighters engaged at Mars, draw thin beams from
	// every fighter to its nearest opposite.
	defenders, attackers := mars_combatants()
	if attackers > 0 && defenders > 0 {
		for a := 0; a < unit_count; a += 1 {
			if !mars_fighter(&units[a], true) { continue }
			rl.DrawLine3D(units[a].position, nearest_mars_fighter(a, false), rl.RED)
		}
		for d := 0; d < unit_count; d += 1 {
			if !mars_fighter(&units[d], false) { continue }
			rl.DrawLine3D(units[d].position, nearest_mars_fighter(d, true), rl.SKYBLUE)
		}
	}
	// The transit lines make dispatches visibly physical rather than teleporting.
	for i := 0; i < unit_count; i += 1 {
		if units[i].state == .TRANSIT { rl.DrawLine3D(units[i].position, planets[units[i].target_planet].position, rl.Color{255, 210, 80, 100}) }
	}
	rl.EndMode3D()

	// Overlay labels are anchored to the 3D positions and stay readable while panning.
	for p in 0..<PLANET_COUNT {
		pos := rl.GetWorldToScreen(planets[p].position, camera)
		if pos.x < f32(viewport_w) && pos.x > 0 && pos.y > 0 && pos.y < f32(rl.GetScreenHeight()) {
			label := planets[p].name
			if p == selected_planet {
				w := rl.MeasureText(label, 14)
				rl.DrawRectangle(c.int(pos.x) - w/2 - 6, c.int(pos.y - planets[p].radius * 5 - 18), w + 12, 22, rl.Color{110, 85, 25, 230})
			}
			rl.DrawText(label, c.int(pos.x - 28), c.int(pos.y - planets[p].radius * 5 - 14), 14, p == selected_planet ? rl.GOLD : rl.WHITE)
		}
	}
	status := rl.TextFormat("FPS %d   RIGHT CLICK: GROUP ORDER   CTRL+CLICK: MULTI-SELECT   N: ENEMY WAVE (DEBUG)", rl.GetFPS())
	rl.DrawRectangle(12, 12, 230, 34, rl.Color{20, 32, 45, 235})
	rl.DrawText(rl.TextFormat("◆ MINERALS: %d", minerals), 22, 20, 18, rl.GOLD)
	rl.DrawText(status, 18, rl.GetScreenHeight() - 28, 14, rl.Color{155, 170, 195, 255})
}

draw_inspector :: proc() {
	x := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	h := f32(rl.GetScreenHeight())
	rl.DrawRectangle(c.int(x), 0, SCREEN_PANEL_WIDTH, rl.GetScreenHeight(), rl.Color{16, 22, 38, 255})
	rl.DrawRectangle(c.int(x), 0, 3, rl.GetScreenHeight(), rl.GOLD)
	rl.DrawText("PLANET INSPECTOR", c.int(x + 18), 18, 20, rl.WHITE)
	planet := &planets[selected_planet]
	rl.DrawText(rl.TextFormat("%s  //  MINERALS %03d", planet.name, planet.minerals), c.int(x + 18), 48, 15, rl.SKYBLUE)
	rl.DrawText("BASES", c.int(x + 18), 76, 14, rl.WHITE)
	for pip := 0; pip < MAX_BASES; pip += 1 {
		pip_color := rl.Color{43, 51, 64, 255}
		if pip < base_counts[selected_planet] { pip_color = rl.Color{55, 190, 105, 255} }
		pip_rect := rl.Rectangle{x + 76 + f32(pip * 22), 75, 18, 18}
		rl.DrawRectangleRec(pip_rect, pip_color)
		rl.DrawRectangleLinesEx(pip_rect, 1, rl.Color{90, 105, 125, 255})
	}
	rl.DrawText(rl.TextFormat("MPS %.1f", planet_mps(selected_planet)), c.int(x + 236), 79, 13, rl.SKYBLUE)

	base_button := rl.Rectangle{x + 18, 106, 294, 32}
	rl.DrawRectangleRec(base_button, rl.Color{35, 56, 78, 255})
	rl.DrawRectangleLinesEx(base_button, 1, rl.Color{85, 125, 155, 255})
	if base_build_planet == selected_planet {
		rl.DrawText(rl.TextFormat("COMMAND BASE  %3.1fs", 6 - base_build_progress), c.int(x + 28), 115, 14, rl.GOLD)
	} else {
		rl.DrawText("Construct Command Base (200 Minerals)", c.int(x + 28), 115, 14, rl.WHITE)
	}
	if base_build_planet == selected_planet { draw_progress({x + 18, 142, 294, 7}, base_build_progress / 6, rl.GOLD) }

	rl.DrawText("PRODUCTION LINES", c.int(x + 18), 166, 13, rl.Color{130, 150, 175, 255})
	for b := 0; b < base_counts[selected_planet]; b += 1 {
		line := production[selected_planet][b]
		y := f32(180 + b * 30)
		if line.active {
			name := "MINING DRONE"
			total := f32(3)
			if line.kind == .COMBAT { name = "COMBAT DRONE"; total = 5 }
			rl.DrawText(rl.TextFormat("BASE %d  %s", b + 1, name), c.int(x + 18), c.int(y), 12, rl.WHITE)
			draw_progress({x + 18, y + 17, 185, 7}, line.progress / total, rl.SKYBLUE)
		} else {
			rl.DrawText(rl.TextFormat("BASE %d  READY", b + 1), c.int(x + 18), c.int(y), 12, rl.Color{90, 110, 135, 255})
		}
	}

	orders_y := production_orders_y()
	rl.DrawText("BUILD", c.int(x + 18), c.int(orders_y - 16), 13, rl.Color{130, 150, 175, 255})
	draw_button({x + 18, f32(orders_y), 141, 34}, "[M] MINER  (50)", rl.Color{38, 72, 75, 255})
	draw_button({x + 171, f32(orders_y), 141, 34}, "[C] COMBAT (125)", rl.Color{78, 48, 55, 255})

	queue_y := orders_y + 45
	queue_capacity := base_counts[selected_planet] * MAX_BASES
	queue_total := queued_count(selected_planet)
	rl.DrawText(rl.TextFormat("BUILD QUEUE  (%d/%d)", queue_total, queue_capacity), c.int(x + 18), c.int(queue_y), 12, rl.Color{130, 150, 175, 255})
	for slot := 0; slot < queue_capacity; slot += 1 {
		row := slot / MAX_BASES
		column := slot % MAX_BASES
		rect := rl.Rectangle{x + 18 + f32(column * 22), f32(queue_y + 17 + row * 22), 18, 18}
		queued := slot < queue_total
		kind := Unit_Type.MINING
		if queued { kind = queue_kind_at(selected_planet, slot) }
		draw_queue_slot(rect, queued, kind)
	}

	rl.DrawText("MINING DRONES", c.int(x + 18), c.int(unit_tile_y(.MINING) - 18), 13, rl.ORANGE)
	for i := 0; i < unit_count; i += 1 {
		if unit_in_roster(i, .MINING) { draw_unit_tile(i, x, roster_ordinal(i, .MINING)) }
	}
	rl.DrawText("FIGHTING DRONES", c.int(x + 18), c.int(unit_tile_y(.COMBAT) - 18), 13, rl.SKYBLUE)
	for i := 0; i < unit_count; i += 1 {
		if unit_in_roster(i, .COMBAT) { draw_unit_tile(i, x, roster_ordinal(i, .COMBAT)) }
	}
	if h > 700 { rl.DrawText(rl.TextFormat("SELECTED UNITS: %d", selection_count()), c.int(x + 18), rl.GetScreenHeight() - 34, 13, rl.GOLD) }
}

production_orders_y :: proc() -> int {
	return 246 + max_int(base_counts[selected_planet] - 1, 0) * 30
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
	mining_rows := (roster_count(.MINING) + TILES_PER_ROW - 1) / TILES_PER_ROW
	y := production_orders_y() + 116 + (base_counts[selected_planet] - 1) * 22
	if kind == .COMBAT { y += 26 + mining_rows * (TILE_SIZE + TILE_GAP) }
	return y
}

roster_ordinal :: proc(index: int, kind: Unit_Type) -> int {
	ordinal := 0
	for i := 0; i < index; i += 1 { if unit_in_roster(i, kind) { ordinal += 1 } }
	return ordinal
}

unit_tile_rect :: proc(x: f32, y: int, ordinal: int) -> rl.Rectangle {
	column := ordinal % TILES_PER_ROW
	row := ordinal / TILES_PER_ROW
	return rl.Rectangle{x + 18 + f32(column * (TILE_SIZE + TILE_GAP)), f32(y + row * (TILE_SIZE + TILE_GAP)), TILE_SIZE, TILE_SIZE}
}

draw_unit_tile :: proc(index: int, x: f32, ordinal: int) {
	rect := unit_tile_rect(x, unit_tile_y(units[index].kind), ordinal)
	fill := rl.Color{38, 55, 78, 255}
	border := rl.Color{91, 113, 140, 255}
	if selected_units[index] { fill = rl.Color{123, 94, 26, 255}; border = rl.GOLD }
	rl.DrawRectangleRec(rect, fill)
	rl.DrawRectangleLinesEx(rect, 2, border)
	symbol: cstring = "[M]"
	accent := rl.ORANGE
	if units[index].kind == .COMBAT { symbol = "[C]"; accent = rl.SKYBLUE }
	rl.DrawText(symbol, c.int(rect.x + 13), c.int(rect.y + 7), 16, accent)
	rl.DrawText(rl.TextFormat("#%d", ordinal + 1), c.int(rect.x + 16), c.int(rect.y + 28), 11, rl.WHITE)
	rl.DrawCircle(c.int(rect.x + rect.width - 8), c.int(rect.y + 8), 4, state_color(units[index].state))
}

// Player fighters are blue, enemy fighters red.
draw_fighter :: proc(position: rl.Vector3, enemy: bool) {
	color := rl.SKYBLUE
	if enemy { color = rl.RED }
	rl.DrawCubeV(position, {0.7, 0.32, 0.7}, color)
}

// True when the unit is a guarding fighter stationed at Mars on the given side.
mars_fighter :: proc(u: ^Unit, enemy_side: bool) -> bool {
	return u.kind == .COMBAT && u.state == .GUARDING && u.affiliation == 1 && u.enemy == enemy_side
}

nearest_mars_fighter :: proc(index: int, enemy_side: bool) -> rl.Vector3 {
	best := planets[1].position
	best_d := f32(1e9)
	for j := 0; j < unit_count; j += 1 {
		if j == index || !mars_fighter(&units[j], enemy_side) { continue }
		if dd := distance(units[index].position, units[j].position); dd < best_d {
			best_d = dd
			best = units[j].position
		}
	}
	return best
}

draw_selection_ring :: proc(center: rl.Vector3, radius: f32) {
	segments :: 24
	for segment := 0; segment < segments; segment += 1 {
		a := f32(segment) * 2 * math.PI / f32(segments)
		b := f32(segment + 1) * 2 * math.PI / f32(segments)
		rl.DrawLine3D(
			{center.x + math.cos(a) * radius, center.y - 0.25, center.z + math.sin(a) * radius},
			{center.x + math.cos(b) * radius, center.y - 0.25, center.z + math.sin(b) * radius},
			rl.YELLOW,
		)
	}
}

draw_button :: proc(rect: rl.Rectangle, label: cstring, color: rl.Color) {
	rl.DrawRectangleRec(rect, color)
	border := rl.Color{100, 125, 145, 255}
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) { border = rl.GOLD }
	rl.DrawRectangleLinesEx(rect, 1, border)
	rl.DrawText(label, c.int(rect.x + 9), c.int(rect.y + 8), 11, rl.WHITE)
}

draw_queue_slot :: proc(rect: rl.Rectangle, queued: bool, kind: Unit_Type) {
	color := rl.Color{39, 47, 60, 255}
	border := rl.Color{80, 95, 115, 255}
	symbol: cstring = ""
	if queued {
		color = rl.Color{42, 135, 88, 255}
		if kind == .COMBAT { color = rl.Color{155, 108, 35, 255} }
		border = rl.Color{190, 205, 180, 255}
		symbol = "⛏"
		if kind == .COMBAT { symbol = "⚔" }
	}
	rl.DrawRectangleRec(rect, color)
	rl.DrawRectangleLinesEx(rect, 1, border)
	if queued { rl.DrawText(symbol, c.int(rect.x + 3), c.int(rect.y + 1), 13, rl.WHITE) }
}

draw_progress :: proc(rect: rl.Rectangle, value: f32, color: rl.Color) {
	v := clamp_f32(value, 0, 1)
	rl.DrawRectangleRec(rect, rl.Color{35, 43, 58, 255})
	rl.DrawRectangle(c.int(rect.x), c.int(rect.y), c.int(rect.width * v), c.int(rect.height), color)
}

state_color :: proc(state: Unit_State) -> rl.Color {
	switch state {
	case .IDLE: return rl.GRAY
	case .TRANSIT: return rl.SKYBLUE
	case .MINING: return rl.GREEN
	case .RETURNING: return rl.ORANGE
	case .DEPOSITING: return rl.GOLD
	case .GUARDING: return rl.RED
	}
	return rl.WHITE
}

state_name :: proc(state: Unit_State) -> cstring {
	switch state {
	case .IDLE: return "IDLE"
	case .TRANSIT: return "IN TRANSIT"
	case .MINING: return "MINING"
	case .RETURNING: return "RETURNING"
	case .DEPOSITING: return "DEPOSITING"
	case .GUARDING: return "GUARDING"
	}
	return "UNKNOWN"
}

selection_count :: proc() -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if selected_units[i] { count += 1 } }
	return count
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

distance :: proc(a, b: rl.Vector3) -> f32 {
	dx := a.x - b.x; dy := a.y - b.y; dz := a.z - b.z
	return math.sqrt(dx*dx + dy*dy + dz*dz)
}

clamp_f32 :: proc(value, low, high: f32) -> f32 {
	if value < low { return low }
	if value > high { return high }
	return value
}

max_int :: proc(a, b: int) -> int { if a > b { return a }; return b }
