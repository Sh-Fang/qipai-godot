#include "rules.hpp"

#include <algorithm>
#include <map>
#include <set>

namespace dz {

namespace {

constexpr int MIN_SINGLE_CARDS = 5;
constexpr int MIN_PAIRS = 3;
constexpr int MIN_TRIPLES = 2;

bool is_continuous_seq(const std::vector<int>& v) {
    for (size_t i = 0; i + 1 < v.size(); ++i)
        if (v[i + 1] - v[i] != 1) return false;
    return true;
}

std::map<int, int> count_cards(const Move& cards) {
    std::map<int, int> counts;
    for (int c : cards) ++counts[c];
    return counts;
}

// All size-k combinations of `items`, in lexicographic index order
// (same as Python's itertools.combinations).
std::vector<std::vector<int>> combinations(const std::vector<int>& items, size_t k) {
    std::vector<std::vector<int>> out;
    if (k > items.size()) return out;
    std::vector<size_t> idx(k);
    for (size_t i = 0; i < k; ++i) idx[i] = i;
    while (true) {
        std::vector<int> combo;
        for (size_t i : idx) combo.push_back(items[i]);
        out.push_back(std::move(combo));
        size_t i = k;
        while (i > 0 && idx[i - 1] == items.size() - k + i - 1) --i;
        if (i == 0) break;
        ++idx[i - 1];
        for (size_t j = i; j < k; ++j) idx[j] = idx[j - 1] + 1;
    }
    return out;
}

void dedupe(std::vector<Move>& moves) {
    std::set<Move> seen;
    std::vector<Move> out;
    for (auto& m : moves)
        if (seen.insert(m).second) out.push_back(std::move(m));
    moves = std::move(out);
}

Move sorted(Move m) {
    std::sort(m.begin(), m.end());
    return m;
}

// Port of DouZero's MovesGener.
class MovesGener {
public:
    explicit MovesGener(const Move& cards) : cards_(cards), counts_(count_cards(cards)) {}

    std::vector<Move> single() const {
        std::vector<Move> out;
        for (auto [k, v] : counts_) out.push_back({k});
        return out;
    }
    std::vector<Move> of_count(int n, bool exact) const {
        std::vector<Move> out;
        for (auto [k, v] : counts_)
            if (exact ? v == n : v >= n) out.push_back(Move(n, k));
        return out;
    }
    std::vector<Move> pair() const { return of_count(2, false); }
    std::vector<Move> triple() const { return of_count(3, false); }
    std::vector<Move> bomb() const { return of_count(4, true); }
    std::vector<Move> king_bomb() const {
        if (counts_.count(20) && counts_.count(30)) return {{20, 30}};
        return {};
    }

    std::vector<Move> type_6_3_1() const {
        std::vector<Move> out;
        for (auto& t : single())
            for (auto& i : triple())
                if (t[0] != i[0]) out.push_back({t[0], i[0], i[0], i[0]});
        return out;
    }
    std::vector<Move> type_7_3_2() const {
        std::vector<Move> out;
        for (auto& t : pair())
            for (auto& i : triple())
                if (t[0] != i[0]) out.push_back({t[0], t[0], i[0], i[0], i[0]});
        return out;
    }

    std::vector<Move> serial_single(int repeat_num = 0) const {
        return serial_moves(cards_, MIN_SINGLE_CARDS, 1, repeat_num);
    }
    std::vector<Move> serial_pair(int repeat_num = 0) const {
        return serial_moves(ranks_with_at_least(2), MIN_PAIRS, 2, repeat_num);
    }
    std::vector<Move> serial_triple(int repeat_num = 0) const {
        return serial_moves(ranks_with_at_least(3), MIN_TRIPLES, 3, repeat_num);
    }

    std::vector<Move> serial_3_1(int repeat_num = 0) const {
        std::vector<Move> out;
        for (auto& s3 : serial_triple(repeat_num)) {
            std::set<int> s3_set(s3.begin(), s3.end());
            std::vector<int> rest;
            for (int c : cards_)
                if (!s3_set.count(c)) rest.push_back(c);
            for (auto& kick : combinations(rest, s3_set.size())) {
                Move m = s3;
                m.insert(m.end(), kick.begin(), kick.end());
                out.push_back(sorted(m));
            }
        }
        dedupe(out);
        return out;
    }

    std::vector<Move> serial_3_2(int repeat_num = 0) const {
        std::vector<Move> out;
        for (auto& s3 : serial_triple(repeat_num)) {
            std::set<int> s3_set(s3.begin(), s3.end());
            std::vector<int> candidates;
            for (int k : ranks_with_at_least(2))
                if (!s3_set.count(k)) candidates.push_back(k);
            for (auto& kick : combinations(candidates, s3_set.size())) {
                Move m = s3;
                for (int k : kick) m.insert(m.end(), {k, k});
                out.push_back(sorted(m));
            }
        }
        return out;
    }

    std::vector<Move> type_13_4_2() const {
        std::vector<Move> out;
        for (auto& b : bomb()) {
            int fc = b[0];
            std::vector<int> rest;
            for (int c : cards_)
                if (c != fc) rest.push_back(c);
            for (auto& kick : combinations(rest, 2))
                out.push_back(sorted({fc, fc, fc, fc, kick[0], kick[1]}));
        }
        dedupe(out);
        return out;
    }

