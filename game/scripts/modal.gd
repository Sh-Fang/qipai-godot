class_name Modal
extends Control
## A centred panel over a dimmed table that pauses the game while it is open.
## A tap outside the panel closes it. Subclasses fill `box` in `_build()`.

signal closed

var box: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hide()

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed:
            close())
    add_child(dim)

    _panel = PanelContainer.new()
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.1, 0.11, 0.16, 0.97)
    style.border_color = Color(0.95, 0.75, 0.3)
    style.set_border_width_all(4)
    style.set_corner_radius_all(22)
    style.content_margin_left = 44
    style.content_margin_right = 44
    style.content_margin_top = 24
    style.content_margin_bottom = 30
    style.shadow_color = Color(0, 0, 0, 0.5)
    style.shadow_size = 24
    _panel.add_theme_stylebox_override("panel", style)
    _panel.custom_minimum_size = Vector2(440, 0)
    add_child(_panel)

    box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 22)
    _panel.add_child(box)
    _build()

func _build() -> void:
    pass

## Pause the game and pop the panel in.
func popup() -> void:
    get_tree().paused = true
    show()
    relayout()
    _panel.scale = Vector2(0.8, 0.8)
    _panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.25) \
            .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Re-centre after the content changed size.
func relayout() -> void:
    _panel.reset_size()
    await get_tree().process_frame  # let the panel size itself first
    _panel.position = (size - _panel.size) / 2
    _panel.pivot_offset = _panel.size / 2

func close() -> void:
    if not visible:
        return
    Sfx.play("click")
    hide()
    get_tree().paused = false
    closed.emit()

func title(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", UiTheme.bold)
    l.add_theme_font_size_override("font_size", 40)
    l.add_theme_color_override("font_color", UiTheme.GOLD)
    return l

func button(text: String, variation: StringName, action: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.theme_type_variation = variation
    b.custom_minimum_size = Vector2(0, 76)
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.focus_mode = Control.FOCUS_NONE
    b.pressed.connect(action)
    return b
