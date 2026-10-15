package main

import "core:c"
import "core:math"
import "core:mem"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

draw_world :: proc() {
	viewport_w := rl.GetScreenWidth() - SCREEN_PANEL_WIDTH
	// Stars and combat nebulae project to screen space before the 3D pass,
	// so they sit in the background behind every planet and fortress.
	draw_starfield()
	draw_combat_nebulae()
	rl.BeginMode3D(camera)
	for p in 0..<PLANET_COUNT {
		planet := planets[p]
		lit := has_vision(p)
		surface := planet.color
		if !lit {
			// Fog of war: planets the player has no presence at render shadowed.
			surface = rl.Color{58, 62, 74, 255}
		}
		if planet_visuals_ready {
			// Textured, slowly spinning sphere; fogged worlds tint grey.
			tint := rl.WHITE
			if !lit { tint = rl.Color{110, 116, 130, 255} }
			rl.DrawModelEx(planet_models[p], planet.position, {0, 1, 0}, planet_spin[p] * 57.29578, {1, 1, 1}, tint)
		} else {
			rl.DrawSphere(planet.position, planet.radius, surface)
		}
		// Atmosphere shell: faint planet-tinted halo for depth.
		atmo := rl.Color{planet.color.r, planet.color.g, planet.color.b, 255}
		if !lit { atmo = rl.Color{70, 76, 90, 255} }
		rl.DrawSphereEx(planet.position, planet.radius * 1.09, 12, 24, rl.Fade(atmo, 0.16))
		// Sun glint: small bright dot toward the fixed light direction.
		glint_dir := rl.Vector3Normalize({-0.45, 0.75, -0.35})
		glint_pos := planet.position + glint_dir * (planet.radius * 0.82)
		rl.DrawSphereEx(glint_pos, planet.radius * 0.10, 6, 8, rl.Color{255, 255, 255, 70})
		// Drone orbit path: faint ring showing the guard orbit.
		rl.DrawCircle3D(planet.position + {0, 1.0, 0}, planet.radius + 1.5, {0, 1, 0}, 90, rl.Fade(atmo, 0.30))
		// Saturn's rings: two tilted bands.
		if p == SATURN {
			ring_col := rl.Color{225, 205, 155, 255}
			if !lit { ring_col = rl.Color{70, 76, 90, 255} }
			rl.DrawCircle3D(planet.position, planet.radius * 1.55, {0.35, 1, 0.15}, 78, rl.Fade(ring_col, 0.55))
			rl.DrawCircle3D(planet.position, planet.radius * 1.95, {0.35, 1, 0.15}, 78, rl.Fade(ring_col, 0.30))
		}
		if p == selected_planet {
			pulse := 0.75 + 0.25 * math.sin(laser_anim_time * 3.0)
			// Concentric tactical rings with segmented arcs
			rl.DrawCircle3D(planet.position, planet.radius + 0.35, {0, 1, 0}, 90, rl.Fade(SCIFI_CYAN, pulse))
			rl.DrawCircle3D(planet.position, planet.radius + 0.70, {0, 1, 0}, 90, SCIFI_DIM)
			// Cardinal radial ticks
			for a in 0..<4 {
				ang := f32(a) * math.PI / 2.0 + laser_anim_time * 0.4
				p_in := planet.position + rl.Vector3{math.cos(ang) * (planet.radius + 0.35), 0, math.sin(ang) * (planet.radius + 0.35)}
				p_out := planet.position + rl.Vector3{math.cos(ang) * (planet.radius + 0.85), 0, math.sin(ang) * (planet.radius + 0.85)}
				rl.DrawLine3D(p_in, p_out, SCIFI_CYAN)
			}
		}
		// Orbital Defense: cyberpunk sand-colored Flak 88 battery on the planet surface at the north pole
		if orbital_defense_level[p] > 0 {
			draw_cyberpunk_flak88(p)
		} else if orbital_defense_building[p] {
			draw_cyberpunk_flak88_construction_site(p)
		}
	}
	// The enemy HQ fortress at Neptune's old orbit: layered battlestation -
	// dark red hull (bright once scouted), a dead grey husk once destroyed.
	hq_color := rl.Color{96, 34, 40, 255}
	hq_trim := rl.Color{150, 55, 62, 255}
	hq_glow := rl.Color{255, 90, 90, 255}
	if enemy_hq_destroyed() {
		hq_color = rl.Color{58, 60, 66, 255}
		hq_trim = rl.Color{80, 84, 94, 255}
		hq_glow = rl.Color{100, 105, 115, 255}
	} else if has_vision(ENEMY_HOME) {
		hq_color = rl.Color{205, 50, 58, 255}
		hq_trim = rl.Color{255, 120, 125, 255}
	}
	draw_hq_fortress(ENEMY_HQ_POSITION, hq_color, hq_trim, hq_glow)
	if selected_planet == ENEMY_HOME {
		rl.DrawCubeWiresV(ENEMY_HQ_POSITION, {11.2, 5.8, 11.2}, SCIFI_CYAN)
	}
	draw_rally_flag()

	// Drones render representationally per side and group: one drone
	// model per up-to-10 drones (ceil(count/10)), so a 5-drone wave in
	// transit shows as one drone and the 40-strong Jupiter garrison as
	// four. This applies in orbit / on-site and in transit (per target
	// planet). Rosters, tracking and selection still use the real unit list.
	sector_vis: [SECTOR_COUNT]bool
	for p in 0..<SECTOR_COUNT {
		sector_vis[p] = has_vision(p)
		world_sector_spots[p].pc = 0
		world_sector_spots[p].ec = 0
		world_sector_spots[p].pmc = 0
		world_sector_spots[p].emc = 0
	}

	transit_counts: [SECTOR_COUNT][2]int
	miner_transit_counts: [SECTOR_COUNT][2]int
	miner_return_counts: [SECTOR_COUNT][2]int

	// Pass 1: selection rings, stationed unit spots, and transit counts.
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if selected_units[i] {
			draw_selection_ring(u.position, 0.78)
		}
		if u.kind == .COMBAT {
			if u.state == .GUARDING {
				p := u.affiliation
				if p >= 0 && p < SECTOR_COUNT && sector_vis[p] {
					s := &world_sector_spots[p]
					if u.enemy {
						if s.ec < 256 { s.enemy_combat[s.ec] = u.position }
						s.ec += 1
					} else {
						if s.pc < 256 { s.player_combat[s.pc] = u.position }
						s.pc += 1
					}
				}
			} else if u.state == .TRANSIT {
				p := u.target_planet
				if p >= 0 && p < SECTOR_COUNT {
					transit_counts[p][u.enemy ? 1 : 0] += 1
				}
			}
		} else if u.kind == .MINING {
			p := miner_stationed_planet(u)
			if p >= 0 && p < SECTOR_COUNT && sector_vis[p] {
				s := &world_sector_spots[p]
				if u.enemy {
					if s.emc < 256 { s.enemy_miners[s.emc] = u.position }
					s.emc += 1
				} else {
					if s.pmc < 256 { s.player_miners[s.pmc] = u.position }
					s.pmc += 1
				}
			} else if u.target_planet >= 0 && u.target_planet < SECTOR_COUNT {
				side := u.enemy ? 1 : 0
				if u.state == .TRANSIT {
					miner_transit_counts[u.target_planet][side] += 1
				} else if u.state == .RETURNING {
					miner_return_counts[u.target_planet][side] += 1
				}
			}
		}
	}

	// Draw stationed drones and lasers per sector.
	for p in 0..<SECTOR_COUNT {
		if !sector_vis[p] { continue }
		s := &world_sector_spots[p]
		sp := sector_pos(p)
		for d in 0..<rep_count(s.pc) { draw_fighter_drone(s.player_combat[d], false, drone_heading(s.player_combat[d], sp)) }
		for d in 0..<rep_count(s.ec) { draw_fighter_drone(s.enemy_combat[d], true, drone_heading(s.enemy_combat[d], sp)) }
		draw_combat_lasers(p, s.player_combat[:], s.enemy_combat[:], s.pc, s.ec, s.player_miners[:], s.enemy_miners[:], s.pmc, s.emc)
		for d in 0..<rep_count(s.emc) { draw_miner_drone(s.enemy_miners[d], true, drone_heading(s.enemy_miners[d], sp)) }
	}

	vis_combat: [SECTOR_COUNT][2]int
	vis_miner_tr: [SECTOR_COUNT][2]int
	vis_miner_ret: [SECTOR_COUNT][2]int
	drawn_combat: [SECTOR_COUNT][2]int
	drawn_miner_tr: [SECTOR_COUNT][2]int
	drawn_miner_ret: [SECTOR_COUNT][2]int

	for p in 0..<SECTOR_COUNT {
		for side in 0..<2 {
			if side == 1 && !sector_vis[p] { continue }
			vis_combat[p][side] = max(min(transit_counts[p][side], 10), rep_count(transit_counts[p][side]))
			vis_miner_tr[p][side] = rep_count(miner_transit_counts[p][side])
			vis_miner_ret[p][side] = rep_count(miner_return_counts[p][side])
		}
	}

	// Pass 2: draw transit units and transit lines in a single pass.
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.state == .TRANSIT {
			p := u.target_planet
			if p >= 0 && p < SECTOR_COUNT {
				side := u.enemy ? 1 : 0
				can_see := !u.enemy || sector_vis[p]
				if u.kind == .COMBAT {
					if can_see && drawn_combat[p][side] < vis_combat[p][side] {
						drawn_combat[p][side] += 1
						to := sector_pos(p)
						heading := to - u.position
						draw_fighter_drone(u.position, u.enemy, heading)
						if rl.Vector3Length(heading) > 0.001 {
							trail := u.position - rl.Vector3Normalize(heading) * 1.2
							rl.DrawLine3D(u.position, trail, rl.Fade(u.enemy ? rl.RED : SCIFI_CYAN, 0.6))
						}
					}
				} else if u.kind == .MINING {
					if can_see && drawn_miner_tr[p][side] < vis_miner_tr[p][side] {
						drawn_miner_tr[p][side] += 1
						to := sector_pos(p)
						heading := to - u.position
						draw_miner_drone(u.position, u.enemy, heading)
					}
				}
				if can_see {
					line_col := u.enemy ? rl.Color{255, 60, 75, 70} : rl.Color{0, 225, 255, 90}
					rl.DrawLine3D(u.position, sector_pos(p), line_col)
				}
			}
		} else if u.state == .RETURNING {
			p := u.target_planet
			if p >= 0 && p < SECTOR_COUNT && u.kind == .MINING {
				side := u.enemy ? 1 : 0
				if (!u.enemy || sector_vis[p]) && drawn_miner_ret[p][side] < vis_miner_ret[p][side] {
					drawn_miner_ret[p][side] += 1
					to := planets[EARTH].position
					heading := to - u.position
					draw_miner_drone(u.position, u.enemy, heading)
				}
			}
		}
	}
	draw_refinery_mineral_beams()
	draw_orbital_defense_blasts()
	rl.EndMode3D()
	// Luminous industrial manufacturing lights on Earth when units are being created
	draw_earth_industry_lights()
	if in_start_menu {
		return
	}

	// Overlay labels and optical reticles anchored to 3D celestial positions.
	for p in 0..<PLANET_COUNT {
		pos := rl.GetWorldToScreen(planets[p].position, camera)
		if pos.x < f32(viewport_w) && pos.x > 0 && pos.y > 0 && pos.y < f32(rl.GetScreenHeight()) {
			label := planets[p].name
			if p == selected_planet {
				// Optical aim reticle over the selected planet
				draw_optical_reticle_2d(pos, planets[p].radius * 5.0, SCIFI_CYAN, label)
			} else {
				rl.DrawText(label, c.int(pos.x - 28 + 1), c.int(pos.y - planets[p].radius * 5 - 14 + 1), 14, rl.Color{0, 0, 0, 170})
				rl.DrawText(label, c.int(pos.x - 28), c.int(pos.y - planets[p].radius * 5 - 14), 14, SCIFI_TEXT)
			}
		}
	}
	// Enemy HQ label / reticle
	hq_screen := rl.GetWorldToScreen(ENEMY_HQ_POSITION, camera)
	if hq_screen.x < f32(viewport_w) && hq_screen.x > 0 && hq_screen.y > 0 && hq_screen.y < f32(rl.GetScreenHeight()) {
		hq_label: cstring = "ENEMY HQ"
		if enemy_hq_destroyed() { hq_label = "ENEMY HQ (DESTROYED)" }
		if selected_planet == ENEMY_HOME {
			draw_optical_reticle_2d(hq_screen, 28.0, SCIFI_RED, hq_label)
		} else {
			rl.DrawText(hq_label, c.int(hq_screen.x - 30), c.int(hq_screen.y - 26), 13, SCIFI_RED)
		}
	}

	// Conquered planet overlays (planetary defense level, miners current/cap, combat drone count)
	draw_conquered_planet_overlays(f32(viewport_w), f32(rl.GetScreenHeight()))

	// Top bar: minerals plus global MPS and drone speed upgrade level
	// Two-tier aerospace winged HUD dock (inspired by Star Fox Zero top-left UI)
	tl_dock_w: f32 = 400.0
	tl_dock_h: f32 = 50.0
	tl_rect := rl.Rectangle{f32(HUD_PAD), f32(HUD_PAD), tl_dock_w, tl_dock_h}
	draw_winged_panel_left(tl_rect, 6, 20, SCIFI_PANEL, SCIFI_CYAN)

	// Column 1: Minerals (static 104px column to fit up to 999999 minerals without shifting)
	col1_x: f32 = f32(HUD_PAD + 16)
	rl.DrawText("MINERALS", i32(col1_x), i32(HUD_PAD + 7), 10, SCIFI_MINT)
	min_val := rl.TextFormat("%d", minerals)
	rl.DrawText(min_val, i32(col1_x), i32(HUD_PAD + 20), 22, SCIFI_AMBER)

	// Divider 1 (completely static position)
	div1_x: f32 = col1_x + 104.0
	rl.DrawLineV({div1_x, HUD_PAD + 10}, {div1_x, HUD_PAD + 40}, SCIFI_DIM)
	draw_diamond(div1_x, HUD_PAD + 25, 2.5, SCIFI_CYAN)

	// Column 2: MPS (static 92px column)
	col2_x: f32 = div1_x + 16.0
	rl.DrawText("PRODUCTION", i32(col2_x), i32(HUD_PAD + 7), 10, SCIFI_MUTED)
	mps_val := rl.TextFormat("+%.1f/s", global_mps())
	rl.DrawText(mps_val, i32(col2_x), i32(HUD_PAD + 22), 17, SCIFI_CYAN)

	// Divider 2 (completely static position)
	div2_x: f32 = col2_x + 92.0
	rl.DrawLineV({div2_x, HUD_PAD + 10}, {div2_x, HUD_PAD + 40}, SCIFI_DIM)
	draw_diamond(div2_x, HUD_PAD + 25, 2.5, SCIFI_CYAN)

	// Column 3: Drone Speed (completely static position)
	col3_x: f32 = div2_x + 16.0
	rl.DrawText("DRONE SPEED", i32(col3_x), i32(HUD_PAD + 7), 10, SCIFI_MUTED)
	speed_val := rl.TextFormat("LVL %d/%d", drone_speed_level, DRONE_SPEED_UPGRADE_MAX)
	rl.DrawText(speed_val, i32(col3_x), i32(HUD_PAD + 24), 11, SCIFI_MINT)
	draw_segmented_meter({col3_x + 58, HUD_PAD + 24, 48, 12}, f32(drone_speed_level) / f32(DRONE_SPEED_UPGRADE_MAX), 5, SCIFI_MINT, SCIFI_DIM)

	// Save notification chip (if active)
	if hud_save_notification_timer > 0 {
		saved_lbl: cstring = "GAME SAVED"
		saved_w := f32(rl.MeasureText(saved_lbl, 11))
		saved_x := f32(viewport_w) - f32(HUD_PAD) - saved_w - 8
		draw_chamfered_panel({saved_x - 8, HUD_PAD + 12, saved_w + 16, 26}, 4, rl.Color{30, 20, 10, 240}, SCIFI_AMBER_DIM)
		rl.DrawText(saved_lbl, i32(saved_x), i32(HUD_PAD + 18), 11, SCIFI_AMBER)
	}

	// Bottom: standalone Controls button
	ctrl_rect := controls_button_rect()
	draw_button(ctrl_rect, "Controls", SCIFI_PANEL_SOLID, true)

	// Bottom right of viewport: telemetry readout (ALT, ZOOM, FPS) in plain white text
	telemetry_cam := rl.TextFormat("ALT %.0f   ZOOM %d%%   %d FPS", camera.position.y, zoom_percent(), rl.GetFPS())
	tel_font_size: i32 = 12
	tel_w := rl.MeasureText(telemetry_cam, tel_font_size)
	tel_x := i32(viewport_w) - tel_w - HUD_PAD
	tel_y := i32(ctrl_rect.y + (ctrl_rect.height - f32(tel_font_size)) / 2)
	rl.DrawText(telemetry_cam, tel_x, tel_y, tel_font_size, rl.WHITE)

	draw_squad_hud()
}


