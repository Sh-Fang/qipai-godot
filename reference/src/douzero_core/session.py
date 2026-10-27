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
            self._start_play(self.candidate)
        return event

    def _ai_bid(self, seat: int) -> bool:
        score = self.policy.bid_score(C.ranks_of(self.hands[seat]))
        return score > (CALL_THRESHOLD if self.bid_stage == "call" else ROB_THRESHOLD)

    def _start_play(self, landlord_seat: int):
        self.landlord_seat = landlord_seat
        self.hands[landlord_seat] = C.sort_ids(self.hands[landlord_seat] + self.bottom)
        self.players = {p: _ScriptedPlayer() for p in ("landlord", "landlord_up", "landlord_down")}
        self.env = GameEnv(self.players)
        self.env.card_play_init({
            "landlord": C.ranks_of(self.hands[landlord_seat]),
            "landlord_down": C.ranks_of(self.hands[(landlord_seat + 1) % 3]),
            "landlord_up": C.ranks_of(self.hands[(landlord_seat + 2) % 3]),
            "three_landlord_cards": C.ranks_of(self.bottom),
        })
        self.phase = "playing"
        self.current_seat = landlord_seat

    # ---- playing -----------------------------------------------------------

    @property
    def infoset(self):
        return self.env.game_infoset

    def _must_lead(self) -> bool:
        return [] not in self.infoset.legal_actions

    def _apply(self, seat: int, ranks: list[int]) -> dict:
        if self._must_lead():
            self.display = [None, None, None]
        ids = C.take_ids(self.hands[seat], ranks) if ranks else []
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
        return self._apply(seat, self.policy.act(self.infoset))

    def human_bid(self, call: bool) -> dict:
        if self.phase != "bidding" or self.current_seat != HUMAN:
            raise RuleError("现在不能叫地主")
        return self._bid(HUMAN, call)

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
        return self._apply(HUMAN, ranks)

    def human_pass(self) -> dict:
        if self.phase != "playing" or self.current_seat != HUMAN:
            raise RuleError("还没轮到你")
        if self._must_lead():
            raise RuleError("你必须出牌")
        return self._apply(HUMAN, [])

    def hint(self) -> list[int]:
        """Card ids the landlord/farmer model would play in the human's seat."""
        if self.phase != "playing" or self.current_seat != HUMAN:
            return []
        ranks = self.policy.act(self.infoset)
        return C.take_ids(self.hands[HUMAN], ranks) if ranks else []

    # ---- view --------------------------------------------------------------

    def state(self) -> dict:
        """Everything the UI may show to the human player."""
        playing = self.phase in ("playing", "over")
        return {
            "phase": self.phase,
            "current_seat": self.current_seat,
            "landlord_seat": self.landlord_seat,
            "bids": self.bids,
            "bid_stage": self.bid_stage if self.phase == "bidding" else None,
            "rob_count": self.rob_count,
            "multiplier": 2 ** (self.rob_count + (self.env.get_bomb_num() if playing else 0)),
            "my_hand": self.hands[HUMAN],
            "card_counts": [len(h) for h in self.hands],
            "bottom_cards": self.bottom if playing else [],
            "display": self.display,
            "must_lead": self.phase == "playing" and self._must_lead(),
            "bomb_num": self.env.get_bomb_num() if playing else 0,
            "winner": self.winner,
            "human_won": None if self.winner is None else
                (self.winner == "landlord") == (self.landlord_seat == HUMAN),
            # reveal the AI hands only once the game is over
            "hands": self.hands if self.phase == "over" else None,
        }
