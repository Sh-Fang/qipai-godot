// The algorithm core's single entry point: one JSON request in, one JSON reply out.
//
// Request:  {"cmd": "new_game" | "state" | "step" | "bid" | "play" | "pass" | "hint", ...}
// Reply:    {"ok": true, "event": {...} | null, "state": {...}, "hint"?: [...]}
//           {"ok": false, "error": "管不上", "state": {...}}
// 五子棋 commands start with "gomoku_" and reply with the 五子棋 state instead.
//
// Godot calls this through the GDExtension wrapper; tests call it through
// the douzero-cli JSON-lines tool.
#pragma once

#include <memory>
#include <string>

#include "gomoku.hpp"
#include "session.hpp"

namespace dz {

class Core {
public:
    explicit Core(std::unique_ptr<Policy> policy);

    json handle(const json& req);
    std::string handle_line(const std::string& line);

private:
    std::unique_ptr<Policy> policy_;
    Session session_;
    gomoku::Session gomoku_;
    json handle_gomoku(const std::string& cmd, const json& req, json& resp);
};

}  // namespace dz