draw_hq_fortress :: proc(center: rl.Vector3, hull, trim, glow: rl.Color) {
	dark       := rl.Color{u8(f32(hull.r) * 0.46), u8(f32(hull.g) * 0.46), u8(f32(hull.b) * 0.46), 255}
	darker     := rl.Color{u8(f32(hull.r) * 0.25), u8(f32(hull.g) * 0.25), u8(f32(hull.b) * 0.25), 255}
	gunmetal   := rl.Color{24, 27, 34, 255}
	steel_mid  := rl.Color{48, 54, 64, 255}
	steel_lit  := rl.Color{135, 145, 162, 255}
	amber_warn := rl.Color{255, 140, 25, 255}

	destroyed := enemy_hq_destroyed() || enemy_base_hp[ENEMY_HOME] <= 0

	eff_glow := glow
	eff_amber := amber_warn
	if destroyed {
		eff_glow = rl.Color{55, 58, 64, 255}
		eff_amber = rl.Color{45, 48, 52, 255}
	}

	pulse_slow := 0.70 + 0.30 * math.sin(laser_anim_time * 3.0)
	pulse_fast := 0.60 + 0.40 * math.sin(laser_anim_time * 7.5)

	up := rl.Vector3{0, 1, 0}

	// 1. Ventral Keel & Fusion Core
	rl.DrawCylinderEx(center - up * 0.6, center - up * 1.5, 2.6, 1.9, 6, dark)
	rl.DrawCylinderEx(center - up * 1.5, center - up * 2.3, 1.9, 1.0, 6, gunmetal)

	reactor_col := rl.Fade(eff_glow, pulse_slow * 0.95)
	rl.DrawCylinderEx(center - up * 2.25, center - up * 2.35, 1.15, 1.15, 12, reactor_col)
	rl.DrawSphereEx(center - up * 2.45, 0.55 * pulse_slow + 0.12, 8, 12, reactor_col)

	for i in 0..<4 {
		ang := f32(i) * (math.PI / 2.0)
		fdir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		ftan := rl.Vector3{-fdir.z, 0, fdir.x}
		f_top := center - up * 1.0 + fdir * 1.7
		f_bot := center - up * 2.3 + fdir * 0.7
		rl.DrawCylinderEx(f_top, f_bot, 0.14, 0.06, 4, dark)
		rl.DrawLine3D(f_top + ftan * 0.08, f_bot + ftan * 0.08, eff_glow)
		rl.DrawLine3D(f_top - ftan * 0.08, f_bot - ftan * 0.08, eff_glow)
	}

	// 2. Main Bastion Citadel Platform (Layered Octagonal Hull)
	draw_oriented_box(center - up * 0.35, 3.2, 0.35, 3.2, {1, 0, 0}, up, {0, 0, 1}, dark)
	draw_oriented_box(center - up * 0.35, 2.26, 0.36, 2.26, {0.707, 0, 0.707}, up, {-0.707, 0, 0.707}, dark)

	draw_oriented_box(center + up * 0.35, 2.9, 0.35, 2.9, {1, 0, 0}, up, {0, 0, 1}, hull)
	draw_oriented_box(center + up * 0.35, 2.05, 0.36, 2.05, {0.707, 0, 0.707}, up, {-0.707, 0, 0.707}, hull)

	draw_oriented_box(center + up * 0.02, 3.25, 0.06, 3.25, {1, 0, 0}, up, {0, 0, 1}, trim)
	draw_oriented_box(center + up * 0.40, 3.02, 0.05, 3.02, {1, 0, 0}, up, {0, 0, 1}, eff_glow)

	for i in 0..<4 {
		ang := f32(i) * (math.PI / 2.0)
		cdir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		ctan := rl.Vector3{-cdir.z, 0, cdir.x}
		b_pos := center + up * 0.42 + cdir * 2.95
		draw_oriented_box(b_pos, 0.10, 0.26, 1.4, cdir, up, ctan, dark)
		draw_oriented_box(b_pos + up * 0.18, 0.08, 0.06, 1.2, cdir, up, ctan, trim)
		rl.DrawLine3D(b_pos - ctan * 1.3 - up * 0.15, b_pos + ctan * 1.3 - up * 0.15, eff_glow)

		// VLS missile silo cell grid on cardinal decks
		vls_center := center + up * 0.72 + cdir * 2.15
		draw_oriented_box(vls_center, 0.35, 0.02, 0.55, cdir, up, ctan, gunmetal)
		for vr in -1..=1 {
			for vc in 0..=1 {
				cell_pos := vls_center + ctan * (f32(vr) * 0.24) + cdir * (f32(vc) * 0.24 - 0.12)
				draw_oriented_box(cell_pos, 0.08, 0.025, 0.08, cdir, up, ctan, darker)
				rl.DrawSphere(cell_pos + up * 0.02, 0.035, eff_glow)
			}
		}
	}

	// 3. Four Outrigger Fighter Hangar Bastions
	for d_idx in 0..<4 {
		ang := f32(d_idx) * (math.PI / 2.0) + (math.PI / 4.0)
		b_dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		b_tan := rl.Vector3{-b_dir.z, 0, b_dir.x}

		boom_c := center + up * 0.25 + b_dir * 3.3
		draw_oriented_box(boom_c, 0.38, 0.22, 0.75, b_dir, up, b_tan, gunmetal)

		p1_s := center + up * 0.68 + b_dir * 2.0 + b_tan * 0.22
		p1_e := boom_c + up * 0.18 + b_dir * 0.75 + b_tan * 0.22
		rl.DrawCylinderEx(p1_s, p1_e, 0.05, 0.05, 6, steel_mid)
		rl.DrawLine3D(p1_s + up * 0.04, p1_e + up * 0.04, eff_glow)

		p2_s := center + up * 0.68 + b_dir * 2.0 - b_tan * 0.22
		p2_e := boom_c + up * 0.18 + b_dir * 0.75 - b_tan * 0.22
		rl.DrawCylinderEx(p2_s, p2_e, 0.05, 0.05, 6, steel_mid)
		rl.DrawLine3D(p2_s + up * 0.04, p2_e + up * 0.04, eff_glow)

		truss_s := center - up * 0.5 + b_dir * 2.2
		truss_e := boom_c - up * 0.12 + b_dir * 0.6
		rl.DrawCylinderEx(truss_s, truss_e, 0.12, 0.08, 6, dark)

		pod_c := center + up * 0.32 + b_dir * 4.6
		draw_oriented_box(pod_c, 0.65, 0.45, 0.85, b_dir, up, b_tan, hull)
		draw_oriented_box(pod_c + up * 0.25, 0.52, 0.12, 0.72, b_dir, up, b_tan, trim)
		draw_oriented_box(pod_c - up * 0.25, 0.52, 0.10, 0.72, b_dir, up, b_tan, dark)

		bay_face := pod_c + b_dir * 0.86
		draw_oriented_box(bay_face - b_dir * 0.08, 0.38, 0.24, 0.10, b_dir, up, b_tan, rl.Color{8, 10, 14, 255})
		rl.DrawLine3D(bay_face - b_dir * 0.4 - up * 0.08, bay_face + b_dir * 0.15 - up * 0.08, eff_glow)
		rl.DrawSphere(bay_face + b_dir * 0.05, 0.12, eff_glow)

		turret_pos := pod_c + up * 0.48
		rl.DrawCylinderEx(turret_pos, turret_pos + up * 0.14, 0.20, 0.18, 8, gunmetal)
		b1 := turret_pos + up * 0.16 + b_tan * 0.09
		b2 := turret_pos + up * 0.16 - b_tan * 0.09
		rl.DrawCylinderEx(b1, b1 + b_dir * 0.55, 0.038, 0.034, 6, steel_lit)
		rl.DrawCylinderEx(b2, b2 + b_dir * 0.55, 0.038, 0.034, 6, steel_lit)
		rl.DrawSphere(b1 + b_dir * 0.56, 0.032, eff_glow)
		rl.DrawSphere(b2 + b_dir * 0.56, 0.032, eff_glow)

		strobe_col := (d_idx % 2 == 0) ? eff_glow : eff_amber
		strobe_p   := (d_idx % 2 == 0) ? pulse_fast : (1.0 - pulse_fast)
		tip_l := pod_c + b_tan * 0.65 + b_dir * 0.75 + up * 0.32
		tip_r := pod_c - b_tan * 0.65 + b_dir * 0.75 + up * 0.32
		rl.DrawSphere(tip_l, 0.07, rl.Fade(strobe_col, strobe_p))
		rl.DrawSphere(tip_r, 0.07, rl.Fade(strobe_col, 1.0 - strobe_p))
	}

	// 4. Mid-Deck Superstructure & Command Citadel
	draw_oriented_box(center + up * 1.1, 1.9, 0.40, 2.1, {1, 0, 0}, up, {0, 0, 1}, dark)
	draw_oriented_box(center + up * 1.5, 1.5, 0.38, 1.7, {1, 0, 0}, up, {0, 0, 1}, hull)

	bridge_c := center + up * 1.65 + rl.Vector3{0.3, 0, 0}
	draw_oriented_box(bridge_c, 1.35, 0.12, 1.55, {1, 0, 0}, up, {0, 0, 1}, eff_glow)
	draw_oriented_box(bridge_c + up * 0.14, 1.45, 0.06, 1.65, {1, 0, 0}, up, {0, 0, 1}, trim)

	for s in -1..=1 {
		if s == 0 { continue }
		blister_p := center + up * 1.4 + rl.Vector3{0, 0, f32(s) * 1.65}
		draw_oriented_box(blister_p, 0.28, 0.26, 0.28, {1, 0, 0}, up, {0, 0, 1}, gunmetal)
		rl.DrawSphere(blister_p + rl.Vector3{0, 0.08, f32(s) * 0.22}, 0.12, eff_amber)
		rl.DrawCylinderEx(blister_p + up * 0.26, blister_p + up * 0.85, 0.02, 0.01, 4, steel_lit)
	}

	// 5. Integrated Level 10 Orbital Defense Battery
	battery_mount := center + up * 1.95 + rl.Vector3{0.3, 0, 0}
	rl.DrawCylinderEx(battery_mount, battery_mount + up * 0.28, 1.4, 1.3, 16, gunmetal)
	rl.DrawCylinderEx(battery_mount + up * 0.25, battery_mount + up * 0.29, 1.35, 1.35, 16, eff_glow)

	aim_az, aim_el := orbital_defense_aim(ENEMY_HOME)
	cur_az := aim_az
	cur_el := aim_el
	if destroyed || orbital_defense_hp[ENEMY_HOME] <= 0 {
		cur_el = -0.32
	}

	cos_az := math.cos(cur_az)
	sin_az := math.sin(cur_az)
	b_fwd   := rl.Vector3{cos_az, 0, sin_az}
	b_right := rl.Vector3{-sin_az, 0, cos_az}

	cos_el := math.cos(cur_el)
	sin_el := math.sin(cur_el)
	barrel_dir    := b_fwd * cos_el + up * sin_el
	barrel_normal := -b_fwd * sin_el + up * cos_el

	turret_c := battery_mount + up * 0.46
	draw_oriented_box(turret_c, 0.62, 0.26, 0.72, b_fwd, up, b_right, dark)
	draw_oriented_box(turret_c + up * 0.22, 0.50, 0.10, 0.58, b_fwd, up, b_right, trim)

	cheek_l := turret_c + b_right * 0.52 + up * 0.24
	cheek_r := turret_c - b_right * 0.52 + up * 0.24
	draw_oriented_box(cheek_l, 0.12, 0.32, 0.48, b_fwd, up, b_right, gunmetal)
	draw_oriented_box(cheek_r, 0.12, 0.32, 0.48, b_fwd, up, b_right, gunmetal)

	pivot := turret_c + up * 0.36
	rl.DrawCylinderEx(pivot - b_right * 0.60, pivot + b_right * 0.60, 0.12, 0.12, 8, steel_lit)

	shield_c := pivot + barrel_dir * 0.25
	draw_oriented_box(shield_c + b_right * 0.34, 0.18, 0.38, 0.08, barrel_dir, barrel_normal, b_right, hull)
	draw_oriented_box(shield_c - b_right * 0.34, 0.18, 0.38, 0.08, barrel_dir, barrel_normal, b_right, hull)
	draw_oriented_box(shield_c + barrel_normal * 0.26, 0.42, 0.08, 0.08, barrel_dir, barrel_normal, b_right, trim)

	breech := pivot - barrel_dir * 0.35
	draw_oriented_box(breech, 0.45, 0.28, 0.48, barrel_dir, barrel_normal, b_right, gunmetal)
	draw_oriented_box(breech + barrel_normal * 0.22, 0.36, 0.08, 0.40, barrel_dir, barrel_normal, b_right, hull)

	cable_s := turret_c - b_fwd * 0.45 + up * 0.10
	cable_e := breech - barrel_dir * 0.20
	rl.DrawCylinderEx(cable_s, cable_e, 0.08, 0.07, 6, gunmetal)
	rl.DrawLine3D(cable_s + up * 0.07, cable_e + barrel_normal * 0.07, eff_glow)

	rc_l_s := pivot - barrel_dir * 0.30 + b_right * 0.26 + barrel_normal * 0.25
	rc_l_e := pivot + barrel_dir * 0.70 + b_right * 0.26 + barrel_normal * 0.25
	rl.DrawCylinderEx(rc_l_s, rc_l_e, 0.095, 0.095, 8, steel_lit)
	rl.DrawCylinderEx(rc_l_s, rc_l_s + barrel_dir * 0.15, 0.12, 0.12, 8, gunmetal)

	rc_r_s := pivot - barrel_dir * 0.30 - b_right * 0.26 + barrel_normal * 0.25
	rc_r_e := pivot + barrel_dir * 0.70 - b_right * 0.26 + barrel_normal * 0.25
	rl.DrawCylinderEx(rc_r_s, rc_r_e, 0.095, 0.095, 8, steel_lit)
	rl.DrawCylinderEx(rc_r_s, rc_r_s + barrel_dir * 0.15, 0.12, 0.12, 8, gunmetal)

	for b_i in 0..<2 {
		b_sign: f32 = (b_i == 0) ? 1.0 : -1.0
		bar_root := pivot + b_right * (b_sign * 0.26)

		s1_s := bar_root
		s1_e := bar_root + barrel_dir * 1.10
		rl.DrawCylinderEx(s1_s, s1_e, 0.165, 0.145, 8, dark)
		rl.DrawCylinderEx(s1_s, s1_s + barrel_dir * 0.25, 0.19, 0.19, 8, gunmetal)

		s2_s := s1_e
		s2_e := bar_root + barrel_dir * 2.70
		rl.DrawCylinderEx(s2_s, s2_e, 0.13, 0.11, 8, gunmetal)

		for c_idx in 0..<5 {
			c_dist := 0.25 + f32(c_idx) * 0.46
			c_pos := s2_s + barrel_dir * c_dist
			c_end := c_pos + barrel_dir * 0.10
			rl.DrawCylinderEx(c_pos, c_end, 0.155, 0.155, 8, eff_glow)
			rl.DrawCylinderEx(c_pos, c_pos + barrel_dir * 0.02, 0.165, 0.165, 8, steel_lit)
			rl.DrawCylinderEx(c_end - barrel_dir * 0.02, c_end, 0.165, 0.165, 8, steel_lit)
		}

		mb_s := s2_e
		mb_e := s2_e + barrel_dir * 0.55
		rl.DrawCylinderEx(mb_s, mb_e, 0.145, 0.145, 8, steel_mid)
		baf1 := mb_s + barrel_dir * 0.15
		baf2 := mb_s + barrel_dir * 0.32
		rl.DrawCylinderEx(baf1, baf1 + barrel_dir * 0.06, 0.18, 0.18, 8, gunmetal)
		rl.DrawCylinderEx(baf2, baf2 + barrel_dir * 0.06, 0.18, 0.18, 8, gunmetal)

		rl.DrawSphereEx(mb_e, 0.09, 6, 6, eff_glow)
	}

	pod_c := pivot + barrel_normal * 0.32 + barrel_dir * 0.40
	draw_oriented_box(pod_c, 0.18, 0.15, 0.22, barrel_dir, barrel_normal, b_right, gunmetal)
	rl.DrawSphere(pod_c + barrel_dir * 0.23 + barrel_normal * 0.04, 0.08, eff_glow)
	rl.DrawSphere(pod_c + barrel_dir * 0.23 - barrel_normal * 0.04, 0.07, eff_amber)

	collimator_s := pivot + barrel_dir * 0.60
	collimator_e := pivot + barrel_dir * 2.80
	rl.DrawLine3D(collimator_s, collimator_e, eff_glow)

	// 6. Sensor Mast, Rotating Radar & Command Spire
	mast_root := center + up * 2.0 - rl.Vector3{1.1, 0, 0}
	rl.DrawCylinderEx(mast_root, mast_root + up * 2.2, 0.26, 0.14, 6, gunmetal)
	rl.DrawCylinderEx(mast_root + up * 2.2, mast_root + up * 4.2, 0.14, 0.05, 4, steel_lit)

	rl.DrawCylinderEx(mast_root + up * 1.8 - b_right * 0.9, mast_root + up * 1.8 + b_right * 0.9, 0.04, 0.04, 4, steel_mid)
	rl.DrawCylinderEx(mast_root + up * 2.8 - b_right * 0.55, mast_root + up * 2.8 + b_right * 0.55, 0.03, 0.03, 4, steel_mid)

	spire_tip := mast_root + up * 4.3
	rl.DrawSphere(spire_tip, 0.28 * pulse_fast + 0.14, rl.Fade(eff_glow, 0.95))

	if !destroyed {
		sweep_ang := laser_anim_time * 1.8
		sweep_dir := rl.Vector3{math.cos(sweep_ang), 0.22, math.sin(sweep_ang)}
		radar_hub := mast_root + up * 2.3
		rl.DrawCylinderEx(radar_hub, radar_hub + sweep_dir * 0.75, 0.08, 0.26, 8, steel_mid)
		rl.DrawSphere(radar_hub + sweep_dir * 0.78, 0.10, eff_glow)
		rl.DrawLine3D(radar_hub, radar_hub + sweep_dir * 3.8, rl.Fade(eff_glow, 0.75))
	}
}

