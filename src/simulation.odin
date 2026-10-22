package main

import "core:math"
import "core:time"
import rl "vendor:raylib"

initialize_game :: proc() {
	planet_unit_cache_dirty = true
	auto_build_mode = .OFF
	auto_build_last_mode = .MINERS
	autobuild_retry_timer = 0
	base_counts = {}
	base_counts[EARTH] = STARTING_EARTH_BASES
	refinery_built = {}
	refinery_built[EARTH] = STARTING_EARTH_REFINERY
	orbital_defense_level = {}
	orbital_defense_level[EARTH] = STARTING_EARTH_ORBITAL_DEFENSE
	orbital_defense_level[ENEMY_HOME] = STARTING_HQ_ORBITAL_DEFENSE
	orbital_defense_hp = {}
	orbital_defense_hp[EARTH] = orbital_defense_max_hp(EARTH)
	orbital_defense_hp[ENEMY_HOME] = orbital_defense_max_hp(ENEMY_HOME)
	orbital_defense_ammo = {}
	orbital_defense_ammo[EARTH] = ORBITAL_DEFENSE_START_AMMO
	orbital_defense_ammo[ENEMY_HOME] = ORBITAL_DEFENSE_AMMO_MAX
orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_ammo_building = {}
	orbital_defense_ammo_progress = {}
	orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_elevation[EARTH] = ORBITAL_DEFENSE_IDLE_ELEV
	orbital_defense_elevation[ENEMY_HOME] = ORBITAL_DEFENSE_IDLE_ELEV
	enemy_base_hp = GARRISON_BASE_HP
	unit_count = 0
	for _ in 0..<STARTING_EARTH_MINERS {
		spawn_unit(.MINING, EARTH)
	}
	for i in 0..<STARTING_EARTH_COMBAT {
		angle := f32(i) * (2 * math.PI / f32(max(1, STARTING_EARTH_COMBAT)))
		pos := orbit_pos(planets[EARTH].position, planets[EARTH].radius, angle)
		units[unit_count] = Unit{
			kind = .COMBAT,
			state = .GUARDING,
			position = pos,
			home_planet = EARTH,
			affiliation = EARTH,
			target_planet = EARTH,
			orbit_angle = angle,
		}
		unit_count += 1
	}
	generate_stars()
	for p in 0..<SECTOR_COUNT {
		if p == EARTH { continue }
		spawn_garrison(p, GARRISON_FIGHTERS[p], GARRISON_MINERS[p])
	}
	combat_nebula_intensity[ENEMY_HOME] = 0.65
}

reset_world :: proc() {
	unit_count = 0
	for i := 0; i < MAX_UNITS; i += 1 {
		units[i] = {}
		selected_units[i] = false
	}
	for p in 0..<SECTOR_COUNT {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
		combat_vision_timer[p] = 0
	}
	enemy_base_hp = GARRISON_BASE_HP
	base_counts = {}
	base_counts[EARTH] = STARTING_EARTH_BASES
	base_build_planet = -1
	base_build_progress = 0
	refinery_built = {}
	refinery_built[EARTH] = STARTING_EARTH_REFINERY
	refinery_building = {}
	refinery_progress = {}
	orbital_defense_level = {}
	orbital_defense_building = {}
	orbital_defense_progress = {}
	orbital_defense_hp = {}
	orbital_defense_angle = {}
	for p in 0..<SECTOR_COUNT {
		orbital_defense_elevation[p] = ORBITAL_DEFENSE_IDLE_ELEV
	}
	orbital_defense_wave_kills = {}
	orbital_defense_reset_timer = {}
	orbital_defense_fire_timer = {}
	orbital_defense_ammo = {}
	orbital_defense_ammo_building = {}
	orbital_defense_ammo_progress = {}
	orbital_defense_ammo_pending_count = {}
orbital_defense_ammo_pending_kills = {}
	orbital_defense_blasts = {}
	construction_seq_counter = 0
	refinery_build_order = {}
	orbital_defense_build_order = {}
	base_build_order = {}
	minerals = 350
	mineral_accumulator = 0
	enemy_wave_timer = 0
	wave_started = false
	minor_wave_timer = 0
	selected_planet = EARTH
	production = {}
	pending_count = {}
	last_known_intel = {}
	intel_recorded = {}
	laser_anim_time = 0
	combat_nebula_intensity = {}
	minor_wave_source_nebula_intensity = {}
	earth_industry_intensity = 0
	earth_industry_level = 0
	drone_speed_level = 0
	earth_rally = NO_RALLY
	auto_build_mode = .OFF
	auto_build_last_mode = .MINERS
	autobuild_retry_timer = 0
	planet_unit_cache_dirty = true
	victory = false
	defeated = false
	game_paused = false
	controls_overlay_open = false
	in_start_menu = false
	hud_save_notification_timer = 0
	save_feedback_timer = 0
	last_unit_clicked_index = -1
	last_unit_clicked_planet = -1
	last_unit_click_time = {}
	last_row_clicked_kind = -1
	last_row_clicked_planet = -1
	last_row_click_time = {}
	rl.SetRandomSeed(7)
}

