package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

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
	rl.DrawPixelV(v0, border)
	rl.DrawPixelV(v1, border)
	rl.DrawPixelV(v2, border)
	rl.DrawPixelV(v3, border)
	rl.DrawPixelV(v4, border)
	rl.DrawPixelV(v5, border)
	rl.DrawPixelV(v6, border)
	rl.DrawPixelV(v7, border)

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

	fill_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.35)}
	rl.DrawTriangle(nose, wing_l, tail, fill_col)
	rl.DrawTriangle(nose, tail, wing_r, fill_col)

	thick := max(1.0, size * 0.12)
	rl.DrawLineEx(nose, wing_l, thick, color)
	rl.DrawLineEx(wing_l, tail, thick, color)
	rl.DrawLineEx(tail, wing_r, thick, color)
	rl.DrawLineEx(wing_r, nose, thick, color)
	spine_col := rl.Color{SCIFI_MINT.r, SCIFI_MINT.g, SCIFI_MINT.b, color.a}
	rl.DrawLineEx(nose, tail, thick, spine_col)
}

// Tactical defense shield icon for planetary defense level
draw_defense_vector_icon :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
	w := size * 0.9
	h := size * 1.15
	p_top_l := rl.Vector2{center.x - w, center.y - h * 0.55}
	p_top_m := rl.Vector2{center.x, center.y - h * 0.40}
	p_top_r := rl.Vector2{center.x + w, center.y - h * 0.55}
	p_mid_r := rl.Vector2{center.x + w, center.y + h * 0.10}
	p_tip   := rl.Vector2{center.x, center.y + h * 0.80}
	p_mid_l := rl.Vector2{center.x - w, center.y + h * 0.10}

	// Interior fill scaled by color alpha
	fill_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.30)}
	rl.DrawTriangle(p_top_l, p_mid_l, p_tip, fill_col)
	rl.DrawTriangle(p_top_l, p_tip, p_top_m, fill_col)
	rl.DrawTriangle(p_top_m, p_tip, p_top_r, fill_col)
	rl.DrawTriangle(p_top_r, p_tip, p_mid_r, fill_col)

	// Perimeter lines
	thick := max(1.0, size * 0.12)
	rl.DrawLineEx(p_top_l, p_top_m, thick, color)
	rl.DrawLineEx(p_top_m, p_top_r, thick, color)
	rl.DrawLineEx(p_top_r, p_mid_r, thick, color)
	rl.DrawLineEx(p_mid_r, p_tip, thick, color)
	rl.DrawLineEx(p_tip, p_mid_l, thick, color)
	rl.DrawLineEx(p_mid_l, p_top_l, thick, color)

	// Inner vertical spine
	spine_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.75)}
	rl.DrawLineEx(p_top_m, {center.x, center.y + h * 0.45}, thick, spine_col)
}

// Rotating upgrade spinner shown in place of the defense shield icon while
// an orbital defense build/upgrade is underway. Animated on laser_anim_time
// so it freezes on pause like the rest of the sim-driven UI.
draw_orbital_upgrade_spinner :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
	r := size * 0.75
	rl.DrawCircleLines(c.int(center.x), c.int(center.y), r, rl.Fade(color, 0.35))
	ang := laser_anim_time * 5.0
	head := rl.Vector2{center.x + math.cos(ang) * r, center.y + math.sin(ang) * r}
	tail := rl.Vector2{center.x - math.cos(ang) * r * 0.45, center.y - math.sin(ang) * r * 0.45}
	rl.DrawLineEx(tail, head, max(1.5, size * 0.18), color)
	rl.DrawCircleV(center, max(1.5, size * 0.14), color)
}

