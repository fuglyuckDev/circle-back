#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float monitor_type;
	float phosphor_scale;
	float phosphor_power;
	float electron_convergence_x;
	float electron_convergence_y;
	float scanline_depth;
	float scanline_count;
	float scanline_interlaced;
	float rf_noise_static;
	float rf_noise_roll;
	float rf_color_bleed;
	float luma_halation;
	float vignette_strength;
	float corner_roundness;
	float brightness_boost;
	float time;
} params;

float rand(vec2 n) {
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 read_ntsc_composite(vec2 uv, vec2 img_res) {
	float spread = params.rf_color_bleed / img_res.x;

	vec2 conv_offset_r = vec2(params.electron_convergence_x, params.electron_convergence_y) / img_res;
	vec2 conv_offset_b = vec2(-params.electron_convergence_x, -params.electron_convergence_y) / img_res;

	vec2 uv_r = clamp(uv + conv_offset_r, vec2(0.0), vec2(1.0));
	vec2 uv_g = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 uv_b = clamp(uv + conv_offset_b, vec2(0.0), vec2(1.0));

	vec2 smear_left = vec2(-spread, 0.0);
	vec2 smear_right = vec2(spread, 0.0);

	vec3 center = vec3(
		texture(input_texture, uv_r).r,
		texture(input_texture, uv_g).g,
		texture(input_texture, uv_b).b
	);

	if (params.rf_color_bleed < 0.001) return center;

	vec3 left = vec3(
		texture(input_texture, clamp(uv_r + smear_left, vec2(0.0), vec2(1.0))).r,
		texture(input_texture, clamp(uv_g + smear_left, vec2(0.0), vec2(1.0))).g,
		texture(input_texture, clamp(uv_b + smear_left, vec2(0.0), vec2(1.0))).b
	);

	vec3 right = vec3(
		texture(input_texture, clamp(uv_r + smear_right, vec2(0.0), vec2(1.0))).r,
		texture(input_texture, clamp(uv_g + smear_right, vec2(0.0), vec2(1.0))).g,
		texture(input_texture, clamp(uv_b + smear_right, vec2(0.0), vec2(1.0))).b
	);

	float l_center = luma(center);
	vec3 chroma_blur = (left + center + right) / 3.0;
	float blur_luma = luma(chroma_blur);

	vec3 result = chroma_blur * (l_center / max(blur_luma, 0.001));
	return max(vec3(0.0), result);
}

vec3 get_phosphor_mask(vec2 coord) {
	int type = int(params.monitor_type);
	vec3 mask = vec3(1.0);

	vec2 p_coord = floor(coord / max(params.phosphor_scale, 0.1));

	if (type == 0) {
		int m = int(mod(p_coord.x, 3.0));
		mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
	} else if (type == 1) {
		int x = int(mod(p_coord.x, 3.0));
		int y = int(mod(p_coord.y, 2.0));
		int m = int(mod(float(x) + (y == 1 ? 1.5 : 0.0), 3.0));
		mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
	} else if (type == 2) {
		int y = int(mod(p_coord.y, 4.0));
		float offset = (y == 2 || y == 3) ? 1.5 : 0.0;
		int m = int(mod(p_coord.x + offset, 3.0));
		mask = m == 0 ? vec3(1.0, 0.0, 0.0) : (m == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
		if (mod(p_coord.x, 3.0) < 0.5 && mod(p_coord.y, 2.0) > 0.5) mask *= 0.5;
	} else if (type == 3) {
		float lum = mod(p_coord.x + p_coord.y, 2.0);
		mask = lum > 0.5 ? vec3(0.1, 1.0, 0.2) : vec3(0.02, 0.2, 0.04);
	} else if (type == 4) {
		int x = int(mod(p_coord.x, 3.0));
		int y = int(mod(p_coord.y, 3.0));
		mask = x == 0 ? vec3(1.0, 0.1, 0.1) : (x == 1 ? vec3(0.1, 1.0, 0.1) : vec3(0.1, 0.1, 1.0));
		if (y == 0) mask *= 0.5;
	}

	mask = pow(mask, vec3(params.phosphor_power));
	return mask;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 mapped_uv = uv;

	if (params.rf_noise_roll > 0.0) {
		float roll = sin(uv.y * 12.0 - params.time * 4.0) * cos(uv.y * 50.0 + params.time * 2.0);
		mapped_uv.x += roll * params.rf_noise_roll * 0.005;
	}

	if (params.rf_noise_static > 0.0) {
		float snow = rand(uv + vec2(params.time * 0.1)) * 2.0 - 1.0;
		mapped_uv.x += snow * params.rf_noise_static * 0.002;
	}

	vec3 color = read_ntsc_composite(mapped_uv, vec2(size));
	color *= params.brightness_boost;

	if (params.scanline_depth > 0.0) {
		float lines = max(params.scanline_count, 120.0);
		float time_shift = params.scanline_interlaced > 0.5 ? params.time * 60.0 : 0.0;
		float line_wave = sin(mapped_uv.y * lines * 3.14159 + time_shift);
		float line_dim = clamp(line_wave * 0.5 + 0.5, 0.0, 1.0);
		color *= mix(1.0, line_dim, params.scanline_depth);
	}

	vec3 mask = get_phosphor_mask(vec2(pos));
	color *= mask;

	if (params.luma_halation > 0.0) {
		float l = luma(color);
		color = mix(color, color * 1.5, l * params.luma_halation);
	}

	if (params.corner_roundness > 0.0) {
		vec2 corner = abs(uv * 2.0 - 1.0);
		float len = length(max(corner - vec2(1.0 - params.corner_roundness), 0.0));
		float bezel = 1.0 - smoothstep(0.0, 0.01, len - params.corner_roundness);
		color *= bezel;
	}

	if (params.vignette_strength > 0.0) {
		vec2 corner = abs(uv * 2.0 - 1.0);
		float v = 1.0 - pow(max(corner.x, corner.y), 4.0) * params.vignette_strength;
		color *= clamp(v, 0.0, 1.0);
	}

	imageStore(output_image, pos, vec4(clamp(color, 0.0, 1.0), 1.0));
}
