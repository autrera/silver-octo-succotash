package main

import rl "vendor:raylib"

Planet :: enum { Earth, Mars }
Drone_Kind :: enum { Standard, Fast }
Drone_State :: enum { Idle, To_Mars, Mining, Returning }

Drone :: struct {
	position: rl.Vector3,
	location: Planet,
	kind: Drone_Kind,
	state: Drone_State,
	timer: f32,
	selected: bool,
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Planetary Mining Command")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	earth := rl.Vector3{0, 0, 0}
	mars := rl.Vector3{18, 0, 12}
	camera_target := rl.Vector3{8, 0, 6}
	zoom: f32 = 30
	camera := rl.Camera3D{
		position = camera_target + rl.Vector3{zoom * 0.7, zoom * 0.8, zoom},
		target = camera_target,
		up = rl.Vector3{0, 1, 0},
		fovy = 45,
		projection = .PERSPECTIVE,
	}

	minerals := 500
	tech_researched := false
	selected_planet := Planet.Earth
	planet_selected := false
	selected_drone := -1
	inspector_tab := 0
	drones: [dynamic]Drone = make([dynamic]Drone)
	append(&drones, Drone{earth + rl.Vector3{-2, 1.5, 0}, .Earth, .Standard, .Idle, 0, false})
	append(&drones, Drone{mars + rl.Vector3{0, 1.5, 0}, .Mars, .Standard, .Mining, 3, false})

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		pan_camera(&camera_target, dt)
		zoom -= rl.GetMouseWheelMove() * 2
		if rl.IsKeyDown(.Q) || rl.IsKeyDown(.MINUS) { zoom += 18 * dt }
		if rl.IsKeyDown(.E) || rl.IsKeyDown(.EQUAL) { zoom -= 18 * dt }
		zoom = clamp(zoom, 14, 52)
		camera.target = camera_target
		camera.position = camera_target + rl.Vector3{zoom * 0.7, zoom * 0.8, zoom}

		for i := 0; i < len(drones); i += 1 {
			update_drone(&drones[i], dt, earth, mars, &minerals)
		}

		mouse := rl.GetMousePosition()
		fleet_bounds := rl.Rectangle{20, 80, 320, f32(110 + len(drones) * 28)}
		inspector_bounds := rl.Rectangle{f32(rl.GetScreenWidth() - 340), 80, 320, 520}
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, fleet_bounds) {
				row := int((mouse[1] - 110) / 28)
				if row >= 0 && row < len(drones) {
					selected_drone = row
					for i := 0; i < len(drones); i += 1 { drones[i].selected = i == row }
				}
			} else if !rl.CheckCollisionPointRec(mouse, inspector_bounds) && mouse[1] > 64 {
				select_world_object(mouse, camera, earth, mars, &drones, &selected_planet, &planet_selected, &selected_drone)
			}
		}
		if rl.IsMouseButtonPressed(.RIGHT) || rl.IsKeyPressed(.M) {
			for i := 0; i < len(drones); i += 1 {
				if drones[i].selected && drones[i].state == .Idle {
					drones[i].state = .To_Mars
				}
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{12, 20, 36, 255})
		rl.BeginMode3D(camera)
		rl.DrawPlane(rl.Vector3{8, -0.1, 6}, rl.Vector2{55, 45}, rl.Color{24, 48, 56, 255})
		rl.DrawGrid(28, 2)
		rl.DrawSphere(earth, 3.2, rl.BLUE)
		rl.DrawSphereWires(earth, 3.25, 16, 16, rl.SKYBLUE)
		rl.DrawSphere(mars, 4.0, rl.RED)
		rl.DrawSphereWires(mars, 4.1, 16, 16, rl.ORANGE)
		rl.DrawLine3D(earth, mars, rl.Color{90, 90, 110, 180})
		draw_base(earth, rl.SKYBLUE)
		draw_base(mars, rl.ORANGE)
		if planet_selected {
			selected_position := selected_planet == .Earth ? earth : mars
			selected_radius: f32 = selected_planet == .Earth ? 3.7 : 4.5
			rl.DrawSphereWires(selected_position, selected_radius, 20, 20, rl.GOLD)
		}
		for i := 0; i < len(drones); i += 1 {
			d := drones[i]
			rl.DrawSphere(d.position, d.kind == .Fast ? 0.8 : 0.62, drone_color(d))
			if d.kind == .Fast { rl.DrawCubeWires(d.position, 1.9, 1.9, 1.9, rl.SKYBLUE) }
			if d.selected { rl.DrawSphereWires(d.position, 1.0, 8, 8, rl.YELLOW) }
		}
		rl.EndMode3D()

		rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 64, rl.Color{8, 12, 24, 245})
		rl.DrawText("PLANETARY MINING COMMAND", 22, 15, 24, rl.RAYWHITE)
		rl.DrawText(rl.TextFormat("MINERALS  %03d", minerals), 360, 18, 21, rl.GOLD)
		rl.DrawText("RESEARCH / TECH", 540, 10, 12, rl.SKYBLUE)
		if tech_researched {
			rl.DrawText("ADVANCED DRONE TECH: ONLINE", 540, 29, 16, rl.GREEN)
		} else if minerals >= 150 {
			if rl.GuiButton(rl.Rectangle{540, 24, 250, 32}, "Research Advanced Drone Tech (150)") {
				minerals -= 150
				tech_researched = true
			}
		} else {
			rl.DrawRectangle(540, 24, 250, 32, rl.Color{45, 45, 55, 255})
			rl.DrawText("Research Advanced Drone Tech (150)", 550, 34, 13, rl.GRAY)
		}
		rl.DrawText("WASD / ARROWS / EDGE: PAN   SCROLL / Q-E: ZOOM", 825, 22, 13, rl.LIGHTGRAY)

		draw_fleet_panel(&drones)
		if planet_selected {
			draw_inspector(selected_planet, &drones, &minerals, tech_researched, &inspector_tab)
		}
		rl.DrawRectangle(20, rl.GetScreenHeight()-55, 360, 36, rl.Color{20, 35, 52, 255})
		rl.DrawText("M  SEND SELECTED TO MARS   RIGHT CLICK", 30, rl.GetScreenHeight()-46, 13, rl.LIGHTGRAY)
		rl.EndDrawing()
	}
}