// Orbit tangent used as a fighter's forward vector while guarding.
drone_heading :: proc(pos, center: rl.Vector3) -> rl.Vector3 {
	t := rl.Vector3{-(pos.z - center.z), 0, pos.x - center.x}
	if rl.Vector3Length(t) < 0.001 { return {1, 0, 0} }
	return rl.Vector3Normalize(t)
}

// Procedural drone models: baked once into GPU VRAM at startup and drawn via
// DrawModelEx (1 draw call per drone instead of dozens of immediate-mode calls).
add_triangle :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	v1, v2, v3: rl.Vector3, color: rl.Color,
) {
	e1 := v2 - v1
	e2 := v3 - v1
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(e1, e2))
	if rl.Vector3Length(n) < 0.001 { n = {0, 1, 0} }

	pts := [3]rl.Vector3{v1, v2, v3}
	for p in pts {
		append(verts, p.x, p.y, p.z)
		append(norms, n.x, n.y, n.z)
		append(cols, color.r, color.g, color.b, color.a)
	}
}

add_cylinder :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	start, end: rl.Vector3, r_start, r_end: f32, sides: int, color: rl.Color,
) {
	dir := end - start
	dist := rl.Vector3Length(dir)
	if dist < 0.0001 { return }
	d := dir / dist

	up := rl.Vector3{0, 1, 0}
	if math.abs(rl.Vector3DotProduct(d, up)) > 0.95 {
		up = {0, 0, 1}
	}
	u := rl.Vector3Normalize(rl.Vector3CrossProduct(d, up))
	v := rl.Vector3CrossProduct(d, u)

	n_sides := max(sides, 3)
	for i in 0..<n_sides {
		a1 := f32(i) * 2.0 * math.PI / f32(n_sides)
		a2 := f32(i + 1) * 2.0 * math.PI / f32(n_sides)

		c1, s1 := math.cos(a1), math.sin(a1)
		c2, s2 := math.cos(a2), math.sin(a2)

		n1 := u * c1 + v * s1
		n2 := u * c2 + v * s2

		b1 := start + n1 * r_start
		b2 := start + n2 * r_start
		t1 := end + n1 * r_end
		t2 := end + n2 * r_end

		// Side quad (2 triangles)
		append(verts, b1.x, b1.y, b1.z,  b2.x, b2.y, b2.z,  t1.x, t1.y, t1.z)
		append(norms, n1.x, n1.y, n1.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		append(verts, b2.x, b2.y, b2.z,  t2.x, t2.y, t2.z,  t1.x, t1.y, t1.z)
		append(norms, n2.x, n2.y, n2.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		// Start cap
		if r_start > 0 {
			append(verts, start.x, start.y, start.z,  b2.x, b2.y, b2.z,  b1.x, b1.y, b1.z)
			append(norms, -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}

		// End cap
		if r_end > 0 {
			append(verts, end.x, end.y, end.z,  t1.x, t1.y, t1.z,  t2.x, t2.y, t2.z)
			append(norms, d.x, d.y, d.z,  d.x, d.y, d.z,  d.x, d.y, d.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}
	}
}

add_sphere :: proc(
	verts: ^[dynamic]f32, norms: ^[dynamic]f32, cols: ^[dynamic]u8,
	center: rl.Vector3, radius: f32, rings, slices: int, color: rl.Color,
) {
	nRings := max(rings, 3)
	nSlices := max(slices, 3)

	for r in 0..<nRings {
		phi1 := f32(r) * math.PI / f32(nRings)
		phi2 := f32(r + 1) * math.PI / f32(nRings)

		y1 := math.cos(phi1)
		y2 := math.cos(phi2)
		r1 := math.sin(phi1)
		r2 := math.sin(phi2)

		for s in 0..<nSlices {
			th1 := f32(s) * 2.0 * math.PI / f32(nSlices)
			th2 := f32(s + 1) * 2.0 * math.PI / f32(nSlices)

			x11, z11 := r1 * math.cos(th1), r1 * math.sin(th1)
			x12, z12 := r1 * math.cos(th2), r1 * math.sin(th2)
			x21, z21 := r2 * math.cos(th1), r2 * math.sin(th1)
			x22, z22 := r2 * math.cos(th2), r2 * math.sin(th2)

			n00 := rl.Vector3{x11, y1, z11}
			n01 := rl.Vector3{x12, y1, z12}
			n10 := rl.Vector3{x21, y2, z21}
			n11 := rl.Vector3{x22, y2, z22}

			p00 := center + n00 * radius
			p01 := center + n01 * radius
			p10 := center + n10 * radius
			p11 := center + n11 * radius

			// Triangle 1
			append(verts, p00.x, p00.y, p00.z,  p10.x, p10.y, p10.z,  p01.x, p01.y, p01.z)
			append(norms, n00.x, n00.y, n00.z,  n10.x, n10.y, n10.z,  n01.x, n01.y, n01.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

			// Triangle 2
			append(verts, p01.x, p01.y, p01.z,  p10.x, p10.y, p10.z,  p11.x, p11.y, p11.z)
			append(norms, n01.x, n01.y, n01.z,  n10.x, n10.y, n10.z,  n11.x, n11.y, n11.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}
	}
}

make_mesh_from_arrays :: proc(vertices: []f32, normals: []f32, colors: []u8) -> rl.Mesh {
	mesh := rl.Mesh{}
	mesh.vertexCount = c.int(len(vertices) / 3)
	mesh.triangleCount = c.int(len(vertices) / 9)

	mesh.vertices = cast([^]f32)rl.MemAlloc(c.uint(len(vertices) * size_of(f32)))
	mem.copy(mesh.vertices, raw_data(vertices), len(vertices) * size_of(f32))

	mesh.normals = cast([^]f32)rl.MemAlloc(c.uint(len(normals) * size_of(f32)))
	mem.copy(mesh.normals, raw_data(normals), len(normals) * size_of(f32))

	mesh.colors = cast([^]u8)rl.MemAlloc(c.uint(len(colors) * size_of(u8)))
	mem.copy(mesh.colors, raw_data(colors), len(colors) * size_of(u8))

	mesh.texcoords = cast([^]f32)rl.MemAlloc(c.uint(int(mesh.vertexCount) * 2 * size_of(f32)))
	mem.zero(mesh.texcoords, int(mesh.vertexCount) * 2 * size_of(f32))

	rl.UploadMesh(&mesh, false)
	return mesh
}

build_miner_model :: proc(enemy: bool) -> rl.Model {
	verts := make([dynamic]f32)
	defer delete(verts)
	norms := make([dynamic]f32)
	defer delete(norms)
	cols  := make([dynamic]u8)
	defer delete(cols)

	hull_main:   rl.Color
	hull_plate:  rl.Color
	frame_dark:  rl.Color
	metal_trim:  rl.Color
	tank_mesh:   rl.Color
	light_glow:  rl.Color

	if enemy {
		hull_main  = rl.Color{160, 42, 48, 255}
		hull_plate = rl.Color{205, 68, 76, 255}
		frame_dark = rl.Color{36, 18, 22, 255}
		metal_trim = rl.Color{135, 120, 125, 255}
		tank_mesh  = rl.Color{55, 34, 38, 255}
		light_glow = SCIFI_RED
	} else {
		hull_main  = rl.Color{230, 155, 22, 255}
		hull_plate = rl.Color{255, 190, 40, 255}
		frame_dark = rl.Color{26, 28, 34, 255}
		metal_trim = rl.Color{145, 158, 172, 255}
		tank_mesh  = rl.Color{42, 48, 58, 255}
		light_glow = rl.Color{255, 215, 95, 255}
	}

	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pos := rl.Vector3{0, 0, 0}

	// 1. Central Heavy Flatbed Chassis
	deck_f := pos + h * 0.16 - up * 0.02
	deck_b := pos - h * 0.22 - up * 0.02
	add_cylinder(&verts, &norms, &cols, deck_b, deck_f, 0.22, 0.20, 6, frame_dark)
	add_cylinder(&verts, &norms, &cols, deck_b + up * 0.04, deck_f + up * 0.04, 0.18, 0.16, 6, hull_main)

	// 2. Giant Spherical Ore Tank (Mounted High at the Rear)
	tank_pos := pos - h * 0.14 + up * 0.24
	tank_r: f32 = 0.24
	add_sphere(&verts, &norms, &cols, tank_pos, tank_r, 8, 10, tank_mesh)

	s_signs := [2]f32{-1.0, 1.0}
	for s in s_signs {
		cradle_base := pos - h * 0.18 + side * (s * 0.16) + up * 0.04
		cradle_top  := tank_pos + side * (s * 0.18) + up * 0.04
		add_cylinder(&verts, &norms, &cols, cradle_base, cradle_top, 0.030, 0.020, 4, hull_main)
	}
	add_cylinder(&verts, &norms, &cols, pos - h * 0.22 + up * 0.04, tank_pos - h * 0.16 + up * 0.04, 0.035, 0.025, 4, hull_plate)

	// 3. Operator Cabin with Visor (Front-Left Deck)
	cab_pos := pos + h * 0.14 + up * 0.08 - side * 0.07
	add_cylinder(&verts, &norms, &cols, cab_pos - h * 0.08, cab_pos + h * 0.08, 0.09, 0.07, 5, hull_main)
	add_cylinder(&verts, &norms, &cols, cab_pos + h * 0.05, cab_pos + h * 0.09, 0.06, 0.045, 5, SCIFI_CYAN)

	// 4. Heavy Halogen Work Floodlight (Front-Right Deck)
	light_pos := pos + h * 0.22 + up * 0.06 + side * 0.08
	add_cylinder(&verts, &norms, &cols, light_pos - h * 0.04, light_pos, 0.040, 0.040, 4, frame_dark)
	add_sphere(&verts, &norms, &cols, light_pos + h * 0.015, 0.030, 4, 4, light_glow)

	// 5. Four Articulated Hydraulic Outrigger Legs (Spider Stabilizers)
	leg_offsets := [4][2]f32{ {0.12, 0.18}, {0.12, -0.18}, {-0.16, 0.20}, {-0.16, -0.20} }
	leg_targets := [4][2]f32{ {0.26, 0.36}, {0.26, -0.36}, {-0.28, 0.38}, {-0.28, -0.38} }

	for l in 0..<4 {
		hip  := pos + h * leg_offsets[l][0] + side * leg_offsets[l][1] - up * 0.02
		foot := pos + h * leg_targets[l][0] + side * leg_targets[l][1] - up * 0.28
		knee := (hip + foot) * 0.5 + up * 0.08 + side * (leg_targets[l][1] > 0 ? 0.06 : -0.06)

		add_cylinder(&verts, &norms, &cols, hip, knee, 0.036, 0.026, 4, hull_main)
		add_cylinder(&verts, &norms, &cols, knee, foot, 0.026, 0.018, 4, metal_trim)
		add_cylinder(&verts, &norms, &cols, foot, foot - up * 0.035, 0.032, 0.028, 4, frame_dark)
	}

	// 6. Ventral Excavation Drill / Rotary Cutter Tool
	drill_base := pos + h * 0.08 - up * 0.12
	drill_tip  := pos + h * 0.22 - up * 0.40
	add_cylinder(&verts, &norms, &cols, drill_base, drill_base - up * 0.06, 0.05, 0.05, 5, frame_dark)
	add_cylinder(&verts, &norms, &cols, drill_base - up * 0.05, drill_tip, 0.05, 0.012, 5, metal_trim)
	add_sphere(&verts, &norms, &cols, drill_tip, 0.032, 4, 4, light_glow)

	// 7. Twin Rear Hover / Transit Thrusters
	for s in s_signs {
		nozzle_f := pos - h * 0.22 + side * (s * 0.12) - up * 0.04
		nozzle_b := nozzle_f - h * 0.08
		add_cylinder(&verts, &norms, &cols, nozzle_f, nozzle_b, 0.045, 0.035, 4, frame_dark)
		add_sphere(&verts, &norms, &cols, nozzle_b - h * 0.02, 0.045, 4, 4, light_glow)
	}

	mesh := make_mesh_from_arrays(verts[:], norms[:], cols[:])
	return rl.LoadModelFromMesh(mesh)
}

build_fighter_model :: proc(enemy: bool) -> rl.Model {
	verts := make([dynamic]f32)
	defer delete(verts)
	norms := make([dynamic]f32)
	defer delete(norms)
	cols  := make([dynamic]u8)
	defer delete(cols)

	armor_main:  rl.Color
	armor_dark:  rl.Color
	armor_plate: rl.Color
	metal_trim:  rl.Color
	energy_glow: rl.Color
	energy_core: rl.Color

	if enemy {
		armor_main  = rl.Color{78, 28, 36, 255}
		armor_dark  = rl.Color{38, 14, 18, 255}
		armor_plate = rl.Color{125, 42, 52, 255}
		metal_trim  = rl.Color{160, 125, 130, 255}
		energy_glow = SCIFI_RED
		energy_core = rl.Color{255, 190, 140, 255}
	} else {
		armor_main  = rl.Color{28, 48, 76, 255}
		armor_dark  = rl.Color{16, 26, 42, 255}
		armor_plate = rl.Color{46, 82, 126, 255}
		metal_trim  = rl.Color{135, 165, 190, 255}
		energy_glow = SCIFI_CYAN
		energy_core = SCIFI_MINT
	}

	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pos := rl.Vector3{0, 0, 0}

	// 1. Central Core & Armored Dorsal Cowling
	core_f := pos + h * 0.18
	core_b := pos - h * 0.28
	add_cylinder(&verts, &norms, &cols, core_b, core_f, 0.20, 0.18, 6, armor_dark)

	hood_f := pos + h * 0.20 + up * 0.16
	hood_b := pos - h * 0.30 + up * 0.18
	add_cylinder(&verts, &norms, &cols, hood_b, hood_f, 0.15, 0.12, 5, armor_main)

	s_signs := [2]f32{-1.0, 1.0}
	for s_sign in s_signs {
		s_vec := side * s_sign
		sh_f := pos + h * 0.18 + up * 0.06 + s_vec * 0.24
		sh_b := pos - h * 0.26 + up * 0.08 + s_vec * 0.26
		sh_tip := pos + s_vec * 0.30 - up * 0.06

		add_triangle(&verts, &norms, &cols, hood_f, sh_f, hood_b, armor_plate)
		add_triangle(&verts, &norms, &cols, hood_b, sh_f, sh_tip, armor_main)
	}

	// 2. Central Circular Ocular Sensor (The "Eye")
	eye_pos := pos + h * 0.22
	add_cylinder(&verts, &norms, &cols, eye_pos, eye_pos + h * 0.04, 0.14, 0.13, 6, metal_trim)
	add_sphere(&verts, &norms, &cols, eye_pos + h * 0.045, 0.075, 6, 6, energy_glow)
	add_sphere(&verts, &norms, &cols, eye_pos + h * 0.070, 0.035, 4, 4, energy_core)

	// Forward chin sensor probe / needle
	probe_base := pos + h * 0.18 - up * 0.11
	probe_tip  := pos + h * 0.52 - up * 0.20
	add_cylinder(&verts, &norms, &cols, probe_base, probe_tip, 0.025, 0.008, 4, metal_trim)

	// 3. Ventral Stabilizer Mandibles / Struts
	for s_sign in s_signs {
		s_vec := side * s_sign
		strut_top := pos - h * 0.06 - up * 0.10 + s_vec * 0.14
		strut_tip := pos + h * 0.04 - up * 0.34 + s_vec * 0.18
		add_cylinder(&verts, &norms, &cols, strut_top, strut_tip, 0.030, 0.014, 4, metal_trim)
	}

	// 4. Outboard Twin Heavy Weapon Sponsons (Flanking Railguns)
	for s_sign in s_signs {
		s_vec := side * s_sign
		pod_pos := pos + s_vec * 0.40 - up * 0.02

		add_cylinder(&verts, &norms, &cols, pos + s_vec * 0.20, pod_pos, 0.032, 0.032, 4, armor_dark)
		add_cylinder(&verts, &norms, &cols, pod_pos - h * 0.20, pod_pos + h * 0.10, 0.068, 0.058, 5, armor_main)

		rail_len := f32(0.36)
		p_top_start := pod_pos + h * 0.08 + up * 0.040
		p_top_end   := p_top_start + h * rail_len
		add_cylinder(&verts, &norms, &cols, p_top_start, p_top_end, 0.022, 0.014, 4, metal_trim)

		p_bot_start := pod_pos + h * 0.08 - up * 0.040
		p_bot_end   := p_bot_start + h * rail_len
		add_cylinder(&verts, &norms, &cols, p_bot_start, p_bot_end, 0.022, 0.014, 4, metal_trim)

		add_cylinder(&verts, &norms, &cols, pod_pos + h * 0.07, pod_pos + h * 0.38, 0.014, 0.014, 4, energy_glow)
	}

	// 5. Rear Propulsion & Thruster Flare
	engine_pos := pos - h * 0.32
	add_cylinder(&verts, &norms, &cols, pos - h * 0.24, engine_pos, 0.12, 0.09, 6, armor_dark)
	add_cylinder(&verts, &norms, &cols, engine_pos, engine_pos - h * 0.04, 0.09, 0.07, 6, metal_trim)

	add_sphere(&verts, &norms, &cols, engine_pos - h * 0.05, 0.075, 4, 6, energy_glow)
	add_sphere(&verts, &norms, &cols, engine_pos - h * 0.03, 0.040, 4, 4, energy_core)

	mesh := make_mesh_from_arrays(verts[:], norms[:], cols[:])
	return rl.LoadModelFromMesh(mesh)
}

init_drone_visuals :: proc() {
	if drone_visuals_ready { return }
	drone_models[.PLAYER_MINER]   = build_miner_model(false)
	drone_models[.ENEMY_MINER]    = build_miner_model(true)
	drone_models[.PLAYER_FIGHTER] = build_fighter_model(false)
	drone_models[.ENEMY_FIGHTER]  = build_fighter_model(true)
	drone_visuals_ready = true
}

unload_drone_visuals :: proc() {
	if !drone_visuals_ready { return }
	for kind in Drone_Model_Kind {
		rl.UnloadModel(drone_models[kind])
	}
	drone_visuals_ready = false
}

draw_miner_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3 = {1, 0, 0}) {
	if !drone_visuals_ready {
		rl.DrawSphere(position, 0.35, enemy ? rl.RED : rl.ORANGE)
		return
	}
	h := heading
	if rl.Vector3Length(h) < 0.001 { h = {1, 0, 0} }
	h = rl.Vector3Normalize(h)

	bob := math.sin(laser_anim_time * 3.0 + position.x * 2.1 + position.z * 1.7) * 0.04
	pos := position + {0, bob, 0}

	model := enemy ? drone_models[.ENEMY_MINER] : drone_models[.PLAYER_MINER]

	v_from := rl.Vector3{1, 0, 0}
	dot := rl.Vector3DotProduct(v_from, h)
	axis := rl.Vector3{0, 1, 0}
	angle: f32 = 0.0
	if dot < -0.9999 {
		axis = {0, 1, 0}
		angle = 180.0
	} else if dot < 0.9999 {
		axis = rl.Vector3Normalize(rl.Vector3CrossProduct(v_from, h))
		angle = math.acos(math.clamp(dot, -1.0, 1.0)) * (180.0 / math.PI)
	}

	rl.DrawModelEx(model, pos, axis, angle, {1, 1, 1}, rl.WHITE)
}

draw_fighter_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3) {
	if !drone_visuals_ready {
		rl.DrawSphere(position, 0.35, enemy ? rl.RED : SCIFI_BLUE)
		return
	}
	h := heading
	if rl.Vector3Length(h) < 0.001 { h = {1, 0, 0} }
	h = rl.Vector3Normalize(h)

	model := enemy ? drone_models[.ENEMY_FIGHTER] : drone_models[.PLAYER_FIGHTER]

	v_from := rl.Vector3{1, 0, 0}
	dot := rl.Vector3DotProduct(v_from, h)
	axis := rl.Vector3{0, 1, 0}
	angle: f32 = 0.0
	if dot < -0.9999 {
		axis = {0, 1, 0}
		angle = 180.0
	} else if dot < 0.9999 {
		axis = rl.Vector3Normalize(rl.Vector3CrossProduct(v_from, h))
		angle = math.acos(math.clamp(dot, -1.0, 1.0)) * (180.0 / math.PI)
	}

	rl.DrawModelEx(model, position, axis, angle, {1, 1, 1}, rl.WHITE)
}

// Visible laser fire during battles: short flying bolts from each shooter
// toward its target (player fire neon cyan, enemy fire RED), mirroring the
// update_planet_combat rules - dogfights, miner sweeps and base sieges.
draw_combat_lasers :: proc(p: int, player_spots, enemy_spots: []rl.Vector3, pc, ec: int, player_miner_spots, enemy_miner_spots: []rl.Vector3, pmc, emc: int) {
	num_p := min(pc, rep_count(pc))
	num_e := min(ec, rep_count(ec))
	if num_p > 0 && num_e > 0 {
		// Dogfight: visible fighters trade fire.
		for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_spots[i % num_e], f32(i) * 2.3, SCIFI_CYAN) }
		for j in 0..<num_e { draw_laser_bolt(enemy_spots[j], player_spots[j % num_p], f32(j) * 2.3 + 1.1, rl.RED) }
	} else if num_e > 0 {
		if p < PLANET_COUNT && orbital_defense_level[p] > 0 {
			def_pos := orbital_defense_pos(p)
			for j in 0..<num_e {
				draw_laser_bolt(enemy_spots[j], def_pos, f32(j) * 2.3, rl.RED)
			}
		} else {
			// Enemy fighters strafing unescorted player miners (kill_player_miner).
			num_tc := min(pmc, rep_count(pmc))
			for j in 0..<num_e {
				if num_tc == 0 { break }
				draw_laser_bolt(enemy_spots[j], player_miner_spots[j % num_tc], f32(j) * 2.3, rl.RED)
			}
		}
	} else if num_p > 0 {
		// Player fighters sweeping enemy miners (kill_enemy_miner), then
		// besieging the enemy base itself.
		if emc > 0 {
			num_tc := min(emc, rep_count(emc))
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_miner_spots[i % num_tc], f32(i) * 2.3, SCIFI_CYAN) }
		} else if p == ENEMY_HOME && orbital_defense_level[p] > 0 {
			def_pos := orbital_defense_pos(p)
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], def_pos, f32(i) * 2.3, SCIFI_CYAN) }
		} else if enemy_base_hp[p] > 0 {
			base := sector_pos(p) + rl.Vector3{0, sector_radius(p) * 0.6, 0}
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], base, f32(i) * 2.3, SCIFI_CYAN) }
		}
	}
}

