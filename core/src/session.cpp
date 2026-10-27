#include "session.hpp"

#include <algorithm>
#include <map>
#include <numeric>

namespace dz {

// ---- cards -------------------------------------------------------------------

int card_rank(int id) {
    static const int ranks[] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17};
    if (id == 52) return 20;
    if (id == 53) return 30;
    if (id < 0 || id > 53) throw RuleError("没有这张牌");
    return ranks[id / 4];
}

static int card_suit(int id) { return id < 52 ? id % 4 : -1; }

Move ranks_of(const CardIds& ids) {
    Move m;
    for (int id : ids) m.push_back(card_rank(id));
    std::sort(m.begin(), m.end());
    return m;
}

CardIds sort_ids(CardIds ids) {
    std::sort(ids.begin(), ids.end(), [](int a, int b) {
        return std::pair(card_rank(a), card_suit(a)) < std::pair(card_rank(b), card_suit(b));
    });
    return ids;
}

CardIds take_ids(const CardIds& hand, const Move& ranks) {
    CardIds pool = sort_ids(hand), picked;
    for (int r : ranks) {
        auto it = std::find_if(pool.begin(), pool.end(), [r](int c) { return card_rank(c) == r; });
        if (it == pool.end()) throw std::runtime_error("rank not in hand");
        picked.push_back(*it);
        pool.erase(it);
    }
    return sort_ids(picked);
}

// ---- session -----------------------------------------------------------------

Session::Session(Policy& policy, uint64_t seed) : policy_(policy), rng_(seed) { new_game(); }

void Session::new_game() {
    phase_ = "bidding";
    landlord_seat_ = -1;
    bid_start_ = static_cast<int>(rng_() % 3);
    display_ = {};
    env_ = GameEnv();
    deal();
    start_bidding();
}

void Session::start_bidding() {
    bids_ = {};
    bid_queue_ = {bid_start_, (bid_start_ + 1) % 3, (bid_start_ + 2) % 3};
    caller_ = candidate_ = -1;
    rob_count_ = 0;
    caller_last_chance_ = false;
    current_seat_ = bid_queue_.front();
}

void Session::deal() {
    CardIds deck(54);
    std::iota(deck.begin(), deck.end(), 0);
    std::shuffle(deck.begin(), deck.end(), rng_);
    for (int i = 0; i < 3; ++i) hands_[i] = sort_ids({deck.begin() + i * 17, deck.begin() + (i + 1) * 17});
    bottom_ = sort_ids({deck.begin() + 51, deck.end()});
}

json Session::bid(int seat, bool want) {
    bid_queue_.erase(bid_queue_.begin());
    std::string action;
    if (caller_ < 0) {
        action = want ? "call" : "pass";
        if (want) caller_ = candidate_ = seat;
    } else {
        action = want ? "rob" : "no_rob";
        if (want) {
            candidate_ = seat;
            ++rob_count_;
        }
    }
    bids_[seat] = action;
    json event = {{"seat", seat}, {"type", "bid"}, {"action", action}};
    if (bid_queue_.empty()) {
        if (caller_ < 0) {
            // nobody wants it: redeal and bid again from the same seat
            deal();
            start_bidding();
            event["redeal"] = true;
            return event;
        }
        if (rob_count_ > 0 && !caller_last_chance_) {
            caller_last_chance_ = true;
            bid_queue_.push_back(caller_);
        }
    }
    if (!bid_queue_.empty()) current_seat_ = bid_queue_.front();
    else start_play(candidate_);
    return event;
}

void Session::start_play(int landlord_seat) {
    landlord_seat_ = landlord_seat;
    hands_[landlord_seat].insert(hands_[landlord_seat].end(), bottom_.begin(), bottom_.end());
    hands_[landlord_seat] = sort_ids(hands_[landlord_seat]);
    std::array<Move, 3> by_position;
    for (int pos = 0; pos < 3; ++pos) by_position[pos] = ranks_of(hands_[seat_of(pos)]);
    env_.init(by_position);
    phase_ = "playing";
    current_seat_ = landlord_seat;
}

json Session::apply(int seat, const Move& ranks) {
    if (env_.must_lead()) display_ = {};
    CardIds ids = ranks.empty() ? CardIds{} : take_ids(hands_[seat], ranks);
    env_.step(ranks);
    for (int c : ids) hands_[seat].erase(std::find(hands_[seat].begin(), hands_[seat].end(), c));
    display_[seat] = {{"cards", ids}, {"pass", ids.empty()}};
    json event = {{"seat", seat},
                  {"type", ids.empty() ? "pass" : "play"},
                  {"cards", ids},
                  {"move_type", ids.empty() ? "" : move_type_name(move_type(ranks).type)}};
    if (env_.over()) {
        phase_ = "over";
        current_seat_ = -1;
    } else {
        current_seat_ = seat_of(env_.acting());
    }
    return event;
}

