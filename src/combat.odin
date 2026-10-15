package main

import "core:c"
import "core:math"
import rl "vendor:raylib"


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

// ---- Orbital Defense ---------------------------------------------------

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
		// Strictly target approaching combat fighters in transit; never target units that have already reached orbit (.GUARDING)
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
	if planet_idx == ENEMY_HOME {
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		diff := target - pivot
		horiz_d := math.sqrt(diff.x * diff.x + diff.z * diff.z)
		azimuth = math.atan2(diff.z, diff.x)
		raw_elev := horiz_d > 0.001 ? math.atan2(diff.y, horiz_d) : (math.PI * 0.25)
		elev = clamp(raw_elev, 8.0 * rl.DEG2RAD, 85.0 * rl.DEG2RAD)
		return
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	pivot := pole + rl.Vector3{0, 0.58 * s, 0}
	diff := target - pivot
	horiz_d := math.sqrt(diff.x * diff.x + diff.z * diff.z)
	azimuth = math.atan2(diff.z, diff.x)
	raw_elev := horiz_d > 0.001 ? math.atan2(diff.y, horiz_d) : (math.PI * 0.25)
	elev = clamp(raw_elev, 8.0 * rl.DEG2RAD, 85.0 * rl.DEG2RAD)
	return
}

orbital_defense_muzzle_pos_toward :: proc(planet_idx: int, target: rl.Vector3) -> rl.Vector3 {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return {} }
	if planet_idx == ENEMY_HOME {
		azimuth, elev := orbital_defense_aim_toward(planet_idx, target)
		cos_az := math.cos(azimuth)
		sin_az := math.sin(azimuth)
		up := rl.Vector3{0, 1, 0}
		fwd := rl.Vector3{cos_az, 0, sin_az}
		cos_el := math.cos(elev)
		sin_el := math.sin(elev)
		barrel_dir := fwd * cos_el + up * sin_el
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		return pivot + barrel_dir * 3.25
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	azimuth, elev := orbital_defense_aim_toward(planet_idx, target)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)
	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	cos_el := math.cos(elev)
	sin_el := math.sin(elev)
	barrel_dir := fwd * cos_el + up * sin_el
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	return pivot + barrel_dir * (1.97 * s)
}

shortest_angle_diff :: proc(target, current: f32) -> f32 {
	diff := target - current
	for diff < -math.PI { diff += 2 * math.PI }
	for diff >  math.PI { diff -= 2 * math.PI }
	return diff
}

advance_orbital_defense_aim :: proc(planet_idx: int, dt: f32) {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return }
	if orbital_defense_level[planet_idx] <= 0 { return }

	// If upgrading (planets only), hold azimuth and park elevation in maintenance cradle (16 deg)
	if planet_idx < PLANET_COUNT && orbital_defense_building[planet_idx] {
		target_el: f32 = ORBITAL_DEFENSE_PARK_ELEV
		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
		return
	}

	enemy, has_enemy := closest_approaching_enemy(planet_idx)
	if has_enemy {
		// Active tracking: smoothly rotate azimuth and pitch elevation toward enemy
		target_az, target_el := orbital_defense_aim_toward(planet_idx, enemy.position)

		az_diff := shortest_angle_diff(target_az, orbital_defense_angle[planet_idx])
		max_az := ORBITAL_DEFENSE_TRACK_SPEED * dt
		if abs(az_diff) <= max_az {
			orbital_defense_angle[planet_idx] = target_az
		} else {
			orbital_defense_angle[planet_idx] += math.sign(az_diff) * max_az
		}

		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
	} else {
		// Idle scan: continue rotating forward from current azimuth without warping back
		orbital_defense_angle[planet_idx] += ORBITAL_DEFENSE_SCAN_SPEED * dt

		// Smoothly return elevation to idle resting angle
		target_el: f32 = ORBITAL_DEFENSE_IDLE_ELEV
		el_diff := target_el - orbital_defense_elevation[planet_idx]
		max_el := ORBITAL_DEFENSE_ELEV_SPEED * dt
		if abs(el_diff) <= max_el {
			orbital_defense_elevation[planet_idx] = target_el
		} else {
			orbital_defense_elevation[planet_idx] += math.sign(el_diff) * max_el
		}
	}

	// Normalize azimuth to [-PI, PI)
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

orbital_defense_muzzle_pos :: proc(planet_idx: int) -> rl.Vector3 {
	if planet_idx < 0 || planet_idx >= SECTOR_COUNT { return {} }
	if planet_idx == ENEMY_HOME {
		azimuth, elev := orbital_defense_aim(planet_idx)
		cos_az := math.cos(azimuth)
		sin_az := math.sin(azimuth)
		up := rl.Vector3{0, 1, 0}
		fwd := rl.Vector3{cos_az, 0, sin_az}
		cos_el := math.cos(elev)
		sin_el := math.sin(elev)
		barrel_dir := fwd * cos_el + up * sin_el
		pivot := ENEMY_HQ_POSITION + {0.3, 2.31, 0}
		return pivot + barrel_dir * 3.25
	}
	planet := planets[planet_idx]
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	azimuth, elev := orbital_defense_aim(planet_idx)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)
	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	cos_el := math.cos(elev)
	sin_el := math.sin(elev)
	barrel_dir := fwd * cos_el + up * sin_el
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	return pivot + barrel_dir * (1.97 * s)
}


spawn_orbital_defense_blast :: proc(planet: int, from, to: rl.Vector3, duration: f32 = 0.35) {
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
		elapsed = 0,
		duration = duration,
	}
}

update_orbital_defense_blasts :: proc(dt: f32) {
	for i in 0..<MAX_ORBITAL_BLASTS {
		if !orbital_defense_blasts[i].active { continue }
		orbital_defense_blasts[i].elapsed += dt
		if orbital_defense_blasts[i].elapsed >= orbital_defense_blasts[i].duration {
			orbital_defense_blasts[i].active = false
		}
	}
}

