extends Control
## Table UI. Every rule decision comes from the core (autoload `Core`);
## this script only renders and animates the state it gets back and forwards input.
## Keys: Space/Enter 出牌 · H 提示 · P 不出 · Esc 清空选择.
## `-- --rocket` deals the human both jokers every game (for trying the 王炸 effect).
## Every finished game is written to user://logs/ as a 牌谱, and its points to the 积分记录
## (tap the score).
## Hosted by the app (scripts/app.gd), whose 设置 pauses the game: timers made here
## pass process_always = false so the AI, the clock and the deal all wait with it.

const ME := 0
const SEAT_NAMES := ["我", "下家", "上家"]
const BID_TEXT := {"call": "叫地主", "pass": "不叫", "rob": "抢地主", "no_rob": "不抢"}
const BID_VOICE := {"call": "bid_call", "pass": "bid_nocall", "rob": "bid_grab", "no_rob": "bid_nograb"}
const DOUBLE_TEXT := {"double": "加倍", "no_double": "不加倍"}
const DOUBLE_VOICE := {"double": "double", "no_double": "nodouble"}
const RANK_VOICE := ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
## Move types announced by name rather than by rank.
const TYPE_VOICE := {
    "三带一": "type_trio_single", "三带二": "type_trio_pair", "顺子": "type_straight",
    "连对": "type_pairstraight", "飞机": "type_plane", "飞机带单": "type_plane",
    "飞机带对": "type_plane", "四带二": "type_four_two", "四带两对": "type_four_twopair",
    "炸弹": "type_bomb", "王炸": "type_rocket",
}
## AI 思考时间 (seconds, random in range): only for feel, the move is decided instantly.
const THINK_BID := Vector2(0.5, 1.2)
const THINK_PLAY := Vector2(0.6, 1.8)
const THINK_FORCED := Vector2(0.3, 0.6)  # nothing to do but pass
## 倒计时 per phase; when the human runs out of time the safest choice is made for them.
const TURN_SECONDS := {"bidding": 15, "doubling": 15, "playing": 20}
const LOG_DIR := "user://logs"
const LOG_KEEP := 50
const HISTORY_KEEP := 100
const PLAYED_SCALE := 0.85
const BASE_SCORE := 10
## How long the deal animation runs; buttons and AI moves wait for it.
const DEAL_TIME := 17 * HandView.DEAL_GAP + 0.5
## Move types worth a big on-screen callout, with their colour.
const CALLOUTS := {
    "顺子": Color(0.45, 0.85, 1), "连对": Color(0.55, 1, 0.6),
    "飞机": Color(0.75, 0.6, 1), "飞机带单": Color(0.75, 0.6, 1), "飞机带对": Color(0.75, 0.6, 1),
    "四带二": Color(1, 0.6, 0.35), "四带两对": Color(1, 0.6, 0.35),
    "炸弹": Color(1, 0.35, 0.2), "王炸": Color(1, 0.8, 0.2),
}

@onready var seats: Array[SeatView] = [$MySeat, $RightSeat, $LeftSeat]
@onready var play_areas: Array[HBoxContainer] = [$MyPlay, $RightPlay, $LeftPlay]
@onready var hand: HandView = $Hand
@onready var bottom_cards: HBoxContainer = $TopBar/BottomPanel/BottomCards
@onready var mult_label: Label = $TopBar/Stats/Mult
@onready var score_label: Label = $Score
@onready var toast: Label = $Toast
@onready var fx: Fx = $Fx
@onready var dim: ColorRect = $Dim
@onready var result_panel: PanelContainer = $ResultPanel
@onready var overlay: ColorRect = $ConnectOverlay
@onready var bottom_panel: PanelContainer = $TopBar/BottomPanel

var state := {}
var _shown_display := ["", "", ""]
var _ai_running := false
var _game := 0  # bumped by every new game, so an AI loop left over from the last one stops
var _toast_tween: Tween
var _fly_from := {}  # card id -> global position in my hand, for the cards I just played
var _last_mult := 1
var _last_landlord := -1
var _alarmed := [99, 99, 99]  # card count each seat last announced
var _landlord_plays := 0
var _voices := ["male", "female", "male"]  # by seat, reshuffled every game
var _robs := 0  # 抢地主 so far this deal, for the escalating voice lines
var _score := 1000
var _deal_end := 0  # ticks (ms) when the current deal animation finishes
var _turn := 0  # bumped on every event, so a new turn restarts the clock and the hint cycle
var _hint_turn := -1
var _hint_index := 0
var _clock_seat := -1
var _clock_turn := -1
var _clock_time := 0.0  # seconds left, counted in game time so it pauses with the app
var _clock_left := -1
var _requesting := false  # a human action is on its way to the core
var _my_clock: ClockView
var _bottom_tag: Label
var _history: HistoryView
var _games: Array = []  # 积分记录, oldest first: {time, role, won, mult, delta}
var _log: Array[String] = []
var _played := [[], [], []]  # card ids each seat played this game, for the 牌谱

