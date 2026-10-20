package main

import "core:c"
import "core:math"
import "core:math/noise"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

SYSTEM_CENTER     :: rl.Vector3{10, 0, 2}
PLANET_LIGHT_DIR  :: rl.Vector3{-0.62, 0.50, 0.60}
PLANET_LABEL_SIZE :: 14
PLANET_LABEL_GAP  :: 6
PLANET_LABEL_H    :: 18
HALO_TEX_SIZE     :: 128
HALO_SPAN         :: 1.7
NEBULA_TEX_SIZE   :: 256

planet_atmospheres := [PLANET_COUNT]rl.Color{
	{170, 165, 160, 90},
	{255, 215, 150, 200},
	{110, 185, 255, 255},
	{255, 150, 110, 120},
	{255, 220, 170, 170},
	{255, 230, 180, 160},
	{150, 240, 255, 220},
	{100, 150, 255, 230},
}

Planet_Shader_Locs :: struct {
	kind, light_dir, view_pos, rim, time, fog: c.int,
}

Ambient_Nebula :: struct {
	position: rl.Vector3,
	size:     f32,
	rotation: f32,
	tint:     rl.Color,
	texture:  int,
}

ambient_nebulae := [?]Ambient_Nebula{
	{position = {-78, -60, -58}, size = 46, rotation = 20, tint = {120, 70, 255, 92}, texture = 0},
	{position = {-66, -60, -70}, size = 30, rotation = 140, tint = {70, 140, 255, 84}, texture = 1},
	{position = {96, -60, -76}, size = 50, rotation = 75, tint = {40, 190, 160, 64}, texture = 1},
	{position = {30, -60, 84}, size = 40, rotation = 310, tint = {190, 80, 220, 56}, texture = 2},
	{position = {-84, -60, 74}, size = 34, rotation = 250, tint = {50, 150, 230, 56}, texture = 2},
}

planet_shader: rl.Shader
planet_shader_locs: Planet_Shader_Locs
planet_halo_texture: rl.Texture2D
nebula_textures: [3]rl.Texture2D
saturn_ring_model: rl.Model

