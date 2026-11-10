"""The 3D Third Person template's bullet impact sounds, synthesised here (nothing sampled, nothing third-party).

    uv run --with numpy --with scipy python tools/audio/impact_sounds.py --ffmpeg <pinned ffmpeg> \
        [--out templates/3d-third-person/game/assets/audio/impacts] [--wav-dir <folder>]

Three surfaces, three seeded variants each, written as `impact_<surface>_<n>.ogg`: `default` (a dry hit on
stone and dust), `wood` (a knock and a splinter's tick) and `metal` (a ping and a short ricochet whine). The seed
comes from the file's name, so the same command writes the same files. Each is peak-normalised to -6 dBFS: the
level in the game is the `volume_db` of the surface's `Sound` node, not the file's.
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44100
PEAK_DB = -6.0
VARIANTS = 3


def n_of(seconds: float) -> int:
    return round(seconds * RATE)


def decay(n: int, seconds: float) -> np.ndarray:
    """An exponential fall of 60 dB over `seconds`."""
    return np.exp(-6.9 * (np.arange(n) / RATE) / seconds)


def noise(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def filt(x: np.ndarray, kind: str, low: float, high: float | None = None) -> np.ndarray:
    nyq = RATE / 2
    if kind == "band":
        sos = signal.butter(2, [low / nyq, min(high, nyq * 0.95) / nyq], btype="band", output="sos")
    else:
        sos = signal.butter(2, min(low, nyq * 0.95) / nyq, btype=kind, output="sos")
    return signal.sosfilt(sos, x)


def tone(freq: float | np.ndarray, n: int) -> np.ndarray:
    f = np.full(n, float(freq)) if np.isscalar(freq) else freq
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def jitter(rng: np.random.Generator, value: float, share: float) -> float:
    return value * (1.0 + rng.uniform(-share, share))


def default(rng: np.random.Generator) -> np.ndarray:
    """A round into stone: a dry smack, a puff of grit and a short low thud."""
    n = n_of(0.22)
    smack = filt(noise(rng, n), "band", jitter(rng, 1800, 0.2), 5200) * decay(n, 0.03)
    thud = tone(np.geomspace(jitter(rng, 190, 0.15), 70, n), n) * decay(n, 0.045)
    grit = np.zeros(n)
    for _ in range(5):
        at = int(rng.exponential(0.02) * RATE)
        if at < n - 200:
            grit[at : at + 200] += filt(noise(rng, 200), "high", 3500) * decay(200, 0.006)
    return smack * 0.6 + thud * 1.5 + grit * 0.4


def wood(rng: np.random.Generator) -> np.ndarray:
    """A round into a crate: a hollow knock (three inharmonic partials) and a splinter's tick."""
    n = n_of(0.26)
    base = jitter(rng, 420, 0.15)
    knock = sum(
        gain * tone(base * ratio, n) * decay(n, fall)
        for ratio, gain, fall in ((1.0, 1.0, 0.07), (2.31, 0.5, 0.045), (3.87, 0.25, 0.03))
    )
    tick = filt(noise(rng, n), "band", 1100, 3200) * decay(n, 0.012)
    crack = filt(noise(rng, n), "high", 4200) * decay(n, 0.004)
    return knock * 0.9 + tick * 0.8 + crack * 0.35


def metal(rng: np.random.Generator) -> np.ndarray:
    """A round into sheet metal: a click, a ringing ping and a ricochet's falling whine."""
    n = n_of(0.45)
    click = filt(noise(rng, n), "high", 3000) * decay(n, 0.005)
    base = jitter(rng, 1750, 0.2)
    ping = sum(
        gain * tone(base * ratio, n) * decay(n, fall)
        for ratio, gain, fall in ((1.0, 1.0, 0.16), (1.58, 0.6, 0.11), (2.4, 0.4, 0.07))
    )
    whine = tone(np.geomspace(jitter(rng, 5200, 0.12), 1900, n), n) * decay(n, 0.07) * 0.18
    return click * 0.8 + ping * 0.55 + whine


RECIPES = {"default": default, "wood": wood, "metal": metal}


def render(name: str, recipe) -> np.ndarray:
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    x = recipe(rng)
    fade_in, fade_out = n_of(0.0005), n_of(0.02)
    x[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    x[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    return x * 10 ** (PEAK_DB / 20) / max(float(np.max(np.abs(x))), 1e-9)


def write_wav(path: Path, x: np.ndarray) -> None:
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument(
        "--out", default="templates/3d-third-person/game/assets/audio/impacts", type=Path
    )
    parser.add_argument("--wav-dir", type=Path, help="also keep the 16-bit WAVs here")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for surface, recipe in RECIPES.items():
            for variant in range(1, VARIANTS + 1):
                name = f"impact_{surface}_{variant}"
                x = render(name, recipe)
                wav = Path(tmp) / f"{name}.wav"
                write_wav(wav, x)
                if args.wav_dir:
                    args.wav_dir.mkdir(parents=True, exist_ok=True)
                    write_wav(args.wav_dir / f"{name}.wav", x)
                ogg = args.out / f"{name}.ogg"
                subprocess.run(
                    [args.ffmpeg, "-y", "-loglevel", "error", "-i", str(wav)]
                    + ["-c:a", "libvorbis", "-q:a", "5", str(ogg)],
                    check=True,
                )
                print(f"{ogg.name}: {len(x) / RATE:.2f} s")


if __name__ == "__main__":
    main()