func _ready() -> void:
    for n in [$Score, $TopBar, $LeftSeat, $RightSeat, $MySeat, $LeftPlay, $RightPlay,
            $MyPlay, $Actions, $Hand]:
        App.pad(n)
    _build_extras()
    _load_save()
    _set_actions([])
    hand.selection_changed.connect(_update_play_button)
    for b in find_children("*", "Button", true, false):
        UiTheme.juicy(b)

# ---- what the app calls (see scripts/app.gd) ----------------------------------

func start() -> void:
    _new_game()

func restart() -> void:
    _new_game()

func in_progress() -> bool:
    return not state.is_empty() and state["phase"] != "over"

func forfeit_note() -> String:
    return "放弃当前牌局，本局不计分"

## Nodes made in code: the 积分记录, my turn clock and the 底牌倍数 tag.
func _build_extras() -> void:
    _history = HistoryView.new()
    add_child(_history)
    score_label.mouse_filter = Control.MOUSE_FILTER_STOP
    score_label.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
            _on_score_pressed())
    _my_clock = ClockView.new()
    add_child(_my_clock)
    move_child(_my_clock, $Actions.get_index() + 1)
    seats[1].clock.position = Vector2(seats[1].size.x / 2 - ClockView.SIZE.x / 2, seats[1].size.y + 6)
    seats[2].clock.position = Vector2(seats[2].size.x / 2 - ClockView.SIZE.x / 2, seats[2].size.y + 6)
    _bottom_tag = Label.new()
    _bottom_tag.theme_type_variation = &"Pill"
    _bottom_tag.add_theme_font_override("font", UiTheme.bold)
    _bottom_tag.add_theme_font_size_override("font_size", 22)
    _bottom_tag.add_theme_color_override("font_color", UiTheme.GOLD)
    _bottom_tag.hide()
    add_child(_bottom_tag)
    move_child(_bottom_tag, $TopBar.get_index() + 1)

# ---- core round-trips ---------------------------------------------------------

func _new_game() -> void:
    _game += 1
    _ai_running = false
    _hide_result()
    _shown_display = ["", "", ""]
    _last_mult = 1
    _last_landlord = -1
    _alarmed = [99, 99, 99]
    _landlord_plays = 0
    _log.clear()
    _played = [[], [], []]
    _bottom_tag.hide()
    _stop_clock()
    for i in 3:
        _voices[i] = ["male", "female"].pick_random()
    for s in seats:
        s.set_doubled(false)
    if OS.get_cmdline_user_args().has("--rocket"):
        _apply(await Core.request("debug_setup", _rocket_deal()), true)
    else:
        _apply(await Core.request("new_game"), true)
    _run_ai()

## Debug deal (`-- --rocket`): the human gets both jokers and bids first, to try out 王炸.
func _rocket_deal() -> Dictionary:
    var deck := range(52)
    deck.shuffle()
    return {"hands": [[52, 53] + deck.slice(0, 15), deck.slice(15, 32), deck.slice(32, 49)],
            "bottom": deck.slice(49, 52), "bid_start": ME}

func _apply(reply: Dictionary, deal := false) -> bool:
    if reply.is_empty():
        overlay.get_node("Label").text = "算法核心没有响应：\n" + Core.error_text()
        overlay.show()
        return false
    if not reply.get("ok", false):
        Sfx.play("error")
        _toast(reply.get("error", "出错了"))
        hand.shake_selected()
    var event = reply.get("event")
    if event is Dictionary:
        _turn += 1
        _show_event(event)
        if event.get("redeal", false):
            deal = true
    state = reply["state"]
    if deal:
        _turn += 1
        _stop_clock()
        Sfx.play("deal")
        get_tree().create_timer(DEAL_TIME, false).timeout.connect(Sfx.stop.bind("deal"))
        Sfx.music("bgm_normal")
        _robs = 0
        _deal_end = Time.get_ticks_msec() + int(DEAL_TIME * 1000)
        _alarmed = [99, 99, 99]
        for seat in [1, 2]:
            fx.fly_backs(fx.size / 2, seats[seat].avatar_global(), 17, HandView.DEAL_GAP)
    _render(deal)
    return reply.get("ok", false)

