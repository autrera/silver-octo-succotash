package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

SURF_PLAIN  :: 0.0
SURF_PLATED :: 1.0
SURF_METAL  :: 2.0
SURF_HAZARD :: 3.0
SURF_ENGINE :: 4.0
SURF_FLOW   :: 5.0

Fighter_Palette :: struct {
	armor_main, armor_dark, armor_plate, metal_trim, gunmetal, hazard, energy_glow, energy_core: rl.Color,
}

Miner_Palette :: struct {
	hull_main, hull_plate, frame_dark, metal_trim, gunmetal, tank, hazard, ore_glow, light_glow, window: rl.Color,
}

DRONE_RIM_PLAYER :: rl.Color{80, 200, 255, 255}
DRONE_RIM_ENEMY  :: rl.Color{255, 70, 80, 255}

Drone_Shader_Locs :: struct {
	light_dir, view_pos, rim_color, time: c.int,
}

Prism :: struct {
	start, end: rl.Vector3,
	r0, r1:     f32,
	sides:      int,
	roll:       f32,
	open:       bool,
}

drone_shader: rl.Shader
drone_shader_locs: Drone_Shader_Locs
drone_lod_models: [Drone_Model_Kind]rl.Model
drone_instances: [Drone_Model_Kind][2][MAX_UNITS]rl.Matrix
drone_instance_count: [Drone_Model_Kind][2]int

DRONE_VS :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;
uniform mat4 mvp;
out vec3 fragObjPos;
out vec3 fragWorldPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragMaterial;
flat out float fragPhase;
void main() {
	vec4 world = instanceTransform * vec4(vertexPosition, 1.0);
	vec3 origin = instanceTransform[3].xyz;
	fragObjPos = vertexPosition;
	fragWorldPos = world.xyz;
	fragNormal = mat3(instanceTransform) * vertexNormal;
	fragColor = vertexColor;
	fragMaterial = vertexTexCoord;
	fragPhase = fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 6.2831;
	gl_Position = mvp * world;
}
`

DRONE_FS :: `#version 330
in vec3 fragObjPos;
in vec3 fragWorldPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragMaterial;
flat in float fragPhase;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform vec3 rimColor;
uniform float time;
out vec4 finalColor;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec2 face_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	return an.y > max(an.x, an.z) ? p.xz : (an.z > an.x ? p.xy : p.zy);
}

float detail_fade(vec2 uv) {
	vec2 w = fwidth(uv);
	return clamp(1.4 - max(w.x, w.y) * 3.0, 0.0, 1.0);
}

float plating(vec3 p, vec3 n) {
	vec2 uv = face_uv(p, n) * vec2(6.5, 8.5);
	uv.x += 0.5 * mod(floor(uv.y), 2.0);
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 w = max(fwidth(uv), vec2(0.0001));
	vec2 edge = min(f, 1.0 - f) / w;
	float seam = 1.0 - clamp(min(edge.x, edge.y) - 0.5, 0.0, 1.0);
	vec2 rv = abs(f - vec2(0.1, 0.16)) / w;
	float rivet = 1.0 - clamp(max(rv.x, rv.y) - 0.7, 0.0, 1.0);
	float tone = 0.9 + 0.16 * hash3(vec3(cell, floor(p.y * 6.0)));
	return mix(1.0, tone * (1.0 - 0.32 * seam) * (1.0 + 0.25 * rivet), detail_fade(uv));
}

float brushed(vec3 p, vec3 n) {
	vec2 uv = face_uv(p, n) * vec2(4.0, 160.0);
	float streak = hash3(vec3(floor(uv.y), 3.1, 7.7));
	return mix(1.0, 0.88 + 0.2 * streak, detail_fade(uv));
}

float hazard(vec3 p) {
	float s = (p.x + p.y + p.z) * 30.0;
	float w = max(fwidth(s), 0.0001);
	float band = clamp((abs(fract(s) - 0.5) - 0.25) / w + 0.5, 0.0, 1.0);
	return mix(0.5, band, clamp(1.5 - w * 2.0, 0.0, 1.0));
}

