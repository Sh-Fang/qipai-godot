class_name GomokuBoard
extends Control
## The 15×15 board, drawn in code: wood, grid, star points and shaded stones. Pressing
## shows a see-through stone where it would go (with guide lines, as a finger hides it);
## dragging moves it, letting go places it (`cell_pressed`). With a mouse it also follows
## the pointer. New stones drop in with a ripple, taken-back ones fade out; the last move
## gets a red dot, the 提示 a pulsing ring, a threat (`warn()`) red flashes, and the
## winning five lights up stone by stone along a glowing line.

signal cell_pressed(x: int, y: int)

const N := 15
const STARS := [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7)]
const WOOD := Color(0.87, 0.69, 0.43)
const INK := Color(0.27, 0.16, 0.07, 0.85)
const DROP_TIME := 0.3
const RIPPLE_TIME := 0.45
const WARN_TIME := 1.5
## The winning five: lighting starts this long after the last stone, one stone per step.
const LINE_DELAY := 0.15
const LINE_STEP := 0.12

var interactive := false:
    set(v):
        interactive = v
        if not v:
            _preview = Vector2i(-1, -1)
            _pressing = false
var preview_color := 1  # the stone the player would place
var hint := Vector2i(-1, -1)
var _cells: Array = []  # 225 ints: 0 empty, 1 black, 2 white
var _last := Vector2i(-1, -1)
var _line: Array[Vector2i] = []
var _drops := {}  # cell index -> seconds since it was placed
var _fading := {}  # cell index -> [color, seconds since it was taken back]
var _preview := Vector2i(-1, -1)
var _pressing := false
var _warn: Array[Vector2i] = []
var _warn_t := 0.0
var _line_t := 0.0  # seconds since the five appeared
var _t := 0.0

func _ready() -> void:
    _cells.resize(N * N)
    _cells.fill(0)
    mouse_exited.connect(func():
        if not _pressing:
            _preview = Vector2i(-1, -1)
            queue_redraw())

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
    if _line.is_empty() and not line.is_empty():
        _line_t = 0.0
    _line.clear()
    for p in line:
        _line.append(Vector2i(int(p[0]), int(p[1])))
    if hint.x >= 0 and int(cells[hint.y * N + hint.x]) != 0:  # someone played there
        hint = Vector2i(-1, -1)
    _warn.clear()
    queue_redraw()

## Flash these stones red for a moment (a four that's about to become five).
func warn(stones: Array[Vector2i]) -> void:
    _warn = stones
    _warn_t = 0.0
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
        if _drops[k] > RIPPLE_TIME:
            _drops.erase(k)
    for k in _fading.keys():
        _fading[k][1] += delta
        if _fading[k][1] > 0.3:
            _fading.erase(k)
    if not _warn.is_empty():
        _warn_t += delta
        if _warn_t > WARN_TIME:
            _warn.clear()
    _line_t += delta
    if not (_drops.is_empty() and _fading.is_empty() and _line.is_empty() and _warn.is_empty()) \
            or hint.x >= 0:
        queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if not interactive:
        return
    if event is InputEventMouseMotion:
        _preview = _free_cell(event.position)
        queue_redraw()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        accept_event()
        if event.pressed:
            _pressing = true
            _preview = _free_cell(event.position)
        elif _pressing:
            _pressing = false
            var at := _preview
            _preview = Vector2i(-1, -1)
            if at.x >= 0:
                cell_pressed.emit(at.x, at.y)
        queue_redraw()

## The empty intersection under `pos`, or (-1, -1).
func _free_cell(pos: Vector2) -> Vector2i:
    var s := step_size()
    var c := Vector2i(int(floor(pos.x / s)), int(floor(pos.y / s)))
    if c.x < 0 or c.x >= N or c.y < 0 or c.y >= N or int(_cells[c.y * N + c.x]) != 0:
        return Vector2i(-1, -1)
    return c

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
        var at := cell_center(i % N, i / N)
        if _drops.has(i):  # drops in from a bit above, slightly larger, and ripples out
            grow = 1.0 + 0.25 * (1.0 - ease(minf(_drops[i] / DROP_TIME, 1.0), 0.4))
            var k: float = _drops[i] / RIPPLE_TIME
            draw_arc(at, r * (1.0 + 1.1 * k), 0, TAU, 48, Color(0.27, 0.16, 0.07, 0.4 * (1.0 - k)), 2.5, true)
        _stone(at, r * grow, color, 1.0)
    if _last.x >= 0:
        draw_circle(cell_center(_last.x, _last.y), r * 0.22, Color(0.9, 0.15, 0.1), true, -1.0, true)

    if hint.x >= 0:
        var pulse := 0.5 + 0.5 * sin(_t * 6.0)
        var c := cell_center(hint.x, hint.y)
        draw_circle(c, r * (1.0 + 0.15 * pulse), Color(1, 0.82, 0.3, 0.35 + 0.3 * pulse), false, 4.0, true)
        draw_circle(c, r * 0.3, Color(1, 0.82, 0.3, 0.8), true, -1.0, true)

    if not _warn.is_empty():  # three red flashes
        var flash := absf(sin(_warn_t / WARN_TIME * 3.0 * PI))
        for p in _warn:
            draw_circle(cell_center(p.x, p.y), r * 1.08, Color(0.95, 0.15, 0.1, 0.9 * flash), false, 4.0, true)

    var lit := int(floor((_line_t - LINE_DELAY) / LINE_STEP)) + 1  # stones lit so far
    if _line.size() >= 2 and lit > 0:
        var glow := 0.6 + 0.4 * sin(_t * 5.0) if lit > _line.size() else 1.0
        var from := cell_center(_line[0].x, _line[0].y)
        var to := cell_center(_line[mini(lit, _line.size()) - 1].x, _line[mini(lit, _line.size()) - 1].y)
        draw_line(from, to, Color(1, 0.82, 0.3, 0.35 * glow), r * 1.1, true)
        draw_line(from, to, Color(1, 0.9, 0.5, 0.9 * glow), r * 0.25, true)
        for j in mini(lit, _line.size()):
            var pop := clampf((_line_t - LINE_DELAY - j * LINE_STEP) / 0.2, 0.0, 1.0)
            var c := cell_center(_line[j].x, _line[j].y)
            draw_circle(c, r * (1.05 + 0.35 * (1.0 - pop)), Color(1, 0.85, 0.35, glow * (0.4 + 0.6 * pop)), false, 3.0, true)

    if _preview.x >= 0:
        var c := cell_center(_preview.x, _preview.y)
        if _pressing:  # guide lines, since a finger covers the spot
            var guide := Color(1, 0.85, 0.35, 0.6)
            draw_line(Vector2(c.x, a.y), Vector2(c.x, b.y), guide, 2.0, true)
            draw_line(Vector2(a.x, c.y), Vector2(b.x, c.y), guide, 2.0, true)
        _stone(c, r, preview_color, 0.5)

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
