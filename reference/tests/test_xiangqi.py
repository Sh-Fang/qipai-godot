"""象棋 in the C++ core (ElephantEye inside; no Python reference).

Drives core/build/douzero-cli through the xiangqi_* commands. Squares are (x, y):
x = file 0..8 from red's left, y = rank 0..9 from black's back rank. Skipped when the
CLI has not been built yet.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_cpp import DEFAULT_CLI, CppCore  # noqa: E402

pytestmark = pytest.mark.skipif(not DEFAULT_CLI.exists(), reason="C++ core not built")

RED, BLACK = 0, 1


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
    return st["board"][y * 9 + x]


def test_start_position(cpp):
    st = cpp("xiangqi_new", human=RED, level=0)["state"]
    assert "".join(st["board"][81:90]) == "RNBAKABNR" and "".join(st["board"][:9]) == "rnbakabnr"
    assert st["to_move"] == "red" and len(st["legal"]) == 44 and not st["can_undo"]
    assert raw(cpp, "xiangqi_play", move=[0, 9, 0, 5])["error"] == "这步棋不能走"  # 车 can't jump the 兵
    assert raw(cpp, "xiangqi_step")["error"] == "轮到你了"


def test_move_and_capture_events(cpp):
    cpp("xiangqi_new", human=RED, level=0)
    ev = cpp("xiangqi_play", move=[7, 7, 4, 7])["event"]  # 炮二平五
    assert ev == {"type": "move", "move": [7, 7, 4, 7], "piece": "C", "captured": "", "check": False}
    st = cpp("xiangqi_step")["state"]
    assert st["to_move"] == "red" and st["move_count"] == 2 and st["can_undo"]


def test_checkmate(cpp):
    # rook on y=1 seals the second rank, the other rook mates along the back rank
    cpp("xiangqi_setup", fen="4k4/R8/9/9/9/9/9/9/8R/3K5 w", human=RED, level=0)
    reply = cpp("xiangqi_play", move=[8, 8, 8, 0])
    assert reply["event"]["check"]
    st = reply["state"]
    assert st["phase"] == "over" and st["winner"] == "red" and st["reason"] == "将死" and st["human_won"]
    assert st["in_check"]  # the mated king still shows as in check
    assert raw(cpp, "xiangqi_undo")["error"] == "对局已结束"


def test_stalemate_loses(cpp):
    # black's king has no safe square and isn't in check: 困毙
    cpp("xiangqi_setup", fen="4k4/9/4P4/9/9/R4R3/9/9/9/4K4 w", human=RED, level=0)
    st = cpp("xiangqi_play", move=[0, 5, 3, 5])["state"]
    assert st["winner"] == "red" and st["reason"] == "困毙"


def test_perpetual_check_loses(cpp):
    # red checks on every move while black's king steps back and forth
    cycle = [[8, 1, 8, 0], [4, 0, 4, 1], [8, 0, 8, 1], [4, 1, 4, 0]]
    st = cpp("xiangqi_setup", fen="4k4/8R/9/9/9/9/9/9/9/3K5 w", moves=cycle * 2, human=RED, level=0)["state"]
    assert st["winner"] == "black" and st["reason"] == "长将" and not st["human_won"]


def test_threefold_repetition_draws(cpp):
    cycle = [[3, 9, 3, 8], [4, 0, 4, 1], [3, 8, 3, 9], [4, 1, 4, 0]]
    st = cpp("xiangqi_setup", fen="4k4/9/9/9/9/R8/9/9/9/3K5 w", moves=cycle * 2, human=RED, level=0)["state"]
    assert st["winner"] == "draw" and st["reason"] == "三次重复局面"


def test_twice_is_not_yet_a_draw(cpp):
    cycle = [[3, 9, 3, 8], [4, 0, 4, 1], [3, 8, 3, 9], [4, 1, 4, 0]]
    st = cpp("xiangqi_setup", fen="4k4/9/9/9/9/R8/9/9/9/3K5 w", moves=cycle, human=RED, level=0)["state"]
    assert st["phase"] == "playing"


def test_no_attackers_left_draws(cpp):
    # the red king takes black's last rook; nobody can attack any more
    cpp("xiangqi_setup", fen="3k5/9/9/9/9/9/9/9/4r4/4K4 w", human=RED, level=0)
    st = cpp("xiangqi_play", move=[4, 9, 4, 8])["state"]
    assert st["winner"] == "draw" and st["reason"] == "双方都无进攻子力"


def test_sixty_moves_without_capture_draws(cpp):
    # both sides shuffle a rook between two squares the other never repeats with:
    # four different rook squares per side so no position comes back three times
    red = [[0, 9, 0, 8], [0, 8, 0, 7], [0, 7, 0, 6], [0, 6, 0, 9]]
    black = [[8, 0, 8, 1], [8, 1, 8, 2], [8, 2, 8, 3], [8, 3, 8, 0]]
    king_r = [[3, 9, 3, 8], [3, 8, 3, 9]]
    king_b = [[5, 0, 5, 1], [5, 1, 5, 0]]
    moves = []
    for i in range(60):  # 120 plies, mixing rook and king moves to avoid repeats
        moves.append(red[i % 4] if (i // 4) % 2 == 0 else king_r[i % 2])
        moves.append(black[i % 4] if (i // 4) % 2 == 0 else king_b[i % 2])
    reply = raw(cpp, "xiangqi_setup", fen="5k2r/9/9/9/9/9/9/9/9/R2K5 w", moves=moves, human=RED, level=0)
    st = reply["state"]
    assert st["winner"] == "draw", (reply.get("error"), st["reason"], st["move_count"])
    assert st["reason"] in ("60 回合未吃子", "三次重复局面")


def test_undo_and_hint(cpp):
    cpp("xiangqi_new", human=BLACK, level=1, seed=2)
    assert raw(cpp, "xiangqi_undo")["error"] == "没有可以悔的棋"
    first = cpp("xiangqi_step")["event"]["move"]  # the AI (red) opens
    hint = cpp("xiangqi_hint")
    assert hint["state"]["assisted"] and hint["hint"] in hint["state"]["legal"]
    cpp("xiangqi_play", move=hint["hint"])
    cpp("xiangqi_step")
    reply = cpp("xiangqi_undo")  # my move and the AI's reply; the AI's opener stays
    assert len(reply["event"]["removed"]) == 2
    st = reply["state"]
    assert st["move_count"] == 1 and st["last"] == first and st["to_move"] == "black"


@pytest.mark.parametrize("level", [0, 1, 2])
def test_ai_takes_a_mate_in_one(cpp, level):
    cpp("xiangqi_setup", fen="4k4/R8/9/9/9/9/9/9/8R/3K5 w", human=BLACK, level=level)
    st = cpp("xiangqi_step")["state"]
    assert st["winner"] == "red" and st["reason"] == "将死"


def test_normal_beats_easy(cpp):
    """普通 beats 简单 most of the time, even with black."""
    wins = 0
    for seed in range(6):
        st = cpp("xiangqi_new", human=RED, level=0, seed=seed)["state"]
        while st["phase"] == "playing" and st["move_count"] < 300:
            st = cpp("xiangqi_debug_step", level=0 if st["to_move"] == "red" else 1)["state"]
        wins += st["winner"] == "black"
    assert wins >= 5, wins
