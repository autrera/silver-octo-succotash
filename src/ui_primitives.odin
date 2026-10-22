package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

draw_chamfered_panel :: proc(rect: rl.Rectangle, chamfer: f32, fill: rl.Color, border: rl.Color) {
	c := clamp(chamfer, 0, min(rect.width, rect.height) * 0.5)
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	if c <= 0 {
		rl.DrawRectangleRec(rect, fill)
		rl.DrawRectangleLinesEx(rect, 1, border)
		return
	}
	rl.DrawRectangleRec({x + c, y, w - 2 * c, h}, fill)
	rl.DrawRectangleRec({x, y + c, c, h - 2 * c}, fill)
	rl.DrawRectangleRec({x + w - c, y + c, c, h - 2 * c}, fill)
	rl.DrawTriangle({x, y + c}, {x + c, y + c}, {x + c, y}, fill)
	rl.DrawTriangle({x + w - c, y}, {x + w - c, y + c}, {x + w, y + c}, fill)
	rl.DrawTriangle({x + w, y + h - c}, {x + w - c, y + h - c}, {x + w - c, y + h}, fill)
	rl.DrawTriangle({x + c, y + h}, {x + c, y + h - c}, {x, y + h - c}, fill)

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

draw_corner_brackets :: proc(rect: rl.Rectangle, offset: f32, length: f32, color: rl.Color) {
	x := rect.x - offset
	y := rect.y - offset
	w := rect.width + 2 * offset
	h := rect.height + 2 * offset
	l := min(length, min(w * 0.4, h * 0.4))
	if l <= 0 { return }

	rl.DrawLineV({x, y}, {x + l, y}, color)
	rl.DrawLineV({x, y}, {x, y + l}, color)
	rl.DrawLineV({x + w - l, y}, {x + w, y}, color)
	rl.DrawLineV({x + w, y}, {x + w, y + l}, color)
	rl.DrawLineV({x, y + h}, {x + l, y + h}, color)
	rl.DrawLineV({x, y + h - l}, {x, y + h}, color)
	rl.DrawLineV({x + w - l, y + h}, {x + w, y + h}, color)
	rl.DrawLineV({x + w, y + h - l}, {x + w, y + h}, color)
}

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

	glow_col := rl.Fade(border, 0.12)
	rl.DrawRectangleGradientV(i32(x), i32(y), i32(w), i32(h), glow_col, rl.Color{0, 0, 0, 0})

	rl.DrawTriangle(v0, v1, v2, fill)
	rl.DrawTriangle(v0, v2, v3, fill)
	rl.DrawTriangle(v0, v3, v4, fill)
	rl.DrawTriangle(v0, v4, v5, fill)
	rl.DrawTriangle(v0, v5, v6, fill)
	rl.DrawTriangle(v0, v6, v7, fill)

	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)
	rl.DrawPixelV(v0, border)
	rl.DrawPixelV(v1, border)
	rl.DrawPixelV(v2, border)
	rl.DrawPixelV(v3, border)
	rl.DrawPixelV(v4, border)
	rl.DrawPixelV(v5, border)
	rl.DrawPixelV(v6, border)
	rl.DrawPixelV(v7, border)

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
	rl.DrawLineV(iv1, iv2, inner_border)
	rl.DrawLineV(iv2, iv3, inner_border)
	rl.DrawLineV(iv3, iv4, inner_border)
	rl.DrawLineV(iv4, iv5, inner_border)
	rl.DrawLineV(iv5, iv6, inner_border)
	rl.DrawLineV(iv6, iv7, inner_border)
	rl.DrawLineV(iv7, iv0, inner_border)
	rl.DrawPixelV(iv0, inner_border)
	rl.DrawPixelV(iv1, inner_border)
	rl.DrawPixelV(iv2, inner_border)
	rl.DrawPixelV(iv3, inner_border)
	rl.DrawPixelV(iv4, inner_border)
	rl.DrawPixelV(iv5, inner_border)
	rl.DrawPixelV(iv6, inner_border)
	rl.DrawPixelV(iv7, inner_border)
}

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

	glow_col := rl.Fade(border, 0.12)
	rl.DrawRectangleGradientV(i32(x), i32(y), i32(w), i32(h), glow_col, rl.Color{0, 0, 0, 0})

	rl.DrawTriangle(v1, v2, v3, fill)
	rl.DrawTriangle(v1, v3, v4, fill)
	rl.DrawTriangle(v1, v4, v5, fill)
	rl.DrawTriangle(v1, v5, v6, fill)
	rl.DrawTriangle(v1, v6, v7, fill)
	rl.DrawTriangle(v1, v7, v0, fill)

	rl.DrawLineV(v0, v1, border)
	rl.DrawLineV(v1, v2, border)
	rl.DrawLineV(v2, v3, border)
	rl.DrawLineV(v3, v4, border)
	rl.DrawLineV(v4, v5, border)
	rl.DrawLineV(v5, v6, border)
	rl.DrawLineV(v6, v7, border)
	rl.DrawLineV(v7, v0, border)

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

	bracket_col := SCIFI_MINT
	rl.DrawLineV({x + w + 3, y - 3}, {x + w - 12, y - 3}, bracket_col)
	rl.DrawLineV({x + w + 3, y - 3}, {x + w + 3, y + 12}, bracket_col)
	rl.DrawLineV({x + w + 3, y + h + 3}, {x + w - 12, y + h + 3}, bracket_col)
	rl.DrawLineV({x + w + 3, y + h + 3}, {x + w + 3, y + h - 12}, bracket_col)
	rl.DrawLineV({x + wing - 4, y + h + 3}, {x - 3, y + h - wing - 4}, rl.Fade(bracket_col, 0.7))
}