## Let the AIs act one move at a time until it's the human's turn.
func _run_ai() -> void:
    if _ai_running:
        return
    _ai_running = true
    var game := _game
    while state.get("phase") != "over" and int(state.get("current_seat", ME)) != ME:
        await get_tree().create_timer(_think_time() + _deal_left(), false).timeout
        if game != _game:
            return
        var reply := await Core.request("step")
        if game != _game:  # restarted meanwhile; this move belonged to the old game
            return
        if not _apply(reply):
            break
    _ai_running = false

func _think_time() -> float:
    var r := THINK_PLAY
    if state.get("phase") != "playing":
        r = THINK_BID
    elif not state.get("has_move", true):
        r = THINK_FORCED
    return randf_range(r.x, r.y)

# ---- input ------------------------------------------------------------------

## Send one of the human's actions; the turn clock won't fire while it's in flight.
func _human(cmd: String, args := {}) -> bool:
    _requesting = true
    var ok := _apply(await Core.request(cmd, args))
    _requesting = false
    if ok:
        _run_ai()
    return ok

func _on_bid_pressed(want: bool) -> void:
    Sfx.play("click")
    _set_actions([])
    await _human("bid", {"call": want})

func _on_double_pressed(want: bool) -> void:
    Sfx.play("click")
    _set_actions([])
    await _human("double", {"double": want})

func _on_play_pressed() -> void:
    var ids := hand.selected_ids()
    if ids.is_empty():
        Sfx.play("error")
        return
    _fly_from = hand.card_positions(ids)
    if await _human("play", {"cards": ids}):
        hand.clear_selection()
    _fly_from = {}

func _on_pass_pressed() -> void:
    hand.clear_selection()
    await _human("pass")

## Nothing in hand beats the last play: say so, then pass on the player's behalf.
func _auto_pass() -> void:
    seats[ME].say("要不起")
    hand.clear_selection()
    await get_tree().create_timer(0.9, false).timeout
    if state.get("phase") == "playing" and int(state.get("current_seat", -1)) == ME \
            and not state.get("has_move", true):
        _on_pass_pressed()

## 智能提示: each press this turn offers the next-best move, wrapping around.
func _on_hint_pressed() -> void:
    Sfx.play("click")
    if _hint_turn != _turn:
        _hint_turn = _turn
        _hint_index = 0
    var reply := await Core.request("hint", {"index": _hint_index})
    _hint_index += 1
    var ids := []
    for id in reply.get("hint", []):
        ids.append(int(id))
    if ids.is_empty():
        _on_pass_pressed()
    else:
        hand.select_ids(ids)
        Sfx.play("select")

func _on_again_pressed() -> void:
    Sfx.play("click")
    await _new_game()

func _on_score_pressed() -> void:
    Sfx.play("click")
    _history.open(_score, _games)

func _gui_input(event: InputEvent) -> void:
    # a tap on empty table clears the selection
    if event is InputEventMouseButton and event.pressed:
        hand.clear_selection()

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    match event.keycode:
        KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
            _press_if_ready($Actions/PlayBtn)
        KEY_H:
            _press_if_ready($Actions/HintBtn)
        KEY_P:
            _press_if_ready($Actions/PassBtn)
        KEY_ESCAPE:
            hand.clear_selection()

func _press_if_ready(b: Button) -> void:
    if b.is_visible_in_tree() and not b.disabled:
        b.pressed.emit()

# ---- rendering ----------------------------------------------------------------

