#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float intensity;
	float aberration_spread;
	float wave_frequency;
	float time;
	float focus_x;
	float focus_y;
	float wave_speed;
	float falloff_radius;
	float falloff_sharpness;
	float luminance_boost;
	float harmonics;
	float harmonic_scale;
	float blend;
	float distortion_mode;
	float pad0;
	float pad1;
} params;

float radial_mask(float dist, float radius, float sharpness) {
	if (radius <= 0.0) return 1.0;
	float edge = radius * sharpness;
	return 1.0 - smoothstep(radius - edge, radius, dist);
}

float caustic_wave(float dist, float freq, float speed, float t, float harmonics_val, float hscale) {
	float w = sin(dist * freq - t * speed);
	float h2 = sin(dist * freq * harmonics_val - t * speed * 1.3) * hscale;
	float h3 = sin(dist * freq * harmonics_val * 2.1 - t * speed * 0.7) * hscale * 0.5;
	return w + h2 + h3;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);

	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 orig = texture(input_texture, uv).rgb;

	vec2 focus = vec2(params.focus_x, params.focus_y);
	vec2 d = uv - focus;

	float aspect = float(size.x) / float(size.y);
	vec2 d_aspect = d * vec2(aspect, 1.0);
	float dist = length(d_aspect);

	float wave = caustic_wave(dist, params.wave_frequency, params.wave_speed, params.time, params.harmonics, params.harmonic_scale);
	float ripple = wave * (params.intensity * 0.05);

	float mask = radial_mask(dist, params.falloff_radius, params.falloff_sharpness);
	ripple *= mask;

	vec2 radial_dir = (dist > 0.0001) ? (d / length(d)) : vec2(0.0);

	vec2 dir_r;
	vec2 dir_g;
	vec2 dir_b;

	if (params.distortion_mode > 0.5) {
		vec2 tangent = vec2(-radial_dir.y, radial_dir.x);
		dir_r = tangent;
		dir_g = tangent;
		dir_b = tangent;
	} else {
		dir_r = radial_dir;
		dir_g = radial_dir;
		dir_b = radial_dir;
	}

	float chroma = params.aberration_spread;
	vec2 uv_r = clamp(uv + dir_r * ripple, vec2(0.0), vec2(1.0));
	vec2 uv_g = clamp(uv + dir_g * ripple * (1.0 + chroma), vec2(0.0), vec2(1.0));
	vec2 uv_b = clamp(uv + dir_b * ripple * (1.0 + chroma * 2.0), vec2(0.0), vec2(1.0));

	float r = texture(input_texture, uv_r).r;
	float g = texture(input_texture, uv_g).g;
	float b = texture(input_texture, uv_b).b;

	float luma = dot(vec3(r, g, b), vec3(0.2126, 0.7152, 0.0722));
	vec3 distorted = vec3(r, g, b) + vec3(luma) * ripple * params.luminance_boost;

	vec3 result = mix(orig, distorted, params.blend);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