spawn_garrison :: proc(p, fighters, miners: int) {
	for i in 0..<fighters {
		angle := f32(i) * (2 * math.PI / f32(fighters))
		units[unit_count] = Unit{
			kind = .COMBAT, state = .GUARDING, position = orbit_pos(sector_pos(p), sector_radius(p), angle),
			home_planet = p, affiliation = p, target_planet = p,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
	for i in 0..<miners {
		angle := f32(i) * (2 * math.PI / f32(miners)) + 0.3
		units[unit_count] = Unit{
			kind = .MINING, state = .GUARDING, position = orbit_pos(sector_pos(p), sector_radius(p), angle),
			home_planet = p, affiliation = p, target_planet = p,
			enemy = true, orbit_angle = angle,
		}
		unit_count += 1
	}
}

sector_pos :: proc(s: int) -> rl.Vector3 {
	if s == ENEMY_HOME { return ENEMY_HQ_POSITION }
	return planets[s].position
}

sector_radius :: proc(s: int) -> f32 {
	if s == ENEMY_HOME { return ENEMY_HQ_RADIUS }
	return planets[s].radius
}

orbit_pos :: proc(center: rl.Vector3, radius, angle: f32) -> rl.Vector3 {
	return {center.x + math.cos(angle) * (radius + 1.5), center.y + 1.0, center.z + math.sin(angle) * (radius + 1.5)}
}

update_camera :: proc(dt: f32) {
	direction := rl.Vector3{}
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) { direction.z -= 1 }
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) { direction.z += 1 }
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { direction.x -= 1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { direction.x += 1 }
	if rl.Vector3Length(direction) > 0 {
		direction = rl.Vector3Normalize(direction)
		camera_target.x += direction.x * dt * 15
		camera_target.z += direction.z * dt * 15
	}
	zoom := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.MINUS) { zoom -= dt * 3 }
	if rl.IsKeyDown(.E) || rl.IsKeyDown(.EQUAL) { zoom += dt * 3 }
	zoom_y := camera.position.y - zoom * 2.2
	zoom_y = clamp(zoom_y, 15, 200)
	camera.position.x = camera_target.x
	camera.position.y = zoom_y
	camera.position.z = camera_target.z + camera.position.y * 1.0
	camera.target = camera_target
	camera.up = {0, 1, 0}
}