draw_orbital_upgrade_spinner :: proc(center: rl.Vector2, size: f32, progress: f32, color: rl.Color) {
	r_out := size
	r_in := size - max(2.5, size * 0.22)
	rl.DrawRing(center, r_in, r_out, 0, 360, 48, rl.Fade(color, 0.16))

	start: f32 = -90.0
	sweep := clamp(progress, 0.0, 1.0) * 360.0
	if sweep > 0.5 {
		rl.DrawRing(center, r_in, r_out, start, start + sweep, 48, rl.Fade(color, 0.85))
	}

	head := math.mod(laser_anim_time * 280.0, 360.0)
	TRAIL_STEPS :: 12
	for i in 0..<TRAIL_STEPS {
		t := f32(i) / f32(TRAIL_STEPS)
		a0 := head - (t + 1.0 / f32(TRAIL_STEPS)) * 110.0
		a1 := head - t * 110.0
		rl.DrawRing(center, r_in - 3.5, r_in - 1.0, a0, a1, 6, rl.Fade(color, (1.0 - t) * 0.9))
	}

	rad := head * (math.PI / 180.0)
	tip := rl.Vector2{center.x + math.cos(rad) * (r_in - 1.0), center.y + math.sin(rad) * (r_in - 1.0)}
	rl.DrawCircleV(tip, max(1.5, size * 0.12), rl.WHITE)
	rl.DrawCircleV(center, max(1.5, size * 0.1), rl.Fade(color, 0.8))
}

