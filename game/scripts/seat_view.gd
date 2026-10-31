class_name SeatView
extends Control
## One player's spot at the table: drawn avatar (crown for the landlord, straw hat for
## farmers), name, card count with a low-cards alarm, a speech bubble, a 加倍 tag and
## the turn clock.

const R := 34.0
const AVATAR := Vector2(R + 14, R + 14)
const LANDLORD := Color(1, 0.72, 0.2)
const FARMER := Color(0.36, 0.68, 0.98)

@export var seat_name := ""

var role := ""  # "", "landlord", "farmer"
var active := false:
    set(v):
        if active != v:
            active = v
            _set_glow_running(v)
var glow := 0.0:
    set(v):
        glow = v
        queue_redraw()

var _name: Label
var _role: Label
var _count: Label
var _bubble: Label
var _double: Label
var clock: ClockView  # main positions it on the table side of the seat
var _glow_tween: Tween
var _bubble_tween: Tween
var _alarm_tween: Tween
var _count_value := -1

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _name = _label(Vector2(AVATAR.x + R + 10, 8), 22, Color.WHITE, UiTheme.bold)
    _name.text = seat_name
    _role = _label(Vector2(AVATAR.x + R + 10, 38), 18, Color(1, 1, 1, 0.7))
    _count = _label(Vector2(AVATAR.x + R + 34, 64), 22, Color.WHITE, UiTheme.bold)

    _bubble = Label.new()
    _bubble.add_theme_font_override("font", UiTheme.bold)
    _bubble.add_theme_font_size_override("font_size", 24)
    _bubble.add_theme_color_override("font_color", Color(0.35, 0.18, 0.05))
    _bubble.add_theme_constant_override("shadow_offset_y", 0)
    var box := StyleBoxFlat.new()
    box.bg_color = Color(1, 0.97, 0.88)
    box.border_color = Color(0.95, 0.65, 0.2)
    box.set_border_width_all(3)
    box.set_corner_radius_all(18)
    box.content_margin_left = 16
    box.content_margin_right = 16
    box.content_margin_top = 4
    box.content_margin_bottom = 6
    box.shadow_color = Color(0, 0, 0, 0.3)
    box.shadow_size = 5
    _bubble.add_theme_stylebox_override("normal", box)
    _bubble.modulate.a = 0.0
    _bubble.z_index = 5
    add_child(_bubble)

    _double = Label.new()
    _double.text = "加倍"
    _double.add_theme_font_override("font", UiTheme.bold)
    _double.add_theme_font_size_override("font_size", 18)
    _double.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
    var tag := StyleBoxFlat.new()
    tag.bg_color = Color(0.85, 0.15, 0.12)
    tag.border_color = Color(1, 0.8, 0.35)
    tag.set_border_width_all(2)
    tag.set_corner_radius_all(10)
    tag.content_margin_left = 8
    tag.content_margin_right = 8
    tag.content_margin_bottom = 2
    _double.add_theme_stylebox_override("normal", tag)
    _double.position = Vector2(size.x - 58, -12)
    _double.pivot_offset = Vector2(28, 14)
    _double.hide()
    add_child(_double)

    clock = ClockView.new()
    add_child(clock)

func _label(pos: Vector2, font_size: int, color: Color, font: Font = null) -> Label:
    var l := Label.new()
    l.position = pos
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    if font:
        l.add_theme_font_override("font", font)
    add_child(l)
    return l

## Global centre of the avatar, where this player's cards fly from.
func avatar_global() -> Vector2:
    return global_position + AVATAR

func set_info(new_role: String, role_text: String, count: int) -> void:
    if new_role != role:
        role = new_role
        queue_redraw()
        if role != "":
            var t := create_tween()
            scale = Vector2(1.15, 1.15)
            pivot_offset = AVATAR
            t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _role.text = role_text
    _role.add_theme_color_override("font_color",
            LANDLORD if role == "landlord" else FARMER if role == "farmer" else Color(1, 1, 1, 0.7))
    if count != _count_value:
        _count_value = count
        _count.text = str(count)
        _set_alarm(count > 0 and count <= 2)
        queue_redraw()

