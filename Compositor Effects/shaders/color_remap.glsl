#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float shadow_r;
	float shadow_g;
	float shadow_b;
	float strength;
	float highlight_r;
	float highlight_g;
	float highlight_b;
	float preserve_luma;
	float midtone_r;
	float midtone_g;
	float midtone_b;
	float midtone_pos;
	float curve_gamma;
	float saturation_preserve;
	float luma_mode;
	float pad0;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 three_point_gradient(float t, vec3 shadow, vec3 midtone, vec3 highlight, float mid_pos) {
	float mp = clamp(mid_pos, 0.01, 0.99);
	if (t < mp) {
		return mix(shadow, midtone, t / mp);
	}
	return mix(midtone, highlight, (t - mp) / (1.0 - mp));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;

	float l = clamp(luma(color), 0.0, 1.0);

	float gamma = max(params.curve_gamma, 0.01);
	float t = pow(l, 1.0 / gamma);

	vec3 shadow    = vec3(params.shadow_r,    params.shadow_g,    params.shadow_b);
	vec3 midtone   = vec3(params.midtone_r,   params.midtone_g,   params.midtone_b);
	vec3 highlight = vec3(params.highlight_r,  params.highlight_g,  params.highlight_b);

	vec3 remapped = three_point_gradient(t, shadow, midtone, highlight, params.midtone_pos);

	if (params.preserve_luma > 0.001) {
		float remap_luma = luma(remapped);
		float ratio = l / max(remap_luma, 0.0001);
		remapped *= mix(1.0, ratio, params.preserve_luma);
	}

	if (params.saturation_preserve > 0.001) {
		float orig_sat = length(color - vec3(l));
		float remap_luma2 = luma(remapped);
		float remap_sat = length(remapped - vec3(remap_luma2));
		if (remap_sat > 0.0001) {
			float target_sat = mix(remap_sat, orig_sat, params.saturation_preserve);
			remapped = vec3(remap_luma2) + (remapped - vec3(remap_luma2)) * (target_sat / remap_sat);
		}
	}

	vec3 result = mix(color, remapped, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
