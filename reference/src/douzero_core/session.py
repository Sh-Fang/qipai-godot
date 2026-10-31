"""One game of 斗地主 between the human (seat 0) and two DouZero AIs.

Seats go counter-clockwise in play order: 0 = 我 (bottom), 1 = 下家 (right),
2 = 上家 (left). Once the landlord seat L is known, DouZero positions are
L -> landlord, L+1 -> landlord_down, L+2 -> landlord_up.

Bidding follows 欢乐斗地主 叫/抢地主: from a random seat each player in turn
may 叫地主 (call) until someone does; then every later player who has not
declined may 抢地主 (rob), and if anyone robbed, the caller gets a last chance
to rob back. The last player to call/rob becomes landlord; every rob doubles
the stake. If nobody calls, the cards are redealt. AIs decide with the
叫地主 model (ai.DouZeroPolicy.bid_score).

Then the bottom cards are revealed (底牌倍数: a pair x2, three of a kind x3,
one joker x2, both jokers x4, the best one counts) and each player chooses
加倍 or not, farmers first and the landlord last. A farmer's double only
affects that farmer's settlement with the landlord; the landlord's affects both.

The session never advances AI turns on its own: the UI calls step() once per
AI action so it can animate each move.
"""
import random

from . import cards as C
from .ai import DouZeroPolicy
from .env import move_detector as md
from .env.game import GameEnv

HUMAN = 0
SEAT_NAMES = ["我", "下家", "上家"]

MOVE_TYPE_NAMES = {
    md.TYPE_1_SINGLE: "单张", md.TYPE_2_PAIR: "对子", md.TYPE_3_TRIPLE: "三张",
    md.TYPE_4_BOMB: "炸弹", md.TYPE_5_KING_BOMB: "王炸", md.TYPE_6_3_1: "三带一",
    md.TYPE_7_3_2: "三带二", md.TYPE_8_SERIAL_SINGLE: "顺子", md.TYPE_9_SERIAL_PAIR: "连对",
    md.TYPE_10_SERIAL_TRIPLE: "飞机", md.TYPE_11_SERIAL_3_1: "飞机带单",
    md.TYPE_12_SERIAL_3_2: "飞机带对", md.TYPE_13_4_2: "四带二", md.TYPE_14_4_22: "四带两对",
}


class RuleError(Exception):
    """A human action that is not allowed; the message is shown in the UI."""


class _ScriptedPlayer:
    """GameEnv asks players to act(); we hand it the action decided outside."""

    def __init__(self):
        self.action = None

    def act(self, infoset):
        return self.action


def move_type_name(ranks) -> str:
    return MOVE_TYPE_NAMES.get(md.get_move_type(sorted(ranks))["type"], "")


CALL_THRESHOLD = 0.2  # thresholds used by the model's authors
ROB_THRESHOLD = 0.4
# AI 加倍: a farmer when the 叫地主 score of their 17 cards is above FARMER_DOUBLE, the
# landlord when the model's value of their best opening move is above LANDLORD_DOUBLE.
FARMER_DOUBLE = 0.3
LANDLORD_DOUBLE = 0.3


def bottom_bonus(bottom: list[int]) -> tuple[int, str]:
    """底牌倍数 of the three bottom cards: (multiplier, name), (1, "") if nothing special."""
    jokers = sum(c >= 52 for c in bottom)
    ranks = [C.card_rank(c) for c in bottom if c < 52]
    most = max((ranks.count(r) for r in ranks), default=0)
    if jokers == 2:
        return 4, "双王"
    if most == 3:
        return 3, "三条"
    if jokers == 1:
        return 2, "单王"
    if most == 2:
        return 2, "对子"
    return 1, ""


