#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float in_black;
	float in_white;
	float in_gamma;
	float out_black;
	float out_white;
	float strength;
	float in_black_r;
	float in_white_r;
	float in_black_g;
	float in_white_g;
	float in_black_b;
	float in_white_b;
	float gamma_r;
	float gamma_g;
	float gamma_b;
	float clamp_output;
} params;

vec3 apply_levels(vec3 color, vec3 ib, vec3 iw, vec3 gm, float ob, float ow) {
	vec3 in_range = max(iw - ib, vec3(0.0001));
	color = clamp((color - ib) / in_range, vec3(0.0), vec3(1.0));
	color = pow(color, 1.0 / max(gm, vec3(0.01)));
	color = mix(vec3(ob), vec3(ow), color);
	return color;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 original = texture(input_texture, uv).rgb;

	vec3 ib = vec3(params.in_black + params.in_black_r, params.in_black + params.in_black_g, params.in_black + params.in_black_b);
	vec3 iw = vec3(params.in_white + params.in_white_r, params.in_white + params.in_white_g, params.in_white + params.in_white_b);
	vec3 gm = vec3(params.in_gamma * params.gamma_r, params.in_gamma * params.gamma_g, params.in_gamma * params.gamma_b);

	vec3 color = apply_levels(original, ib, iw, gm, params.out_black, params.out_white);

	if (params.clamp_output > 0.5) {
		color = clamp(color, vec3(0.0), vec3(1.0));
	}

	vec3 result = mix(original, color, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
