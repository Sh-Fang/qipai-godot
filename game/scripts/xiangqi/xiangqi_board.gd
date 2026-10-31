class_name XiangqiBoard
extends Control
## The 9×10 board, drawn in code: wood, the grid with its river and palaces, the 炮 / 兵
## marks, and round wooden pieces lettered in 霞鹜文楷 (fonts/xiangqi.ttf). Shown from the
## human's side: `flipped` when they play black. A tap near an intersection emits
## `square_pressed` in board coordinates (x = file from red's left, y = rank from black's
## back rank). The picked piece lifts and its moves show as dots; the last move's two
## squares get corner marks, the 提示 pulses, a king in check glows red; moves slide.

signal square_pressed(x: int, y: int)

const FONT := "res://fonts/xiangqi.ttf"
const NAMES := {
    "K": "帅", "A": "仕", "B": "相", "N": "马", "R": "车", "C": "炮", "P": "兵",
    "k": "将", "a": "士", "b": "象", "n": "马", "r": "车", "c": "炮", "p": "卒",
}
const WOOD := Color(0.88, 0.71, 0.46)
const INK := Color(0.3, 0.16, 0.06, 0.9)
const RED_INK := Color(0.78, 0.13, 0.1)
const BLACK_INK := Color(0.14, 0.11, 0.1)
const MARKS := [Vector2i(1, 2), Vector2i(7, 2), Vector2i(1, 7), Vector2i(7, 7),
        Vector2i(0, 3), Vector2i(2, 3), Vector2i(4, 3), Vector2i(6, 3), Vector2i(8, 3),
        Vector2i(0, 6), Vector2i(2, 6), Vector2i(4, 6), Vector2i(6, 6), Vector2i(8, 6)]
const SLIDE_TIME := 0.22
## Wood left around the outermost lines, in steps, so edge pieces stay on the board.
const PAD := 0.3
const ASPECT := (9.0 + 2 * PAD) / (10.0 + 2 * PAD)

static var _font: Font

var flipped := false
var interactive := false
var selected := Vector2i(-1, -1)
var targets: Array[Vector2i] = []
var hint: Array = []  # [fx, fy, tx, ty], or empty
var _cells: Array = []  # 90 piece letters, "" for empty
var _last: Array = []
var _check := Vector2i(-1, -1)  # the king in check
var _slides := {}  # square index -> [from Vector2i, seconds]
var _fading := {}  # square index -> [piece letter, seconds]
var _t := 0.0

static func font() -> Font:
    if _font == null:
        _font = load(FONT) if ResourceLoader.exists(FONT) else UiTheme.bold
    return _font

func _ready() -> void:
    _cells.resize(90)
    _cells.fill("")

## Show a new position. A move that just happened slides its piece in; the piece it
## took fades out.
func show_position(cells: Array, last, in_check: bool, to_move: String) -> void:
    if last is Array and last != _last:
        var from := int(last[1]) * 9 + int(last[0])
        var to := int(last[3]) * 9 + int(last[2])
        if cells[to] != "" and _cells[from] == cells[to]:  # a move forward, not a 悔棋
            _slides[to] = [Vector2i(int(last[0]), int(last[1])), 0.0]
            if _cells[to] != "":
                _fading[to] = [_cells[to], 0.0]
    _cells = cells.duplicate()
    _last = last if last is Array else []
    _check = Vector2i(-1, -1)
    if in_check:
        var king := "K" if to_move == "red" else "k"
        var i := _cells.find(king)
        if i >= 0:
            _check = Vector2i(i % 9, i / 9)
    selected = Vector2i(-1, -1)
    targets.clear()
    queue_redraw()

func step_size() -> float:
    return size.y / (10.0 + 2 * PAD)

func _view(p: Vector2i) -> Vector2i:
    return Vector2i(8 - p.x, 9 - p.y) if flipped else p

## Centre of board square (x, y), in local coordinates.
func square_center(x: int, y: int) -> Vector2:
    var v := _view(Vector2i(x, y))
    var s := step_size()
    return Vector2((v.x + 0.5 + PAD) * s, (v.y + 0.5 + PAD) * s)