## The 加倍 tag in the panel's corner.
func set_doubled(on: bool) -> void:
    if on == _double.visible:
        return
    _double.visible = on
    if on:
        _double.scale = Vector2(2, 2)
        _double.create_tween().tween_property(_double, "scale", Vector2.ONE, 0.3) \
                .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Speech bubble above the seat that pops in and fades after a moment.
func say(text: String, hold := 1.4) -> void:
    _bubble.text = text
    _bubble.size = Vector2.ZERO
    _bubble.reset_size()
    _bubble.position = Vector2((size.x - _bubble.size.x) / 2, -_bubble.size.y - 6)
    _bubble.pivot_offset = Vector2(_bubble.size.x / 2, _bubble.size.y)
    if _bubble_tween:
        _bubble_tween.kill()
    _bubble.scale = Vector2(0.4, 0.4)
    _bubble.modulate.a = 1.0
    _bubble_tween = create_tween()
    _bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _bubble_tween.tween_interval(hold)
    _bubble_tween.tween_property(_bubble, "modulate:a", 0.0, 0.3)

func _set_alarm(on: bool) -> void:
    if _alarm_tween:
        _alarm_tween.kill()
        _alarm_tween = null
    _count.modulate = Color.WHITE
    _count.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if on else Color.WHITE)
    if on:
        _alarm_tween = create_tween().set_loops()
        _alarm_tween.tween_property(_count, "modulate:a", 0.25, 0.35)
        _alarm_tween.tween_property(_count, "modulate:a", 1.0, 0.35)

