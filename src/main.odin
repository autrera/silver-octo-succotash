package main

import "core:math"
import "core:c"
import rl "vendor:raylib"

SCREEN_PANEL_WIDTH :: 330
MAX_BASES :: 5
MAX_UNITS :: 64
PLANET_COUNT :: 3

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

Unit :: struct {
	kind: Unit_Type,
	state: Unit_State,
	position: rl.Vector3,
	home_planet: int,
	affiliation: int,
	target_planet: int,
	progress: f32,
	orbit_angle: f32,
}

planets := [PLANET_COUNT]Planet{
	{name = "EARTH", position = {0, 0, 0}, radius = 3.0, color = rl.Color{45, 125, 220, 255}, minerals = 0},
	{name = "MARS", position = {15, 1, -5}, radius = 2.2, color = rl.Color{215, 80, 55, 255}, minerals = 80},
	{name = "LUNA", position = {-11, -1, -7}, radius = 1.25, color = rl.Color{150, 160, 175, 255}, minerals = 40},
}

units: [MAX_UNITS]Unit
unit_count: int
selected_units: [MAX_UNITS]bool
selected_planet := 0
minerals := 350
base_counts := [PLANET_COUNT]int{1, 0, 0}
production: [PLANET_COUNT][MAX_BASES]Production
base_build_progress: f32
base_build_planet := -1
camera: rl.Camera3D
camera_target := rl.Vector3{0, 0, 0}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 760, "STARFALL COMMAND // Planetary RTS Prototype")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	initialize_game()
	camera = rl.Camera3D{
		position = {18, 19, 22},
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

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{8, 12, 24, 255})
		draw_world()
		draw_inspector()
		rl.EndDrawing()
	}
}

initialize_game :: proc() {
	unit_count = 2
	units[0] = Unit{kind = .MINING, state = .IDLE, position = {3.8, 0.4, 0}, home_planet = 0, affiliation = 0, target_planet = 0}
	units[1] = Unit{kind = .COMBAT, state = .GUARDING, position = {0, 3.8, 0}, home_planet = 0, affiliation = 0, target_planet = 0, orbit_angle = 0.5}
}

update_camera :: proc(dt: f32) {
	direction := rl.Vector3{}
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { direction.z -= 1 }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { direction.z += 1 }
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { direction.x -= 1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { direction.x += 1 }
	mouse := rl.GetMousePosition()
	sw := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	if mouse.x < 18 { direction.x -= 1 }
	if mouse.x > sw - 18 { direction.x += 1 }
	if mouse.y < 18 { direction.z -= 1 }
	if mouse.y > f32(rl.GetScreenHeight()) - 18 { direction.z += 1 }
	if rl.Vector3Length(direction) > 0 {
		direction = rl.Vector3Normalize(direction)
		camera_target.x += direction.x * dt * 15
		camera_target.z += direction.z * dt * 15
	}
	zoom := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.MINUS) { zoom -= dt * 3 }
	if rl.IsKeyDown(.E) || rl.IsKeyDown(.EQUAL) { zoom += dt * 3 }
	camera.position.y -= zoom * 2.2
	camera.position.x -= zoom * 1.4
	camera.position.z -= zoom * 1.4
	camera.position.y = clamp_f32(camera.position.y, 8, 45)
	camera.position.x = camera_target.x + camera.position.y * 0.78
	camera.position.z = camera_target.z + camera.position.y * 0.9
	camera.target = camera_target
}