// Stylized mining pickaxe icon for mining drone counts
draw_miner_vector_icon :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
	// Diagonal handle
	h_start := rl.Vector2{center.x - size * 0.55, center.y + size * 0.65}
	h_end   := rl.Vector2{center.x + size * 0.40, center.y - size * 0.45}
	handle_thick := max(1.5, size * 0.18)
	handle_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.85)}
	rl.DrawLineEx(h_start, h_end, handle_thick, handle_col)

	// Arched double-sided pick head
	p_tip1 := rl.Vector2{center.x - size * 0.30, center.y - size * 0.75}
	p_mid  := rl.Vector2{center.x + size * 0.35, center.y - size * 0.40}
	p_tip2 := rl.Vector2{center.x + size * 0.75, center.y + size * 0.20}
	p_back := rl.Vector2{center.x + size * 0.48, center.y - size * 0.52}

	rl.DrawTriangle(p_tip1, p_mid, p_back, color)
	rl.DrawTriangle(p_mid, p_tip2, p_back, color)
	blade_thick := max(1.0, size * 0.12)
	rl.DrawLineEx(p_tip1, p_back, blade_thick, color)
	rl.DrawLineEx(p_back, p_tip2, blade_thick, color)
	rl.DrawLineEx(p_tip2, p_mid, blade_thick, color)
	rl.DrawLineEx(p_mid, p_tip1, blade_thick, color)
}

// Tactical ammunition vector icon for orbital defense cannon shells
draw_ammo_vector_icon :: proc(center: rl.Vector2, size: f32, color: rl.Color) {
	w := size * 0.38
	h := size * 0.85
	tip        := rl.Vector2{center.x, center.y - h * 0.70}
	shoulder_l := rl.Vector2{center.x - w, center.y - h * 0.15}
	shoulder_r := rl.Vector2{center.x + w, center.y - h * 0.15}
	base_l     := rl.Vector2{center.x - w, center.y + h * 0.45}
	base_r     := rl.Vector2{center.x + w, center.y + h * 0.45}
	rim_l      := rl.Vector2{center.x - w * 1.25, center.y + h * 0.65}
	rim_r      := rl.Vector2{center.x + w * 1.25, center.y + h * 0.65}
	rim_bot_l  := rl.Vector2{center.x - w * 1.25, center.y + h * 0.75}
	rim_bot_r  := rl.Vector2{center.x + w * 1.25, center.y + h * 0.75}

	fill_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.40)}
	rl.DrawTriangle(tip, shoulder_l, shoulder_r, fill_col)
	rl.DrawTriangle(shoulder_l, base_l, shoulder_r, fill_col)
	rl.DrawTriangle(shoulder_r, base_l, base_r, fill_col)
	rl.DrawTriangle(base_l, rim_bot_l, base_r, fill_col)
	rl.DrawTriangle(base_r, rim_bot_l, rim_bot_r, fill_col)

	thick := max(1.0, size * 0.12)
	rl.DrawLineEx(tip, shoulder_l, thick, color)
	rl.DrawLineEx(shoulder_l, base_l, thick, color)
	rl.DrawLineEx(base_l, rim_l, thick, color)
	rl.DrawLineEx(rim_l, rim_bot_l, thick, color)
	rl.DrawLineEx(rim_bot_l, rim_bot_r, thick, color)
	rl.DrawLineEx(rim_bot_r, rim_r, thick, color)
	rl.DrawLineEx(rim_r, base_r, thick, color)
	rl.DrawLineEx(base_r, shoulder_r, thick, color)
	rl.DrawLineEx(shoulder_r, tip, thick, color)

	casing_col := rl.Color{color.r, color.g, color.b, u8(f32(color.a) * 0.75)}
	rl.DrawLineEx(shoulder_l, shoulder_r, thick, casing_col)
}

// Small high-tech tactile action button on overlay badges
draw_overlay_mini_button :: proc(rect: rl.Rectangle, label: cstring, enabled: bool, alpha_factor: f32) {
	mouse := rl.GetMousePosition()
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

	draw_chamfered_panel(rect, 3, bg, border)
	if hovered {
		draw_corner_brackets(rect, 1, 3, border)
	}

	tw := f32(rl.MeasureText(label, 14))
	tx := i32(rect.x + (rect.width - tw) * 0.5)
	ty := i32(rect.y + (rect.height - 14) * 0.5 + (pressed ? 1.0 : 0.0))
	rl.DrawText(label, tx, ty, 14, text_col)
}

// Returns the screen rectangle for the small '+' ammo build button on an overlay badge
conquered_planet_overlay_ammo_btn_rect :: proc(badge_rect: rl.Rectangle) -> rl.Rectangle {
	btn_w: f32 = 20.0
	btn_h: f32 = 20.0
	row1_cy := badge_rect.y + 17.0
	btn_x := badge_rect.x + badge_rect.width - btn_w - 7.0
	btn_y := row1_cy - btn_h * 0.5
	return rl.Rectangle{btn_x, btn_y, btn_w, btn_h}
}

