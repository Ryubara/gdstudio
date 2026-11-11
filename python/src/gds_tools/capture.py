"""`gds capture`: frames, contact sheets and clips as proof for a pull request (docs/studio/capture.md).

`frames` runs the pinned Godot with Movie Maker (a real window on a private desktop, not headless) and writes
numbered PNGs into `<workspace>/scratch/<repo>/<branch>/<name>/`, with a small `capture.json` recording the frame
rate. `sheet` tiles those frames into one labelled PNG that can be read in a single look. `clip` encodes them into an
MP4 or GIF with the pinned ffmpeg, kept under the size GitHub accepts for an attachment.

Programs are started through a `Runner`, so the tests replace Godot and ffmpeg with fakes.
"""

from __future__ import annotations

import json
import math
import re
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from gds_tools.quiet_run import run_quiet

META_FILE = "capture.json"
SHEET_FILE = "sheet.png"
# Movie Maker writes <name><8 digits>.png; the number takes at most 8 digits so a name ending in a digit stays the
# prefix (`run2` gives run200000000.png, not run + 200000000)
FRAME_RE = re.compile(r"^(?P<prefix>.*?)(?P<number>\d{1,8})\.png$")

DEFAULT_FPS = 10
MAX_FRAMES = 6000  # a safety net: 10 minutes at 10 fps
GODOT_TIMEOUT = 900  # seconds

SHEET_TILE_WIDTH = 480
SHEET_GAP = 6
SHEET_BACKGROUND = (24, 24, 28)
LABEL_COLOR = (255, 255, 255)
LABEL_SHADOW = (0, 0, 0)

CLIP_MAX_SECONDS = 30.0
CLIP_MAX_BYTES = 9 * 1024 * 1024  # GitHub takes 10 MB images and GIFs; stay under it
CLIP_WIDTHS = (1280, 960, 720, 480)  # tried in order until the file fits
MP4_CRF = 26
# A GIF for a pull request (docs/studio/capture.md#gif-or-mp4, measured in #1153): GitHub's description column is
# 814 px wide, a GIF's delays are whole hundredths of a second, and a GIF plays without a stall while it downloads
# only when its bytes a second stay under the viewer's connection.
GIF_WIDTHS = (800, 640, 480)  # tried in order until the file fits gif_budget()
GIF_FPS_CHOICES = (20, 10, 5, 4, 2, 1)  # each a whole number of hundredths a frame
GIF_MAX_FPS = GIF_FPS_CHOICES[0]
GIF_BYTES_PER_SECOND = 512 * 1024  # 4.2 Mbit/s: no stall on the first play while downloading at 10 Mbps
GIF_MIN_BUDGET_SECONDS = 2.0  # a shorter loop may stall once, for under a second, on its first play
GIF_MAX_SECONDS = 10.0  # longer is an MP4; also caps the budget at 5 MB


USER_ARGS = ("--", "++")  # Godot hands every argument after either of these to the game's scripts


def tell_movie_end(args: list[str]) -> list[str]:
    """`args` for Godot with a Movie Maker run's `--quit-after N` repeated to the game as a user argument.

    Godot keeps its own arguments from `OS.get_cmdline_args()`, so a game cannot see where a capture ends; a voice
    still playing then is reported as `resources still in use at exit`, because under Movie Maker the mixer steps
    only on written frames. The game's `AudioSettings` reads `--quit-after=N` and silences the run a few frames
    earlier (docs/engines/godot/audio.md#capturing-sound). Other runs, and one that already says it, are unchanged.
    """
    end = next((i for i, a in enumerate(args) if a in USER_ARGS), len(args))
    engine, user = args[:end], args[end + 1 :]
    if not any(a == "--write-movie" or a.startswith("--write-movie=") for a in engine):
        return args
    if any(a.startswith("--quit-after") for a in user):
        return args
    count = next((engine[i + 1] for i, a in enumerate(engine[:-1]) if a == "--quit-after"), None)
    count = count or next((a.split("=", 1)[1] for a in engine if a.startswith("--quit-after=")), None)
    if count is None:
        return args
    return [*args, f"--quit-after={count}"] if end < len(args) else [*args, "++", f"--quit-after={count}"]


class CaptureError(Exception):
    """A capture step that cannot run or whose result is unusable."""


@dataclass(frozen=True)
class Result:
    """What a started program printed and how it ended."""

    returncode: int
    output: str


Runner = Callable[[list[str], Path | None], Result]


