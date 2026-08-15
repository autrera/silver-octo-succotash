package main

import "core:math"
import rl "vendor:raylib"

MAX_PLANETS :: 2
MAX_BASES :: 5
MAX_UNITS :: 64

Planet_Id :: enum { EARTH, MARS }
Unit_Kind :: enum { STANDARD, FAST, COMBAT }
Unit_Mode :: enum { IDLE, MINING, RETURNING, DEPOSITING, MOVING, GUARDING }

Planet :: struct {
	name:       cstring,
	position:   rl.Vector3,
	radius:     f32,
	color:      rl.Color,
	bases:      int,
	base_timer: f32,
	jobs:       [MAX_BASES]Build_Job,
}

Build_Job :: struct {
	active:    bool,
	kind:      Unit_Kind,
	remaining: f32,
	total:     f32,
}

Unit :: struct {
	active:        bool,
	kind:          Unit_Kind,
	home:          Planet_Id,
	planet:        Planet_Id,
	target_planet: Planet_Id,
	mode:          Unit_Mode,
	position:      rl.Vector3,
	mine_timer:    f32,
	deposit_timer: f32,
	orbit_angle:   f32,
}

Research :: struct {
	active:    bool,
	kind:      int,
	remaining: f32,
	total:     f32,
	advanced:  bool,
	combat:    bool,
}

Game :: struct {
	planets:       [MAX_PLANETS]Planet,
	units:         [MAX_UNITS]Unit,
	minerals:      int,
	research:      Research,
	selected_planet: Planet_Id,
	selected_unit: int,
	inspector_tab: int,
	camera:        rl.Camera3D,
	notice_timer:  f32,
	notice:       cstring,
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 760, "Planetfall: Parallel Mining Command")
	rl.MaximizeWindow()
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	game := Game{
		planets = {
			Planet{"EARTH", rl.Vector3{-6, 0, 0}, 2.0, rl.Color{55, 145, 225, 255}, 1, 0, {}},
			Planet{"MARS", rl.Vector3{6, 0, 0}, 2.0, rl.Color{190, 75, 48, 255}, 1, 0, {}},
		},
		minerals = 600,
		selected_planet = .EARTH,
		selected_unit = -1,
		inspector_tab = 0,
		camera = rl.Camera3D{
			position = rl.Vector3{0, 11, 19},
			target = rl.Vector3{0, 0, 0},
			up = rl.Vector3{0, 1, 0},
			fovy = 45,
			projection = .PERSPECTIVE,
		},
		notice = "Select a planet to inspect its local fleet.",
	}

	// The first Mars miner demonstrates the mining/economy loop immediately.
	spawn_unit(&game, .STANDARD, .MARS)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		update_camera(&game, dt)
		update_simulation(&game, dt)
		handle_world_input(&game)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{7, 12, 25, 255})
		rl.BeginMode3D(game.camera)
		draw_world(&game)
		rl.EndMode3D()
		draw_hud(&game)
		rl.EndDrawing()
	}
}

update_camera :: proc(game: ^Game, dt: f32) {
	move := rl.Vector3{0, 0, 0}
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { move[2] -= 8 * dt }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { move[2] += 8 * dt }
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { move[0] -= 8 * dt }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { move[0] += 8 * dt }
	if rl.GetMouseX() < 18 { move[0] -= 8 * dt }
	if rl.GetMouseX() > rl.GetScreenWidth() - 18 { move[0] += 8 * dt }
	if rl.GetMouseY() < 18 { move[2] -= 8 * dt }
	if rl.GetMouseY() > rl.GetScreenHeight() - 18 { move[2] += 8 * dt }
	game.camera.position = game.camera.position + move
	game.camera.target = game.camera.target + move

	zoom := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD) { zoom += 1 }
	if rl.IsKeyDown(.E) || rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) { zoom -= 1 }
	if zoom != 0 { rl.CameraMoveToTarget(&game.camera, -zoom * dt * 14) }
}

