class_name LobbyView
extends Control
## 大厅. While the core loads it shows just the title on the felt with a progress bar;
## once loaded (`loaded()`), the bar fades and one card per game comes in below where it
## was. Tapping a card fades the lobby out and emits `game_chosen`. Games not built yet
## show dimmed and can't be opened.

signal game_chosen(id: String)

## id, name, in the order the cards are laid out.
const GAMES := [["doudizhu", "斗地主"], ["gomoku", "五子棋"], ["xiangqi", "象棋"]]

var _bar: ProgressBar
var _slot: CenterContainer
var _cards: HBoxContainer

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    var felt := ColorRect.new()
    felt.material = ShaderMaterial.new()
    felt.material.shader = load("res://shaders/table.gdshader")
    felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    var shade := ColorRect.new()
    shade.color = Color(0, 0, 0, 0.25)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(shade)

    var box := VBoxContainer.new()
    box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 26)
    add_child(box)

    var title := Label.new()
    title.text = "棋 牌 合 集"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_override("font", UiTheme.bold)
    title.add_theme_font_size_override("font_size", 96)
    title.add_theme_color_override("font_color", UiTheme.GOLD)
    title.add_theme_color_override("font_outline_color", Color(0.45, 0.08, 0.05))
    title.add_theme_constant_override("outline_size", 20)
    title.add_theme_constant_override("shadow_offset_y", 8)
    box.add_child(title)

    _slot = CenterContainer.new()  # keeps its room after the bar fades, so nothing moves
    _slot.custom_minimum_size = Vector2(0, 30)
    box.add_child(_slot)
    _bar = ProgressBar.new()
    _bar.show_percentage = false
    _bar.max_value = 1.0
    _bar.custom_minimum_size = Vector2(440, 18)
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0, 0, 0, 0.45)
    track.border_color = Color(1, 0.85, 0.45, 0.35)
    track.set_border_width_all(2)
    track.set_corner_radius_all(9)
    var bar_fill := StyleBoxFlat.new()
    bar_fill.bg_color = UiTheme.GOLD
    bar_fill.set_corner_radius_all(9)
    _bar.add_theme_stylebox_override("background", track)
    _bar.add_theme_stylebox_override("fill", bar_fill)
    _bar.accessibility_name = "加载中"
    _slot.add_child(_bar)

    _cards = HBoxContainer.new()
    _cards.alignment = BoxContainer.ALIGNMENT_CENTER
    _cards.add_theme_constant_override("separation", 40)
    box.add_child(_cards)
    for g in GAMES:
        var card := GameCard.new()
        card.id = g[0]
        card.title = g[1]
        card.accessibility_name = g[1]
        card.modulate.a = 0.0  # keeps its space, so nothing shifts when the cards appear
        card.disabled = true
        card.pressed.connect(_choose.bind(card))
        _cards.add_child(card)

func set_progress(value: float) -> void:
    _bar.value = value

## The core is ready: fill the bar, fade it, then bring the cards in one after another.
## `available`: ids of the games that can be opened.
func loaded(available: Array) -> void:
    var t := create_tween()
    t.tween_property(_bar, "value", 1.0, 0.15)
    t.tween_property(_bar, "modulate:a", 0.0, 0.2)
    t.tween_callback(func():
        var i := 0
        for card: GameCard in _cards.get_children():
            card.ready_to_play = available.has(card.id)
            card.disabled = not card.ready_to_play
            card.scale = Vector2(0.85, 0.85)
            var ct := card.create_tween().set_parallel()
            ct.tween_property(card, "modulate:a", 1.0 if card.ready_to_play else 0.5, 0.3).set_delay(i * 0.08)
            ct.tween_property(card, "scale", Vector2.ONE, 0.35).set_delay(i * 0.08) \
                    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
            i += 1)

## Loading failed: say why where the bar was.
func fail(text: String) -> void:
    _bar.hide()
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", 26)
    _slot.add_child(l)

## Back from a game: fade in again.
func reopen() -> void:
    show()
    modulate.a = 0.0
    create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
    for card: GameCard in _cards.get_children():
        card.disabled = not card.ready_to_play

## Open a game as if its card were tapped (autotest).
func choose(id: String) -> void:
    for card: GameCard in _cards.get_children():
        if card.id == id:
            _choose(card)

func _choose(card: GameCard) -> void:
    Sfx.play("click")
    for c: GameCard in _cards.get_children():
        c.disabled = true
    var t := create_tween()
    t.tween_property(self, "modulate:a", 0.0, 0.3)
    t.tween_callback(func():
        hide()
        modulate.a = 1.0
        game_chosen.emit(card.id))