// Returns normalized build progress [0.0, 1.0] for orbital ammo on planet p, or -1.0 if not building
planet_orbital_ammo_build_progress :: proc(p: int) -> f32 {
	if p < 0 || p >= SECTOR_COUNT || !orbital_defense_ammo_building[p] {
		return -1.0
	}
	return clamp(orbital_defense_ammo_progress[p] / ORBITAL_DEFENSE_AMMO_BUILD_TIME, 0.0, 1.0)
}

// Calculates screen-space bounding rectangle for a conquered planet status overlay
conquered_planet_overlay_rect :: proc(p: int, center_screen: rl.Vector2, screen_r: f32, is_selected: bool, viewport_w, screen_h: f32) -> rl.Rectangle {
	def_lvl := orbital_defense_level[p]
	miners := planet_miner_drone_count(p)
	cap := planet_mining_cap(p)
	combat := planet_combat_drone_count(p)

	def_str := rl.TextFormat("%d/%d", orbital_defense_ammo[p], ORBITAL_DEFENSE_AMMO_MAX)
	if def_lvl <= 0 && !orbital_defense_building[p] {
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

	eff_r := screen_r
	if is_selected {
		eff_r = max(screen_r, max(planets[p].radius * 5.0, 20.0) + 9.0)
	}

	// 3x wider spacing from planet bottom/reticle (22px)
	overlay_y := center_screen.y + eff_r + 22.0
	overlay_x := center_screen.x - w * 0.5
	overlay_x = clamp(overlay_x, 6.0, max(6.0, viewport_w - w - 6.0))

	return rl.Rectangle{overlay_x, overlay_y, w, h}
}

// Renders the transparent overlay badge with subtle green border below a conquered planet
draw_conquered_planet_overlay_badge :: proc(p: int, center_screen: rl.Vector2, screen_r: f32, is_selected: bool, viewport_w, screen_h: f32) {
	rect := conquered_planet_overlay_rect(p, center_screen, screen_r, is_selected, viewport_w, screen_h)
	if rect.y + rect.height > screen_h - 4.0 || rect.y < 4.0 {
		return
	}

	// Unselected badges are faint and unobtrusive (~30% alpha);
	// selected badges are fully visible and bright (100% alpha).
	alpha_factor := is_selected ? f32(1.0) : f32(0.30)

	// 1. Dark solid background when selected:
	// Remove background opacity/transparency (alpha 255) so planets, bright rings,
	// and beam lines behind the badge do not bleed through, making it completely legible.
	// When unselected, subtle translucent glass backing (alpha 80).
	bg_alpha := u8(is_selected ? 255 : 80)
	rl.DrawRectangleRounded(rect, 0.16, 4, rl.Color{4, 12, 10, bg_alpha})

	// Ammo construction progress bar filling Row 1 background
	if progress := planet_orbital_ammo_build_progress(p); progress >= 0.0 {
		fill_w := rect.width * progress
		if fill_w > 0.5 {
			scissor_x := c.int(math.floor(rect.x))
			scissor_y := c.int(math.floor(rect.y))
			scissor_w := c.int(math.ceil(fill_w))
			scissor_h := c.int(math.ceil(rect.y + 34.0)) - scissor_y
			rl.BeginScissorMode(scissor_x, scissor_y, scissor_w, scissor_h)
			rl.DrawRectangleRounded(rect, 0.16, 4, rl.Color{0, 200, 120, u8(110.0 * alpha_factor)})
			rl.EndScissorMode()
		}
	}

	// 2. Green border:
	// Selected: high-contrast bright sci-fi border; Unselected: subtle
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
	if def_lvl <= 0 && !orbital_defense_building[p] {
		def_str = rl.TextFormat("--")
	}
	miner_str := rl.TextFormat("%d/%d", miners, cap)
	combat_str := rl.TextFormat("%d", combat)

	icon_size: f32 = 12.0
	icon_x := rect.x + 19.0
	txt_x := i32(rect.x + 38.0)

	// Horizontal micro-dividers between stacked rows
	div1_y := rect.y + 34.0
	div2_y := rect.y + 68.0
	div_col := is_selected ? rl.Color{35, 95, 60, 120} : rl.Color{35, 95, 60, u8(50.0 * alpha_factor)}
	rl.DrawLineEx({rect.x + 8.0, div1_y}, {rect.x + rect.width - 8.0, div1_y}, 1.0, div_col)
	rl.DrawLineEx({rect.x + 8.0, div2_y}, {rect.x + rect.width - 8.0, div2_y}, 1.0, div_col)

	icon_alpha := u8(240.0 * alpha_factor)
	text_alpha := u8(240.0 * alpha_factor)
	muted_alpha := u8(140.0 * alpha_factor)

	shadow_col := rl.Color{0, 0, 0, u8(180.0 * alpha_factor)}

	// Row 1: Planetary Defenses (spinner while a build is underway; ammo
	// count when built, red shield icon when the battery is empty)
	row1_cy := rect.y + 17.0
	def_empty := def_lvl > 0 && orbital_defense_ammo[p] <= 0
	def_col := def_lvl > 0 ? rl.Color{130, 240, 200, icon_alpha} : rl.Color{130, 155, 145, muted_alpha}
	if def_empty {
		def_col = rl.Color{255, 70, 70, icon_alpha}
	}
	if orbital_defense_building[p] || orbital_defense_ammo_building[p] {
		draw_orbital_upgrade_spinner({icon_x, row1_cy}, icon_size, rl.Color{0, 240, 216, icon_alpha})
	} else {
		draw_defense_vector_icon({icon_x, row1_cy}, icon_size, def_col)
	}
	rl.DrawText(def_str, txt_x + 1, i32(row1_cy - 8.0), 18, shadow_col)
	def_txt_col := def_lvl > 0 ? rl.Color{130, 240, 200, text_alpha} : rl.Color{130, 155, 145, muted_alpha}
	if def_empty {
		def_txt_col = rl.Color{255, 70, 70, text_alpha}
	}
	rl.DrawText(def_str, txt_x, i32(row1_cy - 9.0), 18, def_txt_col)

	// Small '+' button at the right of the ammo info to queue ammo build
	ammo_btn_rect := conquered_planet_overlay_ammo_btn_rect(rect)
	can_ammo := can_build_orbital_ammo(p)
	draw_overlay_mini_button(ammo_btn_rect, "+", can_ammo, alpha_factor)

	// Row 2: Miners
	row2_cy := rect.y + 51.0
	miner_col := miners > 0 ? rl.Color{240, 180, 60, icon_alpha} : rl.Color{140, 140, 140, muted_alpha}
	draw_miner_vector_icon({icon_x, row2_cy}, icon_size, miner_col)
	rl.DrawText(miner_str, txt_x + 1, i32(row2_cy - 8.0), 18, shadow_col)
	rl.DrawText(miner_str, txt_x, i32(row2_cy - 9.0), 18, miners > 0 ? rl.Color{240, 180, 60, text_alpha} : rl.Color{140, 140, 140, muted_alpha})

	// Row 3: Combat Drones
	row3_cy := rect.y + 85.0
	combat_col := combat > 0 ? rl.Color{100, 200, 255, icon_alpha} : rl.Color{120, 145, 155, muted_alpha}
	draw_fighter_vector_icon({icon_x, row3_cy}, icon_size, combat_col)
	rl.DrawText(combat_str, txt_x + 1, i32(row3_cy - 8.0), 18, shadow_col)
	rl.DrawText(combat_str, txt_x, i32(row3_cy - 9.0), 18, combat_col)
}

// Iterates through all conquered planets and draws their HUD status overlays
draw_conquered_planet_overlays :: proc(viewport_w, screen_h: f32) {
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	// Draw unselected badges first
	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) || p == selected_planet { continue }

		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := rl.GetWorldToScreen(planets[p].position, camera)
		if center_screen.x < -100 || center_screen.x > viewport_w + 100 || center_screen.y < -100 || center_screen.y > screen_h + 100 {
			continue
		}

		limb_screen := rl.GetWorldToScreen(planets[p].position + cam_right * planets[p].radius, camera)
		screen_r := max(rl.Vector2Distance(center_screen, limb_screen), 14.0)

		draw_conquered_planet_overlay_badge(p, center_screen, screen_r, false, viewport_w, screen_h)
	}

	// Draw selected planet badge last so it renders on top
	if selected_planet >= 0 && selected_planet < PLANET_COUNT && planet_liberated(selected_planet) {
		to_planet := planets[selected_planet].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) > 0.1 {
			center_screen := rl.GetWorldToScreen(planets[selected_planet].position, camera)
			if center_screen.x >= -100 && center_screen.x <= viewport_w + 100 && center_screen.y >= -100 && center_screen.y <= screen_h + 100 {
				limb_screen := rl.GetWorldToScreen(planets[selected_planet].position + cam_right * planets[selected_planet].radius, camera)
				screen_r := max(rl.Vector2Distance(center_screen, limb_screen), 14.0)

				draw_conquered_planet_overlay_badge(selected_planet, center_screen, screen_r, true, viewport_w, screen_h)
			}
		}
	}
}