update_simulation :: proc(game: ^Game, dt: f32) {
	if game.notice_timer > 0 { game.notice_timer -= dt }
	if game.research.active {
		game.research.remaining -= dt
		if game.research.remaining <= 0 {
			game.research.active = false
			if game.research.kind == 1 { game.research.advanced = true; game.notice = "Advanced Drone Tech online: MK2 production unlocked." }
			if game.research.kind == 2 { game.research.combat = true; game.notice = "Combat Drone Tech online: crimson guardians unlocked." }
			game.notice_timer = 4
		}
	}

	for planet_index in 0..<MAX_PLANETS {
		planet := &game.planets[planet_index]
		if planet.base_timer > 0 {
			planet.base_timer -= dt
			if planet.base_timer <= 0 {
				planet.bases += 1
				game.notice = rl.TextFormat("%s command base completed.", planet.name)
				game.notice_timer = 3
			}
		}
		for line in 0..<MAX_BASES {
			job := &planet.jobs[line]
			if !job.active { continue }
			job.remaining -= dt
			if job.remaining <= 0 {
				spawn_unit(game, job.kind, Planet_Id(planet_index))
				job.active = false
			}
		}
	}

	for i in 0..<MAX_UNITS {
		unit := &game.units[i]
		if !unit.active { continue }
		earth := game.planets[0].position
		mars := game.planets[1].position
		if unit.kind == .COMBAT {
			unit.orbit_angle += dt * 1.2
			unit.position = orbit_position(game.planets[int(unit.target_planet)].position, unit.orbit_angle, 2.8)
			continue
		}
		if unit.mode == .MINING {
			unit.mine_timer += dt
			if unit.mine_timer >= 3 {
				unit.mine_timer = 0
				unit.mode = .RETURNING
				unit.target_planet = .EARTH
			}
		} else if unit.mode == .RETURNING || unit.mode == .MOVING {
			target := earth
			if unit.target_planet == .MARS { target = mars }
			unit.position = rl.Vector3MoveTowards(unit.position, target, dt * 5)
			if rl.Vector3Distance(unit.position, target) < 0.2 {
				unit.planet = unit.target_planet
				if unit.mode == .RETURNING {
					unit.mode = .DEPOSITING
					unit.deposit_timer = 1
				} else if unit.planet == .MARS {
					unit.mode = .MINING
				} else { unit.mode = .IDLE }
			}
		} else if unit.mode == .DEPOSITING {
			unit.deposit_timer -= dt
			if unit.deposit_timer <= 0 {
				game.minerals += 25
				unit.mode = .MOVING
				unit.target_planet = .MARS
			}
		}
	}
}

spawn_unit :: proc(game: ^Game, kind: Unit_Kind, planet: Planet_Id) -> bool {
	for i in 0..<MAX_UNITS {
		if game.units[i].active { continue }
		mode := Unit_Mode.IDLE
		if planet == .MARS && kind != .COMBAT { mode = .MINING }
		game.units[i] = Unit{
			active = true, kind = kind, home = planet, planet = planet, target_planet = planet,
			mode = mode, position = game.planets[int(planet)].position + rl.Vector3{0, 0, 2.5},
			orbit_angle = f32(i) * 0.8,
		}
		if kind == .COMBAT { game.units[i].mode = .GUARDING }
		return true
	}
	return false
}

orbit_position :: proc(center: rl.Vector3, angle, distance: f32) -> rl.Vector3 {
	return rl.Vector3{center[0] + math.cos(angle) * distance, center[1] + 0.8, center[2] + math.sin(angle) * distance}
}

handle_world_input :: proc(game: ^Game) {
	if rl.IsMouseButtonPressed(.LEFT) {
		mouse := rl.GetMousePosition()
		ray := rl.GetScreenToWorldRay(mouse, game.camera)
		for i in 0..<MAX_PLANETS {
			if rl.GetRayCollisionSphere(ray, game.planets[i].position, game.planets[i].radius).hit {
				game.selected_planet = Planet_Id(i)
				game.inspector_tab = 0
				game.selected_unit = -1
				return
			}
		}
	}
	if rl.IsMouseButtonPressed(.RIGHT) && game.selected_unit >= 0 {
		mouse := rl.GetMousePosition()
		ray := rl.GetScreenToWorldRay(mouse, game.camera)
		for i in 0..<MAX_PLANETS {
			if rl.GetRayCollisionSphere(ray, game.planets[i].position, game.planets[i].radius + 0.5).hit {
				order_unit(game, game.selected_unit, Planet_Id(i))
				return
			}
		}
	}
}

