#include "xiangqi.hpp"

#include <algorithm>
#include <mutex>
#include <random>
#include <vector>

// ElephantEye keeps its search state in globals (Search, PreGen, the hash table); the
// core serves one request at a time, so a single shared engine is enough.
#include "eleeye/hash.h"
#include "eleeye/search.h"

namespace dz::xiangqi {

namespace {

// 难度 knobs on ElephantEye.
struct Level {
    int depth;        // fixed search depth, 0 = search for `ms` instead
    int ms;           // time per move when depth is 0
    bool knowledge;   // positional evaluation beyond material and piece squares
    int random_mask;  // noise added to root move values, ± this much
};
constexpr std::array<Level, 3> LEVELS = {{
    {2, 0, false, 63},  // 简单
    {4, 0, true, 15},   // 普通
    {0, 800, true, 1},  // 困难
}};
constexpr int HINT_MS = 800;
constexpr int QUIET_LIMIT = 120;  // 60 回合 without a capture
constexpr int MAX_DEPTH = 32;

const char* const START_FEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w";

int square(int x, int y) { return COORD_XY(x + FILE_LEFT, y + RANK_TOP); }
int sq_x(int sq) { return FILE_X(sq) - FILE_LEFT; }
int sq_y(int sq) { return RANK_Y(sq) - RANK_TOP; }
json move_json(int mv) { return {sq_x(SRC(mv)), sq_y(SRC(mv)), sq_x(DST(mv)), sq_y(DST(mv))}; }

// "R" / "n" / "" for the piece on a square (red upper case, black lower case).
std::string piece_name(int pc) {
    if (pc == 0) return "";
    char c = PIECE_BYTE(PIECE_TYPE(pc));
    return std::string(1, pc < 32 ? c : static_cast<char>(c - 'A' + 'a'));
}

void init_engine() {
    static std::once_flag once;
    std::call_once(once, [] {
        PreGenInit();
        NewHash(22);  // 4 MB
    });
}

}  // namespace

struct Session::Impl {
    PositionStruct pos;
    std::mt19937_64 rng;
    int human = RED;
    int level = 0;
    int winner = -1;  // -1 playing, RED, BLACK, 2 draw
    std::string reason;
    bool assisted = false;
    std::vector<int> moves;            // ElephantEye move codes, in order
    std::vector<uint64_t> keys;        // position after each ply; [0] = the start
    std::vector<bool> checks;          // whether ply i (1-based like keys) gave check
    std::vector<int> captures;         // piece taken by ply i, 0 for none

    explicit Impl(uint64_t seed) : rng(seed) {}

    uint64_t key() const { return (uint64_t(pos.zobr.dwLock1) << 32) | pos.zobr.dwKey; }
    int mover() const { return pos.sdPlayer; }

    void reset(const std::string& fen) {
        pos.FromFen(fen.c_str());
        winner = -1;
        reason.clear();
        assisted = false;
        moves.clear();
        keys = {key()};
        checks = {false};
        captures = {0};
    }

    std::vector<int> legal() {
        MoveStruct mvs[MAX_GEN_MOVES];
        int n = pos.GenAllMoves(mvs);
        std::vector<int> out;
        for (int i = 0; i < n; ++i) {
            if (pos.MakeMove(mvs[i].wmv)) {
                pos.UndoMakeMove();
                out.push_back(mvs[i].wmv);
            }
        }
        return out;
    }

    json apply(int mv) {
        const int side = mover();
        const int moved = pos.ucpcSquares[SRC(mv)];
        const int taken = pos.ucpcSquares[DST(mv)];
        if (!pos.MakeMove(mv)) throw RuleError("这步棋不能走");
        moves.push_back(mv);
        keys.push_back(key());
        bool check = pos.LastMove().ChkChs > 0;
        checks.push_back(check);
        captures.push_back(taken);
        judge(side);
        return {{"type", "move"}, {"move", move_json(mv)}, {"piece", piece_name(moved)},
                {"captured", piece_name(taken)}, {"check", check}};
    }