update_input :: proc() {
	mouse := rl.GetMousePosition()
	panel_x := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	if rl.IsMouseButtonPressed(.LEFT) {
		if mouse.x >= panel_x {
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
	if rl.CheckCollisionPointRec(mouse, {panel_x + 18, orders_y, 294, 30}) {
		queue_unit(.MINING)
		return
	}
	if rl.CheckCollisionPointRec(mouse, {panel_x + 18, orders_y + 34, 294, 30}) {
		queue_unit(.COMBAT)
		return
	}
	row_y := production_orders_y() + 102
	for i := 0; i < unit_count; i += 1 {
		if units[i].affiliation != selected_planet || units[i].kind != .MINING { continue }
		if rl.CheckCollisionPointRec(mouse, {panel_x + 18, f32(row_y), 294, 27}) {
			if !ctrl_down() { clear_selection(); selected_units[i] = true } else { selected_units[i] = !selected_units[i] }
			return
		}
		row_y += 30
	}
	row_y += 27
	for i := 0; i < unit_count; i += 1 {
		if units[i].affiliation != selected_planet || units[i].kind != .COMBAT { continue }
		if rl.CheckCollisionPointRec(mouse, {panel_x + 18, f32(row_y), 294, 27}) {
			if !ctrl_down() { clear_selection(); selected_units[i] = true } else { selected_units[i] = !selected_units[i] }
			return
		}
		row_y += 30
	}
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
	if minerals < cost { return }
	for i := 0; i < base_counts[selected_planet]; i += 1 {
		if !production[selected_planet][i].active {
			minerals -= cost
			production[selected_planet][i] = Production{kind = kind, active = true, progress = 0}
			return
		}
	}
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
				line.active = false
				line.progress = 0
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
	state := Unit_State.IDLE
	if kind == .COMBAT { state = .GUARDING }
	units[unit_count] = Unit{kind = kind, state = state, position = pos, home_planet = planet, affiliation = planet, target_planet = planet, orbit_angle = angle}
	unit_count += 1
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
			update_miner(u, dt)
		}
	}
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

update_miner :: proc(u: ^Unit, dt: f32) {
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
			planets[u.target_planet].minerals = max_int(planets[u.target_planet].minerals - 10, 0)
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
			minerals += 10
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
		if p == selected_planet { rl.DrawCircle3D(planet.position, planet.radius + 0.35, {0, 1, 0}, 90, rl.GOLD) }
	}
	for i := 0; i < unit_count; i += 1 {
		u := units[i]
		if u.kind == .MINING {
			rl.DrawCubeV(u.position, {0.55, 0.55, 0.55}, rl.ORANGE)
		} else {
			rl.DrawCubeV(u.position, {0.7, 0.32, 0.7}, rl.RED)
		}
		if selected_units[i] { draw_selection_ring(u.position, 0.78) }
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
			rl.DrawText(planets[p].name, c.int(pos.x - 28), c.int(pos.y - planets[p].radius * 5 - 14), 14, rl.WHITE)
		}
	}
	status := rl.TextFormat("FPS %d   RIGHT CLICK: GROUP ORDER   CTRL+CLICK: MULTI-SELECT", rl.GetFPS())
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
	rl.DrawText(rl.TextFormat("BASES: %d / 5", base_counts[selected_planet]), c.int(x + 18), 76, 16, rl.WHITE)

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
	rl.DrawText("PRODUCTION ORDERS", c.int(x + 18), c.int(orders_y - 16), 13, rl.Color{130, 150, 175, 255})
	draw_button({x + 18, f32(orders_y), 294, 30}, "Build Mining Drone (50 / 3s)", rl.Color{38, 72, 75, 255})
	draw_button({x + 18, f32(orders_y + 34), 294, 30}, "Build Combat Drone (125 / 5s)", rl.Color{78, 48, 55, 255})

	rl.DrawText("MINING DRONES", c.int(x + 18), c.int(orders_y + 82), 13, rl.ORANGE)
	y := orders_y + 102
	for i := 0; i < unit_count; i += 1 {
		if units[i].affiliation == selected_planet && units[i].kind == .MINING {
			draw_unit_row(i, y, x)
			y += 30
		}
	}
	rl.DrawText("FIGHTING DRONES", c.int(x + 18), c.int(y + 5), 13, rl.RED)
	y += 27
	for i := 0; i < unit_count; i += 1 {
		if units[i].affiliation == selected_planet && units[i].kind == .COMBAT {
			draw_unit_row(i, y, x)
			y += 30
		}
	}
	if h > 700 { rl.DrawText(rl.TextFormat("SELECTED UNITS: %d", selection_count()), c.int(x + 18), rl.GetScreenHeight() - 34, 13, rl.GOLD) }
}

production_orders_y :: proc() -> int {
	return 246 + max_int(base_counts[selected_planet] - 1, 0) * 32
}

draw_unit_row :: proc(index: int, y: int, x: f32) {
	selected_color := rl.Color{61, 78, 106, 255}
	if selected_units[index] { selected_color = rl.Color{130, 103, 35, 255} }
	rl.DrawRectangle(c.int(x + 18), c.int(y), 294, 27, selected_color)
	rl.DrawRectangleLines(c.int(x + 18), c.int(y), 294, 27, rl.Color{95, 115, 140, 255})
	kind := "MINER"
	if units[index].kind == .COMBAT { kind = "COMBAT" }
	rl.DrawText(rl.TextFormat("%s-%02d", kind, index + 1), c.int(x + 28), c.int(y + 6), 12, rl.WHITE)
	rl.DrawText(state_name(units[index].state), c.int(x + 142), c.int(y + 6), 11, rl.GOLD)
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
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{100, 125, 145, 255})
	rl.DrawText(label, c.int(rect.x + 9), c.int(rect.y + 8), 11, rl.WHITE)
}

draw_progress :: proc(rect: rl.Rectangle, value: f32, color: rl.Color) {
	v := clamp_f32(value, 0, 1)
	rl.DrawRectangleRec(rect, rl.Color{35, 43, 58, 255})
	rl.DrawRectangle(c.int(rect.x), c.int(rect.y), c.int(rect.width * v), c.int(rect.height), color)
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
