#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float levels;
	float strength;
	float gamma;
	float saturation_boost;
	float dither_amount;
	float hsv_mode;
	float levels_r;
	float levels_g;
	float levels_b;
	float dither_size;
	float edge_mode;
	float edge_strength;
	float edge_threshold;
	float pad0;
	float pad1;
	float pad2;
} params;

vec3 rgb_to_hsv(vec3 c) {
	float cmax  = max(c.r, max(c.g, c.b));
	float cmin  = min(c.r, min(c.g, c.b));
	float delta = cmax - cmin;
	float h = 0.0;
	if (delta > 0.00001) {
		if (cmax == c.r)      h = mod((c.g - c.b) / delta, 6.0);
		else if (cmax == c.g) h = (c.b - c.r) / delta + 2.0;
		else                  h = (c.r - c.g) / delta + 4.0;
		h /= 6.0;
		if (h < 0.0) h += 1.0;
	}
	float s = (cmax > 0.00001) ? delta / cmax : 0.0;
	return vec3(h, s, cmax);
}

vec3 hsv_to_rgb(vec3 c) {
	float h = c.x * 6.0;
	float s = c.y;
	float v = c.z;
	float chroma = v * s;
	float x = chroma * (1.0 - abs(mod(h, 2.0) - 1.0));
	float m = v - chroma;
	vec3 rgb;
	if      (h < 1.0) rgb = vec3(chroma, x,      0.0);
	else if (h < 2.0) rgb = vec3(x,      chroma, 0.0);
	else if (h < 3.0) rgb = vec3(0.0,    chroma, x);
	else if (h < 4.0) rgb = vec3(0.0,    x,      chroma);
	else if (h < 5.0) rgb = vec3(x,      0.0,    chroma);
	else              rgb = vec3(chroma,  0.0,    x);
	return rgb + m;
}

float bayer8x8(ivec2 coord) {
	int x = coord.x & 7;
	int y = coord.y & 7;
	const float bayer[64] = float[64](
		 0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
		48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
		12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
		60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
		 3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
		51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
		15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
		63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
	);
	return bayer[y * 8 + x] / 64.0 - 0.5;
}

float quantize(float value, float n, float dither_offset) {
	float shifted = clamp(value + dither_offset / n, 0.0, 1.0);
	return floor(shifted * n + 0.5) / n;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 color = texture(input_texture, uv).rgb;

	float gamma_val = max(params.gamma, 0.01);
	vec3 gc = pow(max(color, vec3(0.0)), vec3(1.0 / gamma_val));

	ivec2 dither_coord = ivec2(vec2(pos) / max(params.dither_size, 1.0));
	float dither = bayer8x8(dither_coord) * params.dither_amount;

	float nr = max(params.levels * params.levels_r, 2.0);
	float ng = max(params.levels * params.levels_g, 2.0);
	float nb = max(params.levels * params.levels_b, 2.0);

	vec3 posterized;
	if (params.hsv_mode > 0.5) {
		vec3 hsv = rgb_to_hsv(gc);
		hsv.x = quantize(hsv.x, nr * 2.0, dither);
		hsv.y = quantize(hsv.y, nr, dither);
		hsv.z = quantize(hsv.z, nr, dither);
		posterized = hsv_to_rgb(hsv);
	} else {
		posterized.r = quantize(gc.r, nr, dither);
		posterized.g = quantize(gc.g, ng, dither);
		posterized.b = quantize(gc.b, nb, dither);
	}

	posterized = pow(max(posterized, vec3(0.0)), vec3(gamma_val));

	float l = luma(posterized);
	posterized = mix(vec3(l), posterized, params.saturation_boost);

	if (params.edge_mode > 0.5) {
		vec3 cx = texture(input_texture, clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb
		        - texture(input_texture, clamp(uv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
		vec3 cy = texture(input_texture, clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb
		        - texture(input_texture, clamp(uv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb;
		float edge = length(cx) + length(cy);
		float mask = smoothstep(params.edge_threshold, params.edge_threshold + 0.1, edge);

		if (params.edge_mode > 1.5) {
			posterized = mix(posterized, vec3(0.0), mask * params.edge_strength);
		} else {
			posterized *= 1.0 + mask * params.edge_strength;
		}
	}

	vec3 result = mix(color, posterized, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
