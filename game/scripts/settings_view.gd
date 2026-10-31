class_name SettingsView
extends Modal
## 设置: the gear button in the top-right corner opens this panel and pauses the game.
## 继续游戏 or a tap outside closes it. 重新开始 asks again before abandoning the game.

signal sound_changed(on: bool)
signal music_changed(on: bool)
signal restart_confirmed

var _main: VBoxContainer
var _confirm: VBoxContainer
var _restart: Button
var _sound: Switch
var _music: Switch

func _build() -> void:
    _main = VBoxContainer.new()
    _main.add_theme_constant_override("separation", 22)
    box.add_child(_main)
    _main.add_child(title("设置"))
    _sound = _row("音效")
    _sound.toggled.connect(func(on: bool): sound_changed.emit(on))
    _music = _row("音乐")
    _music.toggled.connect(func(on: bool): music_changed.emit(on))
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 20)
    _restart = button("重新开始", &"GrayButton", _ask_restart)
    buttons.add_child(_restart)
    buttons.add_child(button("继续游戏", &"PrimaryButton", close))
    _main.add_child(buttons)

    _confirm = VBoxContainer.new()
    _confirm.add_theme_constant_override("separation", 22)
    _confirm.hide()
    box.add_child(_confirm)
    _confirm.add_child(title("重新开始？"))
    var warn := Label.new()
    warn.text = "放弃当前牌局，本局不计分"
    warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    warn.add_theme_font_size_override("font_size", 26)
    _confirm.add_child(warn)
    var choice := HBoxContainer.new()
    choice.add_theme_constant_override("separation", 20)
    choice.add_child(button("取消", &"GrayButton", _cancel_restart))
    choice.add_child(button("重新开始", &"PrimaryButton", func():
        close()
        restart_confirmed.emit()))
    _confirm.add_child(choice)

func _row(text: String) -> Switch:
    var row := HBoxContainer.new()
    var label := Label.new()
    label.text = text
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", 30)
    row.add_child(label)
    var sw := Switch.new()
    sw.accessibility_name = text
    row.add_child(sw)
    _main.add_child(row)
    return sw

## `in_game`: offer 重新开始 (not on the home screen, where there is no game to restart).
func open(sound_on: bool, music_on: bool, in_game: bool) -> void:
    _sound.set_on(sound_on)
    _music.set_on(music_on)
    _restart.visible = in_game
    _main.show()
    _confirm.hide()
    popup()

func _ask_restart() -> void:
    Sfx.play("click")
    _main.hide()
    _confirm.show()
    relayout()

func _cancel_restart() -> void:
    Sfx.play("click")
    _confirm.hide()
    _main.show()
    relayout()

## The gear for the top-right corner.
static func make_button() -> Button:
    var b := Gear.new()
    b.accessibility_name = "设置"
    b.custom_minimum_size = Vector2(64, 64)
    b.focus_mode = Control.FOCUS_NONE
    b.flat = true
    return b

## Round dark button with a gear drawn on it.
class Gear extends Button:
    func _draw() -> void:
        var c := size / 2
        var r := minf(size.x, size.y) / 2
        draw_circle(c, r, Color(0, 0, 0, 0.45 if not is_hovered() else 0.6), true, -1.0, true)
        draw_circle(c, r, Color(1, 1, 1, 0.18), false, 2.0, true)
        var teeth := PackedVector2Array()
        for i in 32:  # 8 teeth, each a flat top and a flat gap
            var a: float = TAU * (i / 4) / 8.0 + [-0.2, -0.13, 0.13, 0.2][i % 4]
            var rr := r * (0.62 if i % 4 in [1, 2] else 0.46)
            teeth.append(c + Vector2(cos(a), sin(a)) * rr)
        draw_colored_polygon(teeth, UiTheme.GOLD)
        draw_polyline(teeth + PackedVector2Array([teeth[0]]), UiTheme.GOLD, 1.0, true)
        draw_circle(c, r * 0.2, Color(0.12, 0.13, 0.18), true, -1.0, true)

## On/off switch: a pill track with a knob that slides across.
class Switch extends Button:
    const W := 92.0
    const H := 50.0
    var _t := 0.0

    func _init() -> void:
        toggle_mode = true
        flat = true
        focus_mode = Control.FOCUS_NONE
        custom_minimum_size = Vector2(W, H)
        size_flags_vertical = Control.SIZE_SHRINK_CENTER
        toggled.connect(func(on: bool):
            Sfx.play("click")
            create_tween().tween_method(_slide, _t, 1.0 if on else 0.0, 0.15))

    func set_on(on: bool) -> void:
        set_pressed_no_signal(on)
        _slide(1.0 if on else 0.0)

    func _slide(t: float) -> void:
        _t = t
        queue_redraw()

    func _draw() -> void:
        var track := StyleBoxFlat.new()
        track.bg_color = Color(0.4, 0.44, 0.5).lerp(UiTheme.ORANGE, _t)
        track.set_corner_radius_all(int(H / 2))
        track.anti_aliasing = true
        draw_style_box(track, Rect2(Vector2.ZERO, Vector2(W, H)))
        var r := H / 2 - 5
        draw_circle(Vector2(lerpf(H / 2, W - H / 2, _t), H / 2), r, Color.WHITE, true, -1.0, true)
