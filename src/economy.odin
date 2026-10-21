package main

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"


base_button_visible :: proc() -> bool {
	return base_counts[EARTH] < MAX_BASES || base_build_planet == EARTH
}

start_base_construction :: proc() {
	if selected_planet != EARTH { return }
	if base_counts[selected_planet] >= MAX_BASES || base_build_planet >= 0 || minerals < BASE_COST { return }
	if !planet_liberated(selected_planet) { return }
	minerals -= BASE_COST
	base_build_planet = selected_planet
	base_build_progress = 0
	construction_seq_counter += 1
	base_build_order[EARTH] = construction_seq_counter

	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			if u.target_planet == EARTH || u.affiliation == EARTH {
				if base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .BASE
					u.progress = 0
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			if u.target_planet == EARTH || u.affiliation == EARTH {
				if (u.state == .MINING || u.state == .DEPOSITING) && base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .BASE
					u.progress = 0
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	}
}

refinery_cost :: proc(planet: int) -> int {
	return planet_mining_cap(planet) * 10
}

can_build_refinery :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	if !planet_liberated(planet) { return false }
	if refinery_built[planet] || refinery_building[planet] { return false }
	return minerals >= refinery_cost(planet)
}

refinery_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, REFINERY_BTN_Y, PANEL_CONTENT_W, BASE_BTN_H}
}

refinery_button_visible :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	return planet_liberated(planet)
}

start_refinery_construction :: proc(planet: int) {
	if !can_build_refinery(planet) { return }
	minerals -= refinery_cost(planet)
	refinery_building[planet] = true
	refinery_progress[planet] = 0
	construction_seq_counter += 1
	refinery_build_order[planet] = construction_seq_counter

	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state == .IDLE {
			if refinery_constructing_miners(planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.build_target = .REFINERY
				u.progress = 0
				u.mining_active = false
			}
		}
	}

	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state == .MINING {
			if refinery_constructing_miners(planet) < REFINERY_CONSTRUCT_MINERS {
				u.state = .CONSTRUCTING
				u.build_target = .REFINERY
				u.progress = 0
				u.mining_active = false
			}
		}
	}
}

planet_can_mine :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT { return false }
	return planet_liberated(planet) && refinery_built[planet]
}

planet_has_refinery_beam :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	return refinery_built[planet]
}

constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p { count += 1 }
	}
	return count
}

refinery_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .REFINERY || (u.build_target == .NONE && !orbital_defense_building[p] && !orbital_defense_ammo_building[p] && base_build_planet != p) {
				count += 1
			}
		}
	}
	return count
}

orbital_defense_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .ORBITAL_DEFENSE || (u.build_target == .NONE && !refinery_building[p] && !orbital_defense_ammo_building[p] && base_build_planet != p) {
				count += 1
			}
		}
	}
	return count
}

base_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if u.build_target == .BASE || (u.build_target == .NONE && !refinery_building[p] && !orbital_defense_building[p] && !orbital_defense_ammo_building[p]) {
				count += 1
			}
		}
	}
	return count
}

