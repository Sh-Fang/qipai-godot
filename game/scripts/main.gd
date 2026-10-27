extends Control
## Table UI. Every rule decision comes from the core (autoload `Core`);
## this script only renders the state it gets back and forwards clicks.

const ME := 0
const SEAT_NAMES := ["我", "下家", "上家"]
const BID_TEXT := {"call": "叫地主", "pass": "不叫", "rob": "抢地主", "no_rob": "不抢"}
const AI_DELAY := 0.8
const PLAYED_SCALE := 0.75

@onready var seats := [$MySeat, $RightSeat, $LeftSeat]
@onready var play_areas := [$MyPlay, $RightPlay, $LeftPlay]
@onready var hand: HandView = $Hand
@onready var bottom_cards: HBoxContainer = $TopBar/BottomCards
@onready var info_label: Label = $TopBar/Info
@onready var toast: Label = $Toast
@onready var result_panel: PanelContainer = $ResultPanel
@onready var overlay: ColorRect = $ConnectOverlay

var state := {}
var _shown_display := ["", "", ""]
var _ai_running := false
var _toast_tween: Tween
var _pulse_tweens := [null, null, null]

func _ready() -> void:
    _set_actions([])
    hand.selection_changed.connect(_update_play_button)
    overlay.show()
    if not Core.start():
        overlay.get_node("Label").text = "算法核心加载失败：\n" + Core.error_text()
        return
    overlay.hide()
    if OS.get_cmdline_user_args().has("--autotest"):
        var bot := Node.new()
        bot.set_script(load("res://scripts/autotest.gd"))
        add_child(bot)
    await _new_game()

# ---- core round-trips ---------------------------------------------------------

func _new_game() -> void:
    result_panel.hide()
    _shown_display = ["", "", ""]
    _apply(await Core.request("new_game"), true)
    _run_ai()

func _apply(reply: Dictionary, deal := false) -> bool:
    if reply.is_empty():
        overlay.get_node("Label").text = "算法核心没有响应：\n" + Core.error_text()
        overlay.show()
        return false
    if not reply.get("ok", false):
        _toast(reply.get("error", "出错了"))
    var event = reply.get("event")
    if event is Dictionary:
        _show_event(event)
        if event.get("redeal", false):
            deal = true
    state = reply["state"]
    _render(deal)
    return reply.get("ok", false)

## Let the AIs act one move at a time until it's the human's turn.
func _run_ai() -> void:
    if _ai_running:
        return
    _ai_running = true
    while state.get("phase") != "over" and int(state.get("current_seat", ME)) != ME:
        await get_tree().create_timer(AI_DELAY).timeout
        if not _apply(await Core.request("step")):
            break
    _ai_running = false

# ---- buttons ----------------------------------------------------------------

func _on_bid_pressed(want: bool) -> void:
    _set_actions([])
    _apply(await Core.request("bid", {"call": want}))
    _run_ai()

func _on_play_pressed() -> void:
    var ids := hand.selected_ids()
    if ids.is_empty():
        _toast("请先选牌")
        return
    if _apply(await Core.request("play", {"cards": ids})):
        _run_ai()

func _on_pass_pressed() -> void:
    hand.clear_selection()
    if _apply(await Core.request("pass")):
        _run_ai()

func _on_hint_pressed() -> void:
    var reply := await Core.request("hint")
    var ids := []
    for id in reply.get("hint", []):
        ids.append(int(id))
    if ids.is_empty():
        _toast("建议：不出")
        hand.clear_selection()
    else:
        hand.select_ids(ids)

func _on_again_pressed() -> void:
    await _new_game()

# ---- rendering ----------------------------------------------------------------

func _render(deal: bool) -> void:
    var phase: String = state["phase"]
    var current := int(state["current_seat"])
    var landlord := int(state["landlord_seat"])

    for seat in 3:
        var box: Control = seats[seat].get_node("VBox")
        var role: Label = box.get_node("Role")
        if landlord < 0:
            var bid = state["bids"][seat]
            role.text = "等待叫地主" if bid == null else BID_TEXT[bid]
            role.modulate = Color.WHITE
        else:
            role.text = "地主" if seat == landlord else "农民"
            role.modulate = Color(1, 0.75, 0.3) if seat == landlord else Color(0.6, 0.85, 1)
        box.get_node("Count").text = "剩 %d 张" % int(state["card_counts"][seat])
        _set_turn_highlight(seat, seat == current)
        _render_play_area(seat, state["display"][seat])

    _render_bottom_cards(state["bottom_cards"])
    info_label.text = "抢地主 %d · 炸弹 %d · 倍数 ×%d" % [
        int(state["rob_count"]), int(state["bomb_num"]), int(state["multiplier"])]

    hand.set_cards(state["my_hand"], deal)

    if phase == "bidding" and current == ME:
        _set_actions(["BidBtn", "NoBidBtn"])
        var rob: bool = state["bid_stage"] == "rob"
        $Actions/BidBtn.text = "抢地主" if rob else "叫地主"
        $Actions/NoBidBtn.text = "不抢" if rob else "不叫"
    elif phase == "playing" and current == ME:
        _set_actions(["PassBtn", "HintBtn", "PlayBtn"])
        $Actions/PassBtn.disabled = state["must_lead"]
        _update_play_button()
    elif phase == "over":
        _set_actions([])
        _show_result()
    else:
        _set_actions(["Waiting"])
        var doing := "出牌"
        if phase == "bidding":
            doing = "抢地主" if state["bid_stage"] == "rob" else "叫地主"
        $Actions/Waiting.text = "等待%s%s…" % [SEAT_NAMES[current], doing]

func _set_actions(visible_names: Array) -> void:
    for child in $Actions.get_children():
        child.visible = visible_names.has(child.name)
        if child is Button:
            child.disabled = false

