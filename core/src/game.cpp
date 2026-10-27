#include "game.hpp"

#include <algorithm>
#include <map>

namespace dz {

const char* position_name(int pos) {
    static const char* names[] = {"landlord", "landlord_down", "landlord_up"};
    return names[pos];
}

void GameEnv::init(const std::array<Move, 3>& hands) {
    *this = GameEnv();
    hands_ = hands;
    for (auto& h : hands_) std::sort(h.begin(), h.end());
    legal_ = legal_actions(hands_[acting_], last_move());
}

Move GameEnv::last_move() const {
    if (history_.empty()) return {};
    if (history_.back().empty()) return history_.size() >= 2 ? history_[history_.size() - 2] : Move{};
    return history_.back();
}

bool GameEnv::must_lead() const {
    return std::find(legal_.begin(), legal_.end(), Move{}) == legal_.end();
}

void GameEnv::step(const Move& action) {
    if (is_bomb(action)) ++bomb_num_;
    last_move_of_[acting_] = action;
    history_.push_back(action);
    Move& hand = hands_[acting_];
    for (int c : action) hand.erase(std::find(hand.begin(), hand.end(), c));
    played_[acting_].insert(played_[acting_].end(), action.begin(), action.end());

    if (hand.empty()) {
        over_ = true;
        landlord_won_ = acting_ == LANDLORD;
        legal_.clear();
        return;
    }
    acting_ = (acting_ + 1) % 3;
    legal_ = legal_actions(hands_[acting_], last_move());
}

// ---- encoding ----------------------------------------------------------------

namespace {

constexpr int CARD_DIM = 54;

int column_of(int rank) { return rank == 17 ? 12 : rank - 3; }

// DouZero _cards2array: 4x13 count matrix flattened column-major + 2 jokers.
void cards_to_array(const Move& cards, float* out) {
    std::fill(out, out + CARD_DIM, 0.0f);
    std::map<int, int> counts;
    for (int c : cards) ++counts[c];
    for (auto [card, n] : counts) {
        if (card == 20) out[52] = 1;
        else if (card == 30) out[53] = 1;
        else
            for (int i = 0; i < n; ++i) out[column_of(card) * 4 + i] = 1;
    }
}

struct Row {
    std::vector<float> v;
    void cards(const Move& m) {
        size_t at = v.size();
        v.resize(at + CARD_DIM);
        cards_to_array(m, v.data() + at);
    }
    void one_hot(int index, int size) {
        size_t at = v.size();
        v.resize(at + size, 0.0f);
        // Python's one_hot[num - 1] with num == 0 would wrap to the last slot.
        v[at + ((index % size) + size) % size] = 1;
    }
};

}  // namespace

Observation encode(const GameEnv& env) {
    const int me = env.acting();
    Move others;
    for (int p = 0; p < 3; ++p)
        if (p != me) others.insert(others.end(), env.hand(p).begin(), env.hand(p).end());

    Row base;  // features shared by every candidate move
    base.cards(env.hand(me));
    base.cards(others);
    if (me == LANDLORD) {
        base.cards(env.last_move());
        base.cards(env.played(LANDLORD_UP));
        base.cards(env.played(LANDLORD_DOWN));
        base.one_hot(static_cast<int>(env.hand(LANDLORD_UP).size()) - 1, 17);
        base.one_hot(static_cast<int>(env.hand(LANDLORD_DOWN).size()) - 1, 17);
    } else {
        const int mate = me == LANDLORD_UP ? LANDLORD_DOWN : LANDLORD_UP;
        base.cards(env.played(LANDLORD));
        base.cards(env.played(mate));
        base.cards(env.last_move());
        base.cards(env.last_move_of(LANDLORD));
        base.cards(env.last_move_of(mate));
        base.one_hot(static_cast<int>(env.hand(LANDLORD).size()) - 1, 20);
        base.one_hot(static_cast<int>(env.hand(mate).size()) - 1, 17);
    }
    base.one_hot(env.bomb_num(), 15);

    Observation obs;
    obs.n = static_cast<int>(env.legal().size());
    obs.x_dim = static_cast<int>(base.v.size()) + CARD_DIM;
    obs.x.resize(static_cast<size_t>(obs.n) * obs.x_dim);
    for (int j = 0; j < obs.n; ++j) {
        float* row = obs.x.data() + static_cast<size_t>(j) * obs.x_dim;
        std::copy(base.v.begin(), base.v.end(), row);
        cards_to_array(env.legal()[j], row + base.v.size());
    }

    // z: the last 15 moves (front-padded with passes), 3 moves per row -> 5x162.
    constexpr int Z_DIM = 15 * CARD_DIM;
    std::vector<float> z(Z_DIM, 0.0f);
    const auto& hist = env.history();
    const size_t take = std::min<size_t>(hist.size(), 15);
    for (size_t i = 0; i < take; ++i)
        cards_to_array(hist[hist.size() - take + i], z.data() + (15 - take + i) * CARD_DIM);
    obs.z.resize(static_cast<size_t>(obs.n) * Z_DIM);
    for (int j = 0; j < obs.n; ++j) std::copy(z.begin(), z.end(), obs.z.begin() + static_cast<size_t>(j) * Z_DIM);
    return obs;
}

}  // namespace dz
