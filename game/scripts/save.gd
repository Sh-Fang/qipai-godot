class_name Save
## user://save.cfg, shared by the app (设置, under [settings]) and the games, each in
## sections of its own. Every write goes straight to disk.

const PATH := "user://save.cfg"

static var _cfg: ConfigFile

static func value(section: String, key: String, default: Variant = null) -> Variant:
    if not _file().has_section_key(section, key):
        return default
    return _cfg.get_value(section, key)

static func store(section: String, key: String, v: Variant) -> void:
    _file().set_value(section, key, v)
    _cfg.save(PATH)

static func _file() -> ConfigFile:
    if _cfg == null:
        _cfg = ConfigFile.new()
        _cfg.load(PATH)  # missing on the first run: start empty
    return _cfg
