#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(push_constant, std430) uniform Params {
	float fog_density;
	float fog_start;
	float fog_end;
	float height_falloff;
	float z_near;
	float z_far;
	float pad0;
	float pad1;
	float horizon_r;
	float horizon_g;
	float horizon_b;
	float horizon_a;
	float zenith_r;
	float zenith_g;
	float zenith_b;
	float zenith_a;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float get_linear_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;
	float near_p = max(params.z_near, 0.01);
	float far_p = max(params.z_far, near_p + 1.0);
	// Godot 4 Reverse-Z: raw_depth = 1.0 at near, 0.0 at far
	float linear_d = (near_p * far_p) / max(near_p + raw_depth * (far_p - near_p), 0.0001);
	return linear_d;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	// Depth-based fog distance
	float depth = get_linear_depth(uv);
	float normalized_depth = clamp((depth - params.fog_start) / max(params.fog_end - params.fog_start, 0.01), 0.0, 1.0);

	// Exponential fog density based on actual depth
	float fog_factor = 1.0 - exp(-normalized_depth * params.fog_density * 2.0);

	// Vertical gradient between horizon and zenith fog colors
	float vert_factor = clamp(1.0 - uv.y, 0.0, 1.0);
	vert_factor = pow(vert_factor, max(params.height_falloff, 0.1));
	vec3 horizon_color = vec3(params.horizon_r, params.horizon_g, params.horizon_b);
	vec3 zenith_color = vec3(params.zenith_r, params.zenith_g, params.zenith_b);
	vec3 fog_gradient = mix(zenith_color, horizon_color, vert_factor);

	vec3 final_color = mix(base_color, fog_gradient, clamp(fog_factor, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
