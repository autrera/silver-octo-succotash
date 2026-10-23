package main

import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"


orbital_defense_key_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.O)
}

trigger_selected_orbital_defense :: proc() -> bool {
	if selected_planet >= 0 && selected_planet < PLANET_COUNT && selected_planet != ENEMY_HOME {
		if can_build_orbital_defense(selected_planet) {
			start_orbital_defense_construction(selected_planet)
			return true
		}
		if can_build_orbital_ammo(selected_planet) {
			start_orbital_ammo_construction(selected_planet)
			return true
		}
	}
	return false
}

orbital_defense_max_hp :: proc(planet: int) -> int {
	if planet < 0 || planet >= SECTOR_COUNT { return 0 }
	return orbital_defense_level[planet] * ORBITAL_DEFENSE_HP_PER_LEVEL
}

orbital_defense_pos :: proc(planet: int) -> rl.Vector3 {
	if planet == ENEMY_HOME {
		return ENEMY_HQ_POSITION + {0.3, 1.95, 0}
	}
	if planet < 0 || planet >= PLANET_COUNT { return {} }
	p := planets[planet]
	return rl.Vector3{
		p.position.x,
		p.position.y + p.radius,
		p.position.z,
	}
}

closest_approaching_enemy :: proc(planet: int) -> (^Unit, bool) {
	if planet < 0 || planet >= SECTOR_COUNT { return nil, false }
	target_pos := sector_pos(planet)
	max_range := sector_radius(planet) + ORBITAL_DEFENSE_TARGET_RANGE
	closest_idx := -1
	closest_dist: f32 = 1e9

	for i in 0..<unit_count {
		u := &units[i]
		is_target := (planet == ENEMY_HOME) ? (!u.enemy) : (u.enemy)
		if !is_target || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != planet { continue }
		d := distance(u.position, target_pos)
		if d <= max_range && d < closest_dist {
			closest_dist = d
			closest_idx = i
		}
	}

	if closest_idx >= 0 {
		return &units[closest_idx], true
	}
	return nil, false
}

orbital_defense_aim_toward :: proc(planet_idx: int, target: rl.Vector3) -> (azimuth: f32, elev: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return 0, 0 }
	pivot: rl.Vector3
	if planet_idx == ENEMY_HOME {
		pivot = ENEMY_HQ_POSITION + HQ_BATTERY_PIVOT
	} else {
		pivot = orbital_defense_pole(planet_idx) + rl.Vector3{0, ORBITAL_DEFENSE_PIVOT.y * orbital_defense_scale(planet_idx), 0}
	}
	diff := target - pivot
	horiz_d := math.sqrt(diff.x * diff.x + diff.z * diff.z)
	azimuth = math.atan2(diff.z, diff.x)
	raw_elev := horiz_d > 0.001 ? math.atan2(diff.y, horiz_d) : (math.PI * 0.25)
	elev = clamp(raw_elev, 8.0 * rl.DEG2RAD, 85.0 * rl.DEG2RAD)
	return
}

orbital_defense_muzzle_pos_toward :: proc(planet_idx: int, target: rl.Vector3) -> rl.Vector3 {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return {} }
	azimuth, elev := orbital_defense_aim_toward(planet_idx, target)
	fwd, _, dir, _ := orbital_defense_axes(azimuth, elev)
	if planet_idx == ENEMY_HOME {
		return ENEMY_HQ_POSITION + HQ_BATTERY_PIVOT + dir * HQ_MUZZLE_REACH
	}
	return orbital_defense_pivot(planet_idx, fwd) + dir * (ORBITAL_DEFENSE_MUZZLE_REACH * orbital_defense_scale(planet_idx))
}

shortest_angle_diff :: proc(target, current: f32) -> f32 {
	diff := target - current
	for diff < -math.PI { diff += 2 * math.PI }
	for diff >  math.PI { diff -= 2 * math.PI }
	return diff
}

slew_toward :: proc(current, target, max_step: f32) -> f32 {
	diff := target - current
	if abs(diff) <= max_step { return target }
	return current + math.sign(diff) * max_step
}

advance_orbital_defense_aim :: proc(planet_idx: int, dt: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return }
	if orbital_defense_level[planet_idx] <= 0 { return }

	max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
	if planet_idx < PLANET_COUNT && orbital_defense_building[planet_idx] {
		orbital_defense_elevation[planet_idx] = slew_toward(orbital_defense_elevation[planet_idx], ORBITAL_DEFENSE_PARK_ELEV, max_el)
		return
	}

	enemy, has_enemy := closest_approaching_enemy(planet_idx)
	if has_enemy {
		target_az, target_el := orbital_defense_aim_toward(planet_idx, enemy.position)
		az_diff := shortest_angle_diff(target_az, orbital_defense_angle[planet_idx])
		max_az := ORBITAL_DEFENSE_TRACK_SPEED * dt
		if abs(az_diff) <= max_az {
			orbital_defense_angle[planet_idx] = target_az
		} else {
			orbital_defense_angle[planet_idx] += math.sign(az_diff) * max_az
		}
		orbital_defense_elevation[planet_idx] = slew_toward(orbital_defense_elevation[planet_idx], target_el, max_el)
	} else {
		orbital_defense_angle[planet_idx] += ORBITAL_DEFENSE_SCAN_SPEED * dt
		orbital_defense_elevation[planet_idx] = slew_toward(orbital_defense_elevation[planet_idx], ORBITAL_DEFENSE_IDLE_ELEV, max_el)
	}

	for orbital_defense_angle[planet_idx] < -math.PI {
		orbital_defense_angle[planet_idx] += 2 * math.PI
	}
	for orbital_defense_angle[planet_idx] >= math.PI {
		orbital_defense_angle[planet_idx] -= 2 * math.PI
	}
}

