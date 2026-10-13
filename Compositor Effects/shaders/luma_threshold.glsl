#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float dark_r;
	float dark_g;
	float dark_b;
	float cutoff;
	float light_r;
	float light_g;
	float light_b;
	float softness;
	float strength;
	float invert_mask;
	float color_space;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;

	float value;
	int space = int(params.color_space);
	if (space == 1)      value = color.r;
	else if (space == 2) value = color.g;
	else if (space == 3) value = color.b;
	else                 value = luma(color);

	float half_soft = max(params.softness, 0.001) * 0.5;
	float t = smoothstep(params.cutoff - half_soft, params.cutoff + half_soft, value);

	if (params.invert_mask > 0.5) {
		t = 1.0 - t;
	}

	vec3 dark_color  = vec3(params.dark_r,  params.dark_g,  params.dark_b);
	vec3 light_color = vec3(params.light_r, params.light_g, params.light_b);
	vec3 thresholded = mix(dark_color, light_color, t);

	vec3 result = mix(color, thresholded, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