// Ray/mouse hit test for clicking the '+' ammo build button on a conquered planet overlay badge
pick_conquered_planet_overlay_ammo_button :: proc(mouse: rl.Vector2) -> int {
	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	// Check selected planet first as its badge renders on top
	if selected_planet >= 0 && selected_planet < PLANET_COUNT && planet_liberated(selected_planet) {
		p := selected_planet
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) > 0.1 {
			center_screen := rl.GetWorldToScreen(planets[p].position, camera)
			limb_screen := rl.GetWorldToScreen(planets[p].position + cam_right * planets[p].radius, camera)
			screen_r := max(rl.Vector2Distance(center_screen, limb_screen), 14.0)
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

		center_screen := rl.GetWorldToScreen(planets[p].position, camera)
		limb_screen := rl.GetWorldToScreen(planets[p].position + cam_right * planets[p].radius, camera)
		screen_r := max(rl.Vector2Distance(center_screen, limb_screen), 14.0)

		rect := conquered_planet_overlay_rect(p, center_screen, screen_r, false, viewport_w, screen_h)
		btn_rect := conquered_planet_overlay_ammo_btn_rect(rect)
		if rl.CheckCollisionPointRec(mouse, btn_rect) {
			return p
		}
	}
	return -1
}

// Ray/mouse hit test for clicking on a conquered planet overlay badge
pick_conquered_planet_overlay :: proc(mouse: rl.Vector2) -> int {
	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) { continue }
		to_planet := planets[p].position - camera.position
		if rl.Vector3DotProduct(to_planet, cam_forward) <= 0.1 { continue }

		center_screen := rl.GetWorldToScreen(planets[p].position, camera)
		limb_screen := rl.GetWorldToScreen(planets[p].position + cam_right * planets[p].radius, camera)
		screen_r := max(rl.Vector2Distance(center_screen, limb_screen), 14.0)

		rect := conquered_planet_overlay_rect(p, center_screen, screen_r, p == selected_planet, viewport_w, screen_h)
		if rl.CheckCollisionPointRec(mouse, rect) {
			return p
		}
	}
	return -1
}

