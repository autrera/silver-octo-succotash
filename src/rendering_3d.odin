package main

import "core:c"
import "core:math"
import "core:mem"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

draw_world :: proc() {
	viewport_w := ui_screen_w() - SCREEN_PANEL_WIDTH
	draw_starfield()
	draw_ambient_nebulae()
	draw_planet_halos()
	draw_combat_nebulae()
	rl.BeginMode3D(camera)
	draw_planets_and_batteries()
	flush_orbital_defenses()
	if hq_on_screen(f32(viewport_w)) {
		draw_hq_fortress(ENEMY_HQ_POSITION)
	}
	draw_rally_marker()
	draw_selection_rings()

	sector_vis: [SECTOR_COUNT]bool
	for p in 0..<SECTOR_COUNT { sector_vis[p] = has_vision(p) }
	collect_sector_spots(sector_vis)
	draw_stationed_units(sector_vis)
	draw_transit_units(sector_vis)
	flush_drones()
	draw_refinery_mineral_beams()
	draw_orbital_defense_blasts()
	rl.EndMode3D()
	apply_ui_scale()
	if in_start_menu {
		return
	}
	draw_hud(viewport_w)
}

draw_planets_and_batteries :: proc() {
	for p in 0..<PLANET_COUNT {
		planet := planets[p]
		draw_planet_body(p)
		ring_col := has_vision(p) ? planet_atmospheres[p] : rl.Color{70, 76, 90, 255}
		rl.DrawCircle3D(planet.position, planet.radius + 1.5, {1, 0, 0}, 90, rl.Fade(ring_col, 0.22))
		draw_orbital_defense(p)
	}
}

collect_sector_spots :: proc(sector_vis: [SECTOR_COUNT]bool) {
	for p in 0..<SECTOR_COUNT {
		s := &world_sector_spots[p]
		s.pc, s.ec, s.pmc, s.emc = 0, 0, 0, 0
	}
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		p := -1
		if u.kind == .COMBAT {
			if u.state == .GUARDING { p = u.affiliation }
		} else {
			p = miner_stationed_planet(u)
		}
		if p < 0 || p >= SECTOR_COUNT || !sector_vis[p] { continue }
		s := &world_sector_spots[p]
		switch {
		case u.kind == .COMBAT && u.enemy:
			if s.ec < MAX_UNITS { s.enemy_combat[s.ec] = u.position }
			s.ec += 1
		case u.kind == .COMBAT:
			if s.pc < MAX_UNITS { s.player_combat[s.pc] = u.position }
			s.pc += 1
		case u.enemy:
			if s.emc < MAX_UNITS { s.enemy_miners[s.emc] = u.position }
			s.emc += 1
		case:
			if s.pmc < MAX_UNITS { s.player_miners[s.pmc] = u.position }
			s.pmc += 1
		}
	}
}

draw_stationed_units :: proc(sector_vis: [SECTOR_COUNT]bool) {
	for p in 0..<SECTOR_COUNT {
		if !sector_vis[p] { continue }
		s := &world_sector_spots[p]
		sp := sector_pos(p)
		for d in 0..<s.pc { draw_fighter_drone(s.player_combat[d], false, drone_heading(s.player_combat[d], sp)) }
		for d in 0..<s.ec { draw_fighter_drone(s.enemy_combat[d], true, drone_heading(s.enemy_combat[d], sp)) }
		draw_combat_lasers(p, s.player_combat[:], s.enemy_combat[:], s.pc, s.ec, s.player_miners[:], s.enemy_miners[:], s.pmc, s.emc)
		for d in 0..<s.emc { draw_miner_drone(s.enemy_miners[d], true, drone_heading(s.enemy_miners[d], sp)) }
	}
}

draw_transit_units :: proc(sector_vis: [SECTOR_COUNT]bool) {
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.state != .TRANSIT { continue }
		p := u.target_planet
		if p < 0 || p >= SECTOR_COUNT { continue }
		if u.enemy && !sector_vis[p] { continue }
		to := sector_pos(p)
		heading := to - u.position
		if u.kind == .COMBAT {
			draw_fighter_drone(u.position, u.enemy, heading)
			if rl.Vector3Length(heading) > 0.001 {
				trail := u.position - rl.Vector3Normalize(heading) * 1.2
				rl.DrawLine3D(u.position, trail, rl.Fade(u.enemy ? rl.RED : SCIFI_GREEN, 0.6))
			}
		} else {
			draw_miner_drone(u.position, u.enemy, heading)
		}
		line_col := u.enemy ? rl.Color{255, 60, 75, 70} : rl.Color{0, 225, 255, 90}
		rl.DrawLine3D(u.position, to, line_col)
	}
}

