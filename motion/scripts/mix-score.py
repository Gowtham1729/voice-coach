#!/usr/bin/env python3
"""Lay Calculated Grace under the finished read.

The track is louder than the voice and returns to full level halfway through
the privacy lines. This keeps the groove, ducks it while someone is speaking,
holds it down through the privacy promise, and fades it out with the end card.
"""

import subprocess
from pathlib import Path

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parents[1]
VOICE = ROOT / "public/promo-2026-10-04/vo/ichido-promo.wav"
MUSIC = ROOT / "public/promo-2026-10-04/music/calculated-grace.mp3"
OUT = ROOT / "public/promo-2026-10-04/vo/ichido-promo-mix.wav"
FILM_SECONDS = 63.232

# Picture: privacy promise, then the end card.
PRIVACY = (42.93, 55.83)


def load(path: Path, channels: int) -> np.ndarray:
    raw = subprocess.check_output(
        [
            "/opt/homebrew/bin/ffmpeg",
            "-v",
            "error",
            "-i",
            str(path),
            "-f",
            "f32le",
            "-ac",
            str(channels),
            "-ar",
            str(SR),
            "-",
        ]
    )
    audio = np.frombuffer(raw, dtype=np.float32).reshape(-1, channels)
    return np.array(audio, copy=True)


def speech_gain(voice: np.ndarray) -> np.ndarray:
    """1 while the bed can sit up, about 0.4 while words are present."""
    mono = voice[:, 0]
    hop = int(0.02 * SR)
    count = len(mono) // hop
    window = mono[: count * hop].reshape(count, hop)
    rms = np.sqrt(np.mean(window**2, axis=1))
    # Open the bed only in real pauses. A light breath should not pump it.
    target = np.where(rms > 0.02, 0.40, 1.0).astype(np.float64)
    gain = np.empty(count, dtype=np.float64)
    level = 1.0
    attack = np.exp(-1 / (0.06 / 0.02))
    release = np.exp(-1 / (0.55 / 0.02))
    for i, want in enumerate(target):
        coeff = attack if want < level else release
        level = want + (level - want) * coeff
        gain[i] = level
    full = np.repeat(gain, hop)
    if len(full) < len(mono):
        full = np.pad(full, (0, len(mono) - len(full)), constant_values=full[-1])
    return full[: len(mono)]


def privacy_gain(n: np.ndarray) -> np.ndarray:
    t = np.arange(len(n)) / SR
    start, end = PRIVACY
    dip = np.ones(len(t), dtype=np.float64)
    # Another 7 dB down, ramped so the return lands with the end card.
    low = 10 ** (-7 / 20)
    enter = np.clip((t - (start - 0.6)) / 0.8, 0, 1)
    leave = np.clip((t - end) / 0.7, 0, 1)
    dip *= 1 - (1 - low) * enter * (1 - leave)
    return dip


def fade(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    curve = np.ones(n, dtype=np.float64)
    curve *= np.clip(t / 0.4, 0, 1)
    # The closing line ends near 62.7. Ease the bed out with the picture.
    curve *= 1 - np.clip((t - 62.35) / 0.88, 0, 1) ** 1.3
    return curve


def main() -> None:
    voice = load(VOICE, 1)
    music = load(MUSIC, 2)
    n = int(FILM_SECONDS * SR)
    voice = voice[:n, 0]
    if len(voice) < n:
        voice = np.pad(voice, (0, n - len(voice)))
    music = music[:n]
    if len(music) < n:
        music = np.pad(music, ((0, n - len(music)), (0, 0)))

    # The track measures about -12 LUFS against a -23 LUFS read.
    bed = 10 ** (-11 / 20)
    env = speech_gain(voice.reshape(-1, 1)) * privacy_gain(np.arange(n)) * fade(n) * bed
    bed_audio = music * env[:, None]
    mix = bed_audio.copy()
    mix[:, 0] += voice
    mix[:, 1] += voice

    peak = float(np.max(np.abs(mix)))
    if peak > 0.89:
        mix *= 0.89 / peak

    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
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
            "2",
            "-i",
            "pipe:0",
            "-c:a",
            "pcm_s16le",
            str(OUT),
        ],
        input=np.ascontiguousarray(mix, dtype=np.float32).tobytes(),
        check=True,
    )
    hop = int(0.02 * SR)
    count = n // hop
    vrms = np.sqrt(np.mean(voice[: count * hop].reshape(count, hop) ** 2, axis=1))
    mrms = np.sqrt(np.mean(bed_audio[: count * hop, 0].reshape(count, hop) ** 2, axis=1))
    spoken = vrms > 0.025
    quiet = ~spoken
    privacy = (np.arange(count) * hop / SR >= PRIVACY[0]) & (np.arange(count) * hop / SR < PRIVACY[1])
    print(f"peak {float(np.max(np.abs(mix))):.3f}")
    print(f"voice while speaking {20 * np.log10(np.median(vrms[spoken]) + 1e-9):.1f} dBFS")
    print(f"bed under speech    {20 * np.log10(np.median(mrms[spoken]) + 1e-9):.1f} dBFS")
    print(f"bed in pauses       {20 * np.log10(np.median(mrms[quiet]) + 1e-9):.1f} dBFS")
    print(f"bed in privacy      {20 * np.log10(np.median(mrms[privacy]) + 1e-9):.1f} dBFS")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
