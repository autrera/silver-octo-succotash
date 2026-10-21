package main

import "core:c"
import "core:math"
import rl "vendor:raylib"

HQ_Model_Part :: enum {
	HULL,
	WRECK,
	TURRET,
	GUN,
	RADAR,
}

HQ_Shader_Locs :: struct {
	light_dir, view_pos, fog, wreck, time: c.int,
}

HQ_Builder :: struct {
	verts: [dynamic]f32,
	norms: [dynamic]f32,
	cols:  [dynamic]u8,
	uvs:   [dynamic]f32,
}

HQ_MAST_ROOT  :: rl.Vector3{-2.97, 0.7, -2.97}
HQ_RADAR_HUB  :: rl.Vector3{-2.97, 3.3, -2.97}
HQ_SPIRE_TIP  :: rl.Vector3{-2.97, 5.6, -2.97}
HQ_POD_RADIAL :: 4.55

HQ_HULL      :: rl.Color{205, 50, 58, 255}
HQ_HULL_HI   :: rl.Color{228, 76, 84, 255}
HQ_TRIM      :: rl.Color{255, 120, 125, 255}
HQ_DARK      :: rl.Color{94, 23, 27, 255}
HQ_DARKER    :: rl.Color{51, 12, 14, 255}
HQ_GUNMETAL  :: rl.Color{44, 48, 58, 255}
HQ_STEEL     :: rl.Color{78, 84, 98, 255}
HQ_STEEL_LIT :: rl.Color{150, 158, 175, 255}
HQ_VOID      :: rl.Color{10, 10, 14, 255}
HQ_GLOW      :: rl.Color{255, 90, 90, 255}
HQ_GLOW_HOT  :: rl.Color{255, 196, 176, 255}
HQ_AMBER     :: rl.Color{255, 140, 25, 255}
HQ_WINDOW    :: rl.Color{255, 152, 112, 255}

hq_models: [HQ_Model_Part]rl.Model
hq_shader: rl.Shader
hq_shader_locs: HQ_Shader_Locs
hq_visuals_ready := false

