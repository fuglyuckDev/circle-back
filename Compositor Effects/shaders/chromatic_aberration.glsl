#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float samples;
	float red_offset;
	float green_offset;
	float blue_offset;
	float falloff_power;
	float barrel_distortion;
	float center_x;
	float center_y;
	float lateral_mode;
	float lateral_angle;
	float inner_radius;
	float fringe_r;
	float fringe_g;
	float fringe_b;
	float pad0;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);

	vec2 center = vec2(params.center_x, params.center_y);
	vec2 delta = uv - center;

	float dist = length(delta);
	vec2 radial_dir = (dist > 0.00001) ? normalize(delta) : vec2(0.0);

	float inner = clamp(params.inner_radius, 0.0, 0.9999);
	float radial_t = max(dist - inner, 0.0) / max(1.0 - inner, 0.0001);
	float falloff = pow(radial_t * 2.0, params.falloff_power);
	float barrel = 1.0 + params.barrel_distortion * dist * dist;
	float base_offset = params.strength * falloff * barrel * 0.002;

	vec2 dir;
	if (params.lateral_mode > 0.5) {
		float rad = params.lateral_angle * (3.14159265 / 180.0);
		dir = vec2(cos(rad), sin(rad));
	} else {
		dir = radial_dir;
	}

	float r_off = base_offset * params.red_offset;
	float g_off = base_offset * params.green_offset;
	float b_off = base_offset * params.blue_offset;

	int sample_count = clamp(int(params.samples), 1, 32);
	float inv_samples = 1.0 / float(sample_count);

	float r_accum = 0.0;
	float g_accum = 0.0;
	float b_accum = 0.0;

	for (int i = 0; i < sample_count; i++) {
		float t = (float(i) + 0.5) * inv_samples;
		vec2 r_uv = clamp(uv + dir * r_off * t, vec2(0.0), vec2(1.0));
		vec2 g_uv = clamp(uv + dir * g_off * t, vec2(0.0), vec2(1.0));
		vec2 b_uv = clamp(uv + dir * b_off * t, vec2(0.0), vec2(1.0));

		r_accum += texture(input_texture, r_uv).r;
		g_accum += texture(input_texture, g_uv).g;
		b_accum += texture(input_texture, b_uv).b;
	}

	r_accum *= inv_samples;
	g_accum *= inv_samples;
	b_accum *= inv_samples;

	vec3 fringe = vec3(params.fringe_r, params.fringe_g, params.fringe_b);
	vec3 result = vec3(r_accum, g_accum, b_accum) * fringe;

	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
