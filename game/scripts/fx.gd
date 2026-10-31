class_name Fx
extends Control
## Full-screen, click-through effects layer: big move-type banners, particle bursts,
## screen flashes and edge glows, confetti and cards flying across the table.

const ROCKET := preload("res://art/fx/rocket.png")
const ROCKET_FLAME := preload("res://art/fx/rocket_flame.png")

var _spark: GradientTexture2D

func _ready() -> void:
    _spark = GradientTexture2D.new()
    _spark.width = 32
    _spark.height = 32
    _spark.fill = GradientTexture2D.FILL_RADIAL
    _spark.fill_from = Vector2(0.5, 0.5)
    _spark.fill_to = Vector2(1.0, 0.5)
    _spark.gradient = _ramp([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

## Big outlined text that slams in at `at` (default: screen centre) and fades away.
func banner(text: String, color: Color, at := Vector2(-1, -1), font_size := 72,
        hold := 0.7) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_font_override("font", UiTheme.bold)
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", color.darkened(0.7))
    l.add_theme_constant_override("outline_size", font_size / 6)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
    l.add_theme_constant_override("shadow_offset_y", 5)
    add_child(l)
    l.reset_size()
    if at.x < 0:
        at = size / 2 - Vector2(0, 40)
    l.position = at - l.size / 2
    l.pivot_offset = l.size / 2
    l.scale = Vector2(2.4, 2.4)
    l.modulate.a = 0.0
    var t := l.create_tween()
    t.set_parallel()
    t.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_property(l, "modulate:a", 1.0, 0.15)
    t.chain().tween_interval(hold)
    t.chain().tween_property(l, "modulate:a", 0.0, 0.35)
    t.parallel().tween_property(l, "position:y", l.position.y - 30, 0.35)
    t.chain().tween_callback(l.queue_free)

## Text that streaks across the screen from right to left (飞机, 顺子 …).
func streak(text: String, color: Color, y: float) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_font_override("font", UiTheme.bold)
    l.add_theme_font_size_override("font_size", 64)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", color.darkened(0.7))
    l.add_theme_constant_override("outline_size", 10)
    add_child(l)
    l.reset_size()
    l.position = Vector2(size.x + 20, y - l.size.y / 2)
    var mid := (size.x - l.size.x) / 2
    var t := l.create_tween()
    t.tween_property(l, "position:x", mid, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    t.tween_interval(0.45)
    t.tween_property(l, "position:x", -l.size.x - 20, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
    t.tween_callback(l.queue_free)
    var tail := _trail(color)
    tail.position = Vector2(l.size.x, l.size.y / 2)
    l.add_child(tail)

## One-shot spray of sparks; `glow` adds a flash where they start.
func burst(at: Vector2, colors: Array, amount := 60, speed := 420.0, glow := true) -> void:
    var p := CPUParticles2D.new()
    p.position = at
    p.one_shot = true
    p.emitting = false
    p.amount = amount
    p.lifetime = 0.9
    p.explosiveness = 0.95
    p.spread = 180.0
    p.direction = Vector2(0, -1)
    p.initial_velocity_min = speed * 0.08
    p.initial_velocity_max = speed
    p.gravity = Vector2(0, 500)
    p.damping_min = 60
    p.damping_max = 160
    p.texture = _spark
    p.scale_amount_min = 0.35
    p.scale_amount_max = 1.1
    p.scale_amount_curve = _shrink()
    p.color_ramp = _ramp(colors)
    add_child(p)
    p.emitting = true
    p.finished.connect(p.queue_free)
    if not glow:
        return
    var flare := Sprite2D.new()
    flare.texture = _spark
    flare.position = at
    flare.modulate = Color(colors[0], 0.9)
    flare.scale = Vector2(2, 2)
    add_child(flare)
    var t := flare.create_tween().set_parallel()
    t.tween_property(flare, "scale", Vector2(9, 9), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    t.tween_property(flare, "modulate:a", 0.0, 0.35)
    t.chain().tween_callback(flare.queue_free)

## Expanding shock-wave circle (bombs).
func ring(at: Vector2, color: Color, radius := 260.0, duration := 0.5) -> void:
    var c := Control.new()
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    c.position = at
    add_child(c)
    var draw_at := func(k: float):
        c.set_meta("k", k)
        c.queue_redraw()
    c.draw.connect(func():
        var k: float = c.get_meta("k", 0.0)
        c.draw_arc(Vector2.ZERO, radius * k, 0, TAU, 64, Color(color, 1.0 - k), 4.0 + 18.0 * (1.0 - k), true))
    var t := c.create_tween()
    t.tween_method(draw_at, 0.05, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    t.tween_callback(c.queue_free)

## Coloured paper raining down over the whole screen.
func confetti() -> void:
    var p := CPUParticles2D.new()
    p.position = Vector2(size.x / 2, -20)
    p.one_shot = true
    p.emitting = false
    p.amount = 160
    p.lifetime = 3.0
    p.explosiveness = 0.6
    p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
    p.emission_rect_extents = Vector2(size.x / 2, 10)
    p.direction = Vector2(0, 1)
    p.spread = 25.0
    p.initial_velocity_min = 120
    p.initial_velocity_max = 320
    p.gravity = Vector2(0, 160)
    p.angular_velocity_min = -360
    p.angular_velocity_max = 360
    p.angle_min = 0
    p.angle_max = 360
    p.scale_amount_min = 6.0
    p.scale_amount_max = 11.0
    p.color_initial_ramp = _ramp([Color(1, 0.3, 0.3), Color(1, 0.8, 0.2), Color(0.4, 0.9, 0.4),
            Color(0.3, 0.7, 1), Color(0.8, 0.45, 1), Color(1, 0.5, 0.8)])
    add_child(p)
    p.emitting = true
    p.finished.connect(p.queue_free)

func flash(color := Color(1, 1, 1, 0.7), duration := 0.35) -> void:
    var r := ColorRect.new()
    r.color = color
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(r)
    var t := r.create_tween()
    t.tween_property(r, "modulate:a", 0.0, duration)
    t.tween_callback(r.queue_free)

## The screen's edges glow `color` for a moment, the middle left clear (绝杀).
func edge_glow(color: Color, hold := 0.5) -> void:
    var r := ColorRect.new()
    r.material = ShaderMaterial.new()
    r.material.shader = load("res://shaders/edge_glow.gdshader")
    r.material.set_shader_parameter("tint", color)
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    r.modulate.a = 0.0
    add_child(r)
    var t := r.create_tween()
    t.tween_property(r, "modulate:a", 1.0, 0.15)
    t.tween_interval(hold)
    t.tween_property(r, "modulate:a", 0.0, 0.9)
    t.tween_callback(r.queue_free)

## Missile for 王炸: launches from `from` (the seat that played it), climbs off the top
## of the screen, then drops nose-first onto the middle of the table and explodes.
## `on_impact` runs at the explosion, for the banner and screen shake.
func missile(from: Vector2, on_impact: Callable) -> void:
    const SIZE := 0.26  # rocket.png is drawn at 2x; this makes it ~145px tall
    var target := Vector2(size.x / 2, size.y / 2 - 30)
    var r := Node2D.new()
    r.position = from
    r.scale = Vector2.ZERO
    add_child(r)
    var flame := Sprite2D.new()
    flame.texture = ROCKET_FLAME
    flame.centered = false
    flame.offset = Vector2(-ROCKET_FLAME.get_width() / 2.0, 0)
    flame.position = Vector2(0, 200)
    r.add_child(flame)
    var body := Sprite2D.new()
    body.texture = ROCKET
    r.add_child(body)
    var smoke := _trail(Color(1, 0.55, 0.1))
    smoke.direction = Vector2(0, 1)
    smoke.spread = 14.0
    smoke.emission_rect_extents = Vector2(6, 2)
    smoke.position = Vector2(0, 420)
    smoke.scale = Vector2.ONE / SIZE
    smoke.scale_amount_max = 1.2
    smoke.color_ramp = _ramp([Color(1, 1, 0.8), Color(1, 0.55, 0.1), Color(0.6, 0.6, 0.6, 0.5), Color(0.6, 0.6, 0.6, 0)])
    r.add_child(smoke)
    var power := [0.8]
    var flicker := flame.create_tween().set_loops()
    flicker.tween_callback(func():
        flame.scale = Vector2(randf_range(0.9, 1.05), randf_range(0.8, 1.15)) * power[0]
        flame.modulate.a = randf_range(0.85, 1.0)).set_delay(0.04)

    # climb: a curve up and slightly towards the middle, out past the top edge
    var exit := Vector2(lerpf(from.x, size.x / 2, 0.35), -260)
    var ctrl := Vector2(from.x, lerpf(from.y, exit.y, 0.6))
    var climb := func(k: float):
        var a := from.lerp(ctrl, k)
        var b := ctrl.lerp(exit, k)
        r.position = a.lerp(b, k)
        r.rotation = (b - a).angle() + PI / 2
    climb.call(0.0)
    var t := r.create_tween()
    t.tween_property(r, "scale", Vector2(SIZE, SIZE), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_callback(func(): power[0] = 1.6)
    t.tween_method(climb, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    t.tween_callback(func(): smoke.emitting = false)
    t.tween_interval(0.35)
    # dive: straight down onto the table, nose first
    t.tween_callback(func():
        r.position = Vector2(target.x, -260)
        r.rotation = PI
        smoke.emitting = true)
    t.tween_property(r, "position", target, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    t.tween_callback(func():
        smoke.emitting = false
        flicker.kill()
        body.hide()
        flame.hide()
        burst(target, [Color(1, 1, 0.8), Color(1, 0.75, 0.2), Color(1, 0.2, 0.1, 0)], 160, 700)
        ring(target, Color(1, 0.85, 0.4), 420, 0.6)
        flash(Color(1, 0.9, 0.6, 0.35), 0.3)
        on_impact.call())
    t.tween_interval(0.6)
    t.tween_callback(r.queue_free)

## Airplane for 飞机: flies right to left across the table towing a banner with `text`.
func plane(text: String, color: Color, y: float) -> void:
    var p := Node2D.new()
    p.draw.connect(_draw_plane.bind(p, color))
    p.scale = Vector2(1.4, 1.4)
    add_child(p)
    var l := Label.new()
    l.text = text
    l.add_theme_font_override("font", UiTheme.bold)
    l.add_theme_font_size_override("font_size", 40)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", color.darkened(0.7))
    l.add_theme_constant_override("outline_size", 7)
    p.add_child(l)
    l.reset_size()
    l.position = Vector2(84, -l.size.y / 2)
    var trail := _trail(Color(1, 1, 1))
    trail.position = Vector2(54, -2)
    trail.emission_rect_extents = Vector2(2, 3)
    trail.color_ramp = _ramp([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
    p.add_child(trail)
    var span := 120.0 + l.size.x * 1.4
    p.position = Vector2(size.x + 90, y + 30)
    var t := p.create_tween()
    t.tween_property(p, "position", Vector2(-span, y - 50), 1.6) \
            .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    t.parallel().tween_property(p, "rotation", 0.06, 1.6)
    t.tween_callback(p.queue_free)

func _draw_plane(p: Node2D, color: Color) -> void:
    var body := Color(0.97, 0.97, 1)
    var dark := color.darkened(0.3)
    p.draw_line(Vector2(54, 0), Vector2(84, 0), Color(1, 1, 1, 0.7), 1.5, true)  # tow rope
    _fill(p, [Vector2(-6, -6), Vector2(8, -6), Vector2(22, -22), Vector2(14, -23)], dark)
    _fill(p, [Vector2(34, -9), Vector2(46, -30), Vector2(55, -30), Vector2(52, -6)], color)
    _fill(p, [Vector2(-54, 0), Vector2(-48, -8), Vector2(-36, -11), Vector2(38, -10),
            Vector2(52, -6), Vector2(54, 0), Vector2(50, 6), Vector2(-36, 9), Vector2(-48, 7)], body)
    _fill(p, [Vector2(-50, 3), Vector2(50, 3), Vector2(50, 6), Vector2(-36, 9), Vector2(-48, 7)], color)
    _fill(p, [Vector2(-46, -5), Vector2(-38, -8), Vector2(-34, -3), Vector2(-44, -1)], Color(0.25, 0.5, 0.85))
    for x in range(-28, 30, 8):
        p.draw_circle(Vector2(x, -3), 2.0, Color(0.3, 0.55, 0.85), true, -1.0, true)
    _fill(p, [Vector2(36, 0), Vector2(48, 0), Vector2(58, 10), Vector2(52, 10)], color)
    _fill(p, [Vector2(-12, 2), Vector2(8, 2), Vector2(30, 26), Vector2(20, 27)], color)

## Filled polygon with an anti-aliased edge, drawn on `ci`.
func _fill(ci: CanvasItem, pts: Array, color: Color) -> void:
    var packed := PackedVector2Array(pts)
    ci.draw_colored_polygon(packed, color)
    packed.append(packed[0])
    ci.draw_polyline(packed, color, 1.0, true)

## Card backs flying from `from` to `to`, one after another (dealing to the AIs).
func fly_backs(from: Vector2, to: Vector2, count: int, gap: float) -> void:
    for i in count:
        var c := CardView.make(-1, false, 0.5)
        c.position = from - c.size / 2
        c.modulate.a = 0.0
        add_child(c)
        var t := c.create_tween()
        t.tween_interval(i * gap)
        t.tween_property(c, "modulate:a", 1.0, 0.05)
        t.tween_property(c, "position", to - c.size / 2, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        t.parallel().tween_property(c, "rotation", randf_range(-0.4, 0.4), 0.3)
        t.tween_property(c, "modulate:a", 0.0, 0.1)
        t.tween_callback(c.queue_free)

## Face-up cards (the bottom cards) gliding to a seat and shrinking away.
func fly_cards(ids: Array, from: Array, to: Vector2, scale_factor: float) -> void:
    for i in ids.size():
        var c := CardView.make(int(ids[i]), true, scale_factor)
        c.position = from[i]
        add_child(c)
        var t := c.create_tween()
        t.tween_interval(0.5 + i * 0.08)
        t.tween_property(c, "position", to - c.size / 2, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
        t.parallel().tween_property(c, "scale", Vector2(0.5, 0.5), 0.4)
        t.tween_property(c, "modulate:a", 0.0, 0.1)
        t.tween_callback(c.queue_free)

## Sparks streaming off whatever node this gets parented to (world-space particles).
func _trail(color: Color) -> CPUParticles2D:
    var p := CPUParticles2D.new()
    p.local_coords = false
    p.amount = 90
    p.lifetime = 0.45
    p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
    p.emission_rect_extents = Vector2(4, 22)
    p.direction = Vector2(1, 0)
    p.spread = 8.0
    p.initial_velocity_min = 60
    p.initial_velocity_max = 220
    p.texture = _spark
    p.scale_amount_min = 0.3
    p.scale_amount_max = 0.7
    p.scale_amount_curve = _shrink()
    p.color_ramp = _ramp([Color.WHITE, color, Color(color, 0)])
    return p

func _shrink() -> Curve:
    var c := Curve.new()
    c.add_point(Vector2(0, 1))
    c.add_point(Vector2(1, 0.1))
    return c

func _ramp(colors: Array) -> Gradient:
    var offsets := PackedFloat32Array()
    for i in colors.size():
        offsets.append(float(i) / max(1, colors.size() - 1))
    var g := Gradient.new()
    g.offsets = offsets
    g.colors = PackedColorArray(colors)
    return g