draw_orbital_defense_blasts :: proc() {
	for i in 0..<MAX_ORBITAL_BLASTS {
		b := &orbital_defense_blasts[i]
		if !b.active { continue }
		if distance(b.from, b.to) < 0.05 { continue }
		if !has_vision(b.planet) && b.planet != ENEMY_HOME { continue }

		t := clamp(b.elapsed / b.duration, 0.0, 1.0)
		fade := 1.0 - t
		alpha := u8(clamp(255.0 * fade, 0, 255))
		glow_alpha := u8(clamp(180.0 * fade, 0, 255))
		shock_alpha := u8(clamp(200.0 * fade, 0, 255))

		// Distinct palettes: Crimson/amber for Enemy HQ, cyan/mint for Player Planets
		beam_color := rl.Color{0, 240, 255, glow_alpha}
		core_color := rl.Color{255, 255, 255, alpha}
		line_color := rl.Color{210, 255, 255, alpha}
		shock_color := rl.Color{130, 255, 245, shock_alpha}
		spark_color := rl.Color{255, 240, 180, alpha}

		if b.planet == ENEMY_HOME {
			beam_color = rl.Color{255, 30, 45, glow_alpha}
			core_color = rl.Color{255, 240, 220, alpha}
			line_color = rl.Color{255, 120, 100, alpha}
			shock_color = rl.Color{255, 60, 75, shock_alpha}
			spark_color = rl.Color{255, 160, 80, alpha}
		}

		// 1. Big Laser Blast Beam (from orbital defense station to target fighter)
		core_r := 0.22 * fade + 0.04
		rl.DrawCylinderEx(b.from, b.to, core_r, core_r * 0.75, 8, core_color)

		// Outer glowing plasma cylinder: wide luminous aura
		glow_r := 0.65 * fade + 0.12
		rl.DrawCylinderEx(b.from, b.to, glow_r, glow_r * 0.75, 8, beam_color)

		// Central accelerator beam core line
		rl.DrawLine3D(b.from, b.to, line_color)

		// 2. Muzzle Flash & Discharge at Orbital Defense Station (b.from)
		flash_r := 0.55 * fade + 0.08
		rl.DrawSphere(b.from, flash_r * 0.6, core_color)
		rl.DrawSphereEx(b.from, flash_r, 8, 12, beam_color)
		rl.DrawCircle3D(b.from, 0.5 + t * 1.0, {0, 1, 0}, 90, beam_color)

		// 3. Vaporization Impact & Explosion at the Enemy Fighter (b.to)
		burst_r := 0.40 + 1.5 * math.sqrt(t)
		rl.DrawSphere(b.to, 0.30 * fade, core_color)
		rl.DrawSphereEx(b.to, burst_r * 0.75, 8, 12, beam_color)

		// Expanding vector wireframe sphere shockwave
		shock_r := 0.45 + 2.4 * t
		rl.DrawSphereWires(b.to, shock_r, 6, 8, shock_color)
		// Expanding horizontal planar tactical shockwave ring
		rl.DrawCircle3D(b.to, shock_r * 1.2, {0, 1, 0}, 90, beam_color)

		// High-energy plasma sparks and debris radiating outward from the blast
		spark_dist := t * 3.4
		for k in 0..<8 {
			ang := f32(k) * (math.PI / 4.0)
			elev := (f32(k % 3) - 1.0) * 0.55
			spark_dir := rl.Vector3Normalize(rl.Vector3{math.cos(ang), elev, math.sin(ang)})
			spark_pos := b.to + spark_dir * spark_dist
			trail_pos := b.to + spark_dir * (spark_dist * 0.65)
			rl.DrawLine3D(trail_pos, spark_pos, beam_color)
			rl.DrawSphere(spark_pos, 0.08 * fade, spark_color)
		}
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

orbital_ammo_constructing_miners :: proc(p: int) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .CONSTRUCTING && u.target_planet == p && u.build_target == .ORBITAL_DEFENSE_AMMO {
			count += 1
		}
	}
	return count
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

queued_ammo_at :: proc(p: int, slot: int) -> bool {
	return slot >= orbital_defense_ammo[p] && slot < orbital_defense_ammo[p] + orbital_defense_ammo_pending_count[p]
}

start_orbital_defense_construction :: proc(planet: int) {
	if !can_build_orbital_defense(planet) { return }
	minerals -= ORBITAL_DEFENSE_COST
	orbital_defense_building[planet] = true
	orbital_defense_progress[planet] = 0
	orbital_defense_elevation[planet] = ORBITAL_DEFENSE_PARK_ELEV
	construction_seq_counter += 1
	orbital_defense_build_order[planet] = construction_seq_counter

	// Pass 1: recruit idle miners first
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state == .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH)
			} else {
				is_match = (u.target_planet == planet)
			}
			if is_match {
				if orbital_defense_constructing_miners(planet) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .ORBITAL_DEFENSE
					u.progress = 0
					u.target_planet = planet
					u.affiliation = planet
					u.mining_active = false
				}
			}
		}
	}

	// Pass 2: recruit active miners (mining or depositing) if crew still needed
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && !u.enemy && u.state != .CONSTRUCTING && u.state != .IDLE {
			is_match := false
			if planet == EARTH {
				is_match = (u.target_planet == EARTH || u.affiliation == EARTH) && (u.state == .MINING || u.state == .DEPOSITING)
			} else {
				is_match = (u.target_planet == planet) && (u.state == .MINING)
			}
			if is_match {
				if orbital_defense_constructing_miners(planet) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
					u.state = .CONSTRUCTING
					u.build_target = .ORBITAL_DEFENSE
					u.progress = 0
					u.target_planet = planet
					u.affiliation = planet
					u.mining_active = false
				}
			}
		}
	}
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
			remove_unit_at(i)
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
	y: f32 = SECTION_TOP + BASE_BTN_H + 8
	return y
}

earth_orbital_defense_bottom_y :: proc() -> f32 {
	return earth_orbital_defense_y() + orbital_defense_section_height(EARTH)
}

orbital_defense_section_height :: proc(p: int) -> f32 {
	if p >= 0 && p < SECTOR_COUNT && orbital_defense_level[p] > 0 && !orbital_defense_building[p] {
		return GRID_PITCH + QUEUE_SLOT_H
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
	return int(outpost_orbital_defense_bottom_y(planet) + 10 + 23)
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

orbital_ammo_button_rect :: proc(panel_x: f32, planet: int) -> rl.Rectangle {
	base_y := orbital_defense_base_y(planet)
	half := (PANEL_CONTENT_W - PANEL_PAD_X) / 2
	return rl.Rectangle{panel_x + PANEL_PAD_X, base_y, f32(half), BASE_BTN_H}
}

orbital_ammo_slot_rect :: proc(panel_x: f32, planet: int, slot: int) -> rl.Rectangle {
	half := (PANEL_CONTENT_W - PANEL_PAD_X) / 2
	base_x := panel_x + PANEL_PAD_X + f32(half) + f32(PANEL_PAD_X)
	base_y := orbital_defense_base_y(planet)
	row := slot / 5
	column := slot % 5
	return rl.Rectangle{base_x + f32(column * 28), base_y + f32(row * GRID_PITCH), 24, QUEUE_SLOT_H}
}

orbital_ammo_queue_head :: proc(p: int) -> int {
	return orbital_defense_ammo[p]
}

draw_orbital_ammo_slot :: proc(rect: rl.Rectangle, filled: bool, progress: f32 = -1) {
	color := SCIFI_PANEL_SOLID
	border := SCIFI_DIM
	if filled {
		color = rl.Color{0, 65, 85, 255}
		border = SCIFI_CYAN
	}
	draw_chamfered_panel(rect, 3, color, border)
	if progress >= 0 {
		fill_rect := rl.Rectangle{rect.x, rect.y, rect.width * clamp(progress, 0, 1), rect.height}
		rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 140})
	}
	if filled || progress >= 0 {
		draw_corner_brackets(rect, 1, 3, border)
		symbol: cstring = "A"
		tw := f32(rl.MeasureText(symbol, 12))
		tx := rect.x + (rect.width - tw) / 2
		ty := rect.y + (rect.height - 12) / 2
		accent := SCIFI_AMBER
		rl.DrawText(symbol, c.int(tx + 1), c.int(ty + 1), 12, rl.Color{0, 0, 0, 160})
		rl.DrawText(symbol, c.int(tx), c.int(ty), 12, accent)
	}
}