orbital_defense_aim :: proc(planet_idx: int) -> (azimuth: f32, elev: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return 0, 0 }
	if planet_idx < PLANET_COUNT && orbital_defense_building[planet_idx] {
		return orbital_defense_angle[planet_idx], ORBITAL_DEFENSE_PARK_ELEV
	}
	if planet_idx == ENEMY_HOME && (enemy_hq_destroyed() || orbital_defense_hp[ENEMY_HOME] <= 0) {
		return orbital_defense_angle[planet_idx], -0.32
	}
	return orbital_defense_angle[planet_idx], orbital_defense_elevation[planet_idx]
}

spawn_orbital_defense_blast :: proc(planet: int, from, to: rl.Vector3, delay: f32 = 0) {
	oldest_idx := 0
	oldest_elapsed: f32 = -1.0
	for i in 0..<MAX_ORBITAL_BLASTS {
		if !orbital_defense_blasts[i].active {
			oldest_idx = i
			break
		}
		if orbital_defense_blasts[i].elapsed > oldest_elapsed {
			oldest_elapsed = orbital_defense_blasts[i].elapsed
			oldest_idx = i
		}
	}
	orbital_defense_blasts[oldest_idx] = Orbital_Defense_Blast{
		active = true,
		planet = planet,
		from = from,
		to = to,
		delay = delay,
		duration = ORBITAL_BEAM_DURATION,
	}
}

update_orbital_defense_blasts :: proc(dt: f32) {
	for i in 0..<MAX_ORBITAL_BLASTS {
		b := &orbital_defense_blasts[i]
		if !b.active { continue }
		b.elapsed += dt
		if b.elapsed >= b.delay + b.duration { b.active = false }
	}
}

draw_orbital_defense_blasts :: proc() {
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	defer {
		rl.EndBlendMode()
		rlgl.EnableDepthMask()
	}
	for i in 0..<MAX_ORBITAL_BLASTS {
		b := &orbital_defense_blasts[i]
		if !b.active || b.elapsed < b.delay { continue }
		if distance(b.from, b.to) < 0.05 { continue }
		if !has_vision(b.planet) && b.planet != ENEMY_HOME { continue }

		t := clamp((b.elapsed - b.delay) / b.duration, 0, 1)
		reach := clamp(t / ORBITAL_BEAM_EXTEND, 0, 1)
		fade := t < ORBITAL_BEAM_EXTEND ? 1 : 1 - (t - ORBITAL_BEAM_EXTEND) / (1 - ORBITAL_BEAM_EXTEND)
		palette := b.planet == ENEMY_HOME ? HQ_BEAM_PALETTE : MINERAL_BEAM_PALETTE
		head := b.from + (b.to - b.from) * reach

		draw_energy_beam(b.from, head, 0.45 + 0.75 * fade, fade, palette)
		draw_beam_node(b.from, 0.34 * (0.6 + 0.4 * fade), fade, palette)
		if reach < 1 {
			draw_beam_node(head, 0.26, 1, palette)
			continue
		}
		hit := (t - ORBITAL_BEAM_EXTEND) / (1 - ORBITAL_BEAM_EXTEND)
		draw_beam_node(b.to, 0.3 + 0.55 * math.sqrt(hit), fade, palette)
	}
}

can_build_orbital_defense :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == ENEMY_HOME { return false }
	if !planet_liberated(planet) { return false }
	if orbital_defense_building[planet] { return false }
	if orbital_defense_level[planet] > 0 { return false }
	if minerals < ORBITAL_DEFENSE_COST { return false }
	if planet == EARTH {
		return player_miners_count(EARTH) >= ORBITAL_DEFENSE_CONSTRUCT_MINERS
	}
	return true
}

can_build_orbital_ammo :: proc(planet: int) -> bool {
	if planet < 0 || planet >= PLANET_COUNT || planet == ENEMY_HOME { return false }
	if orbital_defense_level[planet] <= 0 { return false }
	if orbital_defense_building[planet] { return false }
	if orbital_defense_ammo[planet] + orbital_defense_ammo_pending_count[planet] >= ORBITAL_DEFENSE_AMMO_MAX { return false }
	if minerals < ORBITAL_DEFENSE_AMMO_COST { return false }
	return player_miners_at_planet(planet) >= ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS
}