draw_overlay_mini_button :: proc(src_rect: rl.Rectangle, enabled: bool, alpha_factor: f32) {
	rect := rl.Rectangle{math.round(src_rect.x), math.round(src_rect.y), math.round(src_rect.width), math.round(src_rect.height)}
	mouse := ui_mouse()
	hovered := enabled && rl.CheckCollisionPointRec(mouse, rect)
	pressed := hovered && rl.IsMouseButtonDown(.LEFT)

	eff_alpha := hovered ? f32(1.0) : alpha_factor
	bg := rl.Color{10, 24, 20, u8(180.0 * eff_alpha)}
	border := rl.Color{45, 140, 90, u8(160.0 * eff_alpha)}
	text_col := rl.Color{130, 240, 200, u8(240.0 * eff_alpha)}

	if !enabled {
		bg = rl.Color{6, 14, 12, u8(100.0 * eff_alpha)}
		border = rl.Color{30, 55, 40, u8(70.0 * eff_alpha)}
		text_col = rl.Color{75, 105, 90, u8(100.0 * eff_alpha)}
	} else if pressed {
		bg = rl.Color{0, 75, 55, 255}
		border = rl.Color{60, 255, 170, 255}
		text_col = rl.Color{255, 255, 255, 255}
	} else if hovered {
		bg = rl.Color{15, 60, 45, 255}
		border = rl.Color{50, 235, 150, 255}
		text_col = rl.Color{180, 255, 220, 255}
	}

	draw_chamfered_panel({rect.x, rect.y, rect.width - 1, rect.height - 1}, 3, bg, border)
	if hovered {
		draw_corner_brackets({rect.x, rect.y, rect.width - 1, rect.height - 1}, 1, 3, border)
	}

	arm: f32 = 5.0
	thick: f32 = 2.0
	cx := math.round(rect.x + rect.width * 0.5)
	cy := math.round(rect.y + rect.height * 0.5) + (pressed ? 1.0 : 0.0)
	rl.DrawRectangleRec({cx - arm, cy - thick * 0.5, arm * 2, thick}, text_col)
	rl.DrawRectangleRec({cx - thick * 0.5, cy - arm, thick, arm * 2}, text_col)
}

conquered_planet_overlay_ammo_btn_rect :: proc(badge_rect: rl.Rectangle) -> rl.Rectangle {
	btn_w: f32 = 20.0
	btn_h: f32 = 20.0
	row1_cy := badge_rect.y + 17.0
	btn_x := badge_rect.x + badge_rect.width - btn_w - 7.0
	btn_y := row1_cy - btn_h * 0.5
	return rl.Rectangle{btn_x, btn_y, btn_w, btn_h}
}

overlay_ammo_button_visible :: proc(p: int) -> bool {
	return orbital_defense_level[p] > 0 && !orbital_defense_building[p]
}

planet_orbital_ammo_build_progress :: proc(p: int) -> f32 {
	if p < 0 || p >= SECTOR_COUNT || !orbital_defense_ammo_building[p] {
		return -1.0
	}
	return clamp(orbital_defense_ammo_progress[p] / ORBITAL_DEFENSE_AMMO_BUILD_TIME, 0.0, 1.0)
}

conquered_planet_overlay_rect :: proc(p: int, center_screen: rl.Vector2, screen_r: f32, is_selected: bool, viewport_w, screen_h: f32) -> rl.Rectangle {
	def_lvl := orbital_defense_level[p]
	miners := planet_miner_drone_count(p)
	cap := planet_mining_cap(p)
	combat := planet_combat_drone_count(p)

	def_str := rl.TextFormat("%d/%d", orbital_defense_ammo[p], ORBITAL_DEFENSE_AMMO_MAX)
	if orbital_defense_building[p] || def_lvl <= 0 {
		def_str = rl.TextFormat("--")
	}
	miner_str := rl.TextFormat("%d/%d", miners, cap)
	combat_str := rl.TextFormat("%d", combat)

	def_txt_w := f32(rl.MeasureText(def_str, 18))
	miner_txt_w := f32(rl.MeasureText(miner_str, 18))
	combat_txt_w := f32(rl.MeasureText(combat_str, 18))

	max_txt_w := max(def_txt_w, max(miner_txt_w, combat_txt_w))
	btn_w: f32 = 20.0
	w := max(58.0 + max_txt_w + btn_w, 128.0)
	h: f32 = 102.0

	overlay_y := planet_label_y(center_screen.y, screen_r, is_selected) + PLANET_LABEL_H + 4.0
	overlay_x := center_screen.x - w * 0.5
	overlay_x = clamp(overlay_x, 6.0, max(6.0, viewport_w - w - 6.0))

	return rl.Rectangle{overlay_x, overlay_y, w, h}
}

