#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float vignette_intensity;
	float vignette_smoothness;
	float squeeze_ratio;
	float pad;
	vec4 vignette_color;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	vec2 dist_center = (uv - vec2(0.5));
	dist_center.x *= params.squeeze_ratio;
	float dist = length(dist_center);

	float vignette = smoothstep(0.4, 0.4 + params.vignette_smoothness, dist);
	float mask = clamp(1.0 - vignette * params.vignette_intensity, 0.0, 1.0);

	vec3 final_color = mix(params.vignette_color.rgb, base_color, mask);
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