planet_next_needed_build_target :: proc(p: int) -> Build_Target {
	if p < 0 || p >= PLANET_COUNT { return .NONE }

	if p == EARTH {
		needs_base := (base_build_planet == EARTH) && base_constructing_miners(EARTH) < BASE_CONSTRUCT_MINERS
		needs_defense := orbital_defense_building[EARTH] && orbital_defense_constructing_miners(EARTH) < ORBITAL_DEFENSE_CONSTRUCT_MINERS
		needs_ammo := orbital_defense_ammo_building[EARTH] && orbital_ammo_constructing_miners(EARTH) < ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS

		if needs_base && needs_defense {
			if base_build_order[EARTH] <= orbital_defense_build_order[EARTH] {
				return .BASE
			} else {
				return .ORBITAL_DEFENSE
			}
		} else if needs_base {
			return .BASE
		} else if needs_defense {
			return .ORBITAL_DEFENSE
		} else if needs_ammo {
			return .ORBITAL_DEFENSE_AMMO
		}
		return .NONE
	}

	needs_refinery := refinery_building[p] && refinery_constructing_miners(p) < REFINERY_CONSTRUCT_MINERS
	needs_defense := orbital_defense_building[p] && orbital_defense_constructing_miners(p) < ORBITAL_DEFENSE_CONSTRUCT_MINERS
	needs_ammo := orbital_defense_ammo_building[p] && orbital_ammo_constructing_miners(p) < ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS

	if needs_refinery && needs_defense {
		if refinery_build_order[p] <= orbital_defense_build_order[p] {
			return .REFINERY
		} else {
			return .ORBITAL_DEFENSE
		}
	} else if needs_refinery {
		return .REFINERY
	} else if needs_defense {
		return .ORBITAL_DEFENSE
	} else if needs_ammo {
		return .ORBITAL_DEFENSE_AMMO
	}
	return .NONE
}

earth_assigned_miner_available :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state == .CONSTRUCTING { continue }
		if u.target_planet == EARTH || u.affiliation == EARTH { return true }
	}
	return false
}

constructing_miners_at :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .CONSTRUCTING && u.target_planet == p { count += 1 }
	}
	return count
}

resume_constructing_miners :: proc(p: int, finished: Build_Target = .NONE) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p {
			if finished == .NONE || u.build_target == finished || u.build_target == .NONE {
				next_target := planet_next_needed_build_target(p)
				if next_target != .NONE {
					u.build_target = next_target
					u.progress = 0
					u.mining_active = false
				} else {
					u.build_target = .NONE
					u.progress = 0
					if planet_can_mine(p) && active_mining_drones_count(p) < planet_mining_cap(p) {
						u.state = .MINING
						u.mining_active = true
					} else {
						u.state = .IDLE
						u.mining_active = false
					}
				}
			}
		}
	}
}

player_miners_count :: proc(planet: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy {
			if planet == EARTH {
				if u.target_planet == EARTH || u.affiliation == EARTH { count += 1 }
			} else {
				if u.target_planet == planet { count += 1 }
			}
		}
	}
	return count
}

recruit_build_crew :: proc(planet: int, target: Build_Target, need: int) {
	count_crew := proc(p: int, t: Build_Target) -> int {
		n := 0
		for i := 0; i < unit_count; i += 1 {
			u := &units[i]
			if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p && u.build_target == t { n += 1 }
		}
		return n
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
			} else {
				is_match = (u.target_planet == planet)
			}
			if is_match && count_crew(planet, target) < need {
				u.state = .CONSTRUCTING
				u.build_target = target
				u.progress = 0
				u.target_planet = planet
				u.affiliation = planet
				u.mining_active = false
			}
		}
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH) && (u.state == .MINING || u.state == .DEPOSITING)
			} else {
				is_match = (u.target_planet == planet) && (u.state == .MINING)
			}
			if is_match && count_crew(planet, target) < need {
				u.state = .CONSTRUCTING
				u.build_target = target
				u.progress = 0
				u.target_planet = planet
				u.affiliation = planet
				u.mining_active = false
			}
		}
	}
}

player_miners_at_planet :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		count += 1
	}
	return count
}

unit_cost :: proc(kind: Unit_Type) -> int {
	if kind == .COMBAT { return COMBAT_COST }
	return MINER_COST
}

drone_build_time :: proc(kind: Unit_Type) -> f32 {
	base: f32 = MINER_BUILD_TIME
	if kind == .COMBAT { base = COMBAT_BUILD_TIME }
	return base * math.pow(DRONE_SPEED_UPGRADE_FACTOR, f32(drone_speed_level))
}

drone_speed_maxed :: proc() -> bool {
	return drone_speed_level >= DRONE_SPEED_UPGRADE_MAX
}

