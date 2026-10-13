#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D base_texture;
layout(set = 0, binding = 1) uniform sampler2D blurred_texture;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D output_image;
layout(set = 0, binding = 3) uniform sampler2D depth_texture;

layout(push_constant, std430) uniform Params {
	float focus_distance;
	float in_focus_width;
	float near_range;
	float far_range;
	float z_near;
	float z_far;
	float use_physical;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
	float pad6;
	float pad7;
	float pad8;
} params;

float get_linear_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;
	float near_p = max(params.z_near, 0.01);
	float far_p = max(params.z_far, near_p + 1.0);
	return (near_p * far_p) / max(near_p + raw_depth * (far_p - near_p), 0.0001);
}

float far_coc(float depth, float far_plane) {
	if (params.use_physical > 0.5) {
		float d = max(depth - far_plane, 0.0);
		float denom = max(params.focus_distance + d, 0.0001);
		float norm = max(params.far_range / max(params.focus_distance + params.far_range, 0.0001), 0.0001);
		return clamp((d / denom) / norm, 0.0, 1.0);
	}
	return smoothstep(0.0, max(params.far_range, 0.05), depth - far_plane);
}

float near_coc(float depth, float near_plane) {
	if (params.use_physical > 0.5) {
		float d = max(near_plane - depth, 0.0);
		float denom = max(params.focus_distance + d, 0.0001);
		float norm = max(params.near_range / max(params.focus_distance + params.near_range, 0.0001), 0.0001);
		return clamp((d / denom) / norm, 0.0, 1.0);
	}
	return smoothstep(0.0, max(params.near_range, 0.05), near_plane - depth);
}

float compute_coc(float depth) {
	float half_focus = max(params.in_focus_width * 0.5, 0.01);
	float near_plane = params.focus_distance - half_focus;
	float far_plane = params.focus_distance + half_focus;

	if (depth > far_plane) {
		return far_coc(depth, far_plane);
	} else if (depth < near_plane) {
		return -near_coc(depth, near_plane);
	}
	return 0.0;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);

	vec3 base = texture(base_texture, uv).rgb;
	vec4 blr = texture(blurred_texture, uv);

	// Full-res CoC gate (Godot-style): the blurred layer is half-resolution, so
	// bilinear upsampling smears its alpha over the sharp center. Gate the blend
	// with the full-res depth CoC so pixels that are truly in focus never blur.
	float center_weight = abs(compute_coc(get_linear_depth(uv)));
	float sample_weight = clamp(blr.a, 0.0, 1.0);

	float mix_amount;
	if (sample_weight < center_weight) {
		mix_amount = clamp(max(sample_weight, center_weight), 0.0, 1.0);
	} else {
		mix_amount = clamp(center_weight, 0.0, 1.0);
	}

	vec3 col = mix(base, blr.rgb, mix_amount);
	imageStore(output_image, pos, vec4(clamp(col, 0.0, 1.0), 1.0));
}