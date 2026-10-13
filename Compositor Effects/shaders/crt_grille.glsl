#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float grille_intensity;
	float screen_curvature;
	float scanline_darkness;
	float phosphor_bloom;
} params;

vec2 warp_uv(vec2 uv, float curve) {
	uv = uv * 2.0 - 1.0;
	vec2 offset = abs(uv.yx) / vec2(curve);
	uv = uv + uv * offset * offset;
	uv = uv * 0.5 + 0.5;
	return uv;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);

	if (params.screen_curvature > 0.001) {
		uv = warp_uv(uv, max(10.0 - params.screen_curvature * 8.0, 1.5));
	}

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		imageStore(output_image, pos, vec4(0.0, 0.0, 0.0, 1.0));
		return;
	}

	vec3 base_color = texture(input_texture, uv).rgb;

	// Smooth Anti-Aliased RGB Triad Aperture Grille Mask (Anti-Shimmer / Anti-Moiré)
	float subpixel = mod(float(pos.x), 3.0);
	vec3 mask = 0.5 + 0.5 * cos(6.2831853 * (subpixel / 3.0 - vec3(0.0, 0.333, 0.667)));

	vec3 phosphor_col = mix(base_color, base_color * mask * (1.0 + params.phosphor_bloom * 0.5), params.grille_intensity);

	// Smooth Anti-Aliased Scanlines (No Nyquist Moiré Shimmer)
	float scanline = 0.5 + 0.5 * cos(uv.y * vec2(size).y * 3.14159);
	vec3 final_color = mix(phosphor_col, phosphor_col * scanline, params.scanline_darkness * 0.4);

	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
