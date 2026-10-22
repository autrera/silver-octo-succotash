package main

import "core:math"
import rl "vendor:raylib"

MENU_W        :: 520
MENU_PAD_X    :: 28
MENU_TITLE_H  :: 76
MENU_ITEM_H   :: 46
MENU_ITEM_GAP :: 12
MENU_FOOTER_H :: 56

Menu_Hint :: struct {
	key:   cstring,
	label: cstring,
}

menu_box :: proc(item_count: int, extra_h: f32 = 0, width: f32 = MENU_W) -> rl.Rectangle {
	sw := f32(ui_screen_w())
	sh := f32(ui_screen_h())
	h := f32(MENU_TITLE_H) + 18 + extra_h + f32(item_count) * (MENU_ITEM_H + MENU_ITEM_GAP) - MENU_ITEM_GAP + 26
	y := (sh - MENU_FOOTER_H - h) / 2
	return rl.Rectangle{math.round((sw - width) / 2), math.round(y), width, h}
}

menu_item_rect :: proc(box: rl.Rectangle, index: int, extra_h: f32 = 0) -> rl.Rectangle {
	y := box.y + MENU_TITLE_H + 18 + extra_h + f32(index) * (MENU_ITEM_H + MENU_ITEM_GAP)
	return rl.Rectangle{box.x + MENU_PAD_X, y, box.width - 2 * MENU_PAD_X, MENU_ITEM_H}
}

menu_hover_index :: proc(rects: []rl.Rectangle) -> int {
	delta := ui_mouse_delta()
	if delta.x == 0 && delta.y == 0 && !rl.IsMouseButtonPressed(.LEFT) { return -1 }
	mouse := ui_mouse()
	for r, i in rects {
		if r.width > 0 && rl.CheckCollisionPointRec(mouse, r) { return i }
	}
	return -1
}

glow_line :: proc(a, b: rl.Vector2, thick: f32, color: rl.Color) {
	alpha := f32(color.a) / 255
	rl.DrawLineEx(a, b, thick + 6, rl.Fade(color, alpha * 0.10))
	rl.DrawLineEx(a, b, thick + 2.5, rl.Fade(color, alpha * 0.22))
	rl.DrawLineEx(a, b, thick, color)
}

scale_color :: proc(col: rl.Color, k: f32) -> rl.Color {
	return rl.Color{u8(f32(col.r) * k), u8(f32(col.g) * k), u8(f32(col.b) * k), col.a}
}

draw_menu_backdrop :: proc(hints: []Menu_Hint, accent: rl.Color = SCIFI_GREEN) {
	sw := f32(ui_screen_w())
	sh := f32(ui_screen_h())
	rl.DrawRectangleRec({0, 0, sw, sh}, rl.Color{0, 6, 4, 150})
	bar_y := sh - MENU_FOOTER_H
	rl.DrawRectangleRec({0, bar_y, sw, MENU_FOOTER_H}, rl.Color{0, 4, 2, 245})
	fill := accent == SCIFI_GREEN ? SCIFI_FILL : scale_color(accent, 0.78)
	glow_line({0, bar_y}, {sw, bar_y}, 2, fill)

	label_size: f32 = 15
	key_size: f32 = 11
	cy := bar_y + MENU_FOOTER_H / 2
	x := sw - 32
	for i := len(hints) - 1; i >= 0; i -= 1 {
		h := hints[i]
		lw := measure_display_text(h.label, label_size)
		x -= lw
		draw_display_text(h.label, {x, cy - label_size * 0.5}, label_size, SCIFI_MINT)
		kw := measure_display_text(h.key, key_size)
		cap_w := max(kw + 16, 26)
		x -= cap_w + 10
		cap := rl.Rectangle{x, cy - 13, cap_w, 26}
		rl.DrawRectangleRounded(cap, 1, 12, fill)
		rl.DrawRectangleRoundedLinesEx(cap, 1, 12, 1, accent)
		draw_display_text(h.key, {cap.x + (cap_w - kw) / 2, cy - key_size * 0.5}, key_size, SCIFI_INK)
		x -= 34
	}
}

menu_round :: proc(rect: rl.Rectangle, radius: f32) -> f32 {
	return min(2 * radius / min(rect.width, rect.height), 1)
}

draw_menu_frame :: proc(box: rl.Rectangle, title: cstring, subtitle: cstring = "", accent: rl.Color = SCIFI_GREEN, subtitle_color: rl.Color = SCIFI_LABEL) {
	round := menu_round(box, 18)
	rl.DrawRectangleRounded(box, round, 16, rl.Color{0, 7, 5, 150})
	rl.DrawRectangleRoundedLinesEx(box, round, 16, 1.5, rl.Fade(accent, 0.55))

	title_size: f32 = 28
	title_y := box.y + (MENU_TITLE_H - 8 - title_size) / 2 + 1
	title_fill := accent == SCIFI_GREEN ? SCIFI_MINT : accent
	draw_display_text(title, {box.x + MENU_PAD_X, title_y}, title_size, title_fill)
	title_w := measure_display_text(title, title_size)
	if len(subtitle) > 0 {
		sub_size: f32 = 10
		sw := measure_display_text(subtitle, sub_size)
		if title_w + sw + 32 < box.width - 2 * MENU_PAD_X {
			draw_display_text(subtitle, {box.x + box.width - MENU_PAD_X - sw, title_y + title_size - sub_size - 4}, sub_size, subtitle_color)
		}
	}

	sep_y := box.y + MENU_TITLE_H - 8
	rl.DrawLineEx({box.x + MENU_PAD_X, sep_y}, {box.x + box.width - MENU_PAD_X, sep_y}, 1, rl.Fade(accent, 0.45))
}

draw_menu_item :: proc(rect: rl.Rectangle, label: cstring, key: cstring, focused: bool, enabled: bool = true, accent: rl.Color = SCIFI_GREEN) {
	round := menu_round(rect, 12)
	fill_col := rl.Color{0, 10, 7, 110}
	border := rl.Fade(accent, 0.6)
	text_col := accent
	if !enabled {
		border = rl.Fade(accent, 0.25)
		text_col = rl.Fade(accent, 0.38)
	} else if focused {
		fill_col = accent == SCIFI_GREEN ? SCIFI_FILL : scale_color(accent, 0.78)
		fill_col.a = 235
		border = rl.Fade(accent, 0.9)
		text_col = SCIFI_INK
	}

	rl.DrawRectangleRounded(rect, round, 12, fill_col)
	rl.DrawRectangleRoundedLinesEx(rect, round, 12, 1.5, border)

	label_size: f32 = 17
	cy := rect.y + rect.height / 2
	draw_display_text(label, {rect.x + 22, cy - label_size * 0.5}, label_size, text_col)

	ax := rect.x + rect.width - 26
	rl.DrawTriangle({ax, cy - 6}, {ax, cy + 6}, {ax + 8, cy}, text_col)

	if len(key) > 0 {
		key_size: f32 = 11
		kw := measure_display_text(key, key_size)
		draw_display_text(key, {ax - 22 - kw, cy - key_size * 0.5}, key_size, rl.Fade(text_col, 0.65))
	}
}