PLANET_VS :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;
out vec3 fragObjNormal;
out vec3 fragNormal;
out vec3 fragPos;
void main() {
	fragObjNormal = vertexNormal;
	fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
	fragPos = vec3(matModel * vec4(vertexPosition, 1.0));
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

PLANET_FS :: `#version 330
in vec3 fragObjNormal;
in vec3 fragNormal;
in vec3 fragPos;
uniform vec4 colDiffuse;
uniform int planetKind;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform vec4 rimColor;
uniform float time;
uniform float fog;
out vec4 finalColor;

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;
	i = mod289(i);
	vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0)) + i.y + vec4(0.0, i1.y, i2.y, 1.0)) + i.x + vec4(0.0, i1.x, i2.x, 1.0));
	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float fbm(vec3 p, int octaves) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;
		sum += amp * snoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum;
}

vec3 ramp3(vec3 a, vec3 b, vec3 c, float t) {
	t = clamp(t, 0.0, 1.0);
	return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}

float storm(vec3 p, float lon0, float lat0, float w, float h) {
	float lat = asin(clamp(p.z, -1.0, 1.0));
	float lon = atan(p.y, p.x);
	float dl = lon - lon0;
	dl = dl - 6.2831853 * floor((dl + 3.14159265) / 6.2831853);
	float e = pow(dl * cos(lat) / w, 2.0) + pow((lat - lat0) / h, 2.0);
	return e;
}

vec4 gas_giant(vec3 p, float freq, float turb, vec3 a, vec3 b, vec3 c) {
	vec3 q = p * vec3(1.6, 1.6, 4.5) + vec3(time * 0.01, 0.0, 0.0);
	float warp = fbm(q, 5);
	float t = p.z * freq + warp * turb;
	float band = 0.5 + 0.5 * sin(t * 3.14159265);
	float fine = 0.5 + 0.5 * sin(t * 7.3 + fbm(p * 6.0, 3) * 1.5);
	vec3 col = ramp3(c, b, a, band * 0.75 + fine * 0.25);
	col *= 0.92 + 0.16 * fbm(p * vec3(3.0, 3.0, 12.0), 3);
	return vec4(col, 0.0);
}

vec4 surface(vec3 p) {
	float lat = p.z;
	if (planetKind == 0) {
		float n = fbm(p * 3.2, 6);
		float m = fbm(p * 1.3 + 4.0, 4);
		vec3 col = mix(vec3(0.30, 0.28, 0.26), vec3(0.70, 0.66, 0.60), 0.5 + 0.5 * n);
		col = mix(col, vec3(0.20, 0.19, 0.18), smoothstep(0.0, 0.35, m) * 0.6);
		float rim = 1.0 - abs(snoise(p * 6.5));
		col += vec3(0.10) * smoothstep(0.88, 0.99, rim);
		col -= vec3(0.06) * smoothstep(0.75, 0.88, 1.0 - abs(snoise(p * 13.0)));
		return vec4(col, 0.0);
	}
	if (planetKind == 1) {
		vec3 w = vec3(fbm(p * 1.6, 4), fbm(p * 1.6 + 5.2, 4), fbm(p * 1.6 + 9.7, 4));
		vec3 q = p + 0.6 * w;
		float b = fbm(vec3(q.x * 1.6, q.y * 1.6, q.z * 5.0) + vec3(time * 0.012, 0.0, 0.0), 5);
		vec3 col = mix(vec3(0.74, 0.50, 0.24), vec3(0.98, 0.86, 0.60), smoothstep(-0.5, 0.5, b));
		col = mix(col, vec3(1.0, 0.95, 0.84), smoothstep(0.3, 0.8, b) * 0.6);
		return vec4(col, 0.0);
	}
	if (planetKind == 2) {
		float h = fbm(p * 1.7 + vec3(3.1, 1.2, 7.4), 7);
		float coast = 0.03;
		vec3 col;
		float spec;
		if (h < coast) {
			col = mix(vec3(0.015, 0.06, 0.22), vec3(0.05, 0.30, 0.55), smoothstep(-0.35, coast, h));
			spec = 1.0;
		} else {
			float moist = fbm(p * 3.3 + 11.0, 5);
			float elev = smoothstep(coast, 0.45, h);
			col = mix(vec3(0.12, 0.30, 0.10), vec3(0.55, 0.47, 0.29), smoothstep(-0.15, 0.35, moist));
			col = mix(col, vec3(0.45, 0.40, 0.35), elev * 0.6);
			col = mix(vec3(0.70, 0.66, 0.50), col, smoothstep(coast, coast + 0.03, h));
			spec = 0.0;
		}
		float ice = smoothstep(0.78, 0.86, abs(lat) + 0.06 * fbm(p * 4.0, 3));
		col = mix(col, vec3(0.92, 0.95, 1.0), ice);
		spec *= 1.0 - ice;
		float cl = fbm(p * 2.3 + vec3(time * 0.02, 0.0, time * 0.01), 6);
		float cloud = smoothstep(0.02, 0.5, cl);
		col = mix(col, vec3(0.97, 0.98, 1.0), cloud * 0.9);
		spec *= 1.0 - cloud;
		return vec4(col, spec);
	}
	if (planetKind == 3) {
		float n = fbm(p * 2.2, 6);
		float d = fbm(p * 1.2 + 20.0, 4);
		vec3 col = mix(vec3(0.52, 0.20, 0.10), vec3(0.86, 0.48, 0.27), 0.5 + 0.5 * n);
		col = mix(col, vec3(0.28, 0.12, 0.07), smoothstep(0.05, 0.4, d) * 0.7);
		float ice = smoothstep(0.86, 0.92, abs(lat) + 0.04 * n);
		col = mix(col, vec3(0.96, 0.93, 0.90), ice);
		return vec4(col, 0.0);
	}
	if (planetKind == 4) {
		vec4 s = gas_giant(p, 9.0, 0.9, vec3(0.96, 0.90, 0.78), vec3(0.82, 0.60, 0.42), vec3(0.52, 0.32, 0.20));
		float e = storm(p, 1.1, -0.38, 0.30, 0.13);
		float core = 1.0 - smoothstep(0.35, 1.0, e);
		float swirl = smoothstep(0.7, 1.0, e) * (1.0 - smoothstep(1.0, 1.5, e));
		s.rgb = mix(s.rgb, vec3(0.78, 0.33, 0.18), core * 0.85);
		s.rgb = mix(s.rgb, vec3(0.98, 0.92, 0.82), swirl * 0.5);
		return s;
	}
	if (planetKind == 5) {
		return gas_giant(p, 7.0, 0.35, vec3(0.97, 0.91, 0.74), vec3(0.88, 0.76, 0.54), vec3(0.70, 0.56, 0.36));
	}
	if (planetKind == 6) {
		vec4 s = gas_giant(p, 4.0, 0.15, vec3(0.78, 0.95, 0.96), vec3(0.62, 0.87, 0.91), vec3(0.50, 0.78, 0.86));
		s.rgb = mix(s.rgb, vec3(0.85, 0.97, 0.98), smoothstep(0.6, 0.95, abs(lat)) * 0.5);
		return s;
	}
	vec4 s = gas_giant(p, 6.0, 0.5, vec3(0.34, 0.52, 0.95), vec3(0.18, 0.33, 0.82), vec3(0.08, 0.17, 0.55));
	float e = storm(p, -0.9, -0.35, 0.25, 0.12);
	s.rgb = mix(s.rgb, vec3(0.05, 0.10, 0.35), (1.0 - smoothstep(0.4, 1.0, e)) * 0.8);
	float streak = smoothstep(0.45, 0.75, fbm(p * vec3(1.8, 1.8, 10.0) + 7.0, 4));
	s.rgb = mix(s.rgb, vec3(0.92, 0.96, 1.0), streak * 0.55);
	return s;
}

void main() {
	vec3 p = normalize(fragObjNormal);
	vec4 s = surface(p);
	vec3 N = normalize(fragNormal);
	vec3 L = normalize(lightDir);
	vec3 V = normalize(viewPos - fragPos);
	float ndl = dot(N, L);
	float diff = smoothstep(-0.18, 0.95, ndl);
	vec3 col = s.rgb * (0.06 + 1.12 * diff);
	vec3 H = normalize(L + V);
	col += vec3(1.0, 0.97, 0.90) * pow(max(dot(N, H), 0.0), 48.0) * 0.6 * s.a * step(0.0, ndl);
	float fres = pow(1.0 - max(dot(N, V), 0.0), 2.4);
	col += rimColor.rgb * fres * rimColor.a * (0.18 + 1.0 * smoothstep(-0.35, 0.6, ndl));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, mix(col, vec3(lum) * vec3(0.62, 0.68, 0.76), 0.72) * 0.78, fog);
	finalColor = vec4(col * colDiffuse.rgb, 1.0);
}
`

init_planet_visuals :: proc() {
	if planet_visuals_ready { return }
	planet_shader = rl.LoadShaderFromMemory(PLANET_VS, PLANET_FS)
	planet_shader_locs = Planet_Shader_Locs{
		kind      = rl.GetShaderLocation(planet_shader, "planetKind"),
		light_dir = rl.GetShaderLocation(planet_shader, "lightDir"),
		view_pos  = rl.GetShaderLocation(planet_shader, "viewPos"),
		rim       = rl.GetShaderLocation(planet_shader, "rimColor"),
		time      = rl.GetShaderLocation(planet_shader, "time"),
		fog       = rl.GetShaderLocation(planet_shader, "fog"),
	}
	light := rl.Vector3Normalize(PLANET_LIGHT_DIR)
	rl.SetShaderValue(planet_shader, planet_shader_locs.light_dir, &light, .VEC3)

	for p in 0..<PLANET_COUNT {
		model := rl.LoadModelFromMesh(rl.GenMeshSphere(planets[p].radius, 48, 48))
		model.transform = rl.MatrixRotateX(rl.DEG2RAD * -90)
		model.materials[0].shader = planet_shader
		planet_models[p] = model
	}

	planet_halo_texture = bake_halo_texture()
	for i in 0..<len(nebula_textures) {
		nebula_textures[i] = bake_nebula_texture(i64(i * 7919 + 17))
	}
	saturn_ring_model = build_saturn_ring_model()
	planet_visuals_ready = true
}

unload_planet_visuals :: proc() {
	if !planet_visuals_ready { return }
	for p in 0..<PLANET_COUNT {
		planet_models[p].materials[0].shader = {}
		rl.UnloadModel(planet_models[p])
	}
	rl.UnloadShader(planet_shader)
	rl.UnloadTexture(planet_halo_texture)
	for t in nebula_textures { rl.UnloadTexture(t) }
	rl.UnloadModel(saturn_ring_model)
	planet_visuals_ready = false
}

bake_halo_texture :: proc() -> rl.Texture2D {
	img := rl.GenImageColor(HALO_TEX_SIZE, HALO_TEX_SIZE, rl.BLANK)
	half := f32(HALO_TEX_SIZE) / 2
	edge := 1.0 / f32(HALO_SPAN)
	for y in 0..<HALO_TEX_SIZE {
		for x in 0..<HALO_TEX_SIZE {
			dx := (f32(x) + 0.5 - half) / half
			dy := (f32(y) + 0.5 - half) / half
			d := math.sqrt(dx * dx + dy * dy)
			a: f32 = 0
			if d <= edge {
				a = 1
			} else if d < 1 {
				t := (d - edge) / (1 - edge)
				a = math.pow(1 - t, 2.6)
			}
			rl.ImageDrawPixel(&img, c.int(x), c.int(y), {255, 255, 255, u8(a * 255)})
		}
	}
	tex := rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(tex, .BILINEAR)
	rl.UnloadImage(img)
	return tex
}

nebula_fbm :: proc(seed: i64, x, y: f32, octaves: int) -> f32 {
	sum: f32 = 0
	amp: f32 = 0.5
	fx, fy := x, y
	for _ in 0..<octaves {
		sum += amp * noise.noise_2d(seed, {f64(fx), f64(fy)})
		fx = fx * 2.07 + 13.1
		fy = fy * 2.07 + 7.7
		amp *= 0.5
	}
	return sum
}

bake_nebula_texture :: proc(seed: i64) -> rl.Texture2D {
	img := rl.GenImageColor(NEBULA_TEX_SIZE, NEBULA_TEX_SIZE, rl.BLANK)
	half := f32(NEBULA_TEX_SIZE) / 2
	for y in 0..<NEBULA_TEX_SIZE {
		for x in 0..<NEBULA_TEX_SIZE {
			u := (f32(x) - half) / half
			v := (f32(y) - half) / half
			wx := nebula_fbm(seed + 1, u * 1.4, v * 1.4, 3)
			wy := nebula_fbm(seed + 2, u * 1.4 + 3.3, v * 1.4 - 1.7, 3)
			n := nebula_fbm(seed, u * 2.2 + wx * 1.2, v * 2.2 + wy * 1.2, 6)
			d := math.sqrt(u * u + v * v)
			falloff := clamp(1 - d, 0, 1)
			falloff = falloff * falloff * (3 - 2 * falloff)
			density := clamp(0.5 + n * 1.1, 0, 1)
			density = density * density * falloff
			wisps := clamp(1 - abs(n) * 4, 0, 1)
			a := clamp(density * 0.9 + wisps * falloff * 0.35, 0, 1)
			rl.ImageDrawPixel(&img, c.int(x), c.int(y), {255, 255, 255, u8(a * 255)})
		}
	}
	tex := rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(tex, .BILINEAR)
	rl.UnloadImage(img)
	return tex
}

build_saturn_ring_model :: proc() -> rl.Model {
	verts := make([dynamic]f32)
	defer delete(verts)
	norms := make([dynamic]f32)
	defer delete(norms)
	cols := make([dynamic]u8)
	defer delete(cols)

	r := planets[SATURN].radius
	inner := r * 1.35
	outer := r * 2.25
	bands :: 36
	segments :: 120
	up := rl.Vector3Normalize({0.35, 1, 0.15})
	ax := rl.Vector3Normalize(rl.Vector3CrossProduct(up, {0, 0, 1}))
	az := rl.Vector3CrossProduct(ax, up)
	for b in 0..<bands {
		t0 := f32(b) / bands
		t1 := f32(b + 1) / bands
		r0 := inner + (outer - inner) * t0
		r1 := inner + (outer - inner) * t1
		tm := (t0 + t1) * 0.5
		density := 0.55 + 0.45 * math.sin(tm * 41.0) * math.sin(tm * 13.0 + 1.3)
		if tm > 0.62 && tm < 0.68 { density *= 0.12 }
		density *= math.smoothstep(f32(0), f32(0.08), tm) * (1 - math.smoothstep(f32(0.9), f32(1), tm))
		shade := 0.75 + 0.25 * math.sin(tm * 23.0)
		col := rl.Color{u8(232 * shade), u8(212 * shade), u8(168 * shade), u8(clamp(density, 0, 1) * 170)}
		for s in 0..<segments {
			a0 := f32(s) / segments * 2 * math.PI
			a1 := f32(s + 1) / segments * 2 * math.PI
			d0 := ax * math.cos(a0) + az * math.sin(a0)
			d1 := ax * math.cos(a1) + az * math.sin(a1)
			p00 := d0 * r0
			p01 := d1 * r0
			p10 := d0 * r1
			p11 := d1 * r1
			add_triangle(&verts, &norms, &cols, p00, p10, p01, col)
			add_triangle(&verts, &norms, &cols, p01, p10, p11, col)
			add_triangle(&verts, &norms, &cols, p00, p01, p10, col)
			add_triangle(&verts, &norms, &cols, p01, p11, p10, col)
		}
	}
	return rl.LoadModelFromMesh(make_mesh_from_arrays(verts[:], norms[:], cols[:]))
}

planet_screen_radius :: proc(p: int) -> f32 {
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	center := rl.GetWorldToScreen(planets[p].position, camera)
	limb := rl.GetWorldToScreen(planets[p].position + cam_right * planets[p].radius, camera)
	return rl.Vector2Distance(center, limb)
}

planet_reticle_radius :: proc(screen_r: f32) -> f32 {
	return screen_r * 1.28 + 7
}

planet_label_y :: proc(center_y, screen_r: f32, selected: bool) -> f32 {
	r := selected ? planet_reticle_radius(screen_r) + 4 : screen_r * 1.12
	return center_y + r + PLANET_LABEL_GAP
}

planet_in_front :: proc(pos: rl.Vector3) -> bool {
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	return rl.Vector3DotProduct(pos - camera.position, cam_forward) > 0.1
}

draw_ambient_nebulae :: proc() {
	if !planet_visuals_ready { return }
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	for n in ambient_nebulae {
		if !planet_in_front(n.position) { continue }
		center := rl.GetWorldToScreen(n.position, camera)
		edge := rl.GetWorldToScreen(n.position + cam_right * n.size, camera)
		r := rl.Vector2Distance(center, edge)
		if r < 4 { continue }
		tex := nebula_textures[n.texture]
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{center.x, center.y, r * 2, r * 2}
		rl.DrawTexturePro(tex, src, dst, {r, r}, n.rotation, n.tint)
		core := rl.Color{n.tint.r, n.tint.g, n.tint.b, n.tint.a / 2}
		rl.DrawTexturePro(tex, src, {center.x, center.y, r * 1.1, r * 1.1}, {r * 0.55, r * 0.55}, n.rotation + 90, core)
	}
}

draw_planet_halos :: proc() {
	if !planet_visuals_ready { return }
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()
	src := rl.Rectangle{0, 0, f32(planet_halo_texture.width), f32(planet_halo_texture.height)}
	for p in 0..<PLANET_COUNT {
		if !planet_in_front(planets[p].position) { continue }
		center := rl.GetWorldToScreen(planets[p].position, camera)
		r := planet_screen_radius(p) * HALO_SPAN
		tint := planet_atmospheres[p]
		strength := f32(tint.a) / 255 * 0.75
		if !has_vision(p) {
			tint = {120, 130, 150, 255}
			strength *= 0.45
		}
		rl.DrawTexturePro(planet_halo_texture, src, {center.x - r, center.y - r, r * 2, r * 2}, {}, 0, rl.Fade(tint, strength))
	}
}

draw_orbit_rings :: proc() {
	for p in 0..<PLANET_COUNT {
		pos := planets[p].position
		center := rl.Vector3{SYSTEM_CENTER.x, pos.y, SYSTEM_CENTER.z}
		dist := rl.Vector2Length({pos.x - center.x, pos.z - center.z})
		if dist < 1 { continue }
		rl.DrawCircle3D(center, dist, {1, 0, 0}, 90, rl.Color{50, 210, 160, 34})
	}
}

draw_planet_body :: proc(p: int) {
	planet := planets[p]
	lit := has_vision(p)
	if !planet_visuals_ready {
		rl.DrawSphere(planet.position, planet.radius, lit ? planet.color : rl.Color{58, 62, 74, 255})
		return
	}
	kind := c.int(p)
	fog: f32 = lit ? 0 : 1
	atmo := planet_atmospheres[p]
	rim := [4]f32{f32(atmo.r) / 255, f32(atmo.g) / 255, f32(atmo.b) / 255, f32(atmo.a) / 255}
	view := camera.position
	t := laser_anim_time
	rl.SetShaderValue(planet_shader, planet_shader_locs.kind, &kind, .INT)
	rl.SetShaderValue(planet_shader, planet_shader_locs.fog, &fog, .FLOAT)
	rl.SetShaderValue(planet_shader, planet_shader_locs.rim, &rim, .VEC4)
	rl.SetShaderValue(planet_shader, planet_shader_locs.view_pos, &view, .VEC3)
	rl.SetShaderValue(planet_shader, planet_shader_locs.time, &t, .FLOAT)
	rl.DrawModelEx(planet_models[p], planet.position, {0, 1, 0}, planet_spin[p] * 57.29578, {1, 1, 1}, rl.WHITE)

	if p == SATURN {
		tint := lit ? rl.WHITE : rl.Color{110, 116, 130, 255}
		rlgl.DrawRenderBatchActive()
		rlgl.DisableBackfaceCulling()
		rlgl.DisableDepthMask()
		rl.DrawModel(saturn_ring_model, planet.position, 1, tint)
		rlgl.DrawRenderBatchActive()
		rlgl.EnableDepthMask()
		rlgl.EnableBackfaceCulling()
	}
}

draw_planet_reticle :: proc(center: rl.Vector2, screen_r: f32, color: rl.Color) {
	r := planet_reticle_radius(screen_r)
	pulse := 0.85 + 0.15 * math.sin(laser_anim_time * 3.0)
	arcs := [3][2]f32{{232, 308}, {-28, 68}, {112, 208}}
	for a in arcs {
		rl.DrawRing(center, r - 6, r + 6, a[0] - 2, a[1] + 2, 32, rl.Fade(color, 0.10 * pulse))
		rl.DrawRing(center, r - 3.5, r + 3.5, a[0] - 1, a[1] + 1, 32, rl.Fade(color, 0.22 * pulse))
		rl.DrawRing(center, r - 1.6, r + 1.6, a[0], a[1], 32, rl.Fade(color, pulse))
		rl.DrawRing(center, r - 0.6, r + 0.6, a[0] + 2, a[1] - 2, 32, rl.Fade(rl.WHITE, 0.55 * pulse))
	}
}

draw_planet_label :: proc(label: cstring, center_x, y: f32, color: rl.Color) {
	w := measure_display_text(label, PLANET_LABEL_SIZE)
	draw_display_text_shadowed(label, {center_x - w / 2, y}, PLANET_LABEL_SIZE, color, rl.Color{0, 0, 0, 200})
}

draw_planet_labels :: proc(viewport_w: f32) {
	screen_h := f32(rl.GetScreenHeight())
	for p in 0..<PLANET_COUNT {
		if !planet_in_front(planets[p].position) { continue }
		pos := rl.GetWorldToScreen(planets[p].position, camera)
		if !(pos.x > 0 && pos.x < viewport_w && pos.y > 0 && pos.y < screen_h) { continue }
		screen_r := planet_screen_radius(p)
		selected := p == selected_planet
		if selected {
			draw_planet_reticle(pos, screen_r, SCIFI_CYAN)
		}
		color := SCIFI_LABEL
		if selected {
			color = SCIFI_GREEN
		} else if !has_vision(p) {
			color = rl.Color{48, 140, 98, 255}
		}
		draw_planet_label(planets[p].name, pos.x, planet_label_y(pos.y, screen_r, selected), color)
	}

	if !planet_in_front(ENEMY_HQ_POSITION) { return }
	hq := rl.GetWorldToScreen(ENEMY_HQ_POSITION, camera)
	if !(hq.x > 0 && hq.x < viewport_w && hq.y > 0 && hq.y < screen_h) { return }
	cam_forward := rl.Vector3Normalize(camera.target - camera.position)
	cam_right := rl.Vector3Normalize(rl.Vector3CrossProduct(cam_forward, camera.up))
	hq_r := rl.Vector2Distance(hq, rl.GetWorldToScreen(ENEMY_HQ_POSITION + cam_right * ENEMY_HQ_RADIUS, camera))
	selected := selected_planet == ENEMY_HOME
	if selected {
		draw_planet_reticle(hq, hq_r, SCIFI_RED)
	}
	label: cstring = enemy_hq_destroyed() ? "ENEMY HQ - DESTROYED" : "ENEMY HQ"
	draw_planet_label(label, hq.x, planet_label_y(hq.y, hq_r, selected), SCIFI_RED)
}
