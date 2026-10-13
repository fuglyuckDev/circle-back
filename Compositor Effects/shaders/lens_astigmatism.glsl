#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float edge_blur_strength;
	float chromatic_aberration;
	float vignette_darkness;
	float inner_radius;
	float astigmatism;
	float pad0;
	float pad1;
	float pad2;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 col) {
	return 1.0 / (1.0 + luma(col));
}

vec2 anamorphic_corner_warp(vec2 uv, float strength, vec2 aspect) {
	vec2 uvd = (uv - vec2(0.5)) * aspect;
	float r2 = dot(uvd, uvd);
	// Cylindrical horizontal squeeze combined with radial barrel curvature
	vec2 distorted = (uvd * (1.0 + vec2(r2 * strength * 0.4, r2 * strength * 0.15))) / aspect;
	return distorted + vec2(0.5);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 raw_uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec2 aspect = vec2(float(size.x) / float(size.y), 1.0);

	// Apply optical anamorphic corner barrel warping
	vec2 uv = anamorphic_corner_warp(raw_uv, params.astigmatism, aspect);

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		imageStore(output_image, pos, vec4(0.0, 0.0, 0.0, 1.0));
		return;
	}

	vec3 base_color = texture(input_texture, uv).rgb;

	vec2 dist_center = (uv - vec2(0.5)) * aspect;
	float dist = length(dist_center);
	float dist_sq = dot(dist_center, dist_center);

	float blur_factor = smoothstep(params.inner_radius, params.inner_radius + 0.3, dist);

	float vignette = clamp(1.0 - dist_sq * params.vignette_darkness * 4.0, 0.0, 1.0);

	if (blur_factor <= 0.001) {
		imageStore(output_image, pos, vec4(clamp(base_color * vignette, 0.0, 1.0), 1.0));
		return;
	}

	vec2 dir = normalize(dist_center + vec2(1e-5));
	vec2 perp = vec2(-dir.y, dir.x);

	float r_blur = params.edge_blur_strength * blur_factor * 4.0;
	float r_aberration = params.chromatic_aberration * blur_factor * 2.0;

	vec3 accumulated_col = vec3(0.0);
	float total_weight = 0.0;

	for (int i = -4; i <= 4; i++) {
		float fi = float(i);
		vec2 sample_offset = (dir * fi * r_blur + perp * fi * r_blur * params.astigmatism) * texel;

		vec2 uv_r = clamp(uv + sample_offset + dir * r_aberration * texel, vec2(0.0), vec2(1.0));
		vec2 uv_g = clamp(uv + sample_offset, vec2(0.0), vec2(1.0));
		vec2 uv_b = clamp(uv + sample_offset - dir * r_aberration * texel, vec2(0.0), vec2(1.0));

		vec3 s_r = texture(input_texture, uv_r).rgb;
		vec3 s_g = texture(input_texture, uv_g).rgb;
		vec3 s_b = texture(input_texture, uv_b).rgb;

		vec3 s_combined = vec3(s_r.r, s_g.g, s_b.b);
		float kw = karis_weight(s_combined);
		float w = exp(-0.3 * abs(fi)) * kw;

		accumulated_col += s_combined * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		accumulated_col /= total_weight;
	}

	vec3 final_color = accumulated_col * vignette;

	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
