#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float target_hue;
	float hue_range;
	float falloff;
	float desat_amount;
	float invert_mask;
	float strength;
	float hue_shift;
	float sat_adjust;
	float val_adjust;
	float tint_r;
	float tint_g;
	float tint_b;
	float desat_luma_mode;
	float min_saturation;
	float pad0;
	float pad1;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float rgb_hue(vec3 c) {
	float maxc = max(c.r, max(c.g, c.b));
	float minc = min(c.r, min(c.g, c.b));
	if (maxc - minc < 0.001) return 0.0;
	float d = maxc - minc;
	float h;
	if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
	else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
	else                  h = (c.r - c.g) / d + 4.0;
	return h / 6.0;
}

float rgb_saturation(vec3 c) {
	float maxc = max(c.r, max(c.g, c.b));
	float minc = min(c.r, min(c.g, c.b));
	if (maxc < 0.001) return 0.0;
	return (maxc - minc) / maxc;
}

vec3 rgb_to_hsv(vec3 c) {
	float maxc = max(c.r, max(c.g, c.b));
	float minc = min(c.r, min(c.g, c.b));
	float d = maxc - minc;
	float h = 0.0;
	if (d > 0.00001) {
		if (maxc == c.r)      h = mod((c.g - c.b) / d, 6.0);
		else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
		else                  h = (c.r - c.g) / d + 4.0;
		h /= 6.0;
		if (h < 0.0) h += 1.0;
	}
	float s = (maxc > 0.00001) ? d / maxc : 0.0;
	return vec3(h, s, maxc);
}

vec3 hsv_to_rgb(vec3 c) {
	float h = c.x * 6.0;
	float s = c.y;
	float v = c.z;
	float ch = v * s;
	float x = ch * (1.0 - abs(mod(h, 2.0) - 1.0));
	float m = v - ch;
	vec3 rgb;
	if      (h < 1.0) rgb = vec3(ch, x,  0.0);
	else if (h < 2.0) rgb = vec3(x,  ch, 0.0);
	else if (h < 3.0) rgb = vec3(0.0, ch, x);
	else if (h < 4.0) rgb = vec3(0.0, x,  ch);
	else if (h < 5.0) rgb = vec3(x,  0.0, ch);
	else              rgb = vec3(ch, 0.0, x);
	return rgb + m;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 original = texture(input_texture, uv).rgb;
	vec3 color = clamp(original, vec3(0.0), vec3(65504.0));

	float hue = rgb_hue(color);
	float sat = rgb_saturation(color);

	float target = params.target_hue / 360.0;
	float half_range = (params.hue_range / 360.0) * 0.5;
	float soft = max(params.falloff / 360.0, 0.001);

	float hue_dist = abs(hue - target);
	hue_dist = min(hue_dist, 1.0 - hue_dist);

	float mask = 1.0 - smoothstep(half_range, half_range + soft, hue_dist);
	mask *= smoothstep(params.min_saturation, params.min_saturation + 0.05, sat);

	if (params.invert_mask > 0.5) mask = 1.0 - mask;

	float l = luma(color);
	vec3 desaturated = mix(color, vec3(l), params.desat_amount);

	vec3 tint = vec3(params.tint_r, params.tint_g, params.tint_b);
	desaturated *= tint;

	vec3 selected = color;
	if (abs(params.hue_shift) > 0.001 || params.sat_adjust != 1.0 || params.val_adjust != 1.0) {
		vec3 hsv = rgb_to_hsv(selected);
		hsv.x = fract(hsv.x + params.hue_shift / 360.0);
		hsv.y = clamp(hsv.y * params.sat_adjust, 0.0, 1.0);
		hsv.z *= params.val_adjust;
		selected = hsv_to_rgb(hsv);
	}

	vec3 result = mix(desaturated, selected, mask);
	result = mix(original, result, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
