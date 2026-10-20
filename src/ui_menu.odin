package main

import "core:math"
import rl "vendor:raylib"

MENU_W        :: 520
MENU_PAD_X    :: 28
MENU_TITLE_H  :: 76
MENU_ITEM_H   :: 46
MENU_ITEM_GAP :: 12
MENU_FRAME    :: 12
MENU_FOOTER_H :: 56
MENU_NOTCH    :: 6

Menu_Hint :: struct {
	key:   cstring,
	label: cstring,
}

menu_box :: proc(item_count: int, extra_h: f32 = 0, width: f32 = MENU_W) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	h := f32(MENU_TITLE_H) + 18 + extra_h + f32(item_count) * (MENU_ITEM_H + MENU_ITEM_GAP) - MENU_ITEM_GAP + 26
	y := (sh - MENU_FOOTER_H - h) / 2
	return rl.Rectangle{math.round((sw - width) / 2), math.round(y), width, h}
}

menu_item_rect :: proc(box: rl.Rectangle, index: int, extra_h: f32 = 0) -> rl.Rectangle {
	y := box.y + MENU_TITLE_H + 18 + extra_h + f32(index) * (MENU_ITEM_H + MENU_ITEM_GAP)
	return rl.Rectangle{box.x + MENU_PAD_X, y, box.width - 2 * MENU_PAD_X, MENU_ITEM_H}
}

