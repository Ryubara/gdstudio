"""Sound effects for the templates, generated with ElevenLabs Sound Effects and cut, levelled and checked here.

    ELEVENLABS_API_KEY=... uv run --with numpy python tools/audio/sfx.py --cache <scratch folder> <command> \
        [--only name,...] [--ffmpeg <pinned ffmpeg>]

Commands (`docs/gamedev/audio/sound-effects.md` explains each):

- `credits`: read the plan and the balance (`GET /v1/user/subscription`).
- `plan`: list every request with its cost and send nothing; refuses over the budget.
- `generate`: `plan`, then request each take not yet in the cache (once; the raw mp3 stays in `--cache`).
- `encode`: cut, level and encode the cached takes to Ogg Vorbis in each sound's folder, and write its `LICENSE.md`.
- `check`: measure every committed file (length, lead-in, peak, loudness, loop seam); exit 1 on a failure.

Everything about the sounds (prompt, length, folder, targets) is in `template_sounds.json`. The key is read from the
environment only and is never printed or written. The pure parts (cost, budget, names) need no packages; numpy is
imported by `encode` and `check` only.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "template_sounds.json"
SUBSCRIPTION = "https://api.elevenlabs.io/v1/user/subscription"
RATE = 44100
PEAK_DB = -1.0  # no file peaks above this once decoded
ENCODE_PEAK_DB = -1.5  # the level a file is encoded to: Vorbis overshoots a little, so the decoded peak stays under PEAK_DB
LEAD_DB = -34.0  # a sound starts where it first rises within this many dB of its peak
TAIL_DB = -42.0  # and ends where it last stays above this
LEAD_PAD = 0.004  # seconds kept before the first rise
LEAD_MAX = 0.012  # a file's first rise is within this many seconds of its start (check)
FADE_OUT = 0.04


# ---------------------------------------------------------------- the pure parts: names, cost, budget


def load(path: Path = DATA) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def request_cost(data: dict, seconds: float) -> int:
    """Credits one request costs. A sound effect is billed per second of requested length; auto length is never used."""
    if not data["min_seconds"] <= seconds <= data["max_seconds"]:
        raise ValueError(
            f"{seconds} s is outside {data['min_seconds']} to {data['max_seconds']} s"
        )
    return math.ceil(seconds * data["credits_per_second"])


def take_names(sound: dict) -> list[str]:
    return [f"{sound['name']}_t{n}" for n in range(1, sound["takes"] + 1)]


def chosen(data: dict, only: str | None) -> list[dict]:
    names = set(only.split(",")) if only else None
    sounds = [s for s in data["sounds"] if not names or s["name"] in names]
    if names and {s["name"] for s in sounds} != names:
        raise SystemExit(
            f"unknown sound in --only: {sorted(names - {s['name'] for s in sounds})}"
        )
    return sounds


def spent_in_cache(data: dict, cache: Path) -> int:
    """Credits already spent on the takes in the cache: what the API billed (its `character-cost` header) where it
    said, else the cost planned for the request."""
    total = 0
    for request in cache.glob("*.json"):
        info = json.loads(request.read_text(encoding="utf-8"))
        total += int(info.get("billed", info.get("credits", 0)))
    return total


def plan_rows(data: dict, cache: Path, only: str | None = None) -> list[dict]:
    rows = []
    for sound in chosen(data, only):
        for take in take_names(sound):
            cached = (cache / f"{take}.mp3").exists()
            rows.append(
                {
                    "take": take,
                    "sound": sound["name"],
                    "seconds": sound["seconds"],
                    "credits": 0 if cached else request_cost(data, sound["seconds"]),
                    "cached": cached,
                    "prompt": sound["prompt"],
                }
            )
    return rows


def check_budget(data: dict, cache: Path, rows: list[dict]) -> tuple[int, int]:
    """(already spent, to spend now); raises SystemExit when the total would pass the budget."""
    spent, new = spent_in_cache(data, cache), sum(r["credits"] for r in rows)
    if spent + new > data["budget"]:
        raise SystemExit(
            f"over budget: {spent} spent + {new} planned = {spent + new} > {data['budget']}"
        )
    return spent, new


# ---------------------------------------------------------------- the API


def key() -> str:
    value = os.environ.get("ELEVENLABS_API_KEY", "")
    if not value:
        raise SystemExit("ELEVENLABS_API_KEY is not set")
    return value


def subscription() -> dict:
    request = urllib.request.Request(SUBSCRIPTION, headers={"xi-api-key": key()})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def balance() -> dict:
    sub = subscription()
    used, limit = int(sub["character_count"]), int(sub["character_limit"])
    return {
        "tier": sub["tier"],
        "status": sub["status"],
        "used": used,
        "limit": limit,
        "left": limit - used,
    }


def request_take(data: dict, sound: dict) -> tuple[bytes, dict]:
    body = {
        "text": sound["prompt"],
        "duration_seconds": sound["seconds"],  # always explicit: auto length costs more
        "prompt_influence": sound["influence"],
        "model_id": data["model"],
    }
    if sound.get("loop"):
        body["loop"] = True
    request = urllib.request.Request(
        data["endpoint"] + "?output_format=" + data["output_format"],
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key(), "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read(), {
            "body": body,
            "headers": {k.lower(): v for k, v in response.headers.items()},
        }


# ---------------------------------------------------------------- audio: decode, measure, cut, encode


def decode(ffmpeg: str, src: Path):
    import numpy as np

    raw = subprocess.run(
        [
            ffmpeg,
            "-v",
            "error",
            "-i",
            str(src),
            "-f",
            "f32le",
            "-ac",
            "1",
            "-ar",
            str(RATE),
            "-",
        ],
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def loudness(ffmpeg: str, x) -> dict:
    """EBU R128 through ffmpeg: the loudest momentary reading (a sound shorter than the 400 ms window is read
    zero-padded to one second), the integrated loudness and the momentary readings in order."""
    import numpy as np

    if len(x) < RATE:
        x = np.concatenate([x, np.zeros(RATE - len(x))])
    done = subprocess.run(
        [
            ffmpeg,
            "-nostats",
            "-hide_banner",
            "-f",
            "f32le",
            "-ar",
            str(RATE),
            "-ac",
            "1",
            "-i",
            "-",
        ]
        + ["-af", "ebur128=framelog=info", "-f", "null", "-"],
        input=x.astype("<f4").tobytes(),
        capture_output=True,
        check=True,
    )
    text = done.stderr.decode(errors="replace")
    momentary = [float(v) for v in re.findall(r"\bM:\s*(-?\d+\.\d+)", text)]
    summary = re.findall(r"^\s+I:\s+(-?\d+\.\d+) LUFS", text, flags=re.MULTILINE)
    return {
        "momentary": momentary,
        "m_max": max(momentary) if momentary else -120.0,
        "integrated": float(summary[-1]) if summary else -120.0,
    }


def peak_db(x) -> float:
    import numpy as np

    return 20 * math.log10(max(float(np.abs(x).max()), 1e-9))


def trim(x, lead_db: float = LEAD_DB, tail_db: float = TAIL_DB):
    """Cut the lead-in to `LEAD_PAD` before the first rise and the tail after the last sample above `tail_db`."""
    import numpy as np

    peak = float(np.abs(x).max())
    lead = np.nonzero(np.abs(x) > peak * 10 ** (lead_db / 20))[0]
    tail = np.nonzero(np.abs(x) > peak * 10 ** (tail_db / 20))[0]
    return x[max(int(lead[0]) - int(LEAD_PAD * RATE), 0) : int(tail[-1]) + 1]


def fade_out(x, seconds: float = FADE_OUT):
    import numpy as np

    n = min(int(seconds * RATE), len(x))
    x = x.copy()
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def fade_in(x, seconds: float = 0.002):
    import numpy as np

    n = min(int(seconds * RATE), len(x))
    x = x.copy()
    x[:n] *= np.linspace(0.0, 1.0, n)
    return x


def envelope(x, window: float = 0.005):
    import numpy as np

    n = max(int(window * RATE), 1)
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same"))


def onsets(x, gap: float = 0.28) -> list[int]:
    """Sample index where each step starts: the envelope crosses a share of the take's loud level, with a refractory
    gap so one step's ring is not another step."""
    import numpy as np

    env = envelope(x)
    level = float(np.percentile(env, 99))
    threshold = 0.25 * level
    found, i, n = [], 0, len(env)
    while i < n:
        if env[i] > threshold:
            end = min(i + int(gap * RATE), n)
            top = i + int(np.argmax(env[i:end]))
            # walk back from the crest to where the sound began to rise
            start = top
            while start > 0 and env[start] > 0.08 * env[top]:
                start -= 1
            found.append(start)
            i = max(end, top + 1)
        else:
            i += 1
    return found


