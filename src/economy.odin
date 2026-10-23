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
	recruit_build_crew(EARTH, .BASE, BASE_CONSTRUCT_MINERS)
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

start_refinery_construction :: proc(planet: int) {
	if !can_build_refinery(planet) { return }
	minerals -= refinery_cost(planet)
	refinery_building[planet] = true
	refinery_progress[planet] = 0
	construction_seq_counter += 1
	refinery_build_order[planet] = construction_seq_counter
	recruit_build_crew(planet, .REFINERY, REFINERY_CONSTRUCT_MINERS)
}

planet_can_mine :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT { return false }
	return planet_liberated(planet) && refinery_built[planet]
}

planet_has_refinery_beam :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == EARTH { return false }
	return refinery_built[planet]
}

miner_pass_active: bool
miner_pass_active_counts: [PLANET_COUNT]int
miner_pass_next_target: [PLANET_COUNT]Build_Target
miner_pass_next_target_known: [PLANET_COUNT]bool

counts_as_active_miner :: proc(u: ^Unit) -> bool {
	return u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.mining_active
}

add_active_miner :: proc(counts: ^[PLANET_COUNT]int, u: ^Unit, delta: int) {
	if !counts_as_active_miner(u) { return }
	if u.target_planet >= 0 && u.target_planet < PLANET_COUNT && u.target_planet != EARTH {
		counts[u.target_planet] += delta
	}
	if u.target_planet == EARTH || u.affiliation == EARTH {
		counts[EARTH] += delta
	}
}

begin_miner_pass :: proc() {
	miner_pass_active_counts = {}
	for i := 0; i < unit_count; i += 1 {
		add_active_miner(&miner_pass_active_counts, &units[i], 1)
	}
	miner_pass_next_target_known = {}
	miner_pass_active = true
}

end_miner_pass :: proc() {
	miner_pass_active = false
}

note_miner_change :: proc(before, after: Unit) {
	before, after := before, after
	if before.state != after.state || before.mining_active != after.mining_active || before.target_planet != after.target_planet || before.affiliation != after.affiliation {
		add_active_miner(&miner_pass_active_counts, &before, -1)
		add_active_miner(&miner_pass_active_counts, &after, 1)
	}
	if (before.state == .CONSTRUCTING) != (after.state == .CONSTRUCTING) || before.build_target != after.build_target || before.target_planet != after.target_planet {
		miner_pass_next_target_known = {}
	}
}

crew_required :: proc(target: Build_Target) -> int {
	switch target {
	case .BASE: return BASE_CONSTRUCT_MINERS
	case .REFINERY: return REFINERY_CONSTRUCT_MINERS
	case .ORBITAL_DEFENSE: return ORBITAL_DEFENSE_CONSTRUCT_MINERS
	case .ORBITAL_DEFENSE_AMMO: return ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS
	case .NONE: return 0
	}
	return 0
}

build_in_progress :: proc(p: int, target: Build_Target) -> bool {
	switch target {
	case .BASE: return base_build_planet == p
	case .REFINERY: return refinery_building[p]
	case .ORBITAL_DEFENSE: return orbital_defense_building[p]
	case .ORBITAL_DEFENSE_AMMO: return orbital_defense_ammo_building[p]
	case .NONE: return false
	}
	return false
}

crew_size :: proc(p: int, target: Build_Target) -> int {
	adopts_unassigned := target != .ORBITAL_DEFENSE_AMMO
	for other in Build_Target {
		if other != .NONE && other != target && build_in_progress(p, other) { adopts_unassigned = false }
	}
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.state != .CONSTRUCTING || u.target_planet != p { continue }
		if u.build_target == target || (adopts_unassigned && u.build_target == .NONE) { count += 1 }
	}
	return count
}

crew_short :: proc(p: int, target: Build_Target) -> bool {
	return crew_size(p, target) < crew_required(target)
}

miner_assigned_to :: proc(u: ^Unit, planet: int) -> bool {
	if planet == EARTH { return u.target_planet == EARTH || u.affiliation == EARTH }
	return u.target_planet == planet
}

planet_next_needed_build_target :: proc(p: int) -> Build_Target {
	if !miner_pass_active || p < 0 || p >= PLANET_COUNT {
		return compute_next_needed_build_target(p)
	}
	if !miner_pass_next_target_known[p] {
		miner_pass_next_target[p] = compute_next_needed_build_target(p)
		miner_pass_next_target_known[p] = true
	}
	return miner_pass_next_target[p]
}

