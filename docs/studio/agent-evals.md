# Agent evals

<!-- new section: nothing measured how good an agent's work is, so a change to an agent's page or to the docs it reads
could not be shown to help (gdstudio #774) -->

Small fixed tasks with numbers to meet, which an agent runs so that a change to its page (`.claude/agents/*.md`) or to
the docs it reads can be measured: run the same task before and after the change, at the same model, and compare the
numbers. Each task lives in the kit's `evals/` folder, with a brief, the inputs it starts from and a check that judges
the delivery through the pinned tools, headless. Every agent that does work has at least one task, so the model and
the effort each agent runs at can be chosen from runs rather than guessed (kit #893, #898).

## The tasks {#tasks}

| Task | Agent | What it delivers | What the check measures |
| --- | --- | --- | --- |
| `model-crate` | `blender-artist` | a 1 m supply crate | size, origin, applied transform, open edges, inside-out parts, a shape that is not a box, 120 to 500 triangles ([Modelling](../tools/blender/modelling.md)) |
| `uv-palette` | `blender-artist` | a barrel on a given palette atlas | geometry unchanged, one material on the atlas, nearest filter, every triangle inside one cell and on its part's colour ([UV and texturing](../tools/blender/uv-and-texturing.md)) |
| `rig-humanoid` | `blender-artist` | a blocky humanoid rigged to 17 named bones | bone names and parents, joints within 6 cm, weights (all, at most 4, own part, mirrored), elbow and knee bends ([Rigging](../tools/blender/rigging.md)) |
| `clip-walk` | `blender-artist` | an in-place walk cycle on a given rig | one clip of 1 s, loop seam, hips in place and bobbing, leg and arm swings and phases, arms hanging, feet on the floor ([Animation](../tools/blender/animation.md)) |
| `decimate-boulder` | `blender-artist` | a near and a far level of a 20,480-triangle sculpt | budgets of 2,000 and 500, surface distance, bounds, flat bottom, flipped area, open edges ([Optimisation](../tools/blender/optimisation.md)) |
| `pickup-feature` | `godot-engineer` | pickups and a score in a 3D Blank game | `gds check layout`, gdlint and gdformat, a clean import, its own tests, the task's acceptance suite ([Project conventions](../engines/godot/project-conventions.md)) |
| `moving-platform` | `godot-engineer` | a moving platform component in a 3D Blank game: inspector API, signals, a tuning resource, a scene, tests | the rows of `pickup-feature`, plus how it is built: scripts added, longest script and function, public members without a `##` comment, declarations without a type, allocations in a per-frame function ([GDScript](../engines/godot/gdscript.md)) |
| `arena-layout` | `level-designer` | a 40 m arena scene for the dead to arrive in, built from the template's blocks | the real body's reach by flood fill (no way out, no drop into the void), cover, gates out of sight, the longest sightline, landmark visibility, a navigation mesh that covers the ground ([Map review](../engines/godot/map-review.md)) |
| `lobby-service` | `backend-engineer` | a small HTTP lobby service with tests, a README and a Dockerfile | `ruff` (the kit's pin), its own tests, a contract suite run over HTTP against the started process (auth, validation, races, ports), its log (structured, no token) ([Platform backend](../gamedev/backend.md)) |
| `planted-faults` | `reviewer` | `REVIEW.md` and `findings.json` for a pull request with 13 planted faults | faults found, findings that match none, the verdict ([Pull requests](pull-requests.md#body)) |

Every Blender task also asks for the `build.py` that makes the delivery (the check reruns it and compares) and a
`preview.png` the agent looked at. Every Blender check reads the exported `.glb`, the file Godot gets.

A Godot task is judged by the pinned Godot on a game made from its template; a `service` task by the pinned `ruff`, the
delivery's own `uv run pytest` and a contract suite over HTTP; a `review` task by comparing the reviewer's findings with
an answer key that only the check reads. The numbers of each are in the task's `TASK.md`, which is the agent's brief.

## Running one {#running}

```text
gds eval list
gds eval prepare <task> <folder>                    a fresh folder: the brief (TASK.md) and the inputs
gds eval prompt <task> <folder> --issue <owner/repo>#N
gds eval check <task> <folder>                      the numbers; exit 0 when every one is met
```

(`uv run --project <workspace>/repos/gdstudio/python gds ...`.) Put the folder in the scratch topic of the issue that
changes the page (`<workspace>/scratch/<repo>/<branch>/evals/<task>`). `gds eval prompt` prints the prompt of the run,
the same words every time: the `Issue:` line of that issue, the task's fixed `Read:` lines, and where the brief is.
The coordinator passes it to the Agent tool as it is, with the task's agent type, in the background; several tasks run
at once.

A run records, in the eval folder:

- `result.json`: the rows of the last check, each with its value, its limit and whether it was met;
- `checks.jsonl`: one line per `gds eval check`, so the number of checks a run needed and what the first one met are
  known.

A `service` task's acceptance suite (`evals/service/<task>/acceptance/test_acceptance.py`) is run by `gds eval check`
itself, with `python -m unittest -v` in the delivery's folder (`gds_tools/eval_service.py`), not by pytest: the kit's
`pytest` never collects it ([The command](kit-tests.md#command)), and a case's failure is read from unittest's output
into the check's rows (gdstudio #1189).

- **Approach:** Open the pull request of the branch the evals run from (its `gds` and checks) before starting the
  runs, or run them from a branch that is merged. **Watch out for:** the stop hook holds back a task agent while any kit
  worktree has commits and no pull request, so a run that finished its work was held for the coordinator's branch and
  ended with a note about the branch instead of its report. **Seen:** gdstudio #774, 2026-11-07 (the `decimate-boulder`
  baseline run; its numbers were read from `result.json` and `checks.jsonl`).

From the Agent tool's completion, the coordinator adds the agent's tokens, tool calls and wall time, and reads its
report's `Docs gaps:`: an eval run edits no docs, so what the docs lacked comes back as gaps, and the coordinator puts
each into its topic section.

## Comparing two runs {#comparing}

A change is better when, at the same model and the same task, it meets as many rows, on fewer checks, with fewer
tokens, tool calls and minutes, and its `Docs gaps:` shrink. One run is one sample: a page change worth keeping shows on
every task it touches, and a difference of a few thousand tokens on one run is noise. The brief, the inputs and the
`Read:` lines of a task stay fixed between the runs being compared; a task whose brief or check changes starts a new
baseline.

## Baseline {#baseline}

The first run of each task, 2026-11-07, with the agent pages as they were before gdstudio #774 changed them
(`blender-artist` on Opus 5.5 at high effort, `godot-engineer` on Sonnet 5.5 at high effort). Every run met every row,
so the measure that tells later runs apart is the cost and the gaps. `checks.jsonl` was added while these runs
worked, so how many checks each needed is not in this table; later runs record it:

| Task | Rows met | Tokens | Tool calls | Minutes | What the docs lacked (its `Docs gaps:`) |
| --- | --- | --- | --- | --- | --- |
| `model-crate` | 16 of 16 | 82,140 | 16 | 3.1 | bmesh extrude keeps its face; inset needs even offset; flat colours or the atlas for a prop |
| `uv-palette` | 10 of 10 | 68,884 | 12 | 1.8 | no general palette recipe; the cell formula only on the weapons page; `use_nodes` deprecated |
| `rig-humanoid` | 17 of 17 | 90,335 | 18 | 4.5 | no page on rigging from scratch; weights at seams between pieces |
| `clip-walk` | 16 of 16 | 85,688 | 11 | 3.5 | no walk from nothing on a plain rig; the importer's stray icosphere; Blender 5 actions have no `fcurves` |
| `decimate-boulder` | 21 of 21 (the first two checks ran before its preview existed) | 109,586 | 30 | 8.8 | decimating a static prop: snap the bottom back, collapse shrinks the bounds, folds at 500 triangles; shading a decimated rock; the brief's triangle count was wrong |
| `pickup-feature` (measured with the check before kit #898, which counted the template's own tests as the agent's; run it again for a baseline) | 8 of 8 | 82,362 | 16 | 2.5 | the GdUnit command line was not on a page it read; testing an `Area3D` trigger and a spin |

The gaps went into the topic sections in the same pull request ([Blender](../tools/blender/index.md)); the next run
of each task, with the changed agent pages, is measured against this table.

## A task {#a-task}

`evals/<kind>/<task>/TASK.md` holds TOML front matter between `+++` lines (`agent`, `kind`, `deliver`, `read` and, for
a Godot task, `template`; an optional `[limits]` table of numbers the check uses) and then the brief, whose `#` heading
is the task's title. The `read` lines name sections that exist (a test checks them). The kind says what else the folder
holds and how it is checked:

| Kind | The folder holds | The check |
| --- | --- | --- |
| `blender` | `prepare.py` (writes the inputs, in the pinned Blender), `check.py` (measures the delivery, with `evals/blender/evallib.py`) | rows from the exported `.glb` |
| `godot` | `acceptance/` (a GdUnit4 suite) and/or `probe/probe.gd` (a headless `SceneTree` script that prints `EVAL_ROW {json}` lines), and a `[limits]` table for the quality rows | `gds check layout`, gdlint and gdformat, a clean import, new test suites (and test cases, with `min_test_cases`), the acceptance suite, the probe's rows, the quality rows |
| `service` | `acceptance/test_acceptance.py` (standard library only: it talks HTTP to the started process) | `ruff`, the delivery's own tests, the started process, the acceptance cases, its log |
| `review` | `inputs/` (what the reviewer gets: the description, the diff, the files after the change, the rules) and `faults.toml` (the answer key) | findings matched to faults by file and line |

A Godot task's `acceptance/` suite is copied into the game's `tests/eval_acceptance/`, run with the game's own suites and
removed; its probe is copied to `tests/eval_probe/`, run and removed. `gds eval prepare` makes the game the way `gds
new game` does for what a suite relies on: the template, GdUnit4 and the kit's own addons (`gds_ui`, which the
template's `project.godot` registers as an autoload).

- **Approach:** Prove a new check against a reference solution kept in scratch (never committed, so an agent cannot
  copy it) and against a wrong one, before any agent runs the task. **Watch out for:** a check that cannot be met, or
  that passes anything, measures nothing: the first crate check counted parts that touch as non-manifold, the first
  boulder was flat-shaded so its decimation tore, and a reference walk with its arms in step with its legs passed every
  row except the phase. **Seen:** gdstudio #774, 2026-11-07 (fix: each check passed a reference and failed a broken
  one before the baseline).
- **Approach:** Keep a test that runs every Godot task's acceptance suite and probe against the bare template
  (`test_evals.py`): every case is discovered and run, and the bare template fails them. Count the delivery's new tests
  against the template's own files. **Watch out for:** `pickup-feature` stopped parsing after the template rework (a
  local called `before` shadows a GdUnit4 function) and its check ran 0 acceptance cases; `gds eval prepare` did not
  copy the kit's `gds_ui` addon, which the template's autoload names, so a fresh game printed `ERROR`; and "new test
  suites" counted the template's own files. **Seen:** gdstudio #898, 2026-11-10 (fix: the local renamed, the addons
  copied, new suites are those the template lacks, the test added).
- **Approach:** Name every number of a probe and its limit in the brief, and print where the first miss is (the cell and
  heading of the longest line, the gate the body cannot walk to), never what the answer is. **Watch out for:** a limit
  tuned only to the reference: sightlines along eight directions from every cell were met by no layout of a dozen
  cover pieces, because a diagonal lane across 40 m is not a sniper lane. **Seen:** gdstudio #898, 2026-11-10 (fix: four
  axis directions for the longest line and a share of seeded random pairs for openness, the reference iterated until
  every limit had a margin).

## The quality rows {#quality}

<!-- new section: a correctness suite does not show how a delivery is built, and the code-quality rows of the larger
Godot task needed a home (kit #898) -->

The `[limits]` table of a Godot task turns on rows that read the scripts the delivery added (the ones the template does
not have, outside `addons/`, `tests/` and `tools/`; `gds_tools/eval_quality.py`): `min_scripts`, `max_script_lines`,
`max_function_lines`, `max_undocumented` (public signals, exports, functions, enums and variables, and the script's own
description, without a `##` comment), `max_untyped` (variables, parameters and return types), `max_hot_allocations`
(`.new(`, an array or dictionary literal, `str(`, a node list fetched or a lambda inside `_process`, `_physics_process`
or `_integrate_forces`) and `min_test_cases`. They are line-based reads, fixed and the same for every run; a function is
a `func` at the left margin and an inner class is not looked into.

## Calibration {#calibration}

<!-- new section: a new check is trusted only once it has scored a good delivery and a wrong one as expected; the
numbers of those runs are kept so a changed check can be compared (kit #898) -->

How the checks of the tasks of kit #898 scored the reference deliveries kept in scratch (never committed) and
deliveries made wrong on purpose, 2026-11-10, before any agent ran them. No agent has run these tasks yet: the model and
effort runs of kit #893 give their baseline.

| Task | Delivery | Rows met | What failed, as it should |
| --- | --- | --- | --- |
| `pickup-feature` | the delivery of the failed Opus 5.5 run | 8 of 8 | (before the fix: 0 acceptance cases run) |
| `moving-platform` | reference | 15 of 15 | |
| `moving-platform` | no pause, speed 1.5 times too fast | 13 of 15 | 5 acceptance cases, 1 case of its own tests |
| `moving-platform` | no `##` comments, an untyped `_physics_process`, an array in it | 7 of 15 | the script no longer parses (an unused variable is an error), so 0 acceptance cases run; the documentation, type and allocation rows fail |
| `arena-layout` | reference (12 cover pieces, 4 gates, a tower, 4 spines, a baked mesh) | 32 of 32 | |
| `arena-layout` | stairs up to a wall top | 1 row fails | 156 places at a drop into the void |
| `arena-layout` | floor, walls and tower only | 6 rows fail | no cover, gates in sight, a 37.5 m line, a mean run of 18 m, 87% of pairs see each other |
| `lobby-service` | reference (standard library) | 13 of 13 | |
| `lobby-service` | no lock in `join`, no token on `GET` | acceptance fails the race and the auth case | its own race test fails too |
| `lobby-service` | the token written to the log | 195 log lines carry it | |
| `planted-faults` | one finding on each of the 13 faults | 5 of 5 | |
| `planted-faults` | 5 faults and one vague finding | 4 of 5 | 5 faults found, 9 needed |
| `planted-faults` | 8 faults, the 4 traps and 2 repeats | 3 of 5 | 8 faults found, 9 needed; 6 false findings (4 on correct code) |

## What the evals do not see {#unseen}

Whether the result looks right in the game's style (the check reads numbers, the preview is for the agent), how the
asset behaves in Godot (only the Godot task runs Godot), and a task the brief does not describe. A reviewer still
judges those ([Agents](agents.md#structure-reviews)).