update_drone :: proc(d: ^Drone, dt: f32, earth, mars: rl.Vector3, minerals: ^int) {
	speed: f32 = d.kind == .Fast ? 14 : 7
	mine_time: f32 = d.kind == .Fast ? 1.5 : 3
	earth_target := earth + rl.Vector3{0, 1.5, 0}
	mars_target := mars + rl.Vector3{0, 1.5, 0}
	switch d.state {
	case .Idle:
		return
	case .To_Mars:
		move_toward(&d.position, mars_target, speed * dt)
		if distance(d.position, mars_target) < 0.2 {
			d.position = mars_target
			d.state = .Mining
			d.timer = mine_time
		}
	case .Mining:
		d.location = .Mars
		d.timer -= dt
		if d.timer <= 0 {
			d.state = .Returning
			d.location = .Earth
		}
	case .Returning:
		move_toward(&d.position, earth_target, speed * dt)
		if distance(d.position, earth_target) < 0.2 {
			d.position = earth_target
			minerals^ += 10
			d.state = .To_Mars
			d.location = .Mars
		}
	}
}

select_world_object :: proc(mouse: rl.Vector2, camera: rl.Camera3D, earth, mars: rl.Vector3, drones: ^[dynamic]Drone, planet: ^Planet, planet_selected: ^bool, selected_drone: ^int) {
	ray := rl.GetScreenToWorldRay(mouse, camera)
	best_distance: f32 = 100000
	best_drone := -1
	for i := 0; i < len(drones^); i += 1 {
		hit := rl.GetRayCollisionSphere(ray, drones^[i].position, 0.9)
		if hit.hit && hit.distance < best_distance { best_distance = hit.distance; best_drone = i }
	}
	best_planet := Planet.Earth
	for i := 0; i < 2; i += 1 {
		position := i == 0 ? earth : mars
		radius: f32 = i == 0 ? 3.2 : 4.0
		hit := rl.GetRayCollisionSphere(ray, position, radius)
		if hit.hit && hit.distance < best_distance {
			best_distance = hit.distance
			best_planet = Planet(i)
			best_drone = -1
		}
	}
	if best_drone >= 0 {
		selected_drone^ = best_drone
		for i := 0; i < len(drones^); i += 1 { drones^[i].selected = i == best_drone }
	} else if best_distance < 100000 {
		planet^ = best_planet
		planet_selected^ = true
	}
}

