shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wave_speed = 0.18;
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
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = mix(TIME, 0.0, clamp(calm, 0.0, 1.0));
	vec3 paint = texture(albedo_tex, UV).rgb;
	vec2 p = world_pos.xz * 0.08 + vec2(t * wave_speed * 0.15, -t * wave_speed * 0.09);
	float n = vnoise(p) * 0.55 + vnoise(p * 2.3 + 7.1) * 0.45;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	vec3 col = paint + (n - 0.5) * 0.08;
	col = mix(col, vec3(0.78, 0.90, 0.88), fres * 0.22);
	ALBEDO = col;
	ROUGHNESS = mix(0.14, 0.06, fres);
	METALLIC = 0.05;
	SPECULAR = 0.88;
	EMISSION = col * fres * 0.05;
}
