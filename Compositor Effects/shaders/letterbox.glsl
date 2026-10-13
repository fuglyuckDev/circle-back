#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float target_aspect;
	float edge_feather;
	float pad0;
	float pad1;
	vec4 matte_color;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	float current_aspect = float(size.x) / float(size.y);
	vec2 center_uv = uv - vec2(0.5);

	float mask = 1.0;
	if (current_aspect > params.target_aspect) {
		float visible_width = params.target_aspect / current_aspect * 0.5;
		float dist_x = abs(center_uv.x);
		mask = smoothstep(visible_width, visible_width - params.edge_feather * 0.05, dist_x);
	} else if (current_aspect < params.target_aspect) {
		float visible_height = current_aspect / params.target_aspect * 0.5;
		float dist_y = abs(center_uv.y);
		mask = smoothstep(visible_height, visible_height - params.edge_feather * 0.05, dist_y);
	}

	vec3 final_color = mix(params.matte_color.rgb, base_color, mask);
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
