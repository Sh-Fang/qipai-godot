class_name App
extends Control
## Root of the 棋牌合集. Loads the core behind the 大厅, opens the game picked there and
## brings the player back. Owns what every game shares: 设置 (the gear, top-right), the
## 返回 button (top-left, in a game), the back/close confirmations and the phone safe area.
##
## A game scene's root script provides:
##   start()           deal / set up the first game, once the scene is in the tree
##   restart()         abandon the current game for a new one (设置 → 重新开始)
##   in_progress()     whether leaving now abandons a game
##   forfeit_note()    what abandoning it costs, shown when asking ("本局不计分")
## and may emit `leave_requested` (返回大厅 on its result panel: no question asked).
## It keeps its top-left corner clear for the 返回 button and its top-right corner for
## the gear (see CORNER).

## Scene of each game the lobby can open.
const GAMES := {"doudizhu": "res://scenes/doudizhu.tscn", "gomoku": "res://scenes/gomoku.tscn"}
## Extra room kept clear along the screen edges on phones (rounded corners, camera
## cutout), on top of whatever the system reports as unsafe.
const PHONE_PAD := Vector2(40, 10)
## The corner buttons sit this far in from the (safe) screen edge.
const CORNER := Vector2(16, 12)
const LOBBY_MUSIC := "bgm_welcome"

## Insets (left, top, right, bottom) of the safe area on phones; zero on desktop unless
## run with `-- --phone`.
static var edge := Vector4.ZERO

var game: Control  # the open game, null in the lobby
var _host: Control
var _lobby: LobbyView
var _back: RoundButton
var _gear: RoundButton
var _settings: SettingsView
var _confirm: ConfirmView
var _sound_on := true
var _music_on := true

func _enter_tree() -> void:
    theme = UiTheme.build()  # before children's _ready, which use its fonts

func _ready() -> void:
    _measure_edges()
    _host = Control.new()
    _host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_host)
    _lobby = LobbyView.new()
    _lobby.game_chosen.connect(_open_game)
    add_child(_lobby)
    _back = _corner_button(RoundButton.Kind.BACK, "返回大厅", false, _ask_leave)
    _gear = _corner_button(RoundButton.Kind.GEAR, "设置", true, _on_settings_pressed)
    _settings = SettingsView.new()
    _settings.sound_changed.connect(func(on: bool):
        _sound_on = on
        _apply_audio()
        Save.store("settings", "sound", on))
    _settings.music_changed.connect(func(on: bool):
        _music_on = on
        _apply_audio()
        Save.store("settings", "music", on))
    _settings.restart_confirmed.connect(func(): game.restart())
    add_child(_settings)
    _confirm = ConfirmView.new()
    add_child(_confirm)

    var muted := bool(Save.value("settings", "muted", false))  # before 音效/音乐 were split
    _sound_on = bool(Save.value("settings", "sound", not muted))
    _music_on = bool(Save.value("settings", "music", not muted))
    _apply_audio()
    Sfx.music(LOBBY_MUSIC)
    if OS.get_cmdline_user_args().has("--autotest"):
        var bot := Node.new()
        bot.set_script(load("res://scripts/autotest.gd"))
        add_child(bot)
    # the model load gives no progress of its own, so ease the bar towards 90% meanwhile
    var bar := create_tween()
    bar.tween_method(_lobby.set_progress, 0.0, 0.9, 2.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
    var ok: bool = await Core.start()
    bar.kill()
    if not ok:
        _lobby.fail("算法核心加载失败：\n" + Core.error_text())
        return
    _lobby.loaded(GAMES.keys())
    _gear.show()

## On phones, keep clear of rounded corners and the camera cutout.
func _measure_edges() -> void:
    if not OS.has_feature("mobile") and not OS.get_cmdline_user_args().has("--phone"):
        return
    var safe := Rect2(DisplayServer.get_display_safe_area())
    var screen := Vector2(DisplayServer.screen_get_size())
    var k := size / Vector2(get_window().size)  # screen pixels -> UI units
    edge = Vector4(
            maxf(safe.position.x * k.x, 0.0) + PHONE_PAD.x,
            maxf(safe.position.y * k.y, 0.0) + PHONE_PAD.y,
            maxf((screen.x - safe.end.x) * k.x, 0.0) + PHONE_PAD.x,
            maxf((screen.y - safe.end.y) * k.y, 0.0) + PHONE_PAD.y)

## Move a node anchored to a screen edge inwards by the safe-area insets.
static func pad(c: Control) -> void:
    if c.anchor_left == 0.0: c.offset_left += edge.x
    if c.anchor_right == 0.0: c.offset_right += edge.x
    if c.anchor_left == 1.0: c.offset_left -= edge.z
    if c.anchor_right == 1.0: c.offset_right -= edge.z
    if c.anchor_top == 0.0: c.offset_top += edge.y
    if c.anchor_bottom == 0.0: c.offset_bottom += edge.y
    if c.anchor_top == 1.0: c.offset_top -= edge.w
    if c.anchor_bottom == 1.0: c.offset_bottom -= edge.w

func _corner_button(kind: RoundButton.Kind, label: String, right: bool, action: Callable) -> RoundButton:
    var b := RoundButton.make(kind, label)
    b.set_anchors_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
    if right:
        b.offset_right = -CORNER.x
        b.offset_left = b.offset_right - RoundButton.SIZE.x
    else:
        b.offset_left = CORNER.x
        b.offset_right = b.offset_left + RoundButton.SIZE.x
    b.offset_top = CORNER.y
    b.offset_bottom = b.offset_top + RoundButton.SIZE.y
    pad(b)
    b.pressed.connect(action)
    b.hide()  # the gear once the core has loaded, 返回 inside a game
    add_child(b)
    return b

func _open_game(id: String) -> void:
    game = load(GAMES[id]).instantiate()
    _host.add_child(game)
    if game.has_signal("leave_requested"):
        game.leave_requested.connect(_leave)
    _back.show()
    game.start()

func _leave() -> void:
    game.queue_free()
    game = null
    _back.hide()
    _lobby.reopen()
    Sfx.music(LOBBY_MUSIC)

## What leaving now costs, "" when no game is under way.
func _forfeit_note() -> String:
    return game.forfeit_note() if game and game.in_progress() else ""

func _on_settings_pressed() -> void:
    Sfx.play("click")
    _settings.open(_sound_on, _music_on, game != null, _forfeit_note())

func _ask_leave() -> void:
    Sfx.play("click")
    _confirm.ask("返回大厅？", "返回大厅", _forfeit_note(), _leave)

func _ask_quit() -> void:
    Sfx.play("click")
    _confirm.ask("退出游戏？", "退出", _forfeit_note(), func(): get_tree().quit())

## Leaving asks first (auto_accept_quit and quit_on_go_back are off). Android back closes
## whichever panel is open, like any other app; then in a game it offers the 大厅, and in
## the 大厅 it offers to quit.
func _notification(what: int) -> void:
    if _confirm == null:
        return
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if not _confirm.visible:
            _ask_quit()
    elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
        for m: Modal in get_tree().get_nodes_in_group(Modal.GROUP):
            if m.visible:
                m.close()
                return
        if game:
            _ask_leave()
        else:
            _ask_quit()

func _apply_audio() -> void:
    Sfx.set_sound_on(_sound_on)
    Sfx.set_music_on(_music_on)