start_orbital_ammo_construction :: proc(planet: int) {
	if !can_build_orbital_ammo(planet) { return }
	minerals -= ORBITAL_DEFENSE_AMMO_COST
	orbital_defense_ammo_pending_count[planet] += 1
	if !orbital_defense_ammo_building[planet] {
		orbital_defense_ammo_building[planet] = true
		orbital_defense_ammo_progress[planet] = 0
		recruit_build_crew(planet, .ORBITAL_DEFENSE_AMMO, ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS)
	}
}

start_orbital_defense_construction :: proc(planet: int) {
	if !can_build_orbital_defense(planet) { return }
	minerals -= ORBITAL_DEFENSE_COST
	orbital_defense_building[planet] = true
	orbital_defense_progress[planet] = 0
	orbital_defense_elevation[planet] = ORBITAL_DEFENSE_PARK_ELEV
	construction_seq_counter += 1
	orbital_defense_build_order[planet] = construction_seq_counter
	recruit_build_crew(planet, .ORBITAL_DEFENSE, ORBITAL_DEFENSE_CONSTRUCT_MINERS)
}

destroy_orbital_defense :: proc(planet: int) {
	orbital_defense_level[planet] = 0
	orbital_defense_hp[planet] = 0
	orbital_defense_building[planet] = false
	orbital_defense_progress[planet] = 0
	orbital_defense_ammo[planet] = 0
	orbital_defense_ammo_building[planet] = false
	orbital_defense_ammo_progress[planet] = 0
	orbital_defense_angle[planet] = 0
	orbital_defense_elevation[planet] = (planet == ENEMY_HOME) ? -0.32 : ORBITAL_DEFENSE_IDLE_ELEV
	orbital_defense_wave_kills[planet] = 0
	orbital_defense_reset_timer[planet] = 0
	for i := unit_count - 1; i >= 0; i -= 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.target_planet == planet && u.state != .TRANSIT {
			kill_unit_at(i)
		}
	}
	if planet != EARTH && planet < PLANET_COUNT {
		refinery_built[planet] = false
		refinery_building[planet] = false
		refinery_progress[planet] = 0
	}
}

earth_orbital_defense_y :: proc() -> f32 {
	if !base_button_visible() {
		return SECTION_TOP
	}
	y: f32 = SECTION_TOP + BASE_BTN_H + 16
	return y
}

earth_orbital_defense_bottom_y :: proc() -> f32 {
	return earth_orbital_defense_y() + orbital_defense_section_height(EARTH)
}

orbital_defense_section_height :: proc(p: int) -> f32 {
	if p >= 0 && p < SECTOR_COUNT && orbital_defense_level[p] > 0 && !orbital_defense_building[p] {
		return QUEUE_SLOT_H
	}
	return BASE_BTN_H
}

outpost_orbital_defense_y :: proc(planet: int) -> f32 {
	return ORBITAL_DEFENSE_BTN_Y
}

outpost_orbital_defense_bottom_y :: proc(planet: int) -> f32 {
	return outpost_orbital_defense_y(planet) + orbital_defense_section_height(planet)
}

outpost_liberated_roster_y :: proc(planet: int) -> int {
	return int(outpost_orbital_defense_bottom_y(planet)) + SECTION_BELOW_DY
}

orbital_defense_button_rect :: proc(panel_x: f32, planet: int) -> rl.Rectangle {
	if planet == EARTH {
		return rl.Rectangle{panel_x + PANEL_PAD_X, earth_orbital_defense_y(), PANEL_CONTENT_W, BASE_BTN_H}
	} else {
		return rl.Rectangle{panel_x + PANEL_PAD_X, outpost_orbital_defense_y(planet), PANEL_CONTENT_W, BASE_BTN_H}
	}
}

orbital_defense_base_y :: proc(planet: int) -> f32 {
	if planet == EARTH { return earth_orbital_defense_y() }
	return outpost_orbital_defense_y(planet)
}

orbital_ammo_slot_rect :: proc(panel_x: f32, planet: int, slot: int) -> rl.Rectangle {
	base_x := panel_x + PANEL_PAD_X
	base_y := orbital_defense_base_y(planet)
	slot_w: f32 = 25.0
	slot_gap: f32 = 4.0
	pitch := slot_w + slot_gap
	margin: f32 = 2.0
	x := base_x + margin + f32(slot) * pitch
	return rl.Rectangle{x, base_y, slot_w, QUEUE_SLOT_H}
}

draw_orbital_ammo_slot :: proc(rect: rl.Rectangle, filled: bool, progress: f32 = -1) {
	charging := progress >= 0 && !filled
	outline := SCIFI_DIM
	charge := SCIFI_AMBER
	level: f32 = 0
	if filled {
		outline = SCIFI_AMBER
		level = 1
	} else if charging {
		outline = SCIFI_MINT
		charge = SCIFI_MINT
		level = clamp(progress, 0, 1)
	}
	draw_battery_cell(rect, level, outline, charge)
}

