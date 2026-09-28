// Godot Accumulation Motion Blur
// By Lamb; MIT license
//
// Use in conjunction with the accumulation_motion_blur_shader() GDScript method
// to feed this shader the framebuffer texture.
// Apply this shader material to a ColorRect node to affect visuals underneath it.

shader_type canvas_item;


uniform float alpha: hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float blur = 0.0;
uniform sampler2D framebuffer;


void fragment() {
	COLOR = texture(framebuffer, SCREEN_UV, blur);
	COLOR.a = alpha;
}