def run_program(cmd: list[str], cwd: Path | None = None) -> Result:
    """The real runner: start `cmd`, wait for it and return its combined output."""
    try:
        done = subprocess.run(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=GODOT_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise CaptureError(f"{Path(cmd[0]).name} did not finish within {GODOT_TIMEOUT} s") from error
    return Result(done.returncode, done.stdout)


def run_godot(cmd: list[str], cwd: Path | None = None) -> Result:
    """Run the pinned Godot without taking the focus from the person at the machine (docs/engines/godot/no-focus.md)."""
    outcome = run_quiet(cmd, cwd, timeout=GODOT_TIMEOUT)
    if outcome.timed_out:
        raise CaptureError(f"{Path(cmd[0]).name} did not finish within {GODOT_TIMEOUT} s")
    return Result(outcome.returncode, outcome.output)


def _git(folder: Path, *args: str, run: Runner) -> str:
    result = run(["git", "-C", str(folder), *args], None)
    return result.output.strip() if result.returncode == 0 else ""


def scratch_folder(project: Path, workspace: Path, run: Runner = run_program) -> Path:
    """<workspace>/scratch/<repo>/<branch>/ for a game project folder: the rule of the hooks' `scratch_folder`.

    The repository is the project's git top level; in a worktree (`worktrees/<repo>/<branch>`) its name is the
    parent folder's, and a branch's slashes become dashes.
    """
    project = project.resolve()
    top = _git(project, "rev-parse", "--show-toplevel", run=run)
    if not top:
        raise CaptureError(f"{project} is not inside a git repository")
    repo = Path(top)
    branch = _git(repo, "rev-parse", "--abbrev-ref", "HEAD", run=run) or "detached"
    name = repo.name if repo.parent.name == "repos" else repo.parent.name
    return workspace / "scratch" / name / branch.replace("/", "-")


def frames_folder(
    project: Path, caller: Path, workspace: Path, name: str, out: str | None, run: Runner = run_program
) -> Path:
    """Where `gds capture frames` writes: `out` when given, else the scratch folder of the caller.

    The caller is the folder gds runs in (a task's worktree), never the project: a throwaway game is a git
    repository of its own (`template-check`, branch `main`), and naming the folder from it put every agent's
    frames in the shared `scratch/template-check/main/`.
    """
    if out:
        return Path(out).resolve()
    try:
        return scratch_folder(caller, workspace, run) / safe_name(name)
    except CaptureError as error:
        raise CaptureError(f"{error}; run gds from your worktree, or pass --out <folder>") from error


def safe_name(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise CaptureError(f"capture name {name!r} may only use letters, digits, '_', '-' and '.'")
    return name


def frame_files(folder: Path) -> list[Path]:
    """The numbered frames of a capture folder, in order (the sheet and other images are not frames)."""
    found = [(int(m["number"]), p) for p in folder.glob("*.png") if (m := FRAME_RE.match(p.name))]
    return [p for _, p in sorted(found)]


def no_frames_error(folder: Path) -> CaptureError:
    """The error for a folder without frames: it names the pattern a frame needs and the PNG files that miss it."""
    others = sorted(p.name for p in folder.glob("*.png"))
    listed = ", ".join(others[:3]) + (", ..." if len(others) > 3 else "")
    found = f"; its {len(others)} PNG files ({listed}) are not" if others else ""
    return CaptureError(
        f"no frames in {folder}: a frame is a PNG named <prefix><number>.png, one prefix and one number width for the "
        f"folder, numbered in order (Movie Maker writes capture00000000.png, capture00000001.png, ...){found}; "
        "run `gds capture frames`, or rename the files to that pattern"
    )


def read_fps(folder: Path) -> int:
    """The frame rate `frames` recorded for a folder, or the default when it was not made by `gds capture`."""
    try:
        return int(json.loads((folder / META_FILE).read_text(encoding="utf-8"))["fps"])
    except (OSError, ValueError, KeyError):
        return DEFAULT_FPS


def capture_frames(
    godot: Path,
    project: Path,
    out: Path,
    scene: str | None,
    seconds: float,
    fps: int,
    run: Runner = run_godot,
    log: Callable[[str], None] = print,
) -> list[Path]:
    """Run `scene` (default: the main scene) in Movie Maker for `seconds` at `fps`; returns the written frames.

    The window is a real one, because Movie Maker needs a renderer: the capture is not headless. It opens on a private
    Windows desktop, so it never takes the keyboard or mouse from the person at the machine. The scene runs on a
    fixed timestep, so a seeded scene gives the same frames every time.
    """
    count = math.ceil(seconds * fps)
    if count < 1 or fps < 1:
        raise CaptureError("--seconds and --fps must give at least one frame")
    if count > MAX_FRAMES:
        raise CaptureError(f"{count} frames is more than the limit of {MAX_FRAMES}; shorten --seconds or lower --fps")
    if not (project / "project.godot").exists():
        raise CaptureError(f"{project} has no project.godot")
    name = out.name
    if out.exists():
        for old in (*out.glob("*.png"), *out.glob("*.wav"), out / META_FILE):
            old.unlink(missing_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    if not (project / ".godot" / "imported").exists():
        log("importing the project (first run)")
        run([str(godot), "--headless", "--path", str(project), "--import"], None)

    cmd = [str(godot), "--path", str(project), "--write-movie", str(out / f"{name}.png")]
    cmd += ["--fixed-fps", str(fps), "--quit-after", str(count)]
    if scene:
        cmd.append(scene)
    cmd = tell_movie_end(cmd)
    log(f"capturing {count} frames at {fps} fps into {out}")
    result = run(cmd, project)
    errors = [line for line in result.output.splitlines() if "ERROR" in line]
    for line in errors[:10]:
        log(f"  godot: {line.strip()}")
    frames = frame_files(out)
    if result.returncode != 0 or not frames:
        tail = "\n".join(result.output.strip().splitlines()[-8:])
        raise CaptureError(f"Godot ended with code {result.returncode} and wrote {len(frames)} frames:\n{tail}")
    (out / META_FILE).write_text(json.dumps({"fps": fps, "scene": scene, "frames": len(frames)}) + "\n", "utf-8")
    if errors:
        log(f"  WARNING: Godot printed {len(errors)} ERROR line(s); fix them before using this as proof")
    return frames


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    return ImageFont.load_default(size=size)


def contact_sheet(folder: Path, every: int = 1, columns: int = 4, output: Path | None = None) -> Path:
    """Tile every `every`-th frame of `folder` into a labelled PNG with `columns` columns; returns its path."""
    if every < 1 or columns < 1:
        raise CaptureError("--every and --columns must be at least 1")
    frames = frame_files(folder)
    if not frames:
        raise no_frames_error(folder)
    picked = list(enumerate(frames))[::every]
    with Image.open(picked[0][1]) as first:
        width = SHEET_TILE_WIDTH
        height = max(1, round(first.height * width / first.width))
    rows = math.ceil(len(picked) / columns)
    sheet = Image.new(
        "RGB",
        (columns * width + (columns + 1) * SHEET_GAP, rows * height + (rows + 1) * SHEET_GAP),
        SHEET_BACKGROUND,
    )
    draw = ImageDraw.Draw(sheet)
    font = _font(max(14, height // 12))
    for slot, (index, path) in enumerate(picked):
        x = SHEET_GAP + (slot % columns) * (width + SHEET_GAP)
        y = SHEET_GAP + (slot // columns) * (height + SHEET_GAP)
        with Image.open(path) as frame:
            sheet.paste(frame.convert("RGB").resize((width, height), Image.Resampling.LANCZOS), (x, y))
        label = str(index)
        draw.text((x + 9, y + 7), label, font=font, fill=LABEL_SHADOW)
        draw.text((x + 8, y + 6), label, font=font, fill=LABEL_COLOR)
    target = output or folder / SHEET_FILE
    sheet.save(target, optimize=True)
    return target


def gif_budget(seconds: float) -> int:
    """The most bytes a GIF of `seconds` should take: `GIF_BYTES_PER_SECOND` of it, counted for at least
    `GIF_MIN_BUDGET_SECONDS` and at most `GIF_MAX_SECONDS` (1 to 5 MB)."""
    return int(GIF_BYTES_PER_SECOND * min(max(seconds, GIF_MIN_BUDGET_SECONDS), GIF_MAX_SECONDS))


def gif_fps(fps: int | Fraction) -> int | Fraction:
    """The GIF frame rate for frames played at `fps`: one whose delay is a whole number of hundredths of a second
    (12 fps came out as delays of 8, 8 and 9, a judder), dividing `fps` when it can so the frames kept are even.

    A slowed rate (10 fps slowed 3 times is 10/3) whose delay is already whole (30 hundredths) keeps every frame.
    """
    fps = Fraction(fps)
    if fps <= GIF_MAX_FPS and (100 / fps).denominator == 1:
        return int(fps) if fps.denominator == 1 else fps
    for choice in GIF_FPS_CHOICES:
        if choice <= fps and fps % choice == 0 and choice >= 10:
            return choice
    return next((choice for choice in GIF_FPS_CHOICES if choice <= fps), 1)


def rate_text(rate: int | Fraction) -> str:
    """A frame rate as ffmpeg reads it: `10`, or `10/3` for one that is not whole."""
    rate = Fraction(rate)
    return str(rate.numerator) if rate.denominator == 1 else f"{rate.numerator}/{rate.denominator}"


def _ffmpeg_cmd(
    ffmpeg: Path, pattern: Path, start: int, rate: Fraction, width: int, seconds: float, gif: bool, target: Path
) -> list[str]:
    scale = f"scale='min({width},iw)':-2:flags=lanczos"
    cmd = [str(ffmpeg), "-y", "-hide_banner", "-loglevel", "error", "-framerate", rate_text(rate)]
    # ffmpeg looks for a first frame numbered 0 to 4 only; frames numbered from 1 by Blender in a folder whose name
    # ends in a digit (legs20001.png read as frame 20001), or a folder starting at 16.png, were found by nobody (#1190)
    cmd += ["-start_number", str(start), "-i", str(pattern), "-t", f"{seconds:.3f}"]
    if gif:
        palette = "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4"
        graph = f"fps={rate_text(gif_fps(rate))},{scale},{palette}"
        return [*cmd, "-filter_complex", graph, "-loop", "0", str(target)]
    cmd += ["-vf", f"{scale},format=yuv420p", "-c:v", "libx264", "-preset", "slow", "-crf", str(MP4_CRF)]
    return [*cmd, "-movflags", "+faststart", str(target)]


def encode_clip(
    ffmpeg: Path,
    folder: Path,
    gif: bool = False,
    run: Runner = run_program,
    log: Callable[[str], None] = print,
    max_seconds: float = CLIP_MAX_SECONDS,
    fps: int | None = None,
    slow: float = 1.0,
) -> Path:
    """Encode the frames of `folder` into `<folder>/<name>.mp4` (or .gif), at most `max_seconds` long.

    The frames play at `fps` (default: the rate `capture.json` recorded, else `DEFAULT_FPS`), `slow` times slower:
    `slow=2` plays 10 fps frames at 5 fps, every frame kept, so a fast pose change or a jitter can be seen (#1190).
    `max_seconds` and the GIF's length count the slowed clip. Frames past `max_seconds` are left out, and a line says
    how many and how many seconds (#1132).

    The clip is encoded at the widest size in `CLIP_WIDTHS` and, while the file exceeds `CLIP_MAX_BYTES`, again at
    the next narrower one; CaptureError when even the narrowest is too big.
    """
    if max_seconds <= 0:
        raise CaptureError(f"--max-seconds must be more than 0, not {max_seconds:g}")
    if fps is not None and fps < 1:
        raise CaptureError(f"--fps must be at least 1, not {fps}")
    if slow <= 0:
        raise CaptureError(f"--slow must be more than 0, not {slow:g}")
    frames = frame_files(folder)
    if not frames:
        raise no_frames_error(folder)
    match = FRAME_RE.match(frames[0].name)
    assert match is not None
    digits = len(match["number"])
    pattern = folder / f"{match['prefix']}%0{digits}d.png"
    start = int(match["number"])
    rate = Fraction(fps or read_fps(folder)) / Fraction(str(slow)).limit_denominator(1000)
    total = float(len(frames) / rate)
    seconds = min(total, max_seconds)
    if total > max_seconds:
        left_out = len(frames) - math.ceil(max_seconds * rate)
        log(
            f"clip cut at {max_seconds:g} s: {left_out} frames ({total - max_seconds:g} s) of {len(frames)} left out;"
            " --max-seconds for a longer clip"
        )
    if gif and seconds > GIF_MAX_SECONDS:
        log(
            f"warning: a {seconds:g} s GIF is longer than the {GIF_MAX_SECONDS:g} s a GIF is for; make an MP4 (no"
            " --gif) or a shorter capture (docs/studio/capture.md#gif-or-mp4)"
        )
    target = folder / f"{folder.name}.{'gif' if gif else 'mp4'}"
    widths, budget = (GIF_WIDTHS, gif_budget(seconds)) if gif else (CLIP_WIDTHS, CLIP_MAX_BYTES)
    size = 0
    for width in widths:
        target.unlink(missing_ok=True)
        result = run(_ffmpeg_cmd(ffmpeg, pattern, start, rate, width, seconds, gif, target), None)
        if result.returncode != 0 or not target.exists():
            raise CaptureError(f"ffmpeg failed with code {result.returncode}:\n{result.output.strip()[-600:]}")
        size = target.stat().st_size
        log(f"encoded {target.name}: {_size_text(size)} at up to {width} px wide")
        if size <= budget:
            return target
    if gif and size <= CLIP_MAX_BYTES:
        log(
            f"warning: {target.name} is {_size_text(size)} at {widths[-1]} px, over the {_size_text(budget)} a"
            f" {seconds:g} s GIF plays smoothly in on GitHub; make an MP4 (no --gif) or a shorter capture"
            " (docs/studio/capture.md#gif-or-mp4)"
        )
        return target
    target.unlink(missing_ok=True)
    what, advice = ("GIF", "make an MP4 (no --gif) or shorten it") if gif else ("clip", "shorten it")
    raise CaptureError(f"the {what} is still over {_size_text(CLIP_MAX_BYTES)} at {widths[-1]} px; {advice}")


def _size_text(size: int) -> str:
    """`size` bytes as people read it: `4.2 MB`, `850 KB`."""
    if size < 1024 * 1024:
        return f"{size / 1024:.0f} KB"
    return f"{size / 1024 / 1024:.1f}".removesuffix(".0") + " MB"
