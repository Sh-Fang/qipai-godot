class_name HandView
extends Control
## Lays out the human's cards in an overlapping, centered row and tracks selection.
## Covered cards show only their index strip (rank and a small suit); cards that make
## up a bomb (four of a rank, or both jokers) are marked.
## Tap toggles one card; dragging across several toggles all of them; right-click clears.

signal selection_changed

const CARD_SCALE := 1.7  # big enough to read and tap on a phone
const CARD_SIZE := CardView.SIZE * CARD_SCALE
const MAX_STEP := 40.0 * CARD_SCALE  # visible strip of a covered card: just the index
const DEAL_GAP := 0.045

var cards: Array[CardView] = []
var _drag_from := -1
var _drag_to := -1

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP

## `deal`: fly every card in face down from the deck in the middle of the screen.
## Otherwise cards that weren't in the hand before (the bottom cards) drop in raised.
func set_cards(ids: Array, deal := false) -> void:
    var keep := {}
    for c in cards:
        keep[c.card_id] = c
    if deal:
        for c in cards:
            c.queue_free()
        keep.clear()
    var fresh: Array[CardView] = []
    var next: Array[CardView] = []
    for id in CardView.sort_for_display(ids):
        var c: CardView = keep.get(int(id))
        if c == null:
            c = CardView.make(int(id), true, CARD_SCALE)
            add_child(c)
            fresh.append(c)
        keep.erase(int(id))
        next.append(c)
    for c in keep.values():
        c.queue_free()
    cards = next
    for i in cards.size():
        move_child(cards[i], i)
    _mark_bombs()
    var targets := _targets()
    var deck := get_viewport_rect().size / 2 - global_position - CARD_SIZE / 2
    for i in cards.size():
        var c := cards[i]
        c.base_y = targets[i].y
        if c.selected:
            targets[i].y -= c.lift()
        if deal:
            c.position = deck
            c.set_face_up(false)
            c.modulate.a = 0.0
            var delay := i * DEAL_GAP
            c.create_tween().tween_property(c, "modulate:a", 1.0, 0.1).set_delay(delay)
            c.move_to(targets[i], 0.3, delay, Tween.TRANS_CUBIC)
            c.flip(true, delay + 0.3)
        elif c in fresh and not cards.size() == fresh.size():
            c.position = targets[i] - Vector2(0, 70)
            c.modulate.a = 0.0
            c.set_hovered(true)
            c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2)
            c.move_to(targets[i] - Vector2(0, c.lift()), 0.25, 0.1)
            var t := c.create_tween()
            t.tween_interval(1.2)
            t.tween_callback(c.set_hovered.bind(false))
            t.tween_callback(func(): if not c.selected: c.move_to(Vector2(c.position.x, c.base_y), 0.2))
        else:
            c.move_to(targets[i], 0.18)

## Flag every card that is part of a bomb; the first card of each group gets the badge.
func _mark_bombs() -> void:
    var by_rank := {}
    for c in cards:
        var key: int = 99 if c.card_id >= 52 else c.card_id / 4
        if not by_rank.has(key):
            by_rank[key] = []
        by_rank[key].append(c)
    for c in cards:
        c.set_bomb(0)
    for key in by_rank:
        var group: Array = by_rank[key]
        if group.size() == (2 if key == 99 else 4):
            for c in group:
                c.set_bomb(1)
            group[0].set_bomb(2)  # cards are in display order, so this is the leftmost

func _targets() -> Array[Vector2]:
    var out: Array[Vector2] = []
    var n := cards.size()
    var step := MAX_STEP
    if n > 1:
        step = min(MAX_STEP, (size.x - CARD_SIZE.x) / (n - 1))
    var total := step * (n - 1) + CARD_SIZE.x
    var x0 := (size.x - total) / 2.0
    var y := size.y - CARD_SIZE.y
    for i in n:
        out.append(Vector2(x0 + step * i, y))
    return out

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED and not cards.is_empty():
        var targets := _targets()
        for i in cards.size():
            cards[i].base_y = targets[i].y
            cards[i].move_to(targets[i] - Vector2(0, cards[i].lift() if cards[i].selected else 0.0), 0.15)

# ---- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            clear_selection()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                var i := _card_at(event.position)
                if i >= 0:
                    _drag_from = i
                    _drag_to = i
                    _preview()
                    accept_event()
            elif _drag_from >= 0:
                _finish_drag()
                accept_event()
    elif event is InputEventMouseMotion and _drag_from >= 0:
        var i := _column_at(event.position.x)
        if i != _drag_to:
            _drag_to = i
            _preview()
            Sfx.play("select", -16.0)

## Topmost card under the point (cards to the right overlap those to the left).
func _card_at(p: Vector2) -> int:
    for i in range(cards.size() - 1, -1, -1):
        if cards[i].get_rect().has_point(p):
            return i
    return -1

## Card whose visible strip covers x, ignoring height, so a sloppy drag still works.
func _column_at(x: float) -> int:
    for i in range(cards.size() - 1, -1, -1):
        if x >= cards[i].position.x:
            return i
    return 0

func _preview() -> void:
    var lo := mini(_drag_from, _drag_to)
    var hi := maxi(_drag_from, _drag_to)
    for i in cards.size():
        cards[i].set_hovered(i >= lo and i <= hi)

func _finish_drag() -> void:
    var lo := mini(_drag_from, _drag_to)
    var hi := maxi(_drag_from, _drag_to)
    _drag_from = -1
    for i in cards.size():
        cards[i].set_hovered(false)
    for i in range(lo, hi + 1):
        cards[i].set_selected(not cards[i].selected)
    Sfx.play("select")
    selection_changed.emit()

func selected_ids() -> Array:
    var ids := []
    for c in cards:
        if c.selected:
            ids.append(c.card_id)
    return ids

## Global top-left corner of each card, keyed by id, so played cards can fly from there.
func card_positions(ids: Array) -> Dictionary:
    var out := {}
    for c in cards:
        if ids.has(c.card_id):
            out[c.card_id] = c.global_position
    return out

func select_ids(ids: Array) -> void:
    for c in cards:
        c.set_selected(ids.has(c.card_id))
    selection_changed.emit()

func clear_selection() -> void:
    if not selected_ids().is_empty():
        select_ids([])

## Quick side-to-side wiggle of the raised cards ("管不上").
func shake_selected() -> void:
    for c in cards:
        if c.selected:
            var x := c.position.x
            var t := c.create_tween()
            for dx in [-8.0, 8.0, -5.0, 5.0, 0.0]:
                t.tween_property(c, "position:x", x + dx, 0.04)