draw_orbital_defense_inspector_section :: proc(x: f32, btn: rl.Rectangle, p: int) {
	if orbital_defense_building[p] {
		progress := orbital_defense_progress[p] / ORBITAL_DEFENSE_BUILD_TIME
		draw_chamfered_panel(btn, 6, SCIFI_PANEL_SOLID, SCIFI_STEEL)
		fill_rect := rl.Rectangle{btn.x, btn.y, btn.width * progress, btn.height}
		rl.DrawRectangleRec(fill_rect, rl.Color{0, 200, 120, 120})
		draw_corner_brackets(btn, 2, 6, SCIFI_CYAN)
		if orbital_defense_constructing_miners(p) < ORBITAL_DEFENSE_CONSTRUCT_MINERS {
			rl.DrawText(rl.TextFormat("CREW %d/%d - MINERS AUTO-JOIN", orbital_defense_constructing_miners(p), ORBITAL_DEFENSE_CONSTRUCT_MINERS), i32(btn.x + CARD_INSET), i32(btn.y + 12), 11, rl.WHITE)
		} else {
			remaining := ORBITAL_DEFENSE_BUILD_TIME - orbital_defense_progress[p]
			rl.DrawText(rl.TextFormat("BUILDING DEFENSE  %3.1fs", remaining), i32(btn.x + CARD_INSET), i32(btn.y + 11), 12, rl.WHITE)
		}
	} else if orbital_defense_level[p] == 0 {
		can_build := can_build_orbital_defense(p)
		draw_button(btn, rl.TextFormat("[O] BUILD ORBITAL DEFENSE (%d)", ORBITAL_DEFENSE_COST), SCIFI_PANEL_SOLID, can_build)
	} else {
		can_ammo := can_build_orbital_ammo(p)
		ammo_btn := orbital_ammo_button_rect(x, p)
		draw_button(ammo_btn, "[O] +1 Ammo (200)", SCIFI_PANEL_SOLID, can_ammo)
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
								spawn_orbital_defense_blast(p, muzzle_pos, u.position, 0.35)
								remove_unit_at(i)
								if orbital_defense_wave_kills[p] >= max_kills { break }
							}
						}
					}
				}
			}
		} else if orbital_defense_level[p] > 0 && !is_building {
			// Ammo batteries: each shot consumes 1 ammo and kills up to
			// KILLS_PER_SHOT inbound fighters. Empty batteries hold fire.
			// Fire every shot needed in one update so inbound fighters never
			// reach the planet while ammo is still available.
			target_pos := sector_pos(p)
			r := sector_radius(p)
			engage_dist := r + 3.8
			for orbital_defense_ammo[p] > 0 {
				kills := 0
				shot_fired := false
				for i := unit_count - 1; i >= 0; i -= 1 {
					u := &units[i]
					if !u.enemy || u.kind != .COMBAT || u.state != .TRANSIT || u.target_planet != p { continue }
					d := distance(u.position, target_pos)
					if d <= engage_dist {
						muzzle_pos := orbital_defense_muzzle_pos_toward(p, u.position)
						spawn_orbital_defense_blast(p, muzzle_pos, u.position, 0.35)
						remove_unit_at(i)
						kills += 1
						orbital_defense_wave_kills[p] += 1
						orbital_defense_ammo_pending_kills[p] += 1
						shot_fired = true
						if kills >= ORBITAL_DEFENSE_KILLS_PER_SHOT { break }
					}
				}
				if !shot_fired { break }
				if orbital_defense_ammo_pending_kills[p] >= ORBITAL_DEFENSE_KILLS_PER_SHOT {
					orbital_defense_ammo[p] -= 1
					orbital_defense_ammo_pending_kills[p] -= ORBITAL_DEFENSE_KILLS_PER_SHOT
				}
				orbital_defense_reset_timer[p] = ORBITAL_DEFENSE_WAVE_RESET_DELAY
			}
			// Charge any partial final shot once the inbound wave clears.
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

// Minor wave: every 75 seconds, concurrent minor waves launch against liberated planets.
// Every liberated planet is attacked from the closest not liberated planet.
// Each not liberated planet only attacks one liberated planet, its closest.
// These attacks run independently of the 180s wave.
update_minor_wave :: proc(dt: f32) {
	minor_wave_timer += dt
	if minor_wave_timer >= MINOR_WAVE_INTERVAL {
		launch_minor_wave()
	}
}

// Computes the minor wave attack pairs for all liberated planets.
// Pairs unliberated planets with liberated planets greedily by distance:
// each liberated planet is attacked from the closest available unliberated planet,
// and each unliberated planet attacks at most one liberated planet (its closest
// available liberated planet).
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

	// Sort pairs ascending by distance (insertion sort on at most 16 pairs)
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

// Warning before minor wave: 3 seconds before launch, targeted planets
// receive an ominous red glow at half battle intensity.
planet_is_minor_wave_target :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	_, targets, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if targets[i] == p { return true }
	}
	return false
}

// Warning before minor wave: 3 seconds before launch, attacking source planets
// receive an ominous yellow aura at half battle intensity.
planet_is_minor_wave_source :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return false }
	sources, _, count := collect_minor_wave_attacks()
	for i in 0..<count {
		if sources[i] == p { return true }
	}
	return false
}

minor_wave_warning_planet :: proc() -> int {
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return -1 }
	sources, targets, count := collect_minor_wave_attacks()
	if count == 0 { return -1 }
	for i in 0..<count {
		if targets[i] == EARTH { return EARTH }
	}
	return targets[0]
}

