class_name HandView
extends Control
## Lays out the human's cards in an overlapping, centered row and tracks selection.

signal selection_changed

const MAX_STEP := 44.0

var cards: Array[CardView] = []

func set_cards(ids: Array, animate := false) -> void:
    var keep := {}
    for c in cards:
        keep[c.card_id] = c
    var next: Array[CardView] = []
    for id in CardView.sort_for_display(ids):
        var c: CardView = keep.get(int(id))
        if c == null:
            c = CardView.make(int(id))
            c.pressed.connect(_on_card_pressed)
            add_child(c)
        keep.erase(int(id))
        next.append(c)
    for c in keep.values():
        c.queue_free()
    cards = next
    for i in cards.size():
        move_child(cards[i], i)
    _layout(animate)

func _layout(animate: bool) -> void:
    var n := cards.size()
    if n == 0:
        return
    var step := MAX_STEP
    if n > 1:
        step = min(MAX_STEP, (size.x - CardView.SIZE.x) / (n - 1))
    var total := step * (n - 1) + CardView.SIZE.x
    var x0 := (size.x - total) / 2.0
    var y := size.y - CardView.SIZE.y
    for i in n:
        var c := cards[i]
        c.base_y = y
        var target := Vector2(x0 + step * i, y - (22.0 if c.selected else 0.0))
        if animate:
            c.position = target + Vector2(0, 60)
            c.modulate.a = 0.0
            var t := c.create_tween().set_parallel()
            t.tween_property(c, "position", target, 0.25).set_delay(i * 0.025).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
            t.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(i * 0.025)
        else:
            var t := c.create_tween()
            t.tween_property(c, "position", target, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout(false)

func _on_card_pressed(card: CardView) -> void:
    card.set_selected(not card.selected)
    selection_changed.emit()

func selected_ids() -> Array:
    var ids := []
    for c in cards:
        if c.selected:
            ids.append(c.card_id)
    return ids

func select_ids(ids: Array) -> void:
    for c in cards:
        c.set_selected(ids.has(c.card_id))
    selection_changed.emit()

func clear_selection() -> void:
    select_ids([])