class GameSession:
    def __init__(self, policy: DouZeroPolicy, seed: int | None = None):
        self.policy = policy
        self.rng = random.Random(seed)
        self.new_game()

    # ---- setup -------------------------------------------------------------

    def new_game(self):
        self.phase = "bidding"
        self.landlord_seat = -1
        self.bid_start = self.rng.randrange(3)
        self.env = None
        self.display = [None, None, None]  # what each seat shows on the table
        self.winner = None
        self._deal()
        self._start_bidding()

    def _deal(self):
        deck = C.ALL_CARD_IDS.copy()
        self.rng.shuffle(deck)
        self.hands = [C.sort_ids(deck[i * 17:(i + 1) * 17]) for i in range(3)]
        self.bottom = C.sort_ids(deck[51:])

    def position_of(self, seat: int) -> str:
        return ("landlord", "landlord_down", "landlord_up")[(seat - self.landlord_seat) % 3]

    def seat_of(self, position: str) -> int:
        offset = {"landlord": 0, "landlord_down": 1, "landlord_up": 2}[position]
        return (self.landlord_seat + offset) % 3

    # ---- bidding -----------------------------------------------------------

    def _start_bidding(self):
        self.bids = [None, None, None]  # last bid action per seat: call / pass / rob / no_rob
        self.bid_queue = [(self.bid_start + i) % 3 for i in range(3)]
        self.caller = -1      # who called first
        self.candidate = -1   # landlord if bidding ended now
        self.rob_count = 0
        self.caller_last_chance = False
        self.doubles = [None, None, None]  # 加倍 per seat
        self.double_queue = []
        self.bottom_mult, self.bottom_kind = 1, ""
        self.current_seat = self.bid_queue[0]

    @property
    def bid_stage(self) -> str:
        return "call" if self.caller < 0 else "rob"

    def _bid(self, seat: int, want: bool) -> dict:
        self.bid_queue.pop(0)
        if self.caller < 0:
            action = "call" if want else "pass"
            if want:
                self.caller = self.candidate = seat
        else:
            action = "rob" if want else "no_rob"
            if want:
                self.candidate = seat
                self.rob_count += 1
        self.bids[seat] = action
        event = {"seat": seat, "type": "bid", "action": action}
        if not self.bid_queue:
            if self.caller < 0:
                # nobody wants it: redeal and bid again from the same seat
                self._deal()
                self._start_bidding()
                event["redeal"] = True
                return event
            if self.rob_count > 0 and not self.caller_last_chance:
                self.caller_last_chance = True
                self.bid_queue.append(self.caller)
        if self.bid_queue:
            self.current_seat = self.bid_queue[0]
        else:
            self._start_doubling(self.candidate)
        return event

    def _ai_bid(self, seat: int) -> bool:
        score = self.policy.bid_score(C.ranks_of(self.hands[seat]))
        return score > (CALL_THRESHOLD if self.bid_stage == "call" else ROB_THRESHOLD)

    def _start_doubling(self, landlord_seat: int):
        """The landlord takes the (revealed) bottom cards and the play env is set up,
        so the landlord's 加倍 can look at the model's value of their opening."""
        self.landlord_seat = landlord_seat
        self.hands[landlord_seat] = C.sort_ids(self.hands[landlord_seat] + self.bottom)
        self.bottom_mult, self.bottom_kind = bottom_bonus(self.bottom)
        self.players = {p: _ScriptedPlayer() for p in ("landlord", "landlord_up", "landlord_down")}
        self.env = GameEnv(self.players)
        self.env.card_play_init({
            "landlord": C.ranks_of(self.hands[landlord_seat]),
            "landlord_down": C.ranks_of(self.hands[(landlord_seat + 1) % 3]),
            "landlord_up": C.ranks_of(self.hands[(landlord_seat + 2) % 3]),
            "three_landlord_cards": C.ranks_of(self.bottom),
        })
        self.phase = "doubling"
        self.double_queue = [(landlord_seat + 1) % 3, (landlord_seat + 2) % 3, landlord_seat]
        self.current_seat = self.double_queue[0]

    def _double(self, seat: int, want: bool) -> dict:
        self.double_queue.pop(0)
        self.doubles[seat] = want
        event = {"seat": seat, "type": "double", "action": "double" if want else "no_double"}
        if self.double_queue:
            self.current_seat = self.double_queue[0]
        else:
            self._start_play()
        return event

    def _ai_double(self, seat: int) -> bool:
        if seat != self.landlord_seat:
            return self.policy.bid_score(C.ranks_of(self.hands[seat])) > FARMER_DOUBLE
        return float(max(self.policy.evaluate(self.infoset))) > LANDLORD_DOUBLE

    def _start_play(self):
        self.phase = "playing"
        self.current_seat = self.landlord_seat

    def _setup_playing(self, landlord_seat: int):
        """Test hook: skip bidding and 加倍, landlord_seat leads."""
        self.bids[landlord_seat] = "call"
        self._start_doubling(landlord_seat)
        self.doubles = [False, False, False]
        self.double_queue = []
        self._start_play()

    # ---- playing -----------------------------------------------------------

    @property
    def infoset(self):
        return self.env.game_infoset

    def _must_lead(self) -> bool:
        return [] not in self.infoset.legal_actions

    def _apply(self, seat: int, ranks: list[int], ids: list[int] | None = None) -> dict:
        """`ids`: the exact cards (the human's pick); None = lowest suits realizing `ranks`."""
        if self._must_lead():
            self.display = [None, None, None]
        ids = C.sort_ids(ids) if ids else (C.take_ids(self.hands[seat], ranks) if ranks else [])
        self.players[self.position_of(seat)].action = sorted(ranks)
        self.env.step()
        for c in ids:
            self.hands[seat].remove(c)
        self.display[seat] = {"cards": ids, "pass": not ids}
        event = {"seat": seat, "type": "play" if ids else "pass", "cards": ids,
                 "move_type": move_type_name(ranks) if ids else ""}
        if self.env.game_over:
            self.phase = "over"
            self.winner = self.env.get_winner()  # "landlord" or "farmer"
            self.current_seat = -1
        else:
            self.current_seat = self.seat_of(self.env.acting_player_position)
        return event

    # ---- public actions ----------------------------------------------------

    def step(self) -> dict:
        """Let the AI in the current seat take exactly one action."""
        seat = self.current_seat
        if self.phase == "over":
            raise RuleError("本局已结束")
        if seat == HUMAN:
            raise RuleError("现在轮到你")
        if self.phase == "bidding":
            return self._bid(seat, self._ai_bid(seat))
        if self.phase == "doubling":
            return self._double(seat, self._ai_double(seat))
        return self._apply(seat, self.policy.act(self.infoset))

    def human_bid(self, call: bool) -> dict:
        if self.phase != "bidding" or self.current_seat != HUMAN:
            raise RuleError("现在不能叫地主")
        return self._bid(HUMAN, call)

    def human_double(self, want: bool) -> dict:
        if self.phase != "doubling" or self.current_seat != HUMAN:
            raise RuleError("现在不能加倍")
        return self._double(HUMAN, want)

    def human_play(self, card_ids: list[int]) -> dict:
        if self.phase != "playing" or self.current_seat != HUMAN:
            raise RuleError("还没轮到你出牌")
        if not card_ids:
            raise RuleError("请先选牌")
        if any(c not in self.hands[HUMAN] for c in card_ids):
            raise RuleError("选中的牌不在手里")
        ranks = C.ranks_of(card_ids)
        if ranks not in self.infoset.legal_actions:
            if md.get_move_type(ranks)["type"] == md.TYPE_15_WRONG:
                raise RuleError("不是合法牌型")
            raise RuleError("管不上")
        return self._apply(HUMAN, ranks, list(card_ids))

    def human_pass(self) -> dict:
        if self.phase != "playing" or self.current_seat != HUMAN:
            raise RuleError("还没轮到你")
        if self._must_lead():
            raise RuleError("你必须出牌")
        return self._apply(HUMAN, [])

    def hint(self, index: int = 0) -> list[int]:
        """The human's index-th best move by the model (wrapping around), [] if only pass."""
        if self.phase != "playing" or self.current_seat != HUMAN:
            return []
        moves = [m for m in self.policy.ranked(self.infoset) if m]
        return C.take_ids(self.hands[HUMAN], moves[index % len(moves)]) if moves else []

    # ---- view --------------------------------------------------------------

    def state(self) -> dict:
        """Everything the UI may show to the human player."""
        revealed = self.phase != "bidding"
        bombs = self.env.get_bomb_num() if revealed else 0
        return {
            "phase": self.phase,
            "current_seat": self.current_seat,
            "landlord_seat": self.landlord_seat,
            "bids": self.bids,
            "bid_stage": self.bid_stage if self.phase == "bidding" else None,
            "rob_count": self.rob_count,
            # shared by everyone: robs, bottom cards and bombs (加倍 is per player, see doubles)
            "multiplier": 2 ** (self.rob_count + bombs) * self.bottom_mult,
            "bottom_mult": self.bottom_mult,
            "bottom_kind": self.bottom_kind,
            "doubles": self.doubles,
            "my_hand": self.hands[HUMAN],
            "card_counts": [len(h) for h in self.hands],
            "bottom_cards": self.bottom if revealed else [],
            "display": self.display,
            "must_lead": self.phase == "playing" and self._must_lead(),
            # false when the player to act can only pass (nothing beats the last play)
            "has_move": self.phase == "playing" and any(self.infoset.legal_actions),
            "bomb_num": bombs,
            "winner": self.winner,
            "human_won": None if self.winner is None else
                (self.winner == "landlord") == (self.landlord_seat == HUMAN),
            # reveal the AI hands only once the game is over
            "hands": self.hands if self.phase == "over" else None,
        }
