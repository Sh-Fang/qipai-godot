"""Makes the 五子棋/象棋 table sounds in game/audio/guofeng/, synthesised from damped
partials (modal synthesis), so they're ours to ship.

    uv run --with numpy python tools/board_sounds.py <path to ffmpeg>

wood-1..3: a 象棋 piece set down; wood-capture: one piece knocked by another.
stone-1..3: a 五子棋 stone snapped onto the board. drum: 将军. gong: 绝杀, gong-soft: a
象棋 game starts. bell: five in a row. muyu: a 五子棋 game starts.
"""

import sys

import numpy as np

from jingles import SR, hall, write

T = np.arange(int(3.5 * SR)) / SR


def modes(parts: list[tuple[float, float, float]], dur: float, detune: float = 0.0,
          seed: int = 0) -> np.ndarray:
    """Damped sines: (frequency, gain, seconds to fall 60 dB)."""
    rng = np.random.default_rng(seed)
    t = T[:int(dur * SR)]
    out = np.zeros(len(t))
    for f, g, t60 in parts:
        f *= 1 + detune * rng.uniform(-1, 1)
        out += g * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * 10 ** (-3 * t / t60)
    return out


def click(dur: float, cutoff: float, gain: float, seed: int = 0) -> np.ndarray:
    """A short burst of noise, low-passed to `cutoff` Hz: the moment of contact."""
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, int(dur * SR))
    a = np.exp(-2 * np.pi * cutoff / SR)
    for i in range(1, len(n)):
        n[i] = (1 - a) * n[i] + a * n[i - 1]
    return gain * n * np.linspace(1, 0, len(n)) ** 2


def mix(length: float, *parts: tuple[float, np.ndarray]) -> np.ndarray:
    """(start seconds, sound) laid onto one track."""
    out = np.zeros(int(length * SR))
    for t, x in parts:
        s = int(t * SR)
        out[s:s + len(x)] += x[:len(out) - s]
    return out


def level(x: np.ndarray, peak_db: float, room: float = 0.0) -> np.ndarray:
    if room:
        x = x + (hall(x) - x) * room
    fade = min(len(x) // 4, int(0.05 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.abs(x).max() * 10 ** (peak_db / 20)


def wood(seed: int, hard: float = 1.0) -> np.ndarray:
    """A hard-wood disc on a wooden board: the disc's own knock plus the board's thump."""
    piece = modes([(1150, 1.0, 0.05), (2480, 0.6, 0.035), (3900, 0.35 * hard, 0.02)], 0.25, 0.06, seed)
    board = modes([(190, 0.9, 0.16), (420, 0.5, 0.09)], 0.3, 0.05, seed + 10)
    return mix(0.3, (0, piece), (0, board), (0, click(0.006, 5000 * hard, 1.2, seed)))


def stone(seed: int) -> np.ndarray:
    """A glass stone snapped down: bright and short, on a thinner board."""
    tick = modes([(2700, 1.0, 0.03), (4300, 0.7, 0.02), (6100, 0.4, 0.012)], 0.12, 0.05, seed)
    board = modes([(260, 0.6, 0.1), (610, 0.35, 0.06)], 0.2, 0.05, seed + 10)
    return mix(0.22, (0, tick), (0, board), (0, click(0.004, 9000, 1.4, seed)))


def gong(base: float, dur: float) -> np.ndarray:
    """Inharmonic partials that ring for seconds, with a slight rise in pitch (大锣)."""
    t = T[:int(dur * SR)]
    out = np.zeros(len(t))
    for ratio, g, t60 in [(1, 1.0, 3.0), (1.52, 0.7, 2.4), (2.02, 0.5, 2.0), (2.74, 0.4, 1.4),
                          (3.4, 0.3, 1.0), (4.3, 0.2, 0.7), (5.1, 0.15, 0.5)]:
        f = base * ratio * (1 + 0.025 * (1 - np.exp(-t * 3)))
        out += g * np.sin(2 * np.pi * np.cumsum(f) / SR) * 10 ** (-3 * t / t60)
    swell = 1 - np.exp(-t * 60)  # struck with a soft beater: no hard click
    return out * swell + mix(dur, (0, click(0.03, 1500, 0.6)))


def drum(dur: float = 0.7) -> np.ndarray:
    """A big drum: a low membrane that drops in pitch as it settles."""
    t = T[:int(dur * SR)]
    f = 75 + 70 * np.exp(-t * 18)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * 10 ** (-3 * t / 0.55)
    skin = modes([(180, 0.4, 0.2), (290, 0.25, 0.12)], dur, seed=3)
    return body + skin + mix(dur, (0, click(0.02, 1200, 0.8, 4)))


def main() -> None:
    ffmpeg = sys.argv[1] if len(sys.argv) > 1 else "ffmpeg"
    for i in range(3):
        write(f"wood-{i + 1}", level(wood(i, 0.8 + i * 0.1), -6.0), ffmpeg)
        write(f"stone-{i + 1}", level(stone(i), -6.0), ffmpeg)
    write("wood-capture", level(mix(0.35, (0, wood(7, 1.3)), (0.018, wood(8, 1.4) * 0.8)), -3.0), ffmpeg)
    write("drum", level(drum(), -6.0, room=0.6), ffmpeg)
    write("gong", level(gong(220, 3.2), -8.0, room=0.8), ffmpeg)
    write("gong-soft", level(gong(260, 2.2), -16.0, room=0.8), ffmpeg)
    bell = modes([(1046, 1.0, 2.5), (1046 * 2.76, 0.45, 1.2), (1046 * 5.4, 0.2, 0.6), (1046 * 8.93, 0.08, 0.3)], 2.6)
    write("bell", level(bell + mix(2.6, (0, click(0.004, 8000, 0.5))), -12.0, room=0.8), ffmpeg)
    muyu = modes([(720, 1.0, 0.11), (1690, 0.35, 0.05)], 0.3) + mix(0.3, (0, click(0.004, 4000, 0.8)))
    write("muyu", level(mix(0.6, (0, muyu), (0.22, muyu * 0.7)), -12.0, room=0.5), ffmpeg)


if __name__ == "__main__":
    main()