purchase_drone_speed_upgrade :: proc() -> bool {
	if selected_planet != EARTH { return false }
	if drone_speed_maxed() || minerals < DRONE_SPEED_UPGRADE_COST { return false }
	minerals -= DRONE_SPEED_UPGRADE_COST
	drone_speed_level += 1
	return true
}

queue_unit_on_earth :: proc(kind: Unit_Type) -> bool {
	cost := unit_cost(kind)
	if minerals < cost || queued_count(EARTH) >= base_counts[EARTH] * 5 { return false }
	minerals -= cost
	for i := 0; i < base_counts[EARTH]; i += 1 {
		if !production[EARTH][i].active {
			production[EARTH][i] = Production{kind = kind, active = true, progress = 0}
			return true
		}
	}
	pending[EARTH][pending_count[EARTH]] = kind
	pending_count[EARTH] += 1
	return true
}

can_queue_unit :: proc(kind: Unit_Type) -> bool {
	return minerals >= unit_cost(kind) && queued_count(EARTH) < base_counts[EARTH] * 5
}

queue_unit :: proc(kind: Unit_Type) {
	if selected_planet != EARTH { return }
	queue_unit_on_earth(kind)
}

queue_5_units_on_earth :: proc(kind: Unit_Type) {
	for _ in 0..<BATCH_BUILD_COUNT {
		if !queue_unit_on_earth(kind) { break }
	}
}

can_use_autobuilder :: proc() -> bool {
	return base_counts[EARTH] >= MAX_BASES
}

toggle_autobuild_mode :: proc() {
	if !can_use_autobuilder() { return }
	if auto_build_mode != .OFF {
		auto_build_last_mode = auto_build_mode
		auto_build_mode = .OFF
	} else {
		target := auto_build_last_mode
		if target == .OFF { target = .MINERS }
		auto_build_mode = target
	}
	autobuild_retry_timer = 0
}

set_autobuild_mode :: proc(mode: Auto_Build_Mode) {
	if !can_use_autobuilder() && mode != .OFF { return }
	auto_build_mode = mode
	if mode != .OFF {
		auto_build_last_mode = mode
	}
	autobuild_retry_timer = 0
}

autobuild_radio_rects :: proc(panel_x: f32) -> (off_rect, miner_rect, combat_rect: rl.Rectangle) {
	btn_h: f32 = 20.0
	y := f32(earth_queue_y() - 2)
	right := panel_x + PANEL_PAD_X + PANEL_CONTENT_W
	w_off: f32 = 36.0
	w_m: f32 = 26.0
	w_c: f32 = 26.0
	total_w := w_off + w_m + w_c
	x0 := right - total_w

	off_rect = rl.Rectangle{x0, y, w_off, btn_h}
	miner_rect = rl.Rectangle{x0 + w_off, y, w_m, btn_h}
	combat_rect = rl.Rectangle{x0 + w_off + w_m, y, w_c, btn_h}
	return
}

autobuild_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	off_r, _, combat_r := autobuild_radio_rects(panel_x)
	return rl.Rectangle{off_r.x, off_r.y, (combat_r.x + combat_r.width) - off_r.x, off_r.height}
}

update_autobuilder :: proc(dt: f32) {
	if !can_use_autobuilder() || auto_build_mode == .OFF {
		autobuild_retry_timer = 0
		return
	}

	if queued_count(EARTH) > 0 {
		autobuild_retry_timer = 0
		return
	}

	cost := auto_build_mode == .MINERS ? BATCH_MINER_COST : BATCH_COMBAT_COST

	if autobuild_retry_timer > 0 {
		autobuild_retry_timer -= dt
		if autobuild_retry_timer > 0 {
			return
		}
	}

	if minerals >= cost {
		unit_type := auto_build_mode == .MINERS ? Unit_Type.MINING : Unit_Type.COMBAT
		auto_build_last_mode = auto_build_mode
		queue_5_units_on_earth(unit_type)
		autobuild_retry_timer = 0
	} else {
		autobuild_retry_timer = 1.0
	}
}