draw_conquered_planet_overlay_badge :: proc(p: int, center_screen: rl.Vector2, screen_r: f32, is_selected: bool, viewport_w, screen_h: f32) {
	rect := conquered_planet_overlay_rect(p, center_screen, screen_r, is_selected, viewport_w, screen_h)
	if rect.y + rect.height > screen_h - 4.0 || rect.y < 4.0 {
		return
	}

	alpha_factor := is_selected ? f32(1.0) : f32(0.30)

	bg_alpha := u8(is_selected ? 255 : 80)
	rl.DrawRectangleRounded(rect, 0.16, 4, rl.Color{4, 12, 10, bg_alpha})

	if progress := planet_orbital_ammo_build_progress(p); progress >= 0.0 {
		fill_w := rect.width * progress
		if fill_w > 0.5 {
			scissor_x := c.int(math.floor(rect.x))
			scissor_y := c.int(math.floor(rect.y))
			scissor_w := c.int(math.ceil(fill_w))
			scissor_h := c.int(math.ceil(rect.y + 34.0)) - scissor_y
			rl.BeginScissorMode(c.int(f32(scissor_x) * ui_scale), c.int(f32(scissor_y) * ui_scale), c.int(math.ceil(f32(scissor_w) * ui_scale)), c.int(math.ceil(f32(scissor_h) * ui_scale)))
			rl.DrawRectangleRounded(rect, 0.16, 4, rl.Color{0, 200, 120, u8(110.0 * alpha_factor)})
			rl.EndScissorMode()
		}
	}

	border_col := rl.Color{45, 175, 100, u8(130.0 * alpha_factor)}
	if is_selected {
		border_col = rl.Color{65, 215, 130, 240}
	}
	rl.DrawRectangleRoundedLinesEx(rect, 0.16, 4, 1.2, border_col)

	def_lvl := orbital_defense_level[p]
	miners := planet_miner_drone_count(p)
	cap := planet_mining_cap(p)
	combat := planet_combat_drone_count(p)

	def_str := rl.TextFormat("%d/%d", orbital_defense_ammo[p], ORBITAL_DEFENSE_AMMO_MAX)
	if orbital_defense_building[p] || def_lvl <= 0 {
		def_str = rl.TextFormat("--")
	}
	miner_str := rl.TextFormat("%d/%d", miners, cap)
	combat_str := rl.TextFormat("%d", combat)

	icon_size: f32 = 26.0
	icon_x := rect.x + 19.0
	txt_x := i32(rect.x + 38.0)

	div1_y := rect.y + 34.0
	div2_y := rect.y + 68.0
	div_col := is_selected ? rl.Color{35, 95, 60, 120} : rl.Color{35, 95, 60, u8(50.0 * alpha_factor)}
	rl.DrawLineEx({rect.x + 8.0, div1_y}, {rect.x + rect.width - 8.0, div1_y}, 1.0, div_col)
	rl.DrawLineEx({rect.x + 8.0, div2_y}, {rect.x + rect.width - 8.0, div2_y}, 1.0, div_col)

	icon_alpha := u8(240.0 * alpha_factor)
	text_alpha := u8(240.0 * alpha_factor)
	muted_alpha := u8(140.0 * alpha_factor)

	shadow_col := rl.Color{0, 0, 0, u8(180.0 * alpha_factor)}

	row1_cy := rect.y + 17.0
	def_empty := def_lvl > 0 && orbital_defense_ammo[p] <= 0
	def_col := def_lvl > 0 ? rl.Color{130, 240, 200, icon_alpha} : rl.Color{130, 155, 145, muted_alpha}
	if def_empty {
		def_col = rl.Color{255, 70, 70, icon_alpha}
	}
	if orbital_defense_building[p] {
		draw_orbital_upgrade_spinner({icon_x, row1_cy}, 12.0, orbital_defense_progress[p] / ORBITAL_DEFENSE_BUILD_TIME, rl.Color{0, 240, 216, icon_alpha})
	} else {
		ammo_level := f32(orbital_defense_ammo[p]) / f32(ORBITAL_DEFENSE_AMMO_MAX)
		draw_battery_cell(rl.Rectangle{icon_x - 13.0, row1_cy - 12.0, 26.0, 24.0}, ammo_level, def_col, def_col)
	}
	rl.DrawText(def_str, txt_x + 1, i32(row1_cy - 8.0), 18, shadow_col)
	def_txt_col := def_lvl > 0 ? rl.Color{130, 240, 200, text_alpha} : rl.Color{130, 155, 145, muted_alpha}
	if def_empty {
		def_txt_col = rl.Color{255, 70, 70, text_alpha}
	}
	rl.DrawText(def_str, txt_x, i32(row1_cy - 9.0), 18, def_txt_col)

	ammo_btn_rect := conquered_planet_overlay_ammo_btn_rect(rect)
	if overlay_ammo_button_visible(p) {
		draw_overlay_mini_button(ammo_btn_rect, can_build_orbital_ammo(p), alpha_factor)
	}
	if p == EARTH {
		draw_overlay_mini_button(overlay_drone_plus_btn_rect(rect, rect.y + 51.0), can_queue_unit(.MINING), alpha_factor)
		draw_overlay_mini_button(overlay_drone_plus_btn_rect(rect, rect.y + 85.0), can_queue_unit(.COMBAT), alpha_factor)
	}

	row2_cy := rect.y + 51.0
	miner_col := miners > 0 ? rl.Color{240, 180, 60, icon_alpha} : rl.Color{140, 140, 140, muted_alpha}
	draw_unit_icon(.MINING, {icon_x, row2_cy}, icon_size, miner_col)
	rl.DrawText(miner_str, txt_x + 1, i32(row2_cy - 8.0), 18, shadow_col)
	rl.DrawText(miner_str, txt_x, i32(row2_cy - 9.0), 18, miners > 0 ? rl.Color{240, 180, 60, text_alpha} : rl.Color{140, 140, 140, muted_alpha})

	row3_cy := rect.y + 85.0
	combat_col := combat > 0 ? rl.Color{100, 200, 255, icon_alpha} : rl.Color{120, 145, 155, muted_alpha}
	draw_unit_icon(.COMBAT, {icon_x, row3_cy}, icon_size, combat_col)
	rl.DrawText(combat_str, txt_x + 1, i32(row3_cy - 8.0), 18, shadow_col)
	rl.DrawText(combat_str, txt_x, i32(row3_cy - 9.0), 18, combat_col)
}

