package main

import "core:c"
import "core:fmt"
import rl "vendor:raylib"

draw_inspector :: proc() {
	panel_orig_x := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	h := f32(ui_screen_h())

	container_x := panel_orig_x + 4.0
	container_y: f32 = 12.0
	container_w := f32(SCREEN_PANEL_WIDTH) - 8.0
	container_h := h - 24.0

	draw_tactical_container({container_x, container_y, container_w, container_h})

	x := panel_orig_x

	header_y: c.int = 26
	is_enemy := selected_planet == ENEMY_HOME

	if is_enemy {
		hq_title: cstring = "ENEMY CITADEL"
		if enemy_hq_destroyed() { hq_title = "CITADEL SILENCED (DEAD)" }
		rl.DrawText(hq_title, c.int(x + PANEL_PAD_X), header_y, 17, SCIFI_RED)
	} else {
		rl.DrawText(planets[selected_planet].name, c.int(x + PANEL_PAD_X), header_y, 17, SCIFI_TEXT)

		if selected_planet == EARTH || has_vision(selected_planet) || intel_recorded[selected_planet] {
			mps_text := rl.TextFormat("%.1f MPS", planet_mps(selected_planet))
			mps_w := f32(rl.MeasureText(mps_text, 14))
			rl.DrawText(mps_text, c.int(x + PANEL_PAD_X + PANEL_CONTENT_W - mps_w), header_y + 2, 14, SCIFI_AMBER)
		} else {
			unscouted: cstring = "DARK"
			uw := f32(rl.MeasureText(unscouted, 14))
			rl.DrawText(unscouted, c.int(x + PANEL_PAD_X + PANEL_CONTENT_W - uw), header_y + 2, 14, SCIFI_MUTED)
		}
	}

	if selected_planet == EARTH {
		draw_earth_inspector(x)
	} else if selected_planet == ENEMY_HOME {
		draw_hq_inspector(x)
	} else {
		draw_outpost_inspector(x)
	}

	roster_bottom := h > 700 ? f32(ui_screen_h() - 36) - 6 : container_y + container_h - 8
	begin_ui_scissor({x, 0, f32(SCREEN_PANEL_WIDTH), roster_bottom})
	if ghost_view() {
		draw_ghost_rosters(x)
	} else if selected_planet == EARTH || has_vision(selected_planet) {
		mining_count := roster_count(.MINING)
		mining_hdr := selected_planet != ENEMY_HOME ? rl.TextFormat("MINING DRONES (%d/%d)", mining_count, planet_mining_cap(selected_planet)) : rl.TextFormat("MINING DRONES (%d)", mining_count)
		y_mining := unit_tile_y(.MINING)
		draw_section_header(x + PANEL_PAD_X, f32(y_mining - 23), PANEL_CONTENT_W, mining_hdr, SCIFI_AMBER)
		draw_roster_tiles(x, y_mining, .MINING, false)
		combat_count := roster_count(.COMBAT)
		y_combat := unit_tile_y(.COMBAT)
		draw_section_header(x + PANEL_PAD_X, f32(y_combat - 23), PANEL_CONTENT_W, rl.TextFormat("FIGHTING DRONES (%d)", combat_count), SCIFI_BLUE)
		draw_roster_tiles(x, y_combat, .COMBAT, false)
		if has_vision(selected_planet) {
			enemy_mining := enemy_roster_count(.MINING)
			if enemy_mining > 0 {
				y_em := enemy_tile_y(.MINING)
				draw_section_header(x + PANEL_PAD_X, f32(y_em - 23), PANEL_CONTENT_W, rl.TextFormat("HOSTILE MINING (%d)", enemy_mining), SCIFI_RED)
				draw_roster_tiles(x, y_em, .MINING, true)
			}
			enemy_combat := enemy_roster_count(.COMBAT)
			if enemy_combat > 0 {
				y_ec := enemy_tile_y(.COMBAT)
				draw_section_header(x + PANEL_PAD_X, f32(y_ec - 23), PANEL_CONTENT_W, rl.TextFormat("HOSTILE FIGHTERS (%d)", enemy_combat), SCIFI_RED)
				draw_roster_tiles(x, y_ec, .COMBAT, true)
			}
		}
	}
	rl.EndScissorMode()
	if h > 700 {
		sel_y := f32(ui_screen_h() - 36)
		sel_rect := rl.Rectangle{x + PANEL_PAD_X, sel_y, PANEL_CONTENT_W, 22}
		sel_count := selection_count()
		if sel_count > 0 {
			draw_chamfered_panel(sel_rect, 4, rl.Color{10, 30, 40, 240}, SCIFI_GREEN)
			draw_corner_brackets(sel_rect, 1, 4, SCIFI_MINT)
			rl.DrawText(rl.TextFormat("ACTIVE SQUAD: %d UNITS SELECTED", sel_count), i32(sel_rect.x + 10), i32(sel_rect.y + 5), 11, SCIFI_MINT)
		} else {
			draw_chamfered_panel(sel_rect, 4, SCIFI_PANEL_SOLID, SCIFI_DIM)
			rl.DrawText("NO UNITS SELECTED", i32(sel_rect.x + 10), i32(sel_rect.y + 5), 11, SCIFI_MUTED)
		}
	}
	if inspector_drag_active {
		rect := rect_between(inspector_drag_start, ui_mouse())
		rl.DrawRectangleRec(rect, rl.Fade(SCIFI_GREEN, 0.18))
		rl.DrawRectangleLinesEx(rect, 1, SCIFI_GREEN)
		draw_corner_brackets(rect, 0, 6, SCIFI_MINT)
	}
}

