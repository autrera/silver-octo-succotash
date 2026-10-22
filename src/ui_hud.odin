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
		draw_corner_brackets(badge, 1, 3, SCIFI_GREEN)
		rl.DrawText(label, c.int(x + BADGE_PAD), BADGE_Y + 4, 13, SCIFI_GREEN)
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
	active_lines := 0
	for b in 0..<base_counts[EARTH] {
		if production[EARTH][b].active { active_lines += 1 }
	}
	if base_build_planet == EARTH { active_lines += 1 }
	if active_lines > 0 {
		earth_industry_intensity = min(earth_industry_intensity + dt * 1.4, 1.0)
	} else {
		earth_industry_intensity = max(earth_industry_intensity - dt * 0.9, 0.0)
	}
	level_target := f32(active_lines) / f32(MAX_BASES + 1)
	earth_industry_level += (level_target - earth_industry_level) * min(dt * 1.5, 1.0)
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

PAUSE_MENU_HINTS := [?]Menu_Hint{{"P", "RESUME"}, {"UP/DN", "NAVIGATE"}, {"ENTER", "SELECT"}}

pause_menu_rects :: proc() -> (box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect: rl.Rectangle) {
	box = menu_box(PAUSE_MENU_OPTIONS)
	continue_rect = menu_item_rect(box, 0)
	save_rect     = menu_item_rect(box, 1)
	load_rect     = menu_item_rect(box, 2)
	new_game_rect = menu_item_rect(box, 3)
	quit_rect     = menu_item_rect(box, 4)
	return
}