draw_conquered_planet_overlays :: proc(viewport_w, screen_h: f32) {
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) || p == selected_planet { continue }

		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := ui_world_to_screen(planets[p].position)
		if center_screen.x < -100 || center_screen.x > viewport_w + 100 || center_screen.y < -100 || center_screen.y > screen_h + 100 {
			continue
		}

		limb_screen := ui_world_to_screen(planets[p].position + cam_right * planets[p].radius)
		screen_r := rl.Vector2Distance(center_screen, limb_screen)

		draw_conquered_planet_overlay_badge(p, center_screen, screen_r, false, viewport_w, screen_h)
	}

	if selected_planet >= 0 && selected_planet < PLANET_COUNT && planet_liberated(selected_planet) {
		to_planet := planets[selected_planet].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) > 0.1 {
			center_screen := ui_world_to_screen(planets[selected_planet].position)
			if center_screen.x >= -100 && center_screen.x <= viewport_w + 100 && center_screen.y >= -100 && center_screen.y <= screen_h + 100 {
				limb_screen := ui_world_to_screen(planets[selected_planet].position + cam_right * planets[selected_planet].radius)
				screen_r := rl.Vector2Distance(center_screen, limb_screen)

				draw_conquered_planet_overlay_badge(selected_planet, center_screen, screen_r, true, viewport_w, screen_h)
			}
		}
	}
}

overlay_drone_plus_btn_rect :: proc(badge_rect: rl.Rectangle, row_cy: f32) -> rl.Rectangle {
	ammo := conquered_planet_overlay_ammo_btn_rect(badge_rect)
	return rl.Rectangle{ammo.x, row_cy - ammo.height * 0.5, ammo.width, ammo.height}
}