draw_hud :: proc(viewport_w: i32) {
	draw_planet_labels(f32(viewport_w))
	draw_conquered_planet_overlays(f32(viewport_w), f32(ui_screen_h()))
	draw_resource_hud()

	if hud_save_notification_timer > 0 {
		saved_lbl: cstring = "GAME SAVED"
		saved_w := f32(rl.MeasureText(saved_lbl, 11))
		saved_x := f32(viewport_w) - f32(HUD_PAD) - saved_w - 8
		draw_chamfered_panel({saved_x - 8, HUD_PAD + 12, saved_w + 16, 26}, 4, rl.Color{30, 20, 10, 240}, SCIFI_AMBER_DIM)
		rl.DrawText(saved_lbl, i32(saved_x), i32(HUD_PAD + 18), 11, SCIFI_AMBER)
	}

	ctrl_rect := controls_button_rect()
	draw_button(ctrl_rect, "Controls", SCIFI_PANEL_SOLID, true)

	telemetry_cam := rl.TextFormat("ALT %.0f   ZOOM %d%%   %d FPS", camera.position.y, zoom_percent(), rl.GetFPS())
	tel_font_size: i32 = 12
	tel_w := rl.MeasureText(telemetry_cam, tel_font_size)
	tel_x := i32(viewport_w) - tel_w - HUD_PAD
	tel_y := i32(ctrl_rect.y + (ctrl_rect.height - f32(tel_font_size)) / 2)
	rl.DrawText(telemetry_cam, tel_x, tel_y, tel_font_size, rl.WHITE)

	draw_squad_hud()
}

hq_on_screen :: proc(viewport_w: f32) -> bool {
	if !planet_in_front(ENEMY_HQ_POSITION) { return false }
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	center := ui_world_to_screen(ENEMY_HQ_POSITION)
	edge := ui_world_to_screen(ENEMY_HQ_POSITION + cam_right * (ENEMY_HQ_RADIUS * 2.5))
	margin := rl.Vector2Distance(center, edge)
	h := f32(ui_screen_h())
	return center.x + margin >= 0 && center.x - margin <= viewport_w && center.y + margin >= 0 && center.y - margin <= h
}

drone_heading :: proc(pos, center: rl.Vector3) -> rl.Vector3 {
	t := rl.Vector3{-(pos.z - center.z), 0, pos.x - center.x}
	if rl.Vector3Length(t) < 0.001 { return {1, 0, 0} }
	return rl.Vector3Normalize(t)
}

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

		append(verts, b1.x, b1.y, b1.z,  b2.x, b2.y, b2.z,  t1.x, t1.y, t1.z)
		append(norms, n1.x, n1.y, n1.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		append(verts, b2.x, b2.y, b2.z,  t2.x, t2.y, t2.z,  t1.x, t1.y, t1.z)
		append(norms, n2.x, n2.y, n2.z,  n2.x, n2.y, n2.z,  n1.x, n1.y, n1.z)
		append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

		if r_start > 0 {
			append(verts, start.x, start.y, start.z,  b2.x, b2.y, b2.z,  b1.x, b1.y, b1.z)
			append(norms, -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z,  -d.x, -d.y, -d.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}

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

			append(verts, p00.x, p00.y, p00.z,  p01.x, p01.y, p01.z,  p10.x, p10.y, p10.z)
			append(norms, n00.x, n00.y, n00.z,  n01.x, n01.y, n01.z,  n10.x, n10.y, n10.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)

			append(verts, p01.x, p01.y, p01.z,  p11.x, p11.y, p11.z,  p10.x, p10.y, p10.z)
			append(norms, n01.x, n01.y, n01.z,  n11.x, n11.y, n11.z,  n10.x, n10.y, n10.z)
			append(cols, color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a,  color.r, color.g, color.b, color.a)
		}
	}
}

