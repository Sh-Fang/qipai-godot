class_name HistoryView
extends Modal
## 积分记录: opened by tapping the score. The current score, then one row per finished
## game, newest first: when, 地主/农民, 胜/负, 倍数 and the points won or lost.

const ROW_FONT := 24

var _score: Label
var _list: VBoxContainer
var _scroll: ScrollContainer

func _build() -> void:
    box.add_child(title("积分记录"))
    _score = Label.new()
    _score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _score.add_theme_font_override("font", UiTheme.bold)
    _score.add_theme_font_size_override("font_size", 52)
    box.add_child(_score)
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.custom_minimum_size = Vector2(560, 0)
    box.add_child(_scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _list.add_theme_constant_override("separation", 6)
    _scroll.add_child(_list)
    box.add_child(button("关闭", &"PrimaryButton", close))

## `games`: oldest first, as saved ({time, role, won, mult, delta}).
func open(score: int, games: Array) -> void:
    _score.text = str(score)
    for child in _list.get_children():
        child.queue_free()
    if games.is_empty():
        var none := Label.new()
        none.text = "还没有对局"
        none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        none.add_theme_font_size_override("font_size", ROW_FONT)
        none.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
        _list.add_child(none)
    for i in range(games.size() - 1, -1, -1):
        _list.add_child(_row(games[i]))
    # show up to about five rows, scroll for the rest
    _scroll.custom_minimum_size.y = minf(maxi(games.size(), 1) * 46.0, 5 * 46.0)
    _scroll.scroll_vertical = 0
    popup()

func _row(g: Dictionary) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 40
    row.add_theme_constant_override("separation", 18)
    var when := Time.get_datetime_dict_from_unix_time(int(g["time"]) + _tz_offset())
    _cell(row, "%02d-%02d %02d:%02d" % [when.month, when.day, when.hour, when.minute],
            Color(1, 1, 1, 0.6), 150)
    var landlord: bool = g["role"] == "landlord"
    _cell(row, "地主" if landlord else "农民", SeatView.LANDLORD if landlord else SeatView.FARMER, 60)
    _cell(row, "胜" if g["won"] else "负", Color.WHITE, 30)
    _cell(row, "×%d" % int(g["mult"]), Color(1, 1, 1, 0.75), 70)
    var delta := int(g["delta"])
    var d := _cell(row, "%+d" % delta, Color(1, 0.75, 0.25) if delta > 0 else Color(0.6, 0.85, 1), 0)
    d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    d.add_theme_font_override("font", UiTheme.bold)
    return row

func _cell(row: HBoxContainer, text: String, color: Color, width: float) -> Label:
    var l := Label.new()
    l.text = text
    l.custom_minimum_size.x = width
    l.add_theme_font_size_override("font_size", ROW_FONT)
    l.add_theme_color_override("font_color", color)
    row.add_child(l)
    return l

static func _tz_offset() -> int:
    return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