// A short laser bolt flying along the shooter->target ray: its head advances
// at LASER_BOLT_SPEED on the game clock (laser_anim_time, frozen on pause)
// with a per-shooter phase offset, wrapping at the target. Two half-cycle
// phased bolts per ray read as sustained fire.
draw_laser_bolt :: proc(from, to: rl.Vector3, offset: f32, color: rl.Color) {
	diff := rl.Vector3{to.x - from.x, to.y - from.y, to.z - from.z}
	dist := rl.Vector3Length(diff)
	if dist < 0.05 { return }
	dir := diff * (1.0 / dist)
	for phase in 0..<2 {
		head := math.mod(laser_anim_time * LASER_BOLT_SPEED + offset + f32(phase) * dist * 0.5, dist)
		tail := clamp(head - LASER_BOLT_LEN, 0, dist)
		rl.DrawLine3D(from + dir * tail, from + dir * head, color)
	}
}

// One rendered cube per up-to-10 units: ceil(count / 10).
rep_count :: proc(count: int) -> int { return (count + 9) / 10 }

// Fighting drones in transit to a planet, grouped by side - the unit side of
// the transit representational rendering.
transit_fighters_at :: proc(target_planet: int, enemy: bool) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.state == .TRANSIT && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Mining drones in transit to a planet, grouped by side - the unit side of
// the transit representational rendering.
transit_miners_at :: proc(target_planet: int, enemy: bool = false) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .TRANSIT && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Mining drones returning from a planet to Earth.
returning_miners_at :: proc(target_planet: int, enemy: bool = false) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .MINING && u.state == .RETURNING && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

