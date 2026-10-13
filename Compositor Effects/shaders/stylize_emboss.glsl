#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float angle;
	float mix_mode;
	float bias;
	float kernel_radius;
	float edge_tint_r;
	float edge_tint_g;
	float edge_tint_b;
	float luma_only;
	float contrast;
	float blend;
	float metallic;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 original = texture(input_texture, uv).rgb;

	float a = radians(params.angle);
	vec2 dir = vec2(cos(a), -sin(a));
	int radius = max(int(params.kernel_radius), 1);

	vec3 accum_pos = vec3(0.0);
	vec3 accum_neg = vec3(0.0);

	for (int i = 1; i <= radius; i++) {
		float w = 1.0 / float(i);
		vec2 offset = dir * float(i) * texel;
		accum_pos += texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb * w;
		accum_neg += texture(input_texture, clamp(uv - offset, vec2(0.0), vec2(1.0))).rgb * w;
	}

	vec3 emboss = (accum_pos - accum_neg) * params.strength;

	if (params.contrast != 1.0) {
		emboss = (emboss - 0.0) * params.contrast;
	}

	emboss += vec3(params.bias);

	vec3 tint = vec3(params.edge_tint_r, params.edge_tint_g, params.edge_tint_b);

	vec3 result;
	int mode = int(params.mix_mode);

	if (mode == 0) {
		float l = luma(emboss);
		result = vec3(l) * tint;
	} else if (mode == 1) {
		vec3 base_c = original;
		vec3 bv = clamp(emboss, vec3(0.0), vec3(1.0));
		result = mix(
			2.0 * base_c * bv,
			1.0 - 2.0 * (1.0 - base_c) * (1.0 - bv),
			step(0.5, bv)
		);
	} else if (mode == 2) {
		result = original + emboss * tint - vec3(params.bias);
	} else {
		result = original * (emboss + vec3(1.0 - params.bias));
	}

	if (params.metallic > 0.001) {
		float edge_luma = abs(luma(accum_pos - accum_neg));
		float highlight = pow(clamp(edge_luma * params.strength, 0.0, 1.0), 3.0);
		result += tint * highlight * params.metallic;
	}

	if (params.luma_only > 0.5) {
		float orig_luma = luma(original);
		float result_luma = luma(result);
		if (result_luma > 0.0001 && orig_luma > 0.0001) {
			result = original * (result_luma / orig_luma);
		}
	}

	result = mix(original, result, params.blend);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
