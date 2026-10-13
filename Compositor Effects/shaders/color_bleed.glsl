#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float bleed_strength;
	float samples;
	float bleed_saturation;
	float mode;
	float intensity;
	float original_saturation;
	float sat_threshold;
	float luma_threshold;
	float tint_r;
	float tint_g;
	float tint_b;
	float direction;
	float angle_deg;
	float weight_mode;
	float pad0;
	float pad1;
} params;

vec3 rgb2yuv(vec3 rgb) {
	float y =  0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
	float u = -0.147 * rgb.r - 0.289 * rgb.g + 0.436 * rgb.b;
	float v =  0.615 * rgb.r - 0.515 * rgb.g - 0.100 * rgb.b;
	return vec3(y, u, v);
}

vec3 yuv2rgb(vec3 yuv) {
	float r = yuv.x + 1.140 * yuv.z;
	float g = yuv.x - 0.395 * yuv.y - 0.581 * yuv.z;
	float b = yuv.x + 2.032 * yuv.y;
	return vec3(r, g, b);
}

vec3 adjust_saturation(vec3 rgb, float amt) {
	const vec3 W = vec3(0.2126, 0.7152, 0.0722);
	return mix(vec3(dot(rgb, W)), rgb, amt);
}

float sample_weight(int i, int count, float wmode) {
	float t = abs(float(i)) / float(count + 1);
	if (wmode < 0.5) {
		return max(1.0 - t, 0.0);
	} else if (wmode < 1.5) {
		return exp(-t * t * 5.0);
	} else {
		return exp(-t * 4.0);
	}
}

vec3 accumulate(vec2 uv, vec2 pixel_size, vec2 dir, int count) {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	float wmode = params.weight_mode;
	float strength = params.bleed_strength;

	for (int i = -count; i <= count; i++) {
		vec2 offset = dir * float(i) * strength * pixel_size;
		float w = sample_weight(i, count, wmode);
		sum += texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb * w;
		total += w;
	}

	return sum / max(total, 0.0001);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);

	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 pixel_size = (1.0 / vec2(size)) * (float(size.y) / 1080.0);
	vec2 uv = (vec2(pos) + 0.5) / vec2(size);

	vec3 original = texture(input_texture, uv).rgb;

	float luma = dot(original, vec3(0.2126, 0.7152, 0.0722));
	if (luma < params.luma_threshold) {
		imageStore(output_image, pos, vec4(original, 1.0));
		return;
	}

	vec3 base_col = original;
	if (params.original_saturation != 1.0) {
		base_col = adjust_saturation(base_col, params.original_saturation);
	}

	int sample_count = clamp(int(params.samples), 1, 32);

	vec2 dir_h = vec2(1.0, 0.0);
	vec2 dir_v = vec2(0.0, 1.0);
	float rad = params.angle_deg * (3.14159265 / 180.0);
	vec2 dir_a = vec2(cos(rad), sin(rad));

	vec3 blurred;
	int dir_mode = int(params.direction);

	if (dir_mode == 0) {
		blurred = accumulate(uv, pixel_size, dir_h, sample_count);
	} else if (dir_mode == 1) {
		blurred = accumulate(uv, pixel_size, dir_v, sample_count);
	} else if (dir_mode == 2) {
		vec3 bh = accumulate(uv, pixel_size, dir_h, sample_count);
		vec3 bv = accumulate(uv, pixel_size, dir_v, sample_count);
		blurred = (bh + bv) * 0.5;
	} else {
		blurred = accumulate(uv, pixel_size, dir_a, sample_count);
	}

	vec3 tint = vec3(params.tint_r, params.tint_g, params.tint_b);
	blurred *= tint;

	if (params.bleed_saturation != 1.0) {
		vec3 target_blur = adjust_saturation(blurred, params.bleed_saturation);
		float diff = distance(base_col, blurred);
		float t = (params.sat_threshold <= 0.001)
			? 1.0
			: smoothstep(params.sat_threshold, params.sat_threshold * 2.0 + 0.05, diff);
		blurred = mix(blurred, target_blur, t);
	}

	vec3 result = base_col;
	int blend_mode = int(params.mode);

	if (blend_mode == 0) {
		vec3 orig_yuv = rgb2yuv(base_col);
		vec3 blur_yuv = rgb2yuv(blurred);
		result = yuv2rgb(vec3(orig_yuv.x, mix(orig_yuv.yz, blur_yuv.yz, params.intensity)));
	} else if (blend_mode == 1) {
		result = mix(base_col, blurred, params.intensity);
	} else {
		result = base_col + blurred * params.intensity;
	}

	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