func _render(deal: bool) -> void:
    var phase: String = state["phase"]
    var current := int(state["current_seat"])
    var landlord := int(state["landlord_seat"])

    for seat in 3:
        var view := seats[seat]
        var count := int(state["card_counts"][seat])
        if landlord < 0:
            var bid = state["bids"][seat]
            view.set_info("", "" if bid == null else BID_TEXT[bid], count)
        else:
            view.set_info("landlord" if seat == landlord else "farmer",
                    "地主" if seat == landlord else "农民", count)
        view.set_doubled(state["doubles"][seat] == true)
        var active := seat == current and phase != "over"
        view.active = active
        if count > 0 and count <= 2 and count < _alarmed[seat] and phase == "playing":
            _alarmed[seat] = count
            if seat != ME:
                view.say("我只剩%d张牌啦！" % count, 1.8)
            Sfx.voice(_voices[seat], "last%d" % count, 0.9)
            Sfx.play("warning", -4.0)
            Sfx.music("bgm_warning")
        _render_play_area(seat, state["display"][seat])

    if landlord >= 0 and _last_landlord < 0:
        Sfx.play("select", -2.0)
        _on_landlord_decided(landlord)
    _last_landlord = landlord
    _render_bottom_cards(state["bottom_cards"])
    _render_multiplier()

    hand.set_cards(state["my_hand"], deal)
    if deal:
        _set_actions([])
        get_tree().create_timer(_deal_left(), false).timeout.connect(_render_actions)
    else:
        _render_actions()

func _deal_left() -> float:
    return maxf(0.0, (_deal_end - Time.get_ticks_msec()) / 1000.0)

## The button row for whoever's turn it is (only the human gets buttons).
func _render_actions() -> void:
    var phase: String = state["phase"]
    var current := int(state["current_seat"])
    if phase == "bidding" and current == ME:
        var rob: bool = state["bid_stage"] == "rob"
        $Actions/BidBtn.text = "抢地主" if rob else "叫地主"
        $Actions/NoBidBtn.text = "不抢" if rob else "不叫"
        _set_actions(["NoBidBtn", "BidBtn"])
    elif phase == "doubling" and current == ME:
        _set_actions(["NoDoubleBtn", "DoubleBtn"])
    elif phase == "playing" and current == ME and not state.get("has_move", true):
        _set_actions(["Waiting"])
        _auto_pass()
    elif phase == "playing" and current == ME:
        _set_actions(["PassBtn", "HintBtn", "PlayBtn"])
        $Actions/PassBtn.disabled = state["must_lead"]
        _update_play_button()
    elif phase == "over":
        _set_actions([])
        _show_result()
    else:
        _set_actions([])
    _start_clock()

# ---- turn clock ---------------------------------------------------------------

## (Re)start the 倒计时 for whoever acts now; a no-op if this turn's clock is already running.
func _start_clock() -> void:
    var phase: String = state["phase"]
    var current := int(state["current_seat"])
    var auto_pass: bool = current == ME and phase == "playing" and not state.get("has_move", true)
    if phase == "over" or current < 0 or auto_pass:
        _stop_clock()
        return
    if current == _clock_seat and _turn == _clock_turn:
        return
    _stop_clock()
    _clock_seat = current
    _clock_turn = _turn
    _clock_time = TURN_SECONDS[phase]
    _clock_left = -1
    if current == ME:
        _place_my_clock()

func _stop_clock() -> void:
    _clock_seat = -1
    _my_clock.stop()
    for s in seats:
        s.clock.stop()

## My clock sits just left of the action buttons, whichever of them are showing.
func _place_my_clock() -> void:
    await get_tree().process_frame
    var left := INF
    for child in $Actions.get_children():
        if child.visible:
            left = minf(left, child.global_position.x)
    if left == INF:
        left = $Actions.global_position.x + $Actions.size.x / 2
    _my_clock.global_position = Vector2(left - ClockView.SIZE.x - 16,
            $Actions.global_position.y + ($Actions.size.y - ClockView.SIZE.y) / 2)

func _process(delta: float) -> void:
    if _clock_seat < 0:
        return
    _clock_time -= delta
    var left := ceili(_clock_time)
    if left == _clock_left or (left <= 0 and _requesting):
        return
    _clock_left = left
    var view := _my_clock if _clock_seat == ME else seats[_clock_seat].clock
    view.set_seconds(maxi(left, 0))
    if _clock_seat != ME:
        return
    if left > 0 and left <= ClockView.URGENT_AT:
        Sfx.play("countdown")
    elif left <= 0:
        _stop_clock()
        _on_timeout()

## Out of time: don't call / don't double / pass, or lead the smallest single card.
func _on_timeout() -> void:
    if int(state.get("current_seat", -1)) != ME:
        return
    _toast("超时")
    match state["phase"]:
        "bidding":
            _on_bid_pressed(false)
        "doubling":
            _on_double_pressed(false)
        "playing":
            if state["must_lead"]:
                var smallest: int = CardView.sort_for_display(state["my_hand"]).back()
                hand.select_ids([smallest])
                _on_play_pressed()
            else:
                _on_pass_pressed()

