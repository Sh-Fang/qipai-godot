class_name CardView
extends Control
## One playing card, drawn in code (suits are polygons, so no font glyphs needed).
## Card ids match the core: 0..51 = rank*4 + suit, 52 小王, 53 大王.

const SIZE := Vector2(86, 120)
const LIFT := 26.0  # how far a selected card rises, at scale 1
const RANKS := ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
const SUITS := ["♠", "♥", "♣", "♦"]
const RED := Color(0.84, 0.1, 0.14)
const BLACK := Color(0.12, 0.12, 0.16)
const FACE := Color(1, 0.99, 0.96)

var card_id := -1
var face_up := true
var selected := false
var hovered := false  # previewed by a drag-select in progress
var bomb := 0  # part of a bomb in the hand: 1, or 2 for the group's first card (gets the badge)
var base_y := 0.0

var _move_tween: Tween

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
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    c.pivot_offset = c.size / 2
    return c

func set_face_up(up: bool) -> void:
    face_up = up
    queue_redraw()

func set_bomb(value: int) -> void:
    if bomb != value:
        bomb = value
        queue_redraw()

func set_hovered(value: bool) -> void:
    if hovered != value:
        hovered = value
        queue_redraw()

func set_selected(value: bool) -> void:
    if selected == value:
        return
    selected = value
    queue_redraw()
    move_to(Vector2(position.x, base_y - (lift() if selected else 0.0)), 0.12)

func lift() -> float:
    return LIFT * size.x / SIZE.x

## Tweens to `target`, replacing any move already in flight.
func move_to(target: Vector2, duration: float, delay := 0.0,
        trans := Tween.TRANS_QUAD) -> Tween:
    if _move_tween:
        _move_tween.kill()
    _move_tween = create_tween()
    _move_tween.tween_property(self, "position", target, duration) \
            .set_delay(delay).set_trans(trans).set_ease(Tween.EASE_OUT)
    return _move_tween

## Turn over in place: squash to an edge, swap faces, open back up.
func flip(up: bool, delay := 0.0) -> void:
    var t := create_tween()
    t.tween_property(self, "scale:x", 0.0, 0.08).set_delay(delay)
    t.tween_callback(set_face_up.bind(up))
    t.tween_property(self, "scale:x", 1.0, 0.08)

# ---- drawing ------------------------------------------------------------------

func _draw() -> void:
    var k := size.x / SIZE.x
    var rect := Rect2(Vector2.ZERO, size)
    var s := StyleBoxFlat.new()
    s.set_corner_radius_all(int(8 * k))
    s.anti_aliasing = true
    s.shadow_color = Color(0, 0, 0, 0.3)
    s.shadow_size = int(5 * k)
    s.shadow_offset = Vector2(0, 2 * k)
    if not face_up:
        _draw_back(rect, k, s)
        return
    s.bg_color = FACE
    s.border_color = Color(0.55, 0.55, 0.6)
    s.set_border_width_all(max(1, int(k)))
    if selected:
        s.bg_color = Color(1, 0.93, 0.62)
        s.border_color = Color(0.95, 0.58, 0.08)
        s.set_border_width_all(int(3 * k))
    elif hovered:
        s.bg_color = Color(0.8, 0.88, 1)
    elif bomb > 0:
        s.border_color = Color(1, 0.5, 0.08)
        s.set_border_width_all(int(3 * k))
    draw_style_box(s, rect)
    if card_id >= 52:
        _draw_joker(k)
    else:
        _draw_face(k)
    if bomb == 2:
        _draw_bomb_badge(Vector2(16 * k, (99 if card_id >= 52 else 66) * k), k)

## Little cartoon bomb under the index, in the strip that stays visible when cards overlap.
func _draw_bomb_badge(c: Vector2, k: float) -> void:
    draw_circle(c, 9 * k, Color(1, 0.55, 0.1, 0.35), true, -1.0, true)
    draw_circle(c + Vector2(0, 1) * k, 6.5 * k, Color(0.13, 0.12, 0.16), true, -1.0, true)
    draw_circle(c + Vector2(-2, -1) * k, 1.8 * k, Color(1, 1, 1, 0.55), true, -1.0, true)
    draw_line(c + Vector2(3, -4) * k, c + Vector2(6, -8) * k, Color(0.55, 0.4, 0.25), maxf(1.0, 1.5 * k), true)
    draw_circle(c + Vector2(6.5, -8.5) * k, 2.2 * k, Color(1, 0.75, 0.1), true, -1.0, true)
    draw_circle(c + Vector2(6.5, -8.5) * k, 1.0 * k, Color(1, 1, 0.8), true, -1.0, true)

