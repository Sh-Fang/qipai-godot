class_name DouZeroAgent
extends RefCounted

## Model bridge for the three DouZero ONNX policies.
## The native ONNX Runtime plugin will implement infer() later.

const POSITIONS := ["landlord", "landlord_up", "landlord_down"]
const MODEL_PATHS := {
    "landlord": "res://models/landlord.onnx",
    "landlord_up": "res://models/landlord_up.onnx",
    "landlord_down": "res://models/landlord_down.onnx",
}

var native_runtime: Object = null

func _init() -> void:
    # Reserved for the Android/iOS ONNX Runtime GDExtension or Android plugin.
    # Keeping this optional lets the project open before the native bridge exists.
    if Engine.has_singleton("DouZeroONNX"):
        native_runtime = Engine.get_singleton("DouZeroONNX")

func model_exists(position: String) -> bool:
    return MODEL_PATHS.has(position) and FileAccess.file_exists(MODEL_PATHS[position])

func status() -> String:
    var models_ok := true
    for position in POSITIONS:
        models_ok = models_ok and model_exists(position)
    if native_runtime == null:
        return "模型已就绪；等待 ONNX Runtime 原生插件"
    if not models_ok:
        return "缺少模型文件"
    return "ONNX Runtime 原生插件已连接"

func infer(position: String, z_batch: PackedFloat32Array, x_batch: PackedFloat32Array, action_count: int, x_dim: int) -> PackedFloat32Array:
    if native_runtime == null:
        push_warning("DouZeroONNX plugin is not installed yet")
        return PackedFloat32Array()
    return native_runtime.infer(position, z_batch, x_batch, action_count, x_dim)
