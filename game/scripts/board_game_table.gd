class_name BoardGameTable
extends Control
## What 五子棋 and 象棋 share. A board in the middle of a wooden table; on the left the
## 战绩 (top, beside 返回) and the two players, the one to move lit up; on the right the
## 难度 · 执子 tag (top) and 悔棋 / 提示, or 再来一局 once the game is over. The AI moves
## after a short pause (only for feel). 对局设置, 战绩 and the result panel; 难度, side
## and 战绩 kept in the save under the game's own section. Hosted by the app
## (scripts/app.gd).
##
## Rules and AI live in the core, as "<prefix>_new / _play / _step / _undo / _hint"
## commands (see README). A table overrides the hooks in the "for the table" section.

signal leave_requested

## AI 思考时间 (seconds, random in range): only for feel, the move is decided instantly.
const THINK := Vector2(0.35, 0.9)
const OUTCOME_COLUMN := {"win": 0, "lose": 1, "draw": 2}

var state := {}
var board: Control
var _level := 0
var _human := 0  # the side value sent to the core, one of _sides()
var _record: Array = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]  # per 难度: 胜, 负, 和
var _game := 0  # bumped by every new game, so an AI turn left over from the last one stops
var _busy := false  # a request (or the AI's turn) is under way

var _record_pill: Label
var _chip: Button
var _ai_card: PlayerCard
var _me_card: PlayerCard
var _undo: Button
var _hint: Button
var _again: Button
var _fx: Fx
var _setup: MatchSetupView
var _records: RecordView
var _result: ResultView

# ---- for the table (override) ---------------------------------------------------

## Command prefix and save section: "gomoku".
func _prefix() -> String:
    return ""

## Sides on offer, first one the default: [["执黑", 1], ["执白", 2]].
func _sides() -> Array:
    return []

## The board node; placed and sized by the table, keeping `_board_aspect()`.
func _make_board() -> Control:
    return Control.new()

func _board_aspect() -> float:  # width / height
    return 1.0

## Draw the current state on the board.
func _render_board() -> void:
    pass

## Whether the core's state says it is the human's move.
func _human_to_move() -> bool:
    return false

## Sounds and effects for a move event, the human's or the AI's.
func _on_moved(_event: Dictionary) -> void:
    pass

## Show the core's 提示.
func _show_hint(_hint) -> void:
    pass

## A finished game, for the human: "win", "lose" or "draw".
func _outcome() -> String:
    return "draw"

## Extra line on the result panel ("" for none).
func _result_detail() -> String:
    return ""

## The stone or piece standing for `side` on a player card.
func _draw_side(_canvas: CanvasItem, _center: Vector2, _radius: float, _side) -> void:
    pass

## The side value of the AI, given the human's.
func _other_side(side):
    for s in _sides():
        if s[1] != side:
            return s[1]

# ---- building -------------------------------------------------------------------

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _human = _sides()[0][1]
    var bg := ColorRect.new()
    bg.material = ShaderMaterial.new()
    bg.material.shader = load("res://shaders/wood.gdshader")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)
    board = _make_board()
    add_child(board)

    _record_pill = Label.new()
    _record_pill.theme_type_variation = &"Pill"
    _record_pill.add_theme_color_override("font_color", UiTheme.GOLD)
    _record_pill.mouse_filter = Control.MOUSE_FILTER_STOP
    _record_pill.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
            Sfx.play("click")
            _records.open(_record, _level))
    add_child(_record_pill)
    _chip = Button.new()
    _chip.theme_type_variation = &"GrayButton"
    _chip.focus_mode = Control.FOCUS_NONE
    _chip.custom_minimum_size = Vector2(0, 64)
    _chip.pressed.connect(func():
        Sfx.play("click")
        _setup.open(_level, _human, forfeit_note() if in_progress() else ""))
    add_child(_chip)
    _ai_card = PlayerCard.new()
    _ai_card.title = "电脑"
    _ai_card.draw_side = _draw_side
    add_child(_ai_card)
    _me_card = PlayerCard.new()
    _me_card.title = "我"
    _me_card.draw_side = _draw_side
    add_child(_me_card)
    _undo = _action("悔棋", &"GrayButton", _on_undo)
    _hint = _action("提示", &"BlueButton", _on_hint)
    _again = _action("再来一局", &"PrimaryButton", func():
        Sfx.play("click")
        _new_game())

    _fx = Fx.new()
    add_child(_fx)
    _setup = MatchSetupView.new()
    add_child(_setup)
    _setup.set_sides(_sides())
    _setup.confirmed.connect(func(level: int, side):
        _level = level
        _human = side
        _save()
        _new_game())
    _records = RecordView.new()
    add_child(_records)
    _result = ResultView.new()
    _result.again.connect(_new_game)
    _result.leave.connect(func(): leave_requested.emit())
    add_child(_result)

    _load_save()
    resized.connect(_layout)
    _layout()