draw_battery_cell :: proc(rect: rl.Rectangle, level: f32, outline, charge: rl.Color) {
	body := rl.Rectangle{rect.x + 4, rect.y + 3, rect.width - 8, rect.height - 3}
	nub := rl.Rectangle{rect.x + rect.width * 0.5 - 3, rect.y, 6, 3}
	rl.DrawRectangleRec(body, SCIFI_PANEL_SOLID)

	inner := rl.Rectangle{body.x + 2, body.y + 2, body.width - 4, body.height - 4}
	if level > 0 {
		fill_h := inner.height * level
		fill_alpha := u8(f32(charge.a) * (level >= 1 ? 0.35 : 0.27))
		rl.DrawRectangleRec(rl.Rectangle{inner.x, inner.y + inner.height - fill_h, inner.width, fill_h}, rl.Color{charge.r, charge.g, charge.b, fill_alpha})
	}

	CELL_LINES :: 3
	for i in 0..<CELL_LINES {
		ly := inner.y + inner.height * (f32(i) + 0.5) / CELL_LINES
		lit := level >= 1 - (f32(i) + 0.5) / CELL_LINES
		line_col := rl.Color{SCIFI_STEEL.r, SCIFI_STEEL.g, SCIFI_STEEL.b, u8(f32(outline.a) * 0.24)}
		if lit { line_col = charge }
		rl.DrawLineEx({inner.x + 1, ly}, {inner.x + inner.width - 1, ly}, 1.5, line_col)
	}

	rl.DrawRectangleLinesEx(body, 1, outline)
	rl.DrawRectangleRec(nub, outline)
}

draw_orbital_defense_inspector_section :: proc(x: f32, btn: rl.Rectangle, p: int) {
	if orbital_defense_building[p] {
		progress := orbital_defense_progress[p] / ORBITAL_DEFENSE_BUILD_TIME
		detail := crew_short(p, .ORBITAL_DEFENSE) ? fmt.ctprintf("CREW %d/%d - MINERS AUTO-JOIN", crew_size(p, .ORBITAL_DEFENSE), ORBITAL_DEFENSE_CONSTRUCT_MINERS) : fmt.ctprintf("ONLINE IN %.1fs", ORBITAL_DEFENSE_BUILD_TIME - orbital_defense_progress[p])
		draw_status_button(btn, "BUILDING ORBITAL DEFENSE", detail, fmt.ctprintf("%d%%", int(progress * 100)), progress)
	} else if orbital_defense_level[p] == 0 {
		draw_button(btn, "BUILD ORBITAL DEFENSE", fmt.ctprintf("COST %d - CREW %d", ORBITAL_DEFENSE_COST, ORBITAL_DEFENSE_CONSTRUCT_MINERS), "O", can_build_orbital_defense(p))
	} else {
		for slot in 0..<ORBITAL_DEFENSE_AMMO_MAX {
			completed := slot < orbital_defense_ammo[p]
			queued := slot >= orbital_defense_ammo[p] && slot < orbital_defense_ammo[p] + orbital_defense_ammo_pending_count[p]
			active := orbital_defense_ammo_building[p] && slot == orbital_defense_ammo[p]
			progress: f32 = -1
			if active {
				progress = orbital_defense_ammo_progress[p] / ORBITAL_DEFENSE_AMMO_BUILD_TIME
			} else if queued {
				progress = 0
			}
			draw_orbital_ammo_slot(orbital_ammo_slot_rect(x, p, slot), completed, progress)
		}
	}
}

