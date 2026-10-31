class_name MatchSetupView
extends Modal
## 难度 and side for 五子棋 / 象棋, opened from the tag at the top of the table.
## 开始新局 starts over with the choice; while a game is under way, what that costs is
## shown above the button. A tap outside keeps the current game.

signal confirmed(level: int, side: int)

const LEVEL_NAMES := ["简单", "普通", "困难"]

var _levels: Array[Button] = []
var _sides: Array[Button] = []
var _side_values: Array = []
var _side_row: HBoxContainer
var _note: Label

func _build() -> void:
    box.add_child(title("对局设置"))
    var level_row := _row("难度")
    for i in LEVEL_NAMES.size():
        _levels.append(_option(level_row, LEVEL_NAMES[i], _levels))
    _side_row = _row("执子")
    _note = Label.new()
    _note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _note.add_theme_font_size_override("font_size", 24)
    box.add_child(_note)
    box.add_child(button("开始新局", &"PrimaryButton", func():
        close()
        confirmed.emit(_picked(_levels), _side_values[_picked(_sides)])))

## The sides on offer, e.g. [["执黑", 1], ["执白", 2]]. Call once before open().
func set_sides(sides: Array) -> void:
    for s in sides:
        _sides.append(_option(_side_row, s[0], _sides))
        _side_values.append(s[1])

## `note`: what starting over costs ("" when no game is under way).
func open(level: int, side: int, note: String) -> void:
    _select(_levels, level)
    _select(_sides, maxi(_side_values.find(side), 0))
    _note.text = note
    _note.visible = note != ""
    popup()

func _row(label: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    var l := Label.new()
    l.text = label
    l.custom_minimum_size.x = 90
    l.add_theme_font_size_override("font_size", 30)
    row.add_child(l)
    box.add_child(row)
    return row

## One choice in a row: the picked one is orange, the others gray.
func _option(row: HBoxContainer, text: String, group: Array[Button]) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(130, 68)
    b.focus_mode = Control.FOCUS_NONE
    b.theme_type_variation = &"GrayButton"
    b.pressed.connect(func():
        Sfx.play("click")
        _select(group, group.find(b)))
    row.add_child(b)
    return b

func _select(group: Array[Button], index: int) -> void:
    for i in group.size():
        group[i].theme_type_variation = &"PrimaryButton" if i == index else &"GrayButton"
        group[i].set_meta("picked", i == index)

func _picked(group: Array[Button]) -> int:
    for i in group.size():
        if group[i].get_meta("picked", false):
            return i
    return 0
