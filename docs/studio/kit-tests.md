# The kit's tests

<!-- new section: hooks.md lists what each test file covers and new-game.md holds the speed entries of the new-game
tests; no page said how `pytest python/tests` runs on a machine and in CI, or what its shared parts are -->

The kit's Python (`gds`, the hooks, the scripts under `.github/scripts/`) is tested by `pytest python/tests`. This page
is how that run works: the command here and in CI, the workers, the repositories the tests share, the skips CI
allows and the tripwire against real services. What each file covers is in [Hooks: tests](hooks.md#tests) and beside
the code it tests; a template's own GdUnit4 suites are another run ([Proving a new game](../engines/godot/new-game.md#proof)).

## The command {#command}

```text
uv run --project python pytest python/tests -q -n auto --maxprocesses=4 --dist loadfile
uv run --project python ruff check python && uv run --project python ruff format --check python
```

CI's `test` job runs the same on Ubuntu, Windows and macOS, with `-rs --durations=30 --allowed-skips
python/tests/allowed_skips.toml` added (`.github/workflows/ci.yml`). `pytest-xdist` is in the `dev` group of
`python/pyproject.toml`, so `uv run` has it; one file stays on one worker (`--dist loadfile`), since the fixtures a
file makes once are shared by its tests. Four workers at most, here as in CI: the machine is shared
([Sharing the machine](workspace.md#shared-machine)). A run of one file while you work needs no workers:
`uv run --project python pytest python/tests/test_brief.py -q`. A bare `pytest` from the root collects the same set:
the root `pytest.ini` names `python/tests` (`testpaths`) and repeats `python/pyproject.toml`'s warning filters
(`python/tests/test_root_pytest_config.py` keeps the two in step), so the eval acceptance suites under `evals/` run
only through `gds eval check` ([Agent evals](agent-evals.md#running)).

Run it from the checkout whose code you changed (your worktree), with `--project` naming that checkout's `python`
folder: `uv run --project <another checkout>/python pytest` tests the other checkout's code.

- **Approach:** Name `python/tests` on every full run, as above, the form CI runs; a bare `pytest` from the root
  collects the same set only because of the root `pytest.ini`, so keep it in step with `python/pyproject.toml`.
  **Watch out for:** before that file, a bare `pytest` from the root also collected the eval tasks' acceptance suites
  under `evals/`, which start services and failed with socket timeouts unrelated to the change, so the run looked
  red when the kit was fine. **Seen:** gdstudio #1145, 2026-11-11, after a merge of main (fix: the root `pytest.ini`
  and `test_root_pytest_config.py`, #1189, PR #1196).

## What the tests share {#shared}

- **Repositories made once.** A test that needs "a repository with a commit and a remote" copies a seed made once a
  session (`python/tests/git_seed.py`: `slim` drops git's sample hooks, `relocate` copies the seed and rewrites the
  absolute paths git wrote into each `config`, with no git process). The seeds are `scope="session"` fixtures in
  `python/tests/conftest.py` (`small_kit_seed`, `small_git_kit_seed`); a test gets its own copy (`small_kit`,
  `small_git_kit`) and may write to it.
- **A small kit, not the real templates.** The new-game tests build a kit with `templates/repo/` and a few-file stand-in
  for 3D Blank (`python/tests/new_game_kit.py`, `python/tests/fixtures/new_game_templates/`); only a test about what a
  real template holds reads a game made once from it (`real_game`, `real_third_person_game`), and never writes to it
  ([Adding a template](../engines/godot/new-game.md#adding-a-template) has the measured cost).
- **No real services.** The `no_real_services` fixture makes any `gh`, PowerShell or process listing that reaches
  `subprocess.run` fail the test; the suites that delete or post use it, so a forgotten fake fails instead of acting.
- **Recorded answers.** `gh` answers live as JSON under `python/tests/fixtures/` (issues, pull requests, briefs).
- **Approach:** Keep an issue or pull request body a test reads as a `.txt` file under `python/tests/fixtures/`
  (`pr_bodies/`, `issue_bodies/`). **Watch out for:** saved as `.md`, a GitHub body fails markdownlint in pre-commit
  (no top heading, long lines, a `#904` line read as a heading), and rewrapping it changes the text the test is about.
  **Seen:** gdstudio #1133, 2026-11-11 (#909's body, renamed to `.txt`).

## Skips {#skips}

A test may skip in CI only when `python/tests/allowed_skips.toml` names it with its platforms and the reason
(`python/tests/skip_allowlist.py`, kit #797): a skip it does not name fails the run, and so does an entry whose test
ran on a platform it names. Every entry is a platform fact (a junction is a Windows folder link); a tool a test needs is
installed on the runner instead. A local run without `--allowed-skips` reports skips and does not judge them.

- **Approach:** When a new test runs a pinned tool, add the tool to the Windows test job's `--fetch` in
  `.github/workflows/ci.yml` and an entry for the other platforms (one per test, without its `[parameter]`), then run
  the test file with `--allowed-skips python/tests/allowed_skips.toml` before the push. **Watch out for:** on a machine
  with the tool the test runs and passes, so nothing local shows the skip that fails all three CI test jobs.
  **Seen:** gdstudio #1190, 2026-11-11 (the pinned-ffmpeg clip test; fix: ffmpeg fetched on windows-2025, linux and
  darwin allowed).
- **Approach:** A test that runs a workflow's `run:` script skips on every platform but the runner's (`sys.platform !=
  "linux"` for ubuntu), with an allowlist entry for win32 and darwin, and the file is run with `--allowed-skips` before
  the push. **Watch out for:** macOS's `/bin/bash` is 3.2, so bash 4 syntax such as `${var,,}` fails there with `bad
  substitution`; a skip copied from a win32-only test let the macOS job run the step and failed it, and the Windows job
  failed on the skips the allowlist did not name. **Seen:** gdstudio #1302, 2026-11-11 (fix: `test_main_green.py`
  runs its bash cases on Linux only, three allowlist entries); gdstudio #1483, 2026-11-13 (a new bash case added
  beside those three had no entry of its own, and a run under Git Bash passed it locally; fix: a fourth entry).

## Speed {#speed}

- **Approach:** Count the processes a test starts, not only its seconds: make a repository once a session and copy it,
  share one run of a command between the tests that only read it, and leave out the step a test is not about (the full
  entry is under [Adding a template](../engines/godot/new-game.md#adding-a-template)). **Watch out for:** on Windows a
  git process costs 30 to 110 ms and a copied file 1 ms, and a loaded machine moves wall time by 2x, so a timing taken
  once says little. **Seen:** gdstudio #918 and #945, 2026-11-10 (`pytest python/tests` 266 s to 157 s serial, 57 s on
  four workers; the Windows job had been the longest in CI at 13 min 35 s).
