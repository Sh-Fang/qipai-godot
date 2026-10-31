extends Node
## Smoke test: `godot --path game -- --autotest` presses 开始游戏 on the home screen, plays
## one game through the real UI (bid, double, then follow the hint each turn), saves
## screenshots to user://autotest/, and quits.
## `-- --autotest --fxdemo` instead fires each table effect once and screenshots it.
## `-- --autotest --cards` screenshots the jokers and some face cards.
## `-- --autotest --timeout` lets every one of the human's clocks run out.
## `-- --autotest --select` drags across 9 9 9 8 7, taps the 8 off, plays 999+7 and checks
## that nothing is left selected.
## `-- --autotest --settings` opens 设置 mid-game and checks that the game holds still,
## then restarts through the confirmation, opens the 积分记录 and walks Android back through
## closing it, asking 退出游戏？ and cancelling.

const DEAL_WAIT := 2.0

var main: Node
var _shot := 0

func _ready() -> void:
    main = get_parent()
    DirAccess.make_dir_recursive_absolute("user://autotest")
    for i in 3:  # the first frames haven't been drawn yet
        await get_tree().process_frame
    _screenshot("loading")
    while not main._home._start.visible:  # still loading the core
        await get_tree().process_frame
    await get_tree().create_timer(0.6).timeout
    _screenshot("home")
    main._home._on_start()
    await get_tree().create_timer(0.5).timeout
    if OS.get_cmdline_user_args().has("--cards"):
        _card_gallery()
    elif OS.get_cmdline_user_args().has("--select"):
        _select_check()
    elif OS.get_cmdline_user_args().has("--settings"):
        _settings_check()
    elif OS.get_cmdline_user_args().has("--fxdemo"):
        _fx_demo()
    else:
        _loop(OS.get_cmdline_user_args().has("--timeout"))

## Jokers, a 10 and a few faces at hand size on a plain backdrop, for checking card art.
func _card_gallery() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.2, 0.45, 0.3)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    main.fx.add_child(bg)
    var x := 20.0
    for id in [53, 52, 29, 28, 32, 37, 42, 47, 4]:
        var c := CardView.make(id, true, HandView.CARD_SCALE)
        c.position = Vector2(x, 200)
        bg.add_child(c)
        x += HandView.CARD_SIZE.x + 8
    await get_tree().create_timer(2.0).timeout  # let the deal animation clear
    _screenshot("cards")
    get_tree().quit()

func _select_check() -> void:
    # me: 9♠9♥9♣ 8♠ 7♠ + low junk, landlord and leading
    var mine := [24, 25, 26, 20, 16, 0, 1, 4, 5, 8, 9, 12, 13, 28, 32, 36, 40]
    var rest := []
    for id in 54:
        if not mine.has(id):
            rest.append(id)
    main._apply(await Core.request("debug_setup", {"hands": [mine, rest.slice(0, 17), rest.slice(17, 34)],
            "bottom": rest.slice(34, 37), "landlord": 0}), true)
    await get_tree().create_timer(2.5).timeout
    var hand: HandView = main.hand
    var hints := []
    for i in 3:  # 智能提示 should offer a different move on each press
        await main._on_hint_pressed()
        hints.append(hand.selected_ids())
    print("hints: ", hints)
    hand.clear_selection()
    var at := func(id: int) -> Vector2:  # a point on the card's visible index strip
        for c in hand.cards:
            if c.card_id == id:
                return c.global_position + Vector2(12, 60)
        return Vector2.ZERO
    _drag(at.call(24), at.call(16))  # 9♠ ... 7♠ (display order: 9♠9♥9♣8♠7♠)
    await get_tree().create_timer(0.4).timeout
    print("after drag: ", hand.selected_ids())
    _drag(at.call(20), at.call(20))  # tap 8♠ off
    await get_tree().create_timer(0.4).timeout
    print("after tap: ", hand.selected_ids())
    _screenshot("select_before_play")
    await main._on_play_pressed()
    print("played: ", main.state["display"][0])
    await get_tree().create_timer(1.5).timeout
    _screenshot("select_after_play")
    var raised := []
    for c in hand.cards:
        if c.selected or c.position.y < c.base_y - 1:
            raised.append(c.card_id)
    print("AUTOTEST DONE selected_after_play=", hand.selected_ids(), " raised=", raised)
    get_tree().quit()

