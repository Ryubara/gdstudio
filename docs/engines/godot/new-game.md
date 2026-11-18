# A new game from a template

```text
uv run --project <workspace>/repos/gdstudio/python gds new game --list
uv run --project <workspace>/repos/gdstudio/python gds new game <name> --template 3d-blank \
    --co-author "<model name> <noreply address>" [--title "My Game"] [--description "One line."]
```

`gds new game` makes `<workspace>/repos/<name>/` from one of the kit's templates, publishes it on GitHub and proves
it: the command ends with a public repository, its labels, settings and ruleset, a green first CI run, a live Pages
site and a kit pull request that registers the game. The name is the repository's: lowercase words joined by hyphens.
An agent asks the maintainer only for the name and the template (`--list` prints the templates, a line each); the
title and the description default from the name and the template. Nothing asks a question on the way: every choice is
a flag with a default, because an agent cannot answer a prompt.

Making a new game repository this way, public and under MIT, is the agent's to do (the maintainer decided so on
kit #779). Changing an existing repository's visibility or licence is still a maintainer decision (AGENTS.md).

| Flag | Default | What it changes |
| --- | --- | --- |
| `--licence <SPDX>` | `MIT` | another licence, its text from GitHub's licence list |
| `--copyright <holder>` | the kit's GitHub owner | the licence's copyright holder |
| `--private` | public | a private repository (Pages and free Actions minutes on this plan need public) |
| `--co-author "<trailer>"` | none | the agent's `Co-Authored-By` on the kit commit, and the model in its pull request |
| `--no-wait`, `--wait-minutes N` | wait, 45 minutes | skip, or bound, the wait for the first CI run and Pages |
| `--no-kit-pr` | open it | leave `workspace.toml` alone |
| `--local` | publish | stop at the local repository, nothing goes to GitHub |
| `--remote <url>` | none | with `--local`: record an existing repository as `origin` and in `workspace.toml` |

The command exits 0 when the first CI run and the docs deploy passed and the site answers, 1 when the proof is not
green (it prints which), and 2 when it refused before doing anything.

## What it does {#what-it-does}

1. **Checks GitHub first.** `gh` is signed in and `<owner>/<name>` does not exist yet, before a file is written. The
   owner is the kit's own (`workspace.toml`).
2. **Copies the files.** `templates/repo/` (what every game repository has) and then the template's own folder: its
   `game/` becomes the Godot project and its `docs/` the docs site's pages. The placeholders `{GAME_TITLE}`,
   `{GAME_SLUG}`, `{GAME_DESCRIPTION}`, `{GAME_YEAR}`, `{GAME_COPYRIGHT}`, `{TEMPLATE}`, `{KIT_REPO}` and
   `{KIT_PAGES}` are filled in, line endings are made LF, and a placeholder the command does not know stops it.
   These files are the game's own from then on.
3. **Writes the licence.** MIT with this year and the holder; another `--licence` replaces the file with GitHub's text
   of it (`gh api licenses/<id>`), its year and holder filled in. An id GitHub does not know stops the command first.
4. **Syncs.** The same call as `gds sync`: agent definitions, the hook launcher and its settings, the commit and pull
   request checker, the hold workflows and the message-check hooks, with the lock `.claude/gds-sync.json`
   ([Sync](../../studio/sync.md)). `.github/scripts/pr_status.py` is copied from the kit once.
5. **Sets up git.** `git init -b main`, `git lfs install --local`, a first commit (`build: Add the 3D Blank starter`,
   no trailer: a command wrote it), and the three hooks of `.pre-commit-config.yaml` (`uvx pre-commit install`).
   Git LFS's own pre-push hook, which pre-commit moves to `pre-push.legacy`, is repaired for Windows as
   `gds worktree` repairs it: its `#!/bin/sh` is not found by pre-commit there, and the first push died on it.
   A step whose program is missing is skipped with a line and listed at the end.
6. **Installs the pinned addons.** GdUnit4 and the Godot MCP addon go into `game/addons/` untracked, as
   `gds workspace init` does for every game ([Workspace](../../studio/workspace.md)), when they were fetched.

## On GitHub {#github}

Without `--local`, the command goes on:

