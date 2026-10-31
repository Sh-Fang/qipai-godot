// 五子棋: 15×15, black moves first, no forbidden moves, five or more in a row wins,
// a full board is a draw.
//
// The AI is a small alpha-beta search over a "five-window" evaluation: every run of
// five cells holding stones of only one colour scores by how many it holds. It is
// deliberately casual (docs/adr/0002): each 难度 limits the search depth and adds
// human-like slips (not noticing a threat, picking a merely good move).
//
// Session is one human-vs-AI game. Like the 斗地主 session it never moves the AI on
// its own: the UI calls step() so it can pause and animate.
#pragma once

#include <array>
#include <cstdint>
#include <random>
#include <vector>

#include "session.hpp"  // json, RuleError

namespace dz::gomoku {

constexpr int N = 15;
constexpr int CELLS = N * N;
enum : int { EMPTY = 0, BLACK = 1, WHITE = 2 };
inline int other(int color) { return 3 - color; }

// 难度: search depth and how sloppy the AI is allowed to be.
struct Level {
    int depth;         // plies searched (iterative deepening, stops early on TIME_MS)
    int width;         // candidate moves tried per node, best-looking first
    double margin;     // pick at random among moves within this fraction of the best
    double blunder;    // chance per move to only glance at the board (misses threats)
    double miss_four;  // chance to overlook a four the human is about to complete
};
constexpr std::array<Level, 3> LEVELS = {{
    {1, 10, 0.25, 0.35, 0.1},  // 简单
    {3, 10, 0.08, 0.10, 0.0},  // 普通
    {6, 9, 0.02, 0.0, 0.0},    // 困难
}};
constexpr int TIME_MS = 700;  // per AI move, so slow phones stay snappy

class Board {
public:
    int at(int p) const { return cells_[p]; }
    int stones() const { return stones_; }
    bool full() const { return stones_ == CELLS; }
    void place(int p, int color);
    void remove(int p);
    // Whether `color` playing the empty cell p makes five or more.
    bool makes_five(int p, int color) const;
    // The five-or-more line through the stone at p, empty if none.
    std::vector<int> five_line(int p) const;
    // Empty cells within two of a stone (the centre on an empty board).
    std::vector<int> candidates() const;
    // How much playing p changes `color`'s evaluation: its own windows grow, and the
    // opponent's windows through p die (weighted by `defense`).
    long long gain(int p, int color, double defense = 1.0) const;
    long long score(int color) const { return score_[color]; }

private:
    void windows_through(int p, int sign);
    std::array<int8_t, CELLS> cells_{};
    std::array<long long, 3> score_{};
    int stones_ = 0;
};

class Ai {
public:
    explicit Ai(std::mt19937_64& rng) : rng_(rng) {}
    // The move `color` plays at this 难度 (0..2). The board must not be over or full.
    int choose(Board& board, int color, int level);
    // The best move found by the strongest search (提示).
    int best(Board& board, int color);

private:
    struct Scored {
        int move;
        long long value;
    };
    std::vector<Scored> search_root(Board& board, int color, const Level& level, double defense);
    long long negamax(Board& board, int color, int depth, long long alpha, long long beta, int ply,
                      int width);
    std::vector<int> ordered(const Board& board, int color, int width, double defense) const;
    std::mt19937_64& rng_;
    long long deadline_ = 0;
    bool timed_out_ = false;
};

class Session {
public:
    explicit Session(uint64_t seed);
    // `human`: BLACK or WHITE; `level`: 难度 0 简单 .. 2 困难.
    void new_game(int human, int level);
    void reseed(uint64_t seed) { rng_.seed(seed); }
    json play(int x, int y);  // the human's move
    json step();              // the AI's move
    json undo();              // 悔棋: back to the human's previous turn
    std::array<int, 2> hint();  // 提示: best move for the human
    json state() const;
    // Test hooks: replay `moves` (black first) into a fresh game; let the AI play
    // whoever is to move at `level` (AI-vs-AI strength checks).
    void setup(const std::vector<std::array<int, 2>>& moves, int human, int level);
    json force_step(int level);

private:
    json apply(int p);
    bool over() const { return winner_ != 0; }

    Board board_;
    std::mt19937_64 rng_;
    Ai ai_;
    int human_ = BLACK;
    int level_ = 0;
    int to_move_ = BLACK;
    int winner_ = 0;  // 0 playing, BLACK/WHITE, 3 draw
    bool assisted_ = false;  // used 悔棋 or 提示 this game
    std::vector<int> moves_;
    std::vector<int> line_;
};

}  // namespace dz::gomoku