queue_units :: proc(kind: Unit_Type, count: int) {
	for _ in 0..<count {
		if minerals < unit_cost(kind) || queued_count(selected_planet) >= base_counts[selected_planet] * 5 {
			break
		}
		queue_unit(kind)
	}
}

can_build_5_miners :: proc() -> bool {
	return selected_planet == EARTH && base_counts[EARTH] >= MAX_BASES && minerals >= BATCH_MINER_COST && queued_count(EARTH) < base_counts[EARTH] * 5
}

can_build_5_combat :: proc() -> bool {
	return selected_planet == EARTH && base_counts[EARTH] >= MAX_BASES && minerals >= BATCH_COMBAT_COST && queued_count(EARTH) < base_counts[EARTH] * 5
}

queue_5_miners :: proc() {
	if !can_build_5_miners() { return }
	queue_units(.MINING, BATCH_BUILD_COUNT)
}

queue_5_combat :: proc() {
	if !can_build_5_combat() { return }
	queue_units(.COMBAT, BATCH_BUILD_COUNT)
}

drone_speed_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	dy := UPGRADE_DY
	if base_counts[EARTH] >= MAX_BASES {
		dy += UPGRADE_DY
	}
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + dy), PANEL_CONTENT_W, UPGRADE_H}
}

queue_5_miner_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

queue_5_combat_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

controls_button_rect :: proc() -> rl.Rectangle {
	dock_y := f32(rl.GetScreenHeight() - BOTTOM_DOCK_H - 12)
	return rl.Rectangle{HUD_PAD, dock_y, 110, BOTTOM_DOCK_H}
}

earth_queue_y :: proc() -> int {
	dy := QUEUE_DY
	if base_counts[EARTH] >= MAX_BASES {
		dy += UPGRADE_DY
	}
	if drone_speed_maxed() {
		dy -= UPGRADE_DY
	}
	return production_orders_y() + dy
}

queue_slot_rect :: proc(panel_x: f32, slot: int) -> rl.Rectangle {
	queue_y := f32(earth_queue_y())
	rows := base_counts[EARTH]
	if rows < 1 { rows = 1 }
	row := slot % rows
	column := slot / rows
	return rl.Rectangle{panel_x + PANEL_PAD_X + f32(column * (QUEUE_SLOT_W + QUEUE_SLOT_GAP)), queue_y + QUEUE_LABEL_GAP + f32(row * GRID_PITCH), QUEUE_SLOT_W, QUEUE_SLOT_H}
}

cancel_queued_at :: proc(planet, index: int) -> bool {
	b := 0
	found := -1
	i := index
	for b < base_counts[planet] {
		if !production[planet][b].active { b += 1; continue }
		if i == 0 { found = b; break }
		i -= 1
		b += 1
	}
	if found >= 0 {
		line := &production[planet][found]
		minerals += unit_cost(line.kind)
		line.active = false
		line.progress = 0
		if pending_count[planet] > 0 {
			line.kind = pending[planet][0]
			line.active = true
			for q := 1; q < pending_count[planet]; q += 1 { pending[planet][q-1] = pending[planet][q] }
			pending_count[planet] -= 1
		}
		return true
	}
	if i < pending_count[planet] {
		minerals += unit_cost(pending[planet][i])
		for q := i; q < pending_count[planet] - 1; q += 1 { pending[planet][q] = pending[planet][q+1] }
		pending_count[planet] -= 1
		return true
	}
	return false
}

cancel_last_queued :: proc() -> bool {
	if queued_count(EARTH) == 0 { return false }
	return cancel_queued_at(EARTH, queued_count(EARTH) - 1)
}

