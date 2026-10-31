#include "session.hpp"

#include <algorithm>
#include <map>
#include <numeric>
#include <tuple>

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

std::pair<int, std::string> bottom_bonus(const CardIds& bottom) {
    std::map<int, int> counts;
    int jokers = 0;
    for (int id : bottom) {
        if (id >= 52) ++jokers;
        else ++counts[card_rank(id)];
    }
    int most = 0;
    for (auto [rank, n] : counts) most = std::max(most, n);
    if (jokers == 2) return {4, "双王"};
    if (most == 3) return {3, "三条"};
    if (jokers == 1) return {2, "单王"};
    if (most == 2) return {2, "对子"};
    return {1, ""};
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
    doubles_ = {-1, -1, -1};
    double_queue_.clear();
    bottom_mult_ = 1;
    bottom_kind_.clear();
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
    else start_doubling(candidate_);
    return event;
}

// The landlord takes the bottom cards (revealed to all) and the play env is set up,
// so the landlord's 加倍 can look at the model's value of their opening.
void Session::start_doubling(int landlord_seat) {
    landlord_seat_ = landlord_seat;
    hands_[landlord_seat].insert(hands_[landlord_seat].end(), bottom_.begin(), bottom_.end());
    hands_[landlord_seat] = sort_ids(hands_[landlord_seat]);
    std::tie(bottom_mult_, bottom_kind_) = bottom_bonus(bottom_);
    std::array<Move, 3> by_position;
    for (int pos = 0; pos < 3; ++pos) by_position[pos] = ranks_of(hands_[seat_of(pos)]);
    env_.init(by_position);
    phase_ = "doubling";
    double_queue_ = {seat_of(1), seat_of(2), landlord_seat};
    current_seat_ = double_queue_.front();
}

json Session::do_double(int seat, bool want) {
    double_queue_.erase(double_queue_.begin());
    doubles_[seat] = want ? 1 : 0;
    json event = {{"seat", seat}, {"type", "double"}, {"action", want ? "double" : "no_double"}};
    if (!double_queue_.empty()) current_seat_ = double_queue_.front();
    else start_play();
    return event;
}

bool Session::ai_double(int seat) {
    if (seat != landlord_seat_) return bid_score(seat) > FARMER_DOUBLE;
    auto values = policy_.evaluate(env_);
    return *std::max_element(values.begin(), values.end()) > LANDLORD_DOUBLE;
}

void Session::start_play() {
    phase_ = "playing";
    current_seat_ = landlord_seat_;
}

json Session::apply(int seat, const Move& ranks, CardIds ids) {
    if (env_.must_lead()) display_ = {};
    if (ids.empty() && !ranks.empty()) ids = take_ids(hands_[seat], ranks);
    ids = sort_ids(ids);
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
    if (phase_ == "doubling") return do_double(current_seat_, ai_double(current_seat_));
    return apply(current_seat_, policy_.act(env_));
}

json Session::human_bid(bool call) {
    if (phase_ != "bidding" || current_seat_ != HUMAN) throw RuleError("现在不能叫地主");
    return bid(HUMAN, call);
}

json Session::human_double(bool want) {
    if (phase_ != "doubling" || current_seat_ != HUMAN) throw RuleError("现在不能加倍");
    return do_double(HUMAN, want);
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
    return apply(HUMAN, ranks, ids);
}

json Session::human_pass() {
    if (phase_ != "playing" || current_seat_ != HUMAN) throw RuleError("还没轮到你");
    if (env_.must_lead()) throw RuleError("你必须出牌");
    return apply(HUMAN, {});
}

CardIds Session::hint(int index) {
    if (phase_ != "playing" || current_seat_ != HUMAN) return {};
    std::vector<Move> moves;
    for (const Move& m : policy_.ranked(env_))
        if (!m.empty()) moves.push_back(m);
    if (moves.empty()) return {};
    int n = static_cast<int>(moves.size());
    return take_ids(hands_[HUMAN], moves[((index % n) + n) % n]);
}

json Session::state() const {
    const bool revealed = phase_ != "bidding";
    json bids = json::array(), counts = json::array(), display = json::array(), doubles = json::array();
    for (int s = 0; s < 3; ++s) {
        bids.push_back(bids_[s].empty() ? json(nullptr) : json(bids_[s]));
        doubles.push_back(doubles_[s] < 0 ? json(nullptr) : json(doubles_[s] == 1));
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
        // shared by everyone: robs, bottom cards and bombs (加倍 is per player, see doubles)
        {"multiplier", (1 << (rob_count_ + (revealed ? env_.bomb_num() : 0))) * bottom_mult_},
        {"bottom_mult", bottom_mult_},
        {"bottom_kind", bottom_kind_},
        {"doubles", doubles},
        {"my_hand", hands_[HUMAN]},
        {"card_counts", counts},
        {"bottom_cards", revealed ? bottom_ : CardIds{}},
        {"display", display},
        {"must_lead", phase_ == "playing" && env_.must_lead()},
        // false when the player to act can only pass (nothing beats the last play)
        {"has_move", phase_ == "playing" && std::any_of(env_.legal().begin(), env_.legal().end(),
                                                        [](const Move& m) { return !m.empty(); })},
        {"bomb_num", revealed ? env_.bomb_num() : 0},
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
    if (landlord_seat >= 0) {  // skip bidding and 加倍
        bids_[landlord_seat] = "call";
        start_doubling(landlord_seat);
        doubles_ = {0, 0, 0};
        double_queue_.clear();
        start_play();
    }
}

json Session::force_play(const Move& ranks) {
    if (phase_ != "playing") throw RuleError("not playing");
    const auto& legal = env_.legal();
    if (std::find(legal.begin(), legal.end(), ranks) == legal.end()) throw RuleError("illegal move");
    return apply(current_seat_, ranks);
}

}  // namespace dz
