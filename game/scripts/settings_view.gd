class_name SettingsView
extends Modal
## 设置: the gear in the top-right corner opens this panel and pauses the game.
## 继续游戏 or a tap outside closes it. 重新开始 (in a game) asks again first.

signal sound_changed(on: bool)
signal music_changed(on: bool)
signal restart_confirmed

var _main: VBoxContainer
var _confirm: VBoxContainer
var _restart: Button
var _note: Label
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
    _note = Label.new()
    _note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _note.add_theme_font_size_override("font_size", 26)
    _confirm.add_child(_note)
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

## `in_game`: offer 重新开始 (not in the 大厅, where there is no game to restart).
## `note`: what restarting loses, shown when asking again ("" when nothing is lost).
func open(sound_on: bool, music_on: bool, in_game: bool, note: String) -> void:
    _sound.set_on(sound_on)
    _music.set_on(music_on)
    _restart.visible = in_game
    _note.text = note
    _note.visible = note != ""
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