update_production :: proc(dt: f32) {
	if base_build_planet >= 0 {
		if base_constructing_miners(base_build_planet) >= BASE_CONSTRUCT_MINERS {
			base_build_progress += dt
		}
		if base_build_progress >= BASE_CONSTRUCT_TIME {
			p := base_build_planet
			base_counts[p] += 1
			base_build_planet = -1
			base_build_progress = 0
			resume_constructing_miners(p, .BASE)
			fill_production_lines(p)
		}
	}
	for p in 0..<PLANET_COUNT {
		if refinery_building[p] {
			if refinery_constructing_miners(p) >= REFINERY_CONSTRUCT_MINERS {
				refinery_progress[p] += dt
			}
			if refinery_progress[p] >= REFINERY_BUILD_TIME {
				refinery_progress[p] = 0
				refinery_building[p] = false
				refinery_built[p] = true
				resume_constructing_miners(p, .REFINERY)
			}
		}
	}
	for p in 0..<PLANET_COUNT {
		if orbital_defense_building[p] {
			if orbital_defense_constructing_miners(p) >= ORBITAL_DEFENSE_CONSTRUCT_MINERS {
				orbital_defense_progress[p] += dt
			}
			if orbital_defense_progress[p] >= ORBITAL_DEFENSE_BUILD_TIME {
				orbital_defense_progress[p] = 0
				orbital_defense_building[p] = false
				orbital_defense_level[p] = 1
				orbital_defense_hp[p] = orbital_defense_max_hp(p)
				orbital_defense_elevation[p] = ORBITAL_DEFENSE_IDLE_ELEV
				orbital_defense_ammo[p] = ORBITAL_DEFENSE_START_AMMO
				resume_constructing_miners(p, .ORBITAL_DEFENSE)
			}
		}
		if orbital_defense_ammo_building[p] {
			if orbital_ammo_constructing_miners(p) >= ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS {
				orbital_defense_ammo_progress[p] += dt
			}
			if orbital_defense_ammo_progress[p] >= ORBITAL_DEFENSE_AMMO_BUILD_TIME {
				orbital_defense_ammo_progress[p] = 0
				orbital_defense_ammo_building[p] = false
				orbital_defense_ammo[p] = min(orbital_defense_ammo[p] + 1, ORBITAL_DEFENSE_AMMO_MAX)
				if orbital_defense_ammo_pending_count[p] > 0 {
					orbital_defense_ammo_pending_count[p] -= 1
				}
				resume_constructing_miners(p, .ORBITAL_DEFENSE_AMMO)
				if orbital_defense_ammo_pending_count[p] > 0 && orbital_defense_ammo[p] < ORBITAL_DEFENSE_AMMO_MAX {
					orbital_defense_ammo_building[p] = true
					orbital_defense_ammo_progress[p] = 0
					recruit_build_crew(p, .ORBITAL_DEFENSE_AMMO, ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS)
				}
			}
		}
	}
	for p := 0; p < PLANET_COUNT; p += 1 {
		for b := 0; b < base_counts[p]; b += 1 {
			line := &production[p][b]
			if !line.active { continue }
			build_time := drone_build_time(line.kind)
			line.progress += dt
			if line.progress >= build_time {
				spawn_unit(line.kind, p)
				line.progress = 0
				if pending_count[p] > 0 {
					line.kind = pending[p][0]
					for q := 1; q < pending_count[p]; q += 1 { pending[p][q-1] = pending[p][q] }
					pending_count[p] -= 1
				} else { line.active = false }
			}
		}
	}
	update_autobuilder(dt)
}

fill_production_lines :: proc(p: int) {
	for b := 0; b < base_counts[p]; b += 1 {
		if pending_count[p] == 0 { return }
		line := &production[p][b]
		if line.active { continue }
		line.kind = pending[p][0]
		line.active = true
		line.progress = 0
		for q := 1; q < pending_count[p]; q += 1 { pending[p][q-1] = pending[p][q] }
		pending_count[p] -= 1
	}
}

