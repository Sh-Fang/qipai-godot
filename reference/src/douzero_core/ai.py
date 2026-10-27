"""ONNX policies for the three DouZero positions."""
import os
from pathlib import Path

import numpy as np
import onnxruntime as ort

from .env.env import get_obs

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

    def act(self, infoset) -> list[int]:
        if len(infoset.legal_actions) == 1:
            return infoset.legal_actions[0]
        return infoset.legal_actions[int(np.argmax(self.evaluate(infoset)))]