void main() {
	vec3 n = normalize(fragNormal);
	if (!gl_FrontFacing) n = -n;
	vec3 base = fragColor.rgb;
	float glow = fragMaterial.x;
	float surf = floor(fragMaterial.y + 0.5);
	float shine = 0.16;
	float gloss = 22.0;
	base *= 0.95 + 0.1 * fract(fragPhase * 7.13);

	if (surf == 1.0) {
		base *= plating(fragObjPos, n);
	} else if (surf == 2.0) {
		base *= brushed(fragObjPos, n);
		shine = 0.55;
		gloss = 46.0;
	} else if (surf == 3.0) {
		base = mix(base, vec3(0.07, 0.07, 0.08), hazard(fragObjPos));
		shine = 0.3;
	}

	vec3 v = normalize(viewPos - fragWorldPos);
	float diff = max(dot(n, lightDir), 0.0);
	float fill = max(dot(n, normalize(vec3(0.55, -0.25, -0.65))), 0.0);
	float sky = 0.5 + 0.5 * n.y;
	float spec = pow(max(dot(n, normalize(lightDir + v)), 0.0), gloss);
	float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
	float occlusion = 0.72 + 0.28 * smoothstep(-0.32, 0.22, fragObjPos.y);
	vec3 lit = base * (0.2 + 0.85 * diff + 0.22 * fill * vec3(0.7, 0.85, 1.2) + 0.16 * sky) * occlusion;
	lit += vec3(1.0, 0.95, 0.9) * spec * shine;
	lit += rimColor * rim * 0.5;

	float pulse = 1.0;
	if (surf == 4.0) {
		pulse = 0.78 + 0.16 * sin(time * 21.0 + fragPhase) + 0.08 * sin(time * 37.0 + fragPhase * 2.3);
	} else if (surf == 5.0) {
		pulse = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(time * 9.0 - fragObjPos.x * 34.0 + fragPhase), 2.0);
	}
	float facing = max(dot(n, v), 0.0);
	vec3 hot = mix(base, vec3(1.0), 0.4 * pulse);
	vec3 emissive = mix(base * 0.78, hot, facing * facing) * pulse;
	finalColor = vec4(mix(lit, emissive, glow), fragColor.a);
}
`

fighter_palette :: proc(enemy: bool) -> Fighter_Palette {
	if enemy {
		return Fighter_Palette{
			armor_main  = {132, 42, 52, 255},
			armor_dark  = {62, 22, 28, 255},
			armor_plate = {172, 60, 70, 255},
			metal_trim  = {178, 142, 146, 255},
			gunmetal    = {70, 56, 60, 255},
			hazard      = {226, 150, 40, 255},
			energy_glow = SCIFI_RED,
			energy_core = {255, 190, 140, 255},
		}
	}
	return Fighter_Palette{
		armor_main  = {54, 88, 132, 255},
		armor_dark  = {28, 42, 64, 255},
		armor_plate = {82, 124, 176, 255},
		metal_trim  = {150, 176, 200, 255},
		gunmetal    = {56, 64, 78, 255},
		hazard      = {236, 186, 44, 255},
		energy_glow = SCIFI_GREEN,
		energy_core = SCIFI_MINT,
	}
}

prism_axes :: proc(pr: Prism) -> (d, u, v: rl.Vector3) {
	d = rl.Vector3Normalize(pr.end - pr.start)
	up := rl.Vector3{0, 1, 0}
	if math.abs(rl.Vector3DotProduct(d, up)) > 0.95 { up = {0, 0, 1} }
	u = rl.Vector3Normalize(rl.Vector3CrossProduct(d, up))
	v = rl.Vector3CrossProduct(d, u)
	return
}

prism_corner :: proc(pr: Prism, i: int, t: f32) -> rl.Vector3 {
	_, u, v := prism_axes(pr)
	a := pr.roll + f32(i % pr.sides) * 2 * math.PI / f32(pr.sides)
	r := pr.r0 + (pr.r1 - pr.r0) * t
	return pr.start + (pr.end - pr.start) * t + (u * math.cos(a) + v * math.sin(a)) * r
}

prism_facet_point :: proc(pr: Prism, i: int, f, t: f32) -> rl.Vector3 {
	a := prism_corner(pr, i, t)
	z := prism_corner(pr, i + 1, t)
	return a + (z - a) * f
}

prism_facet_normal :: proc(pr: Prism, i: int) -> rl.Vector3 {
	p00 := prism_corner(pr, i, 0)
	p10 := prism_corner(pr, i + 1, 0)
	p01 := prism_corner(pr, i, 1)
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(p10 - p00, p01 - p00))
	if rl.Vector3DotProduct(n, (p00 + p10) * 0.5 - pr.start) < 0 { n = -n }
	return n
}

drone_prism :: proc(b: ^HQ_Builder, pr: Prism, col: rl.Color, glow: f32 = 0, surf: f32 = SURF_PLAIN) {
	d, _, _ := prism_axes(pr)
	for i in 0..<pr.sides {
		b0 := prism_corner(pr, i, 0)
		b1 := prism_corner(pr, i + 1, 0)
		t0 := prism_corner(pr, i, 1)
		t1 := prism_corner(pr, i + 1, 1)
		hq_face(b, b0, b1, t1, t0, (b0 + b1) * 0.5 - pr.start, col, glow, surf)
		if pr.open { continue }
		if pr.r0 > 0 { hq_tri(b, pr.start, b0, b1, -d, col, glow, surf) }
		if pr.r1 > 0 { hq_tri(b, pr.end, t0, t1, d, col, glow, surf) }
	}
}

drone_facet_decal :: proc(b: ^HQ_Builder, pr: Prism, i: int, f0, f1, t0, t1, lift: f32, col: rl.Color, glow: f32 = 0, surf: f32 = SURF_PLAIN) {
	n := prism_facet_normal(pr, i)
	off := n * lift
	hq_quad(b,
		prism_facet_point(pr, i, f0, t0) + off,
		prism_facet_point(pr, i, f1, t0) + off,
		prism_facet_point(pr, i, f1, t1) + off,
		prism_facet_point(pr, i, f0, t1) + off,
		n, col, glow, surf)
}

drone_raised_quad :: proc(b: ^HQ_Builder, base: [4]rl.Vector3, n: rl.Vector3, height, bevel: f32, col: rl.Color, surf: f32 = SURF_PLAIN) {
	c := (base[0] + base[1] + base[2] + base[3]) * 0.25
	top: [4]rl.Vector3
	for k in 0..<4 {
		top[k] = base[k] + (c - base[k]) * bevel + n * height
	}
	hq_quad(b, top[0], top[1], top[2], top[3], n, col, 0, surf)
	for k in 0..<4 {
		j := (k + 1) % 4
		hq_face(b, base[k], base[j], top[j], top[k], (base[k] + base[j]) * 0.5 - c + n * 0.2, col, 0, surf)
	}
}

drone_facet_panel :: proc(b: ^HQ_Builder, pr: Prism, i: int, f0, f1, t0, t1, height: f32, col: rl.Color, surf: f32 = SURF_PLATED) {
	n := prism_facet_normal(pr, i)
	off := n * 0.001
	base := [4]rl.Vector3{
		prism_facet_point(pr, i, f0, t0) + off,
		prism_facet_point(pr, i, f1, t0) + off,
		prism_facet_point(pr, i, f1, t1) + off,
		prism_facet_point(pr, i, f0, t1) + off,
	}
	drone_raised_quad(b, base, n, height, 0.12, col, surf)
}

drone_plate :: proc(b: ^HQ_Builder, p0, p1, p2: rl.Vector3, thickness: f32, hint: rl.Vector3, col: rl.Color, surf: f32 = SURF_PLATED) -> rl.Vector3 {
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(p1 - p0, p2 - p0))
	if rl.Vector3DotProduct(n, hint) < 0 { n = -n }
	off := -n * thickness
	q := [3]rl.Vector3{p0, p1, p2}
	c := (p0 + p1 + p2) / 3
	hq_tri(b, p0, p1, p2, n, col, 0, surf)
	hq_tri(b, p0 + off, p1 + off, p2 + off, -n, col, 0, surf)
	for k in 0..<3 {
		j := (k + 1) % 3
		hq_face(b, q[k], q[j], q[j] + off, q[k] + off, (q[k] + q[j]) * 0.5 - c, col, 0, surf)
	}
	return n
}

drone_sphere :: proc(b: ^HQ_Builder, center: rl.Vector3, radius: f32, rings, slices: int, col: rl.Color, glow: f32 = 0, surf: f32 = SURF_PLAIN) {
	add_sphere(&b.verts, &b.norms, &b.cols, center, radius, rings, slices, col)
	hq_tag(b, glow, surf)
}

tri_point :: proc(a, b, c: rl.Vector3, s, t: f32) -> rl.Vector3 {
	return a + (b - a) * s + (c - a) * t
}

drone_tri_decal :: proc(b: ^HQ_Builder, a, bb, c, n: rl.Vector3, s0, s1, t0, t1, lift: f32, col: rl.Color, glow: f32 = 0, surf: f32 = SURF_PLAIN) {
	off := n * lift
	hq_quad(b,
		tri_point(a, bb, c, s0, t0) + off,
		tri_point(a, bb, c, s1, t0) + off,
		tri_point(a, bb, c, s1, t1) + off,
		tri_point(a, bb, c, s0, t1) + off,
		n, col, glow, surf)
}

build_fighter_hull :: proc(b: ^HQ_Builder, pal: Fighter_Palette, detailed: bool) {
	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pent_up: f32 = -math.PI / 10.0

	core := Prism{start = -h * 0.28, end = h * 0.18, r0 = 0.20, r1 = 0.18, sides = 6}
	drone_prism(b, core, pal.armor_dark, 0, SURF_PLATED)

	hood_b := -h * 0.30 + up * 0.18
	hood_f := h * 0.20 + up * 0.16
	hood := Prism{start = hood_b, end = hood_f, r0 = 0.15, r1 = 0.12, sides = 5, roll = pent_up}
	drone_prism(b, hood, pal.armor_main, 0, SURF_PLATED)

	s_signs := [2]f32{-1.0, 1.0}
	for s in s_signs {
		s_vec := side * s
		sh_f := h * 0.18 + up * 0.06 + s_vec * 0.24
		sh_tip := s_vec * 0.30 - up * 0.06
		top_n := drone_plate(b, hood_f, sh_f, hood_b, 0.018, up + s_vec * 0.5, pal.armor_plate)
		side_n := drone_plate(b, hood_b, sh_f, sh_tip, 0.018, s_vec + up * 0.4, pal.armor_main)
		if !detailed { continue }

		drone_tri_decal(b, hood_f, sh_f, hood_b, top_n, 0.70, 0.80, 0.06, 0.24, 0.002, pal.energy_glow, 0.9, SURF_FLOW)
		drone_tri_decal(b, hood_f, sh_f, hood_b, top_n, 0.40, 0.62, 0.10, 0.30, 0.002, pal.gunmetal, 0, SURF_HAZARD)
		for k in 0..<3 {
			t0 := 0.20 + f32(k) * 0.085
			drone_tri_decal(b, hood_b, sh_f, sh_tip, side_n, 0.30, 0.52, t0, t0 + 0.04, 0.002, pal.armor_dark)
		}
		raised := [4]rl.Vector3{
			tri_point(hood_b, sh_f, sh_tip, 0.12, 0.08) + side_n * 0.001,
			tri_point(hood_b, sh_f, sh_tip, 0.26, 0.04) + side_n * 0.001,
			tri_point(hood_b, sh_f, sh_tip, 0.20, 0.52) + side_n * 0.001,
			tri_point(hood_b, sh_f, sh_tip, 0.08, 0.46) + side_n * 0.001,
		}
		drone_raised_quad(b, raised, side_n, 0.012, 0.15, pal.armor_plate, SURF_PLATED)
		hq_beam(b, sh_f + s_vec * 0.004, sh_tip + s_vec * 0.004, 0.012, 0.012, side_n, pal.metal_trim, 0, SURF_METAL)
		hq_beam(b, sh_f + up * 0.004, hood_f + up * 0.004, 0.009, 0.009, top_n, pal.metal_trim, 0, SURF_METAL)
	}

	eye_pos := h * 0.22
	eye := Prism{start = eye_pos, end = eye_pos + h * 0.04, r0 = 0.14, r1 = 0.13, sides = 6}
	drone_prism(b, eye, pal.metal_trim, 0, SURF_METAL)
	if detailed {
		drone_prism(b, Prism{start = eye_pos + h * 0.04, end = eye_pos + h * 0.046, r0 = 0.11, r1 = 0.1, sides = 12}, pal.gunmetal, 0, SURF_METAL)
	}
	drone_sphere(b, eye_pos + h * 0.045, 0.075, 6, 8, pal.energy_glow, 1)
	drone_sphere(b, eye_pos + h * 0.070, 0.035, 4, 6, pal.energy_core, 1)

	probe_base := h * 0.18 - up * 0.11
	probe_tip := h * 0.52 - up * 0.20
	hq_cyl(b, probe_base, probe_tip, 0.025, 0.008, 4, pal.metal_trim, 0, SURF_METAL)

	for s in s_signs {
		s_vec := side * s
		strut_top := -h * 0.06 - up * 0.10 + s_vec * 0.14
		strut_tip := h * 0.04 - up * 0.34 + s_vec * 0.18
		hq_cyl(b, strut_top, strut_tip, 0.030, 0.014, 4, pal.metal_trim, 0, SURF_METAL)
		if !detailed { continue }
		drone_sphere(b, strut_top, 0.04, 4, 6, pal.gunmetal)
		piston_a := strut_top - h * 0.045 - up * 0.01
		piston_b := piston_a + (strut_tip - strut_top) * 0.62
		hq_cyl(b, piston_a, piston_b, 0.013, 0.013, 4, pal.gunmetal, 0, SURF_METAL)
		hq_cyl(b, strut_tip, strut_tip + h * 0.07 + up * 0.02, 0.018, 0.002, 4, pal.gunmetal, 0, SURF_METAL)
		drone_sphere(b, strut_tip, 0.016, 3, 4, pal.energy_glow, 1)
	}

	for s in s_signs {
		s_vec := side * s
		pod_pos := s_vec * 0.40 - up * 0.02
		pod_roll: f32 = s > 0 ? 0 : math.PI / 5.0

		drone_prism(b, Prism{start = s_vec * 0.20, end = pod_pos, r0 = 0.032, r1 = 0.032, sides = 4, roll = math.PI / 4.0}, pal.armor_dark, 0, SURF_METAL)
		pod := Prism{start = pod_pos - h * 0.20, end = pod_pos + h * 0.10, r0 = 0.068, r1 = 0.058, sides = 5, roll = pod_roll}
		drone_prism(b, pod, pal.armor_main, 0, SURF_PLATED)

		rail_len := f32(0.36)
		p_top_start := pod_pos + h * 0.08 + up * 0.040
		hq_cyl(b, p_top_start, p_top_start + h * rail_len, 0.022, 0.014, 4, pal.metal_trim, 0, SURF_METAL)
		p_bot_start := pod_pos + h * 0.08 - up * 0.040
		hq_cyl(b, p_bot_start, p_bot_start + h * rail_len, 0.022, 0.014, 4, pal.metal_trim, 0, SURF_METAL)
		hq_cyl(b, pod_pos + h * 0.07, pod_pos + h * 0.38, 0.014, 0.014, 4, pal.energy_glow, 1, SURF_FLOW)
		if !detailed { continue }

		for i in 0..<pod.sides {
			n := prism_facet_normal(pod, i)
			if rl.Vector3DotProduct(n, s_vec) < -0.5 { continue }
			drone_facet_panel(b, pod, i, 0.14, 0.86, 0.08, 0.42, 0.007, pal.armor_plate)
			drone_facet_panel(b, pod, i, 0.14, 0.86, 0.50, 0.80, 0.007, pal.armor_plate)
		}
		drone_prism(b, Prism{start = pod_pos + h * 0.085, end = pod_pos + h * 0.115, r0 = 0.066, r1 = 0.062, sides = 10}, pal.hazard, 0, SURF_HAZARD)
		drone_prism(b, Prism{start = pod_pos - h * 0.20, end = pod_pos - h * 0.235, r0 = 0.058, r1 = 0.044, sides = 10}, pal.gunmetal, 0, SURF_METAL)
		drone_sphere(b, pod_pos - h * 0.238, 0.03, 3, 6, pal.energy_glow, 1)

		for k in 0..<3 {
			ring_x := 0.17 + f32(k) * 0.07
			drone_prism(b, Prism{start = pod_pos + h * ring_x, end = pod_pos + h * (ring_x + 0.02), r0 = 0.03, r1 = 0.03, sides = 6}, pal.energy_glow, 0.85, SURF_FLOW)
		}
		hq_box(b, pod_pos + h * 0.405, 0.016, 0.066, 0.014, h, up, side, pal.gunmetal, 0, SURF_METAL)
		drone_sphere(b, pod_pos + h * 0.43, 0.02, 3, 6, pal.energy_core, 1, SURF_ENGINE)

		for k in 0..<3 {
			fin_c := pod_pos - h * (0.15 - f32(k) * 0.05) + s_vec * 0.075 + up * 0.012
			hq_box(b, fin_c, 0.024, 0.032, 0.006, h, up, s_vec, pal.gunmetal, 0, SURF_METAL)
		}
		nav := pod_pos - h * 0.10 + s_vec * 0.104 + up * 0.03
		drone_sphere(b, nav, 0.016, 3, 6, pal.energy_core, 1, SURF_ENGINE)

		brace_a := -up * 0.12 + s_vec * 0.16
		brace_b := pod_pos - h * 0.06 - up * 0.05
		hq_cyl(b, brace_a, brace_b, 0.012, 0.012, 4, pal.metal_trim, 0, SURF_METAL)
	}

	engine_pos := -h * 0.32
	drone_prism(b, Prism{start = -h * 0.24, end = engine_pos, r0 = 0.12, r1 = 0.09, sides = 6}, pal.armor_dark, 0, SURF_PLATED)
	drone_prism(b, Prism{start = engine_pos, end = engine_pos - h * 0.04, r0 = 0.09, r1 = 0.07, sides = 6}, pal.metal_trim, 0, SURF_METAL)
	drone_sphere(b, engine_pos - h * 0.05, 0.075, 4, 6, pal.energy_glow, 1, SURF_ENGINE)
	drone_sphere(b, engine_pos - h * 0.03, 0.040, 4, 4, pal.energy_core, 1, SURF_ENGINE)
	if !detailed { return }

	for i in 0..<core.sides {
		n := prism_facet_normal(core, i)
		if n.y > 0.3 { continue }
		if n.y < -0.9 {
			drone_facet_decal(b, core, i, 0.36, 0.64, 0.14, 0.72, 0.002, pal.energy_glow, 0.8, SURF_FLOW)
			continue
		}
		drone_facet_panel(b, core, i, 0.1, 0.9, 0.12, 0.38, 0.01, pal.armor_main)
		drone_facet_panel(b, core, i, 0.1, 0.9, 0.62, 0.86, 0.01, pal.armor_main)
		for k in 0..<3 {
			t := 0.44 + f32(k) * 0.055
			drone_facet_decal(b, core, i, 0.45, 0.55, t, t + 0.03, 0.002, pal.energy_core, 1, SURF_ENGINE)
		}
	}
	for band_x in ([2]f32{-0.205, 0.075}) {
		r := 0.20 + (band_x + 0.28) / 0.46 * -0.02 + 0.012
		drone_prism(b, Prism{start = h * band_x, end = h * (band_x + 0.03), r0 = r, r1 = r, sides = 6}, pal.gunmetal, 0, SURF_METAL)
	}
	for s in s_signs {
		keel := side * (s * 0.045) - up * 0.17
		hq_beam(b, keel - h * 0.22, keel + h * 0.12, 0.012, 0.012, side, pal.gunmetal, 0, SURF_METAL)
	}

	for i in ([2]int{0, 4}) {
		f0: f32 = i == 0 ? 0.1 : 0.82
		drone_facet_decal(b, hood, i, f0, f0 + 0.08, 0.1, 0.9, 0.002, pal.energy_glow, 0.9, SURF_FLOW)
		p0: f32 = i == 0 ? 0.3 : 0.12
		drone_facet_panel(b, hood, i, p0, p0 + 0.58, 0.08, 0.46, 0.009, pal.armor_plate)
		drone_facet_panel(b, hood, i, p0, p0 + 0.58, 0.54, 0.9, 0.009, pal.armor_plate)
	}
	ridge_b := prism_corner(hood, 0, 0.08)
	ridge_f := prism_corner(hood, 0, 0.86)
	hq_beam(b, ridge_b + up * 0.008, ridge_f + up * 0.008, 0.013, 0.012, up, pal.metal_trim, 0, SURF_METAL)
	hq_box(b, ridge_b + up * 0.04 + h * 0.03, 0.006, 0.035, 0.05, h, up, side, pal.armor_plate, 0, SURF_PLATED)
	sensor := prism_corner(hood, 0, 0.72) + up * 0.014
	hq_box(b, sensor, 0.024, 0.012, 0.036, h, up, side, pal.gunmetal, 0, SURF_METAL)
	hq_box(b, sensor + h * 0.037, 0.016, 0.006, 0.002, h, up, side, pal.energy_core, 1, SURF_ENGINE)

	for s in s_signs {
		root := prism_corner(hood, 0, 0.06) + side * (s * 0.04)
		tip := root - h * 0.16 + up * 0.1 + side * (s * 0.03)
		hq_cyl(b, root, tip, 0.008, 0.004, 4, pal.metal_trim, 0, SURF_METAL)
		drone_sphere(b, tip, 0.012, 3, 4, pal.energy_core, 1, SURF_ENGINE)
	}

	for k in 0..<3 {
		a := f32(k) * 2.0 * math.PI / 3.0 + math.PI / 2.0
		dir := rl.Vector3{0, -math.sin(a), math.cos(a)}
		drone_sphere(b, eye_pos + h * 0.046 + dir * 0.092, 0.012, 3, 4, pal.energy_core, 1, SURF_ENGINE)
	}
	hq_cyl(b, probe_base - h * 0.01, probe_base + (probe_tip - probe_base) * 0.18, 0.036, 0.03, 6, pal.gunmetal, 0, SURF_METAL)
	drone_sphere(b, probe_tip, 0.014, 3, 4, pal.energy_glow, 1, SURF_ENGINE)

	for k in 0..<4 {
		a := f32(k) * math.PI / 3.0
		dir := rl.Vector3{0, -math.sin(a), math.cos(a)}
		tan := rl.Vector3CrossProduct(h, dir)
		hq_box(b, -h * 0.28 + dir * 0.128, 0.005, 0.03, 0.035, h, dir, tan, pal.gunmetal, 0, SURF_METAL)
	}
	drone_prism(b, Prism{start = -h * 0.235, end = -h * 0.255, r0 = 0.128, r1 = 0.128, sides = 6}, pal.hazard, 0, SURF_HAZARD)
	drone_prism(b, Prism{start = engine_pos - h * 0.036, end = engine_pos - h * 0.044, r0 = 0.062, r1 = 0.062, sides = 12}, pal.energy_core, 1, SURF_ENGINE)
}

miner_palette :: proc(enemy: bool) -> Miner_Palette {
	if enemy {
		return Miner_Palette{
			hull_main  = {168, 46, 54, 255},
			hull_plate = {210, 72, 80, 255},
			frame_dark = {50, 26, 30, 255},
			metal_trim = {170, 146, 150, 255},
			gunmetal   = {72, 58, 62, 255},
			tank       = {118, 84, 88, 255},
			hazard     = {226, 150, 40, 255},
			ore_glow   = {255, 110, 70, 255},
			light_glow = SCIFI_RED,
			window     = {255, 130, 120, 255},
		}
	}
	return Miner_Palette{
		hull_main  = {232, 158, 26, 255},
		hull_plate = {255, 194, 52, 255},
		frame_dark = {36, 40, 48, 255},
		metal_trim = {156, 170, 186, 255},
		gunmetal   = {62, 68, 80, 255},
		tank       = {104, 116, 134, 255},
		hazard     = {245, 205, 60, 255},
		ore_glow   = {255, 176, 60, 255},
		light_glow = {255, 222, 120, 255},
		window     = SCIFI_GREEN,
	}
}

build_miner_hull :: proc(b: ^HQ_Builder, pal: Miner_Palette, detailed: bool) {
	h := rl.Vector3{1, 0, 0}
	up := rl.Vector3{0, 1, 0}
	side := rl.Vector3{0, 0, 1}
	pent_up: f32 = -math.PI / 10.0
	s_signs := [2]f32{-1.0, 1.0}

	deck_f := h * 0.16 - up * 0.02
	deck_b := -h * 0.22 - up * 0.02
	frame := Prism{start = deck_b, end = deck_f, r0 = 0.22, r1 = 0.20, sides = 6}
	drone_prism(b, frame, pal.frame_dark, 0, SURF_PLATED)
	deck := Prism{start = deck_b + up * 0.04, end = deck_f + up * 0.04 + h * 0.008, r0 = 0.18, r1 = 0.16, sides = 6}
	drone_prism(b, deck, pal.hull_main, 0, SURF_PLATED)

	tank_pos := -h * 0.14 + up * 0.24
	tank_r: f32 = 0.24
	drone_sphere(b, tank_pos, tank_r, detailed ? 10 : 8, detailed ? 14 : 10, pal.tank, 0, SURF_METAL)

	for s in s_signs {
		cradle_base := -h * 0.18 + side * (s * 0.16) + up * 0.04
		cradle_top := tank_pos + side * (s * 0.18) + up * 0.04
		hq_cyl(b, cradle_base, cradle_top, 0.030, 0.020, 4, pal.hull_main, 0, SURF_METAL)
	}
	hq_cyl(b, -h * 0.22 + up * 0.04, tank_pos - h * 0.16 + up * 0.04, 0.035, 0.025, 4, pal.hull_plate, 0, SURF_METAL)

	cab_pos := h * 0.14 + up * 0.08 - side * 0.07
	cab := Prism{start = cab_pos - h * 0.08, end = cab_pos + h * 0.08, r0 = 0.09, r1 = 0.07, sides = 5, roll = pent_up}
	drone_prism(b, cab, pal.hull_main, 0, SURF_PLATED)
	drone_prism(b, Prism{start = cab_pos + h * 0.05, end = cab_pos + h * 0.09, r0 = 0.06, r1 = 0.045, sides = 5, roll = pent_up}, pal.window, 0.85)

	light_pos := h * 0.22 + up * 0.06 + side * 0.08
	drone_prism(b, Prism{start = light_pos - h * 0.04, end = light_pos, r0 = 0.040, r1 = 0.040, sides = 6}, pal.frame_dark, 0, SURF_METAL)
	drone_sphere(b, light_pos + h * 0.015, 0.030, 4, 6, pal.light_glow, 1)

	leg_offsets := [4][2]f32{{0.12, 0.18}, {0.12, -0.18}, {-0.16, 0.20}, {-0.16, -0.20}}
	leg_targets := [4][2]f32{{0.26, 0.36}, {0.26, -0.36}, {-0.28, 0.38}, {-0.28, -0.38}}
	for l in 0..<4 {
		hip := h * leg_offsets[l][0] + side * leg_offsets[l][1] - up * 0.02
		foot := h * leg_targets[l][0] + side * leg_targets[l][1] - up * 0.28
		out := side * (leg_targets[l][1] > 0 ? 1 : -1)
		knee := (hip + foot) * 0.5 + up * 0.08 + out * 0.06
		hq_cyl(b, hip, knee, 0.036, 0.026, 4, pal.hull_main, 0, SURF_PLATED)
		hq_cyl(b, knee, foot, 0.026, 0.018, 4, pal.metal_trim, 0, SURF_METAL)
		drone_prism(b, Prism{start = foot, end = foot - up * 0.035, r0 = 0.032, r1 = 0.028, sides = 6}, pal.frame_dark, 0, SURF_METAL)
		if !detailed { continue }
		drone_sphere(b, knee, 0.03, 4, 6, pal.gunmetal, 0, SURF_METAL)
		drone_sphere(b, hip, 0.04, 4, 6, pal.gunmetal, 0, SURF_METAL)
		hq_cyl(b, hip + up * 0.035, hip + (knee - hip) * 0.7 + up * 0.03, 0.011, 0.011, 4, pal.metal_trim, 0, SURF_METAL)
		drone_prism(b, Prism{start = foot - up * 0.035, end = foot - up * 0.045, r0 = 0.05, r1 = 0.05, sides = 6}, pal.gunmetal, 0, SURF_METAL)
		drone_sphere(b, foot + up * 0.004 + out * 0.03, 0.01, 3, 4, pal.light_glow, 1, SURF_ENGINE)
	}

	drill_base := h * 0.08 - up * 0.12
	drill_tip := h * 0.22 - up * 0.40
	drone_prism(b, Prism{start = drill_base, end = drill_base - up * 0.06, r0 = 0.05, r1 = 0.05, sides = 6}, pal.frame_dark, 0, SURF_METAL)
	hq_cyl(b, drill_base - up * 0.05, drill_tip, 0.05, 0.012, 8, pal.metal_trim, 0, SURF_HAZARD)
	drone_sphere(b, drill_tip, 0.032, 4, 6, pal.light_glow, 1, SURF_ENGINE)

	for s in s_signs {
		nozzle_f := -h * 0.22 + side * (s * 0.12) - up * 0.04
		nozzle_b := nozzle_f - h * 0.08
		drone_prism(b, Prism{start = nozzle_f, end = nozzle_b, r0 = 0.045, r1 = 0.035, sides = 8}, pal.frame_dark, 0, SURF_METAL)
		drone_sphere(b, nozzle_b - h * 0.02, 0.045, 4, 6, pal.light_glow, 1, SURF_ENGINE)
		if !detailed { continue }
		drone_prism(b, Prism{start = nozzle_f + h * 0.005, end = nozzle_f - h * 0.02, r0 = 0.054, r1 = 0.054, sides = 8}, pal.gunmetal, 0, SURF_METAL)
		drone_prism(b, Prism{start = nozzle_b, end = nozzle_b - h * 0.006, r0 = 0.03, r1 = 0.03, sides = 8}, pal.light_glow, 1, SURF_ENGINE)
	}
	if !detailed { return }

	for i in 0..<deck.sides {
		n := prism_facet_normal(deck, i)
		if n.y > 0.5 || n.y < -0.5 { continue }
		drone_facet_panel(b, deck, i, 0.12, 0.88, 0.08, 0.46, 0.008, pal.hull_plate)
		drone_facet_panel(b, deck, i, 0.12, 0.88, 0.54, 0.92, 0.008, pal.hull_plate)
	}
	for i in 0..<frame.sides {
		n := prism_facet_normal(frame, i)
		if n.y > -0.5 && n.y < 0.5 {
			for k in 0..<4 {
				t := 0.2 + f32(k) * 0.16
				drone_facet_decal(b, frame, i, 0.3, 0.7, t, t + 0.06, 0.002, pal.gunmetal)
			}
		} else if n.y < -0.9 {
			drone_facet_decal(b, frame, i, 0.38, 0.62, 0.16, 0.84, 0.002, pal.ore_glow, 0.8, SURF_FLOW)
		}
	}
	drone_prism(b, Prism{start = deck_f - h * 0.035, end = deck_f + h * 0.004, r0 = 0.214, r1 = 0.208, sides = 6, open = true}, pal.hazard, 0, SURF_HAZARD)
	drone_prism(b, Prism{start = deck_b - h * 0.004, end = deck_b + h * 0.03, r0 = 0.226, r1 = 0.224, sides = 6}, pal.gunmetal, 0, SURF_METAL)

	drone_prism(b, Prism{start = tank_pos - up * 0.014, end = tank_pos + up * 0.014, r0 = 0.25, r1 = 0.25, sides = 16, open = true}, pal.gunmetal, 0, SURF_METAL)
	drone_prism(b, Prism{start = tank_pos - h * 0.012, end = tank_pos + h * 0.012, r0 = 0.248, r1 = 0.248, sides = 16, open = true}, pal.gunmetal, 0, SURF_METAL)
	drone_prism(b, Prism{start = tank_pos - side * 0.012, end = tank_pos + side * 0.012, r0 = 0.248, r1 = 0.248, sides = 16, open = true}, pal.gunmetal, 0, SURF_METAL)
	band_y: f32 = 0.11
	band_r := math.sqrt(tank_r * tank_r - band_y * band_y) + 0.004
	drone_prism(b, Prism{start = tank_pos + up * (band_y - 0.022), end = tank_pos + up * (band_y + 0.022), r0 = band_r + 0.01, r1 = band_r - 0.01, sides = 16}, pal.ore_glow, 0.85, SURF_FLOW)
	hatch := tank_pos + up * (tank_r - 0.012)
	drone_prism(b, Prism{start = hatch, end = hatch + up * 0.035, r0 = 0.075, r1 = 0.065, sides = 8}, pal.gunmetal, 0, SURF_METAL)
	drone_prism(b, Prism{start = hatch + up * 0.035, end = hatch + up * 0.045, r0 = 0.045, r1 = 0.045, sides = 8}, pal.hazard, 0, SURF_HAZARD)
	drone_sphere(b, hatch + up * 0.06, 0.018, 3, 6, pal.light_glow, 1, SURF_ENGINE)

	for i in 0..<cab.sides {
		n := prism_facet_normal(cab, i)
		if n.y < -0.3 { continue }
		drone_facet_panel(b, cab, i, 0.15, 0.85, 0.08, 0.55, 0.006, pal.hull_plate)
	}
	cab_top := prism_corner(cab, 0, 0.35)
	hq_box(b, cab_top + up * 0.012, 0.03, 0.012, 0.022, h, up, side, pal.frame_dark, 0, SURF_METAL)
	hq_box(b, cab_top + up * 0.03, 0.022, 0.007, 0.012, h, up, side, pal.light_glow, 1, SURF_ENGINE)
	antenna_root := prism_corner(cab, 0, 0.1)
	antenna_tip := antenna_root - h * 0.1 + up * 0.14 - side * 0.03
	hq_cyl(b, antenna_root, antenna_tip, 0.008, 0.004, 4, pal.metal_trim, 0, SURF_METAL)
	drone_sphere(b, antenna_tip, 0.012, 3, 4, pal.light_glow, 1, SURF_ENGINE)

	drone_prism(b, Prism{start = light_pos - h * 0.045, end = light_pos + h * 0.006, r0 = 0.048, r1 = 0.05, sides = 6}, pal.gunmetal, 0, SURF_METAL)
	hq_cyl(b, light_pos - h * 0.04 - up * 0.02, h * 0.1 + up * 0.1 + side * 0.08, 0.01, 0.01, 4, pal.metal_trim, 0, SURF_METAL)

	can_a := -h * 0.02 + up * 0.13 + side * 0.12
	can_b := can_a + h * 0.13
	drone_prism(b, Prism{start = can_a, end = can_b, r0 = 0.035, r1 = 0.035, sides = 8}, pal.metal_trim, 0, SURF_METAL)
	drone_prism(b, Prism{start = can_b, end = can_b + h * 0.015, r0 = 0.037, r1 = 0.03, sides = 8}, pal.hazard, 0, SURF_HAZARD)
	hq_beam(b, can_a + h * 0.04 - up * 0.04, can_a + h * 0.04 + up * 0.035, 0.006, 0.006, h, pal.gunmetal, 0, SURF_METAL)
	hq_beam(b, can_a + h * 0.09 - up * 0.04, can_a + h * 0.09 + up * 0.035, 0.006, 0.006, h, pal.gunmetal, 0, SURF_METAL)

	drone_prism(b, Prism{start = drill_base - up * 0.05, end = drill_base - up * 0.07, r0 = 0.062, r1 = 0.062, sides = 8}, pal.hazard, 0, SURF_HAZARD)
	for k in 0..<3 {
		a := f32(k) * 2 * math.PI / 3
		dir := rl.Vector3{math.cos(a), 0, math.sin(a)}
		hq_cyl(b, drill_base + dir * 0.06 - up * 0.01, drill_base + (drill_tip - drill_base) * 0.35 + dir * 0.035, 0.008, 0.008, 4, pal.gunmetal, 0, SURF_METAL)
	}
}

finish_drone_model :: proc(b: ^HQ_Builder) -> rl.Model {
	mesh := make_mesh_from_arrays(b.verts[:], b.norms[:], b.cols[:], b.uvs[:])
	delete(b.verts)
	delete(b.norms)
	delete(b.cols)
	delete(b.uvs)
	model := rl.LoadModelFromMesh(mesh)
	model.materials[0].shader = drone_shader
	return model
}

build_fighter_model :: proc(enemy: bool, detailed := true) -> rl.Model {
	b: HQ_Builder
	build_fighter_hull(&b, fighter_palette(enemy), detailed)
	return finish_drone_model(&b)
}

build_miner_model :: proc(enemy: bool, detailed := true) -> rl.Model {
	b: HQ_Builder
	build_miner_hull(&b, miner_palette(enemy), detailed)
	return finish_drone_model(&b)
}

init_drone_shader :: proc() {
	drone_shader = rl.LoadShaderFromMemory(DRONE_VS, DRONE_FS)
	drone_shader.locs[rl.ShaderLocationIndex.VERTEX_INSTANCETRANSFORM] = rl.GetShaderLocationAttrib(drone_shader, "instanceTransform")
	drone_shader_locs = Drone_Shader_Locs{
		light_dir = rl.GetShaderLocation(drone_shader, "lightDir"),
		view_pos  = rl.GetShaderLocation(drone_shader, "viewPos"),
		rim_color = rl.GetShaderLocation(drone_shader, "rimColor"),
		time      = rl.GetShaderLocation(drone_shader, "time"),
	}
	light := rl.Vector3Normalize(PLANET_LIGHT_DIR)
	rl.SetShaderValue(drone_shader, drone_shader_locs.light_dir, &light, .VEC3)
}

unload_drone_model :: proc(model: rl.Model) {
	m := model
	m.materials[0].shader = {}
	rl.UnloadModel(m)
}

drone_transform :: proc(position, heading: rl.Vector3) -> rl.Matrix {
	f := heading
	if rl.Vector3Length(f) < 0.001 { f = {1, 0, 0} }
	f = rl.Vector3Normalize(f)
	z := rl.Vector3CrossProduct(f, {0, 1, 0})
	if rl.Vector3Length(z) < 0.001 { z = {0, 0, 1} }
	z = rl.Vector3Normalize(z)
	y := rl.Vector3CrossProduct(z, f)
	return rl.Matrix{
		f.x, y.x, z.x, position.x,
		f.y, y.y, z.y, position.y,
		f.z, y.z, z.z, position.z,
		0, 0, 0, 1,
	}
}

init_drone_visuals :: proc() {
	if drone_visuals_ready { return }
	init_drone_shader()
	for kind in Drone_Model_Kind {
		enemy := kind == .ENEMY_MINER || kind == .ENEMY_FIGHTER
		if kind == .PLAYER_MINER || kind == .ENEMY_MINER {
			drone_models[kind] = build_miner_model(enemy)
			drone_lod_models[kind] = build_miner_model(enemy, false)
		} else {
			drone_models[kind] = build_fighter_model(enemy)
			drone_lod_models[kind] = build_fighter_model(enemy, false)
		}
	}
	drone_icons[.MINING] = bake_drone_icon(drone_lod_models[.PLAYER_MINER], 0.6, 0.45)
	drone_icons[.COMBAT] = bake_drone_icon(drone_lod_models[.PLAYER_FIGHTER], 1.3, 0.9)
	drone_visuals_ready = true
}

unload_drone_visuals :: proc() {
	if !drone_visuals_ready { return }
	for kind in Drone_Model_Kind {
		unload_drone_model(drone_models[kind])
		unload_drone_model(drone_lod_models[kind])
	}
	rl.UnloadShader(drone_shader)
	for kind in Unit_Type {
		rl.UnloadRenderTexture(drone_icons[kind])
	}
	drone_visuals_ready = false
}

queue_drone :: proc(kind: Drone_Model_Kind, position, heading: rl.Vector3) {
	d := position - camera.position
	lod := rl.Vector3DotProduct(d, d) > DRONE_LOD_DISTANCE * DRONE_LOD_DISTANCE ? 1 : 0
	n := drone_instance_count[kind][lod]
	if n >= MAX_UNITS { return }
	drone_instances[kind][lod][n] = drone_transform(position, heading)
	drone_instance_count[kind][lod] = n + 1
}

draw_fighter_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3) {
	if !drone_visuals_ready {
		draw_low_poly_sphere(position, 0.35, enemy ? rl.RED : SCIFI_BLUE)
		return
	}
	queue_drone(enemy ? .ENEMY_FIGHTER : .PLAYER_FIGHTER, position, heading)
}

draw_miner_drone :: proc(position: rl.Vector3, enemy: bool, heading: rl.Vector3 = {1, 0, 0}) {
	if !drone_visuals_ready {
		draw_low_poly_sphere(position, 0.35, enemy ? rl.RED : rl.ORANGE)
		return
	}
	bob := math.sin(laser_anim_time * 3.0 + position.x * 2.1 + position.z * 1.7) * 0.04
	queue_drone(enemy ? .ENEMY_MINER : .PLAYER_MINER, position + {0, bob, 0}, heading)
}

flush_drones :: proc() {
	if !drone_visuals_ready { return }
	view := camera.position
	t := laser_anim_time
	rl.SetShaderValue(drone_shader, drone_shader_locs.view_pos, &view, .VEC3)
	rl.SetShaderValue(drone_shader, drone_shader_locs.time, &t, .FLOAT)
	for kind in Drone_Model_Kind {
		enemy := kind == .ENEMY_MINER || kind == .ENEMY_FIGHTER
		rim := rl.ColorNormalize(enemy ? DRONE_RIM_ENEMY : DRONE_RIM_PLAYER)
		rim_rgb := rl.Vector3{rim.x, rim.y, rim.z}
		rl.SetShaderValue(drone_shader, drone_shader_locs.rim_color, &rim_rgb, .VEC3)
		for lod in 0..<2 {
			n := drone_instance_count[kind][lod]
			if n == 0 { continue }
			model := lod == 0 ? drone_models[kind] : drone_lod_models[kind]
			rl.DrawMeshInstanced(model.meshes[0], model.materials[0], &drone_instances[kind][lod][0], c.int(n))
			drone_instance_count[kind][lod] = 0
		}
	}
}