compute_next_needed_build_target :: proc(p: int) -> Build_Target {
	if p < 0 || p >= PLANET_COUNT { return .NONE }

	primary := p == EARTH ? Build_Target.BASE : Build_Target.REFINERY
	primary_order := p == EARTH ? base_build_order[p] : refinery_build_order[p]
	needs_primary := build_in_progress(p, primary) && crew_short(p, primary)
	needs_defense := orbital_defense_building[p] && crew_short(p, .ORBITAL_DEFENSE)
	needs_ammo := orbital_defense_ammo_building[p] && crew_short(p, .ORBITAL_DEFENSE_AMMO)

	switch {
	case needs_primary && needs_defense:
		return primary_order <= orbital_defense_build_order[p] ? primary : .ORBITAL_DEFENSE
	case needs_primary:
		return primary
	case needs_defense:
		return .ORBITAL_DEFENSE
	case needs_ammo:
		return .ORBITAL_DEFENSE_AMMO
	}
	return .NONE
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
		if u.kind == .MINING && !u.enemy && miner_assigned_to(u, planet) { count += 1 }
	}
	return count
}

recruit_build_crew :: proc(planet: int, target: Build_Target, need: int) {
	crew := crew_size(planet, target)
	for state in ([2]Unit_State{.IDLE, .MINING}) {
		for i := 0; i < unit_count && crew < need; i += 1 {
			u := &units[i]
			if u.kind != .MINING || u.enemy || u.state != state || !miner_assigned_to(u, planet) { continue }
			u.state = .CONSTRUCTING
			u.build_target = target
			u.progress = 0
			u.target_planet = planet
			u.affiliation = planet
			u.mining_active = false
			crew += 1
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

base_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}
}

miner_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y()), BUILD_BTN_W, BUILD_BTN_H}
}

combat_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(production_orders_y()), BUILD_BTN_W, BUILD_BTN_H}
}

queue_5_miner_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

queue_5_combat_button_rect :: proc(panel_x: f32) -> rl.Rectangle {
	return rl.Rectangle{panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, f32(production_orders_y() + UPGRADE_DY), BUILD_BTN_W, UPGRADE_H}
}

manual_button_rect :: proc() -> rl.Rectangle {
	dock_y := f32(ui_screen_h() - BOTTOM_DOCK_H - 12)
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

remove_pending :: proc(planet, index: int) -> Unit_Type {
	kind := pending[planet][index]
	copy(pending[planet][index:pending_count[planet] - 1], pending[planet][index + 1:pending_count[planet]])
	pending_count[planet] -= 1
	return kind
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
			line.kind = remove_pending(planet, 0)
			line.active = true
		}
		return true
	}
	if i < pending_count[planet] {
		minerals += unit_cost(remove_pending(planet, i))
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
		if !crew_short(base_build_planet, .BASE) {
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
			if !crew_short(p, .REFINERY) {
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
			if !crew_short(p, .ORBITAL_DEFENSE) {
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
			if !crew_short(p, .ORBITAL_DEFENSE_AMMO) {
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
					line.kind = remove_pending(p, 0)
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
		line.kind = remove_pending(p, 0)
		line.active = true
		line.progress = 0
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
		to := sector_pos(earth_rally) - planets[planet].position
		slot := rally_spawn_counter % RALLY_SPAWN_SLOTS
		rally_spawn_counter += 1
		angle = math.atan2(to.z, to.x) + (f32(slot) - f32(RALLY_SPAWN_SLOTS - 1) * 0.5) * RALLY_SPAWN_SPACING
		pos = orbit_pos(planets[planet].position, planets[planet].radius, angle)
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
	units_changed()
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
	if miner_pass_active && planet >= 0 && planet < PLANET_COUNT {
		return miner_pass_active_counts[planet]
	}
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if counts_as_active_miner(u) && miner_assigned_to(u, planet) { count += 1 }
	}
	return count
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

update_miner :: proc(u: ^Unit, dt: f32) {
	target := planets[u.target_planet].position
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
				active := active_mining_drones_count(u.target_planet)
				cap := planet_mining_cap(u.target_planet)
				if u.mining_active ? active <= cap : active < cap {
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
		draw_energy_beam(start_pos, end_pos, 1, clamp(pulse, 0.8, 1), MINERAL_BEAM_PALETTE)
		draw_beam_node(start_pos, 0.30 * pulse, 1, MINERAL_BEAM_PALETTE)
		draw_beam_node(end_pos, 0.30 * pulse, 1, MINERAL_BEAM_PALETTE)

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