make_mesh_from_arrays :: proc(vertices: []f32, normals: []f32, colors: []u8, texcoords: []f32 = nil) -> rl.Mesh {
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
	if len(texcoords) == int(mesh.vertexCount) * 2 {
		mem.copy(mesh.texcoords, raw_data(texcoords), len(texcoords) * size_of(f32))
	}

	rl.UploadMesh(&mesh, false)
	return mesh
}

DRONE_ICON_RES :: 128

drone_icons: [Unit_Type]rl.RenderTexture2D

Icon_Edge :: struct {
	a, b:   rl.Vector3,
	normal: rl.Vector3,
	keep:   bool,
}

quantize_vertex :: proc(v: rl.Vector3) -> [3]i32 {
	return {i32(math.round(v.x * 4000)), i32(math.round(v.y * 4000)), i32(math.round(v.z * 4000))}
}

project_icon_point :: proc(p: rl.Vector3, yaw, pitch: f32) -> (rl.Vector2, f32) {
	cy, sy := math.cos(yaw), math.sin(yaw)
	cp, sp := math.cos(pitch), math.sin(pitch)
	x := p.x * cy + p.z * sy
	z := -p.x * sy + p.z * cy
	y := p.y * cp - z * sp
	depth := p.y * sp + z * cp
	return {x, -y}, depth
}

bake_drone_icon :: proc(model: rl.Model, yaw, pitch: f32) -> rl.RenderTexture2D {
	mesh := model.meshes[0]
	edge_index := make(map[[6]i32]int)
	defer delete(edge_index)
	edges := make([dynamic]Icon_Edge)
	defer delete(edges)

	for t in 0..<int(mesh.triangleCount) {
		p: [3]rl.Vector3
		for k in 0..<3 {
			i := (t * 3 + k) * 3
			p[k] = {mesh.vertices[i], mesh.vertices[i + 1], mesh.vertices[i + 2]}
		}
		n := rl.Vector3CrossProduct(p[1] - p[0], p[2] - p[0])
		n_len := rl.Vector3Length(n)
		if n_len < 0.000001 { continue }
		n /= n_len

		for k in 0..<3 {
			a := p[k]
			b := p[(k + 1) % 3]
			qa := quantize_vertex(a)
			qb := quantize_vertex(b)
			if qa == qb { continue }
			key: [6]i32
			if qa.x < qb.x || (qa.x == qb.x && (qa.y < qb.y || (qa.y == qb.y && qa.z < qb.z))) {
				key = {qa.x, qa.y, qa.z, qb.x, qb.y, qb.z}
			} else {
				key = {qb.x, qb.y, qb.z, qa.x, qa.y, qa.z}
			}
			if index, found := edge_index[key]; found {
				if math.abs(rl.Vector3DotProduct(edges[index].normal, n)) > 0.995 {
					edges[index].keep = false
				}
			} else {
				edge_index[key] = len(edges)
				append(&edges, Icon_Edge{a = a, b = b, normal = n, keep = true})
			}
		}
	}

	min_p := rl.Vector2{1e9, 1e9}
	max_p := rl.Vector2{-1e9, -1e9}
	min_d: f32 = 1e9
	max_d: f32 = -1e9
	for e in edges {
		if !e.keep { continue }
		for v in ([2]rl.Vector3{e.a, e.b}) {
			pt, d := project_icon_point(v, yaw, pitch)
			min_p = {min(min_p.x, pt.x), min(min_p.y, pt.y)}
			max_p = {max(max_p.x, pt.x), max(max_p.y, pt.y)}
			min_d = min(min_d, d)
			max_d = max(max_d, d)
		}
	}

	margin: f32 = 8
	extent := max(max_p.x - min_p.x, max_p.y - min_p.y)
	scale := (f32(DRONE_ICON_RES) - 2 * margin) / extent
	mid := (min_p + max_p) * 0.5
	origin := rl.Vector2{f32(DRONE_ICON_RES) * 0.5, f32(DRONE_ICON_RES) * 0.5}

	target := rl.LoadRenderTexture(DRONE_ICON_RES, DRONE_ICON_RES)
	rl.BeginTextureMode(target)
	rl.ClearBackground(rl.Color{255, 255, 255, 0})
	for e in edges {
		if !e.keep { continue }
		pa, da := project_icon_point(e.a, yaw, pitch)
		pb, db := project_icon_point(e.b, yaw, pitch)
		depth := ((da + db) * 0.5 - min_d) / max(max_d - min_d, 0.0001)
		alpha := u8(110 + 145 * clamp(depth, 0, 1))
		rl.DrawLineEx((pa - mid) * scale + origin, (pb - mid) * scale + origin, 2.4, rl.Color{255, 255, 255, alpha})
	}
	rl.EndTextureMode()

	rl.GenTextureMipmaps(&target.texture)
	rl.SetTextureFilter(target.texture, .TRILINEAR)
	return target
}