func _action(text: String, variation: StringName, action: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.theme_type_variation = variation
    b.focus_mode = Control.FOCUS_NONE
    b.pressed.connect(action)
    UiTheme.juicy(b)
    add_child(b)
    return b

## Board in the middle, as tall as the screen allows; the side columns share the rest.
func _layout() -> void:
    var e := App.edge
    var h := size.y - 32 - e.y - e.w
    var w := h * _board_aspect()
    board.size = Vector2(w, h)
    board.position = Vector2((size.x - w) / 2, e.y + 16)
    var left := Rect2(e.x + 16, e.y + 12, board.position.x - e.x - 40, size.y - e.y - e.w - 24)
    var right := Rect2(board.position.x + w + 24, e.y + 12, 0, left.size.y)
    right.size.x = size.x - e.z - 16 - right.position.x

    _record_pill.position = left.position + Vector2(RoundButton.SIZE.x + 12, 12)
    _record_pill.size = Vector2(minf(220, left.size.x - RoundButton.SIZE.x - 12), 40)
    var card := Vector2(minf(260, left.size.x), 96)
    var cx := left.position.x + (left.size.x - card.x) / 2
    _ai_card.position = Vector2(cx, size.y / 2 - card.y - 20)
    _ai_card.size = card
    _me_card.position = Vector2(cx, size.y / 2 + 20)
    _me_card.size = card

    # the tag sits left of the gear, in the corner row
    var chip_w := minf(240, right.size.x - RoundButton.SIZE.x - 12)
    _chip.size = Vector2(chip_w, 64)
    _chip.position = Vector2(right.end.x - RoundButton.SIZE.x - 12 - chip_w, right.position.y)
    var bw := minf(240, right.size.x)
    var bx := right.position.x + (right.size.x - bw) / 2
    var bottom := right.end.y
    _hint.size = Vector2(bw, 78)
    _hint.position = Vector2(bx, bottom - 78)
    _undo.size = Vector2(bw, 78)
    _undo.position = Vector2(bx, bottom - 78 - 20 - 78)
    _again.size = Vector2(bw, 78)
    _again.position = _hint.position

# ---- what the app calls (see scripts/app.gd) ----------------------------------

func start() -> void:
    _new_game()

func restart() -> void:
    _new_game()

func in_progress() -> bool:
    return state.get("phase") == "playing" and int(state.get("move_count", 0)) > 0

func forfeit_note() -> String:
    return "放弃当前对局，本局不计战绩"

# ---- game flow ----------------------------------------------------------------

func _new_game() -> void:
    _game += 1
    _busy = false
    _show_hint(null)
    _apply(await Core.request(_prefix() + "_new", {"human": _human, "level": _level}))
    if _ai_to_move():
        _ai_turn()

func _apply(reply: Dictionary) -> bool:
    if reply.is_empty():
        return false
    state = reply["state"]
    _render()
    if not reply.get("ok", false):
        Sfx.play("error")
        return false
    return true

func _my_turn() -> bool:
    return not _busy and state.get("phase") == "playing" and _human_to_move()

func _ai_to_move() -> bool:
    return state.get("phase") == "playing" and not _human_to_move()

## The human's move (`args` for <prefix>_play), then the AI's answer.
func _play(args: Dictionary) -> void:
    if not _my_turn():
        return
    _busy = true
    _show_hint(null)
    var game := _game
    var reply := await Core.request(_prefix() + "_play", args)
    if game != _game:
        return
    _busy = false
    if not _apply(reply):
        return
    _on_moved(reply["event"])
    if state["phase"] == "over":
        _finish()
    else:
        _ai_turn()

func _ai_turn() -> void:
    var game := _game
    _busy = true
    _render()
    await get_tree().create_timer(randf_range(THINK.x, THINK.y), false).timeout
    if game != _game:
        return
    var reply := await Core.request(_prefix() + "_step")
    if game != _game:
        return
    _busy = false
    if not _apply(reply):
        return
    _on_moved(reply["event"])
    if state["phase"] == "over":
        _finish()

func _on_undo() -> void:
    if not _my_turn() or not state["can_undo"]:
        return
    Sfx.play("kenney/chips-collide-1")
    _show_hint(null)
    _apply(await Core.request(_prefix() + "_undo"))

func _on_hint() -> void:
    if not _my_turn():
        return
    Sfx.play("click")
    _busy = true
    var game := _game
    var reply := await Core.request(_prefix() + "_hint")
    if game != _game:
        return
    _busy = false
    if _apply(reply):
        _show_hint(reply["hint"])

## Game over: count it in the 战绩 (a 困难 win helped by 悔棋 / 提示 doesn't count),
## let the final position show a moment, then the result panel.
func _finish() -> void:
    var outcome := _outcome()
    var counted: bool = not (outcome == "win" and _level == 2 and state["assisted"])
    if counted:
        _record[_level][OUTCOME_COLUMN[outcome]] += 1
        _save()
    _render()
    var game := _game
    await get_tree().create_timer(1.4, false).timeout
    if game != _game:
        return
    Sfx.play("win" if outcome == "win" else "lose")
    if outcome == "win":
        _fx.confetti()
    var detail := _result_detail()
    if not counted:
        detail = "用过悔棋或提示，不计入困难胜局"
    _result.show_result(outcome, detail)

# ---- rendering ----------------------------------------------------------------

func _render() -> void:
    if state.is_empty():
        return
    _render_board()
    var over: bool = state["phase"] == "over"
    _ai_card.side = _other_side(_human)
    _me_card.side = _human
    _ai_card.active = not over and not _human_to_move()
    _me_card.active = not over and _human_to_move()
    _undo.visible = not over
    _hint.visible = not over
    _again.visible = over
    _undo.disabled = not (_my_turn() and state["can_undo"])
    _hint.disabled = not _my_turn()
    var side_name := ""
    for s in _sides():
        if s[1] == _human:
            side_name = s[0]
    _chip.text = "%s · %s ›" % [MatchSetupView.LEVEL_NAMES[_level], side_name]
    var r: Array = _record[_level]
    _record_pill.text = "%d胜 %d负%s ›" % [r[0], r[1], " %d和" % r[2] if r[2] > 0 else ""]

# ---- persistence --------------------------------------------------------------

func _load_save() -> void:
    _level = int(Save.value(_prefix(), "level", 0))
    var side = Save.value(_prefix(), "human", _human)
    for s in _sides():
        if s[1] == side:
            _human = side
    var saved = Save.value(_prefix(), "record", null)
    if saved is Array and saved.size() == 3:
        _record = saved

func _save() -> void:
    Save.store(_prefix(), "level", _level)
    Save.store(_prefix(), "human", _human)
    Save.store(_prefix(), "record", _record)

## One player beside the board: their stone or piece and name, lit up while it's their move.
class PlayerCard extends Control:
    var title := ""
    var draw_side: Callable  # (canvas, centre, radius, side), from the table
    var side = null:
        set(v):
            side = v
            queue_redraw()
    var active := false:
        set(v):
            active = v
            queue_redraw()
    var _t := 0.0

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE

    func _process(delta: float) -> void:
        if active:
            _t += delta
            queue_redraw()

    func _draw() -> void:
        var panel := StyleBoxFlat.new()
        panel.bg_color = Color(0, 0, 0, 0.35)
        panel.set_corner_radius_all(22)
        panel.anti_aliasing = true
        if active:
            panel.border_color = UiTheme.GOLD
            panel.set_border_width_all(4)
            panel.shadow_color = Color(1, 0.82, 0.3, 0.25 + 0.15 * sin(_t * 4.0))
            panel.shadow_size = 16
        draw_style_box(panel, Rect2(Vector2.ZERO, size))
        if side != null:
            draw_side.call(self, Vector2(size.y / 2, size.y / 2), size.y * 0.3, side)
        var font := UiTheme.bold
        var fs := 34
        var baseline := size.y / 2 + (font.get_ascent(fs) - font.get_descent(fs)) / 2
        draw_string(font, Vector2(size.y, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
                Color.WHITE if active else Color(1, 1, 1, 0.75))