// Planet a stationed (non-transit) miner is physically located at.
miner_stationed_planet :: proc(u: ^Unit) -> int {
	if u.state == .TRANSIT || u.state == .RETURNING { return -1 }
	if u.state == .DEPOSITING { return EARTH }
	if u.enemy { return u.affiliation }
	if u.target_planet >= 0 && u.target_planet < SECTOR_COUNT { return u.target_planet }
	if u.affiliation >= 0 && u.affiliation < SECTOR_COUNT { return u.affiliation }
	return EARTH
}

// Stationed mining drones at a planet, grouped by side.
stationed_miners_at :: proc(p: int, enemy: bool) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind != .MINING || u.enemy != enemy { continue }
		if miner_stationed_planet(u) == p { count += 1 }
	}
	return count
}

draw_selection_ring :: proc(center: rl.Vector3, radius: f32) {
	segments :: 24
	pulse := 0.65 + 0.35 * math.sin(laser_anim_time * 5.0)
	for segment := 0; segment < segments; segment += 1 {
		a := f32(segment) * 2 * math.PI / f32(segments)
		b := f32(segment + 1) * 2 * math.PI / f32(segments)
		rl.DrawLine3D(
			{center.x + math.cos(a) * radius, center.y - 0.25, center.z + math.sin(a) * radius},
			{center.x + math.cos(b) * radius, center.y - 0.25, center.z + math.sin(b) * radius},
			rl.Fade(SCIFI_CYAN, pulse),
		)
		// Outer halo ring for depth.
		or_ := radius + 0.22
		rl.DrawLine3D(
			{center.x + math.cos(a) * or_, center.y - 0.25, center.z + math.sin(a) * or_},
			{center.x + math.cos(b) * or_, center.y - 0.25, center.z + math.sin(b) * or_},
			rl.Fade(SCIFI_CYAN, 0.25 * pulse),
		)
	}
}

