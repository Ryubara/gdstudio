# Agent evals

<!-- new section: nothing measured how good an agent's work is, so a change to an agent's page or to the docs it reads
could not be shown to help (gdstudio #774) -->

Small fixed tasks with numbers to meet, which an agent runs so that a change to its page (`.claude/agents/*.md`) or to
the docs it reads can be measured: run the same task before and after the change, at the same model, and compare the
numbers. Each task lives in the kit's `evals/` folder, with a brief, the inputs it starts from and a check that judges
the delivery through the pinned tools, headless.

## The tasks {#tasks}

| Task | Agent | What it delivers | What the check measures |
| --- | --- | --- | --- |
| `model-crate` | `blender-artist` | a 1 m supply crate | size, origin, applied transform, open edges, inside-out parts, a shape that is not a box, 120 to 500 triangles ([Modelling](../tools/blender/modelling.md)) |
| `uv-palette` | `blender-artist` | a barrel on a given palette atlas | geometry unchanged, one material on the atlas, nearest filter, every triangle inside one cell and on its part's colour ([UV and texturing](../tools/blender/uv-and-texturing.md)) |
| `rig-humanoid` | `blender-artist` | a blocky humanoid rigged to 17 named bones | bone names and parents, joints within 6 cm, weights (all, at most 4, own part, mirrored), elbow and knee bends ([Rigging](../tools/blender/rigging.md)) |
| `clip-walk` | `blender-artist` | an in-place walk cycle on a given rig | one clip of 1 s, loop seam, hips in place and bobbing, leg and arm swings and phases, arms hanging, feet on the floor ([Animation](../tools/blender/animation.md)) |
| `decimate-boulder` | `blender-artist` | a near and a far level of a 20,480-triangle sculpt | budgets of 2,000 and 500, surface distance, bounds, flat bottom, flipped area, open edges ([Optimisation](../tools/blender/optimisation.md)) |
| `pickup-feature` | `godot-engineer` | pickups and a score in a 3D Blank game | `gds check layout`, gdlint and gdformat, a clean import, its own tests, the task's acceptance suite ([Project conventions](../engines/godot/project-conventions.md)) |

Every Blender task also asks for the `build.py` that makes the delivery (the check reruns it and compares) and a
`preview.png` the agent looked at. Every Blender check reads the exported `.glb`, the file Godot gets.

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
| `pickup-feature` | 8 of 8 | 82,362 | 16 | 2.5 | the GdUnit command line was not on a page it read; testing an `Area3D` trigger and a spin |

The gaps went into the topic sections in the same pull request ([Blender](../tools/blender/index.md)); the next run
of each task, with the changed agent pages, is measured against this table.

## A task {#a-task}

`evals/<kind>/<task>/TASK.md` holds TOML front matter between `+++` lines (`agent`, `kind`, `deliver`, `read` and, for
a Godot task, `template`) and then the brief, whose `#` heading is the task's title. A Blender task has `prepare.py`
(writes the inputs, in the pinned Blender) and `check.py` (measures the delivery and writes rows, with
`evals/blender/evallib.py`); a Godot task has an `acceptance/` suite, which the check copies into the game's
`tests/eval_acceptance/`, runs with the game's own suites and removes. The `read` lines name sections that exist
(a test checks them).

- **Approach:** Prove a new check against a reference solution kept in scratch (never committed, so an agent cannot
  copy it) and against a wrong one, before any agent runs the task. **Watch out for:** a check that cannot be met, or
  that passes anything, measures nothing: the first crate check counted parts that touch as non-manifold, the first
  boulder was flat-shaded so its decimation tore, and a reference walk with its arms in step with its legs passed every
  row except the phase. **Seen:** gdstudio #774, 2026-11-07 (fix: each check passed a reference and failed a broken
  one before the baseline).

## What the evals do not see {#unseen}

Whether the result looks right in the game's style (the check reads numbers, the preview is for the agent), how the
asset behaves in Godot (only the Godot task runs Godot), and a task the brief does not describe. A reviewer still
judges those ([Agents](agents.md#structure-reviews)).