func _set_actions(visible_names: Array) -> void:
    var i := 0
    for child in $Actions.get_children():
        var was: bool = child.visible
        child.visible = visible_names.has(child.name)
        if child is Button:
            child.disabled = false
        if child.visible and not was:  # pop the row in, one button after another
            child.scale = Vector2(0.5, 0.5)
            child.modulate.a = 0.0
            var t := child.create_tween().set_parallel()
            t.tween_property(child, "scale", Vector2.ONE, 0.25).set_delay(i * 0.05) \
                    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
            t.tween_property(child, "modulate:a", 1.0, 0.15).set_delay(i * 0.05)
            i += 1

func _update_play_button() -> void:
    $Actions/PlayBtn.disabled = hand.selected_ids().is_empty()

## My own 倍数: the shared one times the 加倍 that touch me. A farmer settles only with
## the landlord; the landlord settles with both farmers, so theirs is the sum of the two.
func _my_mult() -> int:
    var common := int(state["multiplier"])
    var landlord := int(state["landlord_seat"])
    if landlord < 0:
        return common
    var d: Array = state["doubles"]
    var k := func(seat: int) -> int: return 2 if d[seat] == true else 1
    if landlord == ME:
        return common * k.call(ME) * (k.call((ME + 1) % 3) + k.call((ME + 2) % 3))
    return common * k.call(landlord) * k.call(ME)

func _render_multiplier() -> void:
    var mult := _my_mult()
    mult_label.text = "×%d" % mult
    if mult > _last_mult:
        mult_label.pivot_offset = mult_label.size / 2
        var t := mult_label.create_tween()
        t.tween_property(mult_label, "scale", Vector2(1.6, 1.6), 0.1)
        t.tween_property(mult_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
    _last_mult = mult

func _render_play_area(seat: int, display) -> void:
    var key := JSON.stringify(display)
    if key == _shown_display[seat]:
        return
    _shown_display[seat] = key
    var area := play_areas[seat]
    for child in area.get_children():
        child.queue_free()
    if display == null:
        return
    if display["pass"]:
        var label := Label.new()
        label.text = "不出"
        label.add_theme_font_override("font", UiTheme.bold)
        label.add_theme_font_size_override("font_size", 34)
        label.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
        label.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.3))
        label.add_theme_constant_override("outline_size", 8)
        area.add_child(label)
        _fly_in(label, seat, 0, null)
        return
    var ids := CardView.sort_for_display(display["cards"])
    for i in ids.size():
        var card := CardView.make(ids[i], true, PLAYED_SCALE)
        area.add_child(card)
        _fly_in(card, seat, i, _fly_from.get(ids[i]))

## Bring a freshly played card in: from its spot in my hand, or out of the AI's avatar.
func _fly_in(node: Control, seat: int, i: int, from_global) -> void:
    node.modulate.a = 0.0
    await get_tree().process_frame  # let the container place it first
    if not is_instance_valid(node):
        return
    var area := node.get_parent() as Control
    var target := node.position
    node.pivot_offset = node.size / 2
    var start_scale := 0.4
    if from_global != null:
        node.position = from_global + HandView.CARD_SIZE / 2 - area.global_position - node.size / 2
        start_scale = HandView.CARD_SCALE / PLAYED_SCALE
    else:
        var src := seats[seat].avatar_global() if seat != ME else area.global_position + Vector2(area.size.x / 2, 120)
        node.position = src - area.global_position - node.size / 2
    node.scale = Vector2(start_scale, start_scale)
    var delay := 0.0 if from_global != null else i * 0.025
    var t := node.create_tween().set_parallel()
    t.tween_property(node, "position", target, 0.26).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    t.tween_property(node, "scale", Vector2.ONE, 0.26).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_property(node, "modulate:a", 1.0, 0.12).set_delay(delay)

func _render_bottom_cards(ids: Array) -> void:
    ids = CardView.sort_for_display(ids)
    var existing := bottom_cards.get_children()
    if ids.is_empty():
        if existing.size() == 3 and not (existing[0] as CardView).face_up:
            return
        for child in existing:
            child.queue_free()
        for i in 3:
            bottom_cards.add_child(CardView.make(-1, false, 0.6))
        return
    if (existing[0] as CardView).face_up:
        return
    for i in 3:  # turn the three backs over to reveal the bottom cards
        var card := existing[i] as CardView
        card.card_id = ids[i]
        card.flip(true, 0.15 + i * 0.12)
    if int(state["bottom_mult"]) > 1:
        get_tree().create_timer(0.7, false).timeout.connect(
                _show_bottom_tag.bind("%s ×%d" % [state["bottom_kind"], int(state["bottom_mult"])]))

