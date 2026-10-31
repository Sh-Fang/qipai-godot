class_name UiTheme
extends RefCounted
## Builds the game's Theme in code: one CJK system font in two weights, chunky
## pill buttons in three colour variations, and a pill style for toasts.

const ORANGE := Color(0.98, 0.58, 0.12)
const BLUE := Color(0.22, 0.56, 0.95)
const GRAY := Color(0.42, 0.47, 0.52)
const GOLD := Color(1.0, 0.82, 0.3)

static var font: Font
static var bold: Font

static func build() -> Theme:
    font = _system_font(500)
    bold = _system_font(800)
    var t := Theme.new()
    t.default_font = font
    t.default_font_size = 20

    t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
    t.set_constant("shadow_offset_x", "Label", 0)
    t.set_constant("shadow_offset_y", "Label", 2)

    _button(t, "Button", GRAY)
    _button(t, "PrimaryButton", ORANGE)
    _button(t, "BlueButton", BLUE)
    _button(t, "GrayButton", GRAY)

    t.set_type_variation("Pill", "Label")
    var pill := _box(Color(0, 0, 0, 0.6), 24)
    pill.content_margin_left = 26
    pill.content_margin_right = 26
    pill.content_margin_top = 8
    pill.content_margin_bottom = 8
    t.set_stylebox("normal", "Pill", pill)
    return t

static func _system_font(weight: int) -> SystemFont:
    var f := SystemFont.new()
    f.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC",
            "PingFang SC", "Microsoft YaHei", "sans-serif"])
    f.font_weight = weight
    return f

static func _box(color: Color, radius: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = color
    s.set_corner_radius_all(radius)
    s.anti_aliasing = true
    return s

## A raised pill: darker bottom edge as a "lip", which collapses when pressed.
static func _button(t: Theme, type: String, color: Color) -> void:
    if type != "Button":
        t.set_type_variation(type, "Button")
    var states := {
        "normal": color,
        "hover": color.lightened(0.12),
        "pressed": color.darkened(0.08),
        "focus": color,
        "disabled": Color(color.darkened(0.35), 0.55),
    }
    for state in states:
        var s := _box(states[state], 26)
        s.border_color = color.darkened(0.4)
        s.border_width_bottom = 2 if state == "pressed" else 6
        s.content_margin_left = 22
        s.content_margin_right = 22
        s.content_margin_top = 10 if state == "pressed" else 6
        s.content_margin_bottom = 4 if state == "pressed" else 8
        if state == "focus":
            s.draw_center = false
            s.border_width_bottom = 0
        else:
            s.shadow_color = Color(0, 0, 0, 0.35)
            s.shadow_size = 6
            s.shadow_offset = Vector2(0, 3)
        t.set_stylebox(state, type, s)
    t.set_font("font", type, bold)
    t.set_font_size("font_size", type, 30)
    t.set_color("font_color", type, Color.WHITE)
    t.set_color("font_hover_color", type, Color.WHITE)
    t.set_color("font_pressed_color", type, Color(1, 1, 1, 0.9))
    t.set_color("font_focus_color", type, Color.WHITE)
    t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.45))
    t.set_color("font_outline_color", type, Color(color.darkened(0.5), 0.8))
    t.set_constant("outline_size", type, 4)

## Buttons squash while held and spring back on release.
static func juicy(b: Button) -> void:
    b.resized.connect(func(): b.pivot_offset = b.size / 2)
    b.button_down.connect(func(): b.create_tween().tween_property(b, "scale", Vector2(0.92, 0.92), 0.06))
    b.button_up.connect(func():
        b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.2) \
                .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
