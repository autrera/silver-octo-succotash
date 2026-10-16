package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

SQUAD_COUNT :: 9

save_squad :: proc(group: int) {
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group { units[i].squad = 0 }
		if selected_units[i] && !units[i].enemy { units[i].squad = group }
	}
}

recall_squad :: proc(group: int) -> int {
	clear_selection()
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group && !units[i].enemy {
			selected_units[i] = true
			count += 1
		}
	}
	return count
}

squad_count :: proc(group: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].squad == group && !units[i].enemy { count += 1 }
	}
	return count
}

draw_squad_hud :: proc() {
	counts: [SQUAD_COUNT + 1]int
	for i := 0; i < unit_count; i += 1 {
		sq := units[i].squad
		if sq >= 1 && sq <= SQUAD_COUNT && !units[i].enemy {
			counts[sq] += 1
		}
	}
	x := f32(HUD_PAD)
	for g in 1..=SQUAD_COUNT {
		count := counts[g]
		if count == 0 { continue }
		label := rl.TextFormat("[%d:%d]", g, count)
		w := f32(rl.MeasureText(label, 13))
		badge := rl.Rectangle{x, BADGE_Y, w + 2 * BADGE_PAD, BADGE_H}
		draw_chamfered_panel(badge, 4, SCIFI_PANEL_SOLID, SCIFI_STEEL)
		draw_corner_brackets(badge, 1, 3, SCIFI_CYAN)
		rl.DrawText(label, c.int(x + BADGE_PAD), BADGE_Y + 4, 13, SCIFI_CYAN)
		x += badge.width + BADGE_GAP
	}
}

pause_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.P) || rl.IsKeyPressed(.F10)
}

PAUSE_MENU_OPTIONS :: 5
pause_menu_selection := 0

toggle_pause :: proc() {
	game_paused = !game_paused
	if game_paused {
		pause_menu_selection = 0
		save_feedback_timer = 0
	}
}

advance_pause_selection :: proc(dir: int) {
	pause_menu_selection = (pause_menu_selection + dir + PAUSE_MENU_OPTIONS) % PAUSE_MENU_OPTIONS
}

activate_pause_selection :: proc() {
	switch pause_menu_selection {
	case 0:
		game_paused = false
	case 1:
		if save_game() {
			save_feedback_timer = 2.0
		}
	case 2:
		if load_game() {
			game_paused = false
		}
	case 3:
		restart_game()
		game_paused = false
	case 4:
		quit_requested = true
	}
}

draw_diamond :: proc(cx, cy, r: f32, color: rl.Color) {
	rl.DrawLineV({cx, cy - r}, {cx + r, cy}, color)
	rl.DrawLineV({cx + r, cy}, {cx, cy + r}, color)
	rl.DrawLineV({cx, cy + r}, {cx - r, cy}, color)
	rl.DrawLineV({cx - r, cy}, {cx, cy - r}, color)
}

step_simulation :: proc(dt: f32) {
	if hud_save_notification_timer > 0 {
		hud_save_notification_timer -= dt
	}
	update_camera(dt)
	update_input()
	update_production(dt)
	update_units(dt)
	update_enemy_waves(dt)
	update_planet_spin(dt)
	update_intel()
	laser_anim_time = math.mod(laser_anim_time + dt, 3600.0)
	is_earth_producing := false
	for b in 0..<base_counts[EARTH] {
		if production[EARTH][b].active {
			is_earth_producing = true
			break
		}
	}
	if is_earth_producing || base_build_planet == EARTH {
		earth_industry_intensity = min(earth_industry_intensity + dt * 2.8, 1.0)
	} else {
		earth_industry_intensity = max(earth_industry_intensity - dt * 1.8, 0.0)
	}
	update_combat_nebula_intensity(dt)
	if !victory && victory_achieved() { victory = true }
	if !victory && !defeated && defeat_condition() { defeated = true }
}