draw_earth_inspector :: proc(x: f32) {
	if base_button_visible() {
		base_button := base_button_rect(x)
		if base_build_planet == EARTH {
			progress := base_build_progress / BASE_CONSTRUCT_TIME
			detail := crew_short(EARTH, .BASE) ? fmt.ctprintf("CREW %d/%d - MINERS AUTO-JOIN", crew_size(EARTH, .BASE), BASE_CONSTRUCT_MINERS) : fmt.ctprintf("ONLINE IN %.1fs", BASE_CONSTRUCT_TIME - base_build_progress)
			draw_status_button(base_button, "BUILDING COMMAND BASE", detail, fmt.ctprintf("%d%%", int(progress * 100)), progress)
		} else {
			can_build_base := minerals >= BASE_COST && base_counts[EARTH] < MAX_BASES && base_build_planet < 0 && planet_liberated(EARTH)
			draw_button(base_button, "COMMAND BASE", fmt.ctprintf("COST %d - +1 PARALLEL BUILD", BASE_COST), "", can_build_base)
		}
	}

	draw_orbital_defense_inspector_section(x, orbital_defense_button_rect(x, EARTH), EARTH)

	orders_y := production_orders_y()
	draw_section_header(x + PANEL_PAD_X, f32(orders_y - 23), PANEL_CONTENT_W, "FLEET REQUISITION", SCIFI_AMBER)
	queue_not_full := queued_count(EARTH) < base_counts[EARTH] * 5
	can_build_miner := minerals >= unit_cost(.MINING) && queue_not_full
	can_build_combat := minerals >= unit_cost(.COMBAT) && queue_not_full
	draw_button(miner_button_rect(x), "MINER", fmt.ctprintf("COST %d", MINER_COST), "M", can_build_miner)
	draw_button(combat_button_rect(x), "COMBAT", fmt.ctprintf("COST %d", COMBAT_COST), "C", can_build_combat)

	if base_counts[EARTH] >= MAX_BASES {
		draw_button(queue_5_miner_button_rect(x), "+5 MINERS", fmt.ctprintf("COST %d", BATCH_MINER_COST), "N", can_build_5_miners())
		draw_button(queue_5_combat_button_rect(x), "+5 COMBAT", fmt.ctprintf("COST %d", BATCH_COMBAT_COST), "X", can_build_5_combat())
	}

	if !drone_speed_maxed() {
		can_upgrade_speed := minerals >= DRONE_SPEED_UPGRADE_COST
		draw_button(drone_speed_button_rect(x), "DRONE BUILD SPEED", fmt.ctprintf("COST %d - LVL %d/%d", DRONE_SPEED_UPGRADE_COST, drone_speed_level, DRONE_SPEED_UPGRADE_MAX), "U", can_upgrade_speed)
	}

	queue_y := earth_queue_y()
	queue_capacity := base_counts[EARTH] * MAX_BASES
	queue_total := queued_count(EARTH)
	draw_section_header(x + PANEL_PAD_X, f32(queue_y), PANEL_CONTENT_W, rl.TextFormat("QUEUE BUFFER (%d/%d)", queue_total, queue_capacity), SCIFI_GREEN)
	if base_counts[EARTH] >= MAX_BASES {
		draw_autobuild_radio_buttons(x)
	}
	for slot := 0; slot < queue_capacity; slot += 1 {
		queued := slot < queue_total
		kind := Unit_Type.MINING
		progress: f32 = -1
		if queued { kind = queue_kind_at(EARTH, slot); progress = queue_progress_at(EARTH, slot) }
		draw_queue_slot(queue_slot_rect(x, slot), queued, kind, progress)
	}
}