    // After `side` moved: is the game over?
    void judge(int side) {
        if (legal().empty()) {
            winner = side;
            reason = pos.LastMove().ChkChs > 0 ? "将死" : "困毙";
            return;
        }
        // plies since the last capture (a capture makes earlier positions unreachable)
        int last = static_cast<int>(keys.size()) - 1, quiet_from = 0;
        for (int i = last; i > 0; --i)
            if (captures[i]) {
                quiet_from = i;
                break;
            }
        int seen = 0, first = -1;
        for (int i = quiet_from; i <= last; ++i)
            if (keys[i] == keys[last]) {
                if (first < 0) first = i;
                ++seen;
            }
        if (seen >= 3) {
            // who checked on every one of their moves since the first time round?
            bool perpetual[2] = {true, true};
            for (int i = first + 1; i <= last; ++i) {
                int by = (last - i) % 2 == 0 ? side : 1 - side;  // ply `last` was `side`'s
                if (!checks[i]) perpetual[by] = false;
            }
            if (perpetual[0] != perpetual[1]) {
                winner = perpetual[0] ? BLACK : RED;
                reason = "长将";
            } else {
                winner = 2;
                reason = "三次重复局面";
            }
            return;
        }
        if (last - quiet_from >= QUIET_LIMIT) {
            winner = 2;
            reason = "60 回合未吃子";
        } else if ((pos.dwBitPiece & BOTH_BITPIECE(ATTACK_BITPIECE)) == 0) {
            winner = 2;
            reason = "双方都无进攻子力";
        }
    }