overlay_drone_row_rect :: proc(badge_rect: rl.Rectangle, kind: Unit_Type) -> rl.Rectangle {
	top := badge_rect.y + 34.0
	if kind == .COMBAT { top += 34.0 }
	return rl.Rectangle{badge_rect.x, top, badge_rect.width, 34.0}
}

overlay_drone_row_cy :: proc(badge_rect: rl.Rectangle, kind: Unit_Type) -> f32 {
	return badge_rect.y + (kind == .MINING ? f32(51.0) : f32(85.0))
}

pick_overlay_drone_row :: proc(mouse: rl.Vector2) -> (planet: int, kind: Unit_Type, on_plus: bool) {
	viewport_w := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	screen_h := f32(ui_screen_h())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) { continue }
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := ui_world_to_screen(planets[p].position)
		limb_screen := ui_world_to_screen(planets[p].position + cam_right * planets[p].radius)
		screen_r := rl.Vector2Distance(center_screen, limb_screen)

		rect := conquered_planet_overlay_rect(p, center_screen, screen_r, p == selected_planet, viewport_w, screen_h)
		if rect.y + rect.height > screen_h - 4.0 || rect.y < 4.0 { continue }
		for k in Unit_Type {
			if p == EARTH && rl.CheckCollisionPointRec(mouse, overlay_drone_plus_btn_rect(rect, overlay_drone_row_cy(rect, k))) {
				return p, k, true
			}
			if rl.CheckCollisionPointRec(mouse, overlay_drone_row_rect(rect, k)) {
				return p, k, false
			}
		}
	}
	return -1, .MINING, false
}

pick_conquered_planet_overlay_ammo_button :: proc(mouse: rl.Vector2) -> int {
	viewport_w := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	screen_h := f32(ui_screen_h())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	if selected_planet >= 0 && selected_planet < PLANET_COUNT && planet_liberated(selected_planet) {
		p := selected_planet
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) > 0.1 {
			center_screen := ui_world_to_screen(planets[p].position)
			limb_screen := ui_world_to_screen(planets[p].position + cam_right * planets[p].radius)
			screen_r := rl.Vector2Distance(center_screen, limb_screen)
			rect := conquered_planet_overlay_rect(p, center_screen, screen_r, true, viewport_w, screen_h)
			btn_rect := conquered_planet_overlay_ammo_btn_rect(rect)
			if rl.CheckCollisionPointRec(mouse, btn_rect) {
				return p
			}
		}
	}

	for p in 0..<PLANET_COUNT {
		if p == selected_planet || !planet_liberated(p) { continue }
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := ui_world_to_screen(planets[p].position)
		limb_screen := ui_world_to_screen(planets[p].position + cam_right * planets[p].radius)
		screen_r := rl.Vector2Distance(center_screen, limb_screen)

		rect := conquered_planet_overlay_rect(p, center_screen, screen_r, false, viewport_w, screen_h)
		btn_rect := conquered_planet_overlay_ammo_btn_rect(rect)
		if overlay_ammo_button_visible(p) && rl.CheckCollisionPointRec(mouse, btn_rect) {
			return p
		}
	}
	return -1
}

pick_conquered_planet_overlay :: proc(mouse: rl.Vector2) -> int {
	viewport_w := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	screen_h := f32(ui_screen_h())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) { continue }
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := ui_world_to_screen(planets[p].position)
		limb_screen := ui_world_to_screen(planets[p].position + cam_right * planets[p].radius)
		screen_r := rl.Vector2Distance(center_screen, limb_screen)

		rect := conquered_planet_overlay_rect(p, center_screen, screen_r, p == selected_planet, viewport_w, screen_h)
		if rl.CheckCollisionPointRec(mouse, rect) {
			return p
		}
	}
	return -1
}

draw_tactical_container :: proc(rect: rl.Rectangle) {
	round := menu_round(rect, 18)
	rl.DrawRectangleRounded(rect, round, 16, SCIFI_PANEL)
	rl.DrawRectangleRoundedLinesEx(rect, round, 16, 1.5, rl.Fade(SCIFI_GREEN, 0.55))
}

