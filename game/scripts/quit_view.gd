class_name QuitView
extends Modal
## 退出游戏？: asked when the system wants the game closed (Android back, the window's close
## button). Mid-game it says the game in hand is lost.

var _warn: Label

func _build() -> void:
    box.add_child(title("退出游戏？"))
    _warn = Label.new()
    _warn.text = "放弃当前牌局，本局不计分"
    _warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _warn.add_theme_font_size_override("font_size", 26)
    box.add_child(_warn)
    var choice := HBoxContainer.new()
    choice.add_theme_constant_override("separation", 20)
    choice.add_child(button("取消", &"GrayButton", close))
    choice.add_child(button("退出", &"PrimaryButton", func(): get_tree().quit()))
    box.add_child(choice)

## `in_game`: warn that the game in hand will not be scored.
func open(in_game: bool) -> void:
    _warn.visible = in_game
    popup()