draw_unit_icon :: proc(kind: Unit_Type, center: rl.Vector2, size: f32, tint: rl.Color) {
	if !drone_visuals_ready { return }
	tex := drone_icons[kind].texture
	src := rl.Rectangle{0, 0, f32(tex.width), -f32(tex.height)}
	dst := rl.Rectangle{center.x - size * 0.5, center.y - size * 0.5, size, size}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, tint)
}

draw_combat_lasers :: proc(p: int, player_spots, enemy_spots: []rl.Vector3, pc, ec: int, player_miner_spots, enemy_miner_spots: []rl.Vector3, pmc, emc: int) {
	num_p := pc
	num_e := ec
	if num_p > 0 && num_e > 0 {
		for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_spots[i % num_e], f32(i) * 2.3, SCIFI_GREEN) }
		for j in 0..<num_e { draw_laser_bolt(enemy_spots[j], player_spots[j % num_p], f32(j) * 2.3 + 1.1, rl.RED) }
	} else if num_e > 0 {
		if p < PLANET_COUNT && orbital_defense_level[p] > 0 {
			def_pos := orbital_defense_pos(p)
			for j in 0..<num_e {
				draw_laser_bolt(enemy_spots[j], def_pos, f32(j) * 2.3, rl.RED)
			}
		} else {
			num_tc := pmc
			for j in 0..<num_e {
				if num_tc == 0 { break }
				draw_laser_bolt(enemy_spots[j], player_miner_spots[j % num_tc], f32(j) * 2.3, rl.RED)
			}
		}
	} else if num_p > 0 {
		if emc > 0 {
			num_tc := emc
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], enemy_miner_spots[i % num_tc], f32(i) * 2.3, SCIFI_GREEN) }
		} else if p == ENEMY_HOME && orbital_defense_level[p] > 0 {
			def_pos := orbital_defense_pos(p)
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], def_pos, f32(i) * 2.3, SCIFI_GREEN) }
		} else if enemy_base_hp[p] > 0 {
			base := sector_pos(p) + rl.Vector3{0, sector_radius(p) * 0.6, 0}
			for i in 0..<num_p { draw_laser_bolt(player_spots[i], base, f32(i) * 2.3, SCIFI_GREEN) }
		}
	}
}

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

transit_fighters_at :: proc(target_planet: int, enemy: bool) -> int {
	count := 0
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.kind == .COMBAT && u.state == .TRANSIT && u.target_planet == target_planet && u.enemy == enemy { count += 1 }
	}
	return count
}

miner_stationed_planet :: proc(u: ^Unit) -> int {
	if u.state == .TRANSIT { return -1 }
	if u.enemy { return u.affiliation }
	if u.target_planet >= 0 && u.target_planet < SECTOR_COUNT { return u.target_planet }
	if u.affiliation >= 0 && u.affiliation < SECTOR_COUNT { return u.affiliation }
	return EARTH
}

SELECTION_RING_SEGMENTS :: 24
SELECTION_RING_RADIUS   :: 0.78
SELECTION_RING_GAP      :: 0.22

selection_ring_dirs: [SELECTION_RING_SEGMENTS + 1][2]f32

@(init)
init_selection_ring_dirs :: proc "contextless" () {
	for i in 0..=SELECTION_RING_SEGMENTS {
		angle := f32(i) * 2 * math.PI / f32(SELECTION_RING_SEGMENTS)
		selection_ring_dirs[i] = {math.cos(angle), math.sin(angle)}
	}
}

