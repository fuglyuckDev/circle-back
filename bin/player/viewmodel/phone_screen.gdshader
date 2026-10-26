shader_type canvas_item;

void fragment() {
    // Calculate distance from the center of the control node (0.5, 0.5)
    float dist = distance(UV, vec2(0.5));
    
    // Smoothly cut off everything outside a 0.5 radius to form a perfect circle
    float alpha = smoothstep(0.5, 0.49, dist);
    
    // Mix the original color with the circular transparency mask
    COLOR = vec4(COLOR.rgb, COLOR.a * alpha);
}
