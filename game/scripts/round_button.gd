class_name RoundButton
extends Button
## Round dark button for a screen corner, with a symbol drawn on it: the 设置 gear or
## the 返回 arrow.

enum Kind { GEAR, BACK }

const SIZE := Vector2(64, 64)

var kind := Kind.GEAR

static func make(k: Kind, label: String) -> RoundButton:
    var b := RoundButton.new()
    b.kind = k
    b.accessibility_name = label
    b.custom_minimum_size = SIZE
    b.focus_mode = Control.FOCUS_NONE
    b.flat = true
    return b

func _draw() -> void:
    var c := size / 2
    var r := minf(size.x, size.y) / 2
    draw_circle(c, r, Color(0, 0, 0, 0.45 if not is_hovered() else 0.6), true, -1.0, true)
    draw_circle(c, r, Color(1, 1, 1, 0.18), false, 2.0, true)
    match kind:
        Kind.GEAR:
            var teeth := PackedVector2Array()
            for i in 32:  # 8 teeth, each a flat top and a flat gap
                var a: float = TAU * (i / 4) / 8.0 + [-0.2, -0.13, 0.13, 0.2][i % 4]
                var rr := r * (0.62 if i % 4 in [1, 2] else 0.46)
                teeth.append(c + Vector2(cos(a), sin(a)) * rr)
            draw_colored_polygon(teeth, UiTheme.GOLD)
            draw_polyline(teeth + PackedVector2Array([teeth[0]]), UiTheme.GOLD, 1.0, true)
            draw_circle(c, r * 0.2, Color(0.12, 0.13, 0.18), true, -1.0, true)
        Kind.BACK:
            var k := r * 0.3
            draw_polyline(PackedVector2Array([c + Vector2(k * 0.5, -k), c + Vector2(-k * 0.6, 0),
                    c + Vector2(k * 0.5, k)]), UiTheme.GOLD, r * 0.16, true)
