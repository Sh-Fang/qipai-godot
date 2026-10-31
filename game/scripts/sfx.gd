extends Node
## Audio (autoload `Sfx`), using the 欢乐斗地主 sound set in audio/hlddz/ (mp3), plus
## our own sounds anywhere else under audio/ (ogg), named by path: "guofeng/stone-1".
## `play()` fires a one-shot effect, `voice()` speaks a line in a male or female
## voice, `music()` switches the looping background track. Effects and voices go to
## the "Sound" bus and music to "Music", so 设置 can switch them off separately.
## Runs while the game is paused, so the settings panel still clicks and music plays on.

const DIR := "res://audio/hlddz/"
const FREE_DIR := "res://audio/"
const POOL_SIZE := 6
const MUSIC_DB := -9.0
const PASS_LINES := {
    "male": ["pass_buyao", "pass_guo", "pass", "pass_peng"],
    "female": ["pass_buyao", "pass_guo", "pass_kan", "pass_yaobuqi"],
}

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _voices := {}  # gender -> player, so a new line cuts off that voice's last one
var _music: AudioStreamPlayer
var _track := ""
var _fade: Tween

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for bus in ["Sound", "Music"]:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
    for i in POOL_SIZE:
        _players.append(_player("Sound"))
    for g in PASS_LINES:
        _voices[g] = _player("Sound")
    _music = _player("Music")

func set_sound_on(on: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Sound"), not on)

func set_music_on(on: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not on)

## One-shot effect from sfx/ (deal, select, play, bomb, plane, straight, win, ...), or a
## sound by its path under audio/ ("guofeng/stone-1").
func play(key: String, volume_db := 0.0) -> void:
    var stream := _load(key if "/" in key else "sfx/" + key)
    if stream:
        var p := _players[_next]
        _next = (_next + 1) % _players.size()
        _start(p, stream, volume_db)

## Fade out an effect that's still playing (the deal sound runs past the deal).
func stop(key: String, fade := 0.2) -> void:
    var stream := _load("sfx/" + key)
    for p in _players:
        if p.playing and p.stream == stream:
            var t := p.create_tween()
            t.tween_property(p, "volume_db", -40.0, fade)
            t.tween_callback(p.stop)

## A spoken line from voice/<gender>/, e.g. "single_A", "type_bomb", "bid_call".
## "pass" picks one of the gender's several ways of saying 不要.
func voice(gender: String, line: String, delay := 0.0) -> void:
    if line == "":
        return
    if line == "pass":
        line = PASS_LINES[gender].pick_random()
    var stream := _load("voice/%s/%s" % [gender, line])
    if not stream:
        return
    if delay > 0.0:
        await get_tree().create_timer(delay).timeout
    _start(_voices[gender], stream)

## Loop a track from bgm/ (bgm_welcome, bgm_normal, bgm_warning), or one by its path
## under audio/ ("local/lobby"); "" stops the music. A missing track just stays silent.
func music(track: String) -> void:
    if track == _track:
        return
    _track = track
    if _fade:
        _fade.kill()
    _fade = _music.create_tween()
    if _music.playing:
        _fade.tween_property(_music, "volume_db", -40.0, 0.4)
    _fade.tween_callback(func():
        _music.stop()
        if track == "":
            return
        var stream := _load(track if "/" in track else "bgm/" + track)
        if not stream:
            return
        stream.set("loop", true)  # both mp3 and ogg streams have it
        _start(_music, stream, MUSIC_DB))

## Turn the music down for a few seconds, under a jingle, then back up.
func duck(seconds: float, by_db := 10.0) -> void:
    if not _music.playing:
        return
    if _fade:
        _fade.kill()
    _fade = _music.create_tween()
    _fade.tween_property(_music, "volume_db", MUSIC_DB - by_db, 0.3)
    _fade.tween_interval(seconds)
    _fade.tween_property(_music, "volume_db", MUSIC_DB, 1.5)

## Stop everything on quit, or a sound still playing leaks its stream.
func _exit_tree() -> void:
    for p in get_children():
        p.stop()
        p.stream = null

func _load(path: String) -> AudioStream:
    if not _cache.has(path):
        var full := DIR + path + ".mp3"
        if not ResourceLoader.exists(full) and ResourceLoader.exists(FREE_DIR + path + ".ogg"):
            full = FREE_DIR + path + ".ogg"
        _cache[path] = load(full) if ResourceLoader.exists(full) else null
        if _cache[path] == null:
            push_warning("missing sound: " + full)
    return _cache[path]

func _start(p: AudioStreamPlayer, stream: AudioStream, volume_db := 0.0) -> void:
    p.stream = stream
    p.volume_db = volume_db
    p.play()

func _player(bus: String) -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.bus = bus
    add_child(p)
    return p
