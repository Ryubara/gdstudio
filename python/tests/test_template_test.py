"""`gds template test`: a throwaway workspace of its own per call, removed on every exit, with Godot replaced by a fake.

The risk the command exists for is the folder: two agents once shared a fixed throwaway folder and one removed it under
the other (docs/engines/godot/new-game.md#proof). So most tests are about where the workspace is, that it is unique,
and that exactly it is removed."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from gds_tools import cli, layout, new_game, scripts, template_test, workspace

KIT = Path(__file__).resolve().parents[2]
GODOT = "fake-godot"

REPORT = """<?xml version="1.0" encoding="UTF-8" ?>
<testsuites id="d" name="report_1" tests="3" failures="{failures}" skipped="0" flaky="0" time="0.000">
	<testsuite id="0" name="test_a" package="tests/core" tests="2" failures="0" errors="0" skipped="0" time="0.5">
		<testcase name="test_one" classname="test_a" time="0.1"></testcase>
		<testcase name="test_two" classname="test_a" time="0.2"></testcase>
	</testsuite>
	<testsuite id="1" name="test_b" package="tests" tests="1" failures="{failures}" errors="0" skipped="0" time="1.5">
		<testcase name="test_three" classname="test_b" time="0.4">{failure}</testcase>
	</testsuite>
</testsuites>
"""
FAILURE = '<failure message="Expecting: 1 but was 2&#10;more">detail</failure>'


@pytest.fixture
def real(tmp_path: Path) -> Path:
    """A real workspace in miniature: marker, the local file with a Godot, the GdUnit4 folder."""
    root = tmp_path / "real"
    (root / "tools" / "gdunit4-6.2.2" / "gdUnit4-6.2.2" / "addons").mkdir(parents=True)
    (root / "tools" / "gdunit4-6.2.2" / ".gds-installed").write_text("stamp", encoding="utf-8")
    (root / workspace.MARKER).write_text("marker\n", encoding="utf-8")
    (root / workspace.LOCAL_FILE).write_text(f'[tools]\ngodot = "{(root / GODOT).as_posix()}"\n', encoding="utf-8")
    (root / GODOT).write_text("", encoding="utf-8")
    return root


@pytest.fixture
def kit(tmp_path: Path) -> Path:
    """The parts of a kit the command reads: the pinned tools, a template, the script check's script."""
    folder = tmp_path / "kit"
    (folder / scripts.SCRIPT).parent.mkdir(parents=True)
    (folder / scripts.SCRIPT).write_text("extends SceneTree\n", encoding="utf-8")
    (folder / "templates" / "tiny").mkdir(parents=True)
    (folder / "templates" / "tiny" / "template.toml").write_text(
        'title = "Tiny"\ndescription = "d"\ndefault_description = "d"\n', encoding="utf-8"
    )
    shutil.copyfile(KIT / "tools.toml", folder / "tools.toml")
    return folder


@pytest.fixture
def base(tmp_path: Path) -> Path:
    """Where the throwaway workspaces are made (the system temp folder in real use), with a neighbour that must live."""
    folder = tmp_path / "temp"
    (folder / "someone-elses-game").mkdir(parents=True)
    (folder / "someone-elses-game" / "keep.txt").write_text("mine", encoding="utf-8")
    return folder


@pytest.fixture(autouse=True)
def no_layout_rules(monkeypatch):
    """The fake game is not a Godot project; its layout is `gds check layout`'s own tests."""
    monkeypatch.setattr(layout, "check", lambda project: [])