order_unit :: proc(game: ^Game, index: int, target: Planet_Id) {
	if index < 0 || index >= MAX_UNITS || !game.units[index].active { return }
	unit := &game.units[index]
	unit.target_planet = target
	if unit.kind == .COMBAT {
		unit.planet = target
		unit.mode = .GUARDING
		game.notice = rl.TextFormat("Combat drone ordered to guard %s.", game.planets[int(target)].name)
	} else if target == .MARS {
		unit.mode = .MOVING
		game.notice = "Mining route assigned to Mars."
	} else {
		unit.mode = .MOVING
		game.notice = "Drone recalled to Earth."
	}
	game.notice_timer = 3
}

draw_world :: proc(game: ^Game) {
	rl.DrawGrid(40, 1)
	rl.DrawLine3D(game.planets[0].position, game.planets[1].position, rl.Color{45, 80, 120, 180})
	rl.DrawSphere(game.planets[0].position, game.planets[0].radius, game.planets[0].color)
	rl.DrawSphere(game.planets[1].position, game.planets[1].radius, game.planets[1].color)
	rl.DrawSphereWires(game.planets[0].position, 2.03, 16, 16, rl.Color{145, 220, 255, 180})
	rl.DrawSphereWires(game.planets[1].position, 2.03, 16, 16, rl.Color{255, 150, 95, 180})
	for p in 0..<MAX_PLANETS {
		planet := &game.planets[p]
		for base in 0..<planet.bases { draw_base(planet.position, base) }
		if planet.base_timer > 0 {
			point := planet_surface_point(planet.position, planet.bases)
			rl.DrawCylinder(point, 0.25, 0.08, 0.5, 6, rl.Color{255, 215, 70, 180})
		}
	}
	for i in 0..<MAX_UNITS {
		if !game.units[i].active { continue }
		draw_unit(&game.units[i], game.planets)
	}
}

draw_base :: proc(center: rl.Vector3, index: int) {
	point := planet_surface_point(center, index)
	cap := point + rl.Vector3{0, 0.48, 0}
	rl.DrawCylinder(point, 0.38, 0.5, 0.7, 8, rl.Color{80, 96, 115, 255})
	rl.DrawCylinder(cap, 0.12, 0.22, 0.45, 6, rl.Color{80, 210, 230, 255})
	rl.DrawSphere(cap + rl.Vector3{0, 0.28, 0}, 0.1, rl.Color{255, 225, 80, 255})
}

planet_surface_point :: proc(center: rl.Vector3, index: int) -> rl.Vector3 {
	angle := f32(index) * 2.399
	return rl.Vector3{center[0] + math.cos(angle) * 1.55, center[1] + 0.65, center[2] + math.sin(angle) * 1.55}
}

draw_unit :: proc(unit: ^Unit, planets: [MAX_PLANETS]Planet) {
	if unit.kind == .COMBAT {
		rl.DrawCircle3D(planets[int(unit.target_planet)].position, 2.8, rl.Vector3{0, 1, 0}, 90, rl.Color{235, 55, 70, 150})
		rl.DrawSphere(unit.position, 0.22, rl.Color{220, 35, 45, 255})
		rl.DrawCylinderEx(unit.position, unit.position + rl.Vector3{0, 0.35, 0}, 0.08, 0.03, 6, rl.Color{255, 100, 60, 255})
		rl.DrawLine3D(unit.position, unit.position + rl.Vector3{0.35, 0, 0}, rl.Color{255, 230, 100, 255})
		return
	}
	color := rl.Color{100, 240, 180, 255}
	if unit.kind == .FAST { color = rl.Color{100, 180, 255, 255} }
	rl.DrawSphere(unit.position, 0.18, color)
	rl.DrawCylinderEx(unit.position, unit.position + rl.Vector3{0, 0, 0.45}, 0.1, 0.02, 6, color)
}

