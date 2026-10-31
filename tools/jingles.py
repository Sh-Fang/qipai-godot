"""Makes the 五子棋/象棋 result jingles in game/audio/guofeng/: plucked-string phrases on
the pentatonic scale, synthesised here (Karplus-Strong), so they're ours to ship.

    uv run --with numpy python tools/jingles.py <path to ffmpeg>

win: a quick rising run up the scale, landing on a chord. lose: a slow fall to the low
note. draw: three notes that settle back in the middle.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "game/audio/guofeng"
PEAK_DB = -12.0  # with the music ducked under it (Sfx.duck), clear but not loud

D4 = 293.66
SCALE = [D4 * 2 ** (s / 12) for s in (0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24)]  # 宫商角徵羽


def pluck(freq: float, dur: float, bright: float = 0.6, seed: int = 0, ring: float = 5.0) -> np.ndarray:
    """One plucked string: a noise burst through a damped delay line. `ring`: seconds
    for the loop gain alone to bring it down 60 dB, the same for every pitch (the
    smoothing takes it down faster, the higher the note)."""
    rng = np.random.default_rng(seed)
    period = SR / freq
    n = int(period)
    frac = period - n
    buf = rng.uniform(-1, 1, n)
    buf = np.convolve(buf, [bright, 1 - bright], "same")  # softer attack than raw noise
    out = np.empty(int(dur * SR))
    decay = 10 ** (-3 / (ring * freq))  # per trip round the line
    idx = 0
    prev = 0.0
    for i in range(len(out)):
        a = buf[idx]
        b = buf[(idx + 1) % n]
        v = decay * ((1 - frac) * a + frac * b + prev) / 2  # low-pass + fractional delay
        prev = a
        buf[idx] = v
        out[i] = a
        idx = (idx + 1) % n
    return out


def phrase(notes: list[tuple[float, int, float]], length: float) -> np.ndarray:
    """notes: (start seconds, scale step, gain)."""
    mix = np.zeros(int(length * SR))
    for i, (t, step, gain) in enumerate(notes):
        tone = pluck(SCALE[step], length - t, seed=i) * gain
        start = int(t * SR)
        mix[start:start + len(tone)] += tone[:len(mix) - start]
    return mix


def hall(x: np.ndarray) -> np.ndarray:
    """A little room, so the notes don't sound dry."""
    rng = np.random.default_rng(7)
    ir = rng.normal(0, 1, int(1.2 * SR)) * np.exp(-np.arange(int(1.2 * SR)) / SR * 4.5)
    ir[0] = 0
    wet = np.convolve(x, ir)[:len(x)] * 0.012
    return x + wet


def finish(x: np.ndarray) -> np.ndarray:
    x = hall(x)
    fade = int(0.4 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.abs(x).max() * 10 ** (PEAK_DB / 20)


def write(name: str, x: np.ndarray, ffmpeg: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1",
                    "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(OUT / f"{name}.ogg")],
                   input=pcm, check=True)


def main() -> None:
    ffmpeg = sys.argv[1] if len(sys.argv) > 1 else "ffmpeg"
    run = [(i * 0.085, step, 0.55 + i * 0.05) for i, step in enumerate([0, 1, 2, 3, 4, 5, 6, 7])]
    chord = [(0.85, 3, 0.7), (0.87, 5, 0.8), (0.89, 8, 0.9)]
    write("win", finish(phrase(run + chord, 3.2)), ffmpeg)
    write("lose", finish(phrase([(0.0, 6, 0.9), (0.38, 4, 0.85), (0.8, 2, 0.8), (1.3, 0, 0.9)], 3.2)), ffmpeg)
    write("draw", finish(phrase([(0.0, 4, 0.85), (0.3, 3, 0.8), (0.65, 5, 0.9)], 2.6)), ffmpeg)


if __name__ == "__main__":
    main()
