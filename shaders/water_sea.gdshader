shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.42, 0.74, 0.70);
uniform vec3 deep : source_color = vec3(0.07, 0.32, 0.40);
uniform vec3 foam : source_color = vec3(0.78, 0.88, 0.82);
uniform vec3 island_origin = vec3(0.0);
uniform float shore_start = 360.0;
uniform float shore_band = 70.0;
uniform float wave_speed = 0.22;
uniform float calm = 0.0;

varying vec3 world_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octaves are per call: the sea covers the whole screen, so every octave is
// paid per pixel. Warp offsets and the faint detail layer don't need 5.
float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		p = m * p * 2.07 + vec2(11.2, 4.8);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = mix(TIME, 0.0, clamp(calm, 0.0, 1.0));
	vec2 p = world_pos.xz * 0.018;
	float h = fbm(p + vec2(t * wave_speed * 0.35, t * wave_speed * 0.12), 5);
	VERTEX.y += (h - 0.5) * mix(1.15, 0.0, clamp(calm, 0.0, 1.0));
}

void fragment() {
	float t = mix(TIME, 0.0, clamp(calm, 0.0, 1.0));
	vec2 p = world_pos.xz * 0.021;
	vec2 q = p + vec2(
		fbm(p + vec2(t * wave_speed, 0.0), 3),
		fbm(p + vec2(5.2, 1.3) - vec2(0.0, t * wave_speed * 0.7), 3)
	);
	float n = fbm(q * 1.6, 4);
	float n2 = fbm(q * 4.1 + vec2(t * 0.08, -t * 0.05), 3);
	float d = length(world_pos.xz - island_origin.xz);
	float deep_f = smoothstep(shore_start * 0.55, shore_start + 920.0, d);
	float shore = 1.0 - smoothstep(shore_start, shore_start + shore_band, d);
	shore *= smoothstep(shore_start - 22.0, shore_start + 8.0, d);
	vec3 col = mix(shallow, deep, deep_f);
	col += (n - 0.5) * 0.10;
	col += (n2 - 0.5) * 0.045;
	col = mix(col, foam, shore * 0.18 * n);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	col = mix(col, vec3(0.72, 0.86, 0.84), fres * 0.28);
	ALBEDO = col;
	ROUGHNESS = mix(0.18, 0.06, deep_f + fres * 0.35);
	METALLIC = 0.04;
	SPECULAR = 0.85;
	EMISSION = col * fres * 0.06;
}