update_orbital_defenses :: proc(dt: f32) {
	update_orbital_defense_blasts(dt)
	update_drone_wrecks(dt)
	for p in 0..<SECTOR_COUNT {
		if orbital_defense_level[p] > 0 {
			advance_orbital_defense_aim(p, dt)
		}
		if orbital_defense_fire_timer[p] > 0 {
			orbital_defense_fire_timer[p] = max(orbital_defense_fire_timer[p] - dt, 0)
		}
		if orbital_defense_reset_timer[p] > 0 {
			orbital_defense_reset_timer[p] = max(orbital_defense_reset_timer[p] - dt, 0)
			if orbital_defense_reset_timer[p] == 0 {
				orbital_defense_wave_kills[p] = 0
			}
		}

		is_building := (p < PLANET_COUNT) && orbital_defense_building[p]
		inbound_count := transit_fighters_at(p, p < PLANET_COUNT)
		if inbound_count == 0 {
			if orbital_defense_ammo_pending_kills[p] > 0 && orbital_defense_ammo[p] > 0 {
				orbital_defense_ammo[p] -= 1
			}
			orbital_defense_ammo_pending_kills[p] = 0
			orbital_defense_wave_kills[p] = 0
			orbital_defense_reset_timer[p] = 0
		} else if p == ENEMY_HOME {
			if orbital_defense_level[p] > 0 {
				max_kills := orbital_defense_level[p] * ORBITAL_DEFENSE_KILLS_PER_LEVEL
				if orbital_defense_wave_kills[p] < max_kills {
					target_pos := sector_pos(p)
					r := sector_radius(p)
					engage_dist := r + 3.8
					arrival_dist := r + 1.65

					for i := unit_count - 1; i >= 0; i -= 1 {
						u := &units[i]
						if u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
						d := distance(u.position, target_pos)
						if d <= engage_dist {
							if orbital_defense_fire_timer[p] <= 0 || d <= arrival_dist {
								orbital_defense_wave_kills[p] += 1
								orbital_defense_reset_timer[p] = ORBITAL_DEFENSE_WAVE_RESET_DELAY
								orbital_defense_fire_timer[p] = 0.06
								muzzle_pos := orbital_defense_muzzle_pos_toward(p, u.position)
								spawn_orbital_defense_blast(p, muzzle_pos, u.position)
								kill_unit_at(i)
								if orbital_defense_wave_kills[p] >= max_kills { break }
							}
						}
					}
				}
			}
		} else if orbital_defense_level[p] > 0 && !is_building {
			target_pos := sector_pos(p)
			r := sector_radius(p)
			engage_dist := r + 3.8
			remaining := inbound_count
			for orbital_defense_ammo[p] > 0 && remaining > 0 {
				in_range := 0
				for i in 0..<unit_count {
					u := &units[i]
					if !u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
					if distance(u.position, target_pos) <= engage_dist { in_range += 1 }
				}
				volley := min(ORBITAL_DEFENSE_KILLS_PER_SHOT, remaining)
				if in_range < volley { break }
				kills := 0
				shot_fired := false
				shot_delay: f32 = 0
				for i := unit_count - 1; i >= 0; i -= 1 {
					u := &units[i]
					if !u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
					d := distance(u.position, target_pos)
					if d <= engage_dist {
						hit_pos := u.position + rl.Vector3Normalize(target_pos - u.position) * (COMBAT_TRANSIT_SPEED * shot_delay)
						spawn_orbital_defense_blast(p, orbital_defense_muzzle_pos_toward(p, hit_pos), hit_pos, shot_delay)
						kill_unit_at(i, shot_delay)
						shot_delay += ORBITAL_BEAM_STAGGER
						kills += 1
						orbital_defense_wave_kills[p] += 1
						orbital_defense_ammo_pending_kills[p] += 1
						shot_fired = true
						if kills >= volley { break }
					}
				}
				if !shot_fired { break }
				remaining -= kills
				if orbital_defense_ammo_pending_kills[p] >= ORBITAL_DEFENSE_KILLS_PER_SHOT {
					orbital_defense_ammo[p] -= 1
					orbital_defense_ammo_pending_kills[p] -= ORBITAL_DEFENSE_KILLS_PER_SHOT
				}
				orbital_defense_reset_timer[p] = ORBITAL_DEFENSE_WAVE_RESET_DELAY
			}
		}
	}
}

update_enemy_waves :: proc(dt: f32) {
	update_combat_vision(dt)
	update_orbital_defenses(dt)
	update_minor_wave(dt)
	update_wave(dt)
	for p in 0..<SECTOR_COUNT { update_planet_combat(dt, p) }
}

update_minor_wave :: proc(dt: f32) {
	minor_wave_timer += dt
	if minor_wave_timer >= MINOR_WAVE_INTERVAL {
		launch_minor_wave()
	}
}

collect_minor_wave_attacks :: proc() -> (sources: [PLANET_COUNT]int, targets: [PLANET_COUNT]int, count: int) {
	Pair :: struct {
		u: int,
		l: int,
		d: f32,
	}

	pairs: [PLANET_COUNT * PLANET_COUNT]Pair
	pair_count := 0

	for u in 0..<PLANET_COUNT {
		if planet_liberated(u) { continue }
		for l in 0..<PLANET_COUNT {
			if !planet_liberated(l) { continue }
			d := distance(planets[u].position, planets[l].position)
			pairs[pair_count] = Pair{u = u, l = l, d = d}
			pair_count += 1
		}
	}

	for i in 1..<pair_count {
		key := pairs[i]
		j := i - 1
		for j >= 0 && pairs[j].d > key.d {
			pairs[j + 1] = pairs[j]
			j -= 1
		}
		pairs[j + 1] = key
	}

	used_u: [PLANET_COUNT]bool
	used_l: [PLANET_COUNT]bool

	for i in 0..<pair_count {
		p := pairs[i]
		if !used_u[p.u] && !used_l[p.l] {
			used_u[p.u] = true
			used_l[p.l] = true
			sources[count] = p.u
			targets[count] = p.l
			count += 1
		}
	}

	return
}

launch_minor_wave :: proc() {
	minor_wave_timer = 0
	sources, targets, count := collect_minor_wave_attacks()
	for i in 0..<count {
		spawn_minor_wave(sources[i], targets[i], MINOR_WAVE_SIZE)
	}
}

planet_is_minor_wave_target :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	_, targets, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if targets[i] == p { return true }
	}
	return false
}

planet_is_minor_wave_source :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	sources, _, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if sources[i] == p { return true }
	}
	return false
}

planet_attack_source_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	return planet_is_minor_wave_source(p)
}

