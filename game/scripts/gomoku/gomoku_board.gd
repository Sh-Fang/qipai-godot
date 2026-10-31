class_name GomokuBoard
extends Control
## The 15×15 board, drawn in code: wood, grid, star points and shaded stones. A tap
## near an intersection emits `cell_pressed`. New stones drop in, taken-back ones fade
## out; the last move gets a red dot, the 提示 a pulsing ring and the winning five a
## glowing line.

signal cell_pressed(x: int, y: int)

const N := 15
const STARS := [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7)]
const WOOD := Color(0.87, 0.69, 0.43)
const INK := Color(0.27, 0.16, 0.07, 0.85)

var interactive := false
var hint := Vector2i(-1, -1)
var _cells: Array = []  # 225 ints: 0 empty, 1 black, 2 white
var _last := Vector2i(-1, -1)
var _line: Array[Vector2i] = []
var _drops := {}  # cell index -> seconds since it was placed
var _fading := {}  # cell index -> [color, seconds since it was taken back]
var _t := 0.0

func _ready() -> void:
    _cells.resize(N * N)
    _cells.fill(0)

## Show a new position; stones that appeared drop in, stones that went fade away.
func show_position(cells: Array, last, line: Array) -> void:
    for i in N * N:
        var was := int(_cells[i]) if i < _cells.size() else 0
        var now := int(cells[i])
        if now != 0 and was == 0:
            _drops[i] = 0.0
        elif now == 0 and was != 0:
            _fading[i] = [was, 0.0]
    _cells = cells.duplicate()
    _last = Vector2i(int(last[0]), int(last[1])) if last is Array else Vector2i(-1, -1)
    _line.clear()
    for p in line:
        _line.append(Vector2i(int(p[0]), int(p[1])))
    if hint.x >= 0 and int(cells[hint.y * N + hint.x]) != 0:  # someone played there
        hint = Vector2i(-1, -1)
    queue_redraw()

func step_size() -> float:
    return size.x / N

## Centre of the intersection (x, y), in local coordinates.
func cell_center(x: int, y: int) -> Vector2:
    var s := step_size()
    return Vector2((x + 0.5) * s, (y + 0.5) * s)

func _process(delta: float) -> void:
    _t += delta
    for k in _drops.keys():
        _drops[k] += delta
        if _drops[k] > 0.3:
            _drops.erase(k)
    for k in _fading.keys():
        _fading[k][1] += delta
        if _fading[k][1] > 0.3:
            _fading.erase(k)
    if not _drops.is_empty() or not _fading.is_empty() or hint.x >= 0 or not _line.is_empty():
        queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if not (interactive and event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var s := step_size()
    var x := int(floor(event.position.x / s))
    var y := int(floor(event.position.y / s))
    if x >= 0 and x < N and y >= 0 and y < N:
        accept_event()
        cell_pressed.emit(x, y)

func _draw() -> void:
    var s := step_size()
    var wood := StyleBoxFlat.new()
    wood.bg_color = WOOD
    wood.set_corner_radius_all(int(s * 0.3))
    wood.shadow_color = Color(0, 0, 0, 0.45)
    wood.shadow_size = int(s * 0.5)
    wood.shadow_offset = Vector2(0, s * 0.15)
    wood.anti_aliasing = true
    draw_style_box(wood, Rect2(Vector2.ZERO, size))
    for i in 9:  # faint grain streaks across the board
        var y := size.y * (0.08 + i * 0.11 + 0.02 * sin(i * 2.3))
        draw_line(Vector2(0, y), Vector2(size.x, y + s * 0.3 * sin(i)), Color(0.6, 0.4, 0.2, 0.08), s * 0.25)

    var a := cell_center(0, 0)
    var b := cell_center(N - 1, N - 1)
    for i in N:
        var w := 3.0 if i == 0 or i == N - 1 else 1.6
        var c := cell_center(i, i)
        draw_line(Vector2(c.x, a.y), Vector2(c.x, b.y), INK, w, true)
        draw_line(Vector2(a.x, c.y), Vector2(b.x, c.y), INK, w, true)
    for p in STARS:
        draw_circle(cell_center(p.x, p.y), s * 0.12, INK, true, -1.0, true)

    var r := s * 0.45
    for k in _fading:
        var f: Array = _fading[k]
        _stone(cell_center(k % N, k / N), r, f[0], 1.0 - f[1] / 0.3)
    for i in N * N:
        var color := int(_cells[i])
        if color == 0:
            continue
        var grow := 1.0
        if _drops.has(i):  # drops in from a bit above, slightly larger
            grow = 1.0 + 0.25 * (1.0 - ease(_drops[i] / 0.3, 0.4))
        _stone(cell_center(i % N, i / N), r * grow, color, 1.0)
    if _last.x >= 0:
        draw_circle(cell_center(_last.x, _last.y), r * 0.22, Color(0.9, 0.15, 0.1), true, -1.0, true)

    if hint.x >= 0:
        var pulse := 0.5 + 0.5 * sin(_t * 6.0)
        var c := cell_center(hint.x, hint.y)
        draw_circle(c, r * (1.0 + 0.15 * pulse), Color(1, 0.82, 0.3, 0.35 + 0.3 * pulse), false, 4.0, true)
        draw_circle(c, r * 0.3, Color(1, 0.82, 0.3, 0.8), true, -1.0, true)

    if _line.size() >= 2:
        var glow := 0.6 + 0.4 * sin(_t * 5.0)
        var from := cell_center(_line[0].x, _line[0].y)
        var to := cell_center(_line[-1].x, _line[-1].y)
        draw_line(from, to, Color(1, 0.82, 0.3, 0.35 * glow), r * 1.1, true)
        draw_line(from, to, Color(1, 0.9, 0.5, 0.9 * glow), r * 0.25, true)
        for p in _line:
            draw_circle(cell_center(p.x, p.y), r * 1.05, Color(1, 0.85, 0.35, glow), false, 3.0, true)

## A stone with a drop shadow and a soft highlight towards the top-left.
func _stone(at: Vector2, r: float, color: int, alpha: float) -> void:
    draw_circle(at + Vector2(r * 0.08, r * 0.14), r, Color(0, 0, 0, 0.35 * alpha), true, -1.0, true)
    var edge := Color(0.04, 0.04, 0.06) if color == 1 else Color(0.78, 0.77, 0.74)
    var shine := Color(0.42, 0.42, 0.46) if color == 1 else Color(1, 1, 1)
    edge.a = alpha
    shine.a = alpha
    draw_circle(at, r, edge, true, -1.0, true)
    for i in 5:  # layered discs fake a radial gradient
        var k := 1.0 - (i + 1) / 6.0
        draw_circle(at - Vector2(r, r) * 0.18 * (1.0 - k), r * k, edge.lerp(shine, (i + 1) / 6.0), true, -1.0, true)