update_combat_nebula_intensity :: proc(dt: f32) {
	for s in 0..<SECTOR_COUNT {
		in_combat := sector_in_combat(s)
		sector_combat_state[s] = in_combat
		target: f32 = 0.0
		is_warning := planet_under_attack_warning(s)
		if is_warning {
			target = 0.5
		}
		if s == ENEMY_HOME {
			if !enemy_hq_destroyed() {
				target = in_combat ? 1.0 : 0.65
			}
		} else if in_combat {
			target = 1.0
		}
		rate: f32 = (in_combat || is_warning) ? 3.5 : 1.2
		combat_nebula_intensity[s] += (target - combat_nebula_intensity[s]) * clamp(dt * rate, 0.0, 1.0)

		is_src_warning := planet_attack_source_warning(s)
		src_target: f32 = is_src_warning ? 0.5 : 0.0
		src_rate: f32 = is_src_warning ? 3.5 : 1.2
		minor_wave_source_nebula_intensity[s] += (src_target - minor_wave_source_nebula_intensity[s]) * clamp(dt * src_rate, 0.0, 1.0)
	}
}

update_intel :: proc() {
	vis: [PLANET_COUNT]bool
	any_vis := false
	for p in 0..<PLANET_COUNT {
		if has_vision(p) {
			vis[p] = true
			any_vis = true
			last_known_intel[p] = Intel{base_hp = enemy_base_hp[p]}
			intel_recorded[p] = true
		}
	}
	if !any_vis { return }

	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT {
			p := u.affiliation
			if p >= 0 && p < PLANET_COUNT && vis[p] {
				intel := &last_known_intel[p]
				if u.enemy && u.state == .GUARDING {
					intel.fighters += 1
				}
				if intel.unit_count < INTEL_UNIT_CAP {
					intel.units[intel.unit_count] = Intel_Unit{kind = u.kind, state = u.state, enemy = u.enemy}
					intel.unit_count += 1
				}
			}
		} else if u.kind == .MINING {
			if u.enemy {
				p_aff := u.affiliation
				if p_aff >= 0 && p_aff < PLANET_COUNT && vis[p_aff] {
					last_known_intel[p_aff].miners += 1
				}
			}
			p_tgt := u.target_planet
			if p_tgt >= 0 && p_tgt < PLANET_COUNT && vis[p_tgt] {
				intel := &last_known_intel[p_tgt]
				if intel.unit_count < INTEL_UNIT_CAP {
					intel.units[intel.unit_count] = Intel_Unit{kind = u.kind, state = u.state, enemy = u.enemy}
					intel.unit_count += 1
				}
			}
		}
	}
}

pause_menu_rects :: proc() -> (box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	title_w := f32(rl.MeasureText("PAUSED", 36))
	box_w := max(title_w, f32(280)) + 60
	box_h: f32 = 352.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}
	btn_w := box.width - 2 * DIALOG_PAD
	continue_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 82, btn_w, DIALOG_BTN_H}
	save_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 134, btn_w, DIALOG_BTN_H}
	load_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 186, btn_w, DIALOG_BTN_H}
	new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 238, btn_w, DIALOG_BTN_H}
	quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 290, btn_w, DIALOG_BTN_H}
	return
}

update_pause_menu :: proc(dt: f32 = 0) {
	if save_feedback_timer > 0 {
		save_feedback_timer -= dt
	}
	if rl.IsKeyPressed(.UP) { advance_pause_selection(-1) }
	if rl.IsKeyPressed(.DOWN) { advance_pause_selection(1) }
	if rl.IsKeyPressed(.C) {
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.S) {
		if save_game() {
			save_feedback_timer = 2.0
		}
		return
	}
	if rl.IsKeyPressed(.L) {
		if load_game() {
			game_paused = false
		}
		return
	}
	if rl.IsKeyPressed(.N) {
		restart_game()
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.Q) {
		quit_requested = true
		return
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		activate_pause_selection()
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	_, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()
	mouse := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse, continue_rect) {
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, save_rect) {
		if save_game() {
			save_feedback_timer = 2.0
		}
	} else if rl.CheckCollisionPointRec(mouse, load_rect) {
		if load_game() {
			game_paused = false
		}
	} else if rl.CheckCollisionPointRec(mouse, new_game_rect) {
		restart_game()
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
		quit_requested = true
	}
}

