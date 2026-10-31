extends Node
## Bridge to the DouZero algorithm core (C++ GDExtension `DouZeroCore`, built from core/).
## Godot only does UI and interaction; all rules and AI live in the core.
## Requests run on a worker thread so model inference never stalls a frame.

const MODELS_DIR := "res://models"

var _core: Object
var _busy := false

## Loads the extension and the models, on a worker thread so the loading screen keeps
## animating. Returns false (and logs why) on failure.
func start() -> bool:
    if not ClassDB.class_exists("DouZeroCore"):
        push_error("DouZeroCore extension not loaded; build it with: cmake --build core/build")
        return false
    _core = ClassDB.instantiate("DouZeroCore")
    var box := [false]
    var task := WorkerThreadPool.add_task(func(): box[0] = _core.load_models(MODELS_DIR))
    while not WorkerThreadPool.is_task_completed(task):
        await get_tree().process_frame
    WorkerThreadPool.wait_for_task_completion(task)
    if not box[0]:
        push_error(_core.get_error())
        return false
    return true

func error_text() -> String:
    return _core.get_error() if _core else "未找到算法核心扩展（core/ 需要先编译）"

## Sends one command and waits for its reply (see core/src/core.hpp for the protocol).
func request(cmd: String, args: Dictionary = {}) -> Dictionary:
    while _busy:
        await get_tree().process_frame
    _busy = true
    var box := [{}]  # lambdas capture locals by value; an array is shared
    var task := WorkerThreadPool.add_task(func(): box[0] = _core.request(cmd, args))
    while not WorkerThreadPool.is_task_completed(task):
        await get_tree().process_frame
    WorkerThreadPool.wait_for_task_completion(task)
    _busy = false
    return box[0]
