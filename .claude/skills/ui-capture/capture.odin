package main

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

Capture_Region :: enum {
	FULL,
	PANEL,
	RECT,
}

Capture_Request :: struct {
	name:   string,
	region: Capture_Region,
	rect:   rl.Rectangle,
}

CAPTURE_WARMUP_FRAMES  :: 3
CAPTURE_SETTLE_FRAMES  :: 2
CAPTURE_MAX_REQUESTS   :: 32
CAPTURE_TIMEOUT_FRAMES :: 20000
CAPTURE_PARKED_MOUSE   :: rl.Vector2{-10000, -10000}

capture_mouse_override := true
capture_mouse_pos := CAPTURE_PARKED_MOUSE
capture_mouse_delta: rl.Vector2

capture_requests: [CAPTURE_MAX_REQUESTS]Capture_Request
capture_request_count := 0
capture_step := -1
capture_countdown := CAPTURE_WARMUP_FRAMES
capture_frame := 0
capture_finished := false
capture_dir := ""

capture_tick :: proc() {
	if capture_frame == 0 {
		capture_dir = os.get_env("CAPTURE_DIR", context.allocator)
		if capture_dir == "" { capture_dir = "." }
		fmt.printfln("CAPTURE_SCREEN %d %d ui_scale=%.2f dpi=%.2f", rl.GetScreenWidth(), rl.GetScreenHeight(), ui_scale, window_dpi_scale)
	}
	capture_frame += 1
	if capture_frame > CAPTURE_TIMEOUT_FRAMES {
		fmt.println("CAPTURE_TIMEOUT")
		quit_requested = true
		return
	}
	if capture_countdown > 0 {
		capture_countdown -= 1
		return
	}
	capture_flush()
	capture_mouse_delta = {}
	if capture_finished {
		fmt.println("CAPTURE_DONE")
		quit_requested = true
		return
	}
	capture_step += 1
	capture_countdown = CAPTURE_SETTLE_FRAMES
	capture_finished = capture_scenario(capture_step)
}

capture_shot :: proc(name: string, region: Capture_Region = .PANEL, rect: rl.Rectangle = {}) {
	if capture_request_count >= CAPTURE_MAX_REQUESTS {
		fmt.printfln("CAPTURE_ERROR too many shots in one step, dropped %s", name)
		return
	}
	capture_requests[capture_request_count] = {name, region, rect}
	capture_request_count += 1
}

capture_wait :: proc(frames: int) {
	capture_countdown = frames
}

capture_hover :: proc(r: rl.Rectangle) {
	capture_hover_point({r.x + r.width / 2, r.y + r.height / 2})
}

capture_hover_point :: proc(p: rl.Vector2) {
	capture_mouse_delta = p - capture_mouse_pos
	if capture_mouse_delta == {} { capture_mouse_delta = {1, 0} }
	capture_mouse_pos = p
}

capture_park_mouse :: proc() {
	capture_mouse_pos = CAPTURE_PARKED_MOUSE
	capture_mouse_delta = {}
}

capture_panel_x :: proc() -> f32 {
	return f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
}

capture_dock_rect :: proc() -> rl.Rectangle {
	h := f32(ui_screen_h())
	return {0, h - 90, 440, 90}
}

capture_enter_game :: proc() {
	restart_game()
	in_start_menu = false
	game_paused = false
}

capture_clear_enemies :: proc(sector: int) {
	for i := unit_count - 1; i >= 0; i -= 1 {
		if units[i].enemy && units[i].target_planet == sector { remove_unit_at(i) }
	}
	units_changed()
}

capture_liberate :: proc(planet: int) {
	enemy_base_hp[planet] = 0
	capture_clear_enemies(planet)
}

capture_region_rect :: proc(req: Capture_Request) -> rl.Rectangle {
	w := f32(ui_screen_w())
	h := f32(ui_screen_h())
	switch req.region {
	case .FULL:
		return {0, 0, w, h}
	case .PANEL:
		panel_h := req.rect.height > 0 ? req.rect.height : h
		return {w - SCREEN_PANEL_WIDTH, 0, SCREEN_PANEL_WIDTH, panel_h}
	case .RECT:
		return req.rect
	}
	return {0, 0, w, h}
}

capture_flush :: proc() {
	if capture_request_count == 0 { return }
	rlgl.DrawRenderBatchActive()
	screen := rl.LoadImageFromScreen()
	rl.ImageFormat(&screen, .UNCOMPRESSED_R8G8B8)
	k := f32(screen.width) / f32(rl.GetScreenWidth()) * ui_scale
	for i in 0..<capture_request_count {
		req := capture_requests[i]
		r := capture_region_rect(req)
		x0 := clamp(math.floor(r.x * k), 0, f32(screen.width))
		y0 := clamp(math.floor(r.y * k), 0, f32(screen.height))
		x1 := clamp(math.ceil((r.x + r.width) * k), 0, f32(screen.width))
		y1 := clamp(math.ceil((r.y + r.height) * k), 0, f32(screen.height))
		if x1 - x0 < 1 || y1 - y0 < 1 {
			fmt.printfln("CAPTURE_ERROR empty region for %s", req.name)
			continue
		}
		img := rl.ImageCopy(screen)
		rl.ImageCrop(&img, {x0, y0, x1 - x0, y1 - y0})
		path := fmt.ctprintf("%s/%s.png", capture_dir, req.name)
		if rl.ExportImage(img, path) {
			fmt.printfln("CAPTURE_SHOT %s %dx%d step=%d", path, img.width, img.height, capture_step)
		} else {
			fmt.printfln("CAPTURE_ERROR export failed %s", path)
		}
		rl.UnloadImage(img)
	}
	rl.UnloadImage(screen)
	capture_request_count = 0
}
