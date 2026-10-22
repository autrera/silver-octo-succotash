package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

DISPLAY_FONT_MAX_PX :: 160

display_font_data := #load("../assets/fonts/Michroma-Regular.ttf")
display_fonts: [DISPLAY_FONT_MAX_PX + 1]rl.Font
display_font_loaded: [DISPLAY_FONT_MAX_PX + 1]bool

display_font :: proc(size: f32) -> rl.Font {
	px := clamp(int(math.round(size * window_dpi_scale * ui_scale)), 6, DISPLAY_FONT_MAX_PX)
	if !display_font_loaded[px] {
		font := rl.LoadFontFromMemory(".ttf", raw_data(display_font_data), c.int(len(display_font_data)), c.int(px), nil, 0)
		rl.SetTextureFilter(font.texture, .BILINEAR)
		display_fonts[px] = font
		display_font_loaded[px] = true
	}
	return display_fonts[px]
}

unload_display_fonts :: proc() {
	for px in 0..=DISPLAY_FONT_MAX_PX {
		if display_font_loaded[px] {
			rl.UnloadFont(display_fonts[px])
			display_font_loaded[px] = false
		}
	}
}

display_spacing :: proc(size: f32) -> f32 {
	return size * 0.06
}

measure_display_text :: proc(text: cstring, size: f32) -> f32 {
	return rl.MeasureTextEx(display_font(size), text, size, display_spacing(size)).x
}

draw_display_text :: proc(text: cstring, pos: rl.Vector2, size: f32, color: rl.Color) {
	p := rl.Vector2{math.round(pos.x), math.round(pos.y)}
	rl.DrawTextEx(display_font(size), text, p, size, display_spacing(size), color)
}

draw_display_text_shadowed :: proc(text: cstring, pos: rl.Vector2, size: f32, color: rl.Color, shadow: rl.Color) {
	for o in ([4]rl.Vector2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
		draw_display_text(text, pos + o, size, shadow)
	}
	draw_display_text(text, pos + {1, 2}, size, shadow)
	draw_display_text(text, pos, size, color)
}

draw_display_text_glow :: proc(text: cstring, pos: rl.Vector2, size: f32, fill: rl.Color, edge: rl.Color, glow: rl.Color) {
	ring :: [8]rl.Vector2{{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}
	for o in ring {
		draw_display_text(text, pos + o * 4, size, rl.Fade(glow, f32(glow.a) / 255 * 0.12))
		draw_display_text(text, pos + o * 2.5, size, rl.Fade(glow, f32(glow.a) / 255 * 0.22))
	}
	for o in ring {
		draw_display_text(text, pos + o * 1.5, size, edge)
	}
	draw_display_text(text, pos, size, fill)
}