draw_section_header :: proc(x, y, w: f32, title: cstring, color: rl.Color) {
	rl.DrawText(title, i32(x), i32(y), 12, color)
	tw := f32(rl.MeasureText(title, 12))
	line_x := x + tw + 8
	if line_x < x + w - 4 {
		rl.DrawLineV({line_x, y + 6}, {x + w - 4, y + 6}, rl.Fade(color, 0.35))
		rl.DrawLineV({x + w - 4, y + 3}, {x + w - 4, y + 9}, color)
	}
}

draw_status_card :: proc(card: rl.Rectangle, border: rl.Color) {
	draw_chamfered_panel(card, 6, SCIFI_PANEL_SOLID, border)
	draw_corner_brackets(card, 2, 8, border)
	rl.DrawLineV({card.x + 8, card.y + 1}, {card.x + card.width - 8, card.y + 1}, rl.Color{255, 255, 255, 30})
}

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

draw_button :: proc(rect: rl.Rectangle, label: cstring, color: rl.Color = SCIFI_PANEL_SOLID, enabled: bool = true) {
	hovered := enabled && rl.CheckCollisionPointRec(ui_mouse(), rect)
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
		border = SCIFI_GREEN
		text_col = SCIFI_GREEN
	}

	draw_chamfered_panel(rect, chamfer, fill, border)

	if hovered && enabled {
		draw_corner_brackets(rect, 2, 6, SCIFI_GREEN)
	}

	tw := f32(rl.MeasureText(label, 12))
	text_x := rect.x + (rect.width - tw) / 2
	if text_x < rect.x + 8 { text_x = rect.x + 8 }
	text_y := rect.y + (rect.height - 12) / 2 + (pressed ? 1.0 : 0.0)
	rl.DrawText(label, c.int(text_x), c.int(text_y), 12, text_col)
}


draw_queue_slot :: proc(rect: rl.Rectangle, queued: bool, kind: Unit_Type, progress: f32 = -1) {
	color := SCIFI_PANEL_SOLID
	border := SCIFI_DIM
	symbol: cstring = ""
	accent := SCIFI_AMBER
	if queued {
		color = rl.Color{0, 65, 85, 255}
		if kind == .COMBAT { color = rl.Color{15, 45, 90, 255}; accent = SCIFI_BLUE }
		border = SCIFI_GREEN
		symbol = "M"
		if kind == .COMBAT { symbol = "C" }
	}
	draw_chamfered_panel(rect, 3, color, border)
	if queued && progress >= 0 {
		fill_rect := rl.Rectangle{rect.x, rect.y, rect.width * progress, rect.height}
		rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 140})
	}
	if queued {
		draw_corner_brackets(rect, 1, 3, border)
		tw := f32(rl.MeasureText(symbol, 12))
		tx := rect.x + (rect.width - tw) / 2
		ty := rect.y + (rect.height - 12) / 2
		rl.DrawText(symbol, c.int(tx + 1), c.int(ty + 1), 12, rl.Color{0, 0, 0, 160})
		rl.DrawText(symbol, c.int(tx), c.int(ty), 12, accent)
	}
}