def cut_steps(x, sound: dict) -> list:
    """Single steps from a longer take: from just before each onset to just before the next, at most `max_seconds`."""
    import numpy as np

    marks = onsets(x)
    pieces = []
    for k, start in enumerate(marks):
        begin = max(start - int(LEAD_PAD * RATE), 0)
        nxt = marks[k + 1] - int(0.02 * RATE) if k + 1 < len(marks) else len(x)
        end = min(nxt, begin + int(sound["max_seconds"] * RATE))
        piece = x[begin:end]
        if len(piece) < sound["min_seconds"] * RATE:
            continue
        piece = trim(piece, tail_db=-36.0)
        if len(piece) >= sound["min_seconds"] * RATE:
            pieces.append(fade_out(fade_in(piece)))
    if not pieces:
        return []
    # a step far under the take's usual step is a scuff or a ring, not a step to cycle
    peaks = [float(np.abs(p).max()) for p in pieces]
    median = float(np.median(peaks))
    return [p for p, pk in zip(pieces, peaks, strict=True) if pk >= 0.4 * median]


def steps_of(x, sound: dict) -> list:
    """The steps of one take. A sound with `highpass_hz` first loses everything under it (the generator's thuds hold
    their energy at 20 to 35 Hz, below what a phone or laptop plays), and one with `tail_db` is trimmed again where
    it falls that far under its peak and faded out over 50 ms, a softer end than the plain cut's."""
    if sound.get("highpass_hz"):
        x = highpass(x, sound["highpass_hz"])
    pieces = cut_steps(x, sound)
    if sound.get("tail_db") is not None:
        pieces = [
            fade_out(fade_in(trim(p, tail_db=sound["tail_db"])), 0.05) for p in pieces
        ]
        pieces = [p for p in pieces if len(p) >= sound["min_seconds"] * RATE]
    return pieces


