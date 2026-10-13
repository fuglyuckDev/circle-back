#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float grain_intensity;
	float grain_size;
	float coarse_mix;
	float peak;
	float rolloff;
	float grain_chroma;
	float frame_seed;
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

// PCG-style permutation hash. The `seed` (frame counter) PERMUTES the random
// value at each fixed cell, so the pattern stays in place spatially but is
// fresh every frame. This is what fixes the "scrolling texture" artifact.
float hash(ivec2 p, int seed) {
	uint v = uint(p.x) * 0x54491B21u ^ uint(p.y) * 0x7A4BAA9Du ^ uint(seed) * 0x9E3779B1u;
	v = (v ^ (v >> 16u)) * 0x85EBCA6Bu;
	v = v ^ (v >> 13u);
	return float(v & 0xFFFFFFu) / float(0xFFFFFFu);
}

// Value noise with quintic smoothstep (C2 continuous, no visible grid edges).
// Random values sit on a coarse grid and blend together — this is what makes
// grain organic silver-halide clusters instead of per-pixel digital speckle.
float vnoise(vec2 p, int seed) {
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i, seed);
	float b = hash(i + ivec2(1, 0), seed);
	float c = hash(i + ivec2(0, 1), seed);
	float d = hash(i + ivec2(1, 1), seed);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;
	float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
	int seed = int(params.frame_seed);

	// Grain grid: fine crystals of `grain_size` px plus coarser clumps at
	// 1.5x (real film crystals cluster into larger structures).
	float gs = max(params.grain_size, 0.25);
	vec2 grain_px = vec2(pos) / gs;

	float fine = vnoise(grain_px, seed);
	float coarse = vnoise(grain_px * (1.0 / 1.5), seed ^ 0x517CC1B7);
	float mono = mix(fine, coarse, params.coarse_mix);

	// Chroma grain: separate R/B noise at 1.8x the grain scale (colour grain is
	// coarser on film), kept subtle.
	float gr = vnoise(grain_px * (1.0 / 1.8), seed ^ 0x1234567);
	float gb = vnoise(grain_px * (1.0 / 1.8), seed ^ 0x7654321);
	vec3 grain = mix(vec3(mono), vec3(mono, gr, gb), params.grain_chroma);
	grain -= 0.5; // centre on zero

	// Asymmetric film response curve (calibrated against real scans):
	//  - peak grain in the midtones at `peak`,
	//  - power-law ramp (gamma 0.18) in the shadows with a smoothstep cut near
	//    true black so blacks stay black,
	//  - tight Gaussian rolloff in the highlights so brights don't go dirty.
	float peak = clamp(params.peak, 0.01, 0.99);
	float roll = max(params.rolloff, 0.01);
	float r = (lum > peak) ? roll * 0.35 : roll;
	float bell = exp(-0.5 * pow((lum - peak) / r, 2.0));
	float shadow = min(pow(max(lum, 1e-4) / peak, 0.18), 1.0);
	shadow *= smoothstep(0.0, 0.03, lum);
	float weight = bell * shadow;

	float scale = params.grain_intensity * weight * 0.5;
	vec3 result = color + grain * scale;
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}