// ---- Planet visuals -------------------------------------------------------

planet_spin_speed :: proc(p: int) -> f32 {
	switch p {
	case JUPITER: return 0.22
	case SATURN: return 0.20
	case URANUS, NEPTUNE: return 0.16
	case MERCURY, VENUS: return 0.10
	}
	return 0.12
}

update_planet_spin :: proc(dt: f32) {
	for p in 0..<PLANET_COUNT {
		planet_spin[p] += dt * planet_spin_speed(p)
		if planet_spin[p] > 2 * math.PI { planet_spin[p] -= 2 * math.PI }
	}
}

// Linear blend between two opaque colors (t = 0 keeps a, t = 1 takes b).
mix_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	return rl.Color{
		u8(f32(a.r) * (1 - t) + f32(b.r) * t),
		u8(f32(a.g) * (1 - t) + f32(b.g) * t),
		u8(f32(a.b) * (1 - t) + f32(b.b) * t),
		255,
	}
}

PLANET_TEX_SIZE :: 128

// One deterministic surface blob (center + radius, in texels).
planet_blob :: struct { x, y, r: f32 }

// Build one procedural surface texture per planet. Deterministic per planet
// (offsets derive from the index), independent of the gameplay RNG. The whole
// pipeline is RGBA from the first pixel: the base image is GenImageColor and
// every texel is shaded in code from the perlin luminance, so no grayscale
// image op can ever drop the hue (which rendered as grey surface gores).
init_planet_visuals :: proc() {
	if planet_visuals_ready { return }
	for p in 0..<PLANET_COUNT {
		base := planets[p].color
		img := rl.GenImageColor(PLANET_TEX_SIZE, PLANET_TEX_SIZE, base)
		noise := rl.GenImagePerlinNoise(PLANET_TEX_SIZE, PLANET_TEX_SIZE, c.int(p * 17 + 3), c.int(p * 29 + 7), 6.0)
		lum := rl.LoadImageColors(noise)
		// Deterministic blotches via a tiny LCG (no gameplay RNG use).
		seed := u32(0x9E3779B9 + u32(p) * 0x85EBCA6B)
		next := proc(seed: ^u32) -> f32 {
			seed^ = seed^ * 1664525 + 1013904223
			return f32((seed^ >> 8) & 0xFFFF) / f32(0xFFFF)
		}
		blobs: [9]planet_blob
		for b in 0..<9 {
			blobs[b] = {next(&seed) * PLANET_TEX_SIZE, next(&seed) * PLANET_TEX_SIZE, 4 + next(&seed) * 11}
		}
		oceans: [6]planet_blob
		for b in 0..<6 {
			oceans[b] = {next(&seed) * PLANET_TEX_SIZE, next(&seed) * PLANET_TEX_SIZE, 6 + next(&seed) * 13}
		}
		blotch := rl.Color{u8(min(int(base.r) + 34, 255)), u8(min(int(base.g) + 34, 255)), u8(min(int(base.b) + 34, 255)), 255}
		ocean := rl.Color{18, 60, 150, 255}
		for y in 0..<PLANET_TEX_SIZE {
			for x in 0..<PLANET_TEX_SIZE {
				l := f32(lum[y * PLANET_TEX_SIZE + x].r) / 255.0
				shade := 0.70 + l * 0.60
				col := rl.Color{
					u8(min(f32(base.r) * shade, 255)),
					u8(min(f32(base.g) * shade, 255)),
					u8(min(f32(base.b) * shade, 255)),
					255,
				}
				if p >= JUPITER {
					// Planetary latitude cloud bands for gas giants.
					// In par_shapes sphere, x is latitude (0 = North Pole, 127 = South Pole).
					// Subtle perlin perturbation (l) adds atmospheric turbulence.
					x_lat := f32(x) + (l - 0.5) * 5.0
					band_freq: f32 = 0.38
					band_phase: f32 = f32(p * 13)
					if p == JUPITER { band_freq = 0.42 }
					else if p == SATURN { band_freq = 0.32 }
					else if p == URANUS { band_freq = 0.22 }
					else if p == NEPTUNE { band_freq = 0.28 }

					band_val := math.sin(x_lat * band_freq + band_phase) + 0.35 * math.sin(x_lat * band_freq * 2.1 + band_phase * 1.5)

					contrast: f32 = 0.26
					if p == JUPITER { contrast = 0.32 }
					else if p == SATURN { contrast = 0.18 }
					else if p == URANUS { contrast = 0.12 }
					else if p == NEPTUNE { contrast = 0.22 }

					if band_val > 0.1 {
						boost := 1.0 + contrast * (band_val * 0.7)
						col = rl.Color{
							u8(min(f32(col.r) * boost + 8 * boost, 255)),
							u8(min(f32(col.g) * boost + 8 * boost, 255)),
							u8(min(f32(col.b) * boost + 8 * boost, 255)),
							255,
						}
					} else {
						darken := 1.0 + contrast * band_val
						darken = max(darken, 0.65)
						if p == JUPITER {
							col = rl.Color{
								u8(min(f32(col.r) * darken * 1.08, 255)),
								u8(f32(col.g) * darken * 0.90),
								u8(f32(col.b) * darken * 0.80),
								255,
							}
						} else {
							col = rl.Color{
								u8(f32(col.r) * darken),
								u8(f32(col.g) * darken),
								u8(f32(col.b) * darken),
								255,
							}
						}
					}

					if p == JUPITER {
						spot_x: f32 = 82.0
						spot_y: f32 = 55.0
						dx := (f32(x) - spot_x) / 5.5
						dy_val := f32(y) - spot_y
						if dy_val > f32(PLANET_TEX_SIZE) / 2.0 { dy_val -= f32(PLANET_TEX_SIZE) }
						if dy_val < -f32(PLANET_TEX_SIZE) / 2.0 { dy_val += f32(PLANET_TEX_SIZE) }
						dy := dy_val / 11.0
						dist_sq := dx * dx + dy * dy
						if dist_sq <= 1.0 {
							spot_col := rl.Color{205, 68, 48, 255}
							col = mix_color(col, spot_col, 0.78 * (1.0 - dist_sq * 0.25))
						}
					} else if p == NEPTUNE {
						spot_x: f32 = 75.0
						spot_y: f32 = 60.0
						dx := (f32(x) - spot_x) / 6.0
						dy_val := f32(y) - spot_y
						if dy_val > f32(PLANET_TEX_SIZE) / 2.0 { dy_val -= f32(PLANET_TEX_SIZE) }
						if dy_val < -f32(PLANET_TEX_SIZE) / 2.0 { dy_val += f32(PLANET_TEX_SIZE) }
						dy := dy_val / 12.0
						dist_sq := dx * dx + dy * dy
						if dist_sq <= 1.0 {
							spot_col := rl.Color{35, 55, 140, 255}
							col = mix_color(col, spot_col, 0.70)
						}
					}
				} else {
					fx, fy := f32(x), f32(y)
					for b in 0..<9 {
						dx, dy := fx - blobs[b].x, fy - blobs[b].y
						if dx * dx + dy * dy <= blobs[b].r * blobs[b].r {
							col = mix_color(col, blotch, 0.5)
							break
						}
					}
					// Earth oceans: deep-blue patches over the marble.
					if p == EARTH {
						for b in 0..<6 {
							dx, dy := fx - oceans[b].x, fy - oceans[b].y
							if dx * dx + dy * dy <= oceans[b].r * oceans[b].r {
								col = mix_color(col, ocean, 0.65)
								break
							}
						}
						if x < 8 || x > 120 {
							col = mix_color(col, rl.Color{240, 245, 255, 255}, 0.85)
						}
					} else if p == MARS {
						if x < 6 || x > 122 {
							col = mix_color(col, rl.Color{240, 230, 225, 255}, 0.80)
						}
					}
				}
				rl.ImageDrawPixel(&img, c.int(x), c.int(y), col)
			}
		}
		rl.UnloadImageColors(lum)
		rl.UnloadImage(noise)
		tex := rl.LoadTextureFromImage(img)
		rl.SetTextureWrap(tex, .REPEAT)
		rl.SetTextureFilter(tex, .BILINEAR)
		rl.UnloadImage(img)
		planet_textures[p] = tex
		model := rl.LoadModelFromMesh(rl.GenMeshSphere(planets[p].radius, 32, 32))
		model.transform = rl.MatrixRotateX(rl.DEG2RAD * -90)
		rl.SetMaterialTexture(&model.materials[0], .ALBEDO, tex)
		planet_models[p] = model
	}
	planet_visuals_ready = true
}

unload_planet_visuals :: proc() {
	if !planet_visuals_ready { return }
	for p in 0..<PLANET_COUNT {
		rl.UnloadModel(planet_models[p])
		rl.UnloadTexture(planet_textures[p])
	}
	planet_visuals_ready = false
}

// ---- Starfield ----------------------------------------------------------

STAR_COUNT :: 280

stars: [STAR_COUNT]rl.Vector3
star_sizes: [STAR_COUNT]f32
star_alphas: [STAR_COUNT]f32

