shader_type canvas_item;
// Dark wooden tabletop under the 五子棋 / 象棋 boards: long wavy grain and a soft vignette.

uniform vec4 light_color : source_color = vec4(0.47, 0.29, 0.15, 1.0);
uniform vec4 dark_color : source_color = vec4(0.2, 0.11, 0.05, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
    // grain runs along x: stretch the noise, bend it with a slower noise
    float warp = noise(UV * vec2(2.0, 6.0)) * 3.0;
    float grain = noise(vec2(UV.x * 4.0, UV.y * 55.0 + warp));
    float streak = sin(UV.y * 90.0 + warp * 4.0) * 0.5 + 0.5;
    vec3 col = mix(dark_color.rgb, light_color.rgb, 0.45 + 0.3 * grain + 0.12 * streak);
    col *= 1.0 - 0.5 * smoothstep(0.3, 1.0, length(p * vec2(0.75, 1.0)));
    col += (hash(floor(FRAGCOORD.xy)) - 0.5) * 0.02;
    COLOR = vec4(col, 1.0);
}