menu_hover_index :: proc(rects: []rl.Rectangle) -> int {
	delta := rl.GetMouseDelta()
	if delta.x == 0 && delta.y == 0 && !rl.IsMouseButtonPressed(.LEFT) { return -1 }
	mouse := rl.GetMousePosition()
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
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangleRec({0, 0, sw, sh}, rl.Color{0, 6, 4, 196})
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

draw_menu_frame :: proc(box: rl.Rectangle, title: cstring, subtitle: cstring = "", accent: rl.Color = SCIFI_GREEN, subtitle_color: rl.Color = SCIFI_LABEL) {
	rl.DrawRectangleRec(box, rl.Color{0, 5, 3, 232})
	rl.DrawRectangleGradientV(i32(box.x), i32(box.y), i32(box.width), MENU_TITLE_H, rl.Fade(accent, 0.07), rl.Color{0, 0, 0, 0})

	o := rl.Rectangle{box.x - MENU_FRAME, box.y - MENU_FRAME, box.width + 2 * MENU_FRAME, box.height + 2 * MENU_FRAME}
	l, t, r, b := o.x, o.y, o.x + o.width, o.y + o.height
	seg := o.width * 0.26
	arm: f32 = 28
	glow_line({l, t + arm}, {l, t}, 2, accent)
	glow_line({l, t}, {l + seg, t}, 2, accent)
	glow_line({r - seg, t}, {r, t}, 2, accent)
	glow_line({r, t}, {r, t + arm}, 2, accent)
	glow_line({l, b - arm}, {l, b}, 2, accent)
	glow_line({l, b}, {l + seg, b}, 2, accent)
	glow_line({r - seg, b}, {r, b}, 2, accent)
	glow_line({r, b}, {r, b - arm}, 2, accent)
	side := rl.Fade(accent, 0.5)
	rl.DrawLineEx({l, t + arm + 6}, {l, b - arm - 6}, 1, side)
	rl.DrawLineEx({r, t + arm + 6}, {r, b - arm - 6}, 1, side)

	mid := t + o.height * 0.5
	tab := min(f32(40), o.height * 0.2)
	glow_line({l, mid - tab - 6}, {l - 5, mid - tab}, 2, accent)
	glow_line({l - 5, mid - tab}, {l - 5, mid + tab}, 3, accent)
	glow_line({l - 5, mid + tab}, {l, mid + tab + 6}, 2, accent)
	glow_line({r, mid - tab - 6}, {r + 5, mid - tab}, 2, accent)
	glow_line({r + 5, mid - tab}, {r + 5, mid + tab}, 3, accent)
	glow_line({r + 5, mid + tab}, {r, mid + tab + 6}, 2, accent)

	draw_corner_brackets({box.x + 4, box.y + 4, box.width - 8, box.height - 8}, 0, 10, accent)

	title_size: f32 = 30
	title_y := box.y + (MENU_TITLE_H - 8 - title_size) / 2 + 1
	title_fill := accent == SCIFI_GREEN ? SCIFI_MINT : accent
	draw_display_text_glow(title, {box.x + MENU_PAD_X, title_y}, title_size, title_fill, scale_color(accent, 0.3), rl.Fade(accent, 0.4))
	title_w := measure_display_text(title, title_size)
	if len(subtitle) > 0 {
		sub_size: f32 = 10
		sw := measure_display_text(subtitle, sub_size)
		if title_w + sw + 32 < box.width - 2 * MENU_PAD_X {
			draw_display_text(subtitle, {box.x + box.width - MENU_PAD_X - sw, title_y + title_size - sub_size - 4}, sub_size, subtitle_color)
		}
	}

	sep_y := box.y + MENU_TITLE_H - 8
	glow_line({l, sep_y}, {r, sep_y}, 2, accent)
	rl.DrawLineEx({l + 6, sep_y - 6}, {l + 6, sep_y + 6}, 2, accent)
	rl.DrawLineEx({r - 6, sep_y - 6}, {r - 6, sep_y + 6}, 2, accent)
}

draw_menu_item :: proc(rect: rl.Rectangle, label: cstring, key: cstring, focused: bool, enabled: bool = true, accent: rl.Color = SCIFI_GREEN) {
	l, t := rect.x, rect.y
	r, b := rect.x + rect.width, rect.y + rect.height
	ch: f32 = 3
	n := f32(MENU_NOTCH)
	nx1 := r - 100
	nx2 := r - 24

	fill_col := rl.Color{0, 8, 4, 150}
	border := accent
	text_col := accent
	arrow_col := accent
	if !enabled {
		border = rl.Fade(accent, 0.35)
		text_col = rl.Fade(accent, 0.38)
		arrow_col = rl.Fade(accent, 0.3)
	} else if focused {
		fill_col = accent == SCIFI_GREEN ? SCIFI_FILL : scale_color(accent, 0.78)
		border = accent == SCIFI_GREEN ? rl.Color{120, 255, 196, 255} : accent
		text_col = SCIFI_INK
		arrow_col = SCIFI_INK
	}

	if focused && enabled {
		rl.DrawRectangleRec({l - 4, t - 4, rect.width + 8, rect.height + 8}, rl.Fade(accent, 0.07))
	}
	rl.DrawRectangleRec({l + 1, t + 1, rect.width - 2, rect.height - n - 1}, fill_col)
	rl.DrawRectangleRec({l + 1, b - n, nx1 - l - 1, n - 1}, fill_col)
	rl.DrawRectangleRec({nx2, b - n, r - nx2 - 1, n - 1}, fill_col)
	rl.DrawTriangle({nx1, b - n}, {nx1, b - 1}, {nx1 + n, b - n}, fill_col)
	rl.DrawTriangle({nx2 - n, b - n}, {nx2, b - 1}, {nx2, b - n}, fill_col)

	if focused && enabled {
		for sy := t + 2; sy < b - 2; sy += 3 {
			rl.DrawLineEx({l + 2, sy}, {r - 2, sy}, 1, rl.Color{0, 40, 20, 34})
		}
	}

	pts := [?]rl.Vector2{
		{l + ch, t}, {r - ch, t}, {r, t + ch}, {r, b - ch}, {r - ch, b},
		{nx2, b}, {nx2 - n, b - n}, {nx1 + n, b - n}, {nx1, b},
		{l + ch, b}, {l, b - ch}, {l, t + ch}, {l + ch, t},
	}
	for i in 0..<len(pts) - 1 {
		rl.DrawLineEx(pts[i], pts[i + 1], 2, border)
	}

	label_size: f32 = 17
	cy := t + (rect.height - n) / 2 + 1
	draw_display_text(label, {l + 20, cy - label_size * 0.5}, label_size, text_col)

	ax := r - 28
	rl.DrawTriangle({ax, cy - 8}, {ax, cy + 8}, {ax + 10, cy}, arrow_col)

	if len(key) > 0 {
		key_size: f32 = 11
		kw := measure_display_text(key, key_size)
		cap := rl.Rectangle{ax - 18 - kw - 14, cy - 11, kw + 14, 22}
		key_col := rl.Fade(text_col, 0.7)
		rl.DrawRectangleRoundedLinesEx(cap, 0.3, 6, 1, key_col)
		draw_display_text(key, {cap.x + 7, cy - key_size * 0.5}, key_size, key_col)
	}
}