    // ElephantEye's move for whoever is to move.
    int search(const Level& lv) {
        auto choices = legal();
        Search.pos = pos;  // with its history, so it steers clear of 长将 and repeats
        Search.pos.nDistance = 0;
        Search.pos.PreEvaluate();
        Search.nBanMoves = 0;
        Search.bQuit = Search.bPonder = Search.bDraw = Search.bBatch = Search.bDebug = false;
        Search.bUseHash = Search.bNullMove = true;
        Search.bUseBook = Search.bIdle = false;
        Search.bKnowledge = lv.knowledge;
        Search.nRandomMask = lv.random_mask;
        Search.nCountMask = 4095;
        uint64_t seed = rng();
        Search.rc4Random.Init(&seed, 8);
        Search.mvResult = 0;
        if (lv.depth > 0) {
            Search.nGoMode = GO_MODE_INFINITY;
            Search.nNodes = 0;
            SearchMain(lv.depth);
        } else {
            Search.nGoMode = GO_MODE_TIMER;
            Search.nProperTimer = lv.ms;
            Search.nMaxTimer = lv.ms * 2;
            SearchMain(MAX_DEPTH);
        }
        int mv = Search.mvResult;
        // nothing back (it gives up on positions it already scores as drawn): any legal move
        if (std::find(choices.begin(), choices.end(), mv) == choices.end()) {
            std::uniform_int_distribution<size_t> pick(0, choices.size() - 1);
            mv = choices[pick(rng)];
        }
        return mv;
    }
};

Session::Session(uint64_t seed) : impl_(std::make_unique<Impl>(seed)) {
    init_engine();
    impl_->reset(START_FEN);
}

Session::~Session() = default;

void Session::reseed(uint64_t seed) { impl_->rng.seed(seed); }

void Session::new_game(int human, int level) {
    if (human != RED && human != BLACK) throw RuleError("执子只能是红或黑");
    impl_->human = human;
    impl_->level = std::clamp(level, 0, 2);
    impl_->reset(START_FEN);
}

void Session::setup(const std::string& fen, const std::vector<Move>& moves, int human, int level) {
    new_game(human, level);
    impl_->reset(fen);
    for (const auto& m : moves) {
        if (impl_->winner >= 0) throw RuleError("setup: game already over");
        impl_->apply(MOVE(square(m[0], m[1]), square(m[2], m[3])));
    }
}

json Session::play(const Move& m) {
    auto& s = *impl_;
    if (s.winner >= 0) throw RuleError("对局已结束");
    if (s.mover() != s.human) throw RuleError("还没轮到你");
    for (int v : {m[0], m[2]})
        if (v < 0 || v > 8) throw RuleError("不在棋盘上");
    for (int v : {m[1], m[3]})
        if (v < 0 || v > 9) throw RuleError("不在棋盘上");
    int mv = MOVE(square(m[0], m[1]), square(m[2], m[3]));
    auto choices = s.legal();
    if (std::find(choices.begin(), choices.end(), mv) == choices.end()) throw RuleError("这步棋不能走");
    return s.apply(mv);
}

json Session::step() {
    auto& s = *impl_;
    if (s.winner >= 0) throw RuleError("对局已结束");
    if (s.mover() == s.human) throw RuleError("轮到你了");
    return s.apply(s.search(LEVELS[s.level]));
}

json Session::force_step(int level) {
    auto& s = *impl_;
    if (s.winner >= 0) throw RuleError("对局已结束");
    return s.apply(s.search(LEVELS[std::clamp(level, 0, 2)]));
}

json Session::undo() {
    auto& s = *impl_;
    if (s.winner >= 0) throw RuleError("对局已结束");
    // the human moved on plies where the side to move before it was theirs; take back
    // the last such ply and everything after it
    int start_side = (s.mover() + static_cast<int>(s.moves.size())) % 2;
    int human_ply = -1;
    for (int i = static_cast<int>(s.moves.size()) - 1; i >= 0; --i)
        if ((start_side + i) % 2 == s.human) {
            human_ply = i;
            break;
        }
    if (human_ply < 0) throw RuleError("没有可以悔的棋");
    json removed = json::array();
    while (static_cast<int>(s.moves.size()) > human_ply) {
        removed.push_back(move_json(s.moves.back()));
        s.pos.UndoMakeMove();
        s.moves.pop_back();
        s.keys.pop_back();
        s.checks.pop_back();
        s.captures.pop_back();
    }
    s.assisted = true;
    return {{"type", "undo"}, {"removed", removed}};
}

Move Session::hint() {
    auto& s = *impl_;
    if (s.winner >= 0) throw RuleError("对局已结束");
    if (s.mover() != s.human) throw RuleError("还没轮到你");
    s.assisted = true;
    int mv = s.search({0, HINT_MS, true, 0});
    return {sq_x(SRC(mv)), sq_y(SRC(mv)), sq_x(DST(mv)), sq_y(DST(mv))};
}

json Session::state() const {
    auto& s = *impl_;
    json board = json::array();
    for (int y = 0; y < 10; ++y)
        for (int x = 0; x < 9; ++x) board.push_back(piece_name(s.pos.ucpcSquares[square(x, y)]));
    json legal = json::array();
    if (s.winner < 0 && s.mover() == s.human)
        for (int mv : const_cast<Impl&>(s).legal()) legal.push_back(move_json(mv));
    const char* names[] = {"red", "black", "draw"};
    int start_side = (s.mover() + static_cast<int>(s.moves.size())) % 2;
    bool human_moved = false;
    for (size_t i = 0; i < s.moves.size(); ++i)
        if ((start_side + static_cast<int>(i)) % 2 == s.human) human_moved = true;
    return {
        {"board", board},
        {"human", names[s.human]},
        {"level", s.level},
        {"to_move", names[s.mover()]},
        {"phase", s.winner >= 0 ? "over" : "playing"},
        {"winner", s.winner >= 0 ? json(names[s.winner]) : json(nullptr)},
        {"reason", s.reason},
        {"human_won", s.winner == s.human},
        {"in_check", s.winner < 0 && s.pos.LastMove().ChkChs > 0},
        {"last", s.moves.empty() ? json(nullptr) : move_json(s.moves.back())},
        {"move_count", s.moves.size()},
        {"can_undo", s.winner < 0 && human_moved},
        {"assisted", s.assisted},
        {"legal", legal},
    };
}

}  // namespace dz::xiangqi