planet_under_attack_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if planet_is_minor_wave_target(p) { return true }
	return transit_fighters_at(p, true) > 0
}

spawn_minor_wave :: proc(source, target: int, count: int = MINOR_WAVE_SIZE) {
	spawn_count := min(count, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	src_pos := planets[source].position
	src_rad := planets[source].radius
	target_pos := sector_pos(target)

	to_target := target_pos - src_pos
	dist := rl.Vector3Length(to_target)
	dir := dist > 0.001 ? to_target / dist : rl.Vector3{1, 0, 0}

	world_up := rl.Vector3{0, 1, 0}
	right := rl.Vector3CrossProduct(dir, world_up)
	if rl.Vector3Length(right) < 0.01 {
		right = rl.Vector3CrossProduct(dir, {0, 0, 1})
	}
	right = rl.Vector3Normalize(right)
	up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, dir))

	launch_dist := dist - (src_rad + 1.5)
	launch_origin := src_pos + dir * (src_rad + 1.5)

	formation_offsets := [5][2]f32{
		{ 0.0,  0.0},
		{-1.3,  0.4},
		{ 1.3,  0.4},
		{-2.6, -0.3},
		{ 2.6, -0.3},
	}

	for i in 0..<spawn_count {
		angle := f32(i) * (2 * math.PI / f32(spawn_count))
		ox := formation_offsets[i % 5][0]
		oy := formation_offsets[i % 5][1]
		if i >= 5 {
			ox += f32((i / 5) * 2) * (i % 2 == 0 ? 1.0 : -1.0)
		}
		raw_pos := launch_origin + right * ox + up * oy
		pos := target_pos - rl.Vector3Normalize(target_pos - raw_pos) * launch_dist
		units[unit_count] = Unit{
			kind = .COMBAT,
			state = .TRANSIT,
			position = pos,
			home_planet = source,
			affiliation = target,
			target_planet = target,
			enemy = true,
			orbit_angle = angle,
		}
		unit_count += 1
	}
}

update_wave :: proc(dt: f32) {
	if liberated_planet_count() >= WAVE_MIN_LIBERATED_PLANETS {
		enemy_wave_timer += dt
		interval := f32(WAVE_FIRST_DELAY)
		if wave_started { interval = f32(WAVE_INTERVAL) }
		if enemy_wave_timer >= interval {
			launch_wave()
		}
	}
}

launch_wave :: proc() {
	size := attack_wave_size()
	enemy_wave_timer = 0
	wave_started = true
	if size <= 0 || enemy_hq_destroyed() { return }
	_, defenders := planet_combatants(ENEMY_HOME)
	if player_attacking_hq() && defenders < ENEMY_HQ_GARRISON {
		spawn_hq_defenders(size)
		return
	}
	spawn_n_enemies_to(closest_liberated_planet_to_hq(), size)
}

combat_tick_for :: proc(p: int) -> f32 {
	if p == ENEMY_HOME {
		return HQ_COMBAT_TICK
	}
	return COMBAT_TICK
}

update_planet_combat :: proc(dt: f32, p: int) {
	tick := combat_tick_for(p)
	players, enemies := planet_combatants(p)
	if players > 0 && enemies > 0 {
		combat_timer[p] += dt
		for combat_timer[p] >= tick {
			combat_timer[p] -= tick
			if !kill_fighter(p, false) { break }
			rem_players, _ := planet_combatants(p)
			if rem_players == 0 {
				combat_vision_timer[p] = COMBAT_VISION_LINGER
			}
			if !kill_fighter(p, true) { break }
		}
	} else if enemies > 0 {
		combat_timer[p] = 0
		if p < PLANET_COUNT && orbital_defense_level[p] > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				orbital_defense_hp[p] -= enemies
				if orbital_defense_hp[p] <= 0 {
					destroy_orbital_defense(p)
					break
				}
			}
		} else {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				if !kill_player_miner(p) { break }
			}
			if p < PLANET_COUNT && p != EARTH && !player_miners_at(p) {
				refinery_built[p] = false
				refinery_building[p] = false
				refinery_progress[p] = 0
			}
			if p == EARTH && !player_miners_at(p) {
				base_timer[p] += dt
				for base_timer[p] >= BASE_SIEGE_TIME {
					base_timer[p] -= BASE_SIEGE_TIME
					destroy_player_base(p)
					if base_counts[p] == 0 { break }
				}
			} else {
				base_timer[p] = 0
			}
		}
	} else if players > 0 {
		combat_timer[p] = 0
		if enemy_miner_count(p) > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				if !kill_enemy_miner(p) { break }
			}
		} else if p == ENEMY_HOME && orbital_defense_level[p] > 0 {
			miner_timer[p] += dt
			for miner_timer[p] >= tick {
				miner_timer[p] -= tick
				orbital_defense_hp[p] -= players
				if orbital_defense_hp[p] <= 0 {
					destroy_orbital_defense(p)
					break
				}
			}
		} else if enemy_base_hp[p] > 0 {
			base_timer[p] += dt
			for base_timer[p] >= tick {
				base_timer[p] -= tick
				enemy_base_hp[p] = max(enemy_base_hp[p] - players, 0)
				if enemy_base_hp[p] == 0 { break }
			}
		} else {
			miner_timer[p] = 0
			base_timer[p] = 0
		}
	} else {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
	}
}

