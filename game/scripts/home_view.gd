class_name HomeView
extends Control
## Home screen. While the core loads it shows just the title on the felt with a
## progress bar; once loaded (`loaded()`), the bar fades and a fan of cards, the start
## button (below where the bar was) and the player's score come in. Uses art/home/bg.png and art/home/title.png
## when they exist (see docs/art-prompts.md), otherwise draws its own.

signal start_pressed
signal score_pressed

const BG := "res://art/home/bg.png"
const TITLE := "res://art/home/title.png"

var _score: Label
var _start: Button
var _bar: ProgressBar
var _fan: Control

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    var fill := ColorRect.new()  # opaque base, so nothing of the table shows through
    fill.color = Color(0.07, 0.29, 0.18)
    fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(fill)
    if ResourceLoader.exists(BG):
        var bg := TextureRect.new()
        bg.texture = load(BG)
        bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(bg)
    else:  # the felt table on its own, slightly darkened, hiding the table UI behind
        var felt := ColorRect.new()
        felt.material = ShaderMaterial.new()
        felt.material.shader = load("res://shaders/table.gdshader")
        felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(felt)
        var shade := ColorRect.new()
        shade.color = Color(0, 0, 0, 0.2)
        shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(shade)
        _fan = Control.new()
        _fan.set_anchors_preset(Control.PRESET_CENTER)
        _fan.position.y += 40
        _fan.hide()
        add_child(_fan)
        var ids := [53, 52, 47, 46, 45, 44]
        for i in ids.size():
            var c := CardView.make(ids[i], true, 1.3)
            c.pivot_offset = Vector2(c.size.x / 2, c.size.y * 1.6)
            c.position = -c.size / 2
            c.rotation = (i - (ids.size() - 1) / 2.0) * 0.16
            _fan.add_child(c)

    var box := VBoxContainer.new()
    box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 18)
    add_child(box)

    if ResourceLoader.exists(TITLE):
        var title := TextureRect.new()
        title.texture = load(TITLE)
        title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        title.custom_minimum_size = Vector2(0, 220)
        box.add_child(title)
    else:
        var title := Label.new()
        title.text = "斗 地 主"
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.add_theme_font_override("font", UiTheme.bold)
        title.add_theme_font_size_override("font_size", 120)
        title.add_theme_color_override("font_color", UiTheme.GOLD)
        title.add_theme_color_override("font_outline_color", Color(0.45, 0.08, 0.05))
        title.add_theme_constant_override("outline_size", 22)
        title.add_theme_constant_override("shadow_offset_y", 8)
        box.add_child(title)

    var gap := Control.new()
    gap.custom_minimum_size = Vector2(0, 180 if not ResourceLoader.exists(BG) else 60)
    box.add_child(gap)

    var slot := CenterContainer.new()  # keeps its room after the bar fades, so nothing moves
    slot.custom_minimum_size = Vector2(0, 30)
    box.add_child(slot)
    _bar = ProgressBar.new()
    _bar.show_percentage = false
    _bar.max_value = 1.0
    _bar.custom_minimum_size = Vector2(440, 18)
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0, 0, 0, 0.45)
    track.border_color = Color(1, 0.85, 0.45, 0.35)
    track.set_border_width_all(2)
    track.set_corner_radius_all(9)
    var bar_fill := StyleBoxFlat.new()
    bar_fill.bg_color = UiTheme.GOLD
    bar_fill.set_corner_radius_all(9)
    _bar.add_theme_stylebox_override("background", track)
    _bar.add_theme_stylebox_override("fill", bar_fill)
    _bar.accessibility_name = "加载中"
    slot.add_child(_bar)
    _start = Button.new()
    _start.text = "开始游戏"
    _start.theme_type_variation = &"PrimaryButton"
    _start.custom_minimum_size = Vector2(300, 88)
    _start.add_theme_font_size_override("font_size", 38)
    _start.focus_mode = Control.FOCUS_NONE
    _start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _start.pressed.connect(_on_start)
    _start.disabled = true  # invisible until loaded, and not pressable either
    _start.modulate.a = 0.0
    box.add_child(_start)

    _score = Label.new()
    _score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _score.add_theme_font_override("font", UiTheme.bold)
    _score.add_theme_font_size_override("font_size", 28)
    _score.add_theme_color_override("font_color", UiTheme.GOLD)
    _score.mouse_filter = Control.MOUSE_FILTER_STOP
    _score.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
            score_pressed.emit())
    _score.modulate.a = 0.0  # keeps its space, so nothing shifts when it appears
    box.add_child(_score)

    # the start button breathes gently so it reads as the thing to press

func set_progress(value: float) -> void:
    _bar.value = value

## The core is ready: fill the bar, then bring in the fan, the start button and the score.
func loaded(score: int) -> void:
    set_score(score)
    var t := create_tween()
    t.tween_property(_bar, "value", 1.0, 0.15)
    t.tween_property(_bar, "modulate:a", 0.0, 0.2)
    t.tween_callback(func():
        _start.disabled = false
        _breathe()
        for n in [_fan, _start, _score]:
            if n:
                n.show()
                n.modulate.a = 0.0
                n.create_tween().tween_property(n, "modulate:a", 1.0, 0.3))

## The start button swells gently about its centre so it reads as the thing to press.
func _breathe() -> void:
    _start.pivot_offset = _start.size / 2
    _start.resized.connect(func(): _start.pivot_offset = _start.size / 2)
    var t := _start.create_tween().set_loops()
    t.tween_property(_start, "scale", Vector2(1.06, 1.06), 0.7).set_trans(Tween.TRANS_SINE)
    t.tween_property(_start, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)

func set_score(score: int) -> void:
    _score.text = "积分 %d ›" % score

func _on_start() -> void:
    Sfx.play("click")
    _start.disabled = true
    var t := create_tween()
    t.tween_property(self, "modulate:a", 0.0, 0.3)
    t.tween_callback(func():
        hide()
        modulate.a = 1.0
        _start.disabled = false
        start_pressed.emit())
