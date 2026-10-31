"""五子棋 in the C++ core (no Python reference: it is not a DouZero port).

Drives core/build/douzero-cli through the gomoku_* commands. Skipped when it has not
been built yet.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_cpp import DEFAULT_CLI, CppCore  # noqa: E402

pytestmark = pytest.mark.skipif(not DEFAULT_CLI.exists(), reason="C++ core not built")

BLACK, WHITE = 1, 2


@pytest.fixture(scope="module")
def cpp():
    core = CppCore(DEFAULT_CLI)
    yield core
    core.proc.kill()


def raw(cpp, cmd, **args):
    """Like cpp(...) but returns failed replies instead of raising."""
    cpp.proc.stdin.write(json.dumps({"cmd": cmd, **args}) + "\n")
    cpp.proc.stdin.flush()
    return json.loads(cpp.proc.stdout.readline())


def at(st, x, y):
    return st["board"][y * 15 + x]


def test_five_wins_and_marks_the_line(cpp):
    # black 3..7 on row 7, white wastes moves on row 0
    moves = [m for i in range(4) for m in ([3 + i, 7], [i, 0])]
    cpp("gomoku_setup", moves=moves, human=BLACK, level=0)
    st = cpp("gomoku_play", x=7, y=7)["state"]
    assert st["phase"] == "over" and st["winner"] == BLACK and st["human_won"]
    assert st["line"] == [[x, 7] for x in range(3, 8)]
    assert raw(cpp, "gomoku_play", x=8, y=8)["error"] == "对局已结束"


def test_six_in_a_row_also_wins(cpp):
    # black 2,3,4 _ 6,7 then fills 5: six in a row (no 长连禁手)
    moves = [[2, 7], [0, 0], [3, 7], [1, 0], [4, 7], [2, 0], [6, 7], [3, 0], [7, 7], [0, 14]]
    cpp("gomoku_setup", moves=moves, human=BLACK, level=0)
    st = cpp("gomoku_play", x=5, y=7)["state"]
    assert st["winner"] == BLACK and len(st["line"]) == 6


def test_turn_and_occupied_errors(cpp):
    st = cpp("gomoku_new", human=WHITE, level=0)["state"]
    assert st["to_move"] == BLACK and st["human"] == WHITE and not st["can_undo"]
    assert raw(cpp, "gomoku_play", x=7, y=7)["error"] == "还没轮到你"
    ev = cpp("gomoku_step")["event"]
    assert (ev["x"], ev["y"]) == (7, 7)  # the AI opens in the centre
    assert raw(cpp, "gomoku_play", x=7, y=7)["error"] == "这里已经有子了"
    assert raw(cpp, "gomoku_step")["error"] == "轮到你了"


def test_undo_takes_back_a_round(cpp):
    cpp("gomoku_new", human=BLACK, level=1, seed=3)
    cpp("gomoku_play", x=7, y=7)
    ai = cpp("gomoku_step")["event"]
    cpp("gomoku_play", x=14, y=14)  # far from the AI's reply next to the centre
    reply = cpp("gomoku_undo")  # before the AI answered: only my move goes
    assert reply["event"]["removed"] == [[14, 14]]
    st = reply["state"]
    assert st["to_move"] == BLACK and at(st, ai["x"], ai["y"]) == WHITE and st["assisted"]
    reply = cpp("gomoku_undo")  # my first move and the AI's reply
    assert reply["event"]["removed"] == [[ai["x"], ai["y"]], [7, 7]]
    assert reply["state"]["move_count"] == 0 and not reply["state"]["can_undo"]
    assert raw(cpp, "gomoku_undo")["error"] == "没有可以悔的棋"


def test_hint_blocks_and_marks_assisted(cpp):
    # white (AI) threatens five on row 0; the hint for black is the block
    moves = [[7, 7], [0, 0], [8, 8], [1, 0], [3, 12], [2, 0], [12, 3], [3, 0]]
    st = cpp("gomoku_setup", moves=moves, human=BLACK, level=2)["state"]
    assert not st["assisted"]
    reply = cpp("gomoku_hint")
    assert reply["hint"] == [4, 0] and reply["state"]["assisted"]


@pytest.mark.parametrize("level", [0, 1, 2])
def test_ai_takes_a_win(cpp, level):
    moves = [[7, 7], [0, 0], [8, 8], [1, 0], [3, 12], [2, 0], [12, 3], [3, 0], [11, 3]]
    cpp("gomoku_setup", moves=moves, human=BLACK, level=level)
    st = cpp("gomoku_step")["state"]
    assert st["winner"] == WHITE and at(st, 4, 0) == WHITE


@pytest.mark.parametrize("level", [1, 2])
def test_ai_blocks_a_four(cpp, level):
    # black 4 in a row with one end open (white already at 6,7)
    moves = [[7, 7], [6, 7], [8, 7], [0, 14], [9, 7], [14, 0], [10, 7]]
    cpp("gomoku_setup", moves=moves, human=BLACK, level=level)
    ev = cpp("gomoku_step")["event"]
    assert (ev["x"], ev["y"]) == (11, 7)


def test_hard_blocks_an_open_three(cpp):
    cpp("gomoku_setup", moves=[[7, 7], [7, 8], [8, 7], [8, 9], [9, 7]], human=BLACK, level=2)
    ev = cpp("gomoku_step")["event"]
    assert (ev["x"], ev["y"]) in [(6, 7), (10, 7), (5, 7), (11, 7)]


def selfplay(cpp, black_level, white_level, seed):
    st = cpp("gomoku_new", human=BLACK, level=0, seed=seed)["state"]
    while st["phase"] == "playing":
        level = black_level if st["to_move"] == BLACK else white_level
        st = cpp("gomoku_debug_step", level=level)["state"]
    return st["winner"]


def test_harder_levels_win_more(cpp):
    """A stronger AI beats a weaker one most of the time, even with white."""
    for strong, weak in [(1, 0), (2, 1)]:
        wins = sum(selfplay(cpp, weak, strong, seed) == WHITE for seed in range(20))
        assert wins >= 12, (strong, weak, wins)


def test_easy_usually_blocks_an_open_three(cpp):
    """简单 slips now and then, but doesn't ignore a plain open three."""
    moves = [[7, 7], [6, 8], [8, 7], [8, 8], [9, 7]]  # black 7..9 on row 7, both ends open
    blocks = 0
    for seed in range(30):
        cpp("gomoku_new", human=BLACK, level=0, seed=seed)
        cpp("gomoku_setup", moves=moves, human=BLACK, level=0)
        ev = cpp("gomoku_step")["event"]
        blocks += (ev["x"], ev["y"]) in [(6, 7), (10, 7), (5, 7), (11, 7)]
    assert blocks >= 21, blocks