// Deterministic sky: a wide disc well below the play plane, so panning and
// zooming parallax-scrolls it. A tiny LCG keeps the starfield identical every
// run and independent of the gameplay RNG.
generate_stars :: proc() {
	seed := u32(0x5F3759DF)
	for i in 0..<STAR_COUNT {
		seed = seed * 1664525 + 1013904223
		angle := f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 2 * math.PI
		seed = seed * 1664525 + 1013904223
		dist := 20.0 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 420.0
		seed = seed * 1664525 + 1013904223
		depth := f32((seed >> 8) & 0xFFFF) / f32(0xFFFF)
		stars[i] = {math.cos(angle) * dist, -14.0 - depth * 60.0, math.sin(angle) * dist}
		seed = seed * 1664525 + 1013904223
		star_sizes[i] = 0.9 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 1.1
		seed = seed * 1664525 + 1013904223
		star_alphas[i] = 0.35 + f32((seed >> 8) & 0xFFFF) / f32(0xFFFF) * 0.6
	}
}

// Cool-tinted pixel stars in screen space, drawn before the 3D pass so they
// stay behind everything. Every 4th star carries a faint cyan tint for a
// colder deep-space feel; the tint derives from the star index so the field
// stays deterministic. The >= bounds form also discards NaN projections of
// points behind the camera.
draw_starfield :: proc() {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	for i in 0..<STAR_COUNT {
		pos := rl.GetWorldToScreen(stars[i], camera)
		if !(pos.x >= 0 && pos.x <= w && pos.y >= 0 && pos.y <= h) { continue }
		tint := rl.WHITE
		if i % 4 == 0 { tint = rl.Color{170, 230, 255, 255} }
		rl.DrawCircleV(pos, star_sizes[i], rl.Fade(tint, star_alphas[i]))
	}
}

// Red palpitating combat nebula in screen space behind planets with active combat
// and behind the enemy HQ, plus yellow pulsating nebula aura behind the minor wave
// attack source planet. Rendered before BeginMode3D so 3D textured planet
// spheres and fortress models occlude the nebula core, creating an organic backlit
// cosmic warzone atmosphere. Uses additive blending for luminous gas clouds.
// Size scaled down by half for a tighter, more focused warzone halo.
draw_combat_nebulae :: proc() {
	has_any := false
	for s in 0..<SECTOR_COUNT {
		if combat_nebula_intensity[s] > 0.005 || minor_wave_source_nebula_intensity[s] > 0.005 {
			has_any = true
			break
		}
	}
	if !has_any { return }

	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for s in 0..<SECTOR_COUNT {
		if combat_nebula_intensity[s] > 0.005 {
			draw_sector_nebula(s, combat_nebula_intensity[s], sector_combat_state[s], false, viewport_w, screen_h, cam_forward, cam_right)
		}
		if minor_wave_source_nebula_intensity[s] > 0.005 {
			draw_sector_nebula(s, minor_wave_source_nebula_intensity[s], false, true, viewport_w, screen_h, cam_forward, cam_right)
		}
	}
}

