shader_type canvas_item;
// Fx.edge_glow: `tint` towards the screen's edges, the middle left clear.

uniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 0.5);

void fragment() {
    vec2 d = abs(UV - 0.5) * 2.0;
    COLOR = vec4(tint.rgb, tint.a * smoothstep(0.72, 1.0, max(d.x, d.y)));
}