// Draws an aerospace tactical console container for the planet inspector
// (matching the bottom-center container in the reference image).
// Features 45° chamfers, dual glowing neon rails, precision ruler tick notches,
// and ambient cyan edge glow.
draw_tactical_container :: proc(rect: rl.Rectangle) {
	x, y, w, h := rect.x, rect.y, rect.width, rect.height
	ch: f32 = 6.0
	wing: f32 = 20.0

	// Soft drop shadow and ambient neon cyan bloom spilling into the viewport to the left
	rl.DrawRectangleGradientH(i32(x - 28), i32(y), 28, i32(h), rl.Color{0, 0, 0, 0}, rl.Color{0, 0, 0, 160})
	glow_col := rl.Fade(SCIFI_CYAN, 0.08)
	rl.DrawRectangleGradientV(i32(x), i32(y), i32(w), i32(h), glow_col, rl.Color{0, 0, 0, 0})

	// 8-vertex winged polygon matching the main HUD dock
	v0 := rl.Vector2{x + ch, y}
	v1 := rl.Vector2{x + w - ch, y}
	v2 := rl.Vector2{x + w, y + ch}
	v3 := rl.Vector2{x + w, y + h - ch}
	v4 := rl.Vector2{x + w - ch, y + h}
	v5 := rl.Vector2{x + wing, y + h}
	v6 := rl.Vector2{x, y + h - wing}
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
	rl.DrawPixelV(v0, border)
	rl.DrawPixelV(v1, border)
	rl.DrawPixelV(v2, border)
	rl.DrawPixelV(v3, border)
	rl.DrawPixelV(v4, border)
	rl.DrawPixelV(v5, border)
	rl.DrawPixelV(v6, border)
	rl.DrawPixelV(v7, border)

	// Secondary inner rail (inset by 3px)
	inner := SCIFI_STEEL
	iv0 := rl.Vector2{x + ch + 2, y + 3}
	iv1 := rl.Vector2{x + w - ch - 2, y + 3}
	iv2 := rl.Vector2{x + w - 3, y + ch + 2}
	iv3 := rl.Vector2{x + w - 3, y + h - ch - 2}
	iv4 := rl.Vector2{x + w - ch - 2, y + h - 3}
	iv5 := rl.Vector2{x + wing, y + h - 3}
	iv6 := rl.Vector2{x + 3, y + h - wing}
	iv7 := rl.Vector2{x + 3, y + ch + 2}

	rl.DrawLineV(iv0, iv1, inner)
	rl.DrawLineV(iv1, iv2, inner)
	rl.DrawLineV(iv2, iv3, inner)
	rl.DrawLineV(iv3, iv4, inner)
	rl.DrawLineV(iv4, iv5, inner)
	rl.DrawLineV(iv5, iv6, inner)
	rl.DrawLineV(iv6, iv7, inner)
	rl.DrawLineV(iv7, iv0, inner)
	rl.DrawPixelV(iv0, inner)
	rl.DrawPixelV(iv1, inner)
	rl.DrawPixelV(iv2, inner)
	rl.DrawPixelV(iv3, inner)
	rl.DrawPixelV(iv4, inner)
	rl.DrawPixelV(iv5, inner)
	rl.DrawPixelV(iv6, inner)
	rl.DrawPixelV(iv7, inner)
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
draw_queue_slot :: proc(rect: rl.Rectangle, queued: bool, kind: Unit_Type, progress: f32 = -1) {
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
	if queued && progress >= 0 {
		// Fill the unit slot green to show build progress for the unit
		// currently being built, leaving the symbol legible on top.
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

// Segmented radio buttons for the Earth autobuilder (Off | M | C).
draw_autobuild_radio_buttons :: proc(panel_x: f32) {
	off_rect, miner_rect, combat_rect := autobuild_radio_rects(panel_x)
	total_rect := rl.Rectangle{off_rect.x, off_rect.y, (combat_rect.x + combat_rect.width) - off_rect.x, off_rect.height}
	mouse := rl.GetMousePosition()

	// Clear dividing rail behind the radio group and the label
	lbl: cstring = "AUTO:"
	lbl_w := f32(rl.MeasureText(lbl, 11))
	lbl_x := off_rect.x - lbl_w - 6
	rl.DrawRectangleRec({lbl_x - 4, total_rect.y - 1, lbl_w + 8, total_rect.height + 2}, SCIFI_PANEL_SOLID)
	rl.DrawText(lbl, i32(lbl_x), i32(total_rect.y + 4), 11, SCIFI_MUTED)

	// Base panel for segmented radio button group
	draw_chamfered_panel(total_rect, 3, SCIFI_PANEL_SOLID, SCIFI_DIM)

	// 1. Off option
	{
		selected := auto_build_mode == .OFF
		hovered := rl.CheckCollisionPointRec(mouse, off_rect)
		fill := SCIFI_PANEL_SOLID
		border := rl.Color{0, 0, 0, 0}
		text_col := SCIFI_MUTED

		if selected {
			fill = rl.Color{0, 60, 75, 255}
			border = SCIFI_CYAN
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

	// 2. Miners option (M)
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

	// 3. Combat option (C)
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

	// Segment vertical dividers (Off | M | C)
	rl.DrawLineV({off_rect.x + off_rect.width, total_rect.y + 2}, {off_rect.x + off_rect.width, total_rect.y + total_rect.height - 2}, SCIFI_DIM)
	rl.DrawLineV({miner_rect.x + miner_rect.width, total_rect.y + 2}, {miner_rect.x + miner_rect.width, total_rect.y + total_rect.height - 2}, SCIFI_DIM)

	// Outer frame
	rl.DrawRectangleLinesEx(total_rect, 1, SCIFI_DIM)
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