1. **The repository.** `gh repo create <owner>/<name> --public` with the description and the Pages address as its
   homepage; `origin` is added and `main` pushed (through the game's own hooks).
2. **Pages.** Its source is set to GitHub Actions through the API (`POST repos/<owner>/<name>/pages`,
   `build_type=workflow`) before the push. When GitHub refuses that on the empty repository, it is set after the push,
   and the push's docs deploy, which then ran before Pages existed, is rerun once.
3. **The conventions.** `python .github/scripts/groundwork.py labels`, `settings` and `ruleset`, each with `-R
   <owner>/<name> --apply`, from the game's own conventions.
4. **The hold sweep.** `gh workflow run hold-sweep.yml` once, now that the ruleset requires `hold`
   ([The hold](../../studio/hooks-hold.md#hold)), tried again for a minute while GitHub registers the pushed workflows.
5. **The proof.** It waits for the first `ci` and `docs` runs of the pushed commit and for the site to answer, and
   prints the runs' and the site's URLs.
6. **The kit pull request.** A kit branch `workspace-add-<name>` in its own worktree
   (`<workspace>/worktrees/gdstudio/`), from a fresh `origin/main`, adds `[repos.<name>]` to `workspace.toml` so
   `gds workspace init` clones the game on the next machine. Its description, with the proof in Testing, passes
   `check-body` before `gh pr create`. The agent lands it like any other pull request.

Every `gh` call goes through the one runner of `gds` (`issues.run_gh`), which refuses anything that posts a comment
([No comments](../../studio/hooks.md#comments)). A failed step stops the command with what failed; the repository may
then exist
already, so finish the remaining steps by hand rather than running the command again under the same name.

The game then holds: `game/` (the project), `docs/` and `mkdocs.yml` (a docs site), `.github/` (the conventions, the
workflows `ci`, `pr`, `docs`, `hygiene`, `pr-status`, `ci-failure`, `issue-area`, `issue-status`, the generated
template and issue forms), `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, licence, code of conduct, security
policy and the lint and format configuration. The game's `ci` runs the same steps a person runs: the conventions and
`gds sync --check` and [`gds check layout`](project-conventions.md), the import, [`gds check scripts`](#proof) (every
script parses), a run of the main scene, the tests, the web export, `gdformat` and `gdlint`, the docs build,
`markdownlint` and `actionlint`.

- **Approach:** Ask of every end step a tool leaves for the maintainer whether it is a real choice per game or the same
  every time, and make the second kind a default the agent runs. **Watch out for:** `gds new game` stopped at the local
  repository and handed over the GitHub repository, Pages, the ruleset, the hold sweep and the licence, though they are
  the same for every game. **Seen:** gdstudio #779, 2026-11-07 (fix: `gds new game` does them, with MIT as the default
  licence (gdstudio #779)).

- **Approach:** Before adding a second place that installs or runs git hooks, grep for the first (`install_hooks`,
  `ensure_hooks`) and call it or its repairs rather than calling `pre-commit install` again; find a hidden hook failure
  without pushing by running `.git/hooks/pre-push origin <url>` with the ref line on stdin. **Watch out for:**
  `pre-commit install` moves Git LFS's `pre-push` to `pre-push.legacy`, and on Windows pre-commit cannot find its
  `#!/bin/sh`; `gds worktree` had repaired this since it first happened, but the new command never called it, and only
  git's stderr was kept while pre-commit writes to stdout. A loop variable `name` shadowed the game's, so the probe's
  pull request was titled "Add the pre-push.legacy game". **Seen:** gdstudio #779, 2026-11-07 (fix: `new_game` calls
  `repair_legacy_hooks`, a test checks the branch and title).

- **Approach:** Run the kit's own `git` calls on a template tree with `-c core.longpaths=true` (the kit pull request's
  worktree), and keep a committed addon's longest path in mind when a test makes a game under a long temporary name.
  **Watch out for:** the Windows `test` job failed 20 tests with "Filename too long" making the kit worktree: Phantom
  Camera's `phantom_camera_noise_emitter_gizmo_plugin_3d.gd.uid` under a pytest folder named for a test passed 260
  characters. **Seen:** gdstudio #821, 2026-11-08 (fix: the flag in `open_kit_pr`'s `git`).

## Proving a new game {#proof}

<!-- new section: the page says what the template job runs; nothing said what proves a game is clean in the editor -->

A new game is proved by a clean open and a parse of every script, not by an import and a short run, which load only the
scripts the main scene reaches. `gds check scripts game` runs the pinned Godot headless with
`godot/tools/check_scripts.gd`, which loads every `.gd` under `res://` fresh (addons included) as the editor does,
prints each one that does not load with Godot's own reason, and exits 1. The game's `godot` job and the kit's
`template` job run it after the import. To see what a person sees, open the made game in the editor
(`gds godot -- --editor --path game --quit-after 200`) and read the Output panel.

**A template's own suites run with one command**, from your worktree, whatever you changed in the template:

```text
uv run --project <your worktree>/python gds template test 3d-third-person
```

Its first line is the source, `kit <path> (<branch> at <commit>, <n> changed file(s))`: the checkout whose `python`
folder `--project` names (the code's own location, never the folder you stand in). It makes a workspace of its own (a
new folder from `tempfile.mkdtemp` under the system temp folder, outside the real workspace, holding the marker, a copy
of `gdstudio.local.toml` and the GdUnit4 folder), makes the game from the working tree's template (uncommitted changes
included, so there is nothing to copy over and no game to make again), checks its layout, imports it and parses every
script, then runs the suites with the command CI uses and prints each suite's cases, failures and time (a failed case
with the first line of its message). The folder is removed when the run ends, passed, failed or interrupted, and nothing
else is: it refuses a folder that is not one of its own. The exit code is GdUnit4's (100 failed tests, 105 a script that
does not parse; 1 for a layout or parse failure, a run that ran no suite, or a `leaked at exit` line, which CI refuses).
Options: `--suite tests/core/test_x.gd` (repeat it; one `-a` per suite in the order given, default all of
`res://tests`), `--keep` (keep the game and print its path: the repository folder, whose `game/` is the Godot
project that `--path` names), `--fixed-fps N` (default 60, the clock CI runs the suites
at: Godot runs a frame per tick with no waiting, [test-speed.md](test-speed.md#time-driven-values)) and `--real-clock`
(no flag, for a check on the wall clock), `--godot-args='...'` and `--gdunit-args='...'` for any other argument (joined
with `=`, since a bare `--flag` looks like an option to the command), `--timeout`. `gds template game <name>` makes the
same game, imports it and keeps it, printing its path, for captures and probes (`gds capture frames --project
<path>/game` runs from your worktree: frames land in its scratch folder, or in `--out`); `gds template clean <path>`
removes it, and only a folder `gds template` made. `gds template bench-web <name> <bench>` makes the same game with a
bench of `tools/bench/` as its main scene and exports it to the web ([A bench's web export](web-probes.md#bench-web)).
Its tests are `python/tests/test_template_test.py` (a fake Godot: unique folder, outside the real workspace, removed on
every exit, kept with `--keep`, two calls at once).

- **Approach:** Remove a kept game with `gds template clean <the path it printed>`, one folder at a time, as soon as
  its captures are made. **Watch out for:** every agent's kept games and logs sit side by side in the user's temp
  folder as `gds-tt-*`; a cleanup by that glob deleted other agents' kept games, some mid-run, before it was
  stopped. **Seen:** gdstudio #1156, 2026-11-12.
- **Approach:** To try a change in a kept game, copy the template's changed scripts and scenes over and make the game
  again (`gds template game`) when `project.godot` changed. **Watch out for:** the made game's `project.godot` is the
  template's with the autoloads and addon settings `gds template game` adds; copying the template's over it dropped
  `UIRouter` and the other autoloads, and every suite that loads `main.tscn` failed on parse errors with nothing of
  the change in them. **Seen:** gdstudio #1400, 2026-11-13.
- **Approach:** Run a scene of a kept game headless with `--path <the printed path>/game` and a `timeout`, and read
  the first lines before waiting. **Watch out for:** `--path` at the printed folder itself (it has no `project.godot`)
  printed only Godot's banner and never returned; three such runs sat for ten minutes until stopped by their PIDs.
  **Seen:** gdstudio #1543, 2026-11-14 (the AI soak's sample runs).
- **Approach:** Prove a new game or template change with a parse of every script (`gds check scripts`) and an editor
  open, and when a script fails, find the registration or file it needs, never an export exclusion. **Watch out
  for:** a new 3D Blank game opened with five parse errors from the `gds_ui` demo (`Identifier "UIRouter" not
  declared`): the template synced the addon but never registered the autoload, and #778 met the same errors in the
  export, excluded the demo and proved only an import and a 60-frame run. Start a `-s` check script in `_initialize`:
  the autoloads join the tree after `_init`. **Seen:** gdstudio #814, 2026-11-08 (fix: the template registers the
  plugin and the autoload, and the parse check fails 5 of 329 scripts on the old template); gdstudio #909, 2026-11-11
  (a probe's Variant `:=` broke the player rig; no suite loaded the probe).
- **Approach:** To run a template's own tests, run `gds template test <t>` from your worktree (see above); it makes the
  game from the working tree each time. **Watch out for:** `templates/<t>/game` has no GdUnit addon, so its tests cannot
  run there, and a game made by hand earlier keeps the template as it was (the old `.tres` and scene of a dropped
  approach stayed in it and broke every test until the game was made again); `gds new game --local --workspace <folder>`
  builds the same way. **Seen:** gdstudio #830, 2026-11-08 (the command: gdstudio #917); gdstudio #857, 2026-11-09 (`gds
  new game`).
- **Approach:** Name your worktree's `python` folder in `--project` (`uv run --project <worktree>/python gds template
  test <t>`) and read the `game` line for the checkout it used; a suite that runs 0 cases, or "Given directory or file
  does not exists" for a suite the branch adds, means the wrong checkout, never a pass. **Watch out for:** the template
  comes from the checkout whose `python` folder `--project` names, not the folder you stand in, so the kit's main
  `python` run from inside a worktree tested `main`'s template, and its green runs were `main`'s copies of the suites.
  **Seen:** gdstudio #940, 2026-11-10 (the main checkout's `python` tested its own template); #1274; PR #1427,
  2026-11-14 (the coordinator, standing in the pull request's worktree).
- **Approach:** Run a desktop probe or a bench of a template in a kept game (`gds template game`, or the game
  `bench-web` keeps without `--run`), never with `--path templates/<t>/game`. **Watch out for:** an import there
  failed to parse the menus and settings (37 errors: their classes come with the game) and rewrote three levels'
  lightmap `.import` files in the worktree (the ASTC copy dropped); committed, they fail CI's step that the build left
  nothing for git, so read `git diff --stat origin/main -- '*.import'` before a push. **Seen:** gdstudio #1433,
  2026-11-13 (put back with `git checkout`); #1400 (PR #1437), 2026-11-13 (two lightmaps' `.exr.import` committed);
  gdstudio #1436, 2026-11-13 (the same 37 errors and one lightmap `.import`).
- **Approach:** Give a new script or shader its `.uid` before `gds template test` with `gds template uids
  <template>` (the template's name, or a folder holding `project.godot`): it writes each missing file in Godot's form
  and leaves every valid one alone. A new asset's `.import` still comes from the kept game (`gds template game
  <template>`, import, copy it back). **Watch out for:** the layout check refuses a script without its `.uid` and the
  template's own folder cannot be opened to make one, so agents copied uids back from a kept game or wrote them by
  hand, and hand-made ones held text Godot never writes. **Seen:** gdstudio #1009, 2026-11-10; gdstudio #1068 (PR
  #1092), 2026-11-11; gdstudio #1148, 2026-11-11; kit #1129, 2026-11-11 (the command); gdstudio #1359 and #1405,
  2026-11-13 (a suite and fixtures run in a kept game, whose uids the worktree lacked).
- **Approach:** Read the source before the results: the first line of `gds template test` and `gds template game` (the
  `from` line in `gds new game`) is `kit <path> (<branch> at <commit>, ...)` and must name your worktree (the kit is the
  `--project` checkout, not your folder). Send a run's log to a new name in your own scratch folder or from `mktemp`,
  never a fixed name in the session scratchpad. **Watch out for:** a run showed another agent's worktree as the source:
  gds had built from the right checkout, but two agents sent their runs to the same `full2.log` in the shared
  scratchpad, and the later run's header landed in the file the first read back. **Seen:** gdstudio #1011 (PR #1019),
  2026-11-10 (fix: gdstudio #1048); gdstudio #1047, 2026-11-10 (`--project` of main's checkout built main; use
  `--project ./python`); gdstudio #1026, #1148 (2026-11-11) and #1315 (2026-11-12), the same.
- **Approach:** Make a game by hand only in a workspace of its own from `mktemp -d` under the system temp folder (copies
  of `.gdstudio-workspace`, `gdstudio.local.toml` and the `tools/` addons), and remove only that; read a template's
  `project.godot` in a test with `ConfigFile`. **Watch out for:** a folder inside the real workspace or an empty
  `--workspace` has no marker, so the game landed in the real `repos/`; a fixed name in the shared scratchpad let a
  reviewer's clean-up delete another agent's game (#896); `ProjectSettings` lacks `editor_plugins/enabled` at run time.
  **Seen:** gdstudio #814, #873, #877 (a stray `repos/zz-parse`, an empty folder, one inside the workspace: moved
  out); #917 (`gds template` makes and removes its folder).

- **Approach:** Prove a template change with `gds template test <t>`, then open the game it kept (`--keep`) in the
  editor for the Output panel; keep the new scripts' `.uid` files (copy them from the kept game back to the template;
  the layout test fails without them), and run the pair that failed in the CI log in the log's order with two
  `--suite` options. **Watch out for:** the file order differs between Windows and the Linux runner, and a base suite
  left the left mouse button and `fire` down, so eight tests of #836 passed in every local order and failed in CI.
  **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Copy the `.import` file of every new asset (image, sound, model) back from the kept game with its
  `.uid` files, and before the push run `git status --porcelain` in the template after a headless `--import` there.
  **Watch out for:** `gds template test` passes without them, since it imports in its own copy, but CI imports inside
  the template and its step that nothing the build made is left for git fails on each missing `.import` (six minimap
  icons); an `.import` written by hand from a sibling's keeps its path hash and has no `uid`, so the import rewrites
  it ([import checks](../../tools/blender/export.md#import-checks)). **Seen:** gdstudio #884, 2026-11-10; gdstudio #887,
  2026-11-10 (nine weapon sounds copied from
another game with no `.import`: the full local run was green and CI's step failed); #1293 (PR #1323), 2026-11-12
  (two clip files' `.glb.import` copied from `prone.glb.import` and renamed); #1342 (PR #1389), 2026-11-12 (the
  bandage's two sounds written by `tools/audio/sfx.py encode`, which makes no `.import`).
- **Approach:** After merging main into a template branch, run the command again: it always makes a fresh game from the
  merged tree. **Watch out for:** a copy loop that skips `.glb` and `.exr` files (to keep the import cache) leaves out
  every model or texture main added, so the copied game ran new scripts against old assets and its tests failed for no
  fault of the change. A merge resolved by hand can also keep both sides' bindings: run it before the push. **Seen:**
  gdstudio #856, 2026-11-09; gdstudio #887, 2026-11-10 (prone and the empty hands both took d-pad down, and
  `test_input_map.gd` failed only on the next run).
- **Approach:** A game is made from the template folder as it is on disk, and the copy leaves out what git ignores
  (`git ls-files --others --ignored`, with `__pycache__`, `.ruff_cache`, `.pytest_cache`, `.mypy_cache`, `.godot` as the
  fixed fallback when the template is not in a checkout); `gds new game`, `gds template test` and the eval games share
  that copy. **Watch out for:** a Python or ruff run in a template's tools folder (`tools/net/`) leaves ignored caches
  there, and the old copy took them, so `gds template test` stopped at `layout: 3 problem(s)` before any suite ran;
  deleting the caches by hand was the only way on. **Seen:** gdstudio #903 (PR #935), 2026-11-10 (fix: gdstudio #957).
- **Approach:** Write a task's logs, reports and probe output to its own scratch folder
  (`<workspace>/scratch/<repo>/<branch>/`) under a name of your own. **Watch out for:** a fixed name in the shared
  session scratchpad (`full.log`) was overwritten by another agent's run, so the results read were someone else's.
  **Seen:** gdstudio #1148 (PR #1181), 2026-11-11.
- **Approach:** Treat a game from `gds template game` as a snapshot of the template when it was made: after changing a
  script, copy it into the game (or make the game again) before the next capture, and after merging main make it
  again, or run a headless `--import` there and copy the synced addons in afresh. **Watch out for:** the kept game
  ran the old script between captures; after a merge it knew no new `class_name` until `--import` ran, and its stale
  `gds_ui` copy failed an inventory case that passed in a fresh game. **Seen:** gdstudio #1172 and #1040, 2026-11-11.
- **Approach:** Keep captures, exports and other heavy work off the machine while a full `gds template test` runs
  its cost suites, or run those suites again alone on a quiet machine before believing a failure. **Watch out for:**
  the cost tests time real work against budgets, so a capture or an export running beside them made a fast step read
  slow and failed a suite the change never touched. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11.
- **Approach:** To read a number a suite prints (a measured cost, a count, a `print` line), run `gds template test` with
  `--keep` and read the kept folder's `gdunit.log`, then remove it with `gds template clean <path>`, or have a probe
  write its own file; after a failing run, read the log named on the run's line starting `log` (a `gds-tt-*.log` in the
  temporary folder). **Watch out for:** the run shows each suite's counts and failure lines, never a test's `print`
  output, and a passing run removes its folder, log included, so the newest `gds-tt-*.log` belongs to an earlier failing
  run. **Seen:** gdstudio #1198 (PR #1223), 2026-11-11; #1273, #1356, #1362 and #1344, 11-12; #1410 (PR #1425), 11-13;
  PR #1422, 11-14 (a probe's lines, from a passing run).
- **Approach:** Give a new script of a synced addon (`godot/addons/<name>/` in the kit) its `.uid` in the addon's
  source, then sync: `uv run --project python python -c "from pathlib import Path; from gds_tools import uids;
  print(uids.write(uids.uid_file(Path('<script>.gd'))))"`. **Watch out for:** `gds template uids` skips every
  `addons/` folder on purpose (an addon's files are its own), so it wrote nothing for a new `gds_game` script, still
  reported every script as having its uid, and nothing on the page said how to make one. **Seen:** gdstudio #1183
  (PR #1214), 2026-11-11; #1037 (PR #1239), 11-11 (the report).
- **Approach:** To run one case through `gds template test`, give its suite with `--suite tests/x.gd` and skip each
  other case in one `--gdunit-args='-i res://tests/x.gd:test_other -i ...'` (split like a shell line), then read that
  one case ran. **Watch out for:** `--suite tests/x.gd:test_name` names no file, so no test runs; `-i` skips the case it
  names and never selects it ([the command line](running-gdunit.md#command-line)). **Seen:** gdstudio PR #1369 refresh,
  2026-11-14.
- **Approach:** Point `gds capture frames --project` and Godot's `--path` at the kept game's `game/` folder (`<printed
  path>/game`), not at the folder `--keep` or `gds template game` prints. **Watch out for:** the printed path is the
  game's repository and its Godot project is the `game/` inside, so a capture given the repository found no project,
  and a headless soak given it printed nothing and waited, using no processor, until its timeout killed it (four
  runs of 300 s lost). **Seen:** gdstudio PR #1530, 2026-11-14; #1591, 2026-11-17.

## With `--local` {#with-local}

Only the local steps run. The command prints the GitHub steps it left out, for whoever publishes the game later:
create the repository and push `main`; Pages' source to GitHub Actions and the three `groundwork.py ... --apply`;
`gh workflow run hold-sweep.yml`; `[repos.<name>]` in the kit's `workspace.toml`. The kit's CI makes its template
check this way (`gds new game template-check --template 3d-blank --local`), then exports the web build and boots it in
headless Chromium ([the boot check](web-probes.md#boot-check)).

- **Approach:** Make a throwaway game for a probe with `gds template test`, or give its folder its own
  `.gdstudio-workspace` marker before `gds new game --local --workspace <folder>`, and check the `made` line's path.
  **Watch out for:** `--workspace` finds the nearest workspace at or above the folder it names, so a folder inside the
  workspace (its `scratch/`) resolves to the workspace itself and the game is made in its `repos/`. **Seen:** gdstudio
  #1481, 2026-11-13 (a game for dumping the pistol's hold landed in `repos/` and was removed at once; the probe then
  used a marked scratch folder).

## A double-click for people {#double-click}

<!-- new section: the page held the command for agents; nothing gave a person a way without typing it -->

A person trying a template double-clicks `templates/new-game.sh` (on Windows `templates/new-game.cmd`, which runs it
with Git for Windows' bash). It lists the templates, asks for one and for a name, refuses a bad name or one whose
`repos/<name>` exists, runs `gds new game <name> --template <t> --local` into `<workspace>/repos/<name>/`, and offers to
open the game in the pinned Godot editor. It finds the workspace by walking up to `.gdstudio-workspace`, so it works
from the kit or a worktree, and it waits for Enter before the window closes. A template change reaches a game only
when the game is made again: `gds sync` refreshes the files every game shares, never a template's own. Agents keep
using the command above, since the script asks questions.

- **Approach:** Write a script a person runs for the bash every platform has: macOS ships bash 3.2, so no `mapfile`,
  `readarray`, associative arrays or `${var,,}`; read lines with a `while IFS= read -r` loop and give every array a
  value (`LINES=()`) before `set -u` meets it. **Watch out for:** Git Bash and Ubuntu run bash 5, so the script passed
  there and only the macOS test job failed (`mapfile: command not found`). **Seen:** gdstudio #840, 2026-11-08.

## The templates {#the-templates}

| Template | What it is | Status |
| --- | --- | --- |
| `3d-blank` | The shared base: a bounded floor and walls on the grid surface (cell size and editor snap from one project value), sky, sun, baked light, a Forward+ graphics profile (Compatibility on the web and phones), `ProtoBlock` for the floor and walls (resize them in the inspector), Phantom Camera with a static view camera, the touch controls component (real `Control` nodes you arrange in the 2D editor), a `WebProbe` that CI's [boot check](web-probes.md#boot-check) waits for, the folder layout and the web export ([Prototype surfaces and daylight](prototype-surfaces.md#web-first-rework)); every template follows [the checklist](template-checklist.md#template-checklist). | made; trimmed to this in #821, the checklist applied in #831 |
| `3d-third-person` | `3d-blank` plus a character controller (walk, run, sprint, crouch, prone and crawl, jump), a Phantom Camera third-person view with sprint and aim views, touch controls bound to it, GDStudio's prototype mannequins (the `form` female for the player and friendlies, the male for enemies; Quaternius's two stay beside them) with the Universal Animation Library 1 and 2, a pistol with a crosshair, projectiles and targets, bullet impacts (marks, effects and sounds by surface), a minimap and a full-screen map ([Minimap](minimap.md)), an assault rifle held with both hands and given by a floating pickup, a muzzle flash and the pooled effect emitter both use, the first sounds, a main menu, pause menu and settings with rebinding, an inventory screen (the live model, the weapons, a bag of items: [Inventory](inventory.md)), and the #788 prototype map with its components, a crouch course, a range and two map sections for AI and pathing work ([The 3D Third Person template](third-person-template.md), [Map sections](map-sections.md)). | made in #821, crouch, pistol and sounds in #836 |
| `3d-first-person`, `3d-universal`, `3d-top-down`, `3d-vehicle` | Controllers and sample content on the same base, filed one at a time after the one before it is tested. | planned |

What each template plays, and on which bus (the buses and the volume node are in [Audio](audio.md#template-buses)):

| Template | Sound | Played by | Bus |
| --- | --- | --- | --- |
| `3d-blank` | the wind loop (`assets/audio/wind/`) | the `Wind` player of `main.tscn`, from the start | `Ambient` |
| `3d-third-person` | the wind loop, at -20 dB (replace it by changing the `stream` of the one `Wind` player; level and bus stay) | the same `Wind` player | `Ambient` |
| `3d-third-person` | footsteps (four soft sneaker steps, `assets/audio/footsteps/`) | `Footsteps` (`Step` at -20 dB, `CrouchStep` at -29, `LandStep` at -15), a step each time a foot of the animated skeleton lands | `SFX` |
| `3d-third-person` | the coin (four files, `assets/audio/coin/`) | the `Sound` node of every `Pickup` at -16 dB, one file a pickup | `SFX` |
| `3d-third-person` | a pistol shot (five files of 0.47 s, `assets/audio/pistol/`, ElevenLabs on the paid plan, kit #1414) | the `ShotSound` of `Weapon`: an `AudioStreamRandomizer` (pitch spread 4%, +-1 dB) at -24 dB, three voices | `SFX` |
| `3d-third-person` | the weapon pickup (two files, `assets/audio/weapon_pickup/`, ElevenLabs on the paid plan: commercial use, no attribution) | the `Sound` node of every `WeaponPickup` at -20 dB, one file a pickup (pitch spread 3%) | `SFX` |
| `3d-third-person` | the rifle (a shot in four files of 0.29 s, ElevenLabs on the paid plan, kit #1414; the empty click, three reload steps and the draw, Deadnight's M4A1, MIT; `assets/audio/rifle/`) | the `Weapon`'s players from `rifle.tres`: the shot an `AudioStreamRandomizer` at -24.5 dB | `SFX` |
| `3d-third-person` | the pistol's empty click, reload steps and draw (`assets/audio/pistol/`) and the fists' swing (`assets/audio/fists/`) | `EmptySound` (-12 dB), `ReloadSound` (-16) and `DrawSound` (-10) of `Weapon`, and its `ShotSound` with the fists' `shot_volume_db` (-27) | `SFX` |
| `3d-third-person` | the bandage's use (two files, `assets/audio/bandage/`, ElevenLabs on the paid plan) | the `Sound` of the player's `ItemUse` at -14 dB, from `gameplay/inventory/bandage_use.tres` (an `AudioStreamRandomizer`, pitch spread 4%, +-1 dB) | `SFX` |
| `3d-third-person` | bullet impacts (nine files, `assets/audio/impacts/`: default, wood and metal, three each) | the `sound` of each `ImpactSurface`'s `EffectDef`, played at -10 to -14 dB from the `EffectEmitter`'s pool | `SFX` |
| `3d-third-person` | the menus' sounds (fourteen files, `assets/audio/ui/`: hint, press, confirm, move, toggle, swish) | the twelve players of the `MenuSounds` autoload (`ui/menus/menu_sound_service.tscn`), from the cues of every `gds_ui` control, the router and the inventory's slots ([Menu sounds](audio.md#menu-sounds)) | `UI` |

Every template sound but the rifle's mechanics is generated with ElevenLabs Sound Effects on a paid plan by the kit's
`tools/audio/sfx.py` ([Sound effects](../../gamedev/audio/sound-effects.md), kit #1083).

- **Approach:** Prove a workflow written for games with a real run in a real game repository: make a throwaway game with
  `gds new game` and read its first CI run before calling a template change done; a test reads every `"$PRE_COMMIT" run`
  line of the template's workflows and fails on more than one hook id. **Watch out for:** the template's `ci.yml` ran
  `pre-commit run gdformat gdlint --all-files`, but `pre-commit run` takes one hook id; the kit's `template` job makes a
  game and runs every hook itself, never the game's own command lines, so the first game's first `ci` run was red.
  **Seen:** gdstudio #778 and #779, 2026-11-07 (fix: one call for each hook; the next probe's first run was green).

- **Approach:** Give a template that commits a third-party addon an exclusion in its own and the kit's
  `.pre-commit-config.yaml` (the top-level `exclude:`), and a `LICENSE.md` beside the addon; make the throwaway game
  with `gds new game --local`, `git add -A` and run `uvx pre-commit run --all-files` in it, then copy the files the
  hooks changed back to the template. **Watch out for:** the game's `gdformat`, `gdlint`, `trailing-whitespace` and
  `end-of-file-fixer` rewrote and failed on Phantom Camera's files (419 lint problems, svg files with no final newline),
  and gdlint's 100-column limit counts comments, so every `##` line written at 120 failed. **Seen:** gdstudio
  #821, 2026-11-08 (fix: the exclusion; the comments reflowed to 96 columns).

- **Approach:** Keep `3d-blank` to the base every game shares: a bounded floor and walls on the grid surface, the
  sky and sun, the renderer per platform and the graphics profile. A prototype map with props and map components
  belongs to the first template with a character to move through it. **Watch out for:** #788 built a full prototype
  map with six components into `3d-blank`, which gives every game started from it a level to delete first. **Seen:**
  gdstudio #788 and pull request #819, 2026-11-08 (the map moves to `3d-third-person`).

- **Approach:** When a template holds a Git LFS file (a lightmap's `.exr`), check out the kit with `lfs: true` in every
  kit CI job that copies the template, and skip the file in text checks. **Watch out for:** without it the template
  holds a pointer file: the `template` job imported it and failed, and every test that pushes a made game to a bare
  repository stopped with "Git LFS upload failed: (missing) ...exr". **Seen:** gdstudio #788, 2026-11-08 (the first CI
  run of the lightmap; fixed in `ci.yml`).

- **Approach:** To capture a template change, make the game with `gds template game <t>` (it prints the path of a game
  in a throwaway workspace, imported); run `gds capture frames --project <path>/game` from your own worktree, and
  `gds template clean <path>` when done and after every `--keep` run. A hand-built probe (as in
  [Adding a template](#adding-a-template)) needs `git init` first. **Watch out for:** `--local` alone writes into the
  real `repos/`; `capture frames` names the scratch folder from the folder you run it in, not from the game (whose
  frames once all landed in the shared `scratch/template-check/main/`); outside git, pass `--out`. **Seen:** gdstudio
  #838 and #847, 2026-11-08 (probes assembled by hand; `git init` checked in #849); #917 (the command); #992 (the
  shared folder); #1026 (about 30 kept games left in the temp folder).
- **Approach:** Capture and import in a made game, never in the template's own `game/` folder, and read the capture's
  error count before its frames. **Watch out for:** the template's folder lacks the synced addons, so `AudioSettings`
  and the other shared classes do not parse there: a capture run in it wrote 255 frames of a scene whose script never
  loaded, and an import there rewrote the lightmaps' `.import` files. **Seen:** gdstudio #1295,
  2026-11-11 (fix: `gds template test --keep`, the tour copied into the kept game, `gds template clean` after);
  gdstudio #1320, 2026-11-11 (a probe script run with `--path` at the kept folder the command prints, which is the
  game's repository: the Godot project is its `game/` folder, the script found no resource, did not quit and held
  the shell for its ten minutes; run every such probe under `timeout 120`); #1274 and #1319, 2026-11-12; #1508,
  11-14.

## What every template is built and reviewed against {#template-checklist}

<!-- moved: new-game.md neared 50 KB with gdstudio #1237; the anchor stays for the links in the corrections log -->

The checklist every template is built and reviewed against (inspector-tunable parts, scene nodes over code, tests):
[Building and reviewing a template](template-checklist.md#template-checklist).

## Adding a template {#adding-a-template}

Moved to [Building and reviewing a template](template-checklist.md#adding-a-template).