draw_base :: proc(position: rl.Vector3, color: rl.Color) {
	base := position + rl.Vector3{0, 3.1, 0}
	rl.DrawCube(base, 1.8, 1.0, 1.8, rl.Color{145, 155, 170, 255})
	rl.DrawCubeWires(base, 1.9, 1.1, 1.9, color)
	rl.DrawCylinder(position + rl.Vector3{0, 3.9, 0}, 0.45, 0.45, 1.0, 12, color)
}

draw_fleet_panel :: proc(drones: ^[dynamic]Drone) {
	x: i32 = 20
	y: i32 = 80
	h := i32(75 + len(drones) * 28)
	rl.DrawRectangle(x, y, 320, h, rl.Color{10, 18, 32, 235})
	rl.DrawRectangleLines(x, y, 320, h, rl.Color{65, 95, 125, 255})
	rl.DrawText("FLEET SELECTION", x+18, y+12, 20, rl.SKYBLUE)
	for i := 0; i < len(drones); i += 1 {
		if drones^[i].selected { rl.DrawRectangle(x+10, y+38+i32(i*28), 300, 25, rl.Color{45, 70, 100, 255}) }
		label := rl.TextFormat("DRONE %d  %s  %s", i+1, kind_name(drones^[i].kind), state_name(drones^[i].state))
		rl.DrawText(label, x+18, y+42+i32(i*28), 14, drone_color(drones^[i]))
	}
}

draw_inspector :: proc(p: Planet, drones: ^[dynamic]Drone, minerals: ^int, tech: bool, tab: ^int) {
	x := i32(rl.GetScreenWidth() - 340)
	y: i32 = 80
	w: i32 = 320
	rl.DrawRectangle(x, y, w, 520, rl.Color{20, 28, 45, 245})
	rl.DrawRectangleLines(x, y, w, 520, rl.Color{80, 110, 150, 255})
	rl.DrawText(rl.TextFormat("PLANET INSPECTOR: %s", planet_name(p)), x+18, y+15, 19, rl.WHITE)
	rl.DrawText("STATUS: OPERATIONAL", x+18, y+43, 14, rl.GREEN)
	if rl.GuiButton(rl.Rectangle{f32(x+16), f32(y+66), 138, 32}, "UNITS") { tab^ = 0 }
	if rl.GuiButton(rl.Rectangle{f32(x+158), f32(y+66), 138, 32}, "BUILDINGS") { tab^ = 1 }
	if tab^ == 1 {
		rl.DrawText("ACTIVE BUILDINGS", x+18, y+125, 14, rl.SKYBLUE)
		rl.DrawText("Command Base", x+18, y+153, 18, rl.WHITE)
		rl.DrawText("ONLINE - production enabled", x+18, y+178, 14, rl.GREEN)
		rl.DrawText("Additional building slots reserved", x+18, y+235, 14, rl.GRAY)
		return
	}

	rl.DrawText("BUILDINGS", x+18, y+125, 14, rl.SKYBLUE)
	rl.DrawText("Command Base (Active)", x+18, y+150, 16, rl.WHITE)
	count := 0
	for d in drones^ { if d.location == p { count += 1 } }
	rl.DrawText(rl.TextFormat("STATIONED UNITS (%d)", count), x+18, y+185, 14, rl.SKYBLUE)
	row := 0
	for d in drones^ {
		if d.location == p {
			label := rl.TextFormat("%s  %s", kind_name(d.kind), state_name(d.state))
			rl.DrawText(label, x+18, y+210+i32(row*22), 14, drone_color(d))
			row += 1
		}
	}
	if base_active(p) && rl.GuiButton(rl.Rectangle{f32(x+18), f32(y+400), 278, 34}, "Build Standard Drone (50)") && minerals^ >= 50 {
		minerals^ -= 50
		spawn_drone(drones, p, .Standard)
	}
	if tech {
		if rl.GuiButton(rl.Rectangle{f32(x+18), f32(y+442), 278, 34}, "Build Fast Drone MK2 (100)") && minerals^ >= 100 {
			minerals^ -= 100
			spawn_drone(drones, p, .Fast)
		}
	} else {
		rl.DrawRectangle(x+18, y+442, 278, 34, rl.Color{45, 45, 55, 255})
		rl.DrawText("Fast Drone MK2 (Research Required)", x+28, y+453, 13, rl.GRAY)
	}
}