draw_pause_menu :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 220})
	box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()

	draw_chamfered_panel(box, 12, SCIFI_PANEL, SCIFI_STEEL)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "MISSION PAUSED"
	title_w := f32(rl.MeasureText(title, 26))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 26), 26, SCIFI_CYAN)

	if save_feedback_timer > 0 {
		saved_txt: cstring = "GAME SAVED TO DISK"
		st_w := f32(rl.MeasureText(saved_txt, 12))
		rl.DrawText(saved_txt, c.int(box.x + (box.width - st_w) / 2), c.int(box.y + 58), 12, SCIFI_AMBER)
	}

	has_save := save_game_exists()
	draw_button(continue_rect, "[C] CONTINUE", SCIFI_PANEL_SOLID)
	draw_button(save_rect, "[S] SAVE GAME", SCIFI_PANEL_SOLID)
	if has_save {
		draw_button(load_rect, "[L] LOAD GAME", SCIFI_PANEL_SOLID)
	} else {
		draw_button(load_rect, "[L] LOAD GAME (NO SAVE)", rl.Color{10, 20, 28, 255}, false)
	}
	draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)

	focused_rect: rl.Rectangle
	switch pause_menu_selection {
	case 0: focused_rect = continue_rect
	case 1: focused_rect = save_rect
	case 2: focused_rect = load_rect
	case 3: focused_rect = new_game_rect
	case 4: focused_rect = quit_rect
	}
	draw_pause_focus(focused_rect)
}

draw_pause_focus :: proc(rect: rl.Rectangle) {
	if rect.width <= 0 { return }
	draw_corner_brackets(rect, 4, 8, SCIFI_CYAN)
	rl.DrawRectangleLinesEx({rect.x - 2, rect.y - 2, rect.width + 4, rect.height + 4}, 1, rl.Fade(SCIFI_CYAN, 0.45))
}

open_controls_overlay :: proc() {
	controls_overlay_open = true
	game_paused = true
}

close_controls_overlay :: proc() {
	controls_overlay_open = false
	game_paused = false
}

controls_overlay_rects :: proc() -> (box: rl.Rectangle, close_btn: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box_w: f32 = 740.0
	box_h: f32 = 490.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}
	close_btn_w: f32 = 200.0
	close_btn_h: f32 = 36.0
	close_btn = rl.Rectangle{box.x + (box.width - close_btn_w) / 2, box.y + box.height - 50, close_btn_w, close_btn_h}
	return
}

update_controls_overlay :: proc() {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.C) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) || pause_key_pressed() {
		close_controls_overlay()
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mouse := rl.GetMousePosition()
		box, close_btn := controls_overlay_rects()
		if rl.CheckCollisionPointRec(mouse, close_btn) || !rl.CheckCollisionPointRec(mouse, box) {
			close_controls_overlay()
			return
		}
	}
}

draw_control_row :: proc(x, y: f32, key, desc: cstring) {
	rl.DrawText(key, c.int(x), c.int(y), 12, SCIFI_MINT)
	rl.DrawText(desc, c.int(x + 115), c.int(y), 12, SCIFI_TEXT)
}

