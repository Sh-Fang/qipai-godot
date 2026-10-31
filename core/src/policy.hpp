// DouZero WP models via ONNX Runtime: score every legal move, play the best.
// A 四带二 / 四带两对 is only played over another move when it scores clearly
// higher (by FOUR_WITH_TWO_MARGIN): otherwise the model happily breaks up a bomb
// just to shed six cards.
// Plus the 叫地主 model (bid.onnx, see reference/scripts/export_bid_model.py).
#pragma once

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "game.hpp"

namespace dz {

constexpr float FOUR_WITH_TWO_MARGIN = 0.05f;

class Policy {
public:
    // Serialized .onnx models: one per Position, then the bid model (index BID_MODEL).
    static constexpr int BID_MODEL = 3;
    static const char* model_name(int index);  // "landlord", ..., "bid"
    explicit Policy(const std::array<std::vector<char>, 4>& models);
    ~Policy();

    // Load landlord / landlord_down / landlord_up / bid .onnx from a directory.
    static std::unique_ptr<Policy> from_dir(const std::string& dir);

    // Model value of each env.legal() move for the acting position.
    std::vector<float> evaluate(const GameEnv& env);
    // env.legal() from best to worst (model value, 四带二 handicapped).
    std::vector<Move> ranked(const GameEnv& env);
    Move act(const GameEnv& env);

    // 叫地主 score of a 17-card hand; higher = stronger landlord hand.
    float bid_score(const Move& hand);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace dz
