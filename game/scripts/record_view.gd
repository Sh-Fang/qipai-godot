class_name RecordView
extends Modal
## 战绩 of 五子棋 / 象棋: wins, losses and draws for each 难度, the one being played
## highlighted.

var _grid: GridContainer

func _build() -> void:
    box.add_child(title("战绩"))
    _grid = GridContainer.new()
    _grid.columns = 4
    _grid.add_theme_constant_override("h_separation", 48)
    _grid.add_theme_constant_override("v_separation", 14)
    var center := CenterContainer.new()
    center.add_child(_grid)
    box.add_child(center)
    box.add_child(button("关闭", &"PrimaryButton", close))

## `record`: [胜, 负, 和] for 简单, 普通, 困难; `level`: the 难度 being played.
func open(record: Array, level: int) -> void:
    for child in _grid.get_children():
        child.queue_free()
    for text in ["", "胜", "负", "和"]:
        _cell(text, Color(1, 1, 1, 0.6))
    for i in 3:
        var color := UiTheme.GOLD if i == level else Color.WHITE
        _cell(MatchSetupView.LEVEL_NAMES[i], color)
        for n in record[i]:
            _cell(str(n), color)
    popup()

func _cell(text: String, color: Color) -> void:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", UiTheme.bold)
    l.add_theme_font_size_override("font_size", 32)
    l.add_theme_color_override("font_color", color)
    _grid.add_child(l)
