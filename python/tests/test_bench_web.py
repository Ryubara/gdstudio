"""`gds template bench-web`: a template's bench scene exported to the web in a throwaway game.

What a bench author did by hand before (docs/engines/godot/web-probes.md#bench-web): swap `run/main_scene` to the
bench, take `tools/*` out of the Web preset's exclude filter, export with the pinned Godot. The edits are tested on the
real template files; Godot is a fake that writes the build files it would."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from gds_tools import bench_web, cli, template_test, workspace

KIT = Path(__file__).resolve().parents[2]
PRESETS = KIT / "templates" / "3d-blank" / "game" / "export_presets.cfg"
PROJECT = KIT / "templates" / "3d-third-person" / "game" / "project.godot"
BENCH = "res://tools/bench/nav_cost_bench.tscn"


@pytest.fixture
def project(tmp_path: Path) -> Path:
    """A game folder with the template's real project and presets files and one bench with its probe."""
    folder = tmp_path / "game"
    (folder / "tools" / "bench").mkdir(parents=True)
    shutil.copyfile(PROJECT, folder / "project.godot")
    shutil.copyfile(PRESETS, folder / "export_presets.cfg")
    (folder / "tools" / "bench" / "nav_cost_bench.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")
    (folder / "tools" / "bench" / "nav_cost_bench.py").write_text("print('probe')\n", encoding="utf-8")
    (folder / "tools" / "bench" / "hold_cost.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")
    return folder


def preset_value(text: str, key: str) -> str:
    return next(line.split("=", 1)[1] for line in text.splitlines() if line.startswith(f"{key}="))


@pytest.mark.parametrize(
    "given",
    ["nav_cost_bench", "nav_cost_bench.tscn", "tools/bench/nav_cost_bench.tscn", BENCH, "tools\\bench\\nav_cost_bench"],
)
def test_a_bench_is_named_by_its_name_its_path_or_its_res_path(project, given):
    assert bench_web.scene_path(project, given) == BENCH


def test_a_bench_that_is_not_there_is_refused_with_the_benches_that_are(project):
    with pytest.raises(bench_web.BenchWebError, match="hold_cost.*nav_cost_bench"):
        bench_web.scene_path(project, "no_such_bench")


def test_the_main_scene_becomes_the_bench_and_nothing_else_changes():
    before = PROJECT.read_text(encoding="utf-8")
    after = bench_web.set_main_scene(before, BENCH)
    assert f'run/main_scene="{BENCH}"' in after
    assert "menu_scene.tscn" not in preset_value(after, "run/main_scene")
    changed = [(a, b) for a, b in zip(before.splitlines(), after.splitlines(), strict=True) if a != b]
    assert len(changed) == 1 and changed[0][0].startswith("run/main_scene=")


def test_a_project_without_a_main_scene_gets_one_in_its_application_section():
    text = '[application]\n\nconfig/name="X"\n\n[rendering]\n\nx=1\n'
    after = bench_web.set_main_scene(text, BENCH)
    application = after.split("[rendering]")[0]
    assert f'run/main_scene="{BENCH}"' in application


def test_a_project_without_an_application_section_is_refused():
    with pytest.raises(bench_web.BenchWebError, match="application"):
        bench_web.set_main_scene("config_version=5\n", BENCH)


def test_the_web_preset_lets_tools_in_and_keeps_the_rest_out():
    after = bench_web.open_tools(PRESETS.read_text(encoding="utf-8"))
    excluded = [p.strip() for p in preset_value(after, "exclude_filter").strip('"').split(",")]
    assert "tools/*" not in excluded
    assert {"tests/*", "addons/gdUnit4/*", "reports/*"} <= set(excluded)


def test_only_the_web_preset_is_opened():
    text = (
        '[preset.0]\n\nname="Linux"\nplatform="Linux"\nexclude_filter="tests/*, tools/*"\n\n'
        '[preset.0.options]\n\nx=1\n\n'
        '[preset.1]\n\nname="Web"\nplatform="Web"\nexclude_filter="tests/*, tools/*"\n'
    )  # fmt: skip
    after = bench_web.open_tools(text)
    linux, web = after.split("[preset.1]")
    assert 'exclude_filter="tests/*, tools/*"' in linux
    assert 'exclude_filter="tests/*"' in web