draw_hq_inspector :: proc(x: f32) {
	card := rl.Rectangle{x + PANEL_PAD_X, OUTPOST_CARD_Y, PANEL_CONTENT_W, CARD_H}
	if enemy_hq_destroyed() {
		draw_status_card(card, SCIFI_DIM)
		rl.DrawText("CITADEL SILENCED - HUSK", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("NO WAVES LAUNCH FROM A DEAD HQ", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	} else if has_vision(ENEMY_HOME) {
		_, garrison := planet_combatants(ENEMY_HOME)
		draw_status_card(card, SCIFI_RED)
		rl.DrawText("HOSTILE CITADEL", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_RED)
		if orbital_defense_level[ENEMY_HOME] > 0 {
			max_hp := orbital_defense_max_hp(ENEMY_HOME)
			cur_hp := orbital_defense_hp[ENEMY_HOME]
			rl.DrawText(rl.TextFormat("GARRISON %d   DEF LVL %d (HP %d/%d)", garrison, orbital_defense_level[ENEMY_HOME], cur_hp, max_hp), i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2 - 2, 11, SCIFI_TEXT)
			draw_progress({x + PANEL_PAD_X + CARD_INSET, CARD_LINE_2 + 13, PANEL_CONTENT_W - 2 * CARD_INSET, 6}, f32(cur_hp) / f32(max(1, max_hp)), SCIFI_RED)
		} else {
			rl.DrawText(rl.TextFormat("FIGHTERS %d   INTEGRITY %d/%d (DEF OFFLINE)", garrison, enemy_base_hp[ENEMY_HOME], ENEMY_HQ_BASE_HP), i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2 - 2, 11, SCIFI_TEXT)
			draw_progress({x + PANEL_PAD_X + CARD_INSET, CARD_LINE_2 + 13, PANEL_CONTENT_W - 2 * CARD_INSET, 6}, f32(enemy_base_hp[ENEMY_HOME]) / f32(ENEMY_HQ_BASE_HP), SCIFI_RED)
		}
	} else {
		draw_status_card(card, SCIFI_STEEL)
		rl.DrawText("UNSCOUTED REACHES", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
		rl.DrawText("DISPATCH COMBAT DRONES TO REVEAL", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
	}
}

draw_outpost_inspector :: proc(x: f32) {
	if !planet_liberated(selected_planet) {
		card := rl.Rectangle{x + PANEL_PAD_X, OUTPOST_CARD_Y, PANEL_CONTENT_W, CARD_H}
		if has_vision(selected_planet) {
			stronghold_color := SCIFI_RED
			title: cstring = "ENEMY STRONGHOLD"
			_, garrison := planet_combatants(selected_planet)
			status := rl.TextFormat("%02d FIGHTERS  BASE %02d: HOSTILE OCCUPATION", garrison, enemy_base_hp[selected_planet])
			draw_status_card(card, stronghold_color)
			rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, stronghold_color)
			rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
		} else if intel_recorded[selected_planet] {
			intel := last_known_intel[selected_planet]
			title: cstring = "ENEMY STRONGHOLD (STALE INTEL)"
			status := rl.TextFormat("%02d FIGHTERS  BASE %02d/%02d: PREVIOUS RECON", intel.fighters, intel.miners, GARRISON_BASE_HP[selected_planet])
			draw_status_card(card, SCIFI_AMBER)
			rl.DrawText(title, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_AMBER)
			rl.DrawText(status, i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_MUTED)
		} else {
			draw_status_card(card, SCIFI_STEEL)
			rl.DrawText("UNSCOUTED SECTOR", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_1, 13, SCIFI_MUTED)
			rl.DrawText("STATUS UNKNOWN: DISPATCH SCOUT", i32(x + PANEL_PAD_X + CARD_INSET), CARD_LINE_2, 11, SCIFI_TEXT)
		}
	}

	if planet_liberated(selected_planet) {
		btn := refinery_button_rect(x)
		if refinery_building[selected_planet] {
			progress := refinery_progress[selected_planet] / REFINERY_BUILD_TIME
			detail := crew_short(selected_planet, .REFINERY) ? fmt.ctprintf("CREW %d/%d - MINERS AUTO-JOIN", crew_size(selected_planet, .REFINERY), REFINERY_CONSTRUCT_MINERS) : fmt.ctprintf("ONLINE IN %.1fs", REFINERY_BUILD_TIME - refinery_progress[selected_planet])
			draw_status_button(btn, "BUILDING REFINERY", detail, fmt.ctprintf("%d%%", int(progress * 100)), progress)
		} else if !refinery_built[selected_planet] {
			draw_button(btn, "BUILD REFINERY", fmt.ctprintf("COST %d - CREW %d", refinery_cost(selected_planet), REFINERY_CONSTRUCT_MINERS), "B", can_build_refinery(selected_planet))
		} else {
			draw_status_button(btn, "REFINERY", "OPERATIONAL", "ONLINE", -1, SCIFI_MINT)
		}
		def_btn := orbital_defense_button_rect(x, selected_planet)
		draw_orbital_defense_inspector_section(x, def_btn, selected_planet)
	}
}

draw_ghost_rosters :: proc(x: f32) {
	intel := last_known_intel[selected_planet]

	kinds := [2]Unit_Type{.MINING, .COMBAT}
	for section in 0..<2 {
		kind := kinds[section]
		label: cstring = "FIGHTING DRONES"
		color := SCIFI_BLUE
		if section == 0 { label = "MINING DRONES"; color = SCIFI_AMBER }
		count := ghost_count(kind, false)
		if count == 0 { continue }
		y := unit_tile_y(kind)
		hdr := section == 0 ? rl.TextFormat("%s (%d/%d) [STALE]", label, count, planet_mining_cap(selected_planet)) : rl.TextFormat("%s (%d) [STALE]", label, count)
		draw_section_header(x + PANEL_PAD_X, f32(y - 23), PANEL_CONTENT_W, hdr, color)
		ordinal := 0
		for i := 0; i < intel.unit_count; i += 1 {
			u := &intel.units[i]
			if u.kind != kind || u.enemy { continue }
			draw_unit_tile_data(u.kind, u.state, false, x, y, ordinal, false)
			ordinal += 1
		}
		flush_unit_tile_overlays()
	}

	for section in 0..<2 {
		kind := kinds[section]
		label: cstring = "HOSTILE FIGHTERS"
		if section == 0 { label = "HOSTILE MINING" }
		count := ghost_count(kind, true)
		if count == 0 { continue }
		y := enemy_tile_y(kind)
		draw_section_header(x + PANEL_PAD_X, f32(y - 23), PANEL_CONTENT_W, rl.TextFormat("%s (%d) [STALE]", label, count), SCIFI_RED)
		ordinal := 0
		for i := 0; i < intel.unit_count; i += 1 {
			u := &intel.units[i]
			if u.kind != kind || !u.enemy { continue }
			draw_unit_tile_data(u.kind, u.state, false, x, y, ordinal, true)
			ordinal += 1
		}
		flush_unit_tile_overlays()
	}

	top := f32(unit_tile_y(.MINING) - 22)
	rl.DrawRectangleRec(rl.Rectangle{x, top, SCREEN_PANEL_WIDTH - 6, f32(ui_screen_h() - 40) - top}, rl.Color{6, 16, 22, 160})
}

production_orders_y :: proc() -> int {
	base_y := ORDERS_BASE_Y
	if selected_planet == EARTH {
		return int(earth_orbital_defense_bottom_y()) + SECTION_BELOW_DY
	}
	return base_y + max(base_counts[selected_planet] - 1, 0) * PROD_PITCH
}

queued_count :: proc(planet: int) -> int {
	count := pending_count[planet]
	for b := 0; b < base_counts[planet]; b += 1 { if production[planet][b].active { count += 1 } }
	return count
}

queue_kind_at :: proc(planet, index: int) -> Unit_Type {
	queue_index := index
	for b := 0; b < base_counts[planet]; b += 1 {
		if !production[planet][b].active { continue }
		if queue_index == 0 { return production[planet][b].kind }
		queue_index -= 1
	}
	return pending[planet][queue_index]
}

queue_progress_at :: proc(planet, index: int) -> f32 {
	queue_index := index
	for b := 0; b < base_counts[planet]; b += 1 {
		if !production[planet][b].active { continue }
		if queue_index == 0 {
			total := drone_build_time(production[planet][b].kind)
			return production[planet][b].progress / total
		}
		queue_index -= 1
	}
	return -1
}

unit_in_roster :: proc(index: int, kind: Unit_Type) -> bool {
	if units[index].enemy { return false }
	if units[index].kind != kind { return false }
	if kind == .MINING { return units[index].target_planet == selected_planet }
	return units[index].affiliation == selected_planet
}

roster_count :: proc(kind: Unit_Type) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if unit_in_roster(i, kind) { count += 1 } }
	return count
}

unit_tile_y :: proc(kind: Unit_Type) -> int {
	mining_rows := (view_count(.MINING, false) + TILES_PER_ROW - 1) / TILES_PER_ROW
	y := ROSTER_BASE_Y
	if selected_planet == EARTH {
		extra_dy := 0
		if base_counts[EARTH] >= MAX_BASES {
			extra_dy = UPGRADE_DY
		}
		if drone_speed_maxed() {
			extra_dy -= UPGRADE_DY
		}
		y = production_orders_y() + ROSTER_BELOW_QUEUE + extra_dy + (base_counts[selected_planet] - 1) * GRID_PITCH
	} else if selected_planet != ENEMY_HOME && planet_liberated(selected_planet) {
		y = outpost_liberated_roster_y(selected_planet)
	}
	if kind == .COMBAT { y += SECTION_PAD_Y + mining_rows * (TILE_SIZE + TILE_GAP) }
	return y
}

enemy_in_roster :: proc(index: int, kind: Unit_Type) -> bool {
	u := &units[index]
	if !u.enemy || u.kind != kind { return false }
	if kind == .MINING { return u.target_planet == selected_planet }
	return u.affiliation == selected_planet
}

enemy_roster_count :: proc(kind: Unit_Type) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 { if enemy_in_roster(i, kind) { count += 1 } }
	return count
}