draw_selection_rings :: proc() {
	pulse := 0.65 + 0.35 * math.sin(laser_anim_time * 5.0)
	inner := rl.Fade(SCIFI_GREEN, pulse)
	outer := rl.Fade(SCIFI_GREEN, 0.25 * pulse)
	outer_radius :: SELECTION_RING_RADIUS + SELECTION_RING_GAP
	for i := 0; i < unit_count; i += 1 {
		if !selected_units[i] { continue }
		center := units[i].position
		y := center.y - 0.25
		rlgl.CheckRenderBatchLimit(4 * SELECTION_RING_SEGMENTS)
		rlgl.Begin(rlgl.LINES)
		rlgl.Color4ub(inner.r, inner.g, inner.b, inner.a)
		for segment in 0..<SELECTION_RING_SEGMENTS {
			a := selection_ring_dirs[segment]
			b := selection_ring_dirs[segment + 1]
			rlgl.Vertex3f(center.x + a.x * SELECTION_RING_RADIUS, y, center.z + a.y * SELECTION_RING_RADIUS)
			rlgl.Vertex3f(center.x + b.x * SELECTION_RING_RADIUS, y, center.z + b.y * SELECTION_RING_RADIUS)
		}
		rlgl.Color4ub(outer.r, outer.g, outer.b, outer.a)
		for segment in 0..<SELECTION_RING_SEGMENTS {
			a := selection_ring_dirs[segment]
			b := selection_ring_dirs[segment + 1]
			rlgl.Vertex3f(center.x + a.x * outer_radius, y, center.z + a.y * outer_radius)
			rlgl.Vertex3f(center.x + b.x * outer_radius, y, center.z + b.y * outer_radius)
		}
		rlgl.End()
	}
}

RALLY_RING_SEGMENTS  :: 56
RALLY_RING_RADIUS    :: 1.25
RALLY_RING_WIDTH     :: 0.14
RALLY_RING_LIFT      :: 0.3
RALLY_RING_HEIGHT    :: 1.2
RALLY_PULSE_PERIOD   :: 1.8
RALLY_PULSE_REACH    :: 1.3
RALLY_CHEVRON_HALF_W :: 1.0
RALLY_CHEVRON_H      :: 1.7
RALLY_CHEVRON_DEPTH  :: 0.42
RALLY_HOVER          :: 0.55
RALLY_BOB            :: 0.3
RALLY_BOB_PERIOD     :: 2.5
RALLY_SWAY_DEG       :: 25.0
RALLY_SWAY_PERIOD    :: 5.0

draw_rally_marker :: proc() {
	if earth_rally == NO_RALLY { return }
	p := planets[earth_rally]
	ring := rl.Vector3{p.position.x, p.position.y + p.radius * RALLY_RING_HEIGHT + RALLY_RING_LIFT, p.position.z}
	bob := RALLY_BOB * 0.5 * (1 - math.cos(2 * math.PI * laser_anim_time / RALLY_BOB_PERIOD))
	tip := ring + {0, RALLY_HOVER + bob, 0}
	sway := RALLY_SWAY_DEG * rl.DEG2RAD * math.sin(2 * math.PI * laser_anim_time / RALLY_SWAY_PERIOD)
	draw_rally_chevron(tip, sway)

	phase := math.mod(laser_anim_time, RALLY_PULSE_PERIOD) / RALLY_PULSE_PERIOD
	pulse_r := RALLY_RING_RADIUS + phase * RALLY_PULSE_REACH
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	draw_flat_annulus(ring, 0, RALLY_RING_RADIUS - RALLY_RING_WIDTH, rl.Fade(SCIFI_GREEN, 0.14))
	draw_flat_annulus(ring, RALLY_RING_RADIUS - RALLY_RING_WIDTH, RALLY_RING_RADIUS, rl.Fade(SCIFI_GREEN, 0.95))
	draw_flat_annulus(ring, pulse_r - RALLY_RING_WIDTH * 0.5, pulse_r, rl.Fade(SCIFI_GREEN, 0.75 * (1 - phase)))
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}

