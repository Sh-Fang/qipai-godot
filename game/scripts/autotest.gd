extends Node
## Smoke test: `godot --path game -- --autotest` plays one game through the real UI
## (bid, then follow the hint each turn), saves screenshots to user://autotest/, and quits.

var main: Node
var _shot := 0

func _ready() -> void:
    main = get_parent()
    DirAccess.make_dir_recursive_absolute("user://autotest")
    _loop()

func _loop() -> void:
    var turns := 0
    while turns < 200:
        await get_tree().create_timer(0.5).timeout
        var st: Dictionary = main.state
        if st.is_empty() or main._ai_running:
            continue
        if st["phase"] == "over":
            await get_tree().create_timer(1.2).timeout
            _screenshot("result")
            print("AUTOTEST DONE human_won=", st["human_won"], " winner=", st["winner"])
            get_tree().quit()
            return
        if int(st["current_seat"]) != 0:
            continue
        turns += 1
        if st["phase"] == "bidding":
            _screenshot("bidding")
            main._on_bid_pressed(true)
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
    var path := "user://autotest/%02d_%s.png" % [_shot, tag]
    _shot += 1
    get_viewport().get_texture().get_image().save_png(path)
    print("screenshot ", ProjectSettings.globalize_path(path))
