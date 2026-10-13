#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(push_constant, std430) uniform Params {
	float strength;
	float threshold;
	float limit;
	float depth_threshold;
	float radius;
	float luma_only;
	float z_near;
	float z_far;
	float detail_boost;
	float edge_protect;
	float pad0;
	float pad1;
} params;

float linearize_depth(float raw_depth) {
	float n = params.z_near;
	float f = params.z_far;
	return (n * f) / (n + raw_depth * (f - n));
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
	vec3 center = texture(input_texture, uv).rgb;

	float raw_depth = texture(depth_texture, uv).r;
	float linear_d = linearize_depth(raw_depth);

	if (params.depth_threshold < 1.0 && linear_d > params.depth_threshold * params.z_far) {
		imageStore(output_image, pos, vec4(center, 1.0));
		return;
	}

	int r = max(int(params.radius), 1);
	vec3 laplacian = vec3(0.0);
	float total_weight = 0.0;

	for (int x = -r; x <= r; x++) {
		for (int y = -r; y <= r; y++) {
			if (x == 0 && y == 0) continue;
			float w = 1.0 / float(abs(x) + abs(y));
			vec2 offset = vec2(float(x), float(y)) * texel;
			laplacian -= texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb * w;
			total_weight += w;
		}
	}
	laplacian += center * total_weight;
	laplacian /= max(total_weight, 0.0001);

	float magnitude;
	if (params.luma_only > 0.5) {
		magnitude = abs(luma(laplacian));
	} else {
		magnitude = length(laplacian);
	}

	float factor = smoothstep(params.threshold, params.threshold + 0.1, magnitude);

	if (params.edge_protect > 0.001) {
		float d_right = linearize_depth(texture(depth_texture, clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r);
		float d_down  = linearize_depth(texture(depth_texture, clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r);
		float depth_grad = abs(linear_d - d_right) + abs(linear_d - d_down);
		float edge_mask = 1.0 - smoothstep(0.0, params.edge_protect, depth_grad);
		factor *= edge_mask;
	}

	vec3 sharpening = laplacian * params.strength * factor;

	if (params.detail_boost > 0.001) {
		float detail = luma(abs(laplacian));
		sharpening *= 1.0 + detail * params.detail_boost;
	}

	sharpening = clamp(sharpening, vec3(-params.limit), vec3(params.limit));

	vec3 result;
	if (params.luma_only > 0.5) {
		float sharp_luma = luma(sharpening);
		result = center + vec3(sharp_luma);
	} else {
		result = center + sharpening;
	}

	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