update_pause_menu :: proc(dt: f32 = 0) {
	if save_feedback_timer > 0 {
		save_feedback_timer -= dt
	}
	_, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()
	rects := [?]rl.Rectangle{continue_rect, save_rect, load_rect, new_game_rect, quit_rect}
	if hovered := menu_hover_index(rects[:]); hovered >= 0 {
		pause_menu_selection = hovered
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
	mouse := rl.GetMousePosition()
	for r, i in rects {
		if rl.CheckCollisionPointRec(mouse, r) {
			pause_menu_selection = i
			activate_pause_selection()
			return
		}
	}
}

draw_pause_menu :: proc() {
	draw_menu_backdrop(PAUSE_MENU_HINTS[:])
	box, continue_rect, save_rect, load_rect, new_game_rect, quit_rect := pause_menu_rects()
	if save_feedback_timer > 0 {
		draw_menu_frame(box, "PAUSED", "GAME SAVED TO DISK", subtitle_color = SCIFI_AMBER)
	} else {
		draw_menu_frame(box, "PAUSED", "MISSION SUSPENDED")
	}
	has_save := save_game_exists()
	draw_menu_item(continue_rect, "CONTINUE", "C", pause_menu_selection == 0)
	draw_menu_item(save_rect, "SAVE GAME", "S", pause_menu_selection == 1)
	draw_menu_item(load_rect, has_save ? "LOAD GAME" : "LOAD GAME - NO SAVE", "L", pause_menu_selection == 2, has_save)
	draw_menu_item(new_game_rect, "NEW GAME", "N", pause_menu_selection == 3)
	draw_menu_item(quit_rect, "QUIT", "Q", pause_menu_selection == 4)
}

open_controls_overlay :: proc() {
	controls_overlay_open = true
	game_paused = true
}

close_controls_overlay :: proc() {
	controls_overlay_open = false
	game_paused = false
}

CONTROLS_HINTS := [?]Menu_Hint{{"ESC", "CLOSE"}, {"ENTER", "RESUME"}}

controls_overlay_rects :: proc() -> (box: rl.Rectangle, close_btn: rl.Rectangle) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	box_w: f32 = 760.0
	box_h: f32 = 540.0
	box = rl.Rectangle{math.round((w - box_w) / 2), math.round((h - MENU_FOOTER_H - box_h) / 2), box_w, box_h}
	close_btn_w: f32 = 300.0
	close_btn = rl.Rectangle{box.x + (box.width - close_btn_w) / 2, box.y + box.height - MENU_ITEM_H - 22, close_btn_w, MENU_ITEM_H}
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
	draw_menu_backdrop(CONTROLS_HINTS[:])
	box, close_btn := controls_overlay_rects()
	draw_menu_frame(box, "CONTROLS", "OPERATIONAL KEYBINDS AND COMMAND PROTOCOLS")

	col1_x := box.x + 32
	col2_x := box.x + 376

	cy1 := box.y + 92
	rl.DrawText("CAMERA AND NAVIGATION", c.int(col1_x), c.int(cy1), 13, SCIFI_GREEN)
	cy1 += 20
	draw_control_row(col1_x, cy1, "WASD / ARROWS", "Pan tactical view")
	cy1 += 18
	draw_control_row(col1_x, cy1, "Q / E / SCROLL", "Zoom altitude in and out")
	cy1 += 18
	draw_control_row(col1_x, cy1, "SPACE", "Select Earth / Center view")

	cy1 += 26
	rl.DrawText("FLEET SELECTION AND SQUADS", c.int(col1_x), c.int(cy1), 13, SCIFI_GREEN)
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
	rl.DrawText("TACTICAL DIRECTIVES", c.int(col1_x), c.int(cy1), 13, SCIFI_GREEN)
	cy1 += 20
	draw_control_row(col1_x, cy1, "RIGHT CLICK", "Dispatch units to planet / HQ")
	cy1 += 18
	draw_control_row(col1_x, cy1, "R-CLICK EARTH", "Set or clear Earth rally flag")
	cy1 += 18
	draw_control_row(col1_x, cy1, "B / CLICK", "Build Refinery on outpost")
	cy1 += 18
	draw_control_row(col1_x, cy1, "O / CLICK", "Build / Upgrade Orbital Defense")

	cy2 := box.y + 92
	rl.DrawText("EARTH BASE REQUISITION", c.int(col2_x), c.int(cy2), 13, SCIFI_GREEN)
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
	rl.DrawText("SYSTEM AND SIMULATION", c.int(col2_x), c.int(cy2), 13, SCIFI_GREEN)
	cy2 += 20
	draw_control_row(col2_x, cy2, "P / F10", "Pause game / Mission menu")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F11", "Toggle fullscreen window")
	cy2 += 18
	draw_control_row(col2_x, cy2, "F5", "Quick-save game state")
	cy2 += 18
	draw_control_row(col2_x, cy2, "CTRL + N", "Debug: force enemy wave")

	cy2 += 26
	rl.DrawText("TACTICAL SENSORS", c.int(col2_x), c.int(cy2), 13, SCIFI_GREEN)
	cy2 += 20
	draw_control_row(col2_x, cy2, "FOG OF WAR", "Presence required to scout")
	cy2 += 18
	draw_control_row(col2_x, cy2, "GHOST VIEW", "Stale intel retained dark")

	draw_menu_item(close_btn, "RESUME GAME", "C", true)
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

START_MENU_HINTS := [?]Menu_Hint{{"UP/DN", "NAVIGATE"}, {"ENTER", "SELECT"}, {"Q", "QUIT"}}

start_menu_rects :: proc(has_save: bool) -> (box, continue_rect, new_game_rect, quit_rect: rl.Rectangle) {
	box = menu_box(start_menu_options_count(has_save), 0, 620)
	if has_save {
		continue_rect = menu_item_rect(box, 0)
		new_game_rect = menu_item_rect(box, 1)
		quit_rect     = menu_item_rect(box, 2)
	} else {
		continue_rect = rl.Rectangle{}
		new_game_rect = menu_item_rect(box, 0)
		quit_rect     = menu_item_rect(box, 1)
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

	_, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)
	all_rects := [?]rl.Rectangle{continue_rect, new_game_rect, quit_rect}
	rects := has_save ? all_rects[:] : all_rects[1:]
	if hovered := menu_hover_index(rects); hovered >= 0 {
		start_menu_selection = hovered
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
	for r, i in rects {
		if rl.CheckCollisionPointRec(mouse, r) {
			start_menu_selection = i
			activate_start_menu_selection()
			return
		}
	}
}

draw_start_menu :: proc() {
	draw_menu_backdrop(START_MENU_HINTS[:])
	has_save := save_game_exists()
	box, continue_rect, new_game_rect, quit_rect := start_menu_rects(has_save)
	draw_menu_frame(box, "STARFALL COMMAND", "STRATEGIC SPACE DEFENSE")
	if has_save {
		draw_menu_item(continue_rect, "CONTINUE", "C", start_menu_selection == 0)
		draw_menu_item(new_game_rect, "NEW GAME", "N", start_menu_selection == 1)
		draw_menu_item(quit_rect, "QUIT", "Q", start_menu_selection == 2)
	} else {
		draw_menu_item(new_game_rect, "NEW GAME", "N", start_menu_selection == 0)
		draw_menu_item(quit_rect, "QUIT", "Q", start_menu_selection == 1)
	}
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

END_MENU_HINTS := [?]Menu_Hint{{"UP/DN", "NAVIGATE"}, {"ENTER", "SELECT"}, {"Q", "QUIT"}}
END_MENU_BODY_H :: 64
end_menu_selection := 0

end_menu_rects :: proc() -> (box, play, quit: rl.Rectangle) {
	box = menu_box(2, END_MENU_BODY_H, 600)
	play = menu_item_rect(box, 0, END_MENU_BODY_H)
	quit = menu_item_rect(box, 1, END_MENU_BODY_H)
	return
}

update_end_menu :: proc() {
	_, play_rect, quit_rect := end_menu_rects()
	rects := [?]rl.Rectangle{play_rect, quit_rect}
	if hovered := menu_hover_index(rects[:]); hovered >= 0 {
		end_menu_selection = hovered
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.DOWN) { end_menu_selection = 1 - end_menu_selection }
	activate := -1
	if rl.IsKeyPressed(.R) { activate = 0 }
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) { activate = 1 }
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) { activate = end_menu_selection }
	if rl.IsMouseButtonPressed(.LEFT) {
		mouse := rl.GetMousePosition()
		for r, i in rects {
			if rl.CheckCollisionPointRec(mouse, r) { activate = i }
		}
	}
	switch activate {
	case 0:
		end_menu_selection = 0
		restart_game()
	case 1:
		quit_requested = true
	}
}

draw_end_menu :: proc(title, subtitle, line1, line2, play_label: cstring, accent: rl.Color) {
	draw_menu_backdrop(END_MENU_HINTS[:], accent)
	box, play_rect, quit_rect := end_menu_rects()
	draw_menu_frame(box, title, subtitle, accent, accent)
	body_y := box.y + MENU_TITLE_H + 14
	draw_display_text(line1, {box.x + MENU_PAD_X, body_y}, 13, SCIFI_MINT)
	draw_display_text(line2, {box.x + MENU_PAD_X, body_y + 26}, 11, SCIFI_MUTED)
	draw_menu_item(play_rect, play_label, "R", end_menu_selection == 0, true, accent)
	draw_menu_item(quit_rect, "QUIT", "Q", end_menu_selection == 1, true, accent)
}

update_victory_overlay :: proc() {
	update_end_menu()
}

draw_victory_overlay :: proc() {
	draw_end_menu("SYSTEM LIBERATED", "VICTORY", "ALL 8 PLANETS LIBERATED - ENEMY HQ DESTROYED", "CAMPAIGN OBJECTIVE ACHIEVED - SOLAR SECTOR SECURED", "PLAY AGAIN", SCIFI_GREEN)
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
	update_end_menu()
}

draw_game_over_overlay :: proc() {
	draw_end_menu("CRITICAL DEFEAT", "MISSION FAILED", "ALL COMMAND BASES AND DRONES DESTROYED", "SECTOR DEFENSE COLLAPSED - HOSTILE FORCES PREVAIL", "RESTART", SCIFI_RED)
}

draw_resource_hud :: proc() {
	x0 := f32(HUD_PAD)
	y0 := f32(HUD_PAD)
	rail := rl.Color{30, 168, 104, 255}
	rail_dim := rl.Color{18, 96, 60, 255}

	num_size: f32 = 40
	cell := measure_display_text("0", num_size) + display_spacing(num_size)
	value := rl.TextFormat("%d", minerals)
	digits := len(string(value))
	num_x := x0
	num_right := num_x + 5 * cell
	side_x := num_right + 14
	side_w := max(measure_display_text("MINERALS", 15), measure_display_text(rl.TextFormat("+%.1f / S", global_mps()), 11))
	w := side_x - x0 + side_w + 20 + 62

	top_y := y0 + 16
	tag: cstring = "RESOURCES"
	tag_size: f32 = 10
	tag_w := measure_display_text(tag, tag_size)
	tag_x := x0 + w - 74 - tag_w
	rl.DrawRectangleRec({x0, top_y - 1.5, 44, 3}, rail)
	rl.DrawLineEx({x0, top_y}, {tag_x - 10, top_y}, 1.5, rail)
	rl.DrawCircleV({tag_x - 6, top_y}, 1.6, rail)
	draw_display_text(tag, {tag_x, top_y - 9}, tag_size, SCIFI_LABEL)

	num_y := y0 + 24
	for i in 0..<digits {
		glyph := [2]u8{(transmute([]u8)string(value))[i], 0}
		gw := measure_display_text(cstring(&glyph[0]), num_size)
		gx := num_right - f32(digits - i) * cell + (cell - display_spacing(num_size) - gw) / 2
		draw_display_text_glow(cstring(&glyph[0]), {gx, num_y}, num_size, SCIFI_MINT, rl.Color{20, 112, 96, 255}, rl.Color{60, 230, 160, 255})
	}
	for sy := num_y + 6; sy < num_y + num_size + 2; sy += 3 {
		rl.DrawLineEx({num_right - f32(digits) * cell - 4, sy}, {num_right + 4, sy}, 1, rl.Color{0, 20, 10, 46})
	}

	draw_display_text("MINERALS", {side_x, num_y + 8}, 15, SCIFI_LABEL)
	draw_display_text(rl.TextFormat("+%.1f / S", global_mps()), {side_x, num_y + 26}, 11, SCIFI_MINT)

	bot_y := y0 + 76
	slash_x := x0 + w - 62
	rl.DrawLineEx({x0, bot_y}, {slash_x, bot_y}, 1.5, rail)
	rl.DrawLineEx({slash_x, bot_y}, {slash_x + 6, bot_y - 6}, 1.5, rail)
	rl.DrawLineEx({slash_x + 6, bot_y - 6}, {slash_x + 18, bot_y - 6}, 1.5, rail)
	rl.DrawLineEx({slash_x + 18, bot_y - 6}, {slash_x + 38, top_y + 4}, 3, rail)
	rl.DrawLineEx({slash_x + 38, top_y + 4}, {slash_x + 46, top_y + 4}, 3, rail)
	rl.DrawLineEx({slash_x + 26, bot_y - 6}, {slash_x + 46, top_y + 4}, 1.5, rail_dim)
	rl.DrawLineEx({slash_x + 46, top_y + 4}, {slash_x + 52, top_y + 4}, 1.5, rail_dim)

	sub_y := bot_y + 9
	rl.DrawRectangleRec({x0, sub_y - 1.5, 44, 3}, rail)
	speed_x := x0 + 66
	draw_display_text("DRONE SPEED", {speed_x, sub_y - 6}, 9, SCIFI_LABEL)
	lvl := rl.TextFormat("LVL %d/%d", drone_speed_level, DRONE_SPEED_UPGRADE_MAX)
	lvl_x := speed_x + measure_display_text("DRONE SPEED", 9) + 10
	draw_display_text(lvl, {lvl_x, sub_y - 6}, 9, SCIFI_MINT)
	meter_x := lvl_x + measure_display_text(lvl, 9) + 10
	draw_segmented_meter({meter_x, sub_y - 4, 60, 8}, f32(drone_speed_level) / f32(DRONE_SPEED_UPGRADE_MAX), DRONE_SPEED_UPGRADE_MAX, SCIFI_FILL, SCIFI_DIM)
}
