"""`gds capture`: frames, contact sheets and clips as proof for a pull request (docs/capture.md).

`frames` runs the pinned Godot with Movie Maker (a real window, not headless) and writes numbered PNGs into
`<workspace>/scratch/<repo>/<branch>/<name>/`, with a small `capture.json` recording the frame rate. `sheet` tiles
those frames into one labelled PNG that can be read in a single look. `clip` encodes them into an MP4 or GIF with the
pinned ffmpeg, kept under the size GitHub accepts for an attachment.

Programs are started through a `Runner`, so the tests replace Godot and ffmpeg with fakes.
"""

from __future__ import annotations

import json
import math
import re
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

META_FILE = "capture.json"
SHEET_FILE = "sheet.png"
FRAME_RE = re.compile(r"^(?P<prefix>.*?)(?P<number>\d+)\.png$")

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
GIF_MAX_FPS = 12


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


def safe_name(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise CaptureError(f"capture name {name!r} may only use letters, digits, '_', '-' and '.'")
    return name


def frame_files(folder: Path) -> list[Path]:
    """The numbered frames of a capture folder, in order (the sheet and other images are not frames)."""
    found = [(int(m["number"]), p) for p in folder.glob("*.png") if (m := FRAME_RE.match(p.name))]
    return [p for _, p in sorted(found)]


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
    run: Runner = run_program,
    log: Callable[[str], None] = print,
) -> list[Path]:
    """Run `scene` (default: the main scene) in Movie Maker for `seconds` at `fps`; returns the written frames.

    The window is a real one, because Movie Maker needs a renderer: the capture is not headless. The scene runs on a
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
        raise CaptureError(f"no frames in {folder}; run `gds capture frames` first")
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


def _ffmpeg_cmd(
    ffmpeg: Path, pattern: Path, fps: int, width: int, seconds: float, gif: bool, target: Path
) -> list[str]:
    scale = f"scale='min({width},iw)':-2:flags=lanczos"
    cmd = [str(ffmpeg), "-y", "-hide_banner", "-loglevel", "error", "-framerate", str(fps), "-i", str(pattern)]
    cmd += ["-t", f"{seconds:.3f}"]
    if gif:
        out_fps = min(fps, GIF_MAX_FPS)
        palette = "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4"
        graph = f"fps={out_fps},{scale},{palette}"
        return [*cmd, "-filter_complex", graph, "-loop", "0", str(target)]
    cmd += ["-vf", f"{scale},format=yuv420p", "-c:v", "libx264", "-preset", "slow", "-crf", str(MP4_CRF)]
    return [*cmd, "-movflags", "+faststart", str(target)]


def encode_clip(
    ffmpeg: Path,
    folder: Path,
    gif: bool = False,
    run: Runner = run_program,
    log: Callable[[str], None] = print,
) -> Path:
    """Encode the frames of `folder` into `<folder>/<name>.mp4` (or .gif), at most `CLIP_MAX_SECONDS` long.

    The clip is encoded at the widest size in `CLIP_WIDTHS` and, while the file exceeds `CLIP_MAX_BYTES`, again at
    the next narrower one; CaptureError when even the narrowest is too big.
    """
    frames = frame_files(folder)
    if not frames:
        raise CaptureError(f"no frames in {folder}; run `gds capture frames` first")
    match = FRAME_RE.match(frames[0].name)
    assert match is not None
    digits = len(match["number"])
    pattern = folder / f"{match['prefix']}%0{digits}d.png"
    fps = read_fps(folder)
    seconds = min(len(frames) / fps, CLIP_MAX_SECONDS)
    if len(frames) / fps > CLIP_MAX_SECONDS:
        log(f"clip cut to its first {CLIP_MAX_SECONDS:g} s")
    target = folder / f"{folder.name}.{'gif' if gif else 'mp4'}"
    for width in CLIP_WIDTHS:
        target.unlink(missing_ok=True)
        result = run(_ffmpeg_cmd(ffmpeg, pattern, fps, width, seconds, gif, target), None)
        if result.returncode != 0 or not target.exists():
            raise CaptureError(f"ffmpeg failed with code {result.returncode}:\n{result.output.strip()[-600:]}")
        size = target.stat().st_size
        log(f"encoded {target.name}: {size / 1024:.0f} KB at up to {width} px wide")
        if size <= CLIP_MAX_BYTES:
            return target
    target.unlink(missing_ok=True)
    raise CaptureError(
        f"the clip is still over {CLIP_MAX_BYTES // 1024 // 1024} MB at {CLIP_WIDTHS[-1]} px; shorten it"
    )