## The 底牌倍数 pill under the bottom cards ("双王 ×4").
func _show_bottom_tag(text: String) -> void:
    _bottom_tag.text = text
    _bottom_tag.reset_size()
    _bottom_tag.global_position = bottom_panel.global_position + Vector2(
            (bottom_panel.size.x - _bottom_tag.size.x) / 2, bottom_panel.size.y + 6)
    _bottom_tag.pivot_offset = _bottom_tag.size / 2
    _bottom_tag.show()
    _bottom_tag.scale = Vector2(2, 2)
    _bottom_tag.create_tween().tween_property(_bottom_tag, "scale", Vector2.ONE, 0.3) \
            .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    Sfx.play("double", -4.0)

func _on_landlord_decided(landlord: int) -> void:
    _log_line("地主：%s · 底牌 %s%s" % [SEAT_NAMES[landlord], _cards_text(state["bottom_cards"]),
            "（%s ×%d）" % [state["bottom_kind"], int(state["bottom_mult"])] if int(state["bottom_mult"]) > 1 else ""])
    var text := "你是地主！" if landlord == ME else "%s 是地主" % SEAT_NAMES[landlord]
    fx.banner(text, Color(1, 0.82, 0.3), Vector2(-1, -1), 52, 0.6)
    if landlord != ME:
        var from := []
        for c in bottom_cards.get_children():
            from.append(c.global_position)
        fx.fly_cards(CardView.sort_for_display(state["bottom_cards"]), from,
                seats[landlord].avatar_global(), 0.6)

func _show_event(event: Dictionary) -> void:
    var seat := int(event["seat"])
    var view := seats[seat]
    match event["type"]:
        "bid":
            if event.get("redeal", false):
                _toast("重新发牌")
            var line: String = BID_VOICE[event["action"]]
            if event["action"] == "rob":
                _robs += 1
                line = ["bid_grab", "bid_grab2", "bid_grab3"][mini(_robs, 3) - 1]
                Sfx.play("double", -4.0)
            Sfx.voice(_voices[seat], line)
            view.say(BID_TEXT[event["action"]])
            _log_line("%s：%s" % [SEAT_NAMES[seat], BID_TEXT[event["action"]]])
            if event.get("redeal", false):
                _log_line("—— 都不叫，重新发牌 ——")
        "double":
            var action: String = event["action"]
            view.say(DOUBLE_TEXT[action])
            Sfx.voice(_voices[seat], DOUBLE_VOICE[action])
            if action == "double":
                Sfx.play("double", -4.0)
            _log_line("%s：%s" % [SEAT_NAMES[seat], DOUBLE_TEXT[action]])
        "play":
            var move_type: String = event.get("move_type", "")
            if seat == int(state.get("landlord_seat", -1)):
                _landlord_plays += 1
            Sfx.play("play")
            Sfx.voice(_voices[seat], _play_line(move_type, event.get("cards", []), seat))
            _callout(move_type, seat)
            _played[seat].append_array(event["cards"])
            _log_line("%s：%s %s" % [_who(seat), move_type, _cards_text(event["cards"])])
        "pass":
            Sfx.voice(_voices[seat], "pass")
            _log_line("%s：不出" % _who(seat))

## What a player says when playing: the rank for singles/pairs/trios, otherwise
## the move type, or now and then 大你/管上/压死 when beating someone's play.
func _play_line(move_type: String, cards: Array, seat: int) -> String:
    var id := int(cards[0])
    match move_type:
        "单张":
            if id >= 52:
                return "single_joker_big" if id == 53 else "single_joker_small"
            return "single_" + RANK_VOICE[id / 4]
        "对子":
            return "pair_" + RANK_VOICE[id / 4]
        "三张":
            return "trio_" + RANK_VOICE[id / 4]
        "炸弹", "王炸":
            return TYPE_VOICE[move_type]
    var following := false
    for s in 3:
        var d = state["display"][s]
        if s != seat and d is Dictionary and not d.get("pass", true):
            following = true
    if following and randf() < 0.5:
        return ["beat", "beat_bigger", "beat_cover"].pick_random()
    return TYPE_VOICE.get(move_type, "")

