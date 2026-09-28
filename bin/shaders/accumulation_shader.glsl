#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D prev_frame;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float alpha;     // blend factor: 0 = no trail, 1 = infinite trail
	float _pad;
} params;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);

	if (texel.x >= size.x || texel.y >= size.y) {
		return;
	}

	vec4 current = imageLoad(color_image, texel);
	vec4 previous = imageLoad(prev_frame, texel);

	// Blend: higher alpha = more trail persistence
	vec4 blended = mix(current, previous, params.alpha);

	// Write blended result to screen
	imageStore(color_image, texel, blended);

	// Store current blended frame as next frame's "previous"
	imageStore(prev_frame, texel, blended);
}