## One game in the lobby: a framed panel with the game's emblem and its name, drawn in
## code (斗地主 a fan of cards, 五子棋 a diagonal five on a board, 象棋 a 帅 piece).
class GameCard extends Button:
    const SIZE := Vector2(300, 330)
    const NAME_SIZE := 44
    const SOON_SIZE := 22

    var id := ""
    var title := ""
    var ready_to_play := true

    func _init() -> void:
        custom_minimum_size = SIZE
        flat = true
        focus_mode = Control.FOCUS_NONE
        resized.connect(func(): pivot_offset = size / 2)
        button_down.connect(func(): create_tween().tween_property(self, "scale", Vector2(0.94, 0.94), 0.06))
        button_up.connect(func():
            create_tween().tween_property(self, "scale", Vector2.ONE, 0.2) \
                    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

    func _ready() -> void:
        if id == "doudizhu":  # real cards, so the emblem matches the table
            var fan := Control.new()
            fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
            fan.position = Vector2(SIZE.x / 2, 128)
            add_child(fan)
            var ids := [53, 51, 47]
            for i in ids.size():
                var c := CardView.make(ids[i], true, 1.05)
                c.mouse_filter = Control.MOUSE_FILTER_IGNORE
                c.pivot_offset = Vector2(c.size.x / 2, c.size.y * 1.4)
                c.position = -c.size / 2
                c.rotation = (i - 1) * 0.26
                fan.add_child(c)

    func _draw() -> void:
        var panel := StyleBoxFlat.new()
        panel.bg_color = Color(0.1, 0.11, 0.16, 0.92 if not is_hovered() else 0.97)
        panel.border_color = UiTheme.GOLD
        panel.set_border_width_all(4)
        panel.set_corner_radius_all(26)
        panel.shadow_color = Color(0, 0, 0, 0.45)
        panel.shadow_size = 18
        panel.anti_aliasing = true
        draw_style_box(panel, Rect2(Vector2.ZERO, size))
        var c := Vector2(size.x / 2, 128)
        match id:
            "gomoku": _draw_gomoku(c)
            "xiangqi": _draw_xiangqi(c)
        var font := UiTheme.bold
        var y := size.y - 44.0 if ready_to_play else size.y - 62.0
        draw_string(font, Vector2(0, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, NAME_SIZE, Color.WHITE)
        if not ready_to_play:
            draw_string(UiTheme.font, Vector2(0, size.y - 24), "敬请期待", HORIZONTAL_ALIGNMENT_CENTER,
                    size.x, SOON_SIZE, Color(1, 1, 1, 0.6))

    func _draw_gomoku(c: Vector2) -> void:
        var half := 86.0
        var board := StyleBoxFlat.new()
        board.bg_color = Color(0.86, 0.68, 0.42)
        board.set_corner_radius_all(10)
        board.anti_aliasing = true
        draw_style_box(board, Rect2(c - Vector2(half, half), Vector2(half, half) * 2))
        var step := half * 2 / 6
        var line := Color(0.35, 0.22, 0.1, 0.8)
        for i in range(1, 6):
            var o := -half + i * step
            draw_line(c + Vector2(o, -half + step * 0.5), c + Vector2(o, half - step * 0.5), line, 2.0)
            draw_line(c + Vector2(-half + step * 0.5, o), c + Vector2(half - step * 0.5, o), line, 2.0)
        var r := step * 0.42
        for p in [Vector2i(1, 4), Vector2i(4, 2), Vector2i(2, 1)]:  # white stones around the five
            _stone(c + Vector2(-half + p.x * step, -half + p.y * step), r, false)
        for i in range(1, 6):
            _stone(c + Vector2(-half + i * step, -half + (6 - i) * step), r, true)

    func _stone(at: Vector2, r: float, black: bool) -> void:
        draw_circle(at + Vector2(1.5, 2.5), r, Color(0, 0, 0, 0.35), true, -1.0, true)
        draw_circle(at, r, Color(0.08, 0.08, 0.1) if black else Color(0.95, 0.94, 0.9), true, -1.0, true)
        draw_circle(at - Vector2(r, r) * 0.32, r * 0.3,
                Color(1, 1, 1, 0.35 if black else 0.8), true, -1.0, true)

    func _draw_xiangqi(c: Vector2) -> void:
        XiangqiBoard.draw_piece(self, c, 76.0, "K")