draw_autobuild_radio_buttons :: proc(panel_x: f32) {
	off_rect, miner_rect, combat_rect := autobuild_radio_rects(panel_x)
	total_rect := rl.Rectangle{off_rect.x, off_rect.y, (combat_rect.x + combat_rect.width) - off_rect.x, off_rect.height}
	mouse := ui_mouse()

	lbl: cstring = "AUTO:"
	lbl_w := f32(rl.MeasureText(lbl, 11))
	lbl_x := off_rect.x - lbl_w - 6
	rl.DrawRectangleRec({lbl_x - 4, total_rect.y - 1, lbl_w + 8, total_rect.height + 2}, SCIFI_PANEL_SOLID)
	rl.DrawText(lbl, i32(lbl_x), i32(total_rect.y + 4), 11, SCIFI_MUTED)

	draw_chamfered_panel(total_rect, 3, SCIFI_PANEL_SOLID, SCIFI_DIM)

	{
		selected := auto_build_mode == .OFF
		hovered := rl.CheckCollisionPointRec(mouse, off_rect)
		fill := SCIFI_PANEL_SOLID
		border := rl.Color{0, 0, 0, 0}
		text_col := SCIFI_MUTED

		if selected {
			fill = rl.Color{0, 60, 75, 255}
			border = SCIFI_GREEN
			text_col = SCIFI_MINT
		} else if hovered {
			fill = rl.Color{10, 36, 46, 255}
			border = SCIFI_STEEL
			text_col = SCIFI_TEXT
		}

		if selected || hovered {
			draw_chamfered_panel(off_rect, 2, fill, border)
		}
		if selected {
			rl.DrawLineV({off_rect.x + 2, off_rect.y + 1}, {off_rect.x + off_rect.width - 2, off_rect.y + 1}, SCIFI_MINT)
		}
		tw := f32(rl.MeasureText("Off", 12))
		rl.DrawText("Off", i32(off_rect.x + (off_rect.width - tw) / 2), i32(off_rect.y + 4), 12, text_col)
	}

	{
		selected := auto_build_mode == .MINERS
		hovered := rl.CheckCollisionPointRec(mouse, miner_rect)
		fill := SCIFI_PANEL_SOLID
		border := rl.Color{0, 0, 0, 0}
		text_col := SCIFI_MUTED

		if selected {
			fill = rl.Color{60, 40, 10, 255}
			border = SCIFI_AMBER
			text_col = SCIFI_AMBER
		} else if hovered {
			fill = rl.Color{32, 22, 8, 255}
			border = SCIFI_AMBER_DIM
			text_col = SCIFI_TEXT
		}

		if selected || hovered {
			draw_chamfered_panel(miner_rect, 2, fill, border)
		}
		if selected {
			rl.DrawLineV({miner_rect.x + 2, miner_rect.y + 1}, {miner_rect.x + miner_rect.width - 2, miner_rect.y + 1}, SCIFI_AMBER)
		}
		tw := f32(rl.MeasureText("M", 12))
		rl.DrawText("M", i32(miner_rect.x + (miner_rect.width - tw) / 2), i32(miner_rect.y + 4), 12, text_col)
	}

	{
		selected := auto_build_mode == .COMBAT
		hovered := rl.CheckCollisionPointRec(mouse, combat_rect)
		fill := SCIFI_PANEL_SOLID
		border := rl.Color{0, 0, 0, 0}
		text_col := SCIFI_MUTED

		if selected {
			fill = rl.Color{10, 45, 80, 255}
			border = SCIFI_BLUE
			text_col = SCIFI_BLUE
		} else if hovered {
			fill = rl.Color{8, 28, 48, 255}
			border = SCIFI_STEEL
			text_col = SCIFI_TEXT
		}

		if selected || hovered {
			draw_chamfered_panel(combat_rect, 2, fill, border)
		}
		if selected {
			rl.DrawLineV({combat_rect.x + 2, combat_rect.y + 1}, {combat_rect.x + combat_rect.width - 2, combat_rect.y + 1}, SCIFI_BLUE)
		}
		tw := f32(rl.MeasureText("C", 12))
		rl.DrawText("C", i32(combat_rect.x + (combat_rect.width - tw) / 2), i32(combat_rect.y + 4), 12, text_col)
	}

	rl.DrawLineV({off_rect.x + off_rect.width, total_rect.y + 2}, {off_rect.x + off_rect.width, total_rect.y + total_rect.height - 2}, SCIFI_DIM)
	rl.DrawLineV({miner_rect.x + miner_rect.width, total_rect.y + 2}, {miner_rect.x + miner_rect.width, total_rect.y + total_rect.height - 2}, SCIFI_DIM)

	rl.DrawRectangleLinesEx(total_rect, 1, SCIFI_DIM)
}

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
	case .DEPOSITING: return SCIFI_GREEN
	case .GUARDING: return rl.RED
	case .CONSTRUCTING: return SCIFI_GREEN
	}
	return rl.WHITE
}

selection_count :: proc() -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if selected_units[i] { count += 1 } }
	return count
}