func _settings_check() -> void:
    await get_tree().create_timer(DEAL_WAIT).timeout
    main._on_settings_pressed()
    var before := JSON.stringify(main.state)
    var clock: float = main._clock_time
    await get_tree().create_timer(4.0).timeout  # process_always: this one runs while paused
    _screenshot("settings")
    var held: bool = JSON.stringify(main.state) == before and is_equal_approx(main._clock_time, clock)
    main._settings.close()
    await get_tree().create_timer(4.0).timeout
    var resumed: bool = JSON.stringify(main.state) != before or main._clock_time < clock
    # 重新开始 → confirm: a fresh deal, and the old game's AI loop must not touch it
    main._on_settings_pressed()
    main._settings._ask_restart()
    await get_tree().create_timer(0.5).timeout
    _screenshot("restart_confirm")
    var game: int = main._game
    main._settings._confirm.get_child(2).get_child(1).pressed.emit()
    await get_tree().create_timer(DEAL_WAIT + 3.0).timeout
    var restarted: bool = main._game == game + 1 and main.state["phase"] == "bidding"
    main._games = [{"time": 1761900000, "role": "landlord", "won": true, "mult": 8, "delta": 80},
            {"time": 1761903600, "role": "farmer", "won": false, "mult": 2, "delta": -20}]
    main._on_score_pressed()
    await get_tree().create_timer(0.5).timeout
    _screenshot("history")
    # Android back: closes the open panel first, then asks before quitting; back again cancels
    var back := func(): get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
    back.call()
    var back_closes: bool = not main._history.visible and not main._quit.visible
    back.call()
    await get_tree().create_timer(0.5).timeout
    _screenshot("quit")
    var asks: bool = main._quit.visible and main._quit._warn.visible and get_tree().paused
    back.call()
    var cancels: bool = not main._quit.visible and not get_tree().paused
    print("AUTOTEST DONE paused_held=", held, " resumed=", resumed, " restarted=", restarted,
            " back_closes=", back_closes, " quit_asks=", asks, " quit_cancels=", cancels)
    get_tree().quit()

## Press at `from`, move to `to`, release, through the real input pipeline.
func _drag(from: Vector2, to: Vector2) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    get_viewport().push_input(press, true)
    for k in [0.5, 1.0]:
        var move := InputEventMouseMotion.new()
        move.position = from.lerp(to, k)
        move.button_mask = MOUSE_BUTTON_MASK_LEFT
        get_viewport().push_input(move, true)
    var release := press.duplicate()
    release.pressed = false
    release.position = to
    get_viewport().push_input(release, true)

func _fx_demo() -> void:
    await get_tree().create_timer(0.25).timeout
    _screenshot("dealing")
    await get_tree().create_timer(2.0).timeout
    for move in [["顺子", 1, [0.25]], ["飞机带单", 2, [0.7]], ["炸弹", 2, [0.2]],
            ["王炸", 1, [0.35, 0.3, 0.55, 0.25, 0.1]], ["王炸", 0, [0.4, 1.0]], ["四带二", 0, [0.2]]]:
        main._callout(move[0], move[1])
        for wait in move[2]:  # several frames for the longer effects
            await get_tree().create_timer(wait).timeout
            _screenshot(move[0])
        await get_tree().create_timer(1.5).timeout
    main.seats[2].say("我只剩2张牌啦！")
    main.fx.confetti()
    await get_tree().create_timer(1.0).timeout
    _screenshot("confetti")
    get_tree().quit()

func _loop(idle := false) -> void:
    var turns := 0
    var shots := {}
    while turns < 200:
        await get_tree().create_timer(0.1 if idle else 0.5).timeout
        var st: Dictionary = main.state
        if st.is_empty() or main._ai_running:
            continue
        if st["phase"] == "over":
            await get_tree().create_timer(1.2).timeout
            _screenshot("result")
            print("AUTOTEST DONE human_won=", st["human_won"], " winner=", st["winner"])
            get_tree().quit()
            return
        if int(st["current_seat"]) != 0 or main.get_node("Actions/Waiting").visible \
                or (st["phase"] == "playing" and not st.get("has_move", true)):
            continue  # the UI passes for us when nothing beats the last play
        if idle:  # let the clock decide; snap each phase once just before it runs out
            if not shots.has(st["phase"]) and main._clock_left == 1:
                shots[st["phase"]] = true
                _screenshot("timeout_" + st["phase"])
                if st["phase"] == "playing":
                    await get_tree().create_timer(2.5).timeout
                    _screenshot("timeout_after")
                    print("AUTOTEST DONE timeouts=", shots.keys())
                    get_tree().quit()
                    return
            continue
        turns += 1
        print("t=%.1f turn %d phase %s cards %s" % [Time.get_ticks_msec() / 1000.0, turns, st["phase"], str(st["card_counts"])])
        if st["phase"] == "bidding":
            _screenshot("bidding")
            main._on_bid_pressed(true)
        elif st["phase"] == "doubling":
            await get_tree().create_timer(0.8).timeout  # bottom-cards tag pops in
            _screenshot("doubling")
            main._on_double_pressed(true)
        else:
            await main._on_hint_pressed()
            await get_tree().create_timer(0.3).timeout
            if turns % 4 == 1:
                _screenshot("turn")
            if main.hand.selected_ids().is_empty():
                main._on_pass_pressed()
            else:
                main._on_play_pressed()

func _screenshot(tag: String) -> void:
    if DisplayServer.get_name() == "headless":  # logic-only run, nothing to capture
        return
    var path := "user://autotest/%02d_%s.png" % [_shot, tag]
    _shot += 1
    get_viewport().get_texture().get_image().save_png(path)
    print("screenshot ", ProjectSettings.globalize_path(path))
