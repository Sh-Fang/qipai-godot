extends BoardGameTable
## 象棋 table (the shared parts are in scripts/board_game_table.gd). Tap one of your
## pieces to pick it up (its moves show on the board), then a dot to move there. A check
## gets a 将军 stamp, a mate 绝杀.

const RED := 0
const BLACK := 1
const REASONS := {"长将": "长将判负"}

func _prefix() -> String:
    return "xiangqi"

func _sides() -> Array:
    return [["执红", RED], ["执黑", BLACK]]

func _board_aspect() -> float:
    return XiangqiBoard.ASPECT

func _make_board() -> Control:
    var b := XiangqiBoard.new()
    b.square_pressed.connect(_on_square)
    return b

func _human_to_move() -> bool:
    return state["to_move"] == ("red" if _human == RED else "black")

func _render_board() -> void:
    board.flipped = _human == BLACK
    board.show_position(state["board"], state["last"], state["in_check"], state["to_move"])
    board.interactive = _my_turn()

func _mine(letter: String) -> bool:
    return letter != "" and (letter == letter.to_upper()) == (_human == RED)

func _on_square(x: int, y: int) -> void:
    if not _my_turn():
        return
    var here := Vector2i(x, y)
    if board.selected.x >= 0 and here in board.targets:
        _play({"move": [board.selected.x, board.selected.y, x, y]})
        return
    board.targets.clear()
    if _mine(state["board"][y * 9 + x]) and here != board.selected:
        board.selected = here
        for m in state["legal"]:
            if int(m[0]) == x and int(m[1]) == y:
                board.targets.append(Vector2i(int(m[2]), int(m[3])))
        Sfx.play("click")
    else:
        board.selected = Vector2i(-1, -1)
    board.queue_redraw()

func _on_moved(event: Dictionary) -> void:
    if event.get("captured", "") != "":
        Sfx.play("kenney/chips-collide-1")
    else:
        Sfx.play("kenney/chip-lay-%d" % randi_range(1, 3))
    if state["phase"] == "over" and state["reason"] == "将死":
        _fx.banner("绝杀", XiangqiBoard.RED_INK.lightened(0.25), Vector2(-1, -1), 120, 0.9)
    elif event.get("check", false):
        _fx.banner("将军", XiangqiBoard.RED_INK.lightened(0.25), Vector2(-1, -1), 96, 0.6)

func _show_hint(hint) -> void:
    board.hint = hint if hint is Array else []
    board.queue_redraw()

func _outcome() -> String:
    if state["winner"] == "draw":
        return "draw"
    return "win" if state["human_won"] else "lose"

func _result_detail() -> String:
    return REASONS.get(state["reason"], state["reason"])

func _draw_side(canvas: CanvasItem, c: Vector2, r: float, side) -> void:
    XiangqiBoard.draw_piece(canvas, c, r, "K" if side == RED else "k")