draw_hud :: proc(game: ^Game) {
	width := rl.GetScreenWidth()
	height := rl.GetScreenHeight()
	panel_x := width - 370
	rl.DrawRectangle(0, 0, width, 62, rl.Color{10, 18, 35, 240})
	rl.DrawRectangle(panel_x, 62, 370, height - 62, rl.Color{12, 21, 38, 245})
	rl.DrawLine(panel_x, 62, panel_x, height, rl.Color{55, 100, 140, 255})
	rl.DrawText("PLANETFALL // MINING COMMAND", 20, 12, 22, rl.Color{140, 220, 255, 255})
	rl.DrawText(rl.TextFormat("MINERALS  %i", game.minerals), 22, 38, 16, rl.Color{245, 210, 90, 255})
	rl.DrawText("RESEARCH", 220, 12, 13, rl.Color{150, 170, 195, 255})
	if game.research.active {
		pct := 1 - game.research.remaining / game.research.total
		rl.DrawText(rl.TextFormat("%s  %.1fs", research_name(game.research.kind), game.research.remaining), 220, 29, 14, rl.WHITE)
		rl.DrawRectangle(220, 48, 230, 5, rl.Color{35, 50, 70, 255})
		rl.DrawRectangle(220, 48, i32(230 * pct), 5, rl.Color{110, 210, 255, 255})
	} else {
		if game.research.advanced { rl.DrawText("ADVANCED DRONE: ONLINE", 220, 29, 13, rl.Color{110, 220, 255, 255}) }
		if game.research.combat { rl.DrawText("COMBAT DRONE: ONLINE", 220, 45, 13, rl.Color{255, 100, 100, 255}) }
		if !game.research.advanced && !game.research.combat { rl.DrawText("Choose a project below", 220, 29, 13, rl.Color{180, 190, 210, 255}) }
	}
	if !game.research.active {
		if !game.research.advanced && rl.GuiButton(rl.Rectangle{465, 10, 145, 22}, "RESEARCH MK2  150") { start_research(game, 1) }
		if !game.research.combat && rl.GuiButton(rl.Rectangle{615, 10, 145, 22}, "RESEARCH COMBAT  200") { start_research(game, 2) }
	}

	planet := &game.planets[int(game.selected_planet)]
	rl.DrawText(rl.TextFormat("%s INSPECTOR", planet.name), panel_x+22, 82, 22, rl.Color{220, 235, 250, 255})
	rl.DrawText(rl.TextFormat("%i active units  |  %i production lines", count_roster(game, game.selected_planet), planet.bases), panel_x+22, 110, 13, rl.Color{145, 170, 195, 255})
	if rl.GuiButton(rl.Rectangle{f32(panel_x+20), 130, 155, 30}, "UNITS") { game.inspector_tab = 0 }
	if rl.GuiButton(rl.Rectangle{f32(panel_x+185), 130, 165, 30}, "BUILDINGS") { game.inspector_tab = 1 }
	if game.inspector_tab == 0 { draw_units_tab(game, panel_x) } else { draw_buildings_tab(game, panel_x) }
	if game.notice_timer > 0 { rl.DrawRectangle(20, height-50, panel_x-40, 32, rl.Color{18, 35, 55, 235}); rl.DrawText(game.notice, 32, height-41, 14, rl.Color{170, 220, 240, 255}) }
}

start_research :: proc(game: ^Game, kind: int) {
	cost := 150
	time := f32(8)
	if kind == 2 { cost = 200; time = 10 }
	if game.minerals < cost { game.notice = "Insufficient minerals for that research project."; game.notice_timer = 3; return }
	game.minerals -= cost
	game.research = Research{active = true, kind = kind, remaining = time, total = time, advanced = game.research.advanced, combat = game.research.combat}
}