update_input :: proc() {
	if rl.IsKeyPressed(.ESCAPE) { cancel_last_queued() }
	if rl.IsKeyPressed(.M) {
		if shift_down() && can_build_5_miners() {
			queue_5_miners()
		} else {
			queue_unit(.MINING)
		}
	}
	if rl.IsKeyPressed(.C) {
		if shift_down() && can_build_5_combat() {
			queue_5_combat()
		} else {
			queue_unit(.COMBAT)
		}
	}
	if !ctrl_down() && rl.IsKeyPressed(.N) {
		if can_build_5_miners() {
			queue_5_miners()
		}
	}
	if rl.IsKeyPressed(.X) {
		if can_build_5_combat() {
			queue_5_combat()
		}
	}
	if rl.IsKeyPressed(.T) && can_use_autobuilder() {
		toggle_autobuild_mode()
	}
	if rl.IsKeyPressed(.U) { purchase_drone_speed_upgrade() }
	if rl.IsKeyPressed(.B) {
		if selected_planet != EARTH && selected_planet != ENEMY_HOME && can_build_refinery(selected_planet) {
			start_refinery_construction(selected_planet)
		}
	}
	if orbital_defense_key_pressed() {
		trigger_selected_orbital_defense()
	}
	if rl.IsKeyPressed(.SPACE) { select_earth() }
	if group := squad_key_pressed(); group > 0 {
		if shift_down() { save_squad(group) } else { recall_squad(group) }
	}
	if ctrl_down() && rl.IsKeyPressed(.N) { spawn_enemy_wave() }
	if rl.IsKeyPressed(.F5) {
		if save_game() {
			hud_save_notification_timer = 2.0
		}
	}
	mouse := ui_mouse()
	panel_x := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mouse, controls_button_rect()) {
			last_unit_clicked_index = -1
			open_controls_overlay()
			return
		}
		if mouse.x >= panel_x {
			inspector_drag_start = mouse
			inspector_drag_active = true
		} else {
			last_unit_clicked_index = -1
			if btn_p := pick_conquered_planet_overlay_ammo_button(mouse); btn_p >= 0 {
				selected_planet = btn_p
				if can_build_orbital_ammo(btn_p) {
					start_orbital_ammo_construction(btn_p)
				}
			} else if row_p, row_kind, on_plus := pick_overlay_drone_row(mouse); row_p >= 0 {
				if on_plus {
					selected_planet = row_p
					queue_unit_on_earth(row_kind)
				} else {
					click_overlay_drone_row(row_p, row_kind)
				}
			} else if planet := pick_planet(mouse); planet >= 0 {
				selected_planet = planet
			} else if ov_p := pick_conquered_planet_overlay(mouse); ov_p >= 0 {
				selected_planet = ov_p
			} else if hq_picked(mouse) {
				selected_planet = ENEMY_HOME
			} else if !ctrl_down() {
				clear_selection()
			}
		}
	} else if rl.IsMouseButtonReleased(.LEFT) && inspector_drag_active {
		inspector_drag_active = false
		handle_inspector_release(mouse, panel_x)
	}
	if rl.IsMouseButtonPressed(.RIGHT) && mouse.x < panel_x {
		if planet := pick_planet(mouse); planet >= 0 {
			handle_planet_right_click(planet)
		} else if ov_p := pick_conquered_planet_overlay(mouse); ov_p >= 0 {
			handle_planet_right_click(ov_p)
		} else if hq_picked(mouse) {
			handle_planet_right_click(ENEMY_HOME)
		}
	}
}

ctrl_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
}

earth_camera_offset_x :: proc() -> f32 {
	screen_h := f32(ui_screen_h() > 0 ? ui_screen_h() : 760)
	zoom_y := camera.position.y > 0 ? camera.position.y : CAMERA_START_Y
	return f32(SCREEN_PANEL_WIDTH) * zoom_y * (2.0 - math.sqrt(f32(2.0))) / screen_h
}

center_camera_on_earth :: proc() {
	camera_target = planets[EARTH].position
	camera_target.x += earth_camera_offset_x()
	camera.position.x = camera_target.x
	camera.position.z = camera_target.z + camera.position.y * 1.0
	camera.target = camera_target
}

select_earth :: proc() {
	if selected_planet == EARTH {
		center_camera_on_earth()
	} else {
		selected_planet = EARTH
		last_unit_clicked_index = -1
	}
}

squad_key_pressed :: proc() -> int {
	for k in rl.KeyboardKey.ONE..=rl.KeyboardKey.NINE {
		if rl.IsKeyPressed(k) { return int(k) - int(rl.KeyboardKey.ONE) + 1 }
	}
	return 0
}

clear_selection :: proc() {
	for i := 0; i < MAX_UNITS; i += 1 { selected_units[i] = false }
}

