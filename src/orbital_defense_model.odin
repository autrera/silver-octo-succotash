package main

import "core:math"
import rl "vendor:raylib"

Battery_Part :: enum {
	BASE,
	TURRET,
	GUN,
	RAM,
}

BATTERY_RAM_LENGTH :: 0.13

BATTERY_SAND       :: rl.Color{214, 182, 134, 255}
BATTERY_SAND_PANEL :: rl.Color{230, 200, 154, 255}
BATTERY_SAND_DARK  :: rl.Color{160, 132, 92, 255}
BATTERY_SAND_LIGHT :: rl.Color{240, 215, 175, 255}
BATTERY_GUNMETAL   :: rl.Color{46, 51, 59, 255}
BATTERY_FRAME      :: rl.Color{72, 80, 92, 255}
BATTERY_STEEL      :: rl.Color{155, 165, 180, 255}
BATTERY_HAZARD     :: rl.Color{236, 186, 44, 255}
BATTERY_VOID       :: rl.Color{12, 13, 16, 255}

battery_models: [Battery_Part]rl.Model
battery_instances: [Battery_Part][PLANET_COUNT]rl.Matrix
battery_instance_count: [Battery_Part]int
battery_effects: [PLANET_COUNT]int
battery_effect_count: int
battery_visuals_ready := false

orbital_defense_scale :: proc(p: int) -> f32 {
	return 0.84 + clamp(planets[p].radius * 0.07, 0.11, 0.32)
}

orbital_defense_pole :: proc(p: int) -> rl.Vector3 {
	return planets[p].position + {0, planets[p].radius, 0}
}

orbital_defense_axes :: proc(azimuth, elev: f32) -> (fwd, right, dir, nrm: rl.Vector3) {
	up := rl.Vector3{0, 1, 0}
	fwd = {math.cos(azimuth), 0, math.sin(azimuth)}
	right = {-math.sin(azimuth), 0, math.cos(azimuth)}
	dir = fwd * math.cos(elev) + up * math.sin(elev)
	nrm = -fwd * math.sin(elev) + up * math.cos(elev)
	return
}

orbital_defense_build_progress :: proc(p: int) -> f32 {
	return clamp(orbital_defense_progress[p] / ORBITAL_DEFENSE_BUILD_TIME, 0.05, 0.95)
}

orbital_defense_pivot :: proc(p: int, fwd: rl.Vector3) -> rl.Vector3 {
	s := orbital_defense_scale(p)
	return orbital_defense_pole(p) + rl.Vector3{0, ORBITAL_DEFENSE_PIVOT.y * s, 0} + fwd * (ORBITAL_DEFENSE_PIVOT.x * s)
}

quad_point :: proc(q: [4]rl.Vector3, u, v: f32) -> rl.Vector3 {
	lo := q[0] + (q[1] - q[0]) * u
	hi := q[3] + (q[2] - q[3]) * u
	return lo + (hi - lo) * v
}

box_face :: proc(center, half_u, half_v, out: rl.Vector3) -> [4]rl.Vector3 {
	c := center + out
	return {c - half_u - half_v, c + half_u - half_v, c + half_u + half_v, c - half_u + half_v}
}

battery_decal :: proc(b: ^HQ_Builder, q: [4]rl.Vector3, n: rl.Vector3, u0, u1, v0, v1: f32, col: rl.Color, glow: f32 = 0, surf: f32 = SURF_PLAIN) {
	off := n * 0.002
	hq_quad(b, quad_point(q, u0, v0) + off, quad_point(q, u1, v0) + off, quad_point(q, u1, v1) + off, quad_point(q, u0, v1) + off, n, col, glow, surf)
}

battery_panel :: proc(b: ^HQ_Builder, q: [4]rl.Vector3, n: rl.Vector3, u0, u1, v0, v1, height: f32, col: rl.Color, surf: f32 = SURF_PLATED) {
	off := n * 0.001
	base := [4]rl.Vector3{quad_point(q, u0, v0) + off, quad_point(q, u1, v0) + off, quad_point(q, u1, v1) + off, quad_point(q, u0, v1) + off}
	drone_raised_quad(b, base, n, height, 0.12, col, surf)
}

