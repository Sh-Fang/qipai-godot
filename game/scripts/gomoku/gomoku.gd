extends BoardGameTable
## 五子棋 table (the shared parts are in scripts/board_game_table.gd): press on the board
## to see where the stone goes, let go to place it. Stones snap down with a little shake;
## at 简单 a four the AI makes flashes red; the winning five lights up and rings a bell.
## A game opens with a 木鱼.

const BLACK := 1
const WHITE := 2
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
const SPARKS := [Color(1, 0.9, 0.5), Color(1, 0.75, 0.25), Color(1, 0.6, 0.2, 0.0)]

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
    board.preview_color = _human
    board.interactive = _my_turn()

func _start_sound() -> String:
    return "guofeng/muyu"

func _undo_sound() -> String:
    return "guofeng/stone-2"

func _on_moved(_event: Dictionary) -> void:
    Sfx.play("guofeng/stone-%d" % randi_range(1, 3))
    _shake(2.0, 0.12)
    if _level == 0 and state["phase"] == "playing" and _human_to_move():
        var fours := _fours(_other_side(_human))
        if not fours.is_empty():
            board.warn(fours)
    var line: Array = state["line"]
    if line.is_empty():
        return
    var game := _game
    await get_tree().create_timer(GomokuBoard.LINE_DELAY + GomokuBoard.LINE_STEP * line.size(), false).timeout
    if game != _game:
        return
    Sfx.play("guofeng/bell")
    var mid: Vector2 = board.position + (board.cell_center(int(line[0][0]), int(line[0][1]))
            + board.cell_center(int(line[-1][0]), int(line[-1][1]))) / 2
    _fx.ring(mid, UiTheme.GOLD, 220.0, 0.6)
    if state["human_won"]:
        _fx.burst(mid, SPARKS, 50, 420.0)

## Stones of `color` that are one move from five: every run that, with one empty point
## filled, would make five or more.
func _fours(color: int) -> Array[Vector2i]:
    var n := GomokuBoard.N
    var cells: Array = state["board"]
    var out: Array[Vector2i] = []
    for y in n:
        for x in n:
            if int(cells[y * n + x]) != 0:
                continue
            for d: Vector2i in DIRS:
                var run: Array[Vector2i] = []
                for way: int in [1, -1]:
                    var p := Vector2i(x, y) + d * way
                    while p.x >= 0 and p.x < n and p.y >= 0 and p.y < n and int(cells[p.y * n + p.x]) == color:
                        run.append(p)
                        p += d * way
                if run.size() >= 4:
                    for p in run:
                        if not out.has(p):
                            out.append(p)
    return out

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