draw_rally_chevron :: proc(tip: rl.Vector3, yaw: f32) {
	c, s := math.cos(yaw), math.sin(yaw)
	corner :: proc(tip: rl.Vector3, c, s, x, y, z: f32) -> rl.Vector3 {
		return {tip.x + x * c + z * s, tip.y + y, tip.z - x * s + z * c}
	}
	w, h, d := f32(RALLY_CHEVRON_HALF_W), f32(RALLY_CHEVRON_H), f32(RALLY_CHEVRON_DEPTH * 0.5)
	fl, fr, ft := corner(tip, c, s, -w, h, d), corner(tip, c, s, w, h, d), corner(tip, c, s, 0, 0, d)
	bl, br, bt := corner(tip, c, s, -w, h, -d), corner(tip, c, s, w, h, -d), corner(tip, c, s, 0, 0, -d)
	center := tip + {0, h * 2.0 / 3.0, 0}

	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rally_face(center, fl, fr, ft)
	rally_face(center, bl, br, bt)
	rally_face(center, fl, fr, br, bl)
	rally_face(center, fl, ft, bt, bl)
	rally_face(center, fr, ft, bt, br)
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()

	edges := [?][2]rl.Vector3{{fl, fr}, {fr, ft}, {ft, fl}, {bl, br}, {br, bt}, {bt, bl}, {fl, bl}, {fr, br}, {ft, bt}}
	for e in edges {
		a := center + (e[0] - center) * 1.015
		b := center + (e[1] - center) * 1.015
		rl.DrawLine3D(a, b, SCIFI_MINT)
	}
}

rally_face :: proc(center: rl.Vector3, verts: ..rl.Vector3) {
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(verts[1] - verts[0], verts[2] - verts[0]))
	if rl.Vector3DotProduct(n, verts[0] - center) < 0 { n = -n }
	light := 0.38 + 0.8 * max(rl.Vector3DotProduct(n, rl.Vector3Normalize(PLANET_LIGHT_DIR)), 0) + 0.12 * max(n.y, 0)
	col := rl.Color{
		u8(min(f32(SCIFI_GREEN.r) * light, 255)),
		u8(min(f32(SCIFI_GREEN.g) * light, 255)),
		u8(min(f32(SCIFI_GREEN.b) * light, 255)),
		255,
	}
	for i in 1..<len(verts) - 1 {
		rl.DrawTriangle3D(verts[0], verts[i], verts[i + 1], col)
	}
}

draw_flat_annulus :: proc(center: rl.Vector3, inner, outer: f32, col: rl.Color) {
	rlgl.CheckRenderBatchLimit(6 * RALLY_RING_SEGMENTS)
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	for i in 0..<RALLY_RING_SEGMENTS {
		a0 := 2 * math.PI * f32(i) / RALLY_RING_SEGMENTS
		a1 := 2 * math.PI * f32(i + 1) / RALLY_RING_SEGMENTS
		c0, s0, c1, s1 := math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
		rlgl.Vertex3f(center.x + c0 * inner, center.y, center.z + s0 * inner)
		rlgl.Vertex3f(center.x + c0 * outer, center.y, center.z + s0 * outer)
		rlgl.Vertex3f(center.x + c1 * outer, center.y, center.z + s1 * outer)
		rlgl.Vertex3f(center.x + c0 * inner, center.y, center.z + s0 * inner)
		rlgl.Vertex3f(center.x + c1 * outer, center.y, center.z + s1 * outer)
		rlgl.Vertex3f(center.x + c1 * inner, center.y, center.z + s1 * inner)
	}
	rlgl.End()
}

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

STAR_COUNT :: 280

stars: [STAR_COUNT]rl.Vector3
star_sizes: [STAR_COUNT]f32
star_alphas: [STAR_COUNT]f32

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

star_dot_texture: rl.Texture2D

draw_starfield :: proc() {
	if star_dot_texture.id == 0 {
		img := rl.GenImageColor(16, 16, rl.BLANK)
		rl.ImageDrawCircle(&img, 8, 8, 7, rl.WHITE)
		star_dot_texture = rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(star_dot_texture, .BILINEAR)
		rl.UnloadImage(img)
	}
	w := f32(ui_screen_w())
	h := f32(ui_screen_h())
	view_proj := rl.MatrixPerspective(camera.fovy * rl.DEG2RAD, w / h, f32(rlgl.GetCullDistanceNear()), f32(rlgl.GetCullDistanceFar())) * rl.GetCameraMatrix(camera)
	src := rl.Rectangle{0, 0, 16, 16}
	for i in 0..<STAR_COUNT {
		clip := view_proj * [4]f32{stars[i].x, stars[i].y, stars[i].z, 1}
		if clip.w <= 0 { continue }
		x := (clip.x / clip.w + 1) / 2 * w
		y := (-clip.y / clip.w + 1) / 2 * h
		if !(x >= 0 && x <= w && y >= 0 && y <= h) { continue }
		tint := rl.WHITE
		if i % 4 == 0 { tint = rl.Color{170, 230, 255, 255} }
		d := star_sizes[i] * 2
		rl.DrawTexturePro(star_dot_texture, src, {x - d / 2, y - d / 2, d, d}, {}, 0, rl.Fade(tint, star_alphas[i]))
	}
}

