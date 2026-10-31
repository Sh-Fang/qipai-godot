class_name ConfirmView
extends Modal
## One question before leaving: 退出游戏？ (Android back in the 大厅, the window's close
## button) or 返回大厅？ (back inside a game). `note` says what is lost, if anything.

var _title: Label
var _note: Label
var _ok: Button
var _action: Callable

func _build() -> void:
    _title = title("")
    box.add_child(_title)
    _note = Label.new()
    _note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _note.add_theme_font_size_override("font_size", 26)
    box.add_child(_note)
    var choice := HBoxContainer.new()
    choice.add_theme_constant_override("separation", 20)
    choice.add_child(button("取消", &"GrayButton", close))
    _ok = button("", &"PrimaryButton", func():
        close()
        _action.call())
    choice.add_child(_ok)
    box.add_child(choice)

func ask(question: String, ok_text: String, note: String, action: Callable) -> void:
    _title.text = question
    _ok.text = ok_text
    _note.text = note
    _note.visible = note != ""
    _action = action
    popup()
