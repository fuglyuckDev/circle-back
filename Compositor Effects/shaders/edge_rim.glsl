#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D normal_texture;

layout(push_constant, std430) uniform Params {
	float strength;
	float rim_r;
	float rim_g;
	float rim_b;
	float depth_threshold;
	float normal_threshold;
	float softness;
	float z_near;
	float z_far;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
	float pad6;
} params;

float linearize_depth(float raw) {
	float n = params.z_near;
	float f = params.z_far;
	return (n * f) / (n + raw * (f - n));
}

vec3 decode_normal(vec2 uv) {
	vec3 n = texture(normal_texture, uv).xyz * 2.0 - 1.0;
	float l = length(n);
	return l > 1e-4 ? n / l : vec3(0.0, 0.0, 1.0);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 size_f = vec2(size);
	vec2 uv = (vec2(pos) + 0.5) / size_f;
	vec2 e = vec2(1.0) / size_f;
	vec3 color = texture(input_texture, uv).rgb;

	// Depth + normal silhouette edges (reuse of the toon-outline edge idea).
	float d0 = linearize_depth(texture(depth_texture, uv).r);
	float dl = linearize_depth(texture(depth_texture, clamp(uv - vec2(e.x, 0.0), vec2(0.0), vec2(1.0))).r);
	float dr = linearize_depth(texture(depth_texture, clamp(uv + vec2(e.x, 0.0), vec2(0.0), vec2(1.0))).r);
	float du = linearize_depth(texture(depth_texture, clamp(uv - vec2(0.0, e.y), vec2(0.0), vec2(1.0))).r);
	float dd = linearize_depth(texture(depth_texture, clamp(uv + vec2(0.0, e.y), vec2(0.0), vec2(1.0))).r);
	float depth_edge = (abs(dl - dr) + abs(du - dd)) / max(d0, 0.001);

	vec3 nl = decode_normal(clamp(uv - vec2(e.x, 0.0), vec2(0.0), vec2(1.0)));
	vec3 nr = decode_normal(clamp(uv + vec2(e.x, 0.0), vec2(0.0), vec2(1.0)));
	vec3 nu = decode_normal(clamp(uv - vec2(0.0, e.y), vec2(0.0), vec2(1.0)));
	vec3 nd = decode_normal(clamp(uv + vec2(0.0, e.y), vec2(0.0), vec2(1.0)));
	float normal_edge = length(nl - nr) + length(nu - nd);

	float edge = max(
		depth_edge / max(params.depth_threshold, 0.0001),
		normal_edge / max(params.normal_threshold, 0.0001)
	);
	float rim = smoothstep(1.0 - params.softness, 1.0 + params.softness, edge);

	vec3 modified = color + vec3(params.rim_r, params.rim_g, params.rim_b) * rim;
	vec3 result = mix(color, modified, clamp(params.strength, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}