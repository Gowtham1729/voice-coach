#!/usr/bin/env python3
"""Smooth the finished ElevenLabs read and write the film's voice track.

The source is a hand-assembled read: a few edit clicks sit in the gaps, and
some phrase starts were cut in at full level. This removes the isolated clicks,
eases only the starts and ends that hit at full level, and brings each phrase
to one level. It does not change timing or wording.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parents[1] / "public/promo-2026-10-04/vo/ichido-promo.wav"


def load(source: Path) -> np.ndarray:
    raw = subprocess.check_output(
        [
            "/opt/homebrew/bin/ffmpeg",
            "-v",
            "error",
            "-i",
            str(source),
            "-f",
            "f32le",
            "-ac",
            "1",
            "-ar",
            str(SR),
            "-",
        ]
    )
    return np.frombuffer(raw, dtype=np.float32).copy()


def declick(x: np.ndarray) -> int:
    """Drop impulse bursts that sit in a gap, and ease a click that opens a word.

    A consonant inside a word has loud sound on both sides, so it is left alone.
    """
    block = int(0.005 * SR)
    count = len(x) // block
    shaped = x[: count * block].reshape(count, block)
    peak = np.max(np.abs(shaped), axis=1)
    rms = np.sqrt(np.mean(shaped**2, axis=1))
    spike = peak > 0.22
    removed = 0
    i = 1
    while i < count - 1:
        if not spike[i]:
            i += 1
            continue
        j = i
        while j < count and (spike[j] or (j + 1 < count and spike[j + 1] and not spike[j])):
            if not spike[j] and not spike[j + 1]:
                break
            j += 1
            if (j - i) * block > int(0.04 * SR):
                break
        span = (j - i) * block
        before = float(np.sqrt(np.mean(x[max(0, i * block - int(0.015 * SR)) : i * block] ** 2)))
        # Measure just past the burst, so a click's own tail does not look like the next word.
        tail_a = min(len(x), j * block + int(0.012 * SR))
        tail_b = min(len(x), j * block + int(0.045 * SR))
        after = float(np.sqrt(np.mean(x[tail_a:tail_b] ** 2))) if tail_b > tail_a else 1.0
        if span <= int(0.03 * SR) and before < 0.012 and after < 0.02:
            a = max(0, i * block - int(0.004 * SR))
            b = min(len(x), j * block + int(0.012 * SR))
            fade = int(0.003 * SR)
            x[a + fade : b - fade] = 0
            x[a : a + fade] *= np.linspace(1, 0, fade)
            x[b - fade : b] *= np.linspace(0, 1, fade)
            removed += 1
        elif before < 0.02 and after > 0.03 and span <= int(0.02 * SR):
            # A mid-phrase cut that lands at full level, then the word continues.
            recent = x[max(0, i * block - int(0.08 * SR)) : max(0, i * block - int(0.02 * SR))]
            if len(recent) and float(np.sqrt(np.mean(recent**2))) > 0.02:
                a = i * block
                n = int(0.01 * SR)
                x[a : a + n] *= np.linspace(0.15, 1, n)
                removed += 1
        i = max(j, i + 1)
    for i in range(1, count):
        if peak[i - 1] < 0.06 and rms[i - 1] < 0.015 and peak[i] > 0.32:
            a = i * block
            n = int(0.008 * SR)
            x[a : a + n] *= np.linspace(0.2, 1, n)
            removed += 1
    return removed


def phrases(x: np.ndarray) -> list[tuple[int, int]]:
    hop = int(0.005 * SR)
    count = len(x) // hop
    rms = np.sqrt(np.mean(x[: count * hop].reshape(count, hop) ** 2, axis=1))
    voiced = rms > 0.012
    runs: list[tuple[int, int]] = []
    i = 0
    while i < count:
        if not voiced[i]:
            i += 1
            continue
        j = i
        while j < count and voiced[j]:
            j += 1
        # Join gaps shorter than 40 ms so a phrase is not faded word by word.
        if runs and (i - runs[-1][1]) * hop < int(0.04 * SR):
            runs[-1] = (runs[-1][0], j)
        else:
            runs.append((i, j))
        i = j
    return [(a * hop, min(b * hop, len(x))) for a, b in runs]


def ease(x: np.ndarray, a: int, b: int) -> None:
    sl = x[a:b]
    if len(sl) < int(0.05 * SR):
        return
    head = int(0.014 * SR)
    body = sl[head : head * 4]
    if len(body) and np.max(np.abs(sl[:head])) > 2.2 * (np.sqrt(np.mean(body**2)) + 1e-6):
        sl[:head] *= np.linspace(0, 1, head) ** 2
    tail = int(0.012 * SR)
    prev = sl[-(tail * 4) : -tail]
    if len(prev) and np.max(np.abs(sl[-tail:])) > 2.2 * (np.sqrt(np.mean(prev**2)) + 1e-6):
        sl[-tail:] *= np.linspace(1, 0, tail) ** 2
    x[a:b] = sl


def level(x: np.ndarray, a: int, b: int, target: float = 0.082) -> None:
    sl = x[a:b]
    if b - a < int(0.35 * SR):
        return
    rms = float(np.sqrt(np.mean(sl**2)))
    if rms < 1e-4:
        return
    gain = float(np.clip(target / rms, 0.55, 1.7))
    peak = float(np.max(np.abs(sl)))
    if peak * gain > 0.9:
        gain = 0.9 / peak
    x[a:b] *= gain


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: finish-vo.py <read.wav>")
    x = load(Path(sys.argv[1]))
    clicks = declick(x)
    for a, b in phrases(x):
        ease(x, a, b)
        level(x, a, b)
    peak = float(np.max(np.abs(x)))
    if peak > 0.92:
        x *= 0.92 / peak
    OUT.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [
            "/opt/homebrew/bin/ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "f32le",
            "-ar",
            str(SR),
            "-ac",
            "1",
            "-i",
            "pipe:0",
            "-ac",
            "2",
            "-c:a",
            "pcm_s16le",
            str(OUT),
        ],
        input=x.astype(np.float32).tobytes(),
        check=True,
    )
    print(f"clicks softened: {clicks}")
    print(f"wrote {OUT} ({len(x) / SR:.3f}s, peak {float(np.max(np.abs(x))):.3f})")
    if proc.returncode != 0:
        sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