handle_inspector_click :: proc(mouse: rl.Vector2, panel_x: f32) {
	if selected_planet == EARTH {
		if base_button_visible() && rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, SECTION_TOP, PANEL_CONTENT_W, BASE_BTN_H}) {
			last_unit_clicked_index = -1
			start_base_construction()
			return
		}
		if rl.CheckCollisionPointRec(mouse, orbital_defense_button_rect(panel_x, EARTH)) {
			last_unit_clicked_index = -1
			if can_build_orbital_defense(EARTH) {
				start_orbital_defense_construction(EARTH)
			}
			return
		}
		orders_y := f32(production_orders_y())
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			last_unit_clicked_index = -1
			queue_unit(.MINING)
			return
		}
		if rl.CheckCollisionPointRec(mouse, {panel_x + PANEL_PAD_X + BUILD_BTN_W + BTN_GAP, orders_y, BUILD_BTN_W, BUILD_BTN_H}) {
			last_unit_clicked_index = -1
			queue_unit(.COMBAT)
			return
		}
		if base_counts[EARTH] >= MAX_BASES {
			off_rect, miner_rect, combat_rect := autobuild_radio_rects(panel_x)
			if rl.CheckCollisionPointRec(mouse, off_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.OFF)
				return
			}
			if rl.CheckCollisionPointRec(mouse, miner_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.MINERS)
				return
			}
			if rl.CheckCollisionPointRec(mouse, combat_rect) {
				last_unit_clicked_index = -1
				set_autobuild_mode(.COMBAT)
				return
			}
			if rl.CheckCollisionPointRec(mouse, queue_5_miner_button_rect(panel_x)) {
				last_unit_clicked_index = -1
				queue_5_miners()
				return
			}
			if rl.CheckCollisionPointRec(mouse, queue_5_combat_button_rect(panel_x)) {
				last_unit_clicked_index = -1
				queue_5_combat()
				return
			}
		}
		if !drone_speed_maxed() && rl.CheckCollisionPointRec(mouse, drone_speed_button_rect(panel_x)) {
			last_unit_clicked_index = -1
			purchase_drone_speed_upgrade()
			return
		}
		for slot := 0; slot < queued_count(EARTH); slot += 1 {
			if rl.CheckCollisionPointRec(mouse, queue_slot_rect(panel_x, slot)) {
				last_unit_clicked_index = -1
				cancel_queued_at(EARTH, slot)
				return
			}
		}
	} else if selected_planet >= 0 && selected_planet < PLANET_COUNT && selected_planet != ENEMY_HOME {
		if can_build_refinery(selected_planet) && rl.CheckCollisionPointRec(mouse, refinery_button_rect(panel_x)) {
			last_unit_clicked_index = -1
			start_refinery_construction(selected_planet)
			return
		}
		if rl.CheckCollisionPointRec(mouse, orbital_defense_button_rect(panel_x, selected_planet)) {
			last_unit_clicked_index = -1
			if can_build_orbital_defense(selected_planet) {
				start_orbital_defense_construction(selected_planet)
			}
			return
		}
	}
	if click_unit_tiles(mouse, panel_x, .MINING) || click_unit_tiles(mouse, panel_x, .COMBAT) { return }
	last_unit_clicked_index = -1
	if !ctrl_down() { clear_selection() }
}

handle_inspector_release :: proc(mouse: rl.Vector2, panel_x: f32) {
	if rl.Vector2Distance(mouse, inspector_drag_start) < 4 {
		handle_inspector_click(mouse, panel_x)
		return
	}
	box_select(mouse, panel_x)
}

box_select :: proc(mouse: rl.Vector2, panel_x: f32) {
	last_unit_clicked_index = -1
	if ghost_view() { return }
	rect := rect_between(inspector_drag_start, mouse)
	replace := !ctrl_down() && !shift_down()
	if replace { clear_selection() }
	m_ord := 0
	c_ord := 0
	y_mining := unit_tile_y(.MINING)
	y_combat := unit_tile_y(.COMBAT)
	for i := 0; i < unit_count; i += 1 {
		kind := units[i].kind
		if !unit_in_roster(i, kind) { continue }
		ord := kind == .MINING ? m_ord : c_ord
		y := kind == .MINING ? y_mining : y_combat
		if kind == .MINING { m_ord += 1 } else { c_ord += 1 }
		tile := unit_tile_rect(panel_x, y, ord)
		if rl.CheckCollisionRecs(tile, rect) {
			if ctrl_down() { selected_units[i] = !selected_units[i] } else { selected_units[i] = true }
		}
	}
}

rect_between :: proc(a, b: rl.Vector2) -> rl.Rectangle {
	return rl.Rectangle{min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}
}

shift_down :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
}