def make_loop(x, seconds: float):
    """Make a take loop with no seam: the last `seconds` fade into the first (equal power), and are dropped."""
    import numpy as np

    c = int(seconds * RATE)
    t = np.linspace(0.0, math.pi / 2, c)
    head = x[:c] * np.sin(t) + x[len(x) - c :] * np.cos(t)
    return np.concatenate([head, x[c : len(x) - c]])


def flatten(x, seconds: float = 0.8, limit_db: float = 14.0):
    """Take the slow swells out of a bed: divide by the level over `seconds` (a Hann window) and hold it to the
    median, so a gust the prompt did not ask for no longer calls attention. The texture inside a window stays."""
    import numpy as np

    n = int(seconds * RATE)
    window = np.hanning(n)
    window /= window.sum()
    padded = np.concatenate(
        [x[n:0:-1], x, x[-2 : -n - 2 : -1]]
    )  # mirror the ends so they are not read as quiet
    # The window's convolution through the FFT: `np.convolve(..., mode="same")` gives the same envelope (to 1e-15) but
    # works sample by sample, 40 s for a 12 s take against 0.04 s here.
    power = padded * padded
    length = len(power) + n - 1
    size = 1 << (length - 1).bit_length()
    full = np.fft.irfft(np.fft.rfft(power, size) * np.fft.rfft(window, size), size)
    same = full[(n - 1) // 2 : (n - 1) // 2 + len(power)]
    env = np.sqrt(np.maximum(same, 0.0))[n : n + len(x)] + 1e-9
    gain = np.clip(np.median(env) / env, 10 ** (-limit_db / 20), 10 ** (limit_db / 20))
    return x * gain


def highpass(x, hz: float):
    import numpy as np

    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    spectrum[freqs < hz] *= np.clip(freqs[freqs < hz] / hz, 0, 1) ** 2
    return np.fft.irfft(spectrum, len(x))


def level(ffmpeg: str, x, sound: dict):
    """Gain to the sound's target loudness, held under the peak ceiling; returns (samples, gain dB, peak limited)."""
    now = loudness(ffmpeg, x)[
        "m_max" if sound["measure"] == "momentary" else "integrated"
    ]
    gain = sound["target_lufs"] - now
    limited = False
    if peak_db(x) + gain > ENCODE_PEAK_DB:
        gain, limited = ENCODE_PEAK_DB - peak_db(x), True
    return x * 10 ** (gain / 20), gain, limited


def write_ogg(ffmpeg: str, x, ogg: Path) -> None:
    import numpy as np

    ogg.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    cmd = [
        ffmpeg,
        "-y",
        "-v",
        "error",
        "-f",
        "s16le",
        "-ar",
        str(RATE),
        "-ac",
        "1",
        "-i",
        "-",
    ]
    cmd += [
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        "-c:a",
        "libvorbis",
        "-q:a",
        "4",
        str(ogg),
    ]
    subprocess.run(cmd, input=pcm.tobytes(), check=True)


def files_of(sound: dict, root: Path) -> list[Path]:
    return sorted(
        (root / sound["folder"]).glob(f"{sound['prefix']}_*.ogg"),
        key=lambda p: int(p.stem.split("_")[-1]),
    )


# ---------------------------------------------------------------- commands


def cmd_credits(args) -> None:
    b = balance()
    print(
        f"plan {b['tier']} ({b['status']}): {b['used']} of {b['limit']} credits used, {b['left']} left"
    )


def cmd_plan(args) -> None:
    data, cache = load(), args.cache
    rows = plan_rows(data, cache, args.only)
    for r in rows:
        mark = "cached" if r["cached"] else f"{r['credits']:>4} credits"
        print(f"{r['take']:<20} {r['seconds']:>5} s  {mark:<12} {r['prompt'][:70]}")
    spent, new = check_budget(data, cache, rows)
    print(f"spent {spent} + planned {new} = {spent + new} of {data['budget']} credits")


def cmd_generate(args) -> None:
    data, cache = load(), args.cache
    cache.mkdir(parents=True, exist_ok=True)
    cmd_plan(args)
    before = balance()
    print(f"balance before: plan {before['tier']}, {before['left']} credits left")
    for sound in chosen(data, args.only):
        for take in take_names(sound):
            mp3 = cache / f"{take}.mp3"
            if mp3.exists():
                continue
            cost = request_cost(data, sound["seconds"])
            if spent_in_cache(data, cache) + cost > data["budget"]:
                raise SystemExit(
                    f"stopped before {take}: the next request would pass the budget"
                )
            print(f"requesting {take} ({sound['seconds']} s, {cost} credits)")
            try:
                audio, info = request_take(data, sound)
            except urllib.error.HTTPError as error:
                raise SystemExit(
                    f"{take}: HTTP {error.code} {error.read()[:300]!r}"
                ) from None
            mp3.write_bytes(audio)
            billed = info["headers"].get("character-cost")
            if billed is not None:
                info["billed"] = int(billed)
            info.update(
                credits=cost,
                tier=before["tier"],
                date=time.strftime("%Y-%m-%d"),
                model=data["model"],
            )
            (cache / f"{take}.json").write_text(
                json.dumps(info, indent=2), encoding="utf-8"
            )
    time.sleep(5)  # the counter lags the requests
    after = balance()
    print(
        f"balance after: {after['left']} credits left ({before['left'] - after['left']} used by this run)"
    )


def licence_text(
    data: dict, sounds: list[dict], root: Path, cache: Path, ffmpeg: str
) -> dict[str, str]:
    """One LICENSE.md per folder: each file, its prompt, its length, the generator, model, plan and the attribution."""
    out = {}
    for sound in sounds:
        files = files_of(sound, root)
        if not files:
            continue
        info = json.loads(
            (cache / f"{take_names(sound)[0]}.json").read_text(encoding="utf-8")
        )
        lines = [
            "# Sounds generated with ElevenLabs Sound Effects",
            "",
            "- Generator: ElevenLabs Sound Effects (<https://elevenlabs.io/sound-effects>), model",
            f"  `{info['model']}`, plan `{info['tier']}`, generated {info['date']} with `tools/audio/sfx.py` in the",
            "  kit.",
            f"- Licence: {data['licence']}",
            f"- Attribution: {data['attribution']}",
            "  A game's Credits screen names ElevenLabs.",
            "",
            "| File | Prompt | Seconds |",
            "| --- | --- | ---: |",
        ]
        for f in files:
            seconds = len(decode(ffmpeg, f)) / RATE
            lines.append(
                f"| `{f.name}` | {sound['prompt']} (requested {sound['seconds']} s) | {seconds:.2f} |"
            )
        out[sound["folder"]] = "\n".join(lines) + "\n"
    return out


def cmd_encode(args) -> None:
    ffmpeg = args.ffmpeg
    data, cache, root = load(), args.cache, args.root
    sounds = chosen(data, args.only)
    for sound in sounds:
        for old in files_of(sound, root):
            old.unlink()
        pieces = []
        for take in take_names(sound):
            mp3 = cache / f"{take}.mp3"
            if not mp3.exists():
                raise SystemExit(f"{take} is not in the cache; run generate")
            x = decode(ffmpeg, mp3)
            if sound["kind"] == "hit":
                pieces.append(hit(x, sound))
            elif sound["kind"] == "steps":
                pieces.extend(steps_of(x, sound))
            else:
                x = flatten(highpass(x, 40.0), sound["flatten_seconds"])
                pieces.append(make_loop(x, sound["crossfade"]))
        if sound.get("max_files"):
            pieces = (
                pieces[: sound["max_files"]]
                if len(pieces) <= sound["max_files"]
                else spread(pieces, sound)
            )
        for n, x in enumerate(pieces, 1):
            x, gain, limited = level(ffmpeg, x, sound)
            name = f"{sound['prefix']}_{n}.ogg"
            write_ogg(ffmpeg, x, root / sound["folder"] / name)
            print(
                f"{name}: {len(x) / RATE:.3f} s, gain {gain:+.1f} dB{' (peak limited)' if limited else ''}"
            )
    for folder, text in licence_text(data, sounds, root, cache, ffmpeg).items():
        (root / folder / "LICENSE.md").write_text(text, encoding="utf-8")
        print(f"wrote {folder}/LICENSE.md")


def hit(x, sound: dict):
    """One short sound from a take: lead-in cut, the tail where it falls `tail_db` under its peak, held inside the
    sound's length range (a longer one is cut with a fade, a shorter one keeps on into the take's own tail)."""
    whole = trim(x, tail_db=-60.0)
    short = trim(x, tail_db=sound["tail_db"])
    # Vorbis pads the end by up to a frame (about 25 ms) when it encodes, so the cut leaves room for it
    most, least = (
        int((sound["max_seconds"] - 0.03) * RATE),
        int(sound["min_seconds"] * RATE),
    )
    x = whole[: min(max(len(short), least), most)]
    return fade_out(fade_in(x), 0.06)


def spread(pieces: list, sound: dict) -> list:
    """Keep `max_files` steps spread over the takes, so the set is not all from the first take."""
    keep = sound["max_files"]
    idx = sorted({round(i * (len(pieces) - 1) / (keep - 1)) for i in range(keep)})
    return [pieces[i] for i in idx]


def measure_file(ffmpeg: str, f: Path) -> dict:
    import numpy as np

    x = decode(ffmpeg, f)
    peak = float(np.abs(x).max())
    rise = np.nonzero(np.abs(x) > peak * 10 ** (LEAD_DB / 20))[0]
    lo = loudness(ffmpeg, x)
    return {
        "x": x,
        "seconds": len(x) / RATE,
        "peak_db": peak_db(x),
        "lead_ms": 1000.0 * float(rise[0]) / RATE if len(rise) else 0.0,
        "m_max": lo["m_max"],
        "integrated": lo["integrated"],
        "momentary": lo["momentary"],
    }


def seam(x) -> dict:
    """How well a loop wraps: the step from its last sample to its first against a typical step, and the level of the
    last 400 ms against the first 400 ms (dB)."""
    import numpy as np

    steps = np.abs(np.diff(x))
    wrap = abs(float(x[0] - x[-1]))
    n = int(0.4 * RATE)

    def rms(s):
        return math.sqrt(float(np.mean(s * s)) + 1e-18)

    return {
        "wrap_ratio": wrap / (float(np.percentile(steps, 99)) + 1e-12),
        "edge_db": 20 * math.log10(rms(x[-n:]) / rms(x[:n])),
    }


def cmd_check(args) -> None:
    import numpy as np

    data, root, ffmpeg = load(), args.root, args.ffmpeg
    failures = []
    for sound in chosen(data, args.only):
        files = files_of(sound, root)
        if len(files) < sound["min_files"]:
            failures.append(
                f"{sound['name']}: {len(files)} files, at least {sound['min_files']} wanted"
            )
        if not (root / sound["folder"] / "LICENSE.md").exists():
            failures.append(f"{sound['folder']}: no LICENSE.md")
        loud = []
        for f in files:
            m = measure_file(ffmpeg, f)
            reading = m["m_max"] if sound["measure"] == "momentary" else m["integrated"]
            loud.append(reading)
            row = (
                f"{f.name:<22} {m['seconds']:6.3f} s  peak {m['peak_db']:6.2f} dBFS  lead {m['lead_ms']:5.1f} ms  "
                f"M-max {m['m_max']:6.1f}  I {m['integrated']:6.1f} LUFS"
            )
            if not sound["min_seconds"] <= m["seconds"] <= sound["max_seconds"]:
                failures.append(
                    f"{f.name}: {m['seconds']:.3f} s is outside {sound['min_seconds']} to {sound['max_seconds']}"
                )
            if m["peak_db"] > PEAK_DB + 0.3:
                failures.append(
                    f"{f.name}: peak {m['peak_db']:.2f} dBFS is over {PEAK_DB}"
                )
            if sound["kind"] != "loop" and m["lead_ms"] > LEAD_MAX * 1000:
                failures.append(f"{f.name}: lead-in {m['lead_ms']:.1f} ms")
            if sound["kind"] == "loop":
                s = seam(m["x"])
                spreadlu = float(
                    np.percentile(m["momentary"][4:], 95)
                    - np.percentile(m["momentary"][4:], 5)
                )
                row += f"  wrap {s['wrap_ratio']:.2f}x  edges {s['edge_db']:+.2f} dB  spread {spreadlu:.2f} LU"
                if s["wrap_ratio"] > 3.0 or abs(s["edge_db"]) > 1.5:
                    failures.append(f"{f.name}: the loop seam shows ({row})")
                if spreadlu > sound["max_spread_lu"]:
                    failures.append(
                        f"{f.name}: level moves {spreadlu:.2f} LU, a gust (limit {sound['max_spread_lu']})"
                    )
            print(row)
        if loud and max(loud) - min(loud) > 1.0:
            failures.append(
                f"{sound['name']}: loudness differs by {max(loud) - min(loud):.1f} LU inside the set"
            )
        if loud:
            print(
                f"-- {sound['name']}: {len(files)} files, loudness {min(loud):.1f} to {max(loud):.1f}"
            )
    for failure in failures:
        print("FAIL", failure)
    print("check:", "FAILED" if failures else "ok")
    if failures:
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "command", choices=["credits", "plan", "generate", "encode", "check"]
    )
    parser.add_argument(
        "--cache",
        type=Path,
        help="folder for the raw takes and their request files (scratch)",
    )
    parser.add_argument("--ffmpeg", help="the pinned ffmpeg (`gds tool path ffmpeg`)")
    parser.add_argument("--only", help="comma-separated sound names")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="the kit checkout the folders are relative to",
    )
    args = parser.parse_args()
    if args.command in {"plan", "generate", "encode"} and not args.cache:
        parser.error("--cache is required")
    if args.command in {"encode", "check"} and not args.ffmpeg:
        parser.error("--ffmpeg is required")
    {
        "credits": cmd_credits,
        "plan": cmd_plan,
        "generate": cmd_generate,
        "encode": cmd_encode,
        "check": cmd_check,
    }[args.command](args)


if __name__ == "__main__":
    main()