enemy_tile_y :: proc(kind: Unit_Type) -> int {
	combat_rows := (view_count(.COMBAT, false) + TILES_PER_ROW - 1) / TILES_PER_ROW
	y := unit_tile_y(.COMBAT) + SECTION_PAD_Y + combat_rows * (TILE_SIZE + TILE_GAP)
	if kind == .COMBAT {
		enemy_mining_count := view_count(.MINING, true)
		if enemy_mining_count > 0 {
			enemy_mining_rows := (enemy_mining_count + TILES_PER_ROW - 1) / TILES_PER_ROW
			y += SECTION_PAD_Y + enemy_mining_rows * (TILE_SIZE + TILE_GAP)
		}
	}
	return y
}

ghost_view :: proc() -> bool {
	return selected_planet != EARTH && selected_planet != ENEMY_HOME && !has_vision(selected_planet) && intel_recorded[selected_planet]
}

ghost_count :: proc(kind: Unit_Type, enemy: bool) -> int {
	count := 0
	intel := last_known_intel[selected_planet]
	for i := 0; i < intel.unit_count; i += 1 {
		u := &intel.units[i]
		if u.kind == kind && u.enemy == enemy { count += 1 }
	}
	return count
}

view_count :: proc(kind: Unit_Type, enemy: bool) -> int {
	if ghost_view() { return ghost_count(kind, enemy) }
	if enemy { return enemy_roster_count(kind) }
	return roster_count(kind)
}

