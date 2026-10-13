#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D current_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D prev_texture;
layout(set = 0, binding = 3) uniform sampler2D velocity_texture;

layout(push_constant, std430) uniform Params {
	float decay;
	float velocity_scale;
	float time;
	float velocity_enabled;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
	float pad6;
	float pad7;
	float pad8;
	float pad9;
	float pad10;
	float pad11;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 current = texture(current_texture, uv).rgb;

	// Motion-rewind: sample the previous accumulation offset along the motion
	// so ghosts trail behind moving objects instead of smearing in place.
	vec2 vel = params.velocity_enabled > 0.5 ? texture(velocity_texture, uv).xy : vec2(0.0);
	vec3 prev = texture(prev_texture, clamp(uv - vel * params.velocity_scale * 0.25, vec2(0.0), vec2(1.0))).rgb;

	// Exponential accumulation: prev fades out, current blends in.
	vec3 acc = mix(prev, current, 1.0 - params.decay);
	imageStore(output_image, pos, vec4(clamp(acc, 0.0, 1.0), 1.0));
}