extends BoardGameTable
## 五子棋 table (the shared parts are in scripts/board_game_table.gd): taps on the board
## place stones, the AI's and mine click down, the winning five glows.

const BLACK := 1
const WHITE := 2

func _prefix() -> String:
    return "gomoku"

func _sides() -> Array:
    return [["执黑", BLACK], ["执白", WHITE]]

func _make_board() -> Control:
    var b := GomokuBoard.new()
    b.cell_pressed.connect(func(x: int, y: int):
        if int(state["board"][y * GomokuBoard.N + x]) == 0:
            _play({"x": x, "y": y}))
    return b

func _human_to_move() -> bool:
    return int(state["to_move"]) == _human

func _render_board() -> void:
    board.show_position(state["board"], state["last"], state["line"])
    board.interactive = _my_turn()

func _on_moved(_event: Dictionary) -> void:
    Sfx.play("kenney/chip-lay-%d" % randi_range(1, 3))

func _show_hint(hint) -> void:
    board.hint = Vector2i(int(hint[0]), int(hint[1])) if hint is Array else Vector2i(-1, -1)

func _outcome() -> String:
    if int(state["winner"]) == 3:
        return "draw"
    return "win" if state["human_won"] else "lose"

func _draw_side(canvas: CanvasItem, c: Vector2, r: float, side) -> void:
    canvas.draw_circle(c + Vector2(2, 3), r, Color(0, 0, 0, 0.4), true, -1.0, true)
    canvas.draw_circle(c, r, Color(0.06, 0.06, 0.08) if side == BLACK else Color(0.93, 0.92, 0.88), true, -1.0, true)
    canvas.draw_circle(c - Vector2(r, r) * 0.3, r * 0.3, Color(1, 1, 1, 0.3 if side == BLACK else 0.8), true, -1.0, true)
