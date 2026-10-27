// 斗地主 card-play rules, ported 1:1 from DouZero's move_detector /
// move_generator / move_selector (Apache-2.0, see LICENSE-DouZero).
//
// A Move is a sorted list of DouZero rank values:
// 3..14 = 3..A, 17 = 2, 20 = 小王, 30 = 大王. The empty move is "pass".
#pragma once

#include <vector>

namespace dz {

using Move = std::vector<int>;

enum MoveType {
    TYPE_0_PASS = 0,
    TYPE_1_SINGLE,
    TYPE_2_PAIR,
    TYPE_3_TRIPLE,
    TYPE_4_BOMB,
    TYPE_5_KING_BOMB,
    TYPE_6_3_1,
    TYPE_7_3_2,
    TYPE_8_SERIAL_SINGLE,
    TYPE_9_SERIAL_PAIR,
    TYPE_10_SERIAL_TRIPLE,
    TYPE_11_SERIAL_3_1,
    TYPE_12_SERIAL_3_2,
    TYPE_13_4_2,
    TYPE_14_4_22,
    TYPE_15_WRONG,
};

struct MoveInfo {
    int type = TYPE_15_WRONG;
    int rank = 0;
    int len = 1;
};

// Classify a sorted move.
MoveInfo move_type(const Move& move);

// Chinese name of a move type ("单张", "炸弹", ...), empty for pass/wrong.
const char* move_type_name(int type);

bool is_bomb(const Move& move);

// Every legal move for `hand` (sorted) when the move to beat is `rival`
// (empty = free lead). Includes the pass move [] when rival is not empty.
std::vector<Move> legal_actions(const Move& hand, const Move& rival);

}  // namespace dz
