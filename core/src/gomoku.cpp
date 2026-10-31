#include "gomoku.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace dz::gomoku {

namespace {

constexpr std::array<std::array<int, 2>, 4> DIRS = {{{1, 0}, {0, 1}, {1, 1}, {1, -1}}};
// Value of a five-window holding k stones of one colour and none of the other.
constexpr std::array<long long, 6> WINDOW = {0, 1, 12, 150, 1800, 0};
constexpr long long WIN = 1'000'000'000;

bool inside(int x, int y) { return x >= 0 && x < N && y >= 0 && y < N; }

long long now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

}  // namespace

// ---- Board ---------------------------------------------------------------------

// Add (sign +1) or take away (-1) the score of every five-window through p.
void Board::windows_through(int p, int sign) {
    const int px = p % N, py = p / N;
    for (auto [dx, dy] : DIRS) {
        for (int s = -4; s <= 0; ++s) {
            int x0 = px + s * dx, y0 = py + s * dy;
            if (!inside(x0, y0) || !inside(x0 + 4 * dx, y0 + 4 * dy)) continue;
            int count[3] = {0, 0, 0};
            for (int i = 0; i < 5; ++i) count[cells_[(y0 + i * dy) * N + x0 + i * dx]]++;
            if (count[BLACK] && !count[WHITE]) score_[BLACK] += sign * WINDOW[count[BLACK]];
            if (count[WHITE] && !count[BLACK]) score_[WHITE] += sign * WINDOW[count[WHITE]];
        }
    }
}

void Board::place(int p, int color) {
    windows_through(p, -1);
    cells_[p] = static_cast<int8_t>(color);
    windows_through(p, +1);
    ++stones_;
}

void Board::remove(int p) {
    windows_through(p, -1);
    cells_[p] = EMPTY;
    windows_through(p, +1);
    --stones_;
}

bool Board::makes_five(int p, int color) const {
    const int px = p % N, py = p / N;
    for (auto [dx, dy] : DIRS) {
        int run = 1;
        for (int sign : {1, -1}) {
            int x = px + sign * dx, y = py + sign * dy;
            while (inside(x, y) && cells_[y * N + x] == color) {
                ++run;
                x += sign * dx;
                y += sign * dy;
            }
        }
        if (run >= 5) return true;
    }
    return false;
}

std::vector<int> Board::five_line(int p) const {
    const int color = cells_[p], px = p % N, py = p / N;
    for (auto [dx, dy] : DIRS) {
        std::vector<int> line = {p};
        for (int sign : {1, -1}) {
            int x = px + sign * dx, y = py + sign * dy;
            while (inside(x, y) && cells_[y * N + x] == color) {
                line.push_back(y * N + x);
                x += sign * dx;
                y += sign * dy;
            }
        }
        if (line.size() >= 5) {
            std::sort(line.begin(), line.end());
            return line;
        }
    }
    return {};
}

std::vector<int> Board::candidates() const {
    if (stones_ == 0) return {(N / 2) * N + N / 2};
    std::vector<int> out;
    for (int p = 0; p < CELLS; ++p) {
        if (cells_[p] != EMPTY) continue;
        const int px = p % N, py = p / N;
        bool near = false;
        for (int y = std::max(0, py - 2); y <= std::min(N - 1, py + 2) && !near; ++y)
            for (int x = std::max(0, px - 2); x <= std::min(N - 1, px + 2); ++x)
                if (cells_[y * N + x] != EMPTY) {
                    near = true;
                    break;
                }
        if (near) out.push_back(p);
    }
    return out;
}

long long Board::gain(int p, int color, double defense) const {
    const int px = p % N, py = p / N, opp = other(color);
    long long attack = 0, block = 0;
    for (auto [dx, dy] : DIRS) {
        for (int s = -4; s <= 0; ++s) {
            int x0 = px + s * dx, y0 = py + s * dy;
            if (!inside(x0, y0) || !inside(x0 + 4 * dx, y0 + 4 * dy)) continue;
            int count[3] = {0, 0, 0};
            for (int i = 0; i < 5; ++i) count[cells_[(y0 + i * dy) * N + x0 + i * dx]]++;
            if (!count[opp]) attack += WINDOW[std::min(count[color] + 1, 4)] - WINDOW[count[color]];
            if (!count[color]) block += WINDOW[count[opp]];
        }
    }
    return attack + static_cast<long long>(std::llround(block * defense));
}

