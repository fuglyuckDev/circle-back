#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float shadow_black_floor;
	float midtone_gamma_balance;
	float highlight_white_ceiling;
	float vibrance;
	vec4 shadow_color;
	vec4 midtone_color;
	vec4 highlight_color;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	vec3 col = max(base_color - vec3(params.shadow_black_floor * 0.1), vec3(0.0));
	col = col / max(1.0 - params.highlight_white_ceiling * 0.2, 0.01);
	col = pow(col, vec3(1.0 / max(params.midtone_gamma_balance, 0.1)));

	float lum = luma(col);
	float shadow_w = clamp(1.0 - lum * 2.5, 0.0, 1.0);
	float highlight_w = clamp(lum * 2.0 - 0.5, 0.0, 1.0);
	float midtone_w = clamp(1.0 - shadow_w - highlight_w, 0.0, 1.0);

	vec3 graded = col * (shadow_w * params.shadow_color.rgb * 2.0 +
	                     midtone_w * params.midtone_color.rgb * 2.0 +
	                     highlight_w * params.highlight_color.rgb * 2.0);

	float max_c = max(graded.r, max(graded.g, graded.b));
	float min_c = min(graded.r, min(graded.g, graded.b));
	float sat = max_c - min_c;
	vec3 vib_color = mix(vec3(lum), graded, 1.0 + params.vibrance * (1.0 - sat));

	imageStore(output_image, pos, vec4(clamp(vib_color, 0.0, 1.0), 1.0));
}