def fake_maker(made: list[Path] | None = None):
    def make(kit: Path, root: Path, name: str, template: str) -> Path:
        game = root / "repos" / name
        (game / "game" / "tests").mkdir(parents=True)
        (game / "game" / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        if made is not None:
            made.append(game)
        return game

    return make


class FakeGodot:
    """Answers each command like the pinned Godot would: the import, the script check, and a GdUnit4 run that writes
    its report into the folder after `-rd`."""

    def __init__(self, gdunit_code: int = 0, failure: bool = False, during=None, parsed: int = 3) -> None:
        self.gdunit_code, self.failure, self.during, self.parsed = gdunit_code, failure, during, parsed
        self.calls: list[list[str]] = []

    def __call__(self, cmd, cwd, timeout):
        cmd = list(cmd)
        self.calls.append(cmd)
        if template_test.GDUNIT_SCRIPT in cmd:
            if self.during:
                self.during(cwd)
            report = Path(cmd[cmd.index("-rd") + 1]) / "report_1"
            report.mkdir(parents=True)
            failures = "1" if self.failure else "0"
            (report / "results.xml").write_text(
                REPORT.format(failures=failures, failure=FAILURE if self.failure else ""), encoding="utf-8"
            )
            return self.gdunit_code, "Overall Summary\n"
        if "-s" in cmd:
            return 0, f"PARSED: {self.parsed} script(s), 0 failed\n"
        return 0, ""

    def gdunit(self) -> list[str]:
        return next(c for c in self.calls if template_test.GDUNIT_SCRIPT in c)


def run(kit, real, base, godot=None, **options):
    lines: list[str] = []
    result = template_test.run_template_test(
        kit,
        real,
        "tiny",
        runner=godot or FakeGodot(),
        maker=options.pop("maker", fake_maker()),
        base=base,
        log=lines.append,
        **options,
    )
    return result, lines


def throwaways(base: Path) -> list[Path]:
    return sorted(p for p in base.iterdir() if p.is_dir() and p.name.startswith(template_test.PREFIX))


def test_the_workspace_is_a_new_folder_of_its_own_outside_the_real_one(kit, real, base):
    seen = []
    godot = FakeGodot(during=lambda cwd: seen.append(cwd))
    result, _ = run(kit, real, base, godot, keep=True)
    folder = result.workspace
    assert folder.parent == base.resolve()
    assert real.resolve() not in folder.parents
    assert workspace.find_workspace(folder) == folder
    assert (folder / workspace.LOCAL_FILE).read_text(encoding="utf-8") == (real / workspace.LOCAL_FILE).read_text(
        encoding="utf-8"
    )
    assert (folder / "tools" / "gdunit4-6.2.2" / ".gds-installed").is_file()
    assert result.game == folder / "repos" / template_test.GAME_NAME
    assert seen == [result.game / "game"]


def test_the_workspace_is_removed_when_the_suites_pass(kit, real, base):
    result, lines = run(kit, real, base)
    assert result.code == 0
    assert throwaways(base) == []
    assert not any(line.startswith("kept") for line in lines)


def test_the_workspace_is_removed_when_a_suite_fails_and_the_code_is_gdunits(kit, real, base):
    result, lines = run(kit, real, base, FakeGodot(gdunit_code=100, failure=True))
    assert result.code == 100
    assert throwaways(base) == []
    assert any("FAIL tests/test_b.gd" in line for line in lines)
    assert any("test_three: Expecting: 1 but was 2" in line for line in lines)


def test_the_workspace_is_removed_when_the_scripts_do_not_parse(kit, real, base):
    godot = FakeGodot()

    def broken(cmd, cwd, timeout):
        if "-s" in cmd and template_test.GDUNIT_SCRIPT not in cmd:
            return 1, "PARSE FAIL: res://x.gd\nPARSED: 4 script(s), 1 failed\n"
        return godot(cmd, cwd, timeout)

    result, lines = run(kit, real, base, broken)
    assert result.code == 1
    assert throwaways(base) == []
    assert not godot.calls[1:], "no suite runs when a script does not parse"
    assert any("1 of 4 do not parse" in line for line in lines)


def test_the_workspace_is_removed_when_the_game_cannot_be_made(kit, real, base):
    def broken(kit, root, name, template):
        (root / "repos" / name).mkdir(parents=True)
        raise new_game.NewGameError("no")

    with pytest.raises(new_game.NewGameError):
        run(kit, real, base, maker=broken)
    assert throwaways(base) == []


def test_the_workspace_is_removed_on_an_interrupt(kit, real, base):
    def interrupted(cmd, cwd, timeout):
        raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        run(kit, real, base, interrupted)
    assert throwaways(base) == []


def test_keep_keeps_the_workspace_and_says_where_the_game_is(kit, real, base):
    result, lines = run(kit, real, base, keep=True)
    assert result.game.is_dir() and (result.game / "game" / "project.godot").is_file()
    assert any(line.startswith("kept") and str(result.game) in line for line in lines)
    assert throwaways(base) == [result.workspace]


def test_a_failed_run_keeps_the_log_outside_the_workspace_it_removes(kit, real, base):
    result, _ = run(kit, real, base, FakeGodot(gdunit_code=100, failure=True))
    assert result.log.is_file() and result.log.parent == base
    assert result.log.read_text(encoding="utf-8") == "Overall Summary\n"


def test_two_calls_at_the_same_time_do_not_share_a_folder(kit, real, base):
    inner = {}

    def second_call(cwd):
        inner["first"] = throwaways(base)
        inner["result"], _ = run(kit, real, base, keep=False)
        inner["after_second"] = throwaways(base)

    result, _ = run(kit, real, base, FakeGodot(during=second_call))
    assert result.code == 0 and inner["result"].code == 0
    first = inner["first"]
    assert len(first) == 1
    assert inner["after_second"] == first, "the second call removed only its own folder, not the first's"
    assert throwaways(base) == []
    assert (base / "someone-elses-game" / "keep.txt").read_text(encoding="utf-8") == "mine"


def test_a_leftover_neighbour_with_the_same_prefix_is_not_the_calls_to_remove(kit, real, base):
    other = base / f"{template_test.PREFIX}someone-elses"
    other.mkdir()
    (other / "game.txt").write_text("another agent's game", encoding="utf-8")
    result, _ = run(kit, real, base)
    assert result.code == 0
    assert (other / "game.txt").is_file()


def test_nothing_that_is_not_a_throwaway_is_removed(base):
    with pytest.raises(template_test.TemplateTestError):
        template_test.remove_throwaway(base / "someone-elses-game")
    assert (base / "someone-elses-game" / "keep.txt").is_file()


def test_a_temporary_folder_inside_the_real_workspace_is_refused(kit, real):
    inside = real / "scratch"
    inside.mkdir()
    with pytest.raises(template_test.TemplateTestError, match="inside the workspace"):
        run(kit, real, inside)
    assert list(inside.iterdir()) == []


def test_clean_finds_the_throwaway_of_a_game_and_refuses_other_paths(kit, real, base, tmp_path):
    result, _ = run(kit, real, base, keep=True)
    assert template_test.throwaway_of(result.game / "game") == result.workspace
    with pytest.raises(template_test.TemplateTestError):
        template_test.throwaway_of(base / "someone-elses-game")
    with pytest.raises(template_test.TemplateTestError):
        template_test.throwaway_of(real)


def test_an_unknown_template_fails_before_anything_is_made(kit, real, base):
    with pytest.raises(new_game.NewGameError, match="no template"):
        template_test.run_template_test(kit, real, "nope", base=base, runner=FakeGodot(), maker=fake_maker())
    assert throwaways(base) == []


def test_the_command_is_the_one_ci_runs_with_a_suite_per_dash_a(kit, real, base):
    godot = FakeGodot()
    run(kit, real, base, godot, suites=["tests/core/test_a.gd", "test_b.gd", "res://tests/x/test_c.gd"])
    cmd = godot.gdunit()
    assert cmd[1:4] == ["--headless", "--path", cmd[3]]
    assert cmd[cmd.index("-s") + 1] == template_test.GDUNIT_SCRIPT
    assert [cmd[i + 1] for i, c in enumerate(cmd) if c == "-a"] == [
        "res://tests/core/test_a.gd",
        "res://tests/test_b.gd",
        "res://tests/x/test_c.gd",
    ]
    assert {"-c", "--ignoreHeadlessMode", "--verbose"} <= set(cmd)
    report_dir = Path(cmd[cmd.index("-rd") + 1])
    assert Path(cmd[3]) not in report_dir.parents, "the reports go outside the project"


def test_all_suites_are_res_tests_as_in_ci(kit, real, base):
    godot = FakeGodot()
    run(kit, real, base, godot)
    cmd = godot.gdunit()
    assert [cmd[i + 1] for i, c in enumerate(cmd) if c == "-a"] == ["res://tests"]
    assert cmd[cmd.index("--fixed-fps") + 1] == str(template_test.CI_FIXED_FPS)


def test_the_tool_and_ci_run_the_suites_at_the_same_clock():
    ci = (KIT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    gdunit_lines = [line for line in ci.splitlines() if "GdUnitCmdTool.gd" in line and "template-check" in line]
    assert gdunit_lines, "ci.yml no longer runs the template suites the way this test reads it"
    for line in gdunit_lines:
        assert f"--fixed-fps {template_test.CI_FIXED_FPS} " in line + " ", line


def test_real_clock_drops_the_flag(kit, real, base):
    godot = FakeGodot()
    run(kit, real, base, godot, fixed_fps=None)
    assert "--fixed-fps" not in godot.gdunit()


def test_fixed_fps_and_the_pass_throughs_reach_the_right_program(kit, real, base):
    godot = FakeGodot()
    run(
        kit,
        real,
        base,
        godot,
        fixed_fps=60,
        godot_args=template_test.split_args("--audio-driver Dummy"),
        gdunit_args=template_test.split_args("--selftest"),
    )
    cmd = godot.gdunit()
    assert cmd[cmd.index("--fixed-fps") + 1] == "60"
    assert cmd.index("--fixed-fps") < cmd.index("-s"), "Godot's own flags come before the script"
    assert cmd.index("--audio-driver") < cmd.index("-s")
    assert cmd[-1] == "--selftest"


def test_a_run_that_ran_no_suite_is_a_failure_even_when_gdunit_exits_zero(kit, real, base):
    def silent(cmd, cwd, timeout):
        if template_test.GDUNIT_SCRIPT in cmd:
            return 0, "nothing\n"
        return FakeGodot()(cmd, cwd, timeout)

    result, lines = run(kit, real, base, silent, suites=["tests/missing.gd"])
    assert result.code == 1
    assert any("no suite ran" in line for line in lines)


def test_a_leak_in_the_log_fails_the_run_as_it_does_in_ci(kit, real, base):
    godot = FakeGodot()

    def leaking(cmd, cwd, timeout):
        code, output = godot(cmd, cwd, timeout)
        return (
            (code, output + "ObjectDB instances leaked at exit\n")
            if template_test.GDUNIT_SCRIPT in cmd
            else (code, output)
        )

    result, _ = run(kit, real, base, leaking)
    assert result.code == 1


def test_each_suite_is_printed_with_its_cases_and_time(kit, real, base):
    _, lines = run(kit, real, base)
    assert "  ok   tests/core/test_a.gd  2 cases, 0 failures, 0.5 s" in lines
    assert "  ok   tests/test_b.gd  1 cases, 0 failures, 1.5 s" in lines
    assert any(line.startswith("gdunit    exit 0: 2 suites, 3 cases, 0 failed") for line in lines)


def test_game_makes_an_imported_game_and_keeps_its_workspace(kit, real, base):
    godot = FakeGodot()
    game = template_test.make_game(kit, real, "tiny", runner=godot, maker=fake_maker(), base=base, log=lambda _: None)
    assert game.is_dir() and throwaways(base) == [game.parent.parent]
    assert godot.calls[0][-1] == "--import"
    template_test.remove_throwaway(template_test.throwaway_of(game))
    assert throwaways(base) == []


def test_game_removes_its_workspace_when_the_import_fails(kit, real, base):
    with pytest.raises(template_test.TemplateTestError, match="import failed"):
        template_test.make_game(
            kit, real, "tiny", runner=lambda c, d, t: (1, "boom"), maker=fake_maker(), base=base, log=print
        )
    assert throwaways(base) == []


def test_the_command_line_runs_the_test_and_returns_gdunits_code(monkeypatch, kit, real):
    seen = {}

    def fake(kit_, real_, name, **options):
        seen.update(name=name, **options)
        return template_test.Result(code=100)

    monkeypatch.setattr(workspace, "require_workspace", lambda *a: real)
    monkeypatch.setattr(workspace, "kit_checkout", lambda: kit)
    monkeypatch.setattr(template_test, "run_template_test", fake)
    code = cli.main(
        ["template", "test", "tiny", "--suite", "tests/a.gd", "--suite", "tests/b.gd", "--keep", "--fixed-fps", "60"]
        + ["--godot-args", "--audio-driver Dummy", "--gdunit-args=--selftest"]
    )
    assert code == 100
    assert seen["name"] == "tiny" and seen["suites"] == ["tests/a.gd", "tests/b.gd"] and seen["keep"]
    assert seen["fixed_fps"] == 60
    assert seen["godot_args"] == ["--audio-driver", "Dummy"] and seen["gdunit_args"] == ["--selftest"]


def test_cli_defaults_to_the_ci_clock_and_real_clock_opts_out(kit, real, monkeypatch):
    seen = []

    def fake(*a, **kw):
        seen.append(kw["fixed_fps"])
        return template_test.Result(code=0)

    monkeypatch.setattr(workspace, "require_workspace", lambda *a: real)
    monkeypatch.setattr(workspace, "kit_checkout", lambda: kit)
    monkeypatch.setattr(template_test, "run_template_test", fake)
    cli.main(["template", "test", "tiny"])
    cli.main(["template", "test", "tiny", "--real-clock"])
    assert seen == [template_test.CI_FIXED_FPS, None]


def test_the_real_new_game_makes_the_game_from_the_working_tree(tmp_path, real, base, monkeypatch):
    """Not a fake maker: `gds new game --local` in the throwaway workspace, from a kit whose template has a change that
    no commit holds."""
    for key, value in {
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "GIT_CONFIG_GLOBAL": str(tmp_path / "gitconfig"),
        "GIT_CONFIG_SYSTEM": str(tmp_path / "gitconfig"),
    }.items():
        monkeypatch.setenv(key, value)
    copy = tmp_path / "wholekit"
    for rel in ("templates/repo", "templates/game", "templates/3d-blank", ".claude/agents", ".github/scripts"):
        shutil.copytree(KIT / rel, copy / rel, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    for rel in ("workspace.toml", "tools.toml", ".pre-commit-config.yaml", scripts.SCRIPT.as_posix()):
        (copy / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(KIT / rel, copy / rel)
    (copy / "templates" / "3d-blank" / "game" / "tests" / "test_uncommitted.gd").write_text(
        "extends GdUnitTestSuite\n", encoding="utf-8"
    )
    seen = []
    godot = FakeGodot(during=lambda cwd: seen.append((cwd / "tests" / "test_uncommitted.gd").is_file()))
    result = template_test.run_template_test(
        copy, real, "3d-blank", runner=godot, base=base, log=lambda _: None, keep=True
    )
    assert result.code == 0 and seen == [True]
    assert (result.game / ".git").exists()
    assert (real / "repos").exists() is False, "nothing was written into the real workspace"
    assert subprocess.run(["git", "-C", str(result.game), "status", "--porcelain"], capture_output=True).returncode == 0
    template_test.remove_throwaway(result.workspace)
