class_name ClockView
extends Control
## Alarm clock showing the seconds left in a turn; turns red and rattles near the end.

const SIZE := Vector2(60, 64)
const URGENT_AT := 5

var seconds := 0
var _shake: Tween

func _ready() -> void:
    custom_minimum_size = SIZE
    size = SIZE
    pivot_offset = SIZE / 2
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    hide()

func set_seconds(value: int) -> void:
    if value == seconds and visible:
        return
    seconds = value
    if not visible:
        show()
        scale = Vector2(0.5, 0.5)
        create_tween().tween_property(self, "scale", Vector2.ONE, 0.2) \
                .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    if seconds <= URGENT_AT and seconds > 0:
        _rattle()
    queue_redraw()

func stop() -> void:
    if _shake:
        _shake.kill()
    rotation = 0.0
    hide()

func _rattle() -> void:
    if _shake:
        _shake.kill()
    _shake = create_tween()
    for a in [0.18, -0.18, 0.12, -0.12, 0.0]:
        _shake.tween_property(self, "rotation", a, 0.05)

func _draw() -> void:
    var urgent := seconds <= URGENT_AT
    var c := Vector2(SIZE.x / 2, SIZE.y / 2 + 4)
    var r := 24.0
    var rim := Color(0.95, 0.25, 0.2) if urgent else Color(1, 0.78, 0.25)
    # bells and feet
    for sx in [-1.0, 1.0]:
        draw_circle(c + Vector2(sx * 15, -21), 8, rim.darkened(0.15), true, -1.0, true)
        draw_line(c + Vector2(sx * 13, 19), c + Vector2(sx * 18, 26), rim.darkened(0.3), 4.0, true)
    draw_line(c + Vector2(0, -r - 2), c + Vector2(0, -r - 7), rim.darkened(0.3), 3.0, true)
    draw_circle(c, r + 3, rim, true, -1.0, true)
    draw_circle(c, r - 1, Color(1, 0.98, 0.93), true, -1.0, true)
    draw_circle(c + Vector2(-7, -9), 7, Color(1, 1, 1, 0.6), true, -1.0, true)
    var text := str(maxi(seconds, 0))
    var color := Color(0.85, 0.12, 0.1) if urgent else Color(0.25, 0.18, 0.1)
    draw_string(UiTheme.bold, c + Vector2(-r, 9), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 26, color)