    std::vector<Move> type_14_4_22() const {
        std::vector<Move> out;
        for (auto& b : bomb()) {
            int fc = b[0];
            std::vector<int> rest;
            for (int k : ranks_with_at_least(2))
                if (k != fc) rest.push_back(k);
            for (auto& kick : combinations(rest, 2))
                out.push_back(sorted({fc, fc, fc, fc, kick[0], kick[0], kick[1], kick[1]}));
        }
        return out;
    }

    std::vector<Move> all() const {
        std::vector<Move> moves;
        for (auto&& part : {single(), pair(), triple(), bomb(), king_bomb(), type_6_3_1(),
                            type_7_3_2(), serial_single(), serial_pair(), serial_triple(),
                            serial_3_1(), serial_3_2(), type_13_4_2(), type_14_4_22()})
            moves.insert(moves.end(), part.begin(), part.end());
        return moves;
    }

private:
    std::vector<int> ranks_with_at_least(int n) const {
        std::vector<int> out;
        for (auto [k, v] : counts_)
            if (v >= n) out.push_back(k);
        return out;
    }

    // Port of MovesGener._gen_serial_moves.
    static std::vector<Move> serial_moves(const std::vector<int>& cards, int min_serial,
                                          int repeat, int repeat_num) {
        if (repeat_num < min_serial) repeat_num = 0;
        std::set<int> uniq(cards.begin(), cards.end());
        std::vector<int> singles(uniq.begin(), uniq.end());
        std::vector<Move> moves;

        size_t start = 0;
        for (size_t i = 0; i < singles.size(); ++i) {
            if (i + 1 < singles.size() && singles[i + 1] - singles[i] == 1) continue;
            int longest = static_cast<int>(i + 1 - start);
            auto emit = [&](int from, int steps) {
                Move m;
                for (int r = 0; r < repeat; ++r)
                    m.insert(m.end(), singles.begin() + start + from,
                             singles.begin() + start + from + steps);
                moves.push_back(sorted(m));
            };
            if (longest >= min_serial) {
                if (repeat_num == 0) {
                    for (int steps = min_serial; steps <= longest; ++steps)
                        for (int index = 0; steps + index <= longest; ++index) emit(index, steps);
                } else if (longest >= repeat_num) {
                    for (int index = 0; index + repeat_num <= longest; ++index)
                        emit(index, repeat_num);
                }
            }
            start = i + 1;
        }
        return moves;
    }