minor_wave_warning_source_planet :: proc() -> int {
	if minor_wave_timer < MINOR_WAVE_INTERVAL - 3.0 { return -1 }
	sources, targets, count := collect_minor_wave_attacks()
	if count == 0 { return -1 }
	for i in 0..<count {
		if targets[i] == EARTH { return sources[i] }
	}
	return sources[0]
}

minor_wave_source_warning_planet :: proc() -> int {
	return minor_wave_warning_source_planet()
}

// A planet is the source of an impending minor wave within 3s of launching.
planet_attack_source_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	return planet_is_minor_wave_source(p)
}

// A planet is under attack warning if an impending minor wave is within 3s
// of launching against it, or if enemy combat drones are currently in transit
// toward it. The warning red glow persists during transit and transitions to
// full battle glow once combat begins.
planet_under_attack_warning :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if planet_is_minor_wave_target(p) { return true }
	return transit_fighters_at(p, true) > 0
}

closest_unliberated_planet_to_earth :: proc() -> (int, bool) {
	best := -1
	best_d: f32 = 1e9
	earth_pos := planets[EARTH].position
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		if planet_liberated(p) { continue }
		d := distance(planets[p].position, earth_pos)
		if best < 0 || d < best_d {
			best = p
			best_d = d
		}
	}
	return best, best >= 0
}

closest_liberated_planet_to :: proc(attacker: int) -> int {
	attacker_pos := planets[attacker].position
	best_other := -1
	best_other_d: f32 = 1e9

	for p in 0..<PLANET_COUNT {
		if p == EARTH || p == attacker { continue }
		if !planet_liberated(p) { continue }
		d := distance(planets[p].position, attacker_pos)
		if best_other < 0 || d < best_other_d {
			best_other = p
			best_other_d = d
		}
	}

	earth_d := distance(planets[EARTH].position, attacker_pos)
	if best_other >= 0 && best_other_d <= earth_d {
		return best_other
	}
	return EARTH
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

// Wave: every 180 seconds, advancing while 2+ worlds are liberated.
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

// One attack cycle: a single wave of attack_wave_size() fighters. While the
// player presses an assault on a weakened HQ the wave musters there as
// guarding defenders instead; otherwise it sorties against the liberated
// planet closest to the enemy HQ. A destroyed HQ launches nothing, ever.
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

launch_attack_wave :: proc() {
	launch_wave()
}

// Combat tick for a sector: HQ battles resolve 5x faster than planet battles.
combat_tick_for :: proc(p: int) -> f32 {
	if p == ENEMY_HOME {
		return HQ_COMBAT_TICK
	}
	return COMBAT_TICK
}
combat_tick :: combat_tick_for
planet_combat_tick :: combat_tick_for

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
			// Earth siege: once no defenders or miners are left, the occupying
			// fighters tear down the command bases, one per BASE_SIEGE_TIME.
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
		// Occupation cleanup: with the garrison fighters gone, player fighters
		// sweep the enemy mining drones, then bring down the enemy base.
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

// Attack wave size: (liberated planets - 1) * WAVE_FIGHTERS_PER_LIBERATED
// fighters (3 liberated worlds send 30). Earth starts liberated, so the
// result is 0 until a second world falls - the wave musters nothing.
attack_wave_size :: proc() -> int {
	return (liberated_planet_count() - 1) * WAVE_FIGHTERS_PER_LIBERATED
}

// Liberated worlds (planets only - the HQ sector is not a planet).
liberated_planet_count :: proc() -> int {
	count := 0
	for p in 0..<PLANET_COUNT { if planet_liberated(p) { count += 1 } }
	return count
}

// The liberated planet closest to the enemy HQ - the wave's fixed target.
// Earth starts liberated, so there is always at least one candidate.
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

// True while player fighters press the HQ: stationed there (affiliation) or
// already inbound (transit with the HQ as target).
player_attacking_hq :: proc() -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.enemy { continue }
		if u.affiliation == ENEMY_HOME { return true }
		if u.state == .TRANSIT && u.target_planet == ENEMY_HOME { return true }
	}
	return false
}

// Muster `count` fighters as guarding defenders of the HQ (capped by free
// unit slots), placed on the guard orbit like the opening garrison.
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

// Debug: force the next attack wave immediately (verify combat without
// waiting 3 minutes).
spawn_enemy_wave :: proc() { launch_attack_wave() }

// Spawns `count` enemy fighters (capped by free unit slots) lifting off from
// the enemy HQ toward `target`. A destroyed HQ launches nothing, ever.
spawn_n_enemies_to :: proc(target: int, count: int) {
	if enemy_hq_destroyed() { return }
	spawn_count := min(count, MAX_UNITS - unit_count)
	if spawn_count <= 0 { return }
	// Every wave lifts off from the enemy HQ (the old Neptune orbit) - no
	// longer from Jupiter space.
	for i in 0..<spawn_count {
		angle := f32(i) * 1.26
		pos := ENEMY_HQ_POSITION + rl.Vector3{math.cos(angle) * 1.5, 0.5, math.sin(angle) * 1.5}
		units[unit_count] = Unit{
			kind = .COMBAT, state = .TRANSIT, position = pos,
			home_planet = NEPTUNE, affiliation = target, target_planet = target,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

// A planet is liberated once its enemy base is destroyed (the combat rules
// only damage the base after every enemy drone there is gone).
planet_liberated :: proc(p: int) -> bool {
	return enemy_base_hp[p] <= 0
}

// Counts of guarding fighters at a planet: player units vs enemy units.
planet_combatants :: proc(p: int) -> (players, enemies: int) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .COMBAT || u.state != .GUARDING || u.affiliation != p { continue }
		if u.enemy { enemies += 1 } else { players += 1 }
	}
	return
}

kill_fighter :: proc(p: int, enemy_side: bool) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.enemy == enemy_side && u.state == .GUARDING && u.affiliation == p {
			remove_unit_at(i)
			return true
		}
	}
	return false
}

// Garrison defenses only engage miners physically at the planet: transit
// across space is safe. A scout freshly pinned at an occupied planet keeps
// a SCOUT_SURVIVAL grace window (its .IDLE progress) before it becomes a
// target, so the player can peek at the garrison before losing the drone.
kill_player_miner :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		if u.state == .IDLE && !planet_liberated(p) && u.progress < SCOUT_SURVIVAL { continue }
		remove_unit_at(i)
		return true
	}
	return false
}

// Any player mining drone physically at p (transit legs are elsewhere and
// safe). Mirrors kill_player_miner's target set without killing anything.
player_miners_at :: proc(p: int) -> bool {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy || u.target_planet != p || u.state == .TRANSIT { continue }
		return true
	}
	return false
}

// Enemy siege tears down one command base: drop its production line (the
// highest-index line), then redistribute pending items across the survivors.
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
			remove_unit_at(i)
			return true
		}
	}
	return false
}