spawn_drone :: proc(drones: ^[dynamic]Drone, p: Planet, kind: Drone_Kind) {
	position := p == .Earth ? rl.Vector3{0, 1.5, 0} : rl.Vector3{18, 1.5, 12}
	state := p == .Mars ? Drone_State.Mining : Drone_State.Idle
	timer: f32 = 0
	if state == .Mining { timer = kind == .Fast ? 1.5 : 3 }
	append(drones, Drone{position, p, kind, state, timer, false})
}

base_active :: proc(p: Planet) -> bool { _ = p; return true }

move_toward :: proc(p: ^rl.Vector3, target: rl.Vector3, amount: f32) {
	delta := target - p^
	length := distance(rl.Vector3{}, delta)
	if length <= amount || length == 0 { p^ = target } else { p^ += delta * (amount / length) }
}

distance :: proc(a, b: rl.Vector3) -> f32 { return rl.Vector3Length(b - a) }

pan_camera :: proc(target: ^rl.Vector3, dt: f32) {
	dx, dz: f32 = 0, 0
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { dx -= 1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { dx += 1 }
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { dz -= 1 }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { dz += 1 }
	mouse := rl.GetMousePosition()
	width, height := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	if mouse[0] < 18 { dx -= 1 }
	if mouse[0] > width-18 { dx += 1 }
	if mouse[1] < 18 { dz -= 1 }
	if mouse[1] > height-18 { dz += 1 }
	target.x += dx * 16 * dt
	target.z += dz * 16 * dt
}

clamp :: proc(value, low, high: f32) -> f32 { return max(low, min(high, value)) }

planet_name :: proc(p: Planet) -> cstring { return p == .Earth ? "Earth" : "Mars" }
kind_name :: proc(k: Drone_Kind) -> cstring { return k == .Fast ? "FAST MK2" : "STANDARD" }
state_name :: proc(s: Drone_State) -> cstring {
	switch s {
	case .Idle: return "IDLE"
	case .To_Mars: return "TO MARS"
	case .Mining: return "MINING"
	case .Returning: return "RETURNING"
	}
	return "UNKNOWN"
}
drone_color :: proc(d: Drone) -> rl.Color {
	if d.kind == .Fast {
		switch d.state {
		case .Idle: return rl.SKYBLUE
		case .To_Mars: return rl.BLUE
		case .Mining: return rl.PURPLE
		case .Returning: return rl.LIME
		}
	}
	switch d.state {
	case .Idle: return rl.GRAY
	case .To_Mars: return rl.YELLOW
	case .Mining: return rl.ORANGE
	case .Returning: return rl.GREEN
	}
	return rl.WHITE
}
