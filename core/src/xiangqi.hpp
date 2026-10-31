// 象棋: standard rules on the 9×10 board, red moves first. A game is lost by having
// no legal move (将死 or 困毙). The rest is our simplified rule set (GLOSSARY.md):
// the same position a third time is a draw, unless one side gave check on every move
// of the cycle, who then loses (长将); 60 回合 (120 plies) without a capture, or no
// attacking pieces left on either side, is a draw.
//
// Move generation, legality and the AI come from ElephantEye (third_party/eleeye,
// LGPL-2.1). It is deliberately casual (docs/adr/0002): each 难度 limits the search
// and its positional knowledge and adds noise to its move choice.
//
// Squares are (x, y): x = file 0..8 from red's left, y = rank 0..9 from black's back
// rank (the top of the board) to red's.
#pragma once

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "session.hpp"  // json, RuleError

namespace dz::xiangqi {

enum : int { RED = 0, BLACK = 1 };

using Move = std::array<int, 4>;  // from x, from y, to x, to y

class Session {
public:
    explicit Session(uint64_t seed);
    ~Session();
    // `human`: RED or BLACK; `level`: 难度 0 简单 .. 2 困难.
    void new_game(int human, int level);
    void reseed(uint64_t seed);
    json play(const Move& m);  // the human's move
    json step();               // the AI's move
    json undo();               // 悔棋: back to the human's previous turn
    Move hint();               // 提示: best move for the human
    json state() const;
    // Test hooks: start from a FEN position and replay `moves` for both sides; let the
    // AI play whoever is to move at `level` (AI-vs-AI strength checks).
    void setup(const std::string& fen, const std::vector<Move>& moves, int human, int level);
    json force_step(int level);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace dz::xiangqi