draw_combat_nebulae :: proc() {
	has_any := false
	for s in 0..<SECTOR_COUNT {
		if combat_nebula_intensity[s] > 0.005 || minor_wave_source_nebula_intensity[s] > 0.005 {
			has_any = true
			break
		}
	}
	if !has_any { return }

	viewport_w := f32(ui_screen_w() - SCREEN_PANEL_WIDTH)
	screen_h := f32(ui_screen_h())
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))

	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for s in 0..<SECTOR_COUNT {
		if combat_nebula_intensity[s] > 0.005 {
			draw_sector_nebula(s, combat_nebula_intensity[s], sector_combat_state[s], NEBULA_PALETTE_COMBAT, viewport_w, screen_h, cam_forward, cam_right)
		}
		if minor_wave_source_nebula_intensity[s] > 0.005 {
			draw_sector_nebula(s, minor_wave_source_nebula_intensity[s], false, NEBULA_PALETTE_WARNING, viewport_w, screen_h, cam_forward, cam_right)
		}
	}
}

Nebula_Palette :: struct {
	grand, secondary, far_lobe, near_lobe, corona, inner, spark: [3]u8,
	mid_r, mid_g, mid_b: [2]f32,
}

NEBULA_PALETTE_COMBAT :: Nebula_Palette{
	grand = {160, 12, 35}, secondary = {190, 20, 50}, far_lobe = {195, 18, 42}, near_lobe = {255, 60, 32},
	corona = {255, 55, 28}, inner = {255, 125, 45}, spark = {255, 135, 50},
	mid_r = {235, 20}, mid_g = {35, 25}, mid_b = {30, 20},
}

NEBULA_PALETTE_WARNING :: Nebula_Palette{
	grand = {170, 150, 15}, secondary = {195, 170, 20}, far_lobe = {205, 185, 20}, near_lobe = {255, 225, 30},
	corona = {255, 230, 30}, inner = {255, 245, 90}, spark = {255, 235, 50},
	mid_r = {245, 10}, mid_g = {215, 25}, mid_b = {25, 15},
}

nebula_color :: proc(rgb: [3]u8, alpha: u8) -> rl.Color {
	return rl.Color{rgb.r, rgb.g, rgb.b, alpha}
}