draw_sector_nebula :: proc(s: int, intensity: f32, in_combat: bool, is_yellow: bool, viewport_w, screen_h: f32, cam_forward, cam_right: rl.Vector3) {
	if intensity <= 0.005 { return }

	pos_3d := sector_pos(s)
	cam_to_pos := pos_3d - camera.position
	if rl.Vector3DotProduct(cam_to_pos, cam_forward) <= 0.1 { return }

	screen_pos := rl.GetWorldToScreen(pos_3d, camera)
	if screen_pos.x < -250 || screen_pos.x > viewport_w + 250 || screen_pos.y < -250 || screen_pos.y > screen_h + 250 {
		return
	}

	rad := sector_radius(s)
	limb_3d := pos_3d + cam_right * rad
	limb_screen := rl.GetWorldToScreen(limb_3d, camera)
	base_r := max(rl.Vector2Distance(screen_pos, limb_screen), 14.0)

	// Palpitating rhythm: organic multi-frequency heartbeat pulse
	// Combines fundamental throb with secondary harmonic for an authentic heart-palpitation cadence
	t := laser_anim_time
	pulse_speed: f32 = in_combat ? 3.8 : 2.4
	pulse1 := math.sin(t * pulse_speed + f32(s) * 1.8)
	pulse2 := math.sin(t * (pulse_speed * 2.0) + f32(s) * 2.5 + 0.45)
	palpitation := 0.85 + 0.28 * pulse1 + 0.16 * pulse2
	radius_pulse := 1.0 + 0.14 * math.sin(t * (pulse_speed * 0.7) + f32(s))

	effective_intensity := clamp(intensity * palpitation, 0.0, 1.6)

	// 1. Grand Outer Ambient Nebula Shroud (deep cosmic space haze)
	// Scaled down by half for a cleaner, tighter atmospheric halo
	grand_r := max(base_r * 5.5, 120.0) * radius_pulse
	grand_alpha := u8(clamp(75.0 * effective_intensity, 0, 255))

	secondary_grand_pos := rl.Vector2{
		screen_pos.x + math.cos(t * 0.3 + f32(s)) * (base_r * 1.4),
		screen_pos.y + math.sin(t * 0.25 + f32(s)) * (base_r * 1.0),
	}
	secondary_r := max(base_r * 4.75, 100.0) * radius_pulse
	secondary_alpha := u8(clamp(60.0 * effective_intensity, 0, 255))

	if is_yellow {
		rl.DrawCircleGradient(screen_pos, grand_r, rl.Color{170, 150, 15, grand_alpha}, rl.Color{0, 0, 0, 0})
		rl.DrawCircleGradient(secondary_grand_pos, secondary_r, rl.Color{195, 170, 20, secondary_alpha}, rl.Color{0, 0, 0, 0})

		// 2. Multi-tiered Asymmetric Billowing Gas Clouds (12 organic lobes across 3 tiers)
		// Tier 1: Outer billowing wisps (4 lobes)
		for i in 0..<4 {
			fi := f32(i)
			ang := fi * (math.PI * 0.5) + math.sin(t * 0.35 + fi * 1.7 + f32(s)) * 0.45 + f32(s) * 0.8
			dist := max(base_r * (1.9 + 0.3 * math.sin(t * 0.6 + fi * 2.2 + f32(s))), 35.0)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.82}
			r := max(base_r * (1.9 + 0.25 * math.cos(t * 1.0 + fi * 1.5)) * radius_pulse, 32.5)
			alpha := u8(clamp(65.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{205, 185, 20, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 2: Mid-range turbulent cloud banks (5 lobes)
		for i in 0..<5 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 5.0) + math.sin(t * 0.45 + fi * 1.5 + f32(s)) * 0.38 + f32(s) * 1.3
			dist := max(base_r * (1.15 + 0.225 * math.sin(t * 0.75 + fi * 1.9 + f32(s))), 22.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.84}
			r := max(base_r * (1.5 + 0.225 * math.cos(t * 1.2 + fi * 1.8)) * radius_pulse, 25.0)
			alpha := u8(clamp(90.0 * effective_intensity, 0, 255))
			r_val := u8(clamp(245.0 + 10.0 * math.sin(fi * 2.0), 0, 255))
			g_val := u8(clamp(215.0 + 25.0 * math.cos(fi * 1.6), 0, 255))
			b_val := u8(clamp(25.0 + 15.0 * math.sin(fi * 3.0), 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{r_val, g_val, b_val, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 3: Dense inner plasma clouds (3 lobes)
		for i in 0..<3 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 3.0) + math.sin(t * 0.5 + fi * 2.1 + f32(s)) * 0.3 + f32(s) * 0.4
			dist := max(base_r * (0.65 + 0.15 * math.sin(t * 0.9 + fi * 2.5)), 12.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.86}
			r := max(base_r * (1.2 + 0.175 * math.cos(t * 1.3 + fi * 2.0)) * radius_pulse, 20.0)
			alpha := u8(clamp(110.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{255, 225, 30, alpha}, rl.Color{0, 0, 0, 0})
		}

		// 3. Hot Inner Corona & Shockwave Disc (backlighting the body silhouette)
		corona_r := max(base_r * 1.4, 22.5) * radius_pulse
		corona_alpha := u8(clamp(135.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, corona_r, rl.Color{255, 230, 30, corona_alpha}, rl.Color{0, 0, 0, 0})

		// Scorching inner core ring right behind planet edge
		inner_core_r := max(base_r * 1.2, 16.0) * (0.95 + 0.1 * palpitation)
		inner_alpha := u8(clamp(115.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, inner_core_r, rl.Color{255, 245, 90, inner_alpha}, rl.Color{0, 0, 0, 0})

		// 4. Ionization Tendrils / Plasma Streamers (fine drifting filaments)
		for k in 0..<8 {
			fk := f32(k)
			spark_angle := fk * 0.785 + t * 0.55 + f32(s) * 1.4
			spark_dist := max(base_r * (1.4 + 0.25 * math.sin(t * 1.4 + fk * 2.2)), 22.5)
			spark_pos := rl.Vector2{
				screen_pos.x + math.cos(spark_angle) * spark_dist,
				screen_pos.y + math.sin(spark_angle) * spark_dist * 0.88,
			}
			spark_r := max(base_r * (0.7 + 0.175 * math.cos(t * 2.1 + fk)), 12.5)
			spark_alpha := u8(clamp(50.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(spark_pos, spark_r, rl.Color{255, 235, 50, spark_alpha}, rl.Color{0, 0, 0, 0})
		}
	} else {
		rl.DrawCircleGradient(screen_pos, grand_r, rl.Color{160, 12, 35, grand_alpha}, rl.Color{0, 0, 0, 0})
		rl.DrawCircleGradient(secondary_grand_pos, secondary_r, rl.Color{190, 20, 50, secondary_alpha}, rl.Color{0, 0, 0, 0})

		// 2. Multi-tiered Asymmetric Billowing Gas Clouds (12 organic lobes across 3 tiers)
		// Tier 1: Outer billowing wisps (4 lobes)
		for i in 0..<4 {
			fi := f32(i)
			ang := fi * (math.PI * 0.5) + math.sin(t * 0.35 + fi * 1.7 + f32(s)) * 0.45 + f32(s) * 0.8
			dist := max(base_r * (1.9 + 0.3 * math.sin(t * 0.6 + fi * 2.2 + f32(s))), 35.0)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.82}
			r := max(base_r * (1.9 + 0.25 * math.cos(t * 1.0 + fi * 1.5)) * radius_pulse, 32.5)
			alpha := u8(clamp(65.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{195, 18, 42, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 2: Mid-range turbulent cloud banks (5 lobes)
		for i in 0..<5 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 5.0) + math.sin(t * 0.45 + fi * 1.5 + f32(s)) * 0.38 + f32(s) * 1.3
			dist := max(base_r * (1.15 + 0.225 * math.sin(t * 0.75 + fi * 1.9 + f32(s))), 22.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.84}
			r := max(base_r * (1.5 + 0.225 * math.cos(t * 1.2 + fi * 1.8)) * radius_pulse, 25.0)
			alpha := u8(clamp(90.0 * effective_intensity, 0, 255))
			r_val := u8(clamp(235.0 + 20.0 * math.sin(fi * 2.0), 0, 255))
			g_val := u8(clamp(35.0 + 25.0 * math.cos(fi * 1.6), 0, 255))
			b_val := u8(clamp(30.0 + 20.0 * math.sin(fi * 3.0), 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{r_val, g_val, b_val, alpha}, rl.Color{0, 0, 0, 0})
		}

		// Tier 3: Dense inner plasma clouds (3 lobes)
		for i in 0..<3 {
			fi := f32(i)
			ang := fi * (2.0 * math.PI / 3.0) + math.sin(t * 0.5 + fi * 2.1 + f32(s)) * 0.3 + f32(s) * 0.4
			dist := max(base_r * (0.65 + 0.15 * math.sin(t * 0.9 + fi * 2.5)), 12.5)
			center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.86}
			r := max(base_r * (1.2 + 0.175 * math.cos(t * 1.3 + fi * 2.0)) * radius_pulse, 20.0)
			alpha := u8(clamp(110.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(center, r, rl.Color{255, 60, 32, alpha}, rl.Color{0, 0, 0, 0})
		}

		// 3. Hot Inner Combat Corona & Shockwave Disc (backlighting the body silhouette)
		corona_r := max(base_r * 1.4, 22.5) * radius_pulse
		corona_alpha := u8(clamp(135.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, corona_r, rl.Color{255, 55, 28, corona_alpha}, rl.Color{0, 0, 0, 0})

		// Scorching inner core ring right behind planet edge
		inner_core_r := max(base_r * 1.2, 16.0) * (0.95 + 0.1 * palpitation)
		inner_alpha := u8(clamp(115.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(screen_pos, inner_core_r, rl.Color{255, 125, 45, inner_alpha}, rl.Color{0, 0, 0, 0})

		// 4. Ionization Tendrils / Plasma Streamers (fine drifting filaments)
		for k in 0..<8 {
			fk := f32(k)
			spark_angle := fk * 0.785 + t * 0.55 + f32(s) * 1.4
			spark_dist := max(base_r * (1.4 + 0.25 * math.sin(t * 1.4 + fk * 2.2)), 22.5)
			spark_pos := rl.Vector2{
				screen_pos.x + math.cos(spark_angle) * spark_dist,
				screen_pos.y + math.sin(spark_angle) * spark_dist * 0.88,
			}
			spark_r := max(base_r * (0.7 + 0.175 * math.cos(t * 2.1 + fk)), 12.5)
			spark_alpha := u8(clamp(50.0 * effective_intensity, 0, 255))
			rl.DrawCircleGradient(spark_pos, spark_r, rl.Color{255, 135, 50, spark_alpha}, rl.Color{0, 0, 0, 0})
		}
	}
}

// ---- Earth industrial manufacturing indicator ----------------------------

// Surface coordinates for major industrial complexes across Earth's continents.
Earth_Industry_Hub :: struct {
	lat: f32,
	lon: f32,
	theme: int, // 0 = foundry/forge, 1 = assembly/shipyard, 2 = laser/welding
}

EARTH_INDUSTRY_HUBS := [10]Earth_Industry_Hub{
	{lat = 38.0,  lon = 30.0,  theme = 0},
	{lat = 42.0,  lon = 85.0,  theme = 1},
	{lat = 52.0,  lon = 135.0, theme = 2},
	{lat = 35.0,  lon = 185.0, theme = 1},
	{lat = 15.0,  lon = 225.0, theme = 0},
	{lat = -25.0, lon = 275.0, theme = 2},
	{lat = -18.0, lon = 320.0, theme = 1},
	{lat = 8.0,   lon = 0.0,   theme = 0},
	{lat = 30.0,  lon = 350.0, theme = 2},
	{lat = -32.0, lon = 60.0,  theme = 1},
}

// Indicator on Earth when units are being created: industrial manufacturing
// complexes light up across Earth's surface with lights turning on and off,
// rhythmic assembly bay shifts, high-frequency robotic welding sparks, hazard
// strobes, and vertical shipyard gantry beacons, rotating naturally with the planet.
// Rendered in screen space with additive blending for pure radiant luminous glow.
draw_earth_industry_lights :: proc() {
	if earth_industry_intensity <= 0.005 { return }

	earth := planets[EARTH]
	spin := planet_spin[EARTH]
	cos_s := math.cos(spin)
	sin_s := math.sin(spin)
	t := laser_anim_time

	viewport_w := f32(rl.GetScreenWidth() - SCREEN_PANEL_WIDTH)
	screen_h := f32(rl.GetScreenHeight())

	// Earth projected silhouette radius in screen space
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	earth_screen := rl.GetWorldToScreen(earth.position, camera)
	limb_screen := rl.GetWorldToScreen(earth.position + cam_right * earth.radius, camera)
	screen_r := max(rl.Vector2Distance(earth_screen, limb_screen), 12.0)

	// Active lines scale the number of active manufacturing hubs
	active_lines := 0
	for b in 0..<base_counts[EARTH] {
		if production[EARTH][b].active { active_lines += 1 }
	}
	if base_build_planet == EARTH { active_lines += 1 }
	hubs_count := min(5 + active_lines * 2, 10)

	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for h in 0..<hubs_count {
		hub := EARTH_INDUSTRY_HUBS[h]
		lat_rad := hub.lat * (math.PI / 180.0)
		lon_rad := hub.lon * (math.PI / 180.0)

		hub_u := rl.Vector3{
			math.cos(lat_rad) * math.cos(lon_rad),
			math.sin(lat_rad),
			math.cos(lat_rad) * math.sin(lon_rad),
		}

		// Rotate with Earth's planetary spin
		hub_rot := rl.Vector3{
			hub_u.x * cos_s - hub_u.z * sin_s,
			hub_u.y,
			hub_u.x * sin_s + hub_u.z * cos_s,
		}

		hub_3d := earth.position + hub_rot * (earth.radius * 1.002)

		// Occlusion check against Earth globe: hide lights on the far hemisphere
		cam_to_hub := camera.position - hub_3d
		cam_dist := rl.Vector3Length(cam_to_hub)
		if cam_dist <= 0.01 { continue }
		to_cam := cam_to_hub / cam_dist
		facing := rl.Vector3DotProduct(hub_rot, to_cam)
		if facing <= 0.02 { continue }
		limb_fade := clamp((facing - 0.02) / 0.18, 0.0, 1.0)
		net_intensity := earth_industry_intensity * limb_fade

		hub_screen := rl.GetWorldToScreen(hub_3d, camera)
		if hub_screen.x < -60 || hub_screen.x > viewport_w + 60 || hub_screen.y < -60 || hub_screen.y > screen_h + 60 {
			continue
		}

		// Local tangent vectors for spreading out facilities across each industrial zone
		up := rl.Vector3{0, 1, 0}
		if abs(hub_rot.y) > 0.90 { up = rl.Vector3{1, 0, 0} }
		tangent_u := rl.Vector3Normalize(rl.Vector3CrossProduct(up, hub_rot))
		tangent_v := rl.Vector3Normalize(rl.Vector3CrossProduct(hub_rot, tangent_u))

		fh := f32(h)

		// Radii scaled to projected planet radius with minimum visibility clamps
		core_r := max(screen_r * 0.045, 2.2)
		glow_r := max(screen_r * 0.12, 5.5)

		// 1. Soft industrial city / factory light bloom spill
		halo_r := max(screen_r * 0.22, 10.0)
		halo_alpha := u8(clamp(95.0 * net_intensity, 0, 255))
		halo_col := hub.theme == 1 ? rl.Color{0, 230, 215, halo_alpha} : rl.Color{255, 140, 25, halo_alpha}
		rl.DrawCircleGradient(hub_screen, halo_r, halo_col, rl.Color{0, 0, 0, 0})

		// 2. Main Foundry Core / Forge Furnace (warm golden-amber pulsing heart)
		foundry_pulse := 0.65 + 0.35 * math.sin(t * 3.0 + fh * 1.5)
		foundry_alpha := u8(clamp(foundry_pulse * 255.0 * net_intensity, 0, 255))
		rl.DrawCircleGradient(hub_screen, glow_r, rl.Color{255, 145, 20, foundry_alpha}, rl.Color{0, 0, 0, 0})
		rl.DrawCircleV(hub_screen, core_r, rl.Color{255, 225, 120, foundry_alpha})

		// Tangent screen offsets for satellite industrial nodes
		pos1_3d := hub_3d + tangent_u * 0.28 + tangent_v * 0.14
		pos1_screen := rl.GetWorldToScreen(pos1_3d, camera)

		pos2_3d := hub_3d + tangent_u * -0.25 + tangent_v * -0.16
		pos2_screen := rl.GetWorldToScreen(pos2_3d, camera)

		pos3_3d := hub_3d + tangent_u * -0.22 + tangent_v * 0.22
		pos3_screen := rl.GetWorldToScreen(pos3_3d, camera)

		pos4_3d := hub_3d + tangent_u * 0.18 + tangent_v * -0.24
		pos4_screen := rl.GetWorldToScreen(pos4_3d, camera)

		// 3. Automated Assembly Bay (electric cyan - turning on and off in distinct shift cycles)
		bay_cycle := math.mod(t * 1.4 + fh * 0.85, 2.0)
		bay_on := bay_cycle < 1.25
		bay_bright: f32 = bay_on ? (0.85 + 0.15 * math.sin(t * 9.0 + fh)) : 0.0
		bay_alpha := u8(clamp(bay_bright * 255.0 * net_intensity, 0, 255))
		if bay_alpha > 5 {
			rl.DrawCircleGradient(pos1_screen, glow_r * 0.9, rl.Color{0, 240, 220, bay_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos1_screen, core_r * 0.9, rl.Color{200, 255, 245, bay_alpha})
		}

		// Secondary assembly bay node (alternating shift)
		bay2_cycle := math.mod(t * 1.2 + fh * 1.4 + 0.8, 1.8)
		bay2_on := bay2_cycle < 1.05
		bay2_bright: f32 = bay2_on ? (0.80 + 0.20 * math.sin(t * 8.0 + fh * 2.0)) : 0.0
		bay2_alpha := u8(clamp(bay2_bright * 255.0 * net_intensity, 0, 255))
		if bay2_alpha > 5 {
			rl.DrawCircleGradient(pos2_screen, glow_r * 0.85, rl.Color{40, 255, 210, bay2_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos2_screen, core_r * 0.85, rl.Color{220, 255, 240, bay2_alpha})
		}

		// 4. Robotic Arc Welding / Laser Fabrication (high-frequency brilliant white-blue sparks)
		weld_cycle := math.mod(t * 1.6 + fh * 1.9, 2.3)
		weld_bright: f32 = 0.0
		if weld_cycle < 1.15 {
			spark := math.sin(t * 36.0 + fh * 7.3)
			if spark > 0.0 {
				weld_bright = 0.95 + 0.05 * math.sin(t * 60.0)
			}
		}
		weld_alpha := u8(clamp(weld_bright * 255.0 * net_intensity, 0, 255))
		if weld_alpha > 10 {
			rl.DrawCircleGradient(pos3_screen, glow_r * 0.95, rl.Color{200, 240, 255, weld_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos3_screen, core_r * 0.95, rl.Color{255, 255, 255, weld_alpha})
		}

		// 5. Strobe Hazard Beacon (sharp periodic warning flash)
		strobe_cycle := math.mod(t * 1.5 + fh * 0.4, 1.0)
		strobe_bright: f32 = strobe_cycle < 0.18 ? (1.0 - (strobe_cycle / 0.18) * 0.85) : 0.0
		strobe_alpha := u8(clamp(strobe_bright * 255.0 * net_intensity, 0, 255))
		if strobe_alpha > 10 {
			rl.DrawCircleGradient(pos4_screen, glow_r * 0.75, rl.Color{255, 195, 20, strobe_alpha}, rl.Color{0, 0, 0, 0})
			rl.DrawCircleV(pos4_screen, core_r * 0.75, rl.Color{255, 240, 140, strobe_alpha})
		}

		// 6. Shipyard Gantry Spire / Launch Laser Beam (rising above surface)
		spire_3d := hub_3d + hub_rot * (earth.radius * 0.25)
		spire_screen := rl.GetWorldToScreen(spire_3d, camera)
		beam_alpha := u8(clamp(190.0 * net_intensity, 0, 255))
		beam_col := hub.theme == 1 ? rl.Color{0, 245, 220, beam_alpha} : rl.Color{255, 160, 40, beam_alpha}
		rl.DrawLineEx(hub_screen, spire_screen, max(screen_r * 0.03, 1.8), beam_col)

		// Pulsing tip beacon at the top of the gantry tower
		beacon_on := math.mod(t * 2.2 + fh * 0.5, 1.0) < 0.25
		beacon_alpha := u8(clamp((beacon_on ? 255.0 : 40.0) * net_intensity, 0, 255))
		rl.DrawCircleV(spire_screen, max(screen_r * 0.04, 2.2), rl.Color{255, 60, 50, beacon_alpha})
	}
}