click_unit_tiles :: proc(mouse: rl.Vector2, panel_x: f32, kind: Unit_Type) -> bool {
	if ghost_view() { return false }
	ordinal := 0
	y := unit_tile_y(kind)
	now := time.tick_now()
	for i := 0; i < unit_count; i += 1 {
		if !unit_in_roster(i, kind) { continue }
		if rl.CheckCollisionPointRec(mouse, unit_tile_rect(panel_x, y, ordinal)) {
			is_double_click := false
			if last_unit_clicked_index == i && last_unit_clicked_planet == selected_planet {
				elapsed := time.duration_seconds(time.tick_diff(last_unit_click_time, now))
				if elapsed >= 0 && elapsed <= DOUBLE_CLICK_TIME {
					is_double_click = true
				}
			}

			if is_double_click {
				last_unit_clicked_index = -1
				if !ctrl_down() {
					clear_selection()
				}
				for j := 0; j < unit_count; j += 1 {
					if unit_in_roster(j, kind) {
						selected_units[j] = true
					}
				}
			} else {
				last_unit_clicked_index = i
				last_unit_clicked_planet = selected_planet
				last_unit_click_time = now
				if !ctrl_down() {
					clear_selection()
					selected_units[i] = true
				} else {
					selected_units[i] = !selected_units[i]
				}
			}
			return true
		}
		ordinal += 1
	}
	return false
}

click_overlay_drone_row :: proc(p: int, kind: Unit_Type) {
	selected_planet = p
	now := time.tick_now()
	is_double_click := false
	if last_row_clicked_kind == int(kind) && last_row_clicked_planet == p {
		elapsed := time.duration_seconds(time.tick_diff(last_row_click_time, now))
		is_double_click = elapsed >= 0 && elapsed <= DOUBLE_CLICK_TIME
	}
	if !is_double_click {
		last_row_clicked_kind = int(kind)
		last_row_clicked_planet = p
		last_row_click_time = now
		return
	}
	last_row_clicked_kind = -1
	if !ctrl_down() { clear_selection() }
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.enemy || u.kind != kind { continue }
		owner := kind == .MINING ? u.target_planet : u.affiliation
		if owner == p { selected_units[i] = true }
	}
}

update_combat_vision :: proc(dt: f32) {
	for p in 0..<SECTOR_COUNT {
		if combat_vision_timer[p] > 0 {
			combat_vision_timer[p] = max(combat_vision_timer[p] - dt, 0)
		}
	}
}

remove_unit_at :: proc(index: int) {
	if last_unit_clicked_index == index {
		last_unit_clicked_index = -1
	} else if last_unit_clicked_index > index {
		last_unit_clicked_index -= 1
	}
	for i := index; i < unit_count - 1; i += 1 {
		units[i] = units[i + 1]
		selected_units[i] = selected_units[i + 1]
	}
	unit_count -= 1
	planet_unit_cache_dirty = true
}

handle_planet_right_click :: proc(planet: int) {
	if selection_count() > 0 {
		issue_group_order(planet)
	} else if selected_planet == EARTH {
		set_earth_rally(planet)
	}
}

issue_group_order :: proc(planet: int) {
	for i := 0; i < unit_count; i += 1 {
		if !selected_units[i] { continue }
		if units[i].kind == .MINING && planet == ENEMY_HOME { continue }
		units[i].target_planet = planet
		units[i].affiliation = planet
		units[i].progress = 0
		units[i].build_target = .NONE
		units[i].mining_active = false
		if units[i].kind == .MINING {
			units[i].state = .TRANSIT
		} else {
			if distance(units[i].position, sector_pos(planet)) < sector_radius(planet) + 1.5 {
				units[i].state = .GUARDING
			} else {
				units[i].state = .TRANSIT
			}
		}
	}
}

update_units :: proc(dt: f32) {
	update_mining_income(dt)
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT {
			update_combat(u, dt)
		} else {
			update_miner(u, i, dt)
		}
	}
	planet_unit_cache_dirty = true
}

refresh_planet_unit_cache :: proc() {
	planet_miner_counts = {}
	planet_combat_counts = {}
	planet_mining_miners = {}
	for i in 0..<unit_count {
		u := &units[i]
		if u.enemy { continue }
		if u.kind == .MINING {
			target := u.target_planet
			if target == EARTH || (target < 0 && u.affiliation == EARTH) {
				planet_miner_counts[EARTH] += 1
				if u.state != .CONSTRUCTING {
					planet_mining_miners[EARTH] += 1
				}
			} else if target >= 0 && target < PLANET_COUNT {
				planet_miner_counts[target] += 1
				if u.state != .CONSTRUCTING {
					planet_mining_miners[target] += 1
				}
			}
		} else if u.kind == .COMBAT {
			p := u.affiliation
			if p >= 0 && p < PLANET_COUNT {
				planet_combat_counts[p] += 1
			}
		}
	}
	planet_unit_cache_dirty = false
}