def test_presets_without_a_web_preset_are_refused():
    with pytest.raises(bench_web.BenchWebError, match="Web"):
        bench_web.open_tools('[preset.0]\n\nname="Linux"\nexclude_filter="tools/*"\n')


def test_prepare_writes_both_files_and_returns_the_bench(project):
    assert bench_web.prepare(project, "nav_cost_bench") == BENCH
    assert f'run/main_scene="{BENCH}"' in (project / "project.godot").read_text(encoding="utf-8")
    assert "tools/*" not in (project / "export_presets.cfg").read_text(encoding="utf-8")


def test_prepare_keeps_the_files_line_endings_lf(project):
    bench_web.prepare(project, "nav_cost_bench")
    for name in ("project.godot", "export_presets.cfg"):
        assert b"\r\n" not in (project / name).read_bytes()


def test_the_probe_is_the_py_beside_the_bench(project):
    assert bench_web.probe_of(project, BENCH) == project / "tools" / "bench" / "nav_cost_bench.py"
    assert bench_web.probe_of(project, "res://tools/bench/hold_cost.tscn") is None


def test_the_probe_runs_under_gds_quiet_with_the_build_and_its_arguments(project, tmp_path):
    kit, build = tmp_path / "kit", tmp_path / "build" / "web"
    cmd = bench_web.probe_command(kit, project / "tools" / "bench" / "nav_cost_bench.py", build, ["4"])
    quiet = cmd.index("quiet")
    assert cmd[:quiet] == ["uv", "run", "--project", str(kit / "python"), "gds"]
    assert cmd[quiet + 1] == "--"
    assert f"playwright=={bench_web.PLAYWRIGHT}" in cmd
    assert cmd[-3:] == [str(project / "tools" / "bench" / "nav_cost_bench.py"), str(build), "4"]


class FakeGodot:
    """The import does nothing; an export writes the pack and the wasm where it was asked to, with `output` as its
    log (one item a call, the last one repeated)."""

    def __init__(self, *outputs: str, write: bool = True) -> None:
        self.outputs, self.write = list(outputs) or [""], write
        self.calls: list[list[str]] = []

    def __call__(self, cmd, cwd, timeout):
        cmd = list(cmd)
        self.calls.append(cmd)
        if "--export-release" not in cmd:
            return 0, ""
        out = Path(cmd[cmd.index("--export-release") + 2])
        if self.write:
            out.parent.mkdir(parents=True, exist_ok=True)
            for suffix in (".html", ".pck", ".wasm"):
                out.with_suffix(suffix).write_bytes(b"x")
        exports = sum("--export-release" in c for c in self.calls)
        return 0, self.outputs[min(exports, len(self.outputs)) - 1]


def test_the_export_is_the_web_preset_into_the_games_build_folder(project, tmp_path):
    godot = FakeGodot()
    build = bench_web.export(Path("godot"), project, godot)
    assert build == project.parent / "build" / "web"
    cmd = godot.calls[-1]
    assert cmd[:4] == ["godot", "--headless", "--path", str(project)]
    assert cmd[cmd.index("--export-release") + 1] == "Web"


def test_an_export_with_an_error_fails_with_the_lines(project):
    with pytest.raises(bench_web.BenchWebError, match="Parse Error"):
        bench_web.export(Path("godot"), project, FakeGodot("ERROR: Parse Error: x\n"))


def test_an_export_whose_only_error_is_the_exit_leak_is_tried_once_more(project):
    godot = FakeGodot("ERROR: 3 resources still in use at exit\n", "ok\n")
    bench_web.export(Path("godot"), project, godot)
    assert sum("--export-release" in c for c in godot.calls) == 2


def test_an_export_that_writes_no_pack_fails(project):
    with pytest.raises(bench_web.BenchWebError, match="index.pck"):
        bench_web.export(Path("godot"), project, FakeGodot(write=False))


