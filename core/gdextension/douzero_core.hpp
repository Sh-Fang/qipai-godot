// Godot-facing wrapper: exposes the core's request(cmd, args) to GDScript.
#pragma once

#include <memory>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "core.hpp"

class DouZeroCore : public godot::RefCounted {
    GDCLASS(DouZeroCore, godot::RefCounted)

public:
    // Load landlord / landlord_down / landlord_up / bid .onnx from a res:// or user:// folder.
    bool load_models(const godot::String& dir);
    // Same request/reply dictionaries the protocol describes (see core.hpp).
    godot::Dictionary request(const godot::String& cmd, const godot::Dictionary& args);
    godot::String get_error() const { return error_; }

protected:
    static void _bind_methods();

private:
    std::unique_ptr<dz::Core> core_;
    godot::String error_;
};