## Banners, particles and shakes for the flashy move types.
func _callout(move_type: String, seat: int) -> void:
    if not CALLOUTS.has(move_type):
        return
    var color: Color = CALLOUTS[move_type]
    var area := play_areas[seat]
    var at := area.global_position + area.size / 2
    match move_type:
        "炸弹":
            Sfx.play("bomb")
            Sfx.music("bgm_warning")
            fx.banner("炸弹", color)
            fx.burst(at, [Color(1, 1, 0.7), Color(1, 0.5, 0.1), Color(0.6, 0.1, 0.05, 0)], 140, 560)
            fx.ring(at, Color(1, 0.75, 0.3))
            fx.flash(Color(1, 0.6, 0.3, 0.45))
            _shake(10.0)
        "王炸":
            Sfx.music("bgm_warning")
            var from := seats[seat].avatar_global() if seat != ME else Vector2(fx.size.x / 2, fx.size.y - 60)
            fx.missile(from, func():
                Sfx.play("bomb")
                fx.banner("王炸", color, Vector2(-1, -1), 96, 0.9)
                _shake(16.0))
        "顺子", "连对":
            Sfx.play("straight")
            fx.streak(move_type, color, at.y)
        "飞机", "飞机带单", "飞机带对":
            Sfx.play("plane")
            fx.plane(move_type, color, at.y)
        _:
            fx.banner(move_type, color, at, 48, 0.4)

func _show_result() -> void:
    if result_panel.visible:
        return
    var won: bool = state["human_won"]
    var landlord := int(state["landlord_seat"])
    var counts: Array = state["card_counts"]
    var spring := ""
    if state["winner"] == "landlord" and int(counts[(landlord + 1) % 3]) == 17 \
            and int(counts[(landlord + 2) % 3]) == 17:
        spring = "春天"
    elif state["winner"] == "farmer" and _landlord_plays <= 1:
        spring = "反春"
    var mult := _my_mult() * (2 if spring != "" else 1)
    var delta := BASE_SCORE * mult * (1 if won else -1)
    _score += delta
    _games.append({"time": int(Time.get_unix_time_from_system()), "role":
            "landlord" if landlord == ME else "farmer", "won": won, "mult": mult, "delta": delta})
    _games = _games.slice(-HISTORY_KEEP)
    _save()
    _write_log(spring, delta)

    var delay := 0.6
    if spring != "":
        get_tree().create_timer(0.3, false).timeout.connect(func():
            Sfx.play("spring")
            fx.banner(spring + "！", Color(1, 0.5, 0.7), Vector2(-1, -1), 88, 0.8))
        delay = 1.6

    var title: Label = result_panel.get_node("VBox/Title")
    title.text = "胜 利" if won else "失 败"
    title.add_theme_color_override("font_color", Color(1, 0.84, 0.3) if won else Color(0.65, 0.75, 0.9))
    title.add_theme_font_override("font", UiTheme.bold)
    var delta_label: Label = result_panel.get_node("VBox/Delta")
    delta_label.text = "%+d 积分" % delta
    delta_label.add_theme_font_override("font", UiTheme.bold)
    delta_label.add_theme_color_override("font_color", Color(1, 0.75, 0.25) if won else Color(0.6, 0.85, 1))
    var detail := "倍数 ×%d" % mult
    if spring != "":
        detail += " · " + spring
    result_panel.get_node("VBox/Detail").text = detail
    _fill_result_hands()

    get_tree().create_timer(delay, false).timeout.connect(func():
        Sfx.music("")
        Sfx.play("win" if won else "lose")
        get_tree().create_timer(5.0, false).timeout.connect(func():
            if result_panel.visible:
                Sfx.music("bgm_welcome"))
        if won:
            fx.confetti()
        _render_score())
    dim.show()
    dim.modulate.a = 0.0
    dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.3).set_delay(delay - 0.2)
    result_panel.show()
    result_panel.pivot_offset = result_panel.size / 2
    result_panel.scale = Vector2(0.6, 0.6)
    result_panel.modulate.a = 0.0
    var t := result_panel.create_tween().set_parallel()
    t.tween_property(result_panel, "scale", Vector2.ONE, 0.35).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_property(result_panel, "modulate:a", 1.0, 0.2).set_delay(delay)

