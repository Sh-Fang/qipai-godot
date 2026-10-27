// Card-play phase of one game, ported from DouZero's GameEnv, plus the
// observation encoding the WP models expect (DouZero env.get_obs).
#pragma once

#include <array>
#include <vector>

#include "rules.hpp"

namespace dz {

// DouZero positions, indexed in play order.
enum Position { LANDLORD = 0, LANDLORD_DOWN = 1, LANDLORD_UP = 2 };
const char* position_name(int pos);

class GameEnv {
public:
    // hands[pos] for each position; the landlord's already holds the bottom cards.
    void init(const std::array<Move, 3>& hands);

    // Apply a legal move for the acting position.
    void step(const Move& action);

    int acting() const { return acting_; }
    bool over() const { return over_; }
    bool landlord_won() const { return landlord_won_; }
    int bomb_num() const { return bomb_num_; }
    const std::vector<Move>& legal() const { return legal_; }
    bool must_lead() const;  // the acting player may not pass

    const Move& hand(int pos) const { return hands_[pos]; }
    // The move to beat: last non-pass of the last two moves, or [] for a free lead.
    Move last_move() const;
    const Move& last_move_of(int pos) const { return last_move_of_[pos]; }
    const Move& played(int pos) const { return played_[pos]; }
    const std::vector<Move>& history() const { return history_; }

private:
    std::array<Move, 3> hands_;
    std::array<Move, 3> last_move_of_;
    std::array<Move, 3> played_;
    std::vector<Move> history_;
    std::vector<Move> legal_;
    int acting_ = LANDLORD;
    int bomb_num_ = 0;
    bool over_ = false;
    bool landlord_won_ = false;
};

// Model inputs for scoring every legal move of the acting position:
// x is [n, x_dim] (373 for the landlord, 484 for farmers), z is [n, 5, 162].
struct Observation {
    int n = 0;
    int x_dim = 0;
    std::vector<float> x;
    std::vector<float> z;
};
Observation encode(const GameEnv& env);

}  // namespace dz