planet_miner_drone_count :: proc(p: int) -> int {
	if p < 0 || p >= PLANET_COUNT { return 0 }
	if planet_unit_cache_dirty { refresh_planet_unit_cache() }
	return planet_miner_counts[p]
}

planet_combat_drone_count :: proc(p: int) -> int {
	if p < 0 || p >= PLANET_COUNT { return 0 }
	if planet_unit_cache_dirty { refresh_planet_unit_cache() }
	return planet_combat_counts[p]
}

has_player_structure :: proc(p: int) -> bool {
	if p < 0 || p >= PLANET_COUNT { return false }
	if refinery_built[p] || refinery_building[p] { return true }
	if orbital_defense_level[p] > 0 || orbital_defense_building[p] { return true }
	if base_counts[p] > 0 || base_build_planet == p { return true }
	return false
}

has_vision :: proc(p: int) -> bool {
	if p < 0 || p >= SECTOR_COUNT { return false }
	if p == EARTH { return true }
	if combat_vision_timer[p] > 0 { return true }
	if has_player_structure(p) { return true }
	r := sector_radius(p) + 2.0
	r2 := r * r
	sp := sector_pos(p)
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.enemy { continue }
		dx := u.position.x - sp.x
		dy := u.position.y - sp.y
		dz := u.position.z - sp.z
		if dx*dx + dy*dy + dz*dz <= r2 {
			return true
		}
	}
	return false
}

is_concealed :: proc(u: ^Unit) -> bool {
	if !u.enemy { return false }
	p := u.affiliation
	if u.state == .TRANSIT { p = u.target_planet }
	return !has_vision(p)
}

set_earth_rally :: proc(target: int) {
	if target == EARTH { earth_rally = NO_RALLY } else if target != ENEMY_HOME { earth_rally = target }
}

rally_flag_planet :: proc() -> int { return earth_rally }

draw_rally_flag :: proc() {
	if earth_rally == NO_RALLY { return }
	p := planets[earth_rally]
	base := rl.Vector3{p.position.x, p.position.y + p.radius, p.position.z}
	top := rl.Vector3{p.position.x, p.position.y + p.radius + 3.4, p.position.z}
	rl.DrawCylinderEx(base, top, 0.07, 0.07, 6, rl.Color{205, 208, 218, 255})
	tip := rl.Vector3{p.position.x + 1.7, top.y - 0.55, p.position.z}
	rl.DrawTriangle3D({p.position.x, top.y, p.position.z}, {p.position.x, top.y - 1.3, p.position.z}, tip, SCIFI_GREEN)
	rl.DrawTriangle3D({p.position.x, top.y - 1.3, p.position.z}, {p.position.x, top.y, p.position.z}, tip, SCIFI_GREEN)
}

zoom_percent :: proc() -> int {
	return int(clamp((200 - camera.position.y) / 185.0 * 100.0, 0, 100))
}

hq_picked :: proc(mouse: rl.Vector2) -> bool {
	ray := ui_screen_to_world_ray(mouse)
	oc := rl.Vector3{ray.position.x - ENEMY_HQ_POSITION.x, ray.position.y - ENEMY_HQ_POSITION.y, ray.position.z - ENEMY_HQ_POSITION.z}
	b := rl.Vector3DotProduct(oc, ray.direction)
	c := rl.Vector3DotProduct(oc, oc) - ENEMY_HQ_RADIUS * ENEMY_HQ_RADIUS
	disc := b*b - c
	if disc < 0 { return false }
	return -b - math.sqrt(disc) >= 0
}

pick_planet :: proc(mouse: rl.Vector2) -> int {
	ray := ui_screen_to_world_ray(mouse)
	closest := f32(999999)
	hit := -1
	for p := 0; p < PLANET_COUNT; p += 1 {
		planet := planets[p]
		oc := rl.Vector3{ray.position.x - planet.position.x, ray.position.y - planet.position.y, ray.position.z - planet.position.z}
		b := rl.Vector3DotProduct(oc, ray.direction)
		c := rl.Vector3DotProduct(oc, oc) - planet.radius * planet.radius
		disc := b*b - c
		if disc < 0 { continue }
		t := -b - math.sqrt(disc)
		if t >= 0 && t < closest { closest = t; hit = p }
	}
	return hit
}

distance :: rl.Vector3Distance