HQ_VS :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;
out vec3 fragObjPos;
out vec3 fragWorldPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragMaterial;
void main() {
	fragObjPos = vertexPosition;
	fragWorldPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
	fragNormal = normalize((matNormal * vec4(vertexNormal, 0.0)).xyz);
	fragColor = vertexColor;
	fragMaterial = vertexTexCoord;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

HQ_FS :: `#version 330
in vec3 fragObjPos;
in vec3 fragWorldPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragMaterial;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform float fog;
uniform float wreck;
uniform float time;
out vec4 finalColor;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float plating(vec3 p, vec3 n) {
	vec3 an = abs(n);
	vec2 uv = an.y > max(an.x, an.z) ? p.xz : (an.x > an.z ? p.zy : p.xy);
	uv *= vec2(2.6, 3.4);
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 w = max(fwidth(uv), vec2(0.0001));
	vec2 edge = min(f, 1.0 - f) / w;
	float seam = 1.0 - clamp(min(edge.x, edge.y) - 0.5, 0.0, 1.0);
	float fade = clamp(1.5 - max(w.x, w.y) * 5.0, 0.0, 1.0);
	float tone = 0.93 + 0.14 * hash3(vec3(cell, floor(p.y * 0.5)));
	return mix(1.0, tone * (1.0 - 0.38 * seam), fade);
}

void main() {
	vec3 n = normalize(fragNormal);
	if (!gl_FrontFacing) n = -n;
	vec3 base = fragColor.rgb;
	float glow = fragMaterial.x;
	float plate = fragMaterial.y;

	if (wreck > 0.5) {
		float g = dot(base, vec3(0.30, 0.59, 0.11));
		float scorch = 0.6 * vnoise(fragObjPos * 1.7) + 0.4 * vnoise(fragObjPos * 4.3);
		base = vec3(g * 0.30 + 0.09) * vec3(1.0, 0.96, 0.93) * (0.45 + 0.65 * scorch);
		float ember = pow(max(sin(time * 1.3 + hash3(floor(fragObjPos * 7.0)) * 40.0), 0.0), 12.0);
		vec3 dead = vec3(0.11, 0.11, 0.12) + vec3(0.55, 0.13, 0.03) * ember * glow;
		base = mix(base, dead, glow);
		glow = 0.0;
		plate *= 0.6;
	}

	base *= mix(1.0, plating(fragObjPos, n), plate);

	vec3 v = normalize(viewPos - fragWorldPos);
	float diff = max(dot(n, lightDir), 0.0);
	float fill = max(dot(n, normalize(vec3(0.55, 0.15, -0.65))), 0.0);
	float sky = 0.5 + 0.5 * n.y;
	float spec = pow(max(dot(n, normalize(lightDir + v)), 0.0), 28.0);
	float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
	float occlusion = 0.74 + 0.26 * smoothstep(-2.6, 1.2, fragObjPos.y);
	vec3 lit = base * (0.22 + 0.80 * diff + 0.18 * fill + 0.14 * sky) * occlusion;
	lit += vec3(1.0, 0.86, 0.80) * spec * 0.18 * (1.0 - 0.8 * wreck);
	lit += vec3(1.0, 0.28, 0.26) * rim * 0.16 * (1.0 - wreck);

	float grey = dot(lit, vec3(0.30, 0.59, 0.11));
	lit = mix(lit, vec3(grey), 0.25 * fog) * (1.0 - 0.5 * fog);

	vec3 col = mix(lit, min(base * 1.12, vec3(1.0)), glow);
	finalColor = vec4(col, fragColor.a);
}
`

hq_rand :: proc(state: ^u32) -> f32 {
	state^ = state^ * 1664525 + 1013904223
	return f32((state^ >> 8) & 0xFFFF) / f32(0xFFFF)
}

hq_tri :: proc(b: ^HQ_Builder, p0, p1, p2, n: rl.Vector3, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	q1, q2 := p1, p2
	if rl.Vector3DotProduct(rl.Vector3CrossProduct(p1 - p0, p2 - p0), n) < 0 {
		q1, q2 = p2, p1
	}
	for p in ([3]rl.Vector3{p0, q1, q2}) {
		append(&b.verts, p.x, p.y, p.z)
		append(&b.norms, n.x, n.y, n.z)
		append(&b.cols, col.r, col.g, col.b, col.a)
		append(&b.uvs, glow, plate)
	}
}

hq_quad :: proc(b: ^HQ_Builder, p0, p1, p2, p3, n: rl.Vector3, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	hq_tri(b, p0, p1, p2, n, col, glow, plate)
	hq_tri(b, p0, p2, p3, n, col, glow, plate)
}

hq_face :: proc(b: ^HQ_Builder, p0, p1, p2, p3, hint: rl.Vector3, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	n := rl.Vector3CrossProduct(p1 - p0, p3 - p0)
	if rl.Vector3Length(n) < 0.000001 { n = rl.Vector3CrossProduct(p2 - p1, p0 - p1) }
	if rl.Vector3Length(n) < 0.000001 { return }
	n = rl.Vector3Normalize(n)
	if rl.Vector3DotProduct(n, hint) < 0 { n = -n }
	hq_quad(b, p0, p1, p2, p3, n, col, glow, plate)
}

hq_tag :: proc(b: ^HQ_Builder, glow, plate: f32) {
	for len(b.uvs) / 2 < len(b.verts) / 3 {
		append(&b.uvs, glow, plate)
	}
}

hq_cyl :: proc(b: ^HQ_Builder, start, end: rl.Vector3, r_start, r_end: f32, sides: int, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	add_cylinder(&b.verts, &b.norms, &b.cols, start, end, r_start, r_end, sides, col)
	hq_tag(b, glow, plate)
}

hq_sphere :: proc(b: ^HQ_Builder, center: rl.Vector3, radius: f32, rings, slices: int, col: rl.Color, glow: f32 = 0) {
	add_sphere(&b.verts, &b.norms, &b.cols, center, radius, rings, slices, col)
	hq_tag(b, glow, 0)
}

hq_box :: proc(b: ^HQ_Builder, center: rl.Vector3, hw, hh, hl: f32, fwd, up, right: rl.Vector3, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	p0 := center - right * hw - up * hh - fwd * hl
	p1 := center + right * hw - up * hh - fwd * hl
	p2 := center + right * hw + up * hh - fwd * hl
	p3 := center - right * hw + up * hh - fwd * hl
	p4 := center - right * hw - up * hh + fwd * hl
	p5 := center + right * hw - up * hh + fwd * hl
	p6 := center + right * hw + up * hh + fwd * hl
	p7 := center - right * hw + up * hh + fwd * hl
	hq_quad(b, p0, p1, p2, p3, -fwd, col, glow, plate)
	hq_quad(b, p4, p5, p6, p7, fwd, col, glow, plate)
	hq_quad(b, p0, p1, p5, p4, -up, col, glow, plate)
	hq_quad(b, p3, p2, p6, p7, up, col, glow, plate)
	hq_quad(b, p0, p3, p7, p4, -right, col, glow, plate)
	hq_quad(b, p1, p2, p6, p5, right, col, glow, plate)
}

hq_axis_box :: proc(b: ^HQ_Builder, center: rl.Vector3, hx, hy, hz: f32, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	hq_box(b, center, hx, hy, hz, {0, 0, 1}, {0, 1, 0}, {1, 0, 0}, col, glow, plate)
}

hq_beam :: proc(b: ^HQ_Builder, a, z: rl.Vector3, hw, hh: f32, up_hint: rl.Vector3, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	d := z - a
	length := rl.Vector3Length(d)
	if length < 0.0001 { return }
	f := d / length
	r := rl.Vector3CrossProduct(f, up_hint)
	if rl.Vector3Length(r) < 0.001 { r = rl.Vector3CrossProduct(f, {1, 0, 0}) }
	r = rl.Vector3Normalize(r)
	u := rl.Vector3CrossProduct(r, f)
	hq_box(b, (a + z) * 0.5, hw, hh, length * 0.5, f, u, r, col, glow, plate)
}

hq_chamfer_rect :: proc(x0, x1, y0, y1, ch: f32) -> [8]rl.Vector2 {
	return {{x1, y0 + ch}, {x1, y1 - ch}, {x1 - ch, y1}, {x0 + ch, y1}, {x0, y1 - ch}, {x0, y0 + ch}, {x0 + ch, y0}, {x1 - ch, y0}}
}

hq_octagon :: proc(half, ch: f32) -> [8]rl.Vector2 {
	return hq_chamfer_rect(-half, half, -half, half, ch)
}

Slab_Frame :: struct {
	origin, fwd, up, right: rl.Vector3,
}

HQ_WORLD_FRAME :: Slab_Frame{origin = {0, 0, 0}, fwd = {0, 0, 1}, up = {0, 1, 0}, right = {1, 0, 0}}

slab_point :: proc(f: Slab_Frame, p: rl.Vector2, y: f32) -> rl.Vector3 {
	return f.origin + f.right * p.x + f.fwd * p.y + f.up * y
}

slab_face_point :: proc(f: Slab_Frame, bottom, top: []rl.Vector2, y0, y1: f32, i: int, t, s: f32) -> rl.Vector3 {
	j := (i + 1) % len(bottom)
	lo := bottom[i] + (bottom[j] - bottom[i]) * t
	hi := top[i] + (top[j] - top[i]) * t
	return slab_point(f, lo + (hi - lo) * s, y0 + (y1 - y0) * s)
}

hq_slab :: proc(b: ^HQ_Builder, f: Slab_Frame, bottom, top: []rl.Vector2, y0, y1: f32, col: rl.Color, glow: f32 = 0, plate: f32 = 0) {
	n := len(bottom)
	mid := f.origin + f.up * ((y0 + y1) * 0.5)
	for i in 0..<n {
		j := (i + 1) % n
		b0 := slab_point(f, bottom[i], y0)
		b1 := slab_point(f, bottom[j], y0)
		t1 := slab_point(f, top[j], y1)
		t0 := slab_point(f, top[i], y1)
		hq_face(b, b0, b1, t1, t0, (b0 + b1 + t0 + t1) * 0.25 - mid, col, glow, plate)
	}
	top_c := f.origin + f.up * y1
	bot_c := f.origin + f.up * y0
	for i in 0..<n {
		j := (i + 1) % n
		hq_tri(b, top_c, slab_point(f, top[i], y1), slab_point(f, top[j], y1), f.up, col, glow, plate)
		hq_tri(b, bot_c, slab_point(f, bottom[i], y0), slab_point(f, bottom[j], y0), -f.up, col, glow, plate)
	}
}

slab_face_frame :: proc(f: Slab_Frame, bottom, top: []rl.Vector2, y0, y1: f32, i: int) -> (tan, vert, nrm: rl.Vector3, length: f32) {
	a := slab_face_point(f, bottom, top, y0, y1, i, 0, 0.5)
	z := slab_face_point(f, bottom, top, y0, y1, i, 1, 0.5)
	lo := slab_face_point(f, bottom, top, y0, y1, i, 0.5, 0)
	hi := slab_face_point(f, bottom, top, y0, y1, i, 0.5, 1)
	length = rl.Vector3Length(z - a)
	tan = (z - a) / length
	vert = hi - lo
	vert = rl.Vector3Normalize(vert - tan * rl.Vector3DotProduct(vert, tan))
	nrm = rl.Vector3Normalize(rl.Vector3CrossProduct(tan, vert))
	if rl.Vector3DotProduct(nrm, (a + z) * 0.5 - (f.origin + f.up * ((y0 + y1) * 0.5))) < 0 { nrm = -nrm }
	return
}

hq_slab_windows :: proc(b: ^HQ_Builder, f: Slab_Frame, bottom, top: []rl.Vector2, y0, y1, s, spacing, hw, hh: f32, mask: u32, col: rl.Color, seed: u32) {
	rng := seed
	for i in 0..<len(bottom) {
		if mask & (1 << u32(i)) == 0 { continue }
		tan, vert, nrm, length := slab_face_frame(f, bottom, top, y0, y1, i)
		count := int(length / spacing) - 1
		for k in 0..<count {
			if hq_rand(&rng) < 0.2 { continue }
			t := f32(k + 1) / f32(count + 1)
			c := slab_face_point(f, bottom, top, y0, y1, i, t, s) + nrm * 0.012
			hq_quad(b, c - tan * hw - vert * hh, c + tan * hw - vert * hh, c + tan * hw + vert * hh, c - tan * hw + vert * hh, nrm, col, 1)
		}
	}
}

hq_slab_band :: proc(b: ^HQ_Builder, f: Slab_Frame, bottom, top: []rl.Vector2, y0, y1, s0, s1, inset: f32, mask: u32, col: rl.Color) {
	for i in 0..<len(bottom) {
		if mask & (1 << u32(i)) == 0 { continue }
		_, _, nrm, _ := slab_face_frame(f, bottom, top, y0, y1, i)
		off := nrm * 0.012
		p0 := slab_face_point(f, bottom, top, y0, y1, i, inset, s0) + off
		p1 := slab_face_point(f, bottom, top, y0, y1, i, 1 - inset, s0) + off
		p2 := slab_face_point(f, bottom, top, y0, y1, i, 1 - inset, s1) + off
		p3 := slab_face_point(f, bottom, top, y0, y1, i, inset, s1) + off
		hq_quad(b, p0, p1, p2, p3, nrm, col, 1)
	}
}

hq_random_frame :: proc(rng: ^u32) -> (fwd, up, right: rl.Vector3) {
	v := rl.Vector3{hq_rand(rng) * 2 - 1, hq_rand(rng) * 2 - 1, hq_rand(rng) * 2 - 1}
	if rl.Vector3Length(v) < 0.05 { v = {1, 0.2, 0.3} }
	fwd = rl.Vector3Normalize(v)
	right = rl.Vector3CrossProduct(fwd, {0, 1, 0})
	if rl.Vector3Length(right) < 0.05 { right = rl.Vector3CrossProduct(fwd, {1, 0, 0}) }
	right = rl.Vector3Normalize(right)
	up = rl.Vector3CrossProduct(right, fwd)
	return
}

hq_finish :: proc(b: ^HQ_Builder) -> rl.Model {
	mesh := make_mesh_from_arrays(b.verts[:], b.norms[:], b.cols[:], b.uvs[:])
	delete(b.verts)
	delete(b.norms)
	delete(b.cols)
	delete(b.uvs)
	model := rl.LoadModelFromMesh(mesh)
	model.materials[0].shader = hq_shader
	return model
}

build_hq_ventral :: proc(b: ^HQ_Builder) {
	up := rl.Vector3{0, 1, 0}
	f := HQ_WORLD_FRAME

	keel_top := hq_octagon(2.6, 0.95)
	keel_bot := hq_octagon(1.85, 0.68)
	hq_slab(b, f, keel_bot[:], keel_top[:], -1.5, -0.7, HQ_DARK, 0, 1)
	belt := hq_octagon(1.92, 0.7)
	hq_slab(b, f, belt[:], belt[:], -1.58, -1.5, HQ_TRIM)
	cone_top := hq_octagon(1.82, 0.66)
	cone_bot := hq_octagon(1.0, 0.36)
	hq_slab(b, f, cone_bot[:], cone_top[:], -2.3, -1.58, HQ_GUNMETAL, 0, 1)
	hq_slab_windows(b, f, keel_bot[:], keel_top[:], -1.5, -0.7, 0.55, 0.2, 0.05, 0.03, 0x55, HQ_WINDOW, 11)

	for i in 0..<8 {
		a := slab_point(f, keel_top[i] * 1.01, -0.72)
		z := slab_point(f, keel_bot[i] * 1.03, -1.5)
		hq_beam(b, a, z, 0.07, 0.05, up, HQ_DARKER)
	}

	for i in 0..<8 {
		ang := f32(i) * (math.PI / 4.0)
		dir := rl.Vector3{math.cos(ang + math.PI / 8.0), 0, math.sin(ang + math.PI / 8.0)}
		tan := rl.Vector3{-dir.z, 0, dir.x}
		fin_c := dir * 1.42 - up * 1.98
		hq_box(b, fin_c, 0.035, 0.27, 0.3, dir, up, tan, HQ_DARKER)
		hq_box(b, fin_c + dir * 0.31, 0.04, 0.24, 0.012, dir, up, tan, HQ_GLOW, 1)
	}

	hq_cyl(b, -up * 2.3, -up * 2.42, 1.15, 1.12, 20, HQ_GUNMETAL)
	hq_cyl(b, -up * 2.42, -up * 2.47, 1.04, 1.0, 20, HQ_GLOW, 1)
	for i in 0..<12 {
		ang := f32(i) * (math.PI / 6.0)
		dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		hq_box(b, dir * 1.14 - up * 2.36, 0.07, 0.07, 0.05, dir, up, {-dir.z, 0, dir.x}, HQ_STEEL)
	}

	for i in 0..<4 {
		ang := f32(i) * (math.PI / 2.0)
		fdir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		ftan := rl.Vector3{-fdir.z, 0, fdir.x}
		f_top := -up * 1.0 + fdir * 1.7
		f_bot := -up * 2.5 + fdir * 0.62
		hq_cyl(b, f_top, f_bot, 0.15, 0.06, 6, HQ_DARK)
		hq_beam(b, f_top + ftan * 0.1, f_bot + ftan * 0.06, 0.016, 0.016, up, HQ_GLOW, 1)
		hq_beam(b, f_top - ftan * 0.1, f_bot - ftan * 0.06, 0.016, 0.016, up, HQ_GLOW, 1)
		hq_cyl(b, f_bot, f_bot - up * 0.5 - fdir * 0.18, 0.04, 0.008, 4, HQ_STEEL_LIT)
	}
}

build_hq_deck :: proc(b: ^HQ_Builder, wreck: bool) {
	up := rl.Vector3{0, 1, 0}
	f := HQ_WORLD_FRAME

	d1_bot := hq_octagon(2.6, 0.95)
	d1_top := hq_octagon(3.2, 1.12)
	hq_slab(b, f, d1_bot[:], d1_top[:], -0.7, -0.05, HQ_DARK, 0, 1)
	rim := hq_octagon(3.27, 1.15)
	hq_slab(b, f, rim[:], rim[:], -0.05, 0.05, HQ_TRIM)
	d2_bot := hq_octagon(3.12, 1.1)
	d2_top := hq_octagon(2.86, 1.0)
	hq_slab(b, f, d2_bot[:], d2_top[:], 0.05, 0.62, HQ_HULL, 0, 1)
	lip := hq_octagon(2.9, 1.02)
	hq_slab(b, f, lip[:], lip[:], 0.62, 0.65, HQ_HULL_HI)
	hq_slab_windows(b, f, d2_bot[:], d2_top[:], 0.05, 0.62, 0.36, 0.16, 0.05, 0.035, 0x55, HQ_WINDOW, 23)
	hq_slab_windows(b, f, d2_bot[:], d2_top[:], 0.05, 0.62, 0.7, 0.16, 0.05, 0.035, 0x55, HQ_WINDOW, 37)
	hq_slab_band(b, f, d1_bot[:], d1_top[:], -0.7, -0.05, 0.62, 0.7, 0.06, 0xFF, HQ_GLOW)

	for i in 0..<8 {
		p := slab_point(f, rim[i] * 1.004, 0)
		hq_sphere(b, p, 0.06, 4, 6, i % 2 == 0 ? HQ_GLOW : HQ_AMBER, 1)
	}

	deck_y: f32 = 0.65
	for i in 0..<4 {
		ang := f32(i) * (math.PI / 2.0)
		cdir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		ctan := rl.Vector3{-cdir.z, 0, cdir.x}

		wall_c := cdir * 2.62 + up * (deck_y + 0.17)
		hq_box(b, wall_c, 1.15, 0.17, 0.1, cdir, up, ctan, HQ_DARK, 0, 1)
		for k in 0..<7 {
			t := -1.0 + f32(k) * (2.0 / 6.0)
			hq_box(b, wall_c + ctan * t + up * 0.21, 0.07, 0.05, 0.1, cdir, up, ctan, HQ_HULL)
		}
		hq_box(b, wall_c + cdir * 0.105 - up * 0.04, 1.0, 0.016, 0.006, cdir, up, ctan, HQ_GLOW, 1)
		for s in ([2]f32{-1, 1}) {
			hq_box(b, wall_c + ctan * (s * 1.22), 0.09, 0.24, 0.14, cdir, up, ctan, HQ_GUNMETAL)
			hq_sphere(b, wall_c + ctan * (s * 1.22) + up * 0.28, 0.05, 4, 6, HQ_AMBER, 1)
		}

		if i == 2 {
			for s in ([2]f32{-1, 1}) {
				ped := cdir * 2.15 + ctan * (s * 0.55) + up * deck_y
				hq_cyl(b, ped, ped + up * 0.24, 0.08, 0.06, 6, HQ_GUNMETAL)
				dish_dir := rl.Vector3Normalize(cdir * 0.45 + up * 0.85 + ctan * (s * 0.25))
				dish_base := ped + up * 0.24
				hq_cyl(b, dish_base, dish_base + dish_dir * 0.14, 0.05, 0.34, 14, HQ_STEEL_LIT)
				hq_cyl(b, dish_base + dish_dir * 0.14, dish_base + dish_dir * 0.4, 0.014, 0.01, 4, HQ_STEEL)
				hq_sphere(b, dish_base + dish_dir * 0.42, 0.035, 4, 6, HQ_GLOW, 1)
			}
			hq_axis_box(b, cdir * 2.15 + up * (deck_y + 0.06), 0.18, 0.06, 0.16, HQ_GUNMETAL)
			continue
		}

		vls_c := cdir * 2.12 + up * deck_y
		hq_box(b, vls_c + up * 0.03, 0.58, 0.03, 0.34, cdir, up, ctan, HQ_GUNMETAL)
		for vr in 0..<4 {
			for vc in 0..<2 {
				cell := vls_c + ctan * ((f32(vr) - 1.5) * 0.27) + cdir * ((f32(vc) - 0.5) * 0.3) + up * 0.075
				hq_box(b, cell, 0.11, 0.025, 0.11, cdir, up, ctan, HQ_DARKER)
				hq_box(b, cell + up * 0.027 - cdir * 0.06, 0.09, 0.004, 0.012, cdir, up, ctan, HQ_STEEL)
				hq_box(b, cell + up * 0.03 + cdir * 0.05, 0.022, 0.006, 0.022, cdir, up, ctan, HQ_GLOW, 1)
			}
		}
	}

	rng := u32(0x2F6E2B1)
	placed := 0
	for placed < 60 {
		ang := hq_rand(&rng) * 2 * math.PI
		r := 2.15 + hq_rand(&rng) * 0.6
		quarter := math.mod(ang, math.PI / 2.0)
		if quarter < 0.42 || quarter > math.PI / 2.0 - 0.42 { continue }
		if abs(quarter - math.PI / 4.0) < 0.2 { continue }
		placed += 1
		dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		tan := rl.Vector3{-dir.z, 0, dir.x}
		pos := dir * r + up * deck_y
		kind := hq_rand(&rng)
		if kind < 0.6 {
			hw := 0.05 + hq_rand(&rng) * 0.1
			hh := 0.03 + hq_rand(&rng) * 0.07
			hl := 0.05 + hq_rand(&rng) * 0.1
			pick := hq_rand(&rng)
			col := pick < 0.35 ? HQ_DARK : (pick < 0.65 ? HQ_GUNMETAL : (pick < 0.85 ? HQ_STEEL : HQ_HULL_HI))
			hq_box(b, pos + up * hh, hw, hh, hl, dir, up, tan, col)
		} else if kind < 0.85 {
			rad := 0.05 + hq_rand(&rng) * 0.05
			hq_cyl(b, pos, pos + up * 0.07, rad, rad * 0.9, 8, HQ_GUNMETAL)
			hq_cyl(b, pos + up * 0.07, pos + up * 0.08, rad * 0.6, rad * 0.6, 8, HQ_GLOW, 1)
		} else {
			hq_beam(b, pos + up * 0.04 - tan * 0.2, pos + up * 0.04 + tan * 0.2, 0.025, 0.025, up, HQ_STEEL)
		}
	}

	for d in 0..<4 {
		ang := f32(d) * (math.PI / 2.0) + math.PI / 4.0
		dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		base := dir * 2.5 + up * deck_y
		hq_cyl(b, base, base + up * 0.1, 0.17, 0.15, 10, HQ_GUNMETAL)
		hq_sphere(b, base + up * 0.16, 0.13, 5, 8, HQ_STEEL)
		aim := rl.Vector3Normalize(dir * 0.8 + up * 0.6)
		side := rl.Vector3{-dir.z, 0, dir.x}
		for s in ([2]f32{-1, 1}) {
			root := base + up * 0.18 + side * (s * 0.05)
			hq_cyl(b, root, root + aim * 0.36, 0.024, 0.02, 5, HQ_STEEL_LIT)
			hq_sphere(b, root + aim * 0.37, 0.022, 3, 4, HQ_GLOW, 1)
		}
	}

	if wreck {
		hole_rng := u32(0x51A6)
		for _ in 0..<14 {
			ang := hq_rand(&hole_rng) * 2 * math.PI
			r := 1.9 + hq_rand(&hole_rng) * 0.9
			dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
			fw, u, rt := hq_random_frame(&hole_rng)
			s := 0.12 + hq_rand(&hole_rng) * 0.16
			hq_box(b, dir * r + up * (deck_y + 0.02), s, s * 0.5, s * 0.8, fw, u, rt, HQ_VOID)
		}
	}
}

build_hq_superstructure :: proc(b: ^HQ_Builder, wreck: bool) {
	up := rl.Vector3{0, 1, 0}
	f := HQ_WORLD_FRAME

	s1_bot := hq_octagon(1.75, 0.55)
	s1_top := hq_octagon(1.6, 0.5)
	hq_slab(b, f, s1_bot[:], s1_top[:], 0.65, 1.25, HQ_DARK, 0, 1)
	hq_slab_windows(b, f, s1_bot[:], s1_top[:], 0.65, 1.25, 0.32, 0.15, 0.045, 0.032, 0xFF, HQ_WINDOW, 51)
	hq_slab_windows(b, f, s1_bot[:], s1_top[:], 0.65, 1.25, 0.66, 0.15, 0.045, 0.032, 0x55, HQ_WINDOW, 73)

	for i in 0..<4 {
		k := i * 2 + 1
		corner_lo := slab_point(f, s1_bot[k] + (s1_bot[(k + 1) % 8] - s1_bot[k]) * 0.5, 0.65)
		corner_hi := slab_point(f, s1_top[k] + (s1_top[(k + 1) % 8] - s1_top[k]) * 0.5, 1.25)
		out := rl.Vector3Normalize(rl.Vector3{corner_lo.x, 0, corner_lo.z})
		hq_beam(b, corner_lo + out * 0.42, corner_hi + out * 0.04, 0.11, 0.09, out, HQ_HULL_HI, 0, 1)
	}

	s2_bot := hq_octagon(1.45, 0.42)
	s2_top := hq_octagon(1.3, 0.36)
	hq_slab(b, f, s2_bot[:], s2_top[:], 1.25, 1.87, HQ_HULL, 0, 1)
	hq_slab_band(b, f, s2_bot[:], s2_top[:], 1.25, 1.87, 0.5, 0.64, 0.05, 0xFF, HQ_GLOW)
	hq_slab_windows(b, f, s2_bot[:], s2_top[:], 1.25, 1.87, 0.25, 0.13, 0.04, 0.028, 0x55, HQ_WINDOW, 97)
	cap := hq_octagon(1.36, 0.38)
	hq_slab(b, f, cap[:], cap[:], 1.87, 1.95, HQ_TRIM)

	for s in ([2]f32{-1, 1}) {
		blister := rl.Vector3{-0.35, 1.5, s * 1.5}
		hq_axis_box(b, blister, 0.24, 0.2, 0.2, HQ_GUNMETAL)
		hq_axis_box(b, blister + {0, 0.21, 0}, 0.2, 0.02, 0.16, HQ_STEEL)
		hq_sphere(b, blister + {0.05, 0.04, s * 0.2}, 0.09, 5, 8, HQ_AMBER, 1)
		hq_cyl(b, blister + {-0.12, 0.22, 0}, blister + {-0.12, 0.88, 0}, 0.02, 0.008, 4, HQ_STEEL_LIT)
		hq_sphere(b, blister + {-0.12, 0.9, 0}, 0.025, 3, 4, HQ_GLOW, 1)
	}

	mount := rl.Vector3{HQ_BATTERY_PIVOT.x, 1.95, HQ_BATTERY_PIVOT.z}
	hq_cyl(b, mount, mount + up * 0.04, 1.18, 1.18, 24, HQ_TRIM)
	hq_cyl(b, mount + up * 0.04, mount + up * 0.2, 1.12, 1.05, 24, HQ_GUNMETAL, 0, 1)
	hq_cyl(b, mount + up * 0.18, mount + up * 0.22, 1.08, 1.08, 24, HQ_GLOW, 1)
	hq_cyl(b, mount + up * 0.2, mount + up * 0.23, 0.86, 0.86, 20, HQ_STEEL_LIT)
	for i in 0..<12 {
		ang := f32(i) * (math.PI / 6.0) + math.PI / 12.0
		dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		hq_box(b, mount + dir * 1.11 + up * 0.11, 0.13, 0.06, 0.04, dir, up, {-dir.z, 0, dir.x}, HQ_STEEL)
	}

	sensor := rl.Vector3{-1.05, 1.95, 0}
	hq_cyl(b, sensor, sensor + up * 0.06, 0.3, 0.28, 12, HQ_TRIM)
	hq_sphere(b, sensor + up * 0.06, 0.22, 6, 10, HQ_STEEL_LIT)
	hq_cyl(b, sensor + up * 0.12, sensor + up * 0.15, 0.2, 0.2, 12, HQ_GLOW, 1)
	for s in ([3]f32{-1, 0, 1}) {
		whip := sensor + {-0.2, 0, s * 0.32}
		hq_cyl(b, whip, whip + up * 0.42, 0.018, 0.008, 4, HQ_STEEL_LIT)
		hq_sphere(b, whip + up * 0.44, 0.022, 3, 4, HQ_GLOW, 1)
	}
}

build_hq_mast :: proc(b: ^HQ_Builder, wreck: bool) {
	up := rl.Vector3{0, 1, 0}
	dir := rl.Vector3Normalize({HQ_MAST_ROOT.x, 0, HQ_MAST_ROOT.z})
	tan := rl.Vector3{-dir.z, 0, dir.x}
	root := HQ_MAST_ROOT

	hq_cyl(b, root, root + up * 0.14, 0.3, 0.28, 10, HQ_TRIM)
	snap: f32 = wreck ? 1.6 : 2.5
	hq_cyl(b, root, root + up * snap, 0.24, 0.15 + (2.5 - snap) * 0.04, 8, HQ_GUNMETAL, 0, 1)
	for sd in ([2]f32{-1, 1}) {
		for st in ([2]f32{-1, 1}) {
			hq_cyl(b, root + dir * (sd * 0.28) + tan * (st * 0.34), root + up * 1.3, 0.024, 0.018, 4, HQ_STEEL)
		}
	}
	obs := root + up * 1.4
	hq_box(b, obs, 0.22, 0.14, 0.22, dir, up, tan, HQ_DARK)
	hq_box(b, obs + up * 0.03, 0.225, 0.03, 0.225, dir, up, tan, HQ_GLOW, 1)
	hq_box(b, obs + up * 0.16, 0.18, 0.02, 0.18, dir, up, tan, HQ_STEEL)

	if wreck {
		top_break := root + up * snap
		fallen := top_break - dir * 1.7 + tan * 0.6 - up * 1.25
		hq_cyl(b, top_break - up * 0.05 - dir * 0.05, fallen, 0.13, 0.06, 6, HQ_STEEL_LIT)
		hq_cyl(b, fallen + dir * 0.5 - tan * 0.4, fallen + dir * 0.2 + tan * 0.45, 0.03, 0.03, 4, HQ_STEEL)
		hq_cyl(b, top_break, top_break + up * 0.2 + dir * 0.08, 0.15, 0.02, 5, HQ_GUNMETAL)
		return
	}

	hq_cyl(b, root + up * 2.5, root + up * 4.8, 0.15, 0.045, 6, HQ_STEEL_LIT)
	for bar in ([2][2]f32{{2.1, 0.9}, {3.4, 0.55}}) {
		y := root + up * bar[0]
		hq_cyl(b, y - tan * bar[1], y + tan * bar[1], 0.035, 0.035, 4, HQ_STEEL)
		for s in ([2]f32{-1, 1}) {
			end := y + tan * (s * bar[1])
			hq_sphere(b, end, 0.04, 3, 4, bar[0] > 3 ? HQ_GLOW : HQ_AMBER, 1)
			if bar[0] < 3 {
				dish_dir := rl.Vector3Normalize(-dir * 0.3 + up * 0.6 + tan * (s * 0.75))
				hq_cyl(b, end, end + dish_dir * 0.06, 0.03, 0.17, 10, HQ_STEEL)
			}
		}
	}
	hq_cyl(b, root + up * 3.9, root + up * 3.96, 0.13, 0.13, 8, HQ_GUNMETAL)
	hq_cyl(b, root + up * 3.96, root + up * 3.99, 0.085, 0.085, 8, HQ_GLOW, 1)
	hq_cyl(b, root + up * 2.54, root + up * 2.6, 0.16, 0.16, 10, HQ_GUNMETAL)
}

build_hq_pod :: proc(b: ^HQ_Builder, d: int) {
	up := rl.Vector3{0, 1, 0}
	ang := f32(d) * (math.PI / 2.0) + math.PI / 4.0
	dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
	tan := rl.Vector3{-dir.z, 0, dir.x}
	f := Slab_Frame{origin = dir * HQ_POD_RADIAL, fwd = dir, up = up, right = tan}

	keel := hq_chamfer_rect(-0.36, 0.36, -0.6, 0.72, 0.14)
	keel_top := hq_chamfer_rect(-0.48, 0.48, -0.7, 0.82, 0.2)
	hq_slab(b, f, keel[:], keel_top[:], -0.38, -0.2, HQ_DARK)
	body_bot := hq_chamfer_rect(-0.6, 0.6, -0.85, 0.9, 0.26)
	body_top := hq_chamfer_rect(-0.5, 0.5, -0.8, 0.84, 0.22)
	hq_slab(b, f, body_bot[:], body_top[:], -0.2, 0.6, HQ_HULL, 0, 1)
	deck := hq_chamfer_rect(-0.4, 0.4, -0.68, 0.66, 0.16)
	hq_slab(b, f, deck[:], deck[:], 0.6, 0.7, HQ_DARK)
	hq_slab_windows(b, f, body_bot[:], body_top[:], -0.2, 0.6, 0.62, 0.15, 0.04, 0.03, 0x11, HQ_WINDOW, u32(131 + d))
	hq_slab_band(b, f, body_bot[:], body_top[:], -0.2, 0.6, 0.18, 0.24, 0.1, 0xEB, HQ_GLOW)

	for k in 0..<4 {
		hq_box(b, slab_point(f, {0, -0.5 + f32(k) * 0.34}, 0.73), 0.44, 0.03, 0.045, dir, up, tan, HQ_TRIM)
	}
	for s in ([2]f32{-1, 1}) {
		for k in 0..<3 {
			hq_box(b, slab_point(f, {s * 0.6, -0.5 + f32(k) * 0.45}, 0.3), 0.035, 0.14, 0.17, dir, up, tan, HQ_DARK)
		}
	}

	door := slab_point(f, {0, 0.86}, 0.12)
	hq_box(b, door, 0.36, 0.2, 0.045, dir, up, tan, HQ_VOID)
	hq_box(b, door + dir * 0.05 + up * 0.22, 0.42, 0.03, 0.03, dir, up, tan, HQ_TRIM)
	hq_box(b, door + dir * 0.05 - up * 0.22, 0.42, 0.03, 0.03, dir, up, tan, HQ_TRIM)
	hq_box(b, door + dir * 0.05 + tan * 0.39, 0.03, 0.22, 0.03, dir, up, tan, HQ_TRIM)
	hq_box(b, door + dir * 0.05 - tan * 0.39, 0.03, 0.22, 0.03, dir, up, tan, HQ_TRIM)
	hq_box(b, door + dir * 0.05 - up * 0.15, 0.3, 0.018, 0.006, dir, up, tan, HQ_GLOW, 1)
	for k in 0..<3 {
		hq_box(b, door + dir * 0.05 + up * 0.13 + tan * (f32(k - 1) * 0.2), 0.03, 0.015, 0.006, dir, up, tan, HQ_GLOW_HOT, 1)
	}
	apron := slab_point(f, {0, 1.05}, -0.16)
	hq_box(b, apron, 0.32, 0.03, 0.16, dir, up, tan, HQ_DARK)
	for k in 0..<3 {
		for s in ([2]f32{-1, 1}) {
			hq_box(b, apron + dir * (f32(k - 1) * 0.1) + tan * (s * 0.26) + up * 0.035, 0.018, 0.008, 0.018, dir, up, tan, HQ_AMBER, 1)
		}
	}

	collar := slab_point(f, {0, -1.02}, 0.2)
	hq_box(b, collar, 0.42, 0.3, 0.26, dir, up, tan, HQ_GUNMETAL, 0, 1)
	hq_box(b, collar + up * 0.31, 0.36, 0.02, 0.22, dir, up, tan, HQ_STEEL)
	for s in ([2]f32{-1, 1}) {
		a := dir * 2.95 + up * 0.72 + tan * (s * 0.22)
		z := dir * (HQ_POD_RADIAL - 0.78) + up * 0.72 + tan * (s * 0.22)
		hq_cyl(b, a, z, 0.05, 0.05, 6, HQ_STEEL)
		hq_cyl(b, a + up * 0.048, z + up * 0.048, 0.012, 0.012, 4, HQ_GLOW, 1)
		for k in 0..<3 {
			c := a + (z - a) * (0.2 + f32(k) * 0.3)
			hq_cyl(b, c - dir * 0.03, c + dir * 0.03, 0.065, 0.065, 6, HQ_GUNMETAL)
		}
	}
	hq_cyl(b, dir * 2.4 - up * 0.66, slab_point(f, {0, -0.45}, -0.32), 0.1, 0.07, 6, HQ_DARK)
	hq_cyl(b, dir * 2.6 - up * 0.6 + tan * 0.3, slab_point(f, {0.3, -0.6}, -0.25), 0.05, 0.04, 5, HQ_GUNMETAL)
	hq_cyl(b, dir * 2.6 - up * 0.6 - tan * 0.3, slab_point(f, {-0.3, -0.6}, -0.25), 0.05, 0.04, 5, HQ_GUNMETAL)

	turret := slab_point(f, {0, 0.12}, 0.7)
	hq_cyl(b, turret, turret + up * 0.12, 0.21, 0.19, 10, HQ_GUNMETAL)
	hq_sphere(b, turret + up * 0.14, 0.15, 5, 8, HQ_STEEL)
	for s in ([2]f32{-1, 1}) {
		root := turret + up * 0.17 + tan * (s * 0.09)
		hq_cyl(b, root, root + dir * 0.6, 0.038, 0.032, 6, HQ_STEEL_LIT)
		hq_cyl(b, root + dir * 0.42, root + dir * 0.48, 0.05, 0.05, 6, HQ_GUNMETAL)
		hq_sphere(b, root + dir * 0.61, 0.032, 3, 4, HQ_GLOW, 1)
	}

	for s in ([2]f32{-1, 1}) {
		light := slab_point(f, {s * 0.36, 0.56}, 0.7)
		hq_cyl(b, light, light + up * 0.06, 0.035, 0.03, 6, HQ_GUNMETAL)
	}
	hq_cyl(b, slab_point(f, {0.25, -0.5}, 0.7), slab_point(f, {0.25, -0.5}, 1.25), 0.016, 0.008, 4, HQ_STEEL_LIT)
}

build_hq_wreck_debris :: proc(b: ^HQ_Builder) {
	up := rl.Vector3{0, 1, 0}
	rng := u32(0xDEB215)
	ang := math.PI / 4.0 + math.PI / 2.0
	pod_dir := rl.Vector3{math.cos(f32(ang)), 0, math.sin(f32(ang))}
	pod_tan := rl.Vector3{-pod_dir.z, 0, pod_dir.x}
	hq_box(b, pod_dir * 3.55 + up * 0.15, 0.4, 0.28, 0.22, pod_dir, up, pod_tan, HQ_GUNMETAL)
	hq_box(b, pod_dir * 3.82 + up * 0.08, 0.3, 0.18, 0.08, pod_dir, up, pod_tan, HQ_VOID)
	for _ in 0..<16 {
		fw, u, rt := hq_random_frame(&rng)
		size := 0.06 + hq_rand(&rng) * 0.16
		pick := hq_rand(&rng)
		col := pick < 0.4 ? HQ_DARK : (pick < 0.75 ? HQ_GUNMETAL : HQ_HULL)
		pos: rl.Vector3
		if hq_rand(&rng) < 0.65 {
			pos = pod_dir * (HQ_POD_RADIAL + (hq_rand(&rng) - 0.4) * 1.4) + pod_tan * ((hq_rand(&rng) - 0.5) * 1.5) + up * (hq_rand(&rng) * 1.4 - 0.6)
		} else {
			a := hq_rand(&rng) * 2 * math.PI
			r := 3.6 + hq_rand(&rng) * 1.6
			pos = {math.cos(a) * r, hq_rand(&rng) * 1.8 - 0.7, math.sin(a) * r}
		}
		hq_box(b, pos, size, size * (0.15 + hq_rand(&rng) * 0.2), size * (0.6 + hq_rand(&rng) * 0.6), fw, u, rt, col)
	}
}

build_hq_hull :: proc(wreck: bool) -> rl.Model {
	b: HQ_Builder
	build_hq_ventral(&b)
	build_hq_deck(&b, wreck)
	build_hq_superstructure(&b, wreck)
	for d in 0..<4 {
		if wreck && d == 1 { continue }
		build_hq_pod(&b, d)
	}
	build_hq_mast(&b, wreck)
	if wreck { build_hq_wreck_debris(&b) }
	return hq_finish(&b)
}

build_hq_turret :: proc() -> rl.Model {
	b: HQ_Builder
	up := rl.Vector3{0, 1, 0}
	fwd := rl.Vector3{1, 0, 0}
	right := rl.Vector3{0, 0, 1}
	f := Slab_Frame{origin = {0, 0, 0}, fwd = fwd, up = up, right = right}

	body_bot := hq_chamfer_rect(-0.64, 0.64, -0.8, 0.74, 0.22)
	body_top := hq_chamfer_rect(-0.54, 0.54, -0.7, 0.6, 0.18)
	hq_slab(&b, f, body_bot[:], body_top[:], -0.62, -0.1, HQ_DARK, 0, 1)
	trim := hq_chamfer_rect(-0.46, 0.46, -0.62, 0.5, 0.14)
	hq_slab(&b, f, trim[:], trim[:], -0.1, -0.06, HQ_TRIM)
	hq_slab_band(&b, f, body_bot[:], body_top[:], -0.62, -0.1, 0.3, 0.38, 0.08, 0xFF, HQ_GLOW)

	for s in ([2]f32{-1, 1}) {
		hq_box(&b, right * (s * 0.54) - up * 0.12, 0.12, 0.32, 0.5, fwd, up, right, HQ_GUNMETAL, 0, 1)
		hq_box(&b, right * (s * 0.67) - up * 0.12, 0.02, 0.24, 0.4, fwd, up, right, HQ_STEEL)
		hq_cyl(&b, right * (s * 0.52), right * (s * 0.7), 0.15, 0.15, 10, HQ_GUNMETAL)
	}
	hq_cyl(&b, -right * 0.66, right * 0.66, 0.12, 0.12, 10, HQ_STEEL_LIT)

	bustle := -fwd * 0.84 - up * 0.36
	hq_box(&b, bustle, 0.46, 0.2, 0.16, fwd, up, right, HQ_GUNMETAL, 0, 1)
	for s in ([3]f32{-1, 0, 1}) {
		c := bustle + right * (s * 0.3) - fwd * 0.12
		hq_cyl(&b, c - up * 0.17, c + up * 0.17, 0.07, 0.07, 8, HQ_STEEL)
		hq_cyl(&b, c - up * 0.03, c + up * 0.03, 0.075, 0.075, 8, HQ_GLOW, 1)
	}
	hq_cyl(&b, -fwd * 0.6 - up * 0.2, -fwd * 0.4 + up * 0.02, 0.07, 0.06, 6, HQ_GUNMETAL)
	hq_axis_box(&b, {-0.3, -0.04, -0.3}, 0.1, 0.03, 0.1, HQ_STEEL)
	return hq_finish(&b)
}

build_hq_gun :: proc() -> rl.Model {
	b: HQ_Builder
	dir := rl.Vector3{1, 0, 0}
	nrm := rl.Vector3{0, 1, 0}
	right := rl.Vector3{0, 0, 1}

	shield_c := dir * 0.25
	for s in ([2]f32{-1, 1}) {
		hq_box(&b, shield_c + right * (s * 0.36), 0.16, 0.38, 0.09, dir, nrm, right, HQ_HULL, 0, 1)
		hq_box(&b, shield_c + right * (s * 0.36) + dir * 0.1, 0.12, 0.3, 0.012, dir, nrm, right, HQ_DARK)
	}
	hq_box(&b, shield_c + nrm * 0.27, 0.44, 0.08, 0.09, dir, nrm, right, HQ_TRIM)
	hq_box(&b, shield_c - nrm * 0.3, 0.44, 0.06, 0.09, dir, nrm, right, HQ_DARK)

	breech := -dir * 0.35
	hq_box(&b, breech, 0.45, 0.28, 0.48, dir, nrm, right, HQ_GUNMETAL, 0, 1)
	hq_box(&b, breech + nrm * 0.3, 0.36, 0.04, 0.4, dir, nrm, right, HQ_HULL)
	for k in 0..<4 {
		hq_box(&b, breech - dir * (0.32 - f32(k) * 0.16) + nrm * 0.35, 0.3, 0.012, 0.03, dir, nrm, right, HQ_STEEL)
	}
	hq_box(&b, breech - dir * 0.49, 0.32, 0.18, 0.012, dir, nrm, right, HQ_GLOW, 1)
	hq_cyl(&b, breech - dir * 0.45 - nrm * 0.18, -nrm * 0.45 - dir * 0.2, 0.07, 0.06, 6, HQ_GUNMETAL)

	for s in ([2]f32{-1, 1}) {
		rs := -dir * 0.3 + right * (s * 0.26) + nrm * 0.25
		re := dir * 0.7 + right * (s * 0.26) + nrm * 0.25
		hq_cyl(&b, rs, re, 0.095, 0.095, 8, HQ_STEEL_LIT)
		hq_cyl(&b, rs, rs + dir * 0.15, 0.12, 0.12, 8, HQ_GUNMETAL)
		hq_cyl(&b, re - dir * 0.06, re, 0.11, 0.11, 8, HQ_GUNMETAL)
	}

	for s in ([2]f32{-1, 1}) {
		root := right * (s * 0.26)
		s1_e := root + dir * 1.1
		hq_cyl(&b, root, s1_e, 0.165, 0.145, 10, HQ_DARK, 0, 1)
		hq_cyl(&b, root, root + dir * 0.25, 0.19, 0.19, 10, HQ_GUNMETAL)
		hq_beam(&b, root + dir * 0.3 + nrm * 0.16, root + dir * 1.05 + nrm * 0.14, 0.03, 0.02, nrm, HQ_STEEL)
		s2_e := root + dir * 2.7
		hq_cyl(&b, s1_e, s2_e, 0.13, 0.11, 10, HQ_GUNMETAL)
		for c_idx in 0..<5 {
			c_pos := s1_e + dir * (0.25 + f32(c_idx) * 0.46)
			c_end := c_pos + dir * 0.1
			hq_cyl(&b, c_pos, c_end, 0.155, 0.155, 10, HQ_GLOW, 1)
			hq_cyl(&b, c_pos - dir * 0.02, c_pos, 0.168, 0.168, 10, HQ_STEEL_LIT)
			hq_cyl(&b, c_end, c_end + dir * 0.02, 0.168, 0.168, 10, HQ_STEEL_LIT)
		}
		mb_e := s2_e + dir * 0.55
		hq_cyl(&b, s2_e, mb_e, 0.145, 0.145, 10, HQ_STEEL)
		for k in 0..<3 {
			baf := s2_e + dir * (0.1 + f32(k) * 0.15)
			hq_cyl(&b, baf, baf + dir * 0.05, 0.185, 0.185, 10, HQ_GUNMETAL)
		}
		hq_cyl(&b, mb_e, mb_e + dir * 0.015, 0.1, 0.1, 10, HQ_GLOW_HOT, 1)
	}
	hq_beam(&b, dir * 1.2, dir * 2.6, 0.2, 0.025, nrm, HQ_GUNMETAL)
	hq_cyl(&b, dir * 0.6 + nrm * 0.05, dir * 2.8 + nrm * 0.05, 0.014, 0.014, 4, HQ_GLOW, 1)

	sensor := nrm * 0.36 + dir * 0.4
	hq_box(&b, sensor, 0.18, 0.12, 0.22, dir, nrm, right, HQ_GUNMETAL)
	hq_sphere(&b, sensor + dir * 0.23 + nrm * 0.04, 0.075, 4, 6, HQ_GLOW, 1)
	hq_sphere(&b, sensor + dir * 0.22 - nrm * 0.05 + right * 0.08, 0.05, 4, 6, HQ_AMBER, 1)
	return hq_finish(&b)
}

build_hq_radar :: proc() -> rl.Model {
	b: HQ_Builder
	up := rl.Vector3{0, 1, 0}
	axis := rl.Vector3Normalize({1, 0.22, 0})
	hq_cyl(&b, -up * 0.06, up * 0.06, 0.13, 0.11, 10, HQ_GUNMETAL)
	hq_cyl(&b, up * 0.02, up * 0.02 + axis * 0.3, 0.04, 0.035, 6, HQ_STEEL)
	hq_cyl(&b, axis * 0.26, axis * 0.46, 0.06, 0.44, 16, HQ_STEEL_LIT)
	hq_cyl(&b, axis * 0.46, axis * 0.82, 0.016, 0.012, 4, HQ_STEEL)
	for k in 0..<3 {
		ang := f32(k) * (2.0 * math.PI / 3.0)
		rim := axis * 0.46 + rl.Vector3{0, math.cos(ang), math.sin(ang)} * 0.4
		hq_cyl(&b, rim, axis * 0.8, 0.008, 0.008, 3, HQ_STEEL)
	}
	hq_sphere(&b, axis * 0.84, 0.055, 4, 6, HQ_GLOW, 1)
	hq_box(&b, -axis * 0.18 + up * 0.02, 0.08, 0.06, 0.1, axis, up, {0, 0, 1}, HQ_GUNMETAL)
	return hq_finish(&b)
}

init_hq_visuals :: proc() {
	if hq_visuals_ready { return }
	hq_shader = rl.LoadShaderFromMemory(HQ_VS, HQ_FS)
	hq_shader_locs = HQ_Shader_Locs{
		light_dir = rl.GetShaderLocation(hq_shader, "lightDir"),
		view_pos  = rl.GetShaderLocation(hq_shader, "viewPos"),
		fog       = rl.GetShaderLocation(hq_shader, "fog"),
		wreck     = rl.GetShaderLocation(hq_shader, "wreck"),
		time      = rl.GetShaderLocation(hq_shader, "time"),
	}
	light := rl.Vector3Normalize(PLANET_LIGHT_DIR)
	rl.SetShaderValue(hq_shader, hq_shader_locs.light_dir, &light, .VEC3)
	hq_models[.HULL] = build_hq_hull(false)
	hq_models[.WRECK] = build_hq_hull(true)
	hq_models[.TURRET] = build_hq_turret()
	hq_models[.GUN] = build_hq_gun()
	hq_models[.RADAR] = build_hq_radar()
	hq_visuals_ready = true
}

unload_hq_visuals :: proc() {
	if !hq_visuals_ready { return }
	for part in HQ_Model_Part {
		hq_models[part].materials[0].shader = {}
		rl.UnloadModel(hq_models[part])
	}
	rl.UnloadShader(hq_shader)
	hq_visuals_ready = false
}

draw_hq_part :: proc(part: HQ_Model_Part, origin, x, y, z: rl.Vector3) {
	model := hq_models[part]
	model.transform = rl.Matrix{
		x.x, y.x, z.x, origin.x,
		x.y, y.y, z.y, origin.y,
		x.z, y.z, z.z, origin.z,
		0, 0, 0, 1,
	}
	rl.DrawModel(model, {0, 0, 0}, 1, rl.WHITE)
}

draw_hq_fortress :: proc(center: rl.Vector3) {
	destroyed := enemy_hq_destroyed()
	if !hq_visuals_ready {
		draw_low_poly_sphere(center, ENEMY_HQ_RADIUS * 0.6, destroyed ? rl.DARKGRAY : rl.MAROON)
		return
	}

	fog: f32 = (destroyed || has_vision(ENEMY_HOME)) ? 0 : 1
	wreck: f32 = destroyed ? 1 : 0
	t := laser_anim_time
	view := camera.position
	rl.SetShaderValue(hq_shader, hq_shader_locs.fog, &fog, .FLOAT)
	rl.SetShaderValue(hq_shader, hq_shader_locs.wreck, &wreck, .FLOAT)
	rl.SetShaderValue(hq_shader, hq_shader_locs.time, &t, .FLOAT)
	rl.SetShaderValue(hq_shader, hq_shader_locs.view_pos, &view, .VEC3)

	up := rl.Vector3{0, 1, 0}
	draw_hq_part(destroyed ? .WRECK : .HULL, center, {1, 0, 0}, up, {0, 0, 1})

	az, el := orbital_defense_aim(ENEMY_HOME)
	fwd := rl.Vector3{math.cos(az), 0, math.sin(az)}
	right := rl.Vector3{-math.sin(az), 0, math.cos(az)}
	barrel_dir := fwd * math.cos(el) + up * math.sin(el)
	barrel_nrm := -fwd * math.sin(el) + up * math.cos(el)
	pivot := center + HQ_BATTERY_PIVOT
	draw_hq_part(.TURRET, pivot, fwd, up, right)
	draw_hq_part(.GUN, pivot, barrel_dir, barrel_nrm, right)

	if destroyed { return }

	sweep := t * 1.8
	sweep_fwd := rl.Vector3{math.cos(sweep), 0, math.sin(sweep)}
	sweep_right := rl.Vector3{-math.sin(sweep), 0, math.cos(sweep)}
	hub := center + HQ_RADAR_HUB
	draw_hq_part(.RADAR, hub, sweep_fwd, up, sweep_right)
	beam_dir := rl.Vector3Normalize(sweep_fwd + up * 0.22)
	rl.DrawLine3D(hub + beam_dir * 0.84, hub + beam_dir * 3.8, rl.Fade(HQ_GLOW, 0.75))

	pulse_slow := 0.70 + 0.30 * math.sin(t * 3.0)
	pulse_fast := 0.60 + 0.40 * math.sin(t * 7.5)
	reactor := rl.Fade(HQ_GLOW, pulse_slow * 0.95)
	rl.DrawSphereEx(center - up * 2.5, 0.5 * pulse_slow + 0.12, 6, 10, reactor)
	draw_low_poly_sphere(center + HQ_SPIRE_TIP, 0.26 * pulse_fast + 0.12, rl.Fade(HQ_GLOW, 0.95))

	for d in 0..<4 {
		ang := f32(d) * (math.PI / 2.0) + math.PI / 4.0
		dir := rl.Vector3{math.cos(ang), 0, math.sin(ang)}
		tan := rl.Vector3{-dir.z, 0, dir.x}
		strobe_col := (d % 2 == 0) ? HQ_GLOW : HQ_AMBER
		strobe_p := (d % 2 == 0) ? pulse_fast : (1.0 - pulse_fast)
		tip := center + dir * (HQ_POD_RADIAL + 0.56) + up * 0.82
		draw_low_poly_sphere(tip + tan * 0.36, 0.065, rl.Fade(strobe_col, strobe_p))
		draw_low_poly_sphere(tip - tan * 0.36, 0.065, rl.Fade(strobe_col, 1.0 - strobe_p))
	}
}