// Drones actively fighting at sector s (dogfight, miner sweep, or base siege).
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
			u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
		}
	} else if u.state == .GUARDING {
		u.orbit_angle += dt * 0.9
		u.position = orbit_pos(sector_pos(u.affiliation), sector_radius(u.affiliation), u.orbit_angle)
	}
}

// Procedural 3D oriented quad (double-wound so it renders from front and back).
draw_quad_3d :: proc(v1, v2, v3, v4: rl.Vector3, col: rl.Color) {
	rl.DrawTriangle3D(v1, v2, v3, col)
	rl.DrawTriangle3D(v1, v3, v4, col)
	rl.DrawTriangle3D(v3, v2, v1, col)
	rl.DrawTriangle3D(v4, v3, v1, col)
}

// Procedural 3D oriented box aligned to an arbitrary orthonormal basis (fwd, up, right).
draw_oriented_box :: proc(
	center: rl.Vector3,
	half_w, half_h, half_l: f32,
	fwd, up, right: rl.Vector3,
	col: rl.Color,
) {
	p0 := center - right * half_w - up * half_h - fwd * half_l
	p1 := center + right * half_w - up * half_h - fwd * half_l
	p2 := center + right * half_w + up * half_h - fwd * half_l
	p3 := center - right * half_w + up * half_h - fwd * half_l
	p4 := center - right * half_w - up * half_h + fwd * half_l
	p5 := center + right * half_w - up * half_h + fwd * half_l
	p6 := center + right * half_w + up * half_h + fwd * half_l
	p7 := center - right * half_w + up * half_h + fwd * half_l

	// Rear face (-fwd)
	draw_quad_3d(p0, p1, p2, p3, col)
	// Front face (+fwd)
	draw_quad_3d(p4, p5, p6, p7, col)
	// Bottom face (-up)
	draw_quad_3d(p0, p1, p5, p4, col)
	// Top face (+up)
	draw_quad_3d(p3, p2, p6, p7, col)
	// Left face (-right)
	draw_quad_3d(p0, p3, p7, p4, col)
	// Right face (+right)
	draw_quad_3d(p1, p2, p6, p5, col)
}

// Pulsating red emergency hazard lights (ambulance-style alternating dual strobes)
// used for orbital defenses undergoing construction or upgrade refits.
draw_ambulance_hazard_lights :: proc(p_left, p_right: rl.Vector3, s: f32) {
	// Alternating high-cadence strobe pulse (ambulance emergency light bar effect)
	t := laser_anim_time * 12.0
	phase := math.sin(t)
	pulse_l := clamp((phase - 0.1) * 2.2, 0.0, 1.0)
	pulse_r := clamp((-phase - 0.1) * 2.2, 0.0, 1.0)

	// Crossbar bracket connecting the lights
	rl.DrawCylinderEx(p_left, p_right, 0.016 * s, 0.016 * s, 6, rl.Color{45, 48, 55, 255})

	// Left red strobe
	rl.DrawCylinderEx(p_left - {0, 0.05 * s, 0}, p_left, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_l > 0.05 {
		rl.DrawSphere(p_left, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_left, 0.09 * s * pulse_l + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_l)})
		rl.DrawSphereEx(p_left, 0.18 * s * pulse_l + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_l)})
	} else {
		rl.DrawSphere(p_left, 0.032 * s, rl.Color{110, 20, 25, 255})
	}

	// Right red strobe
	rl.DrawCylinderEx(p_right - {0, 0.05 * s, 0}, p_right, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_r > 0.05 {
		rl.DrawSphere(p_right, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_right, 0.09 * s * pulse_r + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_r)})
		rl.DrawSphereEx(p_right, 0.18 * s * pulse_r + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_r)})
	} else {
		rl.DrawSphere(p_right, 0.032 * s, rl.Color{110, 20, 25, 255})
	}
}

