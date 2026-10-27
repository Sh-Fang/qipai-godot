class_name CardView
extends Control
## One playing card. Card ids match the core: 0..51 = rank*4 + suit, 52 小王, 53 大王.

signal pressed(card: CardView)

const SIZE := Vector2(72, 100)
const RANKS := ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
const SUITS := ["♠", "♥", "♣", "♦"]
const RED := Color(0.82, 0.1, 0.12)
const BLACK := Color(0.1, 0.1, 0.12)

var card_id := -1
var face_up := true
var selected := false
var base_y := 0.0

var _panel: Panel
var _corner: Label
var _center: Label

## Display order: biggest rank on the left (大王, 小王, 2, A, ... 3), suits ♠♥♣♦ within a rank.
static func sort_for_display(ids: Array) -> Array:
    var out := []
    for id in ids:
        out.append(int(id))
    out.sort_custom(func(a: int, b: int) -> bool:
        var ra := a if a >= 52 else a / 4
        var rb := b if b >= 52 else b / 4
        return ra > rb if ra != rb else a < b)
    return out

static func make(id: int, up := true, scale_factor := 1.0) -> CardView:
    var c := CardView.new()
    c.card_id = id
    c.face_up = up
    c.custom_minimum_size = SIZE * scale_factor
    c.size = SIZE * scale_factor
    return c

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    pivot_offset = size / 2
    _panel = Panel.new()
    _panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_panel)
    var k := size.x / SIZE.x
    _corner = _label(int(20 * k), Vector2(6, 2) * k)
    _center = _label(int(34 * k), Vector2(0, 0))
    _center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _center.position.y = 8 * k
    _center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _refresh()

func _label(font_size: int, pos: Vector2) -> Label:
    var l := Label.new()
    l.position = pos
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_size_override("font_size", font_size)
    _panel.add_child(l)
    return l

func set_face_up(up: bool) -> void:
    face_up = up
    if is_node_ready():
        _refresh()

func _refresh() -> void:
    var style := StyleBoxFlat.new()
    style.set_corner_radius_all(7)
    style.set_border_width_all(2)
    if not face_up:
        style.bg_color = Color(0.2, 0.33, 0.62)
        style.border_color = Color(0.92, 0.92, 0.95)
        _corner.text = ""
        _center.text = "◆"
        _center.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
    else:
        style.bg_color = Color(1, 0.99, 0.95) if not selected else Color(1, 0.95, 0.7)
        style.border_color = Color(0.25, 0.25, 0.3) if not selected else Color(0.95, 0.6, 0.1)
        var color := BLACK
        if card_id == 52:
            _corner.text = "小\n王"
            _center.text = "☆"
        elif card_id == 53:
            _corner.text = "大\n王"
            _center.text = "★"
            color = RED
        else:
            var suit := card_id % 4
            _corner.text = RANKS[card_id / 4] + "\n" + SUITS[suit]
            _center.text = SUITS[suit]
            color = RED if suit == 1 or suit == 3 else BLACK
        _corner.add_theme_color_override("font_color", color)
        _center.add_theme_color_override("font_color", color)
    _panel.add_theme_stylebox_override("panel", style)

func set_selected(value: bool) -> void:
    if selected == value:
        return
    selected = value
    _refresh()
    var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    t.tween_property(self, "position:y", base_y - (22.0 if selected else 0.0), 0.12)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit(self)
        accept_event()
