"""The C++ core (core/) must behave exactly like this Python reference.

Skipped when core/build/douzero-cli has not been built yet.
"""
import json
import sys
from pathlib import Path

import pytest

from douzero_core import cards as C
from douzero_core.ai import DouZeroPolicy

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_cpp import DEFAULT_CLI, CppCore, check_bidding, check_game  # noqa: E402

pytestmark = pytest.mark.skipif(not DEFAULT_CLI.exists(), reason="C++ core not built")


@pytest.fixture(scope="module")
def policy():
    return DouZeroPolicy()


@pytest.fixture(scope="module")
def cpp():
    core = CppCore(DEFAULT_CLI)
    yield core
    core.proc.kill()


@pytest.mark.parametrize("seed", range(30))
def test_same_moves_values_and_states(policy, cpp, seed):
    check_game(seed, policy, cpp)


@pytest.mark.parametrize("seed", range(40))
def test_same_bidding(policy, cpp, seed):
    check_bidding(seed, policy, cpp)


def raw(cpp, cmd, **args):
    """Like cpp(...) but returns failed replies instead of raising."""
    cpp.proc.stdin.write(json.dumps({"cmd": cmd, **args}) + "\n")
    cpp.proc.stdin.flush()
    return json.loads(cpp.proc.stdout.readline())


@pytest.mark.parametrize("seed", range(5))
def test_protocol_full_game(cpp, seed):
    """Drive a whole game through the public commands, the human following hints."""
    st = cpp("new_game", seed=seed)["state"]
    played = []
    while st["phase"] != "over":
        if st["current_seat"] != 0:
            reply = cpp("step")
        elif st["phase"] == "bidding":
            reply = cpp("bid", call=True)
        else:
            hint = cpp("hint")["hint"]
            reply = cpp("play", cards=hint) if hint else cpp("pass")
        if reply["event"] and reply["event"]["type"] == "play":
            played += reply["event"]["cards"]
        st = reply["state"]
    assert st["winner"] in ("landlord", "farmer") and 0 in st["card_counts"]
    assert sorted(played + [c for h in st["hands"] for c in h]) == C.ALL_CARD_IDS


def test_protocol_errors(cpp):
    st = cpp("new_game", seed=1)["state"]
    while not (st["phase"] == "playing" and st["current_seat"] == 0):
        st = (cpp("step") if st["current_seat"] != 0 else cpp("bid", call=True))["state"]
    assert raw(cpp, "play", cards=[])["error"] == "请先选牌"
    assert raw(cpp, "play", cards=[99])["error"] == "选中的牌不在手里"
    hand = st["my_hand"]
    a, b = hand[0], next(c for c in hand if C.card_rank(c) != C.card_rank(hand[0]))
    if {a, b} != {52, 53}:
        assert raw(cpp, "play", cards=[a, b])["error"] == "不是合法牌型"
    if st["must_lead"]:
        assert raw(cpp, "pass")["error"] == "你必须出牌"
    assert raw(cpp, "step")["error"] == "现在轮到你"
    assert raw(cpp, "nope")["ok"] is False