// ---- Ai ------------------------------------------------------------------------

std::vector<int> Ai::ordered(const Board& board, int color, int width, double defense) const {
    std::vector<std::pair<long long, int>> scored;
    for (int p : board.candidates()) scored.push_back({board.gain(p, color, defense), p});
    std::sort(scored.begin(), scored.end(), [](auto& a, auto& b) { return a.first > b.first; });
    std::vector<int> out;
    for (size_t i = 0; i < scored.size() && static_cast<int>(i) < width; ++i) out.push_back(scored[i].second);
    return out;
}

// Value of the position for `color`, who is to move.
long long Ai::negamax(Board& board, int color, int depth, long long alpha, long long beta, int ply,
                      int width) {
    const int opp = other(color);
    if (depth == 0) return board.score(color) - board.score(opp);
    if (board.full()) return 0;
    if ((ply & 7) == 0 && now_ms() > deadline_) timed_out_ = true;
    if (timed_out_) return 0;
    auto cands = board.candidates();
    std::vector<int> threats;  // where the opponent would make five
    for (int p : cands) {
        if (board.makes_five(p, color)) return WIN - ply;
        if (board.makes_five(p, opp)) threats.push_back(p);
    }
    if (threats.size() >= 2) return -(WIN - ply - 1);  // can't block both
    auto moves = threats.empty() ? ordered(board, color, width, 1.0) : threats;
    long long best = -WIN * 2;
    for (int p : moves) {
        board.place(p, color);
        long long v = -negamax(board, opp, depth - 1, -beta, -alpha, ply + 1, width);
        board.remove(p);
        if (timed_out_) return 0;
        best = std::max(best, v);
        alpha = std::max(alpha, v);
        if (alpha >= beta) break;
    }
    return best;
}

// Every root move tried, with its search value, best first. Deepens one ply at a time
// until the level's depth or the time runs out, keeping the last finished depth.
std::vector<Ai::Scored> Ai::search_root(Board& board, int color, const Level& level, double defense) {
    auto moves = ordered(board, color, level.width, defense);
    std::vector<Scored> done;
    deadline_ = now_ms() + TIME_MS;
    timed_out_ = false;
    for (int depth = 1; depth <= level.depth; ++depth) {
        std::vector<Scored> scored;
        for (int p : moves) {
            board.place(p, color);
            long long v = board.makes_five(p, color) ? WIN
                                                     : -negamax(board, other(color), depth - 1, -WIN * 2,
                                                                WIN * 2, 1, level.width);
            board.remove(p);
            if (timed_out_) break;
            scored.push_back({p, v});
        }
        if (timed_out_) break;
        std::stable_sort(scored.begin(), scored.end(), [](auto& a, auto& b) { return a.value > b.value; });
        done = scored;
        if (done.front().value >= WIN - 64 || done.front().value <= -(WIN - 64)) break;  // decided
        moves.clear();
        for (auto& s : done) moves.push_back(s.move);  // search the best ones first next time
    }
    return done;
}

int Ai::choose(Board& board, int color, int level_index) {
    const Level& level = LEVELS[std::clamp(level_index, 0, 2)];
    std::uniform_real_distribution<double> chance(0.0, 1.0);
    const int opp = other(color);
    auto cands = board.candidates();
    std::vector<int> threats;
    for (int p : cands) {
        if (board.makes_five(p, color)) return p;
        if (board.makes_five(p, opp)) threats.push_back(p);
    }
    if (!threats.empty() && chance(rng_) >= level.miss_four) return threats.front();

    // a slip: only glance at the board, half-ignoring what the human is building
    bool careless = chance(rng_) < level.blunder;
    Level used = level;
    if (careless) used.depth = 1;
    auto scored = search_root(board, color, used, careless ? 0.3 : 1.0);
    if (scored.empty()) return cands.front();

    long long top = scored.front().value;
    if (top >= WIN - 64) return scored.front().move;  // a forced win: no reason to slip
    long long slack = static_cast<long long>(std::llabs(top) * used.margin) + (used.margin > 0 ? 6 : 0);
    std::vector<int> close;
    for (auto& s : scored)
        if (s.value >= top - slack) close.push_back(s.move);
    std::uniform_int_distribution<size_t> pick(0, close.size() - 1);
    return close[pick(rng_)];
}

