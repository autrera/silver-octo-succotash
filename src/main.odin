package main

import rl "vendor:raylib"

Drone_State :: enum {Idle, To_Mars, Mining, Returning}
Drone :: struct {
	position: rl.Vector3,
	state: Drone_State,
	timer: f32,
	selected: bool,
}

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})
	rl.InitWindow(1100, 700, "Mars Fleet Command")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	earth := rl.Vector3{0, 0, 0}
	mars := rl.Vector3{18, 0, 12}
	camera := rl.Camera3D{
		position = rl.Vector3{22, 28, 30}, target = rl.Vector3{8, 0, 6},
		up = rl.Vector3{0, 1, 0}, fovy = 45, projection = .PERSPECTIVE,
	}
	drones: [16]Drone
	drones[0] = Drone{rl.Vector3{-2, 1.5, 0}, .Idle, 0, false}
	drones[1] = Drone{rl.Vector3{2, 1.5, 0}, .Idle, 0, false}
	drone_count := 2
	minerals := 100
	selected := 0

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		pan_camera(&camera, dt)
		for i := 0; i < drone_count; i += 1 {
			update_drone(&drones[i], dt, earth, mars, &minerals)
		}

		if rl.IsKeyPressed(.B) && minerals >= 50 && drone_count < len(drones) {
			minerals -= 50
			drones[drone_count] = Drone{earth + rl.Vector3{f32(drone_count % 3) * 2 - 2, 1.5, f32(drone_count / 3) * 2}, .Idle, 0, false}
			drone_count += 1
		}
		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			panel := rl.Rectangle{f32(rl.GetScreenWidth() - 270), 70, 250, f32(80 + drone_count * 28)}
			if rl.CheckCollisionPointRec(mouse, panel) {
				row := int((mouse[1] - 110) / 28)
				if row >= 0 && row < drone_count { selected = row; drones[row].selected = true }
			}
		}
		if rl.IsMouseButtonPressed(.RIGHT) || rl.IsKeyPressed(.M) {
			for i := 0; i < drone_count; i += 1 {
				if drones[i].selected { drones[i].state = .To_Mars; drones[i].timer = 0 }
			}
		}
		_ = selected

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
		for i := 0; i < drone_count; i += 1 {
			color := drone_color(drones[i].state)
			rl.DrawSphere(drones[i].position, 0.65, color)
			if drones[i].selected { rl.DrawSphereWires(drones[i].position, 0.85, 8, 8, rl.YELLOW) }
		}
		rl.EndMode3D()

		rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 58, rl.Color{8, 12, 24, 245})
		rl.DrawText("MARS FLEET COMMAND", 22, 15, 24, rl.RAYWHITE)
		rl.DrawText(rl.TextFormat("MINERALS  %03d", minerals), 365, 18, 21, rl.GOLD)
		rl.DrawText("WASD / ARROWS / EDGE: PAN", 650, 21, 14, rl.LIGHTGRAY)
		rl.DrawRectangle(rl.GetScreenWidth() - 270, 70, 250, i32(80 + drone_count * 28), rl.Color{10, 18, 32, 235})
		rl.DrawText("FLEET", rl.GetScreenWidth() - 250, 82, 20, rl.SKYBLUE)
		for i := 0; i < drone_count; i += 1 {
			label := rl.TextFormat("DRONE %d   %s", i + 1, state_name(drones[i].state))
			if drones[i].selected { rl.DrawRectangle(rl.GetScreenWidth() - 260, 106 + i32(i * 28), 230, 25, rl.Color{45, 70, 100, 255}) }
			rl.DrawText(label, rl.GetScreenWidth() - 250, 110 + i32(i * 28), 15, drone_color(drones[i].state))
		}
		rl.DrawRectangle(20, rl.GetScreenHeight() - 55, 260, 36, rl.Color{20, 35, 52, 255})
		rl.DrawText("B  BUILD DRONE (50)   M  SEND SELECTED", 30, rl.GetScreenHeight() - 46, 13, rl.LIGHTGRAY)
		rl.EndDrawing()
	}
}

update_drone :: proc(d: ^Drone, dt: f32, earth, mars: rl.Vector3, minerals: ^int) {
	speed: f32 = 7
	if d.state == .Idle { return }
	if d.state == .To_Mars {
		move_toward(&d.position, mars + rl.Vector3{0, 1.5, 0}, speed * dt)
		if distance(d.position, mars + rl.Vector3{0, 1.5, 0}) < 0.2 { d.state = .Mining; d.timer = 3 }
	} else if d.state == .Mining {
		d.timer -= dt
		if d.timer <= 0 { d.state = .Returning; d.timer = 10 }
	} else if d.state == .Returning {
		move_toward(&d.position, earth + rl.Vector3{0, 1.5, 0}, speed * dt)
		if distance(d.position, earth + rl.Vector3{0, 1.5, 0}) < 0.2 { minerals^ += 10; d.state = .To_Mars }
	}
}

move_toward :: proc(p: ^rl.Vector3, target: rl.Vector3, amount: f32) {
	d := target - p^; n := distance(rl.Vector3{}, d)
	if n <= amount || n == 0 { p^ = target } else { p^ += d * (amount / n) }
}

distance :: proc(a, b: rl.Vector3) -> f32 { d := b - a; return rl.Vector3Length(d) }

drone_color :: proc(s: Drone_State) -> rl.Color {
	switch s { case .Idle: return rl.GRAY; case .To_Mars: return rl.YELLOW; case .Mining: return rl.ORANGE; case .Returning: return rl.GREEN }
	return rl.WHITE
}
state_name :: proc(s: Drone_State) -> cstring {
	switch s { case .Idle: return "IDLE"; case .To_Mars: return "MOVING TO MARS"; case .Mining: return "MINING"; case .Returning: return "RETURNING" }
	return "UNKNOWN"
}

pan_camera :: proc(camera: ^rl.Camera3D, dt: f32) {
	dx, dz: f32 = 0, 0
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { dx -= 1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { dx += 1 }
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { dz -= 1 }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { dz += 1 }
	m := rl.GetMousePosition(); w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	if m[0] < 18 { dx -= 1 }; if m[0] > w - 18 { dx += 1 }
	if m[1] < 18 { dz -= 1 }; if m[1] > h - 18 { dz += 1 }
	camera.position[0] += dx * 16 * dt; camera.target[0] += dx * 16 * dt
	camera.position[2] += dz * 16 * dt; camera.target[2] += dz * 16 * dt
}
