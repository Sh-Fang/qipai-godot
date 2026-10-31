#include "core.hpp"

#include <random>

namespace dz {

Core::Core(std::unique_ptr<Policy> policy)
    : policy_(std::move(policy)), session_(*policy_, std::random_device{}()) {}

json Core::handle(const json& req) {
    const std::string cmd = req.value("cmd", "");
    json resp = {{"id", req.value("id", json(nullptr))}, {"ok", true}, {"event", nullptr}};
    try {
        if (cmd == "new_game") {
            if (req.contains("seed")) session_.reseed(req["seed"].get<uint64_t>());
            session_.new_game();
        } else if (cmd == "state") {
        } else if (cmd == "step") {
            resp["event"] = session_.step();
        } else if (cmd == "bid") {
            resp["event"] = session_.human_bid(req.value("call", false));
        } else if (cmd == "double") {
            resp["event"] = session_.human_double(req.value("double", false));
        } else if (cmd == "play") {
            resp["event"] = session_.human_play(req.value("cards", CardIds{}));
        } else if (cmd == "pass") {
            resp["event"] = session_.human_pass();
        } else if (cmd == "hint") {
            resp["hint"] = session_.hint(req.value("index", 0));
        } else if (cmd == "debug_setup") {
            session_.setup(req.at("hands").get<std::array<CardIds, 3>>(), req.at("bottom").get<CardIds>(),
                           req.value("landlord", -1), req.value("bid_start", 0));
        } else if (cmd == "debug_eval" && session_.bidding()) {
            resp["bid_score"] = session_.bid_score(session_.current_seat());
        } else if (cmd == "debug_eval") {
            const auto& env = session_.env();
            resp["actions"] = env.legal();
            resp["values"] = env.over() ? std::vector<float>{} : policy_->evaluate(env);
        } else if (cmd == "debug_play") {
            resp["event"] = session_.force_play(req.at("ranks").get<Move>());
        } else {
            throw RuleError("unknown cmd " + cmd);
        }
    } catch (const RuleError& e) {
        resp["ok"] = false;
        resp["error"] = e.what();
    } catch (const std::exception& e) {  // keep serving even on bugs
        resp["ok"] = false;
        resp["error"] = std::string("core error: ") + e.what();
    }
    resp["state"] = session_.state();
    return resp;
}

std::string Core::handle_line(const std::string& line) {
    json req;
    try {
        req = json::parse(line);
    } catch (const std::exception& e) {
        return json{{"ok", false}, {"error", std::string("bad json: ") + e.what()}}.dump();
    }
    return handle(req).dump();
}

}  // namespace dz