draw_controls_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	box, close_btn := controls_overlay_rects()

	draw_chamfered_panel(box, 14, SCIFI_PANEL, SCIFI_CYAN)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "TACTICAL CONTROLS DIRECTIVE"
	title_w := f32(rl.MeasureText(title, 22))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 22), 22, SCIFI_CYAN)

	sub: cstring = "OPERATIONAL KEYBINDS AND COMMAND PROTOCOLS"
	sub_w := f32(rl.MeasureText(sub, 12))
	rl.DrawText(sub, c.int(box.x + (box.width - sub_w) / 2), c.int(box.y + 50), 12, SCIFI_MUTED)

	rl.DrawLineV({box.x + 24, box.y + 70}, {box.x + box.width - 24, box.y + 70}, SCIFI_DIM)

	col1_x := box.x + 32
	col2_x := box.x + 376

	cy1 := box.y + 84
	rl.DrawText("CAMERA AND NAVIGATION", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "WASD / ARROWS", "Pan tactical view")
	cy1 += 18
	draw_control_row(col1_x, cy1, "Q / E / SCROLL", "Zoom altitude in and out")
	cy1 += 18
	draw_control_row(col1_x, cy1, "SPACE", "Select Earth / Center view")

	cy1 += 26
	rl.DrawText("FLEET SELECTION AND SQUADS", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "LEFT CLICK", "Select planet, citadel, or drone")
	cy1 += 18
	draw_control_row(col1_x, cy1, "DRAG BOX", "Box-select unit tiles in panel")
	cy1 += 18
	draw_control_row(col1_x, cy1, "CTRL + CLICK", "Toggle individual units")
	cy1 += 18
	draw_control_row(col1_x, cy1, "SHIFT + 1-9", "Assign selection to Squad 1-9")
	cy1 += 18
	draw_control_row(col1_x, cy1, "1-9", "Recall assigned Squad 1-9")

	cy1 += 26
	rl.DrawText("TACTICAL DIRECTIVES", c.int(col1_x), c.int(cy1), 13, SCIFI_AMBER)
	cy1 += 20
	draw_control_row(col1_x, cy1, "RIGHT CLICK", "Dispatch units to planet / HQ")
	cy1 += 18
	draw_control_row(col1_x, cy1, "R-CLICK EARTH", "Set or clear Earth rally flag")
	cy1 += 18
	draw_control_row(col1_x, cy1, "B / CLICK", "Build Refinery on outpost")
	cy1 += 18
	draw_control_row(col1_x, cy1, "O / CLICK", "Build / Upgrade Orbital Defense")

	cy2 := box.y + 84
	rl.DrawText("EARTH BASE REQUISITION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "M / CLICK", rl.TextFormat("Build Mining Drone (%d)", MINER_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "N", rl.TextFormat("Build +5 Miners (%d)", BATCH_MINER_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "C / CLICK", rl.TextFormat("Build Combat Fighter (%d)", COMBAT_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "X", rl.TextFormat("Build +5 Fighters (%d)", BATCH_COMBAT_COST))
	cy2 += 18
	draw_control_row(col2_x, cy2, "U / SPEED", "Upgrade Build Speed (5,000)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "T", "Toggle Autobuild On / Off")
	cy2 += 18
	draw_control_row(col2_x, cy2, "ESC", "Cancel last build (Refund)")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CLICK SLOT", "Cancel specific queue slot")

	cy2 += 26
	rl.DrawText("SYSTEM AND SIMULATION", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "P / F10", "Pause game / Mission menu")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F11", "Toggle fullscreen window")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F5", "Quick-save game state")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CTRL + N", "Debug: force enemy wave")

	cy2 += 26
	rl.DrawText("TACTICAL SENSORS", c.int(col2_x), c.int(cy2), 13, SCIFI_AMBER)
	cy2 += 20
	draw_control_row(col2_x, cy2, "FOG OF WAR", "Presence required to scout")
	cy2 += 18
	draw_control_row(col2_x, cy2, "GHOST VIEW", "Stale intel retained dark")

	rl.DrawLineV({box.x + 24, box.y + box.height - 64}, {box.x + box.width - 24, box.y + box.height - 64}, SCIFI_DIM)

	draw_button(close_btn, "[C] RESUME GAME", SCIFI_PANEL_SOLID, true)
}

start_menu_options_count :: proc(has_save: bool) -> int {
	return has_save ? 3 : 2
}

advance_start_menu_selection :: proc(dir: int) {
	has_save := save_game_exists()
	count := start_menu_options_count(has_save)
	start_menu_selection = (start_menu_selection + dir + count) % count
}

activate_start_menu_selection :: proc() {
	has_save := save_game_exists()
	if has_save {
		switch start_menu_selection {
		case 0:
			if load_game() {
				in_start_menu = false
				game_paused = false
			}
		case 1:
			restart_game()
			in_start_menu = false
			game_paused = false
		case 2:
			quit_requested = true
		}
	} else {
		switch start_menu_selection {
		case 0:
			restart_game()
			in_start_menu = false
			game_paused = false
		case 1:
			quit_requested = true
		}
	}
}

start_menu_rects :: proc(has_save: bool) -> (box, continue_rect, new_game_rect, quit_rect: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box_w: f32 = 380.0
	box_h: f32 = has_save ? 270.0 : 218.0
	box = rl.Rectangle{(w - box_w) / 2, (h - box_h) / 2, box_w, box_h}

	btn_w := box.width - 2 * DIALOG_PAD
	if has_save {
		continue_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 78, btn_w, DIALOG_BTN_H}
		new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 130, btn_w, DIALOG_BTN_H}
		quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 182, btn_w, DIALOG_BTN_H}
	} else {
		continue_rect = rl.Rectangle{}
		new_game_rect = rl.Rectangle{box.x + DIALOG_PAD, box.y + 78, btn_w, DIALOG_BTN_H}
		quit_rect     = rl.Rectangle{box.x + DIALOG_PAD, box.y + 130, btn_w, DIALOG_BTN_H}
	}
	return
}

