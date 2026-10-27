#include "douzero_core.hpp"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void DouZeroCore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_models", "dir"), &DouZeroCore::load_models);
    ClassDB::bind_method(D_METHOD("request", "cmd", "args"), &DouZeroCore::request, DEFVAL(Dictionary()));
    ClassDB::bind_method(D_METHOD("get_error"), &DouZeroCore::get_error);
}

bool DouZeroCore::load_models(const String& dir) {
    // Read through FileAccess so models packed into an exported .pck/.apk work too.
    std::array<std::vector<char>, 4> models;
    for (int i = 0; i < 4; ++i) {
        String path = dir.path_join(String(dz::Policy::model_name(i)) + ".onnx");
        PackedByteArray bytes = FileAccess::get_file_as_bytes(path);
        if (bytes.is_empty()) {
            error_ = "无法读取模型 " + path;
            return false;
        }
        models[i].assign(reinterpret_cast<const char*>(bytes.ptr()),
                         reinterpret_cast<const char*>(bytes.ptr()) + bytes.size());
    }
    try {
        core_ = std::make_unique<dz::Core>(std::make_unique<dz::Policy>(models));
    } catch (const std::exception& e) {
        error_ = String("加载模型失败：") + e.what();
        return false;
    }
    return true;
}

Dictionary DouZeroCore::request(const String& cmd, const Dictionary& args) {
    if (!core_) return Dictionary();
    Dictionary req = args.duplicate();
    req["cmd"] = cmd;
    CharString line = JSON::stringify(req).utf8();
    std::string reply = core_->handle_line(line.get_data());
    return JSON::parse_string(String::utf8(reply.c_str(), static_cast<int64_t>(reply.size())));
}
