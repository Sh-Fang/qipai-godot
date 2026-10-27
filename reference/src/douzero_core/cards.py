"""Card ids used by the UI <-> DouZero rank values used by the env.

Card id 0..51: rank_index = id // 4 (3,4,...,K,A,2), suit = id % 4 (♠♥♣♦).
Card id 52 = 小王 (env 20), 53 = 大王 (env 30).
"""
RANK_VALUES = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17]
RANK_NAMES = {3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8", 9: "9", 10: "10",
              11: "J", 12: "Q", 13: "K", 14: "A", 17: "2", 20: "小王", 30: "大王"}
SUITS = ["♠", "♥", "♣", "♦"]

ALL_CARD_IDS = list(range(54))


def card_rank(card_id: int) -> int:
    if card_id == 52:
        return 20
    if card_id == 53:
        return 30
    return RANK_VALUES[card_id // 4]


def card_suit(card_id: int) -> int:
    """0..3 for normal cards, -1 for jokers."""
    return card_id % 4 if card_id < 52 else -1


def ranks_of(card_ids) -> list[int]:
    return sorted(card_rank(c) for c in card_ids)


def sort_ids(card_ids) -> list[int]:
    """Sort by rank then suit, the order the hand is displayed in."""
    return sorted(card_ids, key=lambda c: (card_rank(c), card_suit(c)))


def take_ids(hand_ids, ranks) -> list[int]:
    """Pick concrete card ids from a hand that realize the given rank list."""
    pool = sort_ids(hand_ids)
    picked = []
    for r in ranks:
        for c in pool:
            if card_rank(c) == r and c not in picked:
                picked.append(c)
                break
        else:
            raise ValueError(f"rank {r} not in hand")
    return sort_ids(picked)


def describe(ranks) -> str:
    return " ".join(RANK_NAMES[r] for r in sorted(ranks))