json Session::step() {
    if (phase_ == "over") throw RuleError("本局已结束");
    if (current_seat_ == HUMAN) throw RuleError("现在轮到你");
    if (phase_ == "bidding")
        return bid(current_seat_, bid_score(current_seat_) > (caller_ < 0 ? CALL_THRESHOLD : ROB_THRESHOLD));
    return apply(current_seat_, policy_.act(env_));
}

json Session::human_bid(bool call) {
    if (phase_ != "bidding" || current_seat_ != HUMAN) throw RuleError("现在不能叫地主");
    return bid(HUMAN, call);
}

json Session::human_play(const CardIds& ids) {
    if (phase_ != "playing" || current_seat_ != HUMAN) throw RuleError("还没轮到你出牌");
    if (ids.empty()) throw RuleError("请先选牌");
    const auto& hand = hands_[HUMAN];
    for (int c : ids)
        if (std::find(hand.begin(), hand.end(), c) == hand.end()) throw RuleError("选中的牌不在手里");
    Move ranks = ranks_of(ids);
    const auto& legal = env_.legal();
    if (std::find(legal.begin(), legal.end(), ranks) == legal.end()) {
        if (move_type(ranks).type == TYPE_15_WRONG) throw RuleError("不是合法牌型");
        throw RuleError("管不上");
    }
    return apply(HUMAN, ranks);
}

json Session::human_pass() {
    if (phase_ != "playing" || current_seat_ != HUMAN) throw RuleError("还没轮到你");
    if (env_.must_lead()) throw RuleError("你必须出牌");
    return apply(HUMAN, {});
}

CardIds Session::hint() {
    if (phase_ != "playing" || current_seat_ != HUMAN) return {};
    Move ranks = policy_.act(env_);
    return ranks.empty() ? CardIds{} : take_ids(hands_[HUMAN], ranks);
}

json Session::state() const {
    const bool playing = phase_ == "playing" || phase_ == "over";
    json bids = json::array(), counts = json::array(), display = json::array();
    for (int s = 0; s < 3; ++s) {
        bids.push_back(bids_[s].empty() ? json(nullptr) : json(bids_[s]));
        counts.push_back(hands_[s].size());
        display.push_back(display_[s]);
    }
    json winner = nullptr, human_won = nullptr, hands = nullptr;
    if (phase_ == "over") {
        winner = env_.landlord_won() ? "landlord" : "farmer";
        human_won = env_.landlord_won() == (landlord_seat_ == HUMAN);
        hands = hands_;  // reveal the AI hands only once the game is over
    }
    return {
        {"phase", phase_},
        {"current_seat", current_seat_},
        {"landlord_seat", landlord_seat_},
        {"bids", bids},
        {"bid_stage", phase_ == "bidding" ? json(bid_stage()) : json(nullptr)},
        {"rob_count", rob_count_},
        {"multiplier", 1 << (rob_count_ + (playing ? env_.bomb_num() : 0))},
        {"my_hand", hands_[HUMAN]},
        {"card_counts", counts},
        {"bottom_cards", playing ? bottom_ : CardIds{}},
        {"display", display},
        {"must_lead", phase_ == "playing" && env_.must_lead()},
        {"bomb_num", playing ? env_.bomb_num() : 0},
        {"winner", winner},
        {"human_won", human_won},
        {"hands", hands},
    };
}

void Session::setup(const std::array<CardIds, 3>& hands, const CardIds& bottom, int landlord_seat,
                    int bid_start) {
    new_game();
    for (int s = 0; s < 3; ++s) hands_[s] = sort_ids(hands[s]);
    bottom_ = sort_ids(bottom);
    bid_start_ = bid_start;
    start_bidding();
    if (landlord_seat >= 0) {
        bids_[landlord_seat] = "call";
        start_play(landlord_seat);
    }
}

json Session::force_play(const Move& ranks) {
    if (phase_ != "playing") throw RuleError("not playing");
    const auto& legal = env_.legal();
    if (std::find(legal.begin(), legal.end(), ranks) == legal.end()) throw RuleError("illegal move");
    return apply(current_seat_, ranks);
}

}  // namespace dz