draw_sector_nebula :: proc(s: int, intensity: f32, in_combat: bool, pal: Nebula_Palette, viewport_w, screen_h: f32, cam_forward, cam_right: rl.Vector3) {
	if intensity <= 0.005 { return }

	pos_3d := sector_pos(s)
	cam_to_pos := pos_3d - camera.position
	if rl.Vector3DotProduct(cam_to_pos, cam_forward) <= 0.1 { return }

	screen_pos := ui_world_to_screen(pos_3d)
	if screen_pos.x < -250 || screen_pos.x > viewport_w + 250 || screen_pos.y < -250 || screen_pos.y > screen_h + 250 {
		return
	}

	rad := sector_radius(s)
	limb_3d := pos_3d + cam_right * rad
	limb_screen := ui_world_to_screen(limb_3d)
	base_r := max(rl.Vector2Distance(screen_pos, limb_screen), 14.0)

	t := laser_anim_time
	pulse_speed: f32 = in_combat ? 3.8 : 2.4
	pulse1 := math.sin(t * pulse_speed + f32(s) * 1.8)
	pulse2 := math.sin(t * (pulse_speed * 2.0) + f32(s) * 2.5 + 0.45)
	palpitation := 0.85 + 0.28 * pulse1 + 0.16 * pulse2
	radius_pulse := 1.0 + 0.14 * math.sin(t * (pulse_speed * 0.7) + f32(s))

	effective_intensity := clamp(intensity * palpitation, 0.0, 1.6)

	grand_r := max(base_r * 5.5, 120.0) * radius_pulse
	grand_alpha := u8(clamp(75.0 * effective_intensity, 0, 255))

	secondary_grand_pos := rl.Vector2{
		screen_pos.x + math.cos(t * 0.3 + f32(s)) * (base_r * 1.4),
		screen_pos.y + math.sin(t * 0.25 + f32(s)) * (base_r * 1.0),
	}
	secondary_r := max(base_r * 4.75, 100.0) * radius_pulse
	secondary_alpha := u8(clamp(60.0 * effective_intensity, 0, 255))

	clear := rl.Color{0, 0, 0, 0}
	rl.DrawCircleGradient(screen_pos, grand_r, nebula_color(pal.grand, grand_alpha), clear)
	rl.DrawCircleGradient(secondary_grand_pos, secondary_r, nebula_color(pal.secondary, secondary_alpha), clear)

	for i in 0..<4 {
		fi := f32(i)
		ang := fi * (math.PI * 0.5) + math.sin(t * 0.35 + fi * 1.7 + f32(s)) * 0.45 + f32(s) * 0.8
		dist := max(base_r * (1.9 + 0.3 * math.sin(t * 0.6 + fi * 2.2 + f32(s))), 35.0)
		center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.82}
		r := max(base_r * (1.9 + 0.25 * math.cos(t * 1.0 + fi * 1.5)) * radius_pulse, 32.5)
		alpha := u8(clamp(65.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(center, r, nebula_color(pal.far_lobe, alpha), clear)
	}

	for i in 0..<5 {
		fi := f32(i)
		ang := fi * (2.0 * math.PI / 5.0) + math.sin(t * 0.45 + fi * 1.5 + f32(s)) * 0.38 + f32(s) * 1.3
		dist := max(base_r * (1.15 + 0.225 * math.sin(t * 0.75 + fi * 1.9 + f32(s))), 22.5)
		center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.84}
		r := max(base_r * (1.5 + 0.225 * math.cos(t * 1.2 + fi * 1.8)) * radius_pulse, 25.0)
		alpha := u8(clamp(90.0 * effective_intensity, 0, 255))
		r_val := u8(clamp(pal.mid_r[0] + pal.mid_r[1] * math.sin(fi * 2.0), 0, 255))
		g_val := u8(clamp(pal.mid_g[0] + pal.mid_g[1] * math.cos(fi * 1.6), 0, 255))
		b_val := u8(clamp(pal.mid_b[0] + pal.mid_b[1] * math.sin(fi * 3.0), 0, 255))
		rl.DrawCircleGradient(center, r, rl.Color{r_val, g_val, b_val, alpha}, clear)
	}

	for i in 0..<3 {
		fi := f32(i)
		ang := fi * (2.0 * math.PI / 3.0) + math.sin(t * 0.5 + fi * 2.1 + f32(s)) * 0.3 + f32(s) * 0.4
		dist := max(base_r * (0.65 + 0.15 * math.sin(t * 0.9 + fi * 2.5)), 12.5)
		center := rl.Vector2{screen_pos.x + math.cos(ang) * dist, screen_pos.y + math.sin(ang) * dist * 0.86}
		r := max(base_r * (1.2 + 0.175 * math.cos(t * 1.3 + fi * 2.0)) * radius_pulse, 20.0)
		alpha := u8(clamp(110.0 * effective_intensity, 0, 255))
		rl.DrawCircleGradient(center, r, nebula_color(pal.near_lobe, alpha), clear)
	}

	corona_r := max(base_r * 1.4, 22.5) * radius_pulse
	corona_alpha := u8(clamp(135.0 * effective_intensity, 0, 255))
	rl.DrawCircleGradient(screen_pos, corona_r, nebula_color(pal.corona, corona_alpha), clear)

	inner_core_r := max(base_r * 1.2, 16.0) * (0.95 + 0.1 * palpitation)
	inner_alpha := u8(clamp(115.0 * effective_intensity, 0, 255))
	rl.DrawCircleGradient(screen_pos, inner_core_r, nebula_color(pal.inner, inner_alpha), clear)

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
		rl.DrawCircleGradient(spark_pos, spark_r, nebula_color(pal.spark, spark_alpha), clear)
	}
}

draw_low_poly_sphere :: proc(center: rl.Vector3, radius: f32, color: rl.Color) {
	rl.DrawSphereEx(center, radius, 6, 8, color)
}