spawn_unit :: proc(kind: Unit_Type, planet: int) {
	if unit_count >= MAX_UNITS { return }
	angle := f32(unit_count) * 1.8
	pos := planets[planet].position
	if kind == .COMBAT {
		pos.x += math.cos(angle) * (planets[planet].radius + 1.2)
		pos.y += 0.5
		pos.z += math.sin(angle) * (planets[planet].radius + 1.2)
	}
	state := Unit_State.TRANSIT
	target_planet := planet
	if kind == .COMBAT { state = .GUARDING }
	if kind == .MINING { state = .MINING }
	if planet == EARTH && earth_rally != NO_RALLY {
		target_planet = earth_rally
		state = .TRANSIT
	}
	build_target := Build_Target.NONE
	mining_active := false
	if kind == .MINING {
		if state != .TRANSIT {
			target_project := planet_next_needed_build_target(target_planet)
			if target_project != .NONE {
				state = .CONSTRUCTING
				build_target = target_project
			} else if planet_can_mine(target_planet) && active_mining_drones_count(target_planet) < planet_mining_cap(target_planet) {
				state = .MINING
				mining_active = true
			} else {
				state = .IDLE
			}
		}
	}
	affiliation := planet
	if kind == .MINING || target_planet != planet { affiliation = target_planet }
	units[unit_count] = Unit{kind = kind, state = state, position = pos, home_planet = planet, affiliation = affiliation, target_planet = target_planet, orbit_angle = angle, build_target = build_target, mining_active = mining_active}
	unit_count += 1
	planet_unit_cache_dirty = true
}

mined_planets :: proc(seen: ^[PLANET_COUNT]bool) -> int {
	for p in 0..<PLANET_COUNT { seen[p] = false }
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state != .MINING { continue }
		seen[u.target_planet] = true
	}
	count := 0
	for p in 0..<PLANET_COUNT { if seen[p] { count += 1 } }
	return count
}

mined_planet_count :: proc() -> int {
	seen := [PLANET_COUNT]bool{}
	return mined_planets(&seen)
}

mining_rate :: proc(planet: int) -> int {
	if planet >= JUPITER { return 25 }
	return 10
}

planet_mining_cap :: proc(planet: int) -> int {
	switch planet {
	case MERCURY: return 15
	case VENUS: return 35
	case EARTH: return 10
	case MARS: return 50
	case JUPITER: return 100
	case SATURN: return 90
	case URANUS: return 60
	case NEPTUNE: return 60
	}
	return 10
}

active_mining_drones_count :: proc(planet: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state == .CONSTRUCTING { continue }
		is_match := false
		if planet == EARTH {
			is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
		} else {
			is_match = (u.target_planet == planet)
		}
		if is_match && u.mining_active {
			count += 1
		}
	}
	return count
}

is_effective_miner :: proc(index: int) -> bool {
	if units[index].kind != .MINING || units[index].enemy { return false }
	p := units[index].target_planet
	if !planet_can_mine(p) { return false }
	rank := 0
	for j := 0; j < index; j += 1 {
		u := &units[j]
		if u.kind == .MINING && !u.enemy && u.target_planet == p && u.state != .CONSTRUCTING && u.state != .IDLE {
			rank += 1
		}
	}
	return rank < planet_mining_cap(p)
}

planet_cycle_time :: proc(planet: int) -> f32 {
	round_trip := 2.0 * distance(planets[planet].position, planets[EARTH].position)
	travel_time := round_trip / MINING_TRANSIT_SPEED
	return MINING_DURATION + DEPOSIT_DURATION + travel_time
}

planet_mps :: proc(planet: int) -> f32 {
	if !planet_can_mine(planet) { return 0 }
	cap := planet_mining_cap(planet)
	effective := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.target_planet == planet {
			effective += 1
			if effective >= cap { break }
		}
	}
	cycle_time := planet_cycle_time(planet)
	if cycle_time <= 0 { return 0 }
	return f32(effective) * f32(mining_rate(planet)) / cycle_time
}

