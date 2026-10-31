import pytest

from douzero_core import cards as C
from douzero_core.ai import DouZeroPolicy
from douzero_core.server import handle
from douzero_core.session import HUMAN, GameSession, RuleError, bottom_bonus


@pytest.fixture(scope="module")
def policy():
    return DouZeroPolicy()


def drive(session: GameSession, human_call=True):
    """Play a whole game; the human seat follows the model's hint."""
    events = []
    while session.phase != "over":
        if session.current_seat != HUMAN:
            events.append(session.step())
        elif session.phase == "bidding":
            events.append(session.human_bid(human_call))
        elif session.phase == "doubling":
            events.append(session.human_double(human_call))
        else:
            hint = session.hint()
            events.append(session.human_play(hint) if hint else session.human_pass())
    return events


def test_card_ids_cover_deck():
    ranks = C.ranks_of(C.ALL_CARD_IDS)
    assert len(ranks) == 54
    assert ranks.count(17) == 4 and ranks.count(20) == 1 and ranks.count(30) == 1


def test_take_ids_matches_ranks():
    hand = [0, 1, 2, 5, 52, 53]
    assert C.ranks_of(C.take_ids(hand, [3, 3, 20, 30])) == [3, 3, 20, 30]
    with pytest.raises(ValueError):
        C.take_ids(hand, [5])


@pytest.mark.parametrize("seed", range(20))
def test_full_games_terminate_and_conserve_cards(policy, seed):
    s = GameSession(policy, seed=seed)
    events = drive(s, human_call=seed % 2 == 0)
    st = s.state()
    assert st["winner"] in ("landlord", "farmer")
    assert 0 in st["card_counts"]
    played = [c for e in events if e["type"] == "play" for c in e["cards"]]
    assert len(played) == len(set(played))
    assert sorted(played + [c for h in s.hands for c in h]) == C.ALL_CARD_IDS


def test_rule_errors(policy):
    s = GameSession(policy, seed=1)
    while not (s.phase == "playing" and s.current_seat == HUMAN):
        if s.current_seat != HUMAN:
            s.step()
        elif s.phase == "doubling":
            s.human_double(False)
        else:
            s.human_bid(True)
    with pytest.raises(RuleError):
        s.step()
    with pytest.raises(RuleError):
        s.human_play([])
    if s.state()["must_lead"]:
        with pytest.raises(RuleError):
            s.human_pass()
    hand = s.hands[HUMAN]
    singles = [c for c in hand if C.card_rank(c) < 17]
    # 3 + a non-adjacent rank is never a legal two-card move
    bad = [singles[0]] + [c for c in hand if C.card_rank(c) - C.card_rank(singles[0]) > 1][:1]
    if len(bad) == 2:
        with pytest.raises(RuleError):
            s.human_play(bad)


def test_server_handle_reports_errors(policy):
    s = GameSession(policy, seed=3)
    resp = handle(s, {"id": 7, "cmd": "nope"})
    assert resp["id"] == 7 and resp["ok"] is False and "state" in resp
    resp = handle(s, {"id": 8, "cmd": "state"})
    assert resp["ok"] and resp["state"]["phase"] == "bidding"


def scripted_bidding(policy, start, wants):
    """Bid with every seat's decisions scripted: wants[seat] is a list of bools, in order."""
    s = GameSession(policy, seed=0)
    s.bid_start = start
    s._start_bidding()
    queue = {seat: list(w) for seat, w in enumerate(wants)}
    s._ai_bid = lambda seat: queue[seat].pop(0)
    events = []
    while s.phase == "bidding":
        seat = s.current_seat
        events.append(s.human_bid(queue[0].pop(0)) if seat == HUMAN else s.step())
        if events[-1].get("redeal"):
            break
    return s, [(e["seat"], e["action"]) for e in events]


def test_bidding_call_without_robs(policy):
    s, log = scripted_bidding(policy, 1, [[False], [True], [False]])
    assert log == [(1, "call"), (2, "no_rob"), (0, "no_rob")]
    assert s.landlord_seat == 1 and s.state()["multiplier"] == 1


def test_bidding_rob_and_caller_robs_back(policy):
    s, log = scripted_bidding(policy, 0, [[True, True], [True], [False]])
    assert log == [(0, "call"), (1, "rob"), (2, "no_rob"), (0, "rob")]
    assert s.landlord_seat == 0 and s.rob_count == 2 and s.state()["multiplier"] == 4
    assert len(s.hands[0]) == 20


def test_bidding_passers_cannot_rob(policy):
    s, log = scripted_bidding(policy, 0, [[False], [True, False], [True]])
    assert log == [(0, "pass"), (1, "call"), (2, "rob"), (1, "no_rob")]
    assert s.landlord_seat == 2 and s.rob_count == 1


def test_bidding_last_seat_call_ends_bidding(policy):
    s, log = scripted_bidding(policy, 2, [[False], [True], [False]])
    assert log == [(2, "pass"), (0, "pass"), (1, "call")]
    assert s.landlord_seat == 1 and s.phase == "doubling"


def test_bidding_all_pass_redeals(policy):
    s, log = scripted_bidding(policy, 0, [[False], [False], [False]])
    assert log[-1] == (2, "pass")
    assert s.phase == "bidding" and s.bids == [None, None, None] and s.current_seat == 0


@pytest.mark.parametrize("bottom, expected", [
    ([0, 4, 8], (1, "")), ([0, 1, 8], (2, "对子")), ([0, 1, 2], (3, "三条")),
    ([0, 52, 8], (2, "单王")), ([0, 1, 53], (2, "单王")), ([52, 53, 8], (4, "双王")),
])
def test_bottom_bonus(bottom, expected):
    assert bottom_bonus(bottom) == expected


def test_doubling_order_and_multiplier(policy):
    s, _ = scripted_bidding(policy, 1, [[False], [True], [False]])  # seat 1 is landlord
    assert s.phase == "doubling" and s.double_queue == [2, 0, 1] and s.current_seat == 2
    s._ai_double = lambda seat: seat == 2
    log = [s.step(), s.human_double(True), s.step()]
    assert [(e["seat"], e["action"]) for e in log] == [(2, "double"), (0, "double"), (1, "no_double")]
    st = s.state()
    assert st["phase"] == "playing" and st["current_seat"] == 1 and st["doubles"] == [True, False, True]
    assert st["multiplier"] == st["bottom_mult"] and st["bottom_cards"] == s.bottom
    with pytest.raises(RuleError):
        s.human_double(True)


def test_hint_cycles_through_moves(policy):
    s = GameSession(policy, seed=5)
    s._setup_playing(HUMAN)
    first, second = s.hint(0), s.hint(1)
    assert first and second and first != second
    assert s.hint(len(s.policy.ranked(s.infoset))) == first  # no pass while leading: wraps


def test_human_play_uses_the_chosen_suits(policy):
    s = GameSession(policy, seed=2)
    s._setup_playing(HUMAN)
    rank = next(r for r in set(C.ranks_of(s.hands[HUMAN])) if C.ranks_of(s.hands[HUMAN]).count(r) >= 2)
    same = [c for c in s.hands[HUMAN] if C.card_rank(c) == rank]
    pick = same[-1]  # not the lowest suit, which take_ids would choose
    event = s.human_play([pick])
    assert event["cards"] == [pick] and pick not in s.hands[HUMAN] and same[0] in s.hands[HUMAN]