func _set_glow_running(on: bool) -> void:
    if _glow_tween:
        _glow_tween.kill()
        _glow_tween = null
    glow = 0.0
    if on:
        _glow_tween = create_tween().set_loops()
        _glow_tween.tween_property(self, "glow", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
        _glow_tween.tween_property(self, "glow", 0.25, 0.5).set_trans(Tween.TRANS_SINE)

# ---- drawing ------------------------------------------------------------------

func _draw() -> void:
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color(0, 0, 0, 0.32)
    panel.set_corner_radius_all(16)
    panel.anti_aliasing = true
    panel.set_border_width_all(2)
    panel.border_color = Color(1, 1, 1, 0.12)
    if active:
        panel.border_color = Color(1, 0.85, 0.35, 0.35 + 0.65 * glow)
        panel.set_border_width_all(3)
        panel.shadow_color = Color(1, 0.8, 0.3, 0.45 * glow)
        panel.shadow_size = int(14 * glow)
    draw_style_box(panel, Rect2(Vector2.ZERO, size))

    if active:
        draw_circle(AVATAR, R + 7, Color(1, 0.85, 0.35, glow), false, 3.0, true)
    _draw_avatar()

    # card-count icon: a tiny card back
    var icon := Rect2(AVATAR.x + R + 12, 66, 18, 25)
    var back := StyleBoxFlat.new()
    back.bg_color = Color(0.66, 0.1, 0.13)
    back.border_color = Color(0.98, 0.95, 0.88)
    back.set_border_width_all(2)
    back.set_corner_radius_all(3)
    draw_style_box(back, icon)

## Cartoon portrait kept strictly inside the avatar disc: the shoulders are clipped
## to the circle and the hats are sized to sit below its rim.
func _draw_avatar() -> void:
    var u := R
    var o := AVATAR
    var bg := Color(1, 0.8, 0.42) if role == "landlord" else Color(0.62, 0.82, 1) if role == "farmer" \
            else Color(0.78, 0.8, 0.84)
    var ring := LANDLORD if role == "landlord" else FARMER if role == "farmer" else Color(0.6, 0.64, 0.7)
    draw_circle(o, R + 3, Color(1, 1, 1, 0.95), true, -1.0, true)
    draw_circle(o, R, bg, true, -1.0, true)
    draw_circle(o + Vector2(0, -u * 0.35), u * 0.7, Color(1, 1, 1, 0.18), true, -1.0, true)

    var disc := _ellipse(o, R - 0.5, R - 0.5, 48)
    var shirt := Color(0.78, 0.18, 0.16) if role == "landlord" else Color(0.28, 0.5, 0.8) if role == "farmer" \
            else Color(0.45, 0.5, 0.58)
    for part in Geometry2D.intersect_polygons(_ellipse(o + Vector2(0, u * 0.98), u * 0.72, u * 0.5, 32), disc):
        _fill(part, shirt)
    var collar := Color(1, 0.82, 0.25) if role == "landlord" else Color(1, 1, 1, 0.85)
    _fill(PackedVector2Array([o + Vector2(-u * 0.2, u * 0.5), o + Vector2(u * 0.2, u * 0.5),
            o + Vector2(0, u * 0.74)]), collar)

    var skin := Color(1, 0.86, 0.72)
    var head := o + Vector2(0, -u * 0.06)
    draw_rect(Rect2(head + Vector2(-u * 0.11, u * 0.25), Vector2(u * 0.22, u * 0.22)), skin.darkened(0.08))
    draw_circle(head + Vector2(-u * 0.36, u * 0.02), u * 0.08, skin.darkened(0.05), true, -1.0, true)
    draw_circle(head + Vector2(u * 0.36, u * 0.02), u * 0.08, skin.darkened(0.05), true, -1.0, true)
    draw_circle(head, u * 0.36, skin, true, -1.0, true)
    var hair := PackedVector2Array()
    for i in 13:
        var a := PI + PI * i / 12.0
        hair.append(head + Vector2(cos(a) * u * 0.38, sin(a) * u * 0.29 - u * 0.1))
    _fill(hair, Color(0.22, 0.16, 0.12))
    var eye := Color(0.15, 0.1, 0.08)
    for sx in [-1.0, 1.0]:
        draw_circle(head + Vector2(sx * u * 0.13, u * 0.0), u * 0.045, eye, true, -1.0, true)
        draw_circle(head + Vector2(sx * u * 0.21, u * 0.11), u * 0.06, Color(1, 0.45, 0.45, 0.35), true, -1.0, true)
    if role == "landlord":  # moustache
        for sx in [-1.0, 1.0]:
            _fill(_ellipse(head + Vector2(sx * u * 0.08, u * 0.13), u * 0.09, u * 0.035, 12),
                    Color(0.25, 0.15, 0.1))
    draw_arc(head + Vector2(0, u * 0.12), u * 0.1, 0.2 * PI, 0.8 * PI, 10, Color(0.6, 0.2, 0.15), 1.6, true)

    if role == "landlord":
        var gold := Color(1, 0.8, 0.12)
        var c := head + Vector2(0, -u * 0.42)
        var pts := PackedVector2Array()
        for p in [Vector2(-0.36, 0.06), Vector2(-0.4, -0.28), Vector2(-0.18, -0.1), Vector2(0, -0.36),
                Vector2(0.18, -0.1), Vector2(0.4, -0.28), Vector2(0.36, 0.06)]:
            pts.append(c + p * u)
        _fill(pts, gold)
        draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.72, 0.42, 0.05), 1.2, true)
        for p in [Vector2(-0.4, -0.28), Vector2(0, -0.36), Vector2(0.4, -0.28)]:
            draw_circle(c + p * u, u * 0.055, gold, true, -1.0, true)
        draw_circle(c + Vector2(0, -u * 0.04), u * 0.06, Color(0.85, 0.1, 0.12), true, -1.0, true)
    elif role == "farmer":
        var straw := Color(0.95, 0.78, 0.4)
        var c := head + Vector2(0, -u * 0.2)
        _fill(_ellipse(c, u * 0.6, u * 0.12, 24), straw.darkened(0.08))
        var dome := PackedVector2Array()
        for i in 13:
            var a := PI + PI * i / 12.0
            dome.append(c + Vector2(cos(a) * u * 0.3, sin(a) * u * 0.32))
        _fill(dome, straw)
        draw_line(c + Vector2(-u * 0.3, -u * 0.05), c + Vector2(u * 0.3, -u * 0.05), Color(0.8, 0.22, 0.16), 3.0)

    draw_circle(o, R, ring, false, 2.5, true)

## Filled polygon with an anti-aliased edge (draw_colored_polygon alone is jaggy).
func _fill(pts: PackedVector2Array, color: Color) -> void:
    draw_colored_polygon(pts, color)
    draw_polyline(pts + PackedVector2Array([pts[0]]), color, 1.0, true)

func _ellipse(c: Vector2, rx: float, ry: float, n := 24) -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in n:
        var a := TAU * i / n
        pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
    return pts