global_mps :: proc() -> f32 {
	counts: [PLANET_COUNT]int
	caps: [PLANET_COUNT]int
	for p in 0..<PLANET_COUNT { caps[p] = planet_mining_cap(p) }
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.target_planet >= 0 && u.target_planet < PLANET_COUNT {
			p := u.target_planet
			if !planet_can_mine(p) { continue }
			if counts[p] < caps[p] { counts[p] += 1 }
		}
	}
	total: f32 = 0
	for p in 0..<PLANET_COUNT {
		if !planet_can_mine(p) { continue }
		total += f32(counts[p]) * f32(mining_rate(p)) / planet_cycle_time(p)
	}
	return total
}

update_mining_income :: proc(dt: f32) {
	mps := global_mps()
	if mps <= 0 { return }
	mineral_accumulator += mps * dt
	payout := int(mineral_accumulator)
	if payout > 0 {
		minerals += payout
		mineral_accumulator -= f32(payout)
	}
}

update_miner :: proc(u: ^Unit, index: int, dt: f32) {
	target := planets[u.target_planet].position
	earth := planets[EARTH].position
	switch u.state {
	case .TRANSIT:
		travel(u, target, MINING_TRANSIT_SPEED * dt)
		if distance(u.position, target) <= planets[u.target_planet].radius + 1.0 {
			u.position = target
			target_project := planet_next_needed_build_target(u.target_planet)
			if !u.enemy && target_project != .NONE {
				u.state = .CONSTRUCTING
				u.build_target = target_project
				u.progress = 0
				u.mining_active = false
			} else if planet_can_mine(u.target_planet) {
				can_mine := false
				if u.mining_active {
					can_mine = active_mining_drones_count(u.target_planet) <= planet_mining_cap(u.target_planet)
				} else {
					can_mine = active_mining_drones_count(u.target_planet) < planet_mining_cap(u.target_planet)
				}
				if can_mine {
					u.state = .MINING
					u.progress = 0
					u.mining_active = true
				} else {
					u.state = .IDLE
					u.progress = 0
					u.mining_active = false
				}
			} else {
				u.state = .IDLE
				u.progress = 0
				u.mining_active = false
			}
		}
	case .MINING:
		u.progress += dt
		u.position = target
		if !planet_can_mine(u.target_planet) {
			u.state = .IDLE
			u.mining_active = false
			u.progress = 0
		}
	case .RETURNING:
		travel(u, earth, MINING_TRANSIT_SPEED * dt)
		if distance(u.position, earth) <= planets[EARTH].radius + 1.0 {
			u.position = earth
			u.state = .DEPOSITING
			u.progress = 0
		}
	case .DEPOSITING:
		u.progress += dt
		if u.progress >= DEPOSIT_DURATION {
			if is_effective_miner(index) { minerals += mining_rate(u.target_planet) }
			u.progress = 0
			u.state = .TRANSIT
			target_project := planet_next_needed_build_target(EARTH)
			if target_project != .NONE && !u.enemy {
				if u.target_planet == EARTH || u.affiliation == EARTH || !earth_assigned_miner_available() {
					u.state = .CONSTRUCTING
					u.build_target = target_project
					u.target_planet = EARTH
					u.affiliation = EARTH
					u.mining_active = false
				}
			}
		}
	case .IDLE:
		u.position = target
		target_project := planet_next_needed_build_target(u.target_planet)
		if !u.enemy && target_project != .NONE {
			u.state = .CONSTRUCTING
			u.build_target = target_project
			u.progress = 0
			u.mining_active = false
		} else if planet_can_mine(u.target_planet) && active_mining_drones_count(u.target_planet) < planet_mining_cap(u.target_planet) {
			u.state = .MINING
			u.progress = 0
			u.mining_active = true
		} else {
			u.progress += dt
		}
	case .CONSTRUCTING:
		u.position = target
	case .GUARDING:
	}
}