research_name :: proc(kind: int) -> cstring {
	if kind == 1 { return "ADVANCED DRONE TECH" }
	return "COMBAT DRONE TECH"
}

draw_units_tab :: proc(game: ^Game, panel_x: i32) {
	rl.DrawText("LOCAL UNIT ROSTER", panel_x+22, 178, 14, rl.Color{100, 210, 230, 255})
	rl.DrawText("Right-click a planet to assign selected unit", panel_x+22, 198, 12, rl.Color{140, 155, 175, 255})
	row := 222
	found := 0
	for i in 0..<MAX_UNITS {
		if !game.units[i].active || !unit_in_roster(&game.units[i], game.selected_planet) { continue }
		unit := &game.units[i]
		label := rl.TextFormat("%s  %s", unit_name(unit.kind), mode_name(unit.mode))
		if rl.GuiButton(rl.Rectangle{f32(panel_x+20), f32(row), 328, 34}, label) { game.selected_unit = i }
		if game.selected_unit == i { rl.DrawRectangleLines(panel_x+20, i32(row), 328, 34, rl.Color{255, 225, 90, 255}) }
		row += 42
		found += 1
	}
	if found == 0 { rl.DrawText("No units operating from this planet.", panel_x+22, i32(row), 14, rl.Color{140, 155, 175, 255}) }
}

draw_buildings_tab :: proc(game: ^Game, panel_x: i32) {
	planet := &game.planets[int(game.selected_planet)]
	rl.DrawText(rl.TextFormat("BASES: %i / 5", planet.bases), panel_x+22, 180, 20, rl.Color{225, 235, 250, 255})
	rl.DrawText("Each completed base adds one parallel production line.", panel_x+22, 210, 12, rl.Color{145, 165, 185, 255})
	if planet.base_timer > 0 {
		pct := 1 - planet.base_timer / 6
		rl.DrawText(rl.TextFormat("COMMAND BASE CONSTRUCTION  %.1fs", planet.base_timer), panel_x+22, 244, 13, rl.Color{255, 215, 100, 255})
		rl.DrawRectangle(panel_x+22, 264, 325, 9, rl.Color{35, 50, 70, 255})
		rl.DrawRectangle(panel_x+22, 264, i32(325*pct), 9, rl.Color{255, 190, 70, 255})
	} else if planet.bases < MAX_BASES {
		if rl.GuiButton(rl.Rectangle{f32(panel_x+22), 244, 325, 38}, "Construct Command Base (200 Minerals)") { start_base(game, planet) }
	} else { rl.DrawText("Maximum command infrastructure reached.", panel_x+22, 250, 13, rl.Color{120, 220, 150, 255}) }

	rl.DrawText("UNIT PRODUCTION", panel_x+22, 310, 14, rl.Color{100, 210, 230, 255})
	button_y := 330
	if rl.GuiButton(rl.Rectangle{f32(panel_x+22), f32(button_y), 155, 32}, "Standard  50 / 3s") { queue_unit(game, planet, .STANDARD) }
	if rl.GuiButton(rl.Rectangle{f32(panel_x+192), f32(button_y), 155, 32}, "Fast MK2  100 / 4s") { queue_unit(game, planet, .FAST) }
	if rl.GuiButton(rl.Rectangle{f32(panel_x+22), f32(button_y+38), 325, 32}, "Combat Drone  125 / 5s") { queue_unit(game, planet, .COMBAT) }
	if !game.research.advanced { rl.DrawText("MK2 locked: research Advanced Drone Tech", panel_x+22, 408, 12, rl.Color{165, 145, 145, 255}) }
	if !game.research.combat { rl.DrawText("Combat locked: research Combat Drone Tech", panel_x+22, 426, 12, rl.Color{165, 145, 145, 255}) }

	row := 465
	for line in 0..<MAX_BASES {
		job := &planet.jobs[line]
		if !job.active { continue }
		pct := 1 - job.remaining / job.total
		rl.DrawText(rl.TextFormat("LINE %i  %s  %.1fs", line+1, unit_name(job.kind), job.remaining), panel_x+22, i32(row), 12, rl.Color{195, 215, 230, 255})
		rl.DrawRectangle(panel_x+22, i32(row+17), 325, 7, rl.Color{35, 50, 70, 255})
		rl.DrawRectangle(panel_x+22, i32(row+17), i32(325*pct), 7, production_color(job.kind))
		row += 34
	}
}