func _update_play_button() -> void:
    $Actions/PlayBtn.disabled = hand.selected_ids().is_empty()

func _set_turn_highlight(seat: int, on: bool) -> void:
    var panel: Control = seats[seat]
    if _pulse_tweens[seat]:
        _pulse_tweens[seat].kill()
        _pulse_tweens[seat] = null
    panel.self_modulate = Color.WHITE
    var status: Label = panel.get_node("VBox/Status")
    if on:
        status.text = "▶ 思考中" if seat != ME else "▶ 轮到你"
        var t := create_tween().set_loops()
        t.tween_property(panel, "self_modulate", Color(1.6, 1.4, 0.6), 0.5)
        t.tween_property(panel, "self_modulate", Color.WHITE, 0.5)
        _pulse_tweens[seat] = t
    elif status.text.begins_with("▶"):
        status.text = ""

func _render_play_area(seat: int, display) -> void:
    var key := JSON.stringify(display)
    if key == _shown_display[seat]:
        return
    _shown_display[seat] = key
    var area: HBoxContainer = play_areas[seat]
    for child in area.get_children():
        child.queue_free()
    if display == null:
        return
    if display["pass"]:
        var label := Label.new()
        label.text = "不出"
        label.add_theme_font_size_override("font_size", 30)
        label.add_theme_color_override("font_outline_color", Color.BLACK)
        label.add_theme_constant_override("outline_size", 6)
        area.add_child(label)
        _pop_in(label, seat)
        return
    for id in CardView.sort_for_display(display["cards"]):
        var card := CardView.make(int(id), true, PLAYED_SCALE)
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        area.add_child(card)
        _pop_in(card, seat)

## Fade/slide a freshly played card in from its owner's side of the table.
func _pop_in(node: Control, seat: int) -> void:
    var from: Vector2 = [Vector2(0, 50), Vector2(60, 0), Vector2(-60, 0)][seat]
    node.modulate.a = 0.0
    await get_tree().process_frame  # let the container place it first
    if not is_instance_valid(node):
        return
    var target := node.position
    node.position = target + from
    var t := node.create_tween().set_parallel()
    t.tween_property(node, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    t.tween_property(node, "modulate:a", 1.0, 0.18)

func _render_bottom_cards(ids: Array) -> void:
    ids = CardView.sort_for_display(ids)
    var want := 3 if ids.is_empty() else ids.size()
    var face_up := not ids.is_empty()
    var existing := bottom_cards.get_children()
    if existing.size() == want and (existing[0] as CardView).face_up == face_up \
            and (not face_up or (existing[0] as CardView).card_id == int(ids[0])):
        return
    for child in existing:
        child.queue_free()
    for i in want:
        var card := CardView.make(int(ids[i]) if face_up else -1, face_up, 0.6)
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bottom_cards.add_child(card)
        if face_up:  # flip-in when the landlord is decided
            card.scale = Vector2(0, 1)
            card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.25).set_delay(i * 0.08)

func _show_event(event: Dictionary) -> void:
    var seat := int(event["seat"])
    var who: String = SEAT_NAMES[seat]
    var status: Label = seats[seat].get_node("VBox/Status")
    match event["type"]:
        "bid":
            if event.get("redeal", false):
                _toast("都不叫，重新发牌")
            elif event["action"] in ["call", "rob"]:
                _toast("%s %s！" % [who, BID_TEXT[event["action"]]])
        "play":
            status.text = event.get("move_type", "")
            if event.get("move_type", "") in ["炸弹", "王炸"]:
                _toast("%s：%s！" % [who, event["move_type"]])
                _shake()
        "pass":
            status.text = "不出"

func _show_result() -> void:
    if result_panel.visible:
        return
    var won: bool = state["human_won"]
    var title: Label = result_panel.get_node("VBox/Title")
    title.text = "你赢了！" if won else "你输了"
    title.modulate = Color(1, 0.85, 0.3) if won else Color(0.7, 0.8, 1)
    var lines := ["%s 获胜 · 抢地主 %d 次 · 炸弹 %d 个 · 倍数 ×%d" % [
        "地主" if state["winner"] == "landlord" else "农民",
        int(state["rob_count"]), int(state["bomb_num"]), int(state["multiplier"])]]
    var hands = state.get("hands")
    if hands is Array:
        for seat in [1, 2]:
            lines.append("%s 剩余：%s" % [SEAT_NAMES[seat], _cards_text(hands[seat])])
    result_panel.get_node("VBox/Detail").text = "\n".join(lines)
    result_panel.show()
    result_panel.scale = Vector2(0.7, 0.7)
    result_panel.pivot_offset = result_panel.size / 2
    result_panel.modulate.a = 0.0
    var t := create_tween().set_parallel()
    t.tween_property(result_panel, "scale", Vector2.ONE, 0.3).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_property(result_panel, "modulate:a", 1.0, 0.25).set_delay(0.5)

func _cards_text(ids: Array) -> String:
    if ids.is_empty():
        return "（出完了）"
    var parts := []
    for id in CardView.sort_for_display(ids):
        if id == 52:
            parts.append("小王")
        elif id == 53:
            parts.append("大王")
        else:
            parts.append(CardView.RANKS[id / 4])
    return " ".join(parts)

func _toast(text: String) -> void:
    toast.text = text
    toast.modulate.a = 1.0
    if _toast_tween:
        _toast_tween.kill()
    _toast_tween = create_tween()
    _toast_tween.tween_interval(1.2)
    _toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)

func _shake() -> void:
    var t := create_tween()
    for i in 6:
        t.tween_property(self, "position", Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
    t.tween_property(self, "position", Vector2.ZERO, 0.04)