attack_wave_size :: proc() -> int {
	return (liberated_planet_count() - 1) * WAVE_FIGHTERS_PER_LIBERATED
}

liberated_planet_count :: proc() -> int {
	count := 0
	for p in 0..<PLANET_COUNT { if planet_liberated(p) { count += 1 } }
	return count
}

closest_liberated_planet_to_hq :: proc() -> int {
	best := EARTH
	best_d := distance(planets[EARTH].position, ENEMY_HQ_POSITION)
	for p in 0..<PLANET_COUNT {
		if !planet_liberated(p) { continue }
		d := distance(planets[p].position, ENEMY_HQ_POSITION)
		if d < best_d { best_d = d; best = p }
	}
	return best
}

player_attacking_hq :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.enemy { continue }
		if u.affiliation == ENEMY_HOME { return true }
		if u.state == .TRANSIT && u.target_planet == ENEMY_HOME { return true }
	}
	return false
}

spawn_hq_defenders :: proc(count: int) {
	if enemy_hq_destroyed() { return }
	spawn_count := min(count, MAX_UNITS - unit_count)
	for i in 0..<spawn_count {
		angle := f32(unit_count + i) * 1.26
		units[unit_count] = Unit{
			kind = .COMBAT, state = .GUARDING, position = orbit_pos(ENEMY_HQ_POSITION, ENEMY_HQ_RADIUS, angle),
			home_planet = NEPTUNE, affiliation = ENEMY_HOME, target_planet = ENEMY_HOME,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

spawn_n_enemies_to :: proc(target: int, count: int) {
	if enemy_hq_destroyed() { return }
	spawn_count := min(count, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	target_pos := sector_pos(target)
	to_target := target_pos - ENEMY_HQ_POSITION
	to_len := rl.Vector3Length(to_target)
	dir := to_len > 0.001 ? to_target / to_len : rl.Vector3{-1, 0, 0}
	right := rl.Vector3CrossProduct(dir, {0, 1, 0})
	if rl.Vector3Length(right) < 0.01 { right = rl.Vector3{0, 0, 1} }
	right = rl.Vector3Normalize(right)
	up := rl.Vector3Normalize(rl.Vector3CrossProduct(right, dir))
	groups := (spawn_count + 9) / 10
	origin := ENEMY_HQ_POSITION + dir * (ENEMY_HQ_RADIUS + 1.5)

	for i in 0..<spawn_count {
		angle := f32(i) * (2 * math.PI / f32(spawn_count))
		group := i % groups
		member := i / groups
		col := f32(group % 5) - 2
		row := f32(group / 5)
		member_angle := f32(member) * 2.4
		member_radius := 0.12 * f32(member)
		pos := origin +
			right * (col * 1.3 + math.cos(member_angle) * member_radius) +
			up * (abs(col) * 0.2 + math.sin(member_angle) * member_radius) -
			dir * (row * 1.6 + abs(col) * 0.3)
		units[unit_count] = Unit{
			kind = .COMBAT, state = .TRANSIT, position = pos,
			home_planet = NEPTUNE, affiliation = target, target_planet = target,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

planet_liberated :: proc(p: int) -> bool {
	return enemy_base_hp[p] <= 0
}

planet_combatants :: proc(p: int) -> (players, enemies: int) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.state != .GUARDING || u.affiliation != p { continue }
		if u.enemy { enemies += 1 } else { players += 1 }
	}
	return
}

kill_unit_at :: proc(index: int, delay: f32 = 0) {
	if units[index].enemy { spawn_drone_wreck(units[index], delay) }
	remove_unit_at(index)
}

spawn_drone_wreck :: proc(u: Unit, delay: f32) {
	sector := u.affiliation
	heading, velocity: rl.Vector3
	if u.state == .TRANSIT {
		sector = u.target_planet
		if sector < 0 || sector >= SECTOR_COUNT { return }
		heading = sector_pos(sector) - u.position
		speed: f32 = u.kind == .COMBAT ? COMBAT_TRANSIT_SPEED : MINING_TRANSIT_SPEED
		velocity = rl.Vector3Normalize(heading) * speed
	} else {
		if sector < 0 || sector >= SECTOR_COUNT { return }
		heading = drone_heading(u.position, sector_pos(sector))
		velocity = heading * ORBIT_SPEED
	}
	seed := u.position.x * 12.9898 + u.position.y * 78.233 + u.position.z * 37.719
	a := seed * 3.7
	slot := 0
	oldest: f32 = -1
	for i in 0..<MAX_DRONE_WRECKS {
		if !drone_wrecks[i].active { slot = i; break }
		age := drone_wrecks[i].elapsed - drone_wrecks[i].delay
		if age > oldest { oldest = age; slot = i }
	}
	drone_wrecks[slot] = Drone_Wreck{
		active = true,
		kind = u.kind,
		sector = sector,
		position = u.position,
		velocity = velocity,
		heading = heading,
		kick = {math.cos(seed * 2.1), 0, math.sin(seed * 2.1)} * (DRONE_WRECK_SCATTER * (0.6 + 0.4 * abs(math.sin(seed * 0.7)))) + {0, DRONE_WRECK_POP, 0},
		spin_axis = rl.Vector3Normalize({math.cos(a), 0.8 * math.sin(seed), math.sin(a)}),
		spin_rate = DRONE_WRECK_SPIN * (math.sin(seed * 1.3) < 0 ? -1 : 1) * (0.75 + 0.25 * abs(math.cos(seed))),
		delay = delay,
	}
}

update_drone_wrecks :: proc(dt: f32) {
	for i in 0..<MAX_DRONE_WRECKS {
		w := &drone_wrecks[i]
		if !w.active { continue }
		w.elapsed += dt
		if w.elapsed >= w.delay {
			if !w.struck {
				w.struck = true
				w.velocity = w.velocity * DRONE_WRECK_DRIFT + w.kick
			}
			if w.elapsed - w.delay >= DRONE_WRECK_LIFETIME { w.active = false; continue }
			drag := math.exp(-DRONE_WRECK_DRAG * dt)
			w.velocity.x *= drag
			w.velocity.z *= drag
			w.velocity.y -= DRONE_WRECK_GRAVITY * dt
		}
		w.position += w.velocity * dt
	}
}

kill_fighter :: proc(p: int, enemy_side: bool) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.enemy == enemy_side && u.state == .GUARDING && u.affiliation == p {
			kill_unit_at(i)
			return true
		}
	}
	return false
}

kill_player_miner :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		if u.state == .IDLE && !planet_liberated(p) && u.progress < SCOUT_SURVIVAL { continue }
		kill_unit_at(i)
		return true
	}
	return false
}

player_miners_at :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		return true
	}
	return false
}

