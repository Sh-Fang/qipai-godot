extends Control

var agent := DouZeroAgent.new()
@onready var status_label: Label = $Margin/VBox/Status
@onready var log_label: Label = $Margin/VBox/Log

func _ready() -> void:
    status_label.text = agent.status()
    log_label.text = "三个 WP ONNX 模型已放入 res://models/\n下一步：接入 ONNX Runtime 原生插件，再接入牌型和状态编码。"

func _on_check_models_pressed() -> void:
    var lines: PackedStringArray = []
    for position in DouZeroAgent.POSITIONS:
        var state := "OK" if agent.model_exists(position) else "MISSING"
        lines.append("%-14s %s" % [position, state])
    log_label.text = "模型文件检查：\n" + "\n".join(lines)
    status_label.text = agent.status()

func _on_next_step_pressed() -> void:
    log_label.text = "下一步开发顺序：\n1. 移植合法动作生成\n2. 实现 DouZero 特征编码\n3. 接入 Android/iOS ONNX Runtime 插件"