    Move cards_;
    std::map<int, int> counts_;
};

// Rank of the highest triple (serial 3+1 / 3+2) or the four (4+2+2).
int top_rank_with_count(const Move& move, int n) {
    int rank = 0;
    for (auto [k, v] : count_cards(move))
        if (v == n) rank = k;
    return rank;
}

// Port of move_selector.filter_*: keep moves whose key card beats the rival's.
std::vector<Move> filter_beats(const std::vector<Move>& moves, const Move& rival, int type) {
    auto key = [type](const Move& m) {
        switch (type) {
            case TYPE_6_3_1: return m[1];
            case TYPE_7_3_2:
            case TYPE_13_4_2: return m[2];
            case TYPE_11_SERIAL_3_1:
            case TYPE_12_SERIAL_3_2: return top_rank_with_count(m, 3);
            case TYPE_14_4_22: return top_rank_with_count(m, 4);
            default: return m[0];
        }
    };
    std::vector<Move> out;
    int rival_key = key(rival);
    for (auto& m : moves)
        if (key(m) > rival_key) out.push_back(m);
    return out;
}

}  // namespace

MoveInfo move_type(const Move& move) {
    const size_t size = move.size();
    if (size == 0) return {TYPE_0_PASS};
    if (size == 1) return {TYPE_1_SINGLE, move[0]};

    auto counts = count_cards(move);
    const size_t distinct = counts.size();

    if (size == 2) {
        if (move[0] == move[1]) return {TYPE_2_PAIR, move[0]};
        if (move[0] == 20 && move[1] == 30) return {TYPE_5_KING_BOMB};
        return {};
    }
    if (size == 3) return distinct == 1 ? MoveInfo{TYPE_3_TRIPLE, move[0]} : MoveInfo{};
    if (size == 4) {
        if (distinct == 1) return {TYPE_4_BOMB, move[0]};
        if (distinct == 2 && ((move[0] == move[1] && move[1] == move[2]) ||
                              (move[1] == move[2] && move[2] == move[3])))
            return {TYPE_6_3_1, move[1]};
        return {};
    }
    if (is_continuous_seq(move))
        return {TYPE_8_SERIAL_SINGLE, move[0], static_cast<int>(size)};
    if (size == 5) return distinct == 2 ? MoveInfo{TYPE_7_3_2, move[2]} : MoveInfo{};

    std::map<int, size_t> count_of;  // n -> how many ranks appear n times
    for (auto [k, v] : counts) ++count_of[v];
    auto cnt = [&](int n) { return count_of.count(n) ? count_of[n] : 0; };

    if (size == 6 && (distinct == 2 || distinct == 3) && cnt(4) == 1 &&
        (cnt(2) == 1 || cnt(1) == 2))
        return {TYPE_13_4_2, move[2]};

    if (size == 8 && (((distinct == 3 || distinct == 2) && cnt(4) == 1 && cnt(2) == 2) ||
                      cnt(4) == 2))
        return {TYPE_14_4_22, top_rank_with_count(move, 4)};

    std::vector<int> keys;
    for (auto [k, v] : counts) keys.push_back(k);
    if (distinct == cnt(2) && is_continuous_seq(keys))
        return {TYPE_9_SERIAL_PAIR, keys[0], static_cast<int>(keys.size())};
    if (distinct == cnt(3) && is_continuous_seq(keys))
        return {TYPE_10_SERIAL_TRIPLE, keys[0], static_cast<int>(keys.size())};

    if (cnt(3) >= MIN_TRIPLES) {
        std::vector<int> serial_3;
        size_t singles = 0, pairs = 0;
        for (auto [k, v] : counts) {
            if (v == 3) serial_3.push_back(k);
            else if (v == 1) ++singles;
            else if (v == 2) ++pairs;
            else return {};
        }
        const int n3 = static_cast<int>(serial_3.size());
        if (is_continuous_seq(serial_3)) {
            if (serial_3.size() == singles + pairs * 2) return {TYPE_11_SERIAL_3_1, serial_3[0], n3};
            if (serial_3.size() == pairs && distinct == serial_3.size() * 2)
                return {TYPE_12_SERIAL_3_2, serial_3[0], n3};
        }
        if (n3 == 4) {
            if (is_continuous_seq({serial_3.begin() + 1, serial_3.end()}))
                return {TYPE_11_SERIAL_3_1, serial_3[1], n3 - 1};
            if (is_continuous_seq({serial_3.begin(), serial_3.end() - 1}))
                return {TYPE_11_SERIAL_3_1, serial_3[0], n3 - 1};
        }
    }
    return {};
}

const char* move_type_name(int type) {
    static const char* names[] = {"",       "单张",   "对子",   "三张",   "炸弹",
                                  "王炸",   "三带一", "三带二", "顺子",   "连对",
                                  "飞机",   "飞机带单", "飞机带对", "四带二", "四带两对", ""};
    return (type >= 0 && type <= TYPE_15_WRONG) ? names[type] : "";
}

bool is_bomb(const Move& move) {
    if (move.size() == 2) return move[0] == 20 && move[1] == 30;
    return move.size() == 4 && move[0] == move[3];
}

std::vector<Move> legal_actions(const Move& hand, const Move& rival) {
    MovesGener mg(hand);
    const MoveInfo rt = move_type(rival);
    std::vector<Move> moves;
    switch (rt.type) {
        case TYPE_0_PASS: moves = mg.all(); break;
        case TYPE_1_SINGLE: moves = filter_beats(mg.single(), rival, rt.type); break;
        case TYPE_2_PAIR: moves = filter_beats(mg.pair(), rival, rt.type); break;
        case TYPE_3_TRIPLE: moves = filter_beats(mg.triple(), rival, rt.type); break;
        case TYPE_4_BOMB: {
            auto all = mg.bomb();
            for (auto& k : mg.king_bomb()) all.push_back(k);
            moves = filter_beats(all, rival, rt.type);
            break;
        }
        case TYPE_5_KING_BOMB: break;
        case TYPE_6_3_1: moves = filter_beats(mg.type_6_3_1(), rival, rt.type); break;
        case TYPE_7_3_2: moves = filter_beats(mg.type_7_3_2(), rival, rt.type); break;
        case TYPE_8_SERIAL_SINGLE: moves = filter_beats(mg.serial_single(rt.len), rival, rt.type); break;
        case TYPE_9_SERIAL_PAIR: moves = filter_beats(mg.serial_pair(rt.len), rival, rt.type); break;
        case TYPE_10_SERIAL_TRIPLE: moves = filter_beats(mg.serial_triple(rt.len), rival, rt.type); break;
        case TYPE_11_SERIAL_3_1: moves = filter_beats(mg.serial_3_1(rt.len), rival, rt.type); break;
        case TYPE_12_SERIAL_3_2: moves = filter_beats(mg.serial_3_2(rt.len), rival, rt.type); break;
        case TYPE_13_4_2: moves = filter_beats(mg.type_13_4_2(), rival, rt.type); break;
        case TYPE_14_4_22: moves = filter_beats(mg.type_14_4_22(), rival, rt.type); break;
        default: break;
    }
    if (rt.type != TYPE_0_PASS && rt.type != TYPE_4_BOMB && rt.type != TYPE_5_KING_BOMB) {
        for (auto& b : mg.bomb()) moves.push_back(b);
        for (auto& k : mg.king_bomb()) moves.push_back(k);
    }
    if (!rival.empty()) moves.push_back({});
    for (auto& m : moves) std::sort(m.begin(), m.end());
    return moves;
}

}  // namespace dz