func _draw_face(k: float) -> void:
    var rank: int = card_id / 4
    var suit: int = card_id % 4
    var color := RED if suit == 1 or suit == 3 else BLACK
    var text: String = RANKS[rank]
    var font := UiTheme.bold
    var fs := int(27 * k)
    # every rank at the same height; "10" is squeezed sideways to fit the index strip
    var squeeze := minf(1.0, 26 * k / font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
    draw_set_transform(Vector2(16 * k, 28 * k), 0.0, Vector2(squeeze, 1))
    draw_string(font, Vector2(-15 * k / squeeze, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 30 * k / squeeze, fs, color)
    draw_set_transform(Vector2.ZERO)
    _draw_suit(suit, Vector2(16 * k, 44 * k), 16 * k, color)
    var big := 44.0 if rank == 11 else 36.0
    _draw_suit(suit, Vector2(size.x - 28 * k, size.y - 32 * k), big * k, color)

func _draw_joker(k: float) -> void:
    var big := card_id == 53
    var color := RED if big else BLACK
    var font := UiTheme.bold
    var y := 19.0
    var fs := int(16 * k)
    for ch in "JOKER":
        draw_string(font, Vector2(1 * k + _ink_dx(font, ch, fs), y * k), ch, HORIZONTAL_ALIGNMENT_CENTER,
                26 * k, fs, color)
        y += 15.5
    _draw_jester(Vector2(size.x - 31 * k, size.y - 34 * k), k, big)

static var _ink_cache := {}

## Shift that centres a glyph by its ink rather than its advance box, so a column of
## letters (the JOKER index) lines up even though J, O and K sit differently in theirs.
static func _ink_dx(font: Font, ch: String, fs: int) -> float:
    var key := "%s%d" % [ch, fs]
    if _ink_cache.has(key):
        return _ink_cache[key]
    var ts := TextServerManager.get_primary_interface()
    var shaped := ts.create_shaped_text()
    ts.shaped_text_add_string(shaped, ch, font.get_rids(), fs)
    var dx := 0.0
    var glyphs := ts.shaped_text_get_glyphs(shaped)
    if not glyphs.is_empty():
        var g: Dictionary = glyphs[0]
        var size_key := Vector2i(fs, 0)
        ts.font_render_glyph(g["font_rid"], size_key, g["index"])
        var off: Vector2 = ts.font_get_glyph_offset(g["font_rid"], size_key, g["index"])
        var ink: Vector2 = ts.font_get_glyph_size(g["font_rid"], size_key, g["index"])
        if ink.x > 0:
            dx = float(g["advance"]) / 2.0 - (off.x + ink.x / 2.0)
    ts.free_rid(shaped)
    _ink_cache[key] = dx
    return dx

## Jester head in a three-horned belled hat: full colour for 大王, greys for 小王.
func _draw_jester(f: Vector2, k: float, big: bool) -> void:
    var gold := Color(1, 0.78, 0.15)
    var horns := [RED, Color(0.2, 0.4, 0.85), gold] if big \
            else [BLACK, Color(0.55, 0.56, 0.6), BLACK]
    var bell := gold if big else Color(0.78, 0.8, 0.85)
    var skin := Color(1, 0.87, 0.74) if big else Color(0.93, 0.93, 0.93)
    var line := Color(0.35, 0.15, 0.1) if big else BLACK
    # ruff collar
    for i in 5:
        var x := -15.0 + i * 6.0
        _poly(f, k, [Vector2(x, 9), Vector2(x + 6, 9), Vector2(x + 3, 18)],
                horns[i % 2] if big else horns[1])
    # hat: left, right, then the middle horn on top
    _poly(f, k, [Vector2(-11, -5), Vector2(-3, -9), Vector2(-13, -20), Vector2(-25, -15)], horns[0])
    _poly(f, k, [Vector2(11, -5), Vector2(3, -9), Vector2(13, -20), Vector2(25, -15)], horns[0])
    _poly(f, k, [Vector2(-6, -8), Vector2(6, -8), Vector2(3, -21), Vector2(0, -30), Vector2(-3, -21)], horns[1])
    for at in [Vector2(-25, -15), Vector2(25, -15), Vector2(0, -30)]:
        _dot(f, k, at, 2.8, bell)
    # face and brim
    _dot(f, k, Vector2(0, 1), 10.5, skin)
    draw_circle(f + Vector2(0, 1) * k, 10.5 * k, line, false, maxf(1.0, 0.8 * k), true)
    _poly(f, k, [Vector2(-12, -9), Vector2(12, -9), Vector2(11, -4), Vector2(-11, -4)], horns[2])
    _dot(f, k, Vector2(-3.8, 0), 1.3, line)
    _dot(f, k, Vector2(3.8, 0), 1.3, line)
    if big:
        _dot(f, k, Vector2(-6, 4), 1.8, Color(1, 0.45, 0.45, 0.6))
        _dot(f, k, Vector2(6, 4), 1.8, Color(1, 0.45, 0.45, 0.6))
    draw_arc(f + Vector2(0, 2.5) * k, 4.5 * k, 0.15 * PI, 0.85 * PI, 12, line, maxf(1.0, 1.2 * k), true)

func _draw_back(rect: Rect2, k: float, s: StyleBoxFlat) -> void:
    s.bg_color = Color(0.66, 0.1, 0.13)
    s.border_color = Color(0.98, 0.95, 0.88)
    s.set_border_width_all(int(3 * k))
    draw_style_box(s, rect)
    var inner := rect.grow(-7 * k)
    var gold := Color(1, 0.8, 0.35)
    var step := 11.0 * k
    var y := inner.position.y + step / 2
    while y < inner.end.y:
        var x := inner.position.x + step / 2
        while x < inner.end.x:
            var r := step * 0.32
            draw_colored_polygon(PackedVector2Array([Vector2(x, y - r), Vector2(x + r, y),
                    Vector2(x, y + r), Vector2(x - r, y)]), Color(gold, 0.22))
            x += step
        y += step
    draw_rect(inner, Color(gold, 0.8), false, max(1.0, 1.5 * k))
    var c := rect.get_center()
    draw_circle(c, 17 * k, Color(0.5, 0.05, 0.08), true, -1.0, true)
    draw_circle(c, 17 * k, gold, false, 2 * k, true)
    draw_string(UiTheme.bold, Vector2(c.x - 17 * k, c.y + 8 * k), "斗",
            HORIZONTAL_ALIGNMENT_CENTER, 34 * k, int(22 * k), gold)

# ---- shapes (unit coordinates scaled by `w`, the shape's width) ---------------

func _draw_suit(suit: int, c: Vector2, w: float, color: Color) -> void:
    match suit:
        0:  # spade
            _poly(c, w, [Vector2(0, -0.55), Vector2(0.5, 0.02), Vector2(-0.5, 0.02)], color)
            _dot(c, w, Vector2(-0.25, 0.1), 0.27, color)
            _dot(c, w, Vector2(0.25, 0.1), 0.27, color)
            _poly(c, w, [Vector2(0, 0.05), Vector2(0.18, 0.5), Vector2(-0.18, 0.5)], color)
        1:  # heart
            _dot(c, w, Vector2(-0.25, -0.2), 0.27, color)
            _dot(c, w, Vector2(0.25, -0.2), 0.27, color)
            _poly(c, w, [Vector2(-0.51, -0.12), Vector2(0.51, -0.12), Vector2(0, 0.5)], color)
            _poly(c, w, [Vector2(-0.3, -0.2), Vector2(0.3, -0.2), Vector2(0, 0.2)], color)
        2:  # club
            _dot(c, w, Vector2(0, -0.26), 0.22, color)
            _dot(c, w, Vector2(-0.26, 0.08), 0.22, color)
            _dot(c, w, Vector2(0.26, 0.08), 0.22, color)
            _dot(c, w, Vector2(0, 0), 0.14, color)
            _poly(c, w, [Vector2(0, -0.05), Vector2(0.17, 0.5), Vector2(-0.17, 0.5)], color)
        3:  # diamond
            _poly(c, w, [Vector2(0, -0.55), Vector2(0.42, 0), Vector2(0, 0.55), Vector2(-0.42, 0)], color)

func _poly(c: Vector2, w: float, pts: Array, color: Color) -> void:
    var out := PackedVector2Array()
    for p in pts:
        out.append(c + p * w)
    _fill(out, color)

## Filled polygon with an anti-aliased edge (draw_colored_polygon alone is jaggy).
func _fill(pts: PackedVector2Array, color: Color) -> void:
    draw_colored_polygon(pts, color)
    draw_polyline(pts + PackedVector2Array([pts[0]]), color, 1.0, true)

func _dot(c: Vector2, w: float, at: Vector2, r: float, color: Color) -> void:
    draw_circle(c + at * w, r * w, color, true, -1.0, true)