update_start_menu :: proc(dt: f32) {
	update_planet_spin(dt)
	laser_anim_time = math.mod(laser_anim_time + dt, 3600.0)
	has_save := save_game_exists()
	count := start_menu_options_count(has_save)
	if start_menu_selection >= count {
		start_menu_selection = 0
	}

	if rl.IsKeyPressed(.UP) { advance_start_menu_selection(-1) }
	if rl.IsKeyPressed(.DOWN) { advance_start_menu_selection(1) }

	if has_save && rl.IsKeyPressed(.C) {
		if load_game() {
			in_start_menu = false
			game_paused = false
		}
		return
	}
	if rl.IsKeyPressed(.N) {
		restart_game()
		in_start_menu = false
		game_paused = false
		return
	}
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) {
		quit_requested = true
		return
	}

	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		activate_start_menu_selection()
		return
	}

	if !rl.IsMouseButtonPressed(.LEFT) { return }
	mouse := rl.GetMousePosition()
	_, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)
	if has_save && rl.CheckCollisionPointRec(mouse, continue_rect) {
		if load_game() {
			in_start_menu = false
			game_paused = false
		}
	} else if rl.CheckCollisionPointRec(mouse, new_game_rect) {
		restart_game()
		in_start_menu = false
		game_paused = false
	} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
		quit_requested = true
	}
}

draw_start_menu :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 220})
	has_save := save_game_exists()
	box, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)

	draw_chamfered_panel(box, 14, SCIFI_PANEL, SCIFI_STEEL)
	draw_corner_brackets(box, 3, 14, SCIFI_CYAN)

	title: cstring = "STARFALL COMMAND"
	title_w := f32(rl.MeasureText(title, 26))
	rl.DrawText(title, c.int(box.x + (box.width - title_w) / 2), c.int(box.y + 26), 26, SCIFI_CYAN)

	sub: cstring = "STRATEGIC SPACE DEFENSE"
	sub_w := f32(rl.MeasureText(sub, 10))
	rl.DrawText(sub, c.int(box.x + (box.width - sub_w) / 2), c.int(box.y + 56), 10, SCIFI_MUTED)

	focused_rect: rl.Rectangle
	if has_save {
		draw_button(continue_rect, "[C] CONTINUE", SCIFI_PANEL_SOLID)
		draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
		draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
		switch start_menu_selection {
		case 0: focused_rect = continue_rect
		case 1: focused_rect = new_game_rect
		case 2: focused_rect = quit_rect
		}
	} else {
		draw_button(new_game_rect, "[N] NEW GAME", SCIFI_PANEL_SOLID)
		draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
		switch start_menu_selection {
		case 0: focused_rect = new_game_rect
		case 1: focused_rect = quit_rect
		}
	}
	draw_pause_focus(focused_rect)

	footer: cstring = "UP/DOWN: SELECT   ENTER: CONFIRM"
	footer_w := f32(rl.MeasureText(footer, 10))
	rl.DrawText(footer, c.int(box.x + (box.width - footer_w) / 2), c.int(box.y + box.height - 22), 10, SCIFI_MUTED)
}

enemy_hq_destroyed :: proc() -> bool { return enemy_base_hp[ENEMY_HOME] <= 0 }

victory_achieved :: proc() -> bool {
	if !enemy_hq_destroyed() { return false }
	for p in 0..<PLANET_COUNT { if !planet_liberated(p) { return false } }
	return true
}

restart_game :: proc() {
	reset_world()
	initialize_game()
	camera_target = rl.Vector3{10, 0, 2}
	camera.position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y}
	camera.target = camera_target
}

victory_button_rects :: proc() -> (play, quit: rl.Rectangle) {
	cy := f32(rl.GetScreenHeight() / 2 + 66)
	play = rl.Rectangle{f32(rl.GetScreenWidth() / 2 - 144), cy, 140, 44}
	quit = rl.Rectangle{f32(rl.GetScreenWidth() / 2 + 4), cy, 140, 44}
	return
}

victory_quit_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE)
}

