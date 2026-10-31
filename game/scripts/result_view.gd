class_name ResultView
extends Modal
## End of a 五子棋 / 象棋 game: 胜利, 失败 or 和棋, then 再来一局 or 返回大厅. A tap
## outside closes it to look at the final position (the table keeps a 再来一局 button).

signal again
signal leave

var _title: Label
var _detail: Label

func _build() -> void:
    _title = Label.new()
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _title.add_theme_font_override("font", UiTheme.bold)
    _title.add_theme_font_size_override("font_size", 72)
    box.add_child(_title)
    _detail = Label.new()
    _detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _detail.add_theme_font_size_override("font_size", 24)
    _detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
    box.add_child(_detail)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 20)
    buttons.add_child(button("返回大厅", &"GrayButton", func():
        close()
        leave.emit()))
    buttons.add_child(button("再来一局", &"PrimaryButton", func():
        close()
        again.emit()))
    box.add_child(buttons)

## `outcome`: "win", "lose" or "draw". `detail`: an extra line, "" for none.
func show_result(outcome: String, detail := "") -> void:
    _title.text = {"win": "胜 利", "lose": "失 败", "draw": "和 棋"}[outcome]
    _title.add_theme_color_override("font_color",
            {"win": Color(1, 0.84, 0.3), "lose": Color(0.65, 0.75, 0.9), "draw": Color.WHITE}[outcome])
    _detail.text = detail
    _detail.visible = detail != ""
    popup()