int Ai::best(Board& board, int color) {
    const int opp = other(color);
    auto cands = board.candidates();
    for (int p : cands)
        if (board.makes_five(p, color)) return p;
    for (int p : cands)
        if (board.makes_five(p, opp)) return p;
    auto scored = search_root(board, color, LEVELS[2], 1.0);
    return scored.empty() ? cands.front() : scored.front().move;
}

// ---- Session -------------------------------------------------------------------

Session::Session(uint64_t seed) : rng_(seed), ai_(rng_) {}

void Session::new_game(int human, int level) {
    if (human != BLACK && human != WHITE) throw RuleError("执子只能是黑或白");
    board_ = Board{};
    human_ = human;
    level_ = std::clamp(level, 0, 2);
    to_move_ = BLACK;
    winner_ = 0;
    assisted_ = false;
    moves_.clear();
    line_.clear();
}

void Session::setup(const std::vector<std::array<int, 2>>& moves, int human, int level) {
    new_game(human, level);
    for (auto [x, y] : moves) {
        if (!inside(x, y) || board_.at(y * N + x) != EMPTY) throw RuleError("bad setup move");
        apply(y * N + x);
    }
}

json Session::apply(int p) {
    const int color = to_move_;
    board_.place(p, color);
    moves_.push_back(p);
    line_ = board_.five_line(p);
    if (!line_.empty()) {
        winner_ = color;
    } else if (board_.full()) {
        winner_ = 3;
    }
    to_move_ = other(color);
    return {{"type", "move"}, {"color", color}, {"x", p % N}, {"y", p / N}};
}

json Session::play(int x, int y) {
    if (over()) throw RuleError("对局已结束");
    if (to_move_ != human_) throw RuleError("还没轮到你");
    if (!inside(x, y)) throw RuleError("不在棋盘上");
    if (board_.at(y * N + x) != EMPTY) throw RuleError("这里已经有子了");
    return apply(y * N + x);
}

json Session::step() {
    if (over()) throw RuleError("对局已结束");
    if (to_move_ == human_) throw RuleError("轮到你了");
    return apply(ai_.choose(board_, to_move_, level_));
}

json Session::undo() {
    if (over()) throw RuleError("对局已结束");
    // take back the human's last move and the AI's reply after it, if any
    int human_index = -1;
    for (int i = static_cast<int>(moves_.size()) - 1; i >= 0; --i) {
        if ((i % 2 == 0 ? BLACK : WHITE) == human_) {
            human_index = i;
            break;
        }
    }
    if (human_index < 0) throw RuleError("没有可以悔的棋");
    json removed = json::array();
    while (static_cast<int>(moves_.size()) > human_index) {
        int p = moves_.back();
        moves_.pop_back();
        board_.remove(p);
        removed.push_back({p % N, p / N});
    }
    to_move_ = human_;
    assisted_ = true;
    return {{"type", "undo"}, {"removed", removed}};
}

json Session::force_step(int level) {
    if (over()) throw RuleError("对局已结束");
    return apply(ai_.choose(board_, to_move_, level));
}

std::array<int, 2> Session::hint() {
    if (over()) throw RuleError("对局已结束");
    if (to_move_ != human_) throw RuleError("还没轮到你");
    assisted_ = true;
    int p = ai_.best(board_, human_);
    return {p % N, p / N};
}

json Session::state() const {
    std::vector<int> board(CELLS);
    for (int p = 0; p < CELLS; ++p) board[p] = board_.at(p);
    json line = json::array();
    for (int p : line_) line.push_back({p % N, p / N});
    bool human_moved = false;
    for (size_t i = 0; i < moves_.size(); ++i)
        if ((i % 2 == 0 ? BLACK : WHITE) == human_) human_moved = true;
    return {
        {"board", board},
        {"human", human_},
        {"level", level_},
        {"to_move", to_move_},
        {"phase", over() ? "over" : "playing"},
        {"winner", winner_},
        {"human_won", winner_ == human_},
        {"line", line},
        {"last", moves_.empty() ? json(nullptr) : json{moves_.back() % N, moves_.back() / N}},
        {"move_count", moves_.size()},
        {"can_undo", !over() && human_moved},
        {"assisted", assisted_},
    };
}

}  // namespace dz::gomoku
