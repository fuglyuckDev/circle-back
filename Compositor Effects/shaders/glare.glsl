#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float threshold;
	float intensity;
	float glare_size;
	float samples;
	float ray_count;
	float base_angle;
	float color_r;
	float color_g;
	float color_b;
	float falloff;
	float knee;
	float chroma_shift;
	float rotation_speed;
	float time;
	float blend_mode;
	float asymmetry;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 c) {
	return 1.0 / (1.0 + luma(c));
}

float soft_threshold(float luma_val, float thr, float kn) {
	return smoothstep(thr, thr + kn, luma_val);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);

	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 original = texture(input_texture, uv).rgb;

	int rays = max(int(params.ray_count), 1);
	float angle_step = 3.14159265 / float(rays);
	int half_samples = max(int(params.samples), 1);
	float step_size = max(params.glare_size / float(half_samples), 0.0);

	float animated_angle = params.base_angle + params.time * params.rotation_speed;

	vec3 glare_accum = vec3(0.0);

	for (int r = 0; r < rays; r++) {
		float ray_angle = animated_angle + float(r) * angle_step;
		vec2 dir = vec2(cos(ray_angle), -sin(ray_angle));

		float ray_scale_fwd = 1.0 + params.asymmetry * (float(r) / float(max(rays - 1, 1)));
		float ray_scale_bck = 1.0 - params.asymmetry * (float(r) / float(max(rays - 1, 1)));

		for (int i = 1; i <= half_samples; i++) {
			float t = float(i) / float(half_samples);
			float weight = pow(1.0 - t, params.falloff);

			float dist_fwd = float(i) * step_size * ray_scale_fwd;
			float dist_bck = float(i) * step_size * ray_scale_bck;

			float chroma = params.chroma_shift;

			vec2 uv_f_r = clamp(uv + dir * dist_fwd * (1.0 - chroma) * texel, vec2(0.0), vec2(1.0));
			vec2 uv_f_g = clamp(uv + dir * dist_fwd * texel, vec2(0.0), vec2(1.0));
			vec2 uv_f_b = clamp(uv + dir * dist_fwd * (1.0 + chroma) * texel, vec2(0.0), vec2(1.0));

			vec3 col_f_r = texture(input_texture, uv_f_r).rgb;
			vec3 col_f_g = texture(input_texture, uv_f_g).rgb;
			vec3 col_f_b = texture(input_texture, uv_f_b).rgb;

			float l_fr = luma(col_f_r);
			float l_fg = luma(col_f_g);
			float l_fb = luma(col_f_b);

			float h_fr = soft_threshold(l_fr, params.threshold, params.knee) * karis_weight(col_f_r);
			float h_fg = soft_threshold(l_fg, params.threshold, params.knee) * karis_weight(col_f_g);
			float h_fb = soft_threshold(l_fb, params.threshold, params.knee) * karis_weight(col_f_b);

			vec3 fwd_contrib = vec3(col_f_r.r * h_fr, col_f_g.g * h_fg, col_f_b.b * h_fb) * weight;
			glare_accum += fwd_contrib;

			vec2 uv_b_r = clamp(uv - dir * dist_bck * (1.0 - chroma) * texel, vec2(0.0), vec2(1.0));
			vec2 uv_b_g = clamp(uv - dir * dist_bck * texel, vec2(0.0), vec2(1.0));
			vec2 uv_b_b = clamp(uv - dir * dist_bck * (1.0 + chroma) * texel, vec2(0.0), vec2(1.0));

			vec3 col_b_r = texture(input_texture, uv_b_r).rgb;
			vec3 col_b_g = texture(input_texture, uv_b_g).rgb;
			vec3 col_b_b = texture(input_texture, uv_b_b).rgb;

			float l_br = luma(col_b_r);
			float l_bg = luma(col_b_g);
			float l_bb = luma(col_b_b);

			float h_br = soft_threshold(l_br, params.threshold, params.knee) * karis_weight(col_b_r);
			float h_bg = soft_threshold(l_bg, params.threshold, params.knee) * karis_weight(col_b_g);
			float h_bb = soft_threshold(l_bb, params.threshold, params.knee) * karis_weight(col_b_b);

			vec3 bck_contrib = vec3(col_b_r.r * h_br, col_b_g.g * h_bg, col_b_b.b * h_bb) * weight;
			glare_accum += bck_contrib;
		}
	}

	glare_accum *= step_size;
	float norm = 2.0 / float(rays);
	vec3 tint = vec3(params.color_r, params.color_g, params.color_b);
	vec3 final_glare = glare_accum * tint * params.intensity * 0.05 * norm;

	vec3 result;
	int bm = int(params.blend_mode);
	if (bm == 1) {
		result = 1.0 - (1.0 - original) * (1.0 - final_glare);
	} else {
		result = original + final_glare;
	}

	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
