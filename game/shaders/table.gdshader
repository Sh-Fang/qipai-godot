shader_type canvas_item;
// Felt table: radial light falloff, faint grain, and an oval table rim.

uniform vec4 center_color : source_color = vec4(0.14, 0.55, 0.35, 1.0);
uniform vec4 edge_color : source_color = vec4(0.02, 0.17, 0.11, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.45, 0.16);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec2 p = (UV - vec2(0.5, 0.45)) * vec2(aspect, 1.0);
    float d = length(p * vec2(0.75, 1.0));
    vec3 col = mix(center_color.rgb, edge_color.rgb, smoothstep(0.05, 0.9, d));

    // oval table: slightly lighter inside, thin gold rim line
    float e = length(p / vec2(0.62 * aspect / 1.78, 0.36));
    col += 0.03 * (1.0 - smoothstep(0.98, 1.0, e));
    float rim = 1.0 - smoothstep(0.0, 0.006, abs(e - 1.0));
    col = mix(col, rim_color.rgb, rim * rim_color.a);

    col += (hash(floor(FRAGCOORD.xy)) - 0.5) * 0.03;
    COLOR = vec4(col, 1.0);
}
