package main

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

UI_REFERENCE_HEIGHT :: 1280.0
UI_SCALE_MAX :: 3.0
UI_SCALE_STEP :: 0.25

ui_scale: f32 = 1

update_ui_scale :: proc() {
	h := f32(rl.GetScreenHeight())
	s := clamp(h / UI_REFERENCE_HEIGHT, 1, UI_SCALE_MAX)
	ui_scale = math.round(s / UI_SCALE_STEP) * UI_SCALE_STEP
	if ui_scale < 1 { ui_scale = 1 }
}

apply_ui_scale :: proc() {
	rlgl.Scalef(ui_scale, ui_scale, 1)
}

ui_screen_w :: proc() -> i32 {
	return i32(math.ceil(f32(rl.GetScreenWidth()) / ui_scale))
}

ui_screen_h :: proc() -> i32 {
	return i32(math.ceil(f32(rl.GetScreenHeight()) / ui_scale))
}

ui_mouse :: proc() -> rl.Vector2 {
	return rl.GetMousePosition() / ui_scale
}

ui_mouse_delta :: proc() -> rl.Vector2 {
	return rl.GetMouseDelta() / ui_scale
}

ui_world_to_screen :: proc(pos: rl.Vector3) -> rl.Vector2 {
	return rl.GetWorldToScreen(pos, camera) / ui_scale
}

ui_screen_to_world_ray :: proc(pos: rl.Vector2) -> rl.Ray {
	return rl.GetScreenToWorldRay(pos * ui_scale, camera)
}