@pytest.fixture
def real(tmp_path: Path) -> Path:
    root = tmp_path / "real"
    (root / "tools" / "gdunit4-6.2.2" / "gdUnit4-6.2.2" / "addons").mkdir(parents=True)
    (root / workspace.MARKER).write_text("marker\n", encoding="utf-8")
    (root / workspace.LOCAL_FILE).write_text(f'[tools]\ngodot = "{(root / "godot").as_posix()}"\n', encoding="utf-8")
    (root / "godot").write_text("", encoding="utf-8")
    return root


@pytest.fixture
def kit(tmp_path: Path) -> Path:
    folder = tmp_path / "kit"
    (folder / "templates" / "tiny").mkdir(parents=True)
    (folder / "templates" / "tiny" / "template.toml").write_text(
        'title = "Tiny"\ndescription = "d"\ndefault_description = "d"\n', encoding="utf-8"
    )
    shutil.copyfile(KIT / "tools.toml", folder / "tools.toml")
    return folder


def maker_from(project: Path):
    def make(kit: Path, root: Path, name: str, template: str) -> Path:
        game = root / "repos" / name
        shutil.copytree(project, game / "game")
        return game

    return make


def test_bench_web_exports_in_a_kept_throwaway_game_and_leaves_the_template_alone(kit, real, project, tmp_path):
    base = tmp_path / "temp"
    base.mkdir()
    template_before = (project / "project.godot").read_text(encoding="utf-8")
    lines: list[str] = []
    result = bench_web.run_bench_web(
        kit, real, "tiny", "nav_cost_bench", runner=FakeGodot(), maker=maker_from(project), base=base,
        log=lines.append,
    )  # fmt: skip
    assert result.code == 0 and result.build is not None and (result.build / "index.pck").is_file()
    assert result.build.parent.parent.parent.parent.name.startswith(template_test.PREFIX)
    assert any(str(result.build) in line for line in lines)
    assert (project / "project.godot").read_text(encoding="utf-8") == template_before
    template_test.remove_throwaway(template_test.throwaway_of(result.build))


def test_bench_web_with_run_runs_the_probe_and_removes_the_game(kit, real, project, tmp_path):
    base = tmp_path / "temp"
    base.mkdir()
    probes: list[list[str]] = []

    def probe(cmd):
        probes.append(list(cmd))
        return 3

    result = bench_web.run_bench_web(
        kit, real, "tiny", "nav_cost_bench", run=True, probe_args=["4"], runner=FakeGodot(),
        maker=maker_from(project), base=base, probe_runner=probe, log=lambda _: None,
    )  # fmt: skip
    assert result.code == 3 and len(probes) == 1 and probes[0][-1] == "4"
    assert list(base.iterdir()) == []


def test_run_on_a_bench_without_a_probe_fails_before_the_export(kit, real, project, tmp_path):
    base = tmp_path / "temp"
    base.mkdir()
    godot = FakeGodot()
    result = bench_web.run_bench_web(
        kit, real, "tiny", "hold_cost", run=True, runner=godot, maker=maker_from(project), base=base,
        log=lambda _: None,
    )  # fmt: skip
    assert result.code == 1 and not any("--export-release" in c for c in godot.calls)
    assert list(base.iterdir()) == []


def test_the_command_line_passes_the_bench_and_the_probe_arguments(monkeypatch, kit, real):
    seen = {}

    def fake(kit_, real_, template, scene, **options):
        seen.update(template=template, scene=scene, **options)
        return bench_web.Result(code=0)

    monkeypatch.setattr(workspace, "require_workspace", lambda *a: real)
    monkeypatch.setattr(workspace, "kit_checkout", lambda: kit)
    monkeypatch.setattr(bench_web, "run_bench_web", fake)
    code = cli.main(["template", "bench-web", "tiny", "nav_cost_bench", "--run", "--probe-args", "4"])
    assert code == 0
    assert seen["template"] == "tiny" and seen["scene"] == "nav_cost_bench"
    assert seen["run"] and seen["probe_args"] == ["4"] and not seen["keep"]
