"""The skip allowlist (kit #797): an unlisted skip fails the run, a listed one passes, a listed one that ran is stale,
and every entry of the real file names a test that exists."""

from __future__ import annotations

import ast
import subprocess
import sys
from pathlib import Path

import pytest
from skip_allowlist import Entry, judge, key, load

HERE = Path(__file__).resolve().parent
ALLOWLIST = HERE / "allowed_skips.toml"


def test_key_drops_the_folder_and_the_parameters():
    assert key("tests/test_hold.py::test_the_step_itself[true-0-carries]") == "test_hold.py::test_the_step_itself"
    assert key("python/tests/test_x.py::test_y") == "test_x.py::test_y"
    assert key("tests/test_x.py") == "test_x.py"


def test_a_listed_skip_passes_and_an_unlisted_one_is_named_with_its_reason():
    entries = [Entry("test_a.py::test_one", ("win32",), "a Windows call")]
    assert judge(entries, {"test_a.py::test_one": "x"}, set(), "win32") == []
    problems = judge(entries, {"test_a.py::test_two": "the pinned Godot is not installed"}, set(), "win32")
    assert problems == [
        "test_a.py::test_two skipped and is not on the allowlist for win32: the pinned Godot is not installed"
    ]


def test_an_entry_allows_only_its_own_platforms():
    entries = [Entry("test_a.py::test_one", ("linux", "darwin"), "a Windows call")]
    assert judge(entries, {"test_a.py::test_one": "x"}, set(), "darwin") == []
    assert len(judge(entries, {"test_a.py::test_one": "x"}, set(), "win32")) == 1


def test_an_entry_whose_test_ran_on_its_platform_is_stale():
    entries = [Entry("test_a.py::test_one", ("win32",), "a Windows call")]
    assert judge(entries, {}, {"test_a.py::test_one"}, "win32") == [
        "test_a.py::test_one is on the allowlist for win32 but ran: remove the entry or the platform"
    ]
    assert judge(entries, {}, {"test_a.py::test_one"}, "linux") == []  # not this platform's entry
    assert judge(entries, {}, set(), "win32") == []  # not collected in this run (a run of one file)


def test_an_entry_without_a_reason_is_refused(tmp_path):
    path = tmp_path / "skips.toml"
    path.write_text('[[skip]]\ntest = "test_a.py::test_one"\nplatforms = ["win32"]\nreason = " "\n', encoding="utf-8")
    with pytest.raises(ValueError, match="reason"):
        load(path)


def test_every_entry_of_the_real_file_names_a_test_that_exists():
    entries = load(ALLOWLIST)
    assert entries
    for entry in entries:
        file, _, function = entry.test.partition("::")
        tree = ast.parse((HERE / file).read_text(encoding="utf-8"))
        names = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        assert function in names, f"{entry.test} is not a test"
        assert set(entry.platforms) <= {"win32", "linux", "darwin"}, entry


def test_a_real_run_fails_on_an_unlisted_skip_and_passes_with_its_entry(tmp_path):
    """The hooks in a pytest of their own: the exit code is what CI judges."""
    (tmp_path / "conftest.py").write_text(
        f"import sys\nsys.path.insert(0, {str(HERE)!r})\n"
        "from skip_allowlist import pytest_addoption, pytest_collectreport, pytest_runtest_logreport, "
        "pytest_sessionfinish, pytest_terminal_summary  # noqa: F401\n",
        encoding="utf-8",
    )
    (tmp_path / "test_some.py").write_text(
        "import pytest\n\ndef test_runs():\n    pass\n\ndef test_skips():\n    pytest.skip('no tool here')\n",
        encoding="utf-8",
    )
    allowlist = tmp_path / "skips.toml"

    def run() -> subprocess.CompletedProcess[str]:
        cmd = [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "--allowed-skips", str(allowlist)]
        return subprocess.run(cmd, cwd=tmp_path, capture_output=True, text=True, timeout=120)

    allowlist.write_text("", encoding="utf-8")
    unlisted = run()
    assert unlisted.returncode == 1, unlisted.stdout
    assert "test_some.py::test_skips skipped and is not on the allowlist" in unlisted.stdout
    assert "no tool here" in unlisted.stdout

    platform = sys.platform
    allowlist.write_text(
        f'[[skip]]\ntest = "test_some.py::test_skips"\nplatforms = ["{platform}"]\nreason = "no tool here"\n',
        encoding="utf-8",
    )
    assert run().returncode == 0

    allowlist.write_text(
        f'[[skip]]\ntest = "test_some.py::test_runs"\nplatforms = ["{platform}"]\nreason = "stale"\n'
        f'[[skip]]\ntest = "test_some.py::test_skips"\nplatforms = ["{platform}"]\nreason = "no tool here"\n',
        encoding="utf-8",
    )
    stale = run()
    assert stale.returncode == 1
    assert "test_some.py::test_runs is on the allowlist" in stale.stdout
