"""`gds capture`: the scratch rule, the Godot and ffmpeg command lines, contact sheets and size capping, with the
programs replaced by fakes."""

import json
from pathlib import Path

import pytest
from PIL import Image

from gds_tools import capture
from gds_tools.capture import CaptureError, Result


def make_frames(folder: Path, count: int, prefix: str = "main", size: tuple[int, int] = (320, 180)) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for i in range(count):
        Image.new("RGB", size, (i * 20 % 256, 80, 120)).save(folder / f"{prefix}{i:08d}.png")


class FakeGodot:
    """Writes `frames` Movie Maker frames to the --write-movie path, like the real thing."""

    def __init__(self, frames: int = 3, returncode: int = 0, output: str = "") -> None:
        self.frames, self.returncode, self.output = frames, returncode, output
        self.calls: list[list[str]] = []

    def __call__(self, cmd: list[str], cwd: Path | None) -> Result:
        self.calls.append(cmd)
        if "--write-movie" in cmd:
            movie = Path(cmd[cmd.index("--write-movie") + 1])
            make_frames(movie.parent, self.frames, movie.stem)
        return Result(self.returncode, self.output)


@pytest.fixture
def project(tmp_path: Path) -> Path:
    folder = tmp_path / "game"
    (folder / ".godot" / "imported").mkdir(parents=True)
    (folder / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    return folder


def git_fake(top: Path, branch: str):
    def run(cmd: list[str], cwd: Path | None) -> Result:
        args = cmd[3:]
        if args[:2] == ["rev-parse", "--show-toplevel"]:
            return Result(0, f"{top}\n")
        if args[:2] == ["rev-parse", "--abbrev-ref"]:
            return Result(0, f"{branch}\n")
        return Result(1, "")

    return run


def test_scratch_folder_for_a_main_checkout(tmp_path: Path) -> None:
    top = tmp_path / "repos" / "deadnight"
    (top / "game").mkdir(parents=True)
    folder = capture.scratch_folder(top / "game", tmp_path / "ws", git_fake(top, "feature/zombies"))
    assert folder == tmp_path / "ws" / "scratch" / "deadnight" / "feature-zombies"


def test_scratch_folder_for_a_worktree_uses_the_parent_folder(tmp_path: Path) -> None:
    top = tmp_path / "worktrees" / "deadnight" / "hud"
    (top / "game").mkdir(parents=True)
    folder = capture.scratch_folder(top / "game", tmp_path / "ws", git_fake(top, "hud"))
    assert folder == tmp_path / "ws" / "scratch" / "deadnight" / "hud"


def test_scratch_folder_outside_git(tmp_path: Path) -> None:
    with pytest.raises(CaptureError, match="not inside a git"):
        capture.scratch_folder(tmp_path, tmp_path, lambda cmd, cwd: Result(128, ""))


def test_frames_folder_follows_the_caller_not_the_throwaway_game(tmp_path: Path) -> None:
    """A throwaway game is its own git repository (`template-check`, branch `main`): its frames must not land
    in the shared `scratch/template-check/main/`, but in the scratch folder of the worktree gds runs in."""
    game = tmp_path / "elsewhere" / "template-check" / "game"
    worktree = tmp_path / "worktrees" / "gdstudio" / "my-task"
    game.mkdir(parents=True)
    worktree.mkdir(parents=True)

    def run(cmd: list[str], cwd: Path | None) -> Result:
        top = game.parent if Path(cmd[2]) == game.resolve() else worktree
        return git_fake(top, "main" if top == game.parent else "my-task")(cmd, cwd)

    out = capture.frames_folder(game, worktree, tmp_path / "ws", "hud", None, run)
    assert out == tmp_path / "ws" / "scratch" / "gdstudio" / "my-task" / "hud"


def test_frames_folder_takes_an_explicit_out(tmp_path: Path) -> None:
    explicit = tmp_path / "mine" / "clip"
    out = capture.frames_folder(
        tmp_path / "game", tmp_path, tmp_path / "ws", "hud", str(explicit), git_fake(tmp_path, "x")
    )
    assert out == explicit.resolve()


def test_frames_command_line_and_metadata(project: Path, tmp_path: Path) -> None:
    fake = FakeGodot(frames=3)
    out = tmp_path / "scratch" / "main"
    frames = capture.capture_frames(Path("godot"), project, out, "res://x.tscn", 0.25, 12, fake, lambda m: None)
    cmd = fake.calls[-1]
    assert cmd[:3] == ["godot", "--path", str(project)]
    assert "--headless" not in cmd
    assert cmd[cmd.index("--write-movie") + 1] == str(out / "main.png")
    assert cmd[cmd.index("--fixed-fps") + 1] == "12"
    assert cmd[cmd.index("--quit-after") + 1] == "3"  # ceil(0.25 * 12)
    assert "--resolution" not in cmd  # Movie Maker ignores it: frames are the project's viewport size
    assert cmd[-1] == "res://x.tscn"
    assert len(frames) == 3
    assert json.loads((out / capture.META_FILE).read_text(encoding="utf-8"))["fps"] == 12
    assert capture.read_fps(out) == 12


def test_frames_replaces_old_frames_and_imports_a_fresh_project(project: Path, tmp_path: Path) -> None:
    (project / ".godot" / "imported").rmdir()
    out = tmp_path / "scratch" / "main"
    make_frames(out, 9)
    fake = FakeGodot(frames=2)
    assert len(capture.capture_frames(Path("godot"), project, out, None, 1, 2, run=fake, log=lambda m: None)) == 2
    assert "--import" in fake.calls[0]
    assert "res://" not in " ".join(fake.calls[-1])  # no scene given: the main scene runs


def test_frames_fails_when_godot_fails_or_writes_nothing(project: Path, tmp_path: Path) -> None:
    with pytest.raises(CaptureError, match="wrote 0 frames"):
        capture.capture_frames(Path("g"), project, tmp_path / "a", None, 1, 1, run=FakeGodot(0), log=lambda m: None)
    with pytest.raises(CaptureError, match="code 3"):
        capture.capture_frames(Path("g"), project, tmp_path / "b", None, 1, 1, run=FakeGodot(2, 3), log=lambda m: None)


def test_frames_reports_error_lines(project: Path, tmp_path: Path) -> None:
    logged: list[str] = []
    fake = FakeGodot(1, output="fine\nERROR: bad thing\n")
    capture.capture_frames(Path("g"), project, tmp_path / "a", None, 1, 1, run=fake, log=logged.append)
    assert any("ERROR: bad thing" in line for line in logged)
    assert any("WARNING" in line for line in logged)


@pytest.mark.parametrize(("seconds", "fps"), [(0, 10), (1, 0), (10_000, 10)])
def test_frames_rejects_bad_lengths(project: Path, tmp_path: Path, seconds: float, fps: int) -> None:
    with pytest.raises(CaptureError):
        capture.capture_frames(Path("g"), project, tmp_path / "a", None, seconds, fps, run=FakeGodot(), log=print)


def test_frames_needs_a_project(tmp_path: Path) -> None:
    with pytest.raises(CaptureError, match="project.godot"):
        capture.capture_frames(Path("g"), tmp_path, tmp_path / "a", None, 1, 1, run=FakeGodot(), log=print)


def test_safe_name() -> None:
    assert capture.safe_name("hud-1.2_a") == "hud-1.2_a"
    with pytest.raises(CaptureError):
        capture.safe_name("../x")


def test_frame_files_ignore_non_frames_and_sort_numerically(tmp_path: Path) -> None:
    make_frames(tmp_path, 12)
    Image.new("RGB", (4, 4)).save(tmp_path / "sheet.png")
    names = [p.name for p in capture.frame_files(tmp_path)]
    assert names[0] == "main00000000.png"
    assert len(names) == 12


def test_contact_sheet_layout(tmp_path: Path) -> None:
    make_frames(tmp_path, 10, size=(320, 180))
    sheet = capture.contact_sheet(tmp_path, every=2, columns=3)
    assert sheet == tmp_path / "sheet.png"
    with Image.open(sheet) as image:
        tile_h = round(180 * capture.SHEET_TILE_WIDTH / 320)
        assert image.width == 3 * capture.SHEET_TILE_WIDTH + 4 * capture.SHEET_GAP
        assert image.height == 2 * tile_h + 3 * capture.SHEET_GAP  # 5 tiles in 3 columns: two rows
        # The top-left tile holds the first frame (colour (0, 80, 120)), the label is drawn in white on top of it.
        assert image.getpixel((capture.SHEET_GAP + 300, capture.SHEET_GAP + 100)) == (0, 80, 120)
        corner = image.crop((capture.SHEET_GAP, capture.SHEET_GAP, capture.SHEET_GAP + 60, capture.SHEET_GAP + 40))
        assert (255, 255, 255) in {color for _, color in corner.getcolors(10_000)}


def test_contact_sheet_errors(tmp_path: Path) -> None:
    with pytest.raises(CaptureError, match="no frames"):
        capture.contact_sheet(tmp_path)
    for name in ("walk-front.png", "sheet.png"):
        Image.new("RGB", (8, 8)).save(tmp_path / name)
    with pytest.raises(CaptureError) as error:  # names that miss the pattern: the error says the pattern (#815)
        capture.contact_sheet(tmp_path)
    assert "<prefix><number>.png" in str(error.value) and "00000001.png" in str(error.value)
    assert "its 2 PNG files (sheet.png, walk-front.png) are not" in str(error.value)
    for name in ("walk-front.png", "sheet.png"):
        (tmp_path / name).unlink()
    make_frames(tmp_path, 1)
    with pytest.raises(CaptureError):
        capture.contact_sheet(tmp_path, every=0)


class FakeFfmpeg:
    """Writes an output file of the next size in `sizes` (one per call)."""

    def __init__(self, sizes: list[int], returncode: int = 0) -> None:
        self.sizes, self.returncode = list(sizes), returncode
        self.calls: list[list[str]] = []

    def __call__(self, cmd: list[str], cwd: Path | None) -> Result:
        self.calls.append(cmd)
        if self.returncode == 0:
            Path(cmd[-1]).write_bytes(b"x" * self.sizes.pop(0))
        return Result(self.returncode, "boom")


def test_mp4_command_line(tmp_path: Path) -> None:
    folder = tmp_path / "run"
    make_frames(folder, 20)
    (folder / capture.META_FILE).write_text('{"fps": 10}', encoding="utf-8")
    fake = FakeFfmpeg([1000])
    clip = capture.encode_clip(Path("ffmpeg"), folder, run=fake, log=lambda m: None)
    cmd = fake.calls[0]
    assert clip == folder / "run.mp4"
    assert cmd[cmd.index("-framerate") + 1] == "10"
    assert cmd[cmd.index("-i") + 1] == str(folder / "main%08d.png")
    assert cmd[cmd.index("-t") + 1] == "2.000"
    assert "libx264" in cmd and "yuv420p" in " ".join(cmd)


def test_clip_steps_down_in_width_until_it_fits(tmp_path: Path) -> None:
    folder = tmp_path / "run"
    make_frames(folder, 5)
    big, small = capture.CLIP_MAX_BYTES + 1, 10
    fake = FakeFfmpeg([big, big, small])
    clip = capture.encode_clip(Path("ffmpeg"), folder, run=fake, log=lambda m: None)
    assert clip.stat().st_size == small
    assert [f"min({w}," in " ".join(c) for c, w in zip(fake.calls, capture.CLIP_WIDTHS[:3], strict=True)] == [True] * 3


def test_clip_too_big_even_when_narrow(tmp_path: Path) -> None:
    folder = tmp_path / "run"
    make_frames(folder, 5)
    fake = FakeFfmpeg([capture.CLIP_MAX_BYTES + 1] * len(capture.CLIP_WIDTHS))
    with pytest.raises(CaptureError, match="still over"):
        capture.encode_clip(Path("ffmpeg"), folder, run=fake, log=lambda m: None)
    assert not (folder / "run.mp4").exists()


def test_clip_length_is_capped(tmp_path: Path) -> None:
    folder = tmp_path / "run"
    make_frames(folder, 40, size=(8, 8))
    (folder / capture.META_FILE).write_text('{"fps": 1}', encoding="utf-8")  # 40 s of frames
    fake = FakeFfmpeg([1])
    capture.encode_clip(Path("ffmpeg"), folder, run=fake, log=lambda m: None)
    assert fake.calls[0][fake.calls[0].index("-t") + 1] == "30.000"


def test_gif_command_line_and_ffmpeg_failure(tmp_path: Path) -> None:
    folder = tmp_path / "run"
    make_frames(folder, 5)
    fake = FakeFfmpeg([1])
    clip = capture.encode_clip(Path("ffmpeg"), folder, gif=True, run=fake, log=lambda m: None)
    assert clip == folder / "run.gif"
    assert "palettegen" in " ".join(fake.calls[0])
    with pytest.raises(CaptureError, match="ffmpeg failed"):
        capture.encode_clip(Path("ffmpeg"), folder, run=FakeFfmpeg([], returncode=1), log=lambda m: None)


def test_clip_without_frames(tmp_path: Path) -> None:
    with pytest.raises(CaptureError, match="no frames"):
        capture.encode_clip(Path("ffmpeg"), tmp_path, run=FakeFfmpeg([]), log=lambda m: None)