destroy_player_base :: proc(p: int) {
	if base_counts[p] <= 0 { return }
	production[p][base_counts[p] - 1] = Production{}
	base_counts[p] -= 1
	fill_production_lines(p)
}

enemy_miner_count :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		if units[i].kind == .MINING && units[i].enemy && units[i].affiliation == p { count += 1 }
	}
	return count
}

kill_enemy_miner :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.enemy && u.affiliation == p {
			kill_unit_at(i)
			return true
		}
	}
	return false
}

sector_in_combat :: proc(s: int) -> bool {
	players := 0
	enemies := 0
	has_player_miners := false
	has_enemy_miners := false
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.state == .GUARDING && u.affiliation == s {
			if u.enemy { enemies += 1 } else { players += 1 }
			if players > 0 && enemies > 0 { return true }
		} else if u.kind == .MINING {
			if u.enemy && u.affiliation == s {
				has_enemy_miners = true
			} else if !u.enemy && u.target_planet == s && u.state != .TRANSIT {
				has_player_miners = true
			}
		}
	}
	if players > 0 && enemies > 0 { return true }
	if enemies > 0 && (has_player_miners || (s == EARTH && base_counts[s] > 0) || (s < PLANET_COUNT && orbital_defense_level[s] > 0)) { return true }
	if players > 0 && (has_enemy_miners || enemy_base_hp[s] > 0 || (s == ENEMY_HOME && orbital_defense_level[s] > 0)) { return true }
	return false
}

update_combat :: proc(u: ^Unit, dt: f32) {
	if u.state == .TRANSIT {
		target := sector_pos(u.target_planet)
		travel(u, target, COMBAT_TRANSIT_SPEED * dt)
		if distance(u.position, target) <= sector_radius(u.target_planet) + 1.4 {
			u.state = .GUARDING
			u.orbit_placed = false
			u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
		}
	} else if u.state == .GUARDING {
		side := u.enemy ? 1 : 0
		s := u.affiliation
		n := orbit_group_count[s][side]
		if n > 1 && n < ORBIT_EVEN_SPACING_MAX {
			rank := orbit_group_rank[s][side] % n
			orbit_group_rank[s][side] += 1
			slot := orbit_phase + f32(rank) * 2 * math.PI / f32(n)
			diff := math.mod(slot - u.orbit_angle, 2 * math.PI)
			if diff > math.PI { diff -= 2 * math.PI }
			if diff < -math.PI { diff += 2 * math.PI }
			speed := ORBIT_SPEED + clamp(diff * ORBIT_SPACING_GAIN, -ORBIT_SPEED * (1 - ORBIT_SPACING_SLOWDOWN), ORBIT_SPEED * (ORBIT_SPACING_CATCHUP - 1))
			if !u.orbit_placed || abs(diff) < ORBIT_SPACING_SNAP {
				u.orbit_placed = true
				u.orbit_angle = slot
			} else {
				u.orbit_angle += speed * dt
			}
		} else {
			u.orbit_angle += dt * ORBIT_SPEED
		}
		u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
	}
}
