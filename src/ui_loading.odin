package main

import "core:math"
import rl "vendor:raylib"

Loading_Step :: struct {
	label: cstring,
	run:   proc(),
}

LOADING_STEPS := [?]Loading_Step{
	{"CHARTING PLANETS", init_planet_visuals},
	{"ASSEMBLING DRONE FLEET", init_drone_visuals},
	{"ARMING ORBITAL BATTERIES", init_orbital_defense_visuals},
	{"LOCATING ENEMY CITADEL", init_hq_visuals},
}

Loading_Star :: struct {
	angle: f32,
	phase: f32,
	speed: f32,
	alpha: f32,
}

loading_step := 0
loading_frames := 0
loading_start_time: f64
loading_anim_time: f32
loading_progress: f32
loading_fade_time: f32
loading_stars: [LOADING_STAR_COUNT]Loading_Star

init_loading_screen :: proc() {
	loading_start_time = rl.GetTime()
	seed := u32(0x2545F491)
	next :: proc(seed: ^u32) -> f32 {
		seed^ = seed^ * 1664525 + 1013904223
		return f32((seed^ >> 8) & 0xFFFF) / f32(0xFFFF)
	}
	for &s in loading_stars {
		s.angle = next(&seed) * 2 * math.PI
		s.phase = next(&seed)
		s.speed = 0.018 + next(&seed) * 0.03
		s.alpha = 0.35 + next(&seed) * 0.65
	}
}

loading_steps_done :: proc() -> bool {
	return loading_step >= len(LOADING_STEPS)
}

loading_screen_active :: proc() -> bool {
	return !loading_steps_done() || rl.GetTime() - loading_start_time < LOADING_MIN_TIME || loading_progress < 1
}

loading_fade_out :: proc(duration: f32) -> f32 {
	if loading_screen_active() { return 1 }
	t := clamp((loading_fade_time - LOADING_FADE_HOLD) / duration, 0, 1)
	return 1 - t * t * (3 - 2 * t)
}

loading_overlay_alpha :: proc() -> f32 {
	return loading_fade_out(LOADING_FADE_TIME)
}

update_loading :: proc(dt: f32) {
	if loading_overlay_alpha() <= 0 { return }
	step := min(dt, LOADING_MAX_DT)
	loading_anim_time += step
	if !loading_steps_done() && loading_frames >= LOADING_WARMUP_FRAMES {
		LOADING_STEPS[loading_step].run()
		loading_step += 1
	}
	loading_frames += 1
	target := f32(loading_step) / f32(len(LOADING_STEPS))
	loading_progress += (target - loading_progress) * min(step * 9, 1)
	if target - loading_progress < 0.002 { loading_progress = target }
	if !loading_screen_active() { loading_fade_time += step }
}

draw_loading_screen :: proc() {
	backdrop := loading_overlay_alpha()
	if backdrop <= 0 { return }
	alpha := loading_fade_out(LOADING_FADE_TIME * 0.45)
	sw := f32(ui_screen_w())
	sh := f32(ui_screen_h())
	t := loading_anim_time
	center := rl.Vector2{sw / 2, sh / 2}
	rl.DrawRectangleRec({0, 0, sw, sh}, rl.Fade(rl.BLACK, backdrop))

	reach := math.sqrt(center.x * center.x + center.y * center.y)
	for s in loading_stars {
		z := math.mod(s.phase + t * s.speed, 1)
		r := reach * (0.04 + 1.05 * z * z)
		pos := center + rl.Vector2{math.cos(s.angle), math.sin(s.angle)} * r
		birth := clamp((z - 0.2) / 0.35, 0, 1)
		a := s.alpha * birth * birth * backdrop
		rl.DrawCircleV(pos, 0.5 + 1.4 * z, rl.Fade(SCIFI_MINT, a))
	}

	logo_in := min(t / LOADING_LOGO_FADE_IN, 1)
	logo_in = logo_in * logo_in * (3 - 2 * logo_in)
	la := logo_in * alpha
	breathe := 0.5 + 0.5 * math.sin(t * 1.4)
	rl.DrawCircleGradient(center, 380 + 30 * breathe, rl.Fade(SCIFI_GREEN, (0.05 + 0.03 * breathe) * la), rl.Fade(SCIFI_GREEN, 0))

	title: cstring = "STARFALL COMMAND"
	size: f32 = LOADING_LOGO_SIZE
	spacing := size * 0.16
	font := display_font(size)
	tw := rl.MeasureTextEx(font, title, size, spacing).x
	tp := rl.Vector2{math.round(center.x - tw / 2), math.round(center.y - size * 0.75 - (1 - logo_in) * 10)}
	ring :: [8]rl.Vector2{{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}
	glow := 0.75 + 0.25 * breathe
	for o in ring {
		rl.DrawTextEx(font, title, tp + o * 5, size, spacing, rl.Fade(SCIFI_GREEN, 0.07 * glow * la))
		rl.DrawTextEx(font, title, tp + o * 2.5, size, spacing, rl.Fade(SCIFI_GREEN, 0.16 * glow * la))
	}
	rl.DrawTextEx(font, title, tp, size, spacing, rl.Fade(SCIFI_MINT, la))

	line_y := tp.y + size + 22
	half := tw / 2 * logo_in
	glow_line({center.x - half, line_y}, {center.x + half, line_y}, 1.5, rl.Fade(SCIFI_FILL, 0.55 * la))
	sweep := center.x - tw / 2 + math.mod(t * 0.35, 1) * tw
	if abs(sweep - center.x) < half {
		rl.DrawCircleGradient({sweep, line_y}, 26, rl.Fade(SCIFI_GREEN, 0.5 * la), rl.Fade(SCIFI_GREEN, 0))
	}

	sub: cstring = "STRATEGIC SPACE DEFENSE"
	sub_size: f32 = 15
	sub_spacing := sub_size * 0.5
	sub_font := display_font(sub_size)
	sub_w := rl.MeasureTextEx(sub_font, sub, sub_size, sub_spacing).x
	rl.DrawTextEx(sub_font, sub, {math.round(center.x - sub_w / 2), math.round(line_y + 20)}, sub_size, sub_spacing, rl.Fade(SCIFI_LABEL, 0.85 * la))

	bar := rl.Rectangle{math.round(center.x - LOADING_BAR_W / 2), math.round(sh - 140), LOADING_BAR_W, 2}
	rl.DrawRectangleRec(bar, rl.Fade(SCIFI_DIM, alpha))
	fill := bar
	fill.width = math.round(bar.width * loading_progress)
	rl.DrawRectangleRec(fill, rl.Fade(SCIFI_GREEN, alpha))
	rl.DrawCircleGradient({fill.x + fill.width, fill.y + 1}, 14, rl.Fade(SCIFI_GREEN, 0.45 * alpha), rl.Fade(SCIFI_GREEN, 0))

	label: cstring = loading_steps_done() ? "SYSTEMS ONLINE" : LOADING_STEPS[loading_step].label
	label_size: f32 = 11
	label_y := bar.y - label_size - 10
	draw_display_text(label, {bar.x, label_y}, label_size, rl.Fade(SCIFI_LABEL, 0.8 * alpha))
	pct := rl.TextFormat("%d%%", i32(math.round(loading_progress * 100)))
	pw := measure_display_text(pct, label_size)
	draw_display_text(pct, {bar.x + bar.width - pw, label_y}, label_size, rl.Fade(SCIFI_MINT, 0.8 * alpha))
}