unit_tile_rect :: proc(x: f32, y: int, ordinal: int) -> rl.Rectangle {
	column := ordinal % TILES_PER_ROW
	row := ordinal / TILES_PER_ROW
	row_w := f32(TILES_PER_ROW * (TILE_SIZE + TILE_GAP) - TILE_GAP)
	return rl.Rectangle{x + (f32(SCREEN_PANEL_WIDTH) - row_w) / 2 + f32(column * (TILE_SIZE + TILE_GAP)), f32(y + row * (TILE_SIZE + TILE_GAP)), TILE_SIZE, TILE_SIZE}
}

draw_unit_tile :: proc(index: int, x: f32, y: int, ordinal: int, enemy: bool) {
	draw_unit_tile_data(units[index].kind, units[index].state, selected_units[index], x, y, ordinal, enemy)
}

draw_roster_tiles :: proc(x: f32, y: int, kind: Unit_Type, enemy: bool) {
	ordinal := 0
	for i := 0; i < unit_count; i += 1 {
		in_roster := enemy ? enemy_in_roster(i, kind) : unit_in_roster(i, kind)
		if !in_roster { continue }
		draw_unit_tile(i, x, y, ordinal, enemy)
		ordinal += 1
	}
	flush_unit_tile_overlays()
}

TILE_DOT_SEGMENTS :: 12