## One row per AI: name, role and the cards they were left holding.
func _fill_result_hands() -> void:
    var box: VBoxContainer = result_panel.get_node("VBox/Hands")
    for child in box.get_children():
        child.queue_free()
    var hands = state.get("hands")
    if not hands is Array:
        return
    var landlord := int(state["landlord_seat"])
    for seat in [2, 1]:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        var who := Label.new()
        who.text = "%s%s" % [SEAT_NAMES[seat], "(地主)" if seat == landlord else ""]
        who.custom_minimum_size.x = 120
        who.add_theme_color_override("font_color", SeatView.LANDLORD if seat == landlord else SeatView.FARMER)
        row.add_child(who)
        var cards := HBoxContainer.new()
        cards.add_theme_constant_override("separation", -26)
        var ids: Array = hands[seat]
        if ids.is_empty():
            var done := Label.new()
            done.text = "出完了"
            done.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
            cards.add_child(done)
        for id in CardView.sort_for_display(ids):
            cards.add_child(CardView.make(id, true, 0.5))
        row.add_child(cards)
        box.add_child(row)

# ---- 牌谱 ----------------------------------------------------------------------

func _who(seat: int) -> String:
    return "%s(%s)" % [SEAT_NAMES[seat], "地主" if seat == int(state["landlord_seat"]) else "农民"]

static func _cards_text(ids: Array) -> String:
    var parts := []
    for id in CardView.sort_for_display(ids):
        if id >= 52:
            parts.append("大王" if id == 53 else "小王")
        else:
            parts.append(CardView.SUITS[id % 4] + CardView.RANKS[id / 4])
    return " ".join(parts)

func _log_line(text: String) -> void:
    _log.append(text)

## Save the finished game to user://logs/ (keeping the newest LOG_KEEP). Starting hands are rebuilt from what was played plus
## what was left, since the AI hands are only revealed once the game is over.
func _write_log(spring: String, delta: int) -> void:
    var landlord := int(state["landlord_seat"])
    var lines: Array[String] = ["DouZero 斗地主 牌谱 · %s" % Time.get_datetime_string_from_system(false, true), ""]
    lines.append("起手牌（地主含底牌）：")
    for seat in 3:
        var start: Array = _played[seat] + Array(state["hands"][seat])
        lines.append("  %s：%s" % [_who(seat), _cards_text(start)])
    lines.append("")
    lines.append_array(_log)
    lines.append("")
    var doubles := []
    for seat in 3:
        if state["doubles"][seat] == true:
            doubles.append(SEAT_NAMES[seat])
    lines.append("结果：%s获胜 · 公共倍数 ×%d · 加倍 %s%s · 我 %+d 积分" % [
            "地主" if state["winner"] == "landlord" else "农民", int(state["multiplier"]),
            "、".join(doubles) if not doubles.is_empty() else "无",
            " · " + spring if spring != "" else "", delta])
    var text := "\n".join(lines) + "\n"
    DirAccess.make_dir_recursive_absolute(LOG_DIR)
    var name := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
    var f := FileAccess.open("%s/%s.txt" % [LOG_DIR, name], FileAccess.WRITE)
    if f:
        f.store_string(text)
        f.close()
    var files := Array(DirAccess.get_files_at(LOG_DIR))
    files.sort()
    for i in maxi(0, files.size() - LOG_KEEP):
        DirAccess.remove_absolute("%s/%s" % [LOG_DIR, files[i]])

func _hide_result() -> void:
    result_panel.hide()
    dim.hide()

func _toast(text: String) -> void:
    toast.text = text
    toast.reset_size()
    toast.position.x = (size.x - toast.size.x) / 2
    toast.modulate.a = 1.0
    if _toast_tween:
        _toast_tween.kill()
    _toast_tween = create_tween()
    _toast_tween.tween_interval(1.3)
    _toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)

func _shake(strength := 8.0) -> void:
    var t := create_tween()
    for i in 8:
        var k := strength * (1.0 - i / 8.0)
        t.tween_property(self, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.035)
    t.tween_property(self, "position", Vector2.ZERO, 0.035)

# ---- persistence --------------------------------------------------------------

## 斗地主's own sections of the save file: [player] score and [history] games.
func _load_save() -> void:
    _score = int(Save.value("player", "score", _score))
    _games = Save.value("history", "games", [])
    _render_score()

func _save() -> void:
    Save.store("player", "score", _score)
    Save.store("history", "games", _games)

func _render_score() -> void:
    score_label.text = "积分 %d ›" % _score