func _process(delta: float) -> void:
    _t += delta
    for k in _slides.keys():
        _slides[k][1] += delta
        if _slides[k][1] > SLIDE_TIME:
            _slides.erase(k)
    for k in _fading.keys():
        _fading[k][1] += delta
        if _fading[k][1] > 0.3:
            _fading.erase(k)
    if not _slides.is_empty() or not _fading.is_empty() or not hint.is_empty() or _check.x >= 0 \
            or selected.x >= 0:
        queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if not (interactive and event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var s := step_size()
    var v := Vector2i(int(floor(event.position.x / s - PAD)), int(floor(event.position.y / s - PAD)))
    if v.x < 0 or v.x > 8 or v.y < 0 or v.y > 9:
        return
    accept_event()
    var p := _view(v)  # the flip is its own inverse
    square_pressed.emit(p.x, p.y)

func _draw() -> void:
    var s := step_size()
    var wood := StyleBoxFlat.new()
    wood.bg_color = WOOD
    wood.set_corner_radius_all(int(s * 0.25))
    wood.shadow_color = Color(0, 0, 0, 0.45)
    wood.shadow_size = int(s * 0.5)
    wood.shadow_offset = Vector2(0, s * 0.15)
    wood.anti_aliasing = true
    draw_style_box(wood, Rect2(Vector2.ZERO, size))
    for i in 9:  # faint grain
        var y := size.y * (0.07 + i * 0.105 + 0.02 * sin(i * 1.7))
        draw_line(Vector2(0, y), Vector2(size.x, y + s * 0.3 * sin(i * 0.8)), Color(0.6, 0.4, 0.2, 0.08), s * 0.22)
    _draw_grid(s)
    var r := s * 0.44
    for k in _fading:
        var f: Array = _fading[k]
        draw_piece(self, _square_center_index(k), r, f[0], 1.0 - f[1] / 0.3)
    if _last.size() == 4:
        _corners(square_center(int(_last[0]), int(_last[1])), s, Color(0.15, 0.4, 0.8, 0.8))
        _corners(square_center(int(_last[2]), int(_last[3])), s, Color(0.15, 0.4, 0.8, 0.8))
    for i in 90:
        var name: String = _cells[i]
        if name == "" or Vector2i(i % 9, i / 9) == selected:
            continue
        var at := _square_center_index(i)
        if _slides.has(i):
            var from: Vector2i = _slides[i][0]
            var k := ease(_slides[i][1] / SLIDE_TIME, 0.4)
            at = square_center(from.x, from.y).lerp(at, k)
        if Vector2i(i % 9, i / 9) == _check:
            var pulse := 0.5 + 0.5 * sin(_t * 8.0)
            draw_circle(at, r * (1.12 + 0.08 * pulse), Color(1, 0.2, 0.1, 0.35 + 0.35 * pulse), true, -1.0, true)
        draw_piece(self, at, r, name)
    for t in targets:  # where the picked piece can go
        var c := square_center(t.x, t.y)
        if _cells[t.y * 9 + t.x] == "":
            draw_circle(c, s * 0.13, Color(0.12, 0.5, 0.22, 0.8), true, -1.0, true)
        else:
            draw_circle(c, r * 1.05, Color(0.9, 0.2, 0.1, 0.9), false, 4.0, true)
    if selected.x >= 0 and _cells[selected.y * 9 + selected.x] != "":  # lifted, drawn on top
        var c := square_center(selected.x, selected.y) - Vector2(0, r * 0.18)
        draw_piece(self, c, r * 1.06, _cells[selected.y * 9 + selected.x], 1.0, 2.2)
        draw_circle(c, r * 1.1, UiTheme.GOLD, false, 3.0, true)
    if hint.size() == 4:
        var pulse := 0.5 + 0.5 * sin(_t * 6.0)
        var a := square_center(int(hint[0]), int(hint[1]))
        var b := square_center(int(hint[2]), int(hint[3]))
        var gold := Color(1, 0.82, 0.3, 0.45 + 0.4 * pulse)
        draw_line(a, b, Color(1, 0.82, 0.3, 0.5), s * 0.08, true)
        draw_circle(a, r * 1.08, gold, false, 4.0, true)
        draw_circle(b, r * (0.6 + 0.2 * pulse), gold, false, 4.0, true)

func _square_center_index(i: int) -> Vector2:
    return square_center(i % 9, i / 9)

## The lines, river, palaces and 炮 / 兵 marks; symmetric, so the same flipped or not.
func _draw_grid(s: float) -> void:
    var p := func(x: float, y: float) -> Vector2: return Vector2((x + 0.5 + PAD) * s, (y + 0.5 + PAD) * s)
    for y in 10:
        draw_line(p.call(0, y), p.call(8, y), INK, 3.0 if y == 0 or y == 9 else 1.6, true)
    for x in 9:
        var w := 3.0 if x == 0 or x == 8 else 1.6
        if x == 0 or x == 8:
            draw_line(p.call(x, 0), p.call(x, 9), INK, w, true)
        else:  # broken by the river
            draw_line(p.call(x, 0), p.call(x, 4), INK, w, true)
            draw_line(p.call(x, 5), p.call(x, 9), INK, w, true)
    var frame := Rect2(p.call(0, 0) - Vector2(s, s) * 0.14, Vector2(8 * s, 9 * s) + Vector2(s, s) * 0.28)
    draw_rect(frame, INK, false, 2.0, true)
    for top in [0, 7]:  # palaces
        draw_line(p.call(3, top), p.call(5, top + 2), INK, 1.6, true)
        draw_line(p.call(5, top), p.call(3, top + 2), INK, 1.6, true)
    for m in MARKS:
        var c: Vector2 = p.call(m.x, m.y)
        for sx in [-1, 1]:
            if (m.x == 0 and sx < 0) or (m.x == 8 and sx > 0):
                continue
            for sy in [-1, 1]:
                var o := c + Vector2(sx, sy) * s * 0.1
                draw_line(o, o + Vector2(sx * s * 0.18, 0), INK, 1.6, true)
                draw_line(o, o + Vector2(0, sy * s * 0.18), INK, 1.6, true)
    var fs := int(s * 0.5)
    var f := font()
    var river_y: float = p.call(0, 4.5).y + (f.get_ascent(fs) - f.get_descent(fs)) / 2
    var river := Color(INK.r, INK.g, INK.b, 0.65)
    draw_string(f, Vector2(p.call(0, 0).x, river_y), "楚  河", HORIZONTAL_ALIGNMENT_CENTER, 4 * s, fs, river)
    draw_string(f, Vector2(p.call(4, 0).x, river_y), "汉  界", HORIZONTAL_ALIGNMENT_CENTER, 4 * s, fs, river)

## Corner brackets around a square (the last move's from and to).
func _corners(c: Vector2, s: float, color: Color) -> void:
    var k := s * 0.42
    var l := s * 0.14
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            var o := c + Vector2(sx * k, sy * k)
            draw_line(o, o - Vector2(sx * l, 0), color, 3.0, true)
            draw_line(o, o - Vector2(0, sy * l), color, 3.0, true)

## A round wooden piece with its character: red pieces are upper-case letters.
static func draw_piece(canvas: CanvasItem, c: Vector2, r: float, letter: String, alpha := 1.0,
        lift := 1.0) -> void:
    var red := letter == letter.to_upper()
    var ink := RED_INK if red else BLACK_INK
    ink.a = alpha
    canvas.draw_circle(c + Vector2(r * 0.06, r * 0.12) * lift, r, Color(0, 0, 0, 0.4 * alpha), true, -1.0, true)
    canvas.draw_circle(c, r, Color(0.58, 0.38, 0.2, alpha), true, -1.0, true)
    canvas.draw_circle(c, r * 0.9, Color(0.97, 0.88, 0.67, alpha), true, -1.0, true)
    canvas.draw_circle(c - Vector2(r, r) * 0.08, r * 0.6, Color(1, 0.95, 0.82, 0.35 * alpha), true, -1.0, true)
    canvas.draw_circle(c, r * 0.76, ink, false, maxf(1.5, r * 0.05), true)
    var f := font()
    var fs := int(r * 1.15)
    var text: String = NAMES.get(letter, "?")
    var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    var baseline := c.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2
    canvas.draw_string(f, Vector2(c.x - w / 2, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
