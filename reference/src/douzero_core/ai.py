"""ONNX policies for the three DouZero positions.

A 四带二 / 四带两对 is only played over another move when it scores clearly higher
(by FOUR_WITH_TWO_MARGIN): otherwise the model happily breaks up a bomb just to
shed six cards.
"""
import os
from pathlib import Path

import numpy as np
import onnxruntime as ort

from .env import move_detector as md
from .env.env import get_obs

FOUR_WITH_TWO_MARGIN = 0.05

# 叫地主 model column per DouZero rank (3..A, 2, 小王, 大王)
BID_RANK_COLUMN = {3: 0, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6, 10: 7, 11: 8, 12: 9, 13: 10, 14: 11,
                   17: 12, 20: 13, 30: 14}

POSITIONS = ("landlord", "landlord_up", "landlord_down")
DEFAULT_MODELS_DIR = Path(os.environ.get(
    "DOUZERO_MODELS", Path(__file__).resolve().parents[3] / "game" / "models"))


class DouZeroPolicy:
    def __init__(self, models_dir: Path = DEFAULT_MODELS_DIR):
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        self.sessions = {
            p: ort.InferenceSession(str(Path(models_dir) / f"{p}.onnx"), opts,
                                    providers=["CPUExecutionProvider"])
            for p in POSITIONS
        }
        self.bid_session = ort.InferenceSession(str(Path(models_dir) / "bid.onnx"), opts,
                                                providers=["CPUExecutionProvider"])

    def bid_score(self, ranks) -> float:
        """叫地主 score of a 17-card hand (see scripts/export_bid_model.py); higher = stronger."""
        x = np.zeros((4, 15), np.float32)
        for rank in set(ranks):
            x[:ranks.count(rank), BID_RANK_COLUMN[rank]] = 1
        return float(self.bid_session.run(["score"], {"x": x.reshape(1, 60)})[0][0, 0])

    def evaluate(self, infoset) -> np.ndarray:
        """Q-value per legal action of the acting position."""
        obs = get_obs(infoset)
        out = self.sessions[infoset.player_position].run(
            ["values"], {"z": obs["z_batch"], "x": obs["x_batch"]})[0]
        return out[:, 0]

    def ranked(self, infoset) -> list[list[int]]:
        """Legal actions from best to worst (model value, 四带二 handicapped)."""
        legal = infoset.legal_actions
        if len(legal) <= 1:
            return list(legal)
        values = self.evaluate(infoset).astype(np.float32)
        for i, move in enumerate(legal):
            if md.get_move_type(move)["type"] in (md.TYPE_13_4_2, md.TYPE_14_4_22):
                values[i] -= np.float32(FOUR_WITH_TWO_MARGIN)
        order = sorted(range(len(legal)), key=lambda i: -values[i])  # stable: ties keep order
        return [legal[i] for i in order]

    def act(self, infoset) -> list[int]:
        return self.ranked(infoset)[0]
