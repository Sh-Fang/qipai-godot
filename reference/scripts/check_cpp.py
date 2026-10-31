"""Cross-check the C++ core against this Python reference, step by step.

Bidding: both cores get the same deal and first bidder; at every bid we compare
the 叫地主 model score, the event and the whole UI state (the human seat bids
at random so 抢地主 paths get exercised), then the same through 加倍. A redeal ends the check, since each
core reshuffles with its own RNG.

Card play: both cores get the same deal and landlord, then at every move we compare the
legal moves, the model value of each move, the emitted event and the whole UI
state. Half of the moves are random legal moves (not the model's choice) so
rare move types and rival combinations get exercised too.

    uv run python scripts/check_cpp.py [games] [path/to/douzero-cli]
"""
import json
import random
import subprocess
import sys
from pathlib import Path

from douzero_core import cards as C
from douzero_core.ai import DouZeroPolicy
from douzero_core.session import HUMAN, GameSession

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CLI = ROOT / "core" / "build" / "douzero-cli"
TOLERANCE = 1e-4


class CppCore:
    def __init__(self, cli: Path):
        self.proc = subprocess.Popen([str(cli)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def __call__(self, cmd: str, **args) -> dict:
        self.proc.stdin.write(json.dumps({"cmd": cmd, **args}) + "\n")
        self.proc.stdin.flush()
        reply = json.loads(self.proc.stdout.readline())
        if not reply["ok"]:
            raise AssertionError(f"C++ {cmd} failed: {reply['error']}")
        return reply


def normalized(obj):
    return json.loads(json.dumps(obj))


def check_bidding(seed: int, policy: DouZeroPolicy, cpp: CppCore) -> int:
    rng = random.Random(seed)
    py = GameSession(policy, seed=seed)
    cpp("debug_setup", hands=py.hands, bottom=py.bottom, bid_start=py.bid_start)
    bids = 0
    while py.phase in ("bidding", "doubling"):
        seat = py.current_seat
        if py.phase == "bidding":
            score = policy.bid_score(C.ranks_of(py.hands[seat]))
            assert abs(score - cpp("debug_eval")["bid_score"]) < TOLERANCE, f"seed {seed}: bid scores differ"
        if seat == HUMAN:
            want = rng.random() < 0.5
            if py.phase == "bidding":
                py_event, reply = py.human_bid(want), cpp("bid", call=want)
            else:
                py_event, reply = py.human_double(want), cpp("double", double=want)
        else:
            py_event, reply = py.step(), cpp("step")
        assert normalized(py_event) == reply["event"], f"seed {seed} bid {bids}: events differ"
        bids += 1
        if py_event.get("redeal"):
            break
        assert normalized(py.state()) == reply["state"], f"seed {seed} bid {bids}: states differ"
    return bids


def check_game(seed: int, policy: DouZeroPolicy, cpp: CppCore) -> tuple[int, float]:
    rng = random.Random(seed)
    py = GameSession(policy, seed=seed)
    landlord = seed % 3
    cpp("debug_setup", hands=py.hands, bottom=py.bottom, landlord=landlord)
    py._setup_playing(landlord)

    steps, worst = 0, 0.0
    while py.phase != "over":
        info = py.infoset
        reply = cpp("debug_eval")
        py_values = dict(zip(map(tuple, info.legal_actions), policy.evaluate(info)))
        cpp_values = dict(zip(map(tuple, reply["actions"]), reply["values"]))
        # DouZero's Python generator can list a 4+2 / plane-with-wings move twice
        # (itertools.groupby only drops adjacent repeats); C++ dedupes, so compare sets.
        assert set(py_values) == set(cpp_values) and len(cpp_values) == len(reply["actions"]), \
            f"seed {seed} step {steps}: legal moves differ"
        for action, v in py_values.items():
            worst = max(worst, abs(v - cpp_values[action]))
        assert worst < TOLERANCE, f"seed {seed} step {steps}: values differ by {worst}"

        ranks = rng.choice(info.legal_actions) if rng.random() < 0.5 else policy.act(info)
        py_event = py._apply(py.current_seat, sorted(ranks))
        cpp_reply = cpp("debug_play", ranks=sorted(ranks))
        assert normalized(py_event) == cpp_reply["event"], f"seed {seed} step {steps}: events differ"
        assert normalized(py.state()) == cpp_reply["state"], f"seed {seed} step {steps}: states differ"
        steps += 1
    return steps, worst


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    cli = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_CLI
    policy = DouZeroPolicy()
    cpp = CppCore(cli)
    total_steps, total_bids, worst = 0, 0, 0.0
    for seed in range(games):
        total_bids += check_bidding(seed, policy, cpp)
        steps, w = check_game(seed, policy, cpp)
        total_steps += steps
        worst = max(worst, w)
    print(f"OK: {games} games, {total_bids} bids and {total_steps} moves identical; "
          f"max value diff {worst:.2e}")


if __name__ == "__main__":
    main()