Tile_Dot :: struct {
	x, y:  c.int,
	color: rl.Color,
}

tile_brackets: [MAX_UNITS]rl.Rectangle
tile_bracket_count: int
tile_dots: [MAX_UNITS]Tile_Dot
tile_dot_count: int

draw_unit_tile_data :: proc(kind: Unit_Type, state: Unit_State, selected: bool, x: f32, y: int, ordinal: int, enemy: bool) {
	rect := unit_tile_rect(x, y, ordinal)
	if rect.y > f32(ui_screen_h()) || rect.y + rect.height < 0 { return }
	accent := SCIFI_AMBER
	if kind == .COMBAT { accent = SCIFI_BLUE }
	if enemy { accent = SCIFI_RED }
	center := rl.Vector2{rect.x + rect.width * 0.5, rect.y + rect.height * 0.5}
	draw_unit_icon(kind, center, rect.width, accent)
	if selected && !enemy && tile_bracket_count < MAX_UNITS {
		tile_brackets[tile_bracket_count] = rect
		tile_bracket_count += 1
	}
	if tile_dot_count < MAX_UNITS {
		tile_dots[tile_dot_count] = {c.int(rect.x + rect.width - 2), c.int(rect.y + 2), state_color(state)}
		tile_dot_count += 1
	}
}

flush_unit_tile_overlays :: proc() {
	for i in 0..<tile_bracket_count {
		draw_corner_brackets(tile_brackets[i], 1, 4, SCIFI_GREEN)
	}
	for i in 0..<tile_dot_count {
		rl.DrawCircleSector({f32(tile_dots[i].x), f32(tile_dots[i].y)}, 3, 0, 360, TILE_DOT_SEGMENTS, tile_dots[i].color)
	}
	tile_bracket_count = 0
	tile_dot_count = 0
}