travel :: proc(u: ^Unit, target: rl.Vector3, amount: f32) {
	dx := target.x - u.position.x
	dy := target.y - u.position.y
	dz := target.z - u.position.z
	d := math.sqrt(dx*dx + dy*dy + dz*dz)
	if d <= amount || d == 0 { u.position = target; return }
	u.position.x += dx / d * amount
	u.position.y += dy / d * amount
	u.position.z += dz / d * amount
}

draw_refinery_mineral_beams :: proc() {
	has_any := false
	for p in 0..<PLANET_COUNT {
		if planet_has_refinery_beam(p) { has_any = true; break }
	}
	if !has_any { return }

	earth_pos := planets[EARTH].position
	earth_rad := planets[EARTH].radius

	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	defer {
		rl.EndBlendMode()
		rlgl.EnableDepthMask()
	}

	for p in 0..<PLANET_COUNT {
		if !planet_has_refinery_beam(p) { continue }

		p_pos := planets[p].position
		p_rad := planets[p].radius
		diff := earth_pos - p_pos
		dist := rl.Vector3Length(diff)
		if dist < 0.1 { continue }
		dir := diff * (1.0 / dist)

		start_pos := p_pos + dir * (p_rad + 0.1)
		end_pos := earth_pos - dir * (earth_rad + 0.1)
		beam_len := rl.Vector3Length(end_pos - start_pos)
		if beam_len < 0.1 { continue }

		pulse := 0.85 + 0.15 * math.sin(laser_anim_time * 6.0 + f32(p) * 1.5)
		outer_alpha := u8(clamp(150.0 * pulse, 110, 180))
		mid_alpha := u8(clamp(190.0 * pulse, 150, 220))
		inner_alpha := u8(clamp(220.0 * pulse, 180, 255))
		core_alpha := u8(clamp(255.0 * pulse, 240, 255))

		rl.DrawCylinderEx(start_pos, end_pos, 0.23, 0.23, 8, rl.Color{0, 65, 255, outer_alpha})

		rl.DrawCylinderEx(start_pos, end_pos, 0.14, 0.14, 6, rl.Color{0, 150, 255, mid_alpha})

		rl.DrawCylinderEx(start_pos, end_pos, 0.07, 0.07, 6, rl.Color{70, 210, 255, inner_alpha})

		rl.DrawCylinderEx(start_pos, end_pos, 0.035, 0.035, 4, rl.Color{255, 255, 255, core_alpha})

		rl.DrawLine3D(start_pos, end_pos, rl.Color{255, 255, 255, 255})

		glow_rad: f32 = 0.30 * pulse
		rl.DrawSphereEx(start_pos, glow_rad, 6, 8, rl.Color{0, 90, 255, 160})
		rl.DrawSphereEx(start_pos, glow_rad * 0.45, 4, 6, rl.Color{255, 255, 255, 255})

		rl.DrawSphereEx(end_pos, glow_rad, 6, 8, rl.Color{0, 90, 255, 160})
		rl.DrawSphereEx(end_pos, glow_rad * 0.45, 4, 6, rl.Color{255, 255, 255, 255})

		if planet_can_mine(p) && planet_miner_drone_count(p) > 0 {
			num_packets := clamp(int(beam_len / 25.0), 3, 6)
			packet_speed: f32 = 18.0
			for k in 0..<num_packets {
				travel := math.mod(laser_anim_time * packet_speed + f32(k) * (beam_len / f32(num_packets)), beam_len)
				pkt_pos := start_pos + dir * travel
				trail_pos := pkt_pos - dir * 1.5
				rl.DrawLine3D(trail_pos, pkt_pos, rl.Color{140, 230, 255, 240})
				rl.DrawSphereEx(pkt_pos, 0.16, 4, 6, rl.Color{0, 130, 255, 200})
				rl.DrawSphereEx(pkt_pos, 0.07, 4, 4, rl.Color{255, 255, 255, 255})
			}
		}
	}
}