update_victory_overlay :: proc() {
	if rl.IsKeyPressed(.R) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) { restart_game(); return }
	if victory_quit_key_pressed() { quit_requested = true; return }
	if rl.IsMouseButtonPressed(.LEFT) {
		play_rect, quit_rect := victory_button_rects()
		mouse := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mouse, play_rect) {
			restart_game()
		} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
			quit_requested = true
		}
	}
}

draw_victory_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box := rl.Rectangle{w/2 - 280, h/2 - 130, 560, 270}
	draw_chamfered_panel(box, 16, SCIFI_PANEL, SCIFI_CYAN)
	draw_corner_brackets(box, 4, 16, SCIFI_CYAN)

	title: cstring = "SYSTEM LIBERATED"
	title_w := f32(rl.MeasureText(title, 32))
	rl.DrawText(title, c.int(w/2 - title_w/2), c.int(box.y + 36), 32, SCIFI_CYAN)

	sub: cstring = "ALL 8 PLANETS LIBERATED   ENEMY HQ DESTROYED"
	sub_w := f32(rl.MeasureText(sub, 14))
	rl.DrawText(sub, c.int(w/2 - sub_w/2), c.int(box.y + 78), 14, SCIFI_MINT)

	stats: cstring = "CAMPAIGN OBJECTIVE ACHIEVED   SOLAR SECTOR SECURED"
	stats_w := f32(rl.MeasureText(stats, 11))
	rl.DrawText(stats, c.int(w/2 - stats_w/2), c.int(box.y + 104), 11, SCIFI_MUTED)

	hint: cstring = "R / ENTER: PLAY AGAIN   Q / ESC: QUIT"
	hint_w := f32(rl.MeasureText(hint, 10))
	rl.DrawText(hint, c.int(w/2 - hint_w/2), c.int(box.y + 140), 10, SCIFI_MUTED)

	play_rect, quit_rect := victory_button_rects()
	draw_button(play_rect, "[R] PLAY AGAIN", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
}

defeat_condition :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		if !units[i].enemy { return false }
	}
	for p in 0..<PLANET_COUNT {
		if base_counts[p] != 0 { return false }
	}
	return true
}

update_game_over_overlay :: proc() {
	if rl.IsKeyPressed(.R) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) { restart_game(); return }
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) { quit_requested = true; return }
	if rl.IsMouseButtonPressed(.LEFT) {
		play_rect, quit_rect := victory_button_rects()
		mouse := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mouse, play_rect) {
			restart_game()
		} else if rl.CheckCollisionPointRec(mouse, quit_rect) {
			quit_requested = true
		}
	}
}

draw_game_over_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{4, 12, 18, 225})
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box := rl.Rectangle{w/2 - 280, h/2 - 130, 560, 270}
	draw_chamfered_panel(box, 16, SCIFI_PANEL, SCIFI_RED)
	draw_corner_brackets(box, 4, 16, SCIFI_RED)

	title: cstring = "CRITICAL DEFEAT"
	title_w := f32(rl.MeasureText(title, 32))
	rl.DrawText(title, c.int(w/2 - title_w/2), c.int(box.y + 36), 32, SCIFI_RED)

	sub: cstring = "ALL COMMAND BASES AND DRONES DESTROYED"
	sub_w := f32(rl.MeasureText(sub, 14))
	rl.DrawText(sub, c.int(w/2 - sub_w/2), c.int(box.y + 78), 14, SCIFI_TEXT)

	stats: cstring = "SECTOR DEFENSE COLLAPSED   HOSTILE FORCES PREVAIL"
	stats_w := f32(rl.MeasureText(stats, 11))
	rl.DrawText(stats, c.int(w/2 - stats_w/2), c.int(box.y + 104), 11, SCIFI_MUTED)

	hint: cstring = "R / ENTER: RESTART   Q / ESC: QUIT"
	hint_w := f32(rl.MeasureText(hint, 10))
	rl.DrawText(hint, c.int(w/2 - hint_w/2), c.int(box.y + 140), 10, SCIFI_MUTED)

	play_rect, quit_rect := victory_button_rects()
	draw_button(play_rect, "[R] RESTART", SCIFI_PANEL_SOLID)
	draw_button(quit_rect, "[Q] QUIT", SCIFI_PANEL_SOLID)
}

