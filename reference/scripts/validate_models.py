"""Sanity-check the three DouZero ONNX models with the original DouZero env.

ONNX agents should crush random agents in both roles; ONNX vs ONNX should
land near the landlord win rate reported for DouZero WP self-play (~40-45%).
"""
import random
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort

from douzero_core.env.env import get_obs, deck
from douzero_core.env.game import GameEnv

MODELS_DIR = Path(__file__).resolve().parents[2] / "game" / "models"
POSITIONS = ["landlord", "landlord_up", "landlord_down"]


class OnnxAgent:
    def __init__(self, position):
        self.sess = ort.InferenceSession(str(MODELS_DIR / f"{position}.onnx"),
                                         providers=["CPUExecutionProvider"])

    def act(self, infoset):
        if len(infoset.legal_actions) == 1:
            return infoset.legal_actions[0]
        obs = get_obs(infoset)
        values = self.sess.run(["values"], {"z": obs["z_batch"], "x": obs["x_batch"]})[0]
        return infoset.legal_actions[int(np.argmax(values[:, 0]))]


class RandomAgent:
    def act(self, infoset):
        return random.choice(infoset.legal_actions)


def play(players, n_games, seed):
    rng = np.random.default_rng(seed)
    env = GameEnv(players)
    landlord_wins = 0
    for _ in range(n_games):
        d = deck.copy()
        rng.shuffle(d)
        data = {"landlord": sorted(d[:20]), "landlord_up": sorted(d[20:37]),
                "landlord_down": sorted(d[37:54]), "three_landlord_cards": sorted(d[17:20])}
        env.card_play_init(data)
        while not env.game_over:
            env.step()
        landlord_wins += env.get_winner() == "landlord"
        env.reset()
    return landlord_wins / n_games


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    random.seed(0)
    onnx = {p: OnnxAgent(p) for p in POSITIONS}
    rand = {p: RandomAgent() for p in POSITIONS}
    setups = {
        "ONNX 地主 vs 随机农民": {"landlord": onnx["landlord"], "landlord_up": rand["landlord_up"], "landlord_down": rand["landlord_down"]},
        "随机地主 vs ONNX 农民": {"landlord": rand["landlord"], "landlord_up": onnx["landlord_up"], "landlord_down": onnx["landlord_down"]},
        "ONNX vs ONNX (自对弈)": onnx,
        "随机 vs 随机 (基线)": rand,
    }
    for name, players in setups.items():
        t = time.time()
        wp = play(players, n, seed=42)
        print(f"{name:24s} 地主胜率 {wp:6.1%}  ({n} 局, {time.time() - t:.1f}s)")


if __name__ == "__main__":
    main()