battery_plate :: proc(b: ^HQ_Builder, q: [4]rl.Vector3, thickness: f32, hint: rl.Vector3, col: rl.Color, surf: f32 = SURF_PLATED) -> rl.Vector3 {
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(q[1] - q[0], q[3] - q[0]))
	if rl.Vector3DotProduct(n, hint) < 0 { n = -n }
	off := -n * thickness
	c := (q[0] + q[1] + q[2] + q[3]) * 0.25
	hq_quad(b, q[0], q[1], q[2], q[3], n, col, 0, surf)
	hq_quad(b, q[0] + off, q[1] + off, q[2] + off, q[3] + off, -n, col, 0, surf)
	for k in 0..<4 {
		j := (k + 1) % 4
		hq_face(b, q[k], q[j], q[j] + off, q[k] + off, (q[k] + q[j]) * 0.5 - c, col, 0, surf)
	}
	return n
}

build_battery_base :: proc(b: ^HQ_Builder) {
	up := rl.Vector3{0, 1, 0}

	drone_prism(b, Prism{start = -up * 0.12, end = up * 0.02, r0 = 0.47, r1 = 0.45, sides = 12}, BATTERY_GUNMETAL, 0, SURF_METAL)
	low := Prism{start = up * 0.02, end = up * 0.12, r0 = 0.44, r1 = 0.40, sides = 12}
	drone_prism(b, low, BATTERY_GUNMETAL, 0, SURF_PLATED)
	drone_prism(b, Prism{start = up * 0.105, end = up * 0.135, r0 = 0.414, r1 = 0.404, sides = 12, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)
	high := Prism{start = up * 0.12, end = up * 0.22, r0 = 0.40, r1 = 0.36, sides = 12}
	drone_prism(b, high, BATTERY_SAND_DARK, 0, SURF_PLATED)
	for i in 0..<12 {
		drone_facet_panel(b, low, i, 0.4, 0.6, 0.25, 0.6, 0.008, BATTERY_FRAME, SURF_METAL)
		if i % 2 == 0 {
			drone_facet_panel(b, high, i, 0.12, 0.88, 0.18, 0.86, 0.01, BATTERY_SAND)
			continue
		}
		for k in 0..<3 {
			t := 0.22 + f32(k) * 0.22
			drone_facet_decal(b, high, i, 0.25, 0.75, t, t + 0.1, 0.002, BATTERY_GUNMETAL)
		}
	}

	tt := Prism{start = up * 0.22, end = up * 0.30, r0 = 0.35, r1 = 0.35, sides = 16}
	drone_prism(b, tt, BATTERY_GUNMETAL, 0, SURF_METAL)
	for k in 0..<24 {
		a := f32(k) * 2 * math.PI / 24
		dir := rl.Vector3{math.cos(a), 0, math.sin(a)}
		tan := rl.Vector3{-dir.z, 0, dir.x}
		hq_box(b, dir * 0.352 + up * 0.25, 0.016, 0.026, 0.014, dir, up, tan, BATTERY_FRAME, 0, SURF_METAL)
	}
	drone_prism(b, Prism{start = up * 0.30, end = up * 0.312, r0 = 0.342, r1 = 0.336, sides = 16}, SCIFI_GREEN, 0.9, SURF_FLOW)

	for d in 0..<4 {
		a := f32(d) * math.PI / 2
		dir := rl.Vector3{math.cos(a), 0, math.sin(a)}
		tan := rl.Vector3{-dir.z, 0, dir.x}
		l0 := dir * 0.30 + up * 0.10
		l1 := dir * 0.78 + up * 0.03
		leg := Prism{start = l0, end = l1, r0 = 0.085, r1 = 0.062, sides = 6}
		drone_prism(b, leg, BATTERY_SAND, 0, SURF_PLATED)
		for i in 0..<leg.sides {
			n := prism_facet_normal(leg, i)
			if n.y > 0.8 {
				drone_facet_decal(b, leg, i, 0.3, 0.7, 0.16, 0.9, 0.002, SCIFI_GREEN, 0.9, SURF_FLOW)
			} else if n.y > -0.2 {
				drone_facet_panel(b, leg, i, 0.14, 0.86, 0.22, 0.5, 0.007, BATTERY_SAND_PANEL)
				drone_facet_panel(b, leg, i, 0.14, 0.86, 0.56, 0.74, 0.007, BATTERY_SAND_PANEL)
			}
		}
		drone_prism(b, Prism{start = l0 - dir * 0.02, end = l0 + dir * 0.11, r0 = 0.098, r1 = 0.094, sides = 6}, BATTERY_GUNMETAL, 0, SURF_METAL)
		drone_prism(b, Prism{start = l0 + (l1 - l0) * 0.8, end = l0 + (l1 - l0) * 0.86, r0 = 0.072, r1 = 0.071, sides = 6, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)

		for s in ([2]f32{-1, 1}) {
			root := dir * 0.355 + up * 0.17 + tan * (s * 0.058)
			tip := l0 + (l1 - l0) * 0.58 + tan * (s * 0.056) + up * 0.012
			hq_cyl(b, root, root + (tip - root) * 0.5, 0.02, 0.019, 6, BATTERY_GUNMETAL, 0, SURF_METAL)
			hq_cyl(b, root, tip, 0.011, 0.011, 6, BATTERY_STEEL, 0, SURF_METAL)
			drone_sphere(b, tip, 0.017, 3, 6, BATTERY_GUNMETAL, 0, SURF_METAL)
		}

		pad_c := dir * 0.80
		drone_prism(b, Prism{start = pad_c - up * 0.26, end = pad_c - up * 0.02, r0 = 0.06, r1 = 0.12, sides = 8, roll = math.PI / 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
		drone_prism(b, Prism{start = pad_c - up * 0.02, end = pad_c + up * 0.06, r0 = 0.15, r1 = 0.13, sides = 8, roll = math.PI / 8}, BATTERY_GUNMETAL, 0, SURF_PLATED)
		drone_prism(b, Prism{start = pad_c, end = pad_c + up * 0.028, r0 = 0.149, r1 = 0.143, sides = 8, roll = math.PI / 8, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)
		drone_prism(b, Prism{start = pad_c + up * 0.06, end = pad_c + up * 0.068, r0 = 0.118, r1 = 0.112, sides = 8, roll = math.PI / 8}, SCIFI_GREEN, 0.8)
		drone_prism(b, Prism{start = pad_c + up * 0.068, end = pad_c + up * 0.15, r0 = 0.045, r1 = 0.04, sides = 6}, BATTERY_STEEL, 0, SURF_METAL)
		drone_prism(b, Prism{start = pad_c + up * 0.15, end = pad_c + up * 0.168, r0 = 0.05, r1 = 0.036, sides = 6}, BATTERY_GUNMETAL, 0, SURF_METAL)
		drone_sphere(b, pad_c + up * 0.178, 0.016, 3, 6, SCIFI_GREEN, 1, SURF_BEACON)
	}
}

build_battery_turret :: proc(b: ^HQ_Builder) {
	fwd := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	right := rl.Vector3{0, 0, 1}
	s_signs := [2]f32{-1, 1}

	deck := Prism{start = up * 0.30, end = up * 0.38, r0 = 0.33, r1 = 0.31, sides = 8, roll = math.PI / 8}
	drone_prism(b, deck, BATTERY_SAND, 0, SURF_PLATED)
	for i in 0..<deck.sides {
		drone_facet_panel(b, deck, i, 0.14, 0.86, 0.2, 0.78, 0.008, BATTERY_SAND_PANEL)
	}
	drone_prism(b, Prism{start = up * 0.374, end = up * 0.388, r0 = 0.318, r1 = 0.31, sides = 8, roll = math.PI / 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
	hq_box(b, fwd * 0.10 + up * 0.39, 0.04, 0.012, 0.045, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_METAL)

	for s in s_signs {
		hq_box(b, -fwd * 0.14 + up * 0.41 + right * (s * 0.25), 0.04, 0.03, 0.07, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_PLATED)
		locker := box_face(-fwd * 0.14 + up * 0.41 + right * (s * 0.25), fwd * 0.07, up * 0.03, right * (s * 0.04))
		battery_decal(b, locker, right * s, 0.12, 0.88, 0.3, 0.7, BATTERY_HAZARD, 0, SURF_HAZARD)
	}

	for s in s_signs {
		side := right * s
		c := up * 0.51 + side * 0.16
		hq_box(b, c, 0.045, 0.14, 0.13, fwd, up, right, BATTERY_SAND, 0, SURF_PLATED)
		outer := box_face(c, fwd * 0.13, up * 0.14, side * 0.045)
		battery_panel(b, outer, side, 0.1, 0.9, 0.12, 0.74, 0.012, BATTERY_SAND_PANEL)
		battery_decal(b, outer, side, 0.16, 0.84, 0.82, 0.88, SCIFI_GREEN, 0.9, SURF_FLOW)
		front := box_face(c, side * 0.045, up * 0.14, fwd * 0.13)
		battery_decal(b, front, fwd, 0, 1, 0.04, 0.24, BATTERY_HAZARD, 0, SURF_HAZARD)
		for k in 0..<3 {
			v := 0.38 + f32(k) * 0.12
			battery_decal(b, front, fwd, 0.25, 0.75, v, v + 0.06, BATTERY_GUNMETAL)
		}

		axle := up * 0.58 + side * 0.205
		drone_prism(b, Prism{start = axle, end = axle + side * 0.045, r0 = 0.085, r1 = 0.08, sides = 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
		drone_prism(b, Prism{start = axle + side * 0.045, end = axle + side * 0.051, r0 = 0.056, r1 = 0.054, sides = 8}, SCIFI_GREEN, 0.9, SURF_FLOW)
		drone_prism(b, Prism{start = axle + side * 0.051, end = axle + side * 0.064, r0 = 0.024, r1 = 0.02, sides = 6}, BATTERY_STEEL, 0, SURF_METAL)
		for k in 0..<6 {
			a := f32(k) * math.PI / 3
			bolt := axle + side * 0.047 + (up * math.cos(a) + fwd * math.sin(a)) * 0.068
			hq_box(b, bolt, 0.008, 0.008, 0.008, fwd, up, right, BATTERY_STEEL, 0, SURF_METAL)
		}
	}
	hq_cyl(b, up * 0.58 - right * 0.23, up * 0.58 + right * 0.23, 0.055, 0.055, 8, BATTERY_STEEL, 0, SURF_METAL)

	sh := fwd * 0.19 + up * 0.58
	for s in s_signs {
		side := right * s
		pc := sh + side * 0.14
		hq_box(b, pc - fwd * 0.02, 0.076, 0.226, 0.008, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_METAL)
		hq_box(b, pc, 0.07, 0.22, 0.015, fwd, up, right, BATTERY_SAND, 0, SURF_PLATED)
		face := box_face(pc, side * 0.07, up * 0.22, fwd * 0.015)
		battery_decal(b, face, fwd, 0, 1, 0.01, 0.09, BATTERY_HAZARD, 0, SURF_HAZARD)
		battery_panel(b, face, fwd, 0.1, 0.9, 0.12, 0.47, 0.01, BATTERY_SAND_PANEL)
		battery_panel(b, face, fwd, 0.1, 0.9, 0.52, 0.84, 0.01, BATTERY_SAND_PANEL)

		root := sh + side * 0.21
		tip := root + side * 0.16 - fwd * 0.14
		wing := [4]rl.Vector3{root - up * 0.21, tip - up * 0.21, tip + up * 0.21, root + up * 0.21}
		wn := battery_plate(b, wing, 0.02, fwd * 0.16 + side * 0.14, BATTERY_SAND_DARK)
		battery_panel(b, wing, wn, 0.08, 0.7, 0.1, 0.9, 0.01, BATTERY_SAND)
		battery_decal(b, wing, wn, 0.78, 0.96, 0.04, 0.96, BATTERY_HAZARD, 0, SURF_HAZARD)
		hq_beam(b, root + up * 0.214 - wn * 0.01, tip + up * 0.214 - wn * 0.01, 0.016, 0.008, up, BATTERY_GUNMETAL, 0, SURF_METAL)
		hq_beam(b, tip - up * 0.2 - wn * 0.01, tip + up * 0.2 - wn * 0.01, 0.006, 0.014, wn, SCIFI_GREEN, 0.9, SURF_FLOW)
	}
	hq_box(b, sh + up * 0.19, 0.22, 0.03, 0.015, fwd, up, right, BATTERY_SAND_LIGHT, 0, SURF_PLATED)
	hq_box(b, sh + up * 0.224, 0.226, 0.006, 0.02, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_METAL)
	bar := box_face(sh + up * 0.19, right * 0.22, up * 0.03, fwd * 0.015)
	battery_decal(b, bar, fwd, 0.08, 0.92, 0.3, 0.55, SCIFI_GREEN, 0.9, SURF_FLOW)

	pod := sh - right * 0.15 + up * 0.10 + fwd * 0.04
	hq_box(b, pod, 0.055, 0.065, 0.075, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_METAL)
	pod_side := box_face(pod, fwd * 0.075, up * 0.065, -right * 0.055)
	for k in 0..<3 {
		v := 0.25 + f32(k) * 0.2
		battery_decal(b, pod_side, -right, 0.2, 0.8, v, v + 0.08, BATTERY_VOID)
	}
	lenses := [2]rl.Vector3{pod + fwd * 0.075 + up * 0.024, pod + fwd * 0.075 - up * 0.026}
	drone_prism(b, Prism{start = lenses[0] - fwd * 0.005, end = lenses[0] + fwd * 0.03, r0 = 0.03, r1 = 0.03, sides = 8, open = true}, BATTERY_FRAME, 0, SURF_METAL)
	drone_prism(b, Prism{start = lenses[1] - fwd * 0.005, end = lenses[1] + fwd * 0.03, r0 = 0.034, r1 = 0.034, sides = 8, open = true}, BATTERY_FRAME, 0, SURF_METAL)
	drone_sphere(b, lenses[0] + fwd * 0.008, 0.024, 4, 8, SCIFI_GREEN, 1)
	drone_sphere(b, lenses[1] + fwd * 0.008, 0.028, 4, 8, SCIFI_AMBER, 1)
	hq_cyl(b, pod + up * 0.065 - fwd * 0.04, pod + up * 0.13 - fwd * 0.06, 0.008, 0.004, 4, BATTERY_STEEL, 0, SURF_METAL)

	mast_b := sh + right * 0.19 + up * 0.22
	mast_t := mast_b + up * 0.30 - fwd * 0.04
	hq_box(b, mast_b + up * 0.012, 0.025, 0.014, 0.025, fwd, up, right, BATTERY_GUNMETAL, 0, SURF_METAL)
	hq_cyl(b, mast_b, mast_t, 0.016, 0.007, 6, BATTERY_STEEL, 0, SURF_METAL)
	for k in 0..<2 {
		m := mast_b + (mast_t - mast_b) * (0.5 + f32(k) * 0.2)
		w := 0.045 - f32(k) * 0.015
		hq_beam(b, m - fwd * w, m + fwd * w, 0.004, 0.004, up, BATTERY_STEEL, 0, SURF_METAL)
	}
	drone_sphere(b, mast_t, 0.022, 4, 6, SCIFI_GREEN, 1, SURF_BEACON)
}

build_battery_gun :: proc(b: ^HQ_Builder) {
	dir := rl.Vector3{1, 0, 0}
	nrm := rl.Vector3{0, 1, 0}
	right := rl.Vector3{0, 0, 1}

	breech := -dir * 0.16
	hq_box(b, breech, 0.10, 0.09, 0.15, dir, nrm, right, BATTERY_GUNMETAL, 0, SURF_METAL)
	hq_box(b, breech + nrm * 0.08, 0.09, 0.025, 0.14, dir, nrm, right, BATTERY_SAND, 0, SURF_PLATED)
	for s in ([2]f32{-1, 1}) {
		side := right * s
		hq_box(b, breech + side * 0.105, 0.008, 0.045, 0.11, dir, nrm, right, SCIFI_GREEN, 0.9, SURF_FLOW)
		cheek := box_face(breech, dir * 0.15, nrm * 0.09, side * 0.10)
		battery_panel(b, cheek, side, 0.04, 0.2, 0.15, 0.85, 0.006, BATTERY_FRAME, SURF_METAL)
		battery_panel(b, cheek, side, 0.8, 0.96, 0.15, 0.85, 0.006, BATTERY_FRAME, SURF_METAL)
	}
	for k in 0..<5 {
		hq_box(b, breech + nrm * 0.11 + dir * (-0.11 + f32(k) * 0.055), 0.08, 0.008, 0.008, dir, nrm, right, BATTERY_GUNMETAL, 0, SURF_METAL)
	}
	rear := box_face(breech, right * 0.10, nrm * 0.09, -dir * 0.15)
	battery_panel(b, rear, -dir, 0.15, 0.85, 0.15, 0.85, 0.01, BATTERY_FRAME, SURF_PLATED)
	battery_decal(b, rear, -dir, 0.25, 0.75, 0.42, 0.58, SCIFI_MINT, 1, SURF_ENGINE)
	hq_beam(b, breech - dir * 0.165 - right * 0.05 - nrm * 0.05, breech - dir * 0.165 + right * 0.05 - nrm * 0.05, 0.008, 0.008, dir, BATTERY_STEEL, 0, SURF_METAL)

	rc_s := -dir * 0.18 + nrm * 0.11
	rc_e := dir * 0.35 + nrm * 0.11
	hq_cyl(b, rc_s, rc_e, 0.045, 0.045, 8, BATTERY_STEEL, 0, SURF_METAL)
	drone_prism(b, Prism{start = rc_s, end = rc_s + dir * 0.06, r0 = 0.058, r1 = 0.058, sides = 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
	drone_prism(b, Prism{start = rc_e - dir * 0.05, end = rc_e + dir * 0.004, r0 = 0.052, r1 = 0.05, sides = 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
	drone_prism(b, Prism{start = rc_s + dir * 0.13, end = rc_s + dir * 0.145, r0 = 0.049, r1 = 0.049, sides = 8}, SCIFI_GREEN, 0.9, SURF_FLOW)
	rp_s := -dir * 0.14 - nrm * 0.09
	rp_e := dir * 0.28 - nrm * 0.09
	hq_cyl(b, rp_s, rp_e, 0.038, 0.038, 8, BATTERY_STEEL, 0, SURF_METAL)
	drone_prism(b, Prism{start = rp_e - dir * 0.04, end = rp_e + dir * 0.004, r0 = 0.046, r1 = 0.044, sides = 8}, BATTERY_GUNMETAL, 0, SURF_METAL)

	jacket := Prism{start = {}, end = dir * 0.45, r0 = 0.088, r1 = 0.076, sides = 10}
	drone_prism(b, jacket, BATTERY_SAND, 0, SURF_PLATED)
	for i in 0..<jacket.sides {
		if i % 2 == 1 { continue }
		drone_facet_panel(b, jacket, i, 0.18, 0.82, 0.26, 0.82, 0.006, BATTERY_SAND_PANEL)
	}
	drone_prism(b, Prism{start = -dir * 0.005, end = dir * 0.09, r0 = 0.10, r1 = 0.10, sides = 10}, BATTERY_GUNMETAL, 0, SURF_METAL)
	drone_prism(b, Prism{start = dir * 0.395, end = dir * 0.44, r0 = 0.0815, r1 = 0.0805, sides = 10, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)

	drone_prism(b, Prism{start = dir * 0.45, end = dir * 1.25, r0 = 0.070, r1 = 0.058, sides = 10}, BATTERY_GUNMETAL, 0, SURF_METAL)
	for c_i in 0..<4 {
		x := 0.45 + 0.75 * (0.12 + f32(c_i) * 0.25)
		drone_prism(b, Prism{start = dir * x, end = dir * (x + 0.038), r0 = 0.082, r1 = 0.082, sides = 10}, SCIFI_GREEN, 0.9, SURF_FLOW)
		drone_prism(b, Prism{start = dir * (x - 0.006), end = dir * (x + 0.004), r0 = 0.088, r1 = 0.088, sides = 10}, BATTERY_FRAME, 0, SURF_METAL)
		drone_prism(b, Prism{start = dir * (x + 0.034), end = dir * (x + 0.044), r0 = 0.088, r1 = 0.088, sides = 10}, BATTERY_FRAME, 0, SURF_METAL)
	}
	for k in 0..<4 {
		a := f32(k) * math.PI / 2 + math.PI / 4
		off := (nrm * math.cos(a) + right * math.sin(a)) * 0.074
		hq_cyl(b, dir * 0.52 + off, dir * 1.16 + off, 0.007, 0.007, 4, BATTERY_STEEL, 0, SURF_METAL)
	}
	drone_prism(b, Prism{start = dir * 1.22, end = dir * 1.28, r0 = 0.068, r1 = 0.066, sides = 10}, BATTERY_FRAME, 0, SURF_METAL)

	drone_prism(b, Prism{start = dir * 1.25, end = dir * 1.75, r0 = 0.054, r1 = 0.044, sides = 10}, BATTERY_SAND, 0, SURF_PLATED)
	drone_prism(b, Prism{start = dir * 1.66, end = dir * 1.70, r0 = 0.0475, r1 = 0.0467, sides = 10, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)

	brake := Prism{start = dir * 1.75, end = dir * ORBITAL_DEFENSE_MUZZLE_REACH, r0 = 0.074, r1 = 0.074, sides = 8, roll = math.PI / 8}
	drone_prism(b, brake, BATTERY_GUNMETAL, 0, SURF_METAL)
	for x in ([2]f32{1.81, 1.88}) {
		drone_prism(b, Prism{start = dir * x, end = dir * (x + 0.03), r0 = 0.092, r1 = 0.092, sides = 8, roll = math.PI / 8}, BATTERY_FRAME, 0, SURF_METAL)
	}
	for i in 0..<brake.sides {
		drone_facet_decal(b, brake, i, 0.25, 0.75, 0.08, 0.24, 0.002, BATTERY_VOID)
		drone_facet_decal(b, brake, i, 0.25, 0.75, 0.44, 0.56, 0.002, BATTERY_VOID)
		drone_facet_decal(b, brake, i, 0.25, 0.75, 0.76, 0.92, 0.002, BATTERY_VOID)
	}
	muzzle := dir * ORBITAL_DEFENSE_MUZZLE_REACH
	drone_prism(b, Prism{start = muzzle, end = muzzle + dir * 0.006, r0 = 0.05, r1 = 0.048, sides = 10}, SCIFI_MINT, 1)
	drone_sphere(b, muzzle + dir * 0.008, 0.032, 4, 8, SCIFI_GREEN, 1, SURF_ENGINE)
}

build_battery_ram :: proc(b: ^HQ_Builder) {
	dir := rl.Vector3{1, 0, 0}
	drone_prism(b, Prism{start = -dir * 0.01, end = dir * (BATTERY_RAM_LENGTH * 0.55), r0 = 0.058, r1 = 0.058, sides = 8}, BATTERY_GUNMETAL, 0, SURF_METAL)
	drone_prism(b, Prism{start = dir * (BATTERY_RAM_LENGTH * 0.18), end = dir * (BATTERY_RAM_LENGTH * 0.3), r0 = 0.061, r1 = 0.061, sides = 8, open = true}, BATTERY_HAZARD, 0, SURF_HAZARD)
	drone_prism(b, Prism{start = dir * (BATTERY_RAM_LENGTH * 0.55), end = dir * (BATTERY_RAM_LENGTH + 0.01), r0 = 0.036, r1 = 0.034, sides = 8}, BATTERY_STEEL, 0, SURF_METAL)
}

init_orbital_defense_visuals :: proc() {
	if battery_visuals_ready || !drone_visuals_ready { return }
	for part in Battery_Part {
		b: HQ_Builder
		switch part {
		case .BASE:   build_battery_base(&b)
		case .TURRET: build_battery_turret(&b)
		case .GUN:    build_battery_gun(&b)
		case .RAM:    build_battery_ram(&b)
		}
		battery_models[part] = finish_drone_model(&b)
	}
	battery_visuals_ready = true
}

unload_orbital_defense_visuals :: proc() {
	if !battery_visuals_ready { return }
	for part in Battery_Part {
		unload_drone_model(battery_models[part])
	}
	battery_visuals_ready = false
}

queue_battery_part :: proc(part: Battery_Part, origin, x, y, z: rl.Vector3, dim: f32) {
	n := battery_instance_count[part]
	if n >= PLANET_COUNT { return }
	battery_instances[part][n] = instance_transform(origin, x, y, z, dim)
	battery_instance_count[part] = n + 1
}

draw_orbital_defense :: proc(p: int) {
	if p < 0 || p >= PLANET_COUNT { return }
	built := orbital_defense_level[p] > 0
	if !built && !orbital_defense_building[p] { return }
	s := orbital_defense_scale(p)
	pole := orbital_defense_pole(p)
	up := rl.Vector3{0, 1, 0}
	if !battery_visuals_ready {
		draw_low_poly_sphere(pole + up * (0.3 * s), 0.3 * s, SCIFI_GREEN)
		return
	}

	dim: f32 = orbital_defense_building[p] ? 1 : 0
	spin := planet_spin[p]
	base := built ? pole : pole - up * (0.3 * s * (1 - orbital_defense_build_progress(p)))
	queue_battery_part(.BASE, base, rl.Vector3{math.cos(spin), 0, -math.sin(spin)} * s, up * s, rl.Vector3{math.sin(spin), 0, math.cos(spin)} * s, dim)
	if dim > 0 && battery_effect_count < PLANET_COUNT {
		battery_effects[battery_effect_count] = p
		battery_effect_count += 1
	}
	if !built { return }

	az, el := orbital_defense_aim(p)
	fwd, right, dir, nrm := orbital_defense_axes(az, el)
	pivot := orbital_defense_pivot(p, fwd)
	queue_battery_part(.TURRET, pole, fwd * s, up * s, right * s, dim)
	queue_battery_part(.GUN, pivot, dir * s, nrm * s, right * s, dim)

	ram_b := pole + up * (0.37 * s) + fwd * (0.10 * s)
	ram := pivot - up * (0.05 * s) - nrm * (0.07 * s) - ram_b
	ram_len := rl.Vector3Length(ram)
	ram_dir := ram / ram_len
	queue_battery_part(.RAM, ram_b, ram_dir * (ram_len / BATTERY_RAM_LENGTH), rl.Vector3CrossProduct(right, ram_dir) * s, right * s, dim)
}

flush_orbital_defenses :: proc() {
	if !battery_visuals_ready { return }
	set_drone_shader_frame(DRONE_RIM_PLAYER)
	for part in Battery_Part {
		n := battery_instance_count[part]
		if n == 0 { continue }
		model := battery_models[part]
		rl.DrawMeshInstanced(model.meshes[0], model.materials[0], &battery_instances[part][0], i32(n))
		battery_instance_count[part] = 0
	}
	for i in 0..<battery_effect_count {
		p := battery_effects[i]
		if orbital_defense_level[p] > 0 {
			draw_battery_hazard_lights(p)
		} else {
			draw_battery_construction_effects(p)
		}
	}
	battery_effect_count = 0
}

draw_ambulance_hazard_lights :: proc(p_left, p_right: rl.Vector3, s: f32) {
	t := laser_anim_time * 12.0
	phase := math.sin(t)
	pulse_l := clamp((phase - 0.1) * 2.2, 0.0, 1.0)
	pulse_r := clamp((-phase - 0.1) * 2.2, 0.0, 1.0)

	rl.DrawCylinderEx(p_left, p_right, 0.016 * s, 0.016 * s, 6, rl.Color{45, 48, 55, 255})

	rl.DrawCylinderEx(p_left - {0, 0.05 * s, 0}, p_left, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_l > 0.05 {
		draw_low_poly_sphere(p_left, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_left, 0.09 * s * pulse_l + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_l)})
		rl.DrawSphereEx(p_left, 0.18 * s * pulse_l + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_l)})
	} else {
		draw_low_poly_sphere(p_left, 0.032 * s, rl.Color{110, 20, 25, 255})
	}

	rl.DrawCylinderEx(p_right - {0, 0.05 * s, 0}, p_right, 0.026 * s, 0.024 * s, 6, rl.Color{35, 38, 44, 255})
	if pulse_r > 0.05 {
		draw_low_poly_sphere(p_right, 0.038 * s, rl.Color{255, 245, 245, 255})
		rl.DrawSphereEx(p_right, 0.09 * s * pulse_r + 0.02 * s, 8, 8, rl.Color{255, 30, 35, u8(230 * pulse_r)})
		rl.DrawSphereEx(p_right, 0.18 * s * pulse_r + 0.03 * s, 6, 6, rl.Color{255, 10, 15, u8(95 * pulse_r)})
	} else {
		draw_low_poly_sphere(p_right, 0.032 * s, rl.Color{110, 20, 25, 255})
	}
}

draw_battery_hazard_lights :: proc(p: int) {
	s := orbital_defense_scale(p)
	az, _ := orbital_defense_aim(p)
	fwd, right, _, _ := orbital_defense_axes(az, 0)
	sh := orbital_defense_pole(p) + rl.Vector3{0, 0.84 * s, 0} + fwd * (0.19 * s)
	draw_ambulance_hazard_lights(sh - right * (0.16 * s), sh + right * (0.16 * s), s)
}

draw_battery_construction_effects :: proc(p: int) {
	pole := orbital_defense_pole(p)
	up := rl.Vector3{0, 1, 0}
	s := orbital_defense_scale(p)

	st_l := pole + up * (0.65 * s) - rl.Vector3{0.35 * s, 0, 0}
	st_r := pole + up * (0.65 * s) + rl.Vector3{0.35 * s, 0, 0}
	rl.DrawCylinderEx(pole - rl.Vector3{0.35 * s, 0, 0}, st_l, 0.02 * s, 0.015 * s, 6, BATTERY_GUNMETAL)
	rl.DrawCylinderEx(pole + rl.Vector3{0.35 * s, 0, 0}, st_r, 0.02 * s, 0.015 * s, 6, BATTERY_GUNMETAL)
	draw_ambulance_hazard_lights(st_l, st_r, s)

	pulse := 0.70 + 0.30 * math.sin(laser_anim_time * 3.5)
	rl.DrawSphereWires(pole + up * (0.45 * s), 0.85 * s, 6, 10, rl.Fade(SCIFI_GREEN, pulse * 0.45))
	rl.DrawCylinderEx(pole + up * (0.035 * s), pole + up * (0.045 * s), 0.95 * s, 0.95 * s, 24, rl.Fade(SCIFI_GREEN, 0.55))

	prog := orbital_defense_build_progress(p)
	ring_y := 0.08 + prog * 0.70
	ring_r := 0.65 * s * (1.05 - prog * 0.3)
	rl.DrawCylinderEx(pole + up * (ring_y * s), pole + up * ((ring_y + 0.015) * s), ring_r, ring_r, 20, rl.Fade(SCIFI_MINT, 0.4))

	spark_ang := laser_anim_time * 6.5 + f32(p) * 2.0
	spark_pt := pole + up * (ring_y * s) + rl.Vector3{math.cos(spark_ang) * 0.45 * s, 0, math.sin(spark_ang) * 0.45 * s}
	rl.DrawLine3D(spark_pt, pole + up * (0.15 * s), rl.Color{255, 255, 200, 255})
	draw_low_poly_sphere(spark_pt, 0.045 * s, rl.Color{255, 255, 220, 255})
}
