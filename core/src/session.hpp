// One game of 斗地主 between the human (seat 0) and two DouZero AIs.
//
// Seats go counter-clockwise in play order: 0 = 我 (bottom), 1 = 下家 (right),
// 2 = 上家 (left). With landlord seat L, a seat's DouZero position is
// (seat - L) mod 3, i.e. L -> landlord, L+1 -> landlord_down, L+2 -> landlord_up.
//
// Bidding follows 欢乐斗地主 叫/抢地主: from a random seat each player in turn
// may 叫地主 (call) until someone does; then every later player who has not
// declined may 抢地主 (rob), and if anyone robbed, the caller gets a last chance
// to rob back. The last player to call/rob becomes landlord; every rob doubles
// the stake. If nobody calls, the cards are redealt. AIs decide with the
// 叫地主 model (Policy::bid_score).
//
// The session never advances AI turns on its own: the UI calls step() once per
// AI action so it can animate each move.
#pragma once

#include <array>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "game.hpp"
#include "policy.hpp"

namespace dz {

using json = nlohmann::json;
using CardIds = std::vector<int>;

constexpr int HUMAN = 0;

// A human action that is not allowed; the message is shown in the UI.
struct RuleError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

// UI card ids: 0..51 = rank_index * 4 + suit (♠♥♣♦), 52 = 小王, 53 = 大王.
int card_rank(int id);
Move ranks_of(const CardIds& ids);
CardIds sort_ids(CardIds ids);
// Concrete ids from `hand` realizing `ranks` (lowest suit first).
CardIds take_ids(const CardIds& hand, const Move& ranks);

// AI bids when the 叫地主 model score is above these (the model authors' values).
constexpr float CALL_THRESHOLD = 0.2f;
constexpr float ROB_THRESHOLD = 0.4f;

class Session {
public:
    Session(Policy& policy, uint64_t seed);

    void new_game();
    void reseed(uint64_t seed) { rng_.seed(seed); }

    json step();  // the AI in the current seat acts once
    json human_bid(bool call);
    json human_play(const CardIds& ids);
    json human_pass();
    CardIds hint();
    json state() const;

    // Test hooks (used by the Python cross-check): a fixed deal that either
    // starts bidding at bid_start (landlord_seat < 0) or skips it, and moves
    // forced for whichever seat is acting.
    void setup(const std::array<CardIds, 3>& hands, const CardIds& bottom, int landlord_seat, int bid_start);
    bool bidding() const { return phase_ == "bidding"; }
    float bid_score(int seat) { return policy_.bid_score(ranks_of(hands_[seat])); }
    int current_seat() const { return current_seat_; }
    const GameEnv& env() const { return env_; }
    Policy& policy() { return policy_; }
    json force_play(const Move& ranks);

private:
    void deal();
    void start_bidding();
    const char* bid_stage() const { return caller_ < 0 ? "call" : "rob"; }
    json bid(int seat, bool want);
    void start_play(int landlord_seat);
    json apply(int seat, const Move& ranks);
    int seat_of(int pos) const { return (landlord_seat_ + pos) % 3; }

    Policy& policy_;
    std::mt19937_64 rng_;
    std::string phase_;
    int current_seat_ = 0;
    int landlord_seat_ = -1;
    int bid_start_ = 0;
    std::array<std::string, 3> bids_;  // last bid action per seat: call / pass / rob / no_rob
    std::vector<int> bid_queue_;       // seats still to bid, in order
    int caller_ = -1;                  // who called first
    int candidate_ = -1;               // landlord if bidding ended now
    int rob_count_ = 0;
    bool caller_last_chance_ = false;
    std::array<CardIds, 3> hands_;
    CardIds bottom_;
    std::array<json, 3> display_;  // what each seat shows on the table (null = nothing)
    GameEnv env_;
};

}  // namespace dz