start_base :: proc(game: ^Game, planet: ^Planet) {
	if planet.bases >= MAX_BASES || planet.base_timer > 0 { return }
	if game.minerals < 200 { game.notice = "Need 200 minerals to construct a command base."; game.notice_timer = 3; return }
	game.minerals -= 200
	planet.base_timer = 6
}

queue_unit :: proc(game: ^Game, planet: ^Planet, kind: Unit_Kind) {
	cost := 50
	time := f32(3)
	if kind == .FAST { cost = 100; time = 4; if !game.research.advanced { game.notice = "Research Advanced Drone Tech first."; game.notice_timer = 3; return } }
	if kind == .COMBAT { cost = 125; time = 5; if !game.research.combat { game.notice = "Research Combat Drone Tech first."; game.notice_timer = 3; return } }
	if game.minerals < cost { game.notice = "Insufficient minerals for that production order."; game.notice_timer = 3; return }
	for i in 0..<planet.bases {
		if !planet.jobs[i].active {
			planet.jobs[i] = Build_Job{active = true, kind = kind, remaining = time, total = time}
			game.minerals -= cost
			return
		}
	}
	game.notice = "All command bases are busy; production waits for a line."; game.notice_timer = 3
}

unit_in_roster :: proc(unit: ^Unit, planet: Planet_Id) -> bool {
	switch unit.mode {
	case .IDLE: return unit.home == planet
	case .MOVING, .RETURNING: return unit.target_planet == planet
	case .MINING, .DEPOSITING, .GUARDING: return unit.planet == planet
	}
	return false
}

count_roster :: proc(game: ^Game, planet: Planet_Id) -> int {
	count := 0
	for i in 0..<MAX_UNITS { if game.units[i].active && unit_in_roster(&game.units[i], planet) { count += 1 } }
	return count
}

unit_name :: proc(kind: Unit_Kind) -> cstring {
	switch kind {
	case .STANDARD: return "STANDARD DRONE"
	case .FAST: return "FAST DRONE MK2"
	case .COMBAT: return "COMBAT DRONE"
	}
	return "DRONE"
}

mode_name :: proc(mode: Unit_Mode) -> cstring {
	switch mode {
	case .IDLE: return "IDLE / STATIONED"
	case .MINING: return "MINING"
	case .RETURNING: return "RETURNING TO EARTH"
	case .DEPOSITING: return "DEPOSITING"
	case .MOVING: return "IN TRANSIT"
	case .GUARDING: return "GUARDING / ORBIT"
	}
	return "ACTIVE"
}

production_color :: proc(kind: Unit_Kind) -> rl.Color {
	if kind == .COMBAT { return rl.Color{235, 55, 70, 255} }
	if kind == .FAST { return rl.Color{90, 190, 255, 255} }
	return rl.Color{100, 225, 175, 255}
}

// search_and_set_resource_dir is kept for projects embedding this sample.
search_and_set_resource_dir :: proc(folder_name: cstring) -> bool {
	if rl.DirectoryExists(folder_name) {
		rl.ChangeDirectory(rl.TextFormat("%s/%s", rl.GetWorkingDirectory(), folder_name))
		return true
	}
	app_dir := rl.GetApplicationDirectory()
	dir := rl.TextFormat("%s%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) { rl.ChangeDirectory(dir); return true }
	dir = rl.TextFormat("%s../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) { rl.ChangeDirectory(dir); return true }
	dir = rl.TextFormat("%s../../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) { rl.ChangeDirectory(dir); return true }
	dir = rl.TextFormat("%s../../../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) { rl.ChangeDirectory(dir); return true }
	return false
}