// Cyberpunk space version of a sand-colored Flak 88 battery mounted on the
// planet surface at the north pole.
draw_cyberpunk_flak88 :: proc(planet_idx: int) {
	if planet_idx < 0 || planet_idx >= PLANET_COUNT { return }
	planet := planets[planet_idx]
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	lit := has_vision(planet_idx)
	level := orbital_defense_level[planet_idx]
	is_upgrading := orbital_defense_building[planet_idx]

	// Scale subtly with planet radius for consistent planetary presence
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)

	// Azimuth and elevation dynamically track approaching enemies when active,
	// or scan gracefully when idle, or park in maintenance cradle when upgrading.
	azimuth, elev := orbital_defense_aim(planet_idx)
	cos_az := math.cos(azimuth)
	sin_az := math.sin(azimuth)

	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{cos_az, 0, sin_az}
	right := rl.Vector3{-sin_az, 0, cos_az}

	cos_el := math.cos(elev)
	sin_el := math.sin(elev)

	barrel_dir := fwd * cos_el + up * sin_el
	barrel_normal := -fwd * sin_el + up * cos_el

	// Palette: sand military armor contrasted with gunmetal chassis & cyan energy
	sand_base    := rl.Color{214, 182, 134, 255}
	sand_dark    := rl.Color{160, 132, 92, 255}
	sand_light   := rl.Color{240, 215, 175, 255}
	gunmetal     := rl.Color{36, 40, 46, 255}
	frame_mid    := rl.Color{65, 72, 82, 255}
	steel_bright := rl.Color{155, 165, 180, 255}
	cyan_glow    := SCIFI_CYAN
	mint_core    := SCIFI_MINT
	amber_lens   := SCIFI_AMBER

	if !lit {
		sand_base = rl.Color{105, 100, 92, 255}
		sand_dark = rl.Color{75, 72, 68, 255}
		sand_light = rl.Color{125, 120, 112, 255}
		gunmetal = rl.Color{45, 47, 52, 255}
		frame_mid = rl.Color{55, 58, 64, 255}
		steel_bright = rl.Color{90, 95, 102, 255}
		cyan_glow = rl.Color{0, 120, 130, 200}
		mint_core = rl.Color{70, 130, 120, 200}
		amber_lens = rl.Color{120, 70, 30, 200}
	} else if is_upgrading {
		// Powered-down coils and dark energy conduits while disabled during upgrade
		cyan_glow = rl.Color{55, 50, 45, 255}
		mint_core = rl.Color{80, 70, 60, 255}
	}

	// 1. Kreuzlafette: Central base collar & 4 cruciform outrigger legs on surface
	base_b := pole + up * (0.01 * s)
	base_m := pole + up * (0.12 * s)
	base_t := pole + up * (0.22 * s)
	rl.DrawCylinderEx(base_b, base_m, 0.44 * s, 0.40 * s, 12, gunmetal)
	rl.DrawCylinderEx(base_m, base_t, 0.40 * s, 0.36 * s, 12, sand_dark)

	for d_idx in 0..<4 {
		leg_ang := planet_spin[planet_idx] + f32(d_idx) * (math.PI / 2.0)
		ldir := rl.Vector3{math.cos(leg_ang), 0, math.sin(leg_ang)}
		l_start := pole + up * (0.08 * s) + ldir * (0.30 * s)
		l_end   := pole + up * (0.05 * s) + ldir * (0.80 * s)

		// Tapered girder outrigger
		rl.DrawCylinderEx(l_start, l_end, 0.085 * s, 0.060 * s, 6, sand_base)
		rl.DrawCylinderEx(l_start, l_start + ldir * (0.10 * s), 0.095 * s, 0.090 * s, 6, gunmetal)

		// Conduit line along the top spine of each leg
		c_s := l_start + up * (0.065 * s)
		c_e := l_end + up * (0.045 * s)
		rl.DrawLine3D(c_s, c_e, cyan_glow)

		// Outrigger footpad / leveling jack
		pad_b := pole + up * (0.01 * s) + ldir * (0.80 * s)
		pad_t := pole + up * (0.09 * s) + ldir * (0.80 * s)
		rl.DrawCylinderEx(pad_b, pad_t, 0.15 * s, 0.13 * s, 8, gunmetal)
		rl.DrawCylinderEx(pad_t, pad_t + up * (0.08 * s), 0.045 * s, 0.045 * s, 6, steel_bright)
		rl.DrawCylinderEx(pad_t, pad_t + up * (0.01 * s), 0.13 * s, 0.13 * s, 8, rl.Fade(cyan_glow, 0.7))
	}

	// 2. Azimuth Turntable Ring & Traversing Platform Deck
	tt_b := pole + up * (0.22 * s)
	tt_t := pole + up * (0.30 * s)
	rl.DrawCylinderEx(tt_b, tt_t, 0.35 * s, 0.35 * s, 16, gunmetal)
	rl.DrawCylinderEx(tt_t, tt_t + up * (0.01 * s), 0.34 * s, 0.34 * s, 16, cyan_glow)

	deck_b := tt_t
	deck_t := pole + up * (0.38 * s)
	rl.DrawCylinderEx(deck_b, deck_t, 0.33 * s, 0.31 * s, 8, sand_base)

	// 3. Twin Trunnion Stanchions (Mounting Cheeks) & Pivot Axle
	ch_h: f32 = 0.28 * s
	ch_w: f32 = 0.09 * s
	ch_l: f32 = 0.26 * s
	ch_y := 0.51 * s
	pos_left := pole + up * ch_y - right * (0.16 * s)
	pos_right := pole + up * ch_y + right * (0.16 * s)
	draw_oriented_box(pos_left, ch_w * 0.5, ch_h * 0.5, ch_l * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(pos_right, ch_w * 0.5, ch_h * 0.5, ch_l * 0.5, fwd, up, right, sand_base)

	axle_y := 0.58 * s
	axle_l := pole + up * axle_y - right * (0.23 * s)
	axle_r := pole + up * axle_y + right * (0.23 * s)
	rl.DrawCylinderEx(axle_l, axle_r, 0.055 * s, 0.055 * s, 8, steel_bright)
	rl.DrawCylinderEx(axle_l, axle_l - right * (0.03 * s), 0.08 * s, 0.075 * s, 8, gunmetal)
	rl.DrawCylinderEx(axle_r, axle_r + right * (0.03 * s), 0.08 * s, 0.075 * s, 8, gunmetal)

	// Hydraulic elevation ram under cradle
	ram_b := pole + up * (0.37 * s) + fwd * (0.10 * s)
	ram_t := pole + up * (0.53 * s) + fwd * (0.03 * s) - barrel_normal * (0.07 * s)
	rl.DrawCylinderEx(ram_b, ram_t, 0.045 * s, 0.035 * s, 6, steel_bright)
	rl.DrawCylinderEx(ram_b, (ram_b + ram_t) * 0.5, 0.058 * s, 0.058 * s, 6, gunmetal)

	// 4. Sloped Gun Shield (Schutzschild) & Targeting Optronics
	sh_center := pole + up * (0.58 * s) + fwd * (0.19 * s)
	pl_w: f32 = 0.14 * s
	pl_h: f32 = 0.44 * s
	pl_th: f32 = 0.03 * s
	draw_oriented_box(sh_center - right * (0.14 * s), pl_w * 0.5, pl_h * 0.5, pl_th * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(sh_center + right * (0.14 * s), pl_w * 0.5, pl_h * 0.5, pl_th * 0.5, fwd, up, right, sand_base)
	draw_oriented_box(sh_center + up * (0.19 * s), 0.22 * s, 0.06 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_light)

	// Angled side cheek wings (bent backwards along -fwd)
	h_half := up * (0.21 * s)
	w_l_root := sh_center - right * (0.21 * s)
	w_l_tip  := w_l_root - right * (0.16 * s) - fwd * (0.14 * s)
	draw_quad_3d(w_l_root - h_half, w_l_tip - h_half, w_l_tip + h_half, w_l_root + h_half, sand_dark)

	w_r_root := sh_center + right * (0.21 * s)
	w_r_tip  := w_r_root + right * (0.16 * s) - fwd * (0.14 * s)
	draw_quad_3d(w_r_root - h_half, w_r_tip - h_half, w_r_tip + h_half, w_r_root + h_half, sand_dark)

	// Optronic sensor pod on left shield
	pod_pos := sh_center - right * (0.15 * s) + up * (0.10 * s) + fwd * (0.04 * s)
	draw_oriented_box(pod_pos, 0.055 * s, 0.065 * s, 0.075 * s, fwd, up, right, gunmetal)
	rl.DrawSphereEx(pod_pos + fwd * (0.08 * s) + up * (0.022 * s), 0.024 * s, 6, 6, cyan_glow)
	rl.DrawSphereEx(pod_pos + fwd * (0.08 * s) - up * (0.022 * s), 0.028 * s, 6, 6, amber_lens)

	// Communications mast on right shield
	mast_b := sh_center + right * (0.19 * s) + up * (0.22 * s)
	mast_t := mast_b + up * (0.30 * s) - fwd * (0.04 * s)
	rl.DrawCylinderEx(mast_b, mast_t, 0.016 * s, 0.007 * s, 4, steel_bright)
	beacon_pulse := 0.75 + 0.25 * math.sin(laser_anim_time * 8.0 + f32(planet_idx))
	rl.DrawSphere(mast_t, 0.022 * s, rl.Fade(cyan_glow, beacon_pulse))

	// If upgrading: Pulsating Red Ambulance Lights on top of the shield!
	if is_upgrading {
		light_l := sh_center - right * (0.16 * s) + up * (0.26 * s)
		light_r := sh_center + right * (0.16 * s) + up * (0.26 * s)
		draw_ambulance_hazard_lights(light_l, light_r, s)
	}

	// 5. Gun Cradle & Breech Mechanism
	pivot := pole + up * (0.58 * s) + fwd * (0.03 * s)
	breech_c := pivot - barrel_dir * (0.16 * s)
	draw_oriented_box(breech_c, 0.10 * s, 0.09 * s, 0.15 * s, barrel_dir, barrel_normal, right, gunmetal)
	draw_oriented_box(breech_c + barrel_normal * (0.08 * s), 0.09 * s, 0.025 * s, 0.14 * s, barrel_dir, barrel_normal, right, sand_base)

	// Heatsink slats with cyan thermal channels
	draw_oriented_box(breech_c + right * (0.105 * s), 0.008 * s, 0.045 * s, 0.11 * s, barrel_dir, barrel_normal, right, cyan_glow)
	draw_oriented_box(breech_c - right * (0.105 * s), 0.008 * s, 0.045 * s, 0.11 * s, barrel_dir, barrel_normal, right, cyan_glow)

	// Upper recoil cylinder
	rc_s := pivot - barrel_dir * (0.18 * s) + barrel_normal * (0.11 * s)
	rc_e := pivot + barrel_dir * (0.35 * s) + barrel_normal * (0.11 * s)
	rl.DrawCylinderEx(rc_s, rc_e, 0.045 * s, 0.045 * s, 8, steel_bright)
	rl.DrawCylinderEx(rc_s, rc_s + barrel_dir * (0.06 * s), 0.058 * s, 0.058 * s, 8, gunmetal)

	// Lower recuperator cylinder
	rp_s := pivot - barrel_dir * (0.14 * s) - barrel_normal * (0.09 * s)
	rp_e := pivot + barrel_dir * (0.28 * s) - barrel_normal * (0.09 * s)
	rl.DrawCylinderEx(rp_s, rp_e, 0.038 * s, 0.038 * s, 8, steel_bright)

	// 6. Stepped Barrel with Magnetic Rail Accelerator Coils & Double-Baffle Muzzle Brake
	// Stage 1: Base Thermal Sleeve
	s1_s := pivot
	s1_e := pivot + barrel_dir * (0.45 * s)
	rl.DrawCylinderEx(s1_s, s1_e, 0.088 * s, 0.076 * s, 10, sand_base)
	rl.DrawCylinderEx(s1_s, s1_s + barrel_dir * (0.09 * s), 0.10 * s, 0.10 * s, 10, gunmetal)

	// Stage 2: Accelerator Section
	s2_s := s1_e
	s2_e := pivot + barrel_dir * (1.25 * s)
	rl.DrawCylinderEx(s2_s, s2_e, 0.070 * s, 0.058 * s, 10, gunmetal)

	for c_i in 0..<4 {
		c_t: f32 = 0.12 + f32(c_i) * 0.25
		c_pos := s2_s + barrel_dir * ((0.75 * c_t) * s)
		c_len := c_pos + barrel_dir * (0.038 * s)
		rl.DrawCylinderEx(c_pos, c_len, 0.082 * s, 0.082 * s, 10, cyan_glow)
		rl.DrawCylinderEx(c_pos, c_pos + barrel_dir * (0.008 * s), 0.086 * s, 0.086 * s, 10, mint_core)
		rl.DrawCylinderEx(c_len - barrel_dir * (0.008 * s), c_len, 0.086 * s, 0.086 * s, 10, mint_core)
	}

	// Stage 3: Forward Barrel
	s3_s := s2_e
	s3_e := pivot + barrel_dir * (1.75 * s)
	rl.DrawCylinderEx(s3_s, s3_e, 0.054 * s, 0.044 * s, 10, sand_base)

	// Stage 4: Double-Baffle Muzzle Brake
	mb_s := s3_e
	mb_e := s3_e + barrel_dir * (0.22 * s)
	rl.DrawCylinderEx(mb_s, mb_e, 0.074 * s, 0.074 * s, 8, gunmetal)
	baf1 := mb_s + barrel_dir * (0.06 * s)
	rl.DrawCylinderEx(baf1, baf1 + barrel_dir * (0.03 * s), 0.092 * s, 0.092 * s, 8, frame_mid)
	baf2 := mb_s + barrel_dir * (0.13 * s)
	rl.DrawCylinderEx(baf2, baf2 + barrel_dir * (0.03 * s), 0.092 * s, 0.092 * s, 8, frame_mid)

	rl.DrawCylinderEx(mb_e - barrel_dir * (0.015 * s), mb_e, 0.048 * s, 0.048 * s, 8, mint_core)
	rl.DrawSphereEx(mb_e, 0.032 * s, 6, 6, cyan_glow)

	// 7. Tech upgrades for higher defense levels
	if level >= 2 {
		cap_l := pole + up * (0.40 * s) - right * (0.24 * s) - fwd * (0.08 * s)
		cap_r := pole + up * (0.40 * s) + right * (0.24 * s) - fwd * (0.08 * s)
		rl.DrawCylinderEx(cap_l, cap_l + up * (0.16 * s), 0.060 * s, 0.060 * s, 8, sand_dark)
		rl.DrawCylinderEx(cap_r, cap_r + up * (0.16 * s), 0.060 * s, 0.060 * s, 8, sand_dark)
		rl.DrawLine3D(cap_l + up * (0.02 * s), cap_l + up * (0.14 * s), cyan_glow)
		rl.DrawLine3D(cap_r + up * (0.02 * s), cap_r + up * (0.14 * s), cyan_glow)

		rail_s := s1_e + barrel_normal * (0.085 * s)
		rail_e := s2_e + barrel_normal * (0.075 * s)
		rl.DrawLine3D(rail_s, rail_e, cyan_glow)
	}

	if level >= 3 {
		radar_b := pole + up * (0.40 * s) + right * (0.24 * s) - fwd * (0.14 * s)
		radar_t := radar_b + up * (0.24 * s)
		rl.DrawCylinderEx(radar_b, radar_t, 0.02 * s, 0.015 * s, 4, steel_bright)

		radar_sweep := laser_anim_time * 2.2 + f32(planet_idx)
		r_dir := rl.Vector3{math.cos(radar_sweep), 0.35, math.sin(radar_sweep)}
		rl.DrawCylinderEx(radar_t, radar_t + r_dir * (0.025 * s), 0.12 * s, 0.08 * s, 8, sand_light)
		rl.DrawLine3D(radar_t, radar_t + r_dir * (0.13 * s), cyan_glow)
		rl.DrawSphere(radar_t + r_dir * (0.035 * s), 0.022 * s, cyan_glow)
	}

	if level >= 4 {
		p_pulse := 0.65 + 0.35 * math.sin(laser_anim_time * 6.0 + f32(planet_idx))
		rl.DrawSphereEx(breech_c, 0.08 * s * p_pulse, 6, 8, rl.Fade(cyan_glow, 0.85))
	}

	if level >= 6 {
		bcap_l := pole + up * (0.32 * s) - right * (0.28 * s) - fwd * (0.22 * s)
		bcap_r := pole + up * (0.32 * s) + right * (0.28 * s) - fwd * (0.22 * s)
		rl.DrawCylinderEx(bcap_l, bcap_l + up * (0.20 * s), 0.075 * s, 0.075 * s, 8, gunmetal)
		rl.DrawCylinderEx(bcap_r, bcap_r + up * (0.20 * s), 0.075 * s, 0.075 * s, 8, gunmetal)
		rl.DrawCylinderEx(bcap_l + up * (0.05 * s), bcap_l + up * (0.15 * s), 0.082 * s, 0.082 * s, 8, cyan_glow)
		rl.DrawCylinderEx(bcap_r + up * (0.05 * s), bcap_r + up * (0.15 * s), 0.082 * s, 0.082 * s, 8, cyan_glow)
	}

	if level >= 8 {
		draw_oriented_box(sh_center - right * (0.34 * s), 0.10 * s, 0.36 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_dark)
		draw_oriented_box(sh_center + right * (0.34 * s), 0.10 * s, 0.36 * s * 0.5, pl_th * 0.5, fwd, up, right, sand_dark)
		rl.DrawLine3D(sh_center - right * (0.38 * s) - up * (0.16 * s), sh_center - right * (0.38 * s) + up * (0.16 * s), cyan_glow)
		rl.DrawLine3D(sh_center + right * (0.38 * s) - up * (0.16 * s), sh_center + right * (0.38 * s) + up * (0.16 * s), cyan_glow)
	}

	if level >= 10 {
		under_s := s1_e - barrel_normal * (0.085 * s)
		under_e := s3_e - barrel_normal * (0.065 * s)
		rl.DrawLine3D(under_s, under_e, mint_core)
		corona_pulse := 0.70 + 0.30 * math.sin(laser_anim_time * 9.0 + f32(planet_idx))
		corona_r: f32 = 0.16 * s * corona_pulse
		rl.DrawCircle3D(mb_e + barrel_dir * (0.06 * s), corona_r, barrel_dir, 32, rl.Fade(cyan_glow, 0.85))
		rl.DrawCircle3D(mb_e + barrel_dir * (0.09 * s), corona_r * 0.7, barrel_dir, 24, rl.Fade(mint_core, 0.95))
	}
}

// Visual construction site for an orbital defense battery being assembled by miners
draw_cyberpunk_flak88_construction_site :: proc(planet_idx: int) {
	if planet_idx < 0 || planet_idx >= PLANET_COUNT { return }
	planet := planets[planet_idx]
	pole := rl.Vector3{planet.position.x, planet.position.y + planet.radius, planet.position.z}
	up := rl.Vector3{0, 1, 0}
	s: f32 = 0.84 + clamp(planet.radius * 0.07, 0.11, 0.32)

	gunmetal := rl.Color{40, 44, 52, 255}
	cyan_glow := SCIFI_CYAN
	mint_core := SCIFI_MINT

	// Base outriggers & pads
	for d_idx in 0..<4 {
		ang := f32(d_idx) * (math.PI / 2.0)
		ldir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		l_start := pole + up * (0.05 * s)
		l_end := pole + up * (0.04 * s) + ldir * (0.75 * s)
		rl.DrawLine3D(l_start, l_end, cyan_glow)

		pad_b := pole + up * (0.01 * s) + ldir * (0.75 * s)
		pad_t := pole + up * (0.07 * s) + ldir * (0.75 * s)
		rl.DrawCylinderEx(pad_b, pad_t, 0.13 * s, 0.11 * s, 8, gunmetal)
	}

	// Staging pylons with alternating ambulance pulsating hazard lights
	st_l := pole + up * (0.65 * s) - rl.Vector3{0.35 * s, 0, 0}
	st_r := pole + up * (0.65 * s) + rl.Vector3{0.35 * s, 0, 0}
	rl.DrawCylinderEx(pole - rl.Vector3{0.35 * s, 0, 0}, st_l, 0.02 * s, 0.015 * s, 6, gunmetal)
	rl.DrawCylinderEx(pole + rl.Vector3{0.35 * s, 0, 0}, st_r, 0.02 * s, 0.015 * s, 6, gunmetal)
	draw_ambulance_hazard_lights(st_l, st_r, s)

	rl.DrawCylinderEx(pole + up * (0.02 * s), pole + up * (0.03 * s), 0.38 * s, 0.38 * s, 16, cyan_glow)
	rl.DrawCylinderEx(pole + up * (0.18 * s), pole + up * (0.19 * s), 0.34 * s, 0.34 * s, 16, cyan_glow)

	pulse := 0.70 + 0.30 * math.sin(laser_anim_time * 3.5)
	rl.DrawSphereWires(pole + up * (0.45 * s), 0.85 * s, 6, 10, rl.Fade(cyan_glow, pulse * 0.45))
	rl.DrawCylinderEx(pole + up * (0.035 * s), pole + up * (0.045 * s), 0.95 * s, 0.95 * s, 24, rl.Fade(cyan_glow, 0.55))

	prog: f32 = 0.0
	if ORBITAL_DEFENSE_BUILD_TIME > 0 {
		prog = clamp(orbital_defense_progress[planet_idx] / ORBITAL_DEFENSE_BUILD_TIME, 0.05, 0.95)
	}
	ring_y := 0.08 + prog * 0.70
	rl.DrawCylinderEx(pole + up * (ring_y * s), pole + up * ((ring_y + 0.015) * s), 0.65 * s * (1.05 - prog * 0.3), 0.65 * s * (1.05 - prog * 0.3), 20, mint_core)

	spark_ang := laser_anim_time * 6.5 + f32(planet_idx) * 2.0
	spark_pt := pole + up * (ring_y * s) + rl.Vector3{math.cos(spark_ang) * 0.45 * s, 0, math.sin(spark_ang) * 0.45 * s}
	spark_target := pole + up * (0.15 * s)
	rl.DrawLine3D(spark_pt, spark_target, rl.Color{255, 255, 200, 255})
	rl.DrawSphere(spark_pt, 0.045 * s, rl.Color{255, 255, 220, 255})
}
