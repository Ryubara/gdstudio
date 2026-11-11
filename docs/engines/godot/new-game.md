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
   ([The hold](../../studio/hooks.md#hold)), tried again for a minute while GitHub registers the pushed workflows.
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
`res://tests`), `--keep` (keep the game and print its path), `--fixed-fps N` (default 60, the clock CI runs the suites
at: Godot runs a frame per tick with no waiting, [test-speed.md](test-speed.md#time-driven-values)) and `--real-clock`
(no flag, for a check on the wall clock), `--godot-args='...'` and `--gdunit-args='...'` for any other argument (joined
with `=`, since a bare `--flag` looks like an option to the command), `--timeout`. `gds template game <name>` makes the
same game, imports it and keeps it, printing its path, for captures and probes (`gds capture frames --project
<path>/game` runs from your worktree: frames land in its scratch folder, or in `--out`); `gds template clean <path>`
removes it, and only a folder `gds template` made. `gds template bench-web <name> <bench>` makes the same game with a
bench of `tools/bench/` as its main scene and exports it to the web ([A bench's web export](web-probes.md#bench-web)).
Its tests are `python/tests/test_template_test.py` (a fake Godot: unique folder, outside the real workspace, removed on
every exit, kept with `--keep`, two calls at once).

- **Approach:** Prove a new game or template change with a parse of every script (`gds check scripts`) and an editor
  open, and when a script fails, find the registration or file it needs, never an export exclusion. **Watch out
  for:** a new 3D Blank game opened with five parse errors from the `gds_ui` demo (`Identifier "UIRouter" not
  declared`): the template synced the addon but never registered the autoload, and #778 met the same errors in the
  export, excluded the demo and proved only an import and a 60-frame run. Start a `-s` check script in `_initialize`:
  the autoloads join the tree after `_init`. **Seen:** gdstudio #814, 2026-11-08 (fix: the template registers the
  plugin and the autoload, and the parse check fails 5 of 329 scripts on the old template); gdstudio #909, 2026-11-11
  (a probe's Variant `:=` broke the player rig; no suite loaded the probe).
- **Approach:** To run a template's own tests, run `gds template test <t>` from your worktree (see above); it makes the
  game from the working tree each time. **Watch out for:** `templates/<t>/game` has no GdUnit addon, so its tests
  cannot run there, and a game made by hand earlier keeps the template as it was (the old `.tres` and scene of a
  dropped approach stayed in it and broke every test until the game was made again); the template comes from the
  checkout whose `python` folder `--project` names, not the folder you stand in, so `--project` names the worktree's
  (the `game` line prints which checkout it used); `gds new game --local --workspace <folder>` builds the same way.
  **Seen:** gdstudio #830, 2026-11-08 (the command: gdstudio #917); gdstudio #857, 2026-11-09 (`gds new game`);
  gdstudio #940, 2026-11-10 (the main checkout's `python` tested the main checkout's template).
- **Approach:** Give a new script or shader its `.uid` before `gds template test` with `gds template uids
  <template>` (the template's name, or a folder holding `project.godot`): it writes each missing file in Godot's form
  and leaves every valid one alone. A new asset's `.import` still comes from the kept game (`gds template game
  <template>`, import, copy it back). **Watch out for:** the layout check refuses a script without its `.uid` and the
  template's own folder cannot be opened to make one, so agents copied uids back from a kept game or wrote them by
  hand, and hand-made ones held text Godot never writes. **Seen:** gdstudio #1009, 2026-11-10; gdstudio #1068 (PR
  #1092), 2026-11-11; gdstudio #1148, 2026-11-11 (a suite written after the scripts); kit #1129, 2026-11-11 (the
  command).
- **Approach:** Read the source before the results: the first line of `gds template test` and `gds template game`
  (the `from` line in `gds new game`) is `kit <path> (<branch> at <commit>, ...)` and must name your worktree. Send a
  run's log to a new name in your own scratch folder or from `mktemp`, never a fixed name in the session scratchpad.
  **Watch out for:** a run showed another agent's worktree as the source: gds had built from the right checkout, but
  two agents sent their runs to the same `full2.log` in the shared scratchpad, and the later run's header landed in the
  file the first read back. **Seen:** gdstudio #1011 (PR #1019), 2026-11-10 (fix: gdstudio #1048, the `kit` line and
  `python/tests/test_kit_source.py` with two worktrees); gdstudio #1047, 2026-11-10 (`--project` of main's
  checkout built main; use `--project ./python`); gdstudio #1026 and #1148, 2026-11-11 (the same).
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
  icons). **Seen:** gdstudio #884, 2026-11-10; gdstudio #887, 2026-11-10 (nine weapon sounds copied from
another game with no `.import`: the full local run was green and CI's step failed).
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

## With `--local` {#with-local}

Only the local steps run. The command prints the GitHub steps it left out, for whoever publishes the game later:
create the repository and push `main`; Pages' source to GitHub Actions and the three `groundwork.py ... --apply`;
`gh workflow run hold-sweep.yml`; `[repos.<name>]` in the kit's `workspace.toml`. The kit's CI makes its template
check this way (`gds new game template-check --template 3d-blank --local`), then exports the web build and boots it in
headless Chromium ([the boot check](web-probes.md#boot-check)).

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
| `3d-blank` | The shared base: a bounded floor and walls on the grid surface (cell size and editor snap from one project value), sky, sun, baked light, a Forward+ graphics profile (Compatibility on the web and phones), `ProtoBlock` for the floor and walls (resize them in the inspector), Phantom Camera with a static view camera, the touch controls component (real `Control` nodes you arrange in the 2D editor), a `WebProbe` that CI's [boot check](web-probes.md#boot-check) waits for, the folder layout and the web export ([Prototype surfaces and daylight](prototype-surfaces.md#web-first-rework)); every template follows [the checklist](#template-checklist). | made; trimmed to this in #821, the checklist applied in #831 |
| `3d-third-person` | `3d-blank` plus a character controller (walk, run, sprint, crouch, prone and crawl, jump), a Phantom Camera third-person view with sprint and aim views, touch controls bound to it, the Quaternius female and male mannequins (the female is the default) with the Universal Animation Library 1 and 2, a pistol with a crosshair, projectiles and targets, bullet impacts (marks, effects and sounds by surface), a minimap and a full-screen map ([Minimap](minimap.md)), an assault rifle model, a muzzle flash and the pooled effect emitter both use, the first sounds, a main menu, pause menu and settings with rebinding, an inventory screen (the live model, the weapons, a bag of items: [Inventory](inventory.md)), and the #788 prototype map with its components, a crouch course, a range and two map sections for AI and pathing work ([The 3D Third Person template](third-person-template.md), [Map sections](map-sections.md)). | made in #821, crouch, pistol and sounds in #836 |
| `3d-first-person`, `3d-universal`, `3d-top-down`, `3d-vehicle` | Controllers and sample content on the same base, filed one at a time after the one before it is tested. | planned |

What each template plays, and on which bus (the buses and the volume node are in [Audio](audio.md#template-buses)):

| Template | Sound | Played by | Bus |
| --- | --- | --- | --- |
| `3d-blank` | the wind loop (`assets/audio/wind/`) | the `Wind` player of `main.tscn`, from the start | `Ambient` |
| `3d-third-person` | the wind loop, at -20 dB (replace it by changing the `stream` of the one `Wind` player; level and bus stay) | the same `Wind` player | `Ambient` |
| `3d-third-person` | footsteps (four soft thuds, `assets/audio/footsteps/`) | `Footsteps` (`Step` at -20 dB, `CrouchStep` at -29, `LandStep` at -15), a step each time a foot of the animated skeleton lands | `SFX` |
| `3d-third-person` | the coin (four files, `assets/audio/coin/`) | the `Sound` node of every `Pickup` at -16 dB, one file a pickup | `SFX` |
| `3d-third-person` | a pistol shot (five files, `assets/audio/pistol/`, Deadnight's House Pistol, MIT) | the `ShotSound` of `Weapon`: an `AudioStreamRandomizer` (pitch spread 4%, +-1 dB) at -22 dB, three voices | `SFX` |
| `3d-third-person` | bullet impacts (nine files, `assets/audio/impacts/`: default, wood and metal, three each, synthesised by `tools/audio/impact_sounds.py`, MIT) | the `sound` of each `ImpactSurface`'s `EffectDef`, played at -10 to -14 dB from the `EffectEmitter`'s pool | `SFX` |

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

## What every template is built and reviewed against {#template-checklist}

<!-- new section: the page said what a template holds; nothing said what its scripts, scenes and tests must do so that
     people and agents can tune and read them (gdstudio #831) -->

A template is a starting point that people open in the editor and agents read as text, so its parts follow one
contract. A new template is built to it and every change to a template is reviewed against it; the review lists a line
per component (passes, or what was fixed). The twelve items, each with its reason:

Items 1 to 9 are for the **inspector** (what a person sees and changes), 10 to 12 for **agents** (what makes the
template cheap to change):

1. **Every value a developer would tune is an `@export`**, in a named group (`@export_group`, `@export_subgroup`),
   with a range and a unit suffix where it has one, a `##` tooltip and a default that plays well; internals are not
   exported.
   *Why:* the inspector is where a game gets tuned, and a number in a script constant cannot be found there.
2. **A change takes effect at once**, in the running game and the remote inspector: a value is read where it is used, or
   applied through a setter, and never copied once in `_enter_tree()` or `_ready()`. *Why:* tuning while the game runs
   is the fast loop, and a copy made at load silently ignores the edit.
3. **A value with a visible effect in the editor is a `@tool` script** (a camera's distance and field of view, a
   platform's path, a door's size, a block's size and colour, a trigger's shape, a spawn point's facing): the viewport
   shows the change. Gameplay, input and signal wiring stay off in the editor (`Engine.is_editor_hint()`). *Why:* a
   person tuning a map should see the map change, not run it to find out.
4. **Nothing generated at edit time is saved into a scene**: a `.tscn` holds what a person or agent put there and
   nothing more. *Why:* generated data is noise in a diff and goes stale; the one exception is a lightmap's UV2 mesh,
   which only the editor can make (the `ProtoBlock`).
5. **No node shows `<empty>` for something it needs, and none carries a configuration warning when its scene opens**; a
   node that needs another says so through `_get_configuration_warnings()`. *Why:* a warning on opening is the first
   thing a new person sees, and it teaches them to ignore warnings.
6. **Shared tuning lives in a `.tres` resource** (`player_tuning.tres`) and an edit to the resource applies live (its
   `changed` signal). *Why:* a copy of the file is a second feel, and the resource is one place to diff.
7. **Node references are exported (`@export var x: Node3D`) or unique names (`%Name`)**, never long hard-coded paths,
   and **a part a person is expected to replace (a model, a weapon) is never referenced by its own node name or unique
   name**: it sits under a stable slot node, and everything else references the slot (an export) and asks it for the
   part. *Why:* a component then works when it is moved or reused, and a replaced part is deleted, so the editor empties
   every path that pointed at it, and a dropped-in scene takes its file's name and is not unique
   (the model swap in #844; [Replacing the model](third-person-template.md#replacing-the-model)). A unique name on a
   node between the owner and the part also turns the `AnimationTree`'s root into a `%Name/...` path that the editor's
   helper player cannot resolve.
8. **Each component works alone** when dropped into an empty scene and set up from the inspector, and talks to the others
   through signals. An area that senses bodies says which ones by its mask (the named layers of
   [Physics layers](physics-layers.md#template-layers)) and, behind it, which ones count (characters, props, any) in an
   export, and by default ignores the level and itself. *Why:* a template that only works whole cannot be taken apart,
   and in a level where every body shares layer 1 an area that counts any body is triggered by the floor beside it
   (the gate door in #845 and the pressure pad in #848).
9. **Whatever a person sees or places is real nodes in its scene**, laid out in the editor: UI (the touch stick, look
   zone and buttons as `Control` nodes with anchors), the HUD, markers, spawn points and map pieces. Scripts hold
   behaviour; they do not build or `_draw` visible parts at run time. *One exception:* a shape that is only a function
   of exports and that no node draws (the HUD's `Crosshair`: a filled circle and a thin ring, `ui/hud/crosshair.gd`)
   may be a `Control` that `_draw`s itself, as long as the node is in the scene, placed by anchors, shows in the editor
   (`@tool`) and its look is exports; the alternative is a texture file for a shape that must scale to any size.
   *Why:* a developer opening the scene sees what is there and moves or restyles it there, and an agent reads the
   `.tscn` text for placements as easily as code.

10. **Generated structures stay in code only where a scene could not hold them well** (the animation tree's graph, built
    in code with `@tool` so the editor shows it). Typed GDScript, short scripts, a `##` doc comment on every class,
    export and signal. *Why:* code is what agents change most reliably, and a graph of many nodes is not worth placing
    by hand.
11. **Scene and resource files stay small and diff cleanly**: no editor-only state, no generated data, stable node names.
    *Why:* a review reads the diff.
12. **Every component has tests, in its home**: a component any game of any template can use unchanged is a script of
    the synced `addons/gds_game/`, proved alone in `godot/tests/gds_game/`; the template keeps its scene, its tuning
    and its in-the-map suites ([Sync](../../studio/sync.md#gds-game)). Each export's default is pinned (`ExportPins`,
    in the synced `addons/gds_game/testing/`) and a test changes each live export at run time and checks its effect.
    *Why:* a pinned default is a decision someone made, a test of the change is the only proof that item 2 holds, and a
    universal part copied into a template is never fixed in the games made from it.

A test of item 5 calls the script's own `_get_configuration_warnings()`: the engine's `get_configuration_warnings()` is
not callable from GDScript ("Nonexistent function"), and the script's list is the one a missing component adds to.

How it is proved: `gds check scripts` and an editor open of a fresh game (the probe of
[editor screenshots](editor-screenshots.md) prints each node's configuration warnings and what is empty, and saves each
scene to see that nothing generated is written), the suites with a pin and a live test per export, and the editor's own
remote-inspector message ([Changing values like the remote inspector](editor-screenshots.md#remote-inspector)).

- **Approach:** Build a new template to the twelve items and review a changed one against them, a line per component in
  the pull request (what was checked, what passed, what was fixed). **Watch out for:** 3D Third Person (#821) passed its
  tests and shipped with exports copied once at load (the camera, the capsule, the graphics profile, a door's sensor),
  map components that built their meshes and shapes in code so nothing showed in their scenes, and no pin of any
  default; the maintainer found two of these by using it. **Seen:** gdstudio #831, 2026-11-08.
- **Approach:** Make every visible part a node of its scene, laid out with anchors, and let a `@tool` script only read
  their places and apply the inspector's numbers to them. Mark the mesh, shape or material a script sizes
  `resource_local_to_scene = true` and look parts up by unique name (`%Panel`), which works from the instance's root.
  **Watch out for:** the touch controls were one empty `CanvasLayer` that drew the stick and buttons in `_draw`, and the
  door, platform, prop, pickup, zone and spawn point made children with `add_child` that the Scene dock never lists.
  A `@tool` script that sets a property of an instance's child does not dirty the scene that instances it (a level
  held no override after the editor saved it). **Seen:** gdstudio #831, 2026-11-08
  ([touch controls](ui-controls.md#touch-controls), [map components](third-person-template.md#map-components)).
- **Approach:** When a `@tool` script has to write into nodes that the scene file itself owns (not an instance's
  children), take the written values off in `NOTIFICATION_EDITOR_PRE_SAVE` and put them back in `..._POST_SAVE`, as the
  animation tree and the camera wrapper do. **Watch out for:** opening and saving `main.tscn` with the camera wrapper as
  a `@tool` script wrote spring length, margin, damping, offset and a computed transform onto the Phantom Camera, and a
  `@tool` `Player` wrote `floor_snap_length`; read the saved file once after making a part `@tool`. **Seen:** gdstudio
  #831, 2026-11-08 ([camera](camera.md#phantom-camera)).
- **Approach:** Pin the inspector contract of every node and resource with one fixture (`ExportPins.differences` and
  `wrong_values` against a dictionary of defaults) so a new export fails the suite until its default is pinned, and keep
  one suite per component under gdlint's twenty public methods. **Watch out for:** two suites went past twenty `test_`
  functions and gdlint (`max-public-methods`) failed them, and a float export compared with `is_equal` failed on a
  property that holds a float32 (use `is_equal_approx`). **Seen:** gdstudio #831, 2026-11-08; #846, 2026-11-09 (the
  ragdoll's 19 tests, two suites); #875, #879 and #881, 2026-11-10 (impacts, shake and menus split into suites per
  part; `duplicated-load`: a `preload` constant); #981, 2026-11-10, and #1094, 2026-11-11 (new exports unpinned until
  the full run: run the class's pin suite); #965, 2026-11-10 (a class split too).

- **Approach:** When a change adds a setting to an extending template's own `project.godot`, run
  `python/tests/test_new_game.py` before the push: it compares that file with the base's and lists each allowed
  difference. **Watch out for:** 3D Third Person's Jolt setting (#846) failed the kit's `test` job on all three systems
  with the template's own suite green, because the comparison only knew the input map and the orientation. **Seen:**
  gdstudio #846, 2026-11-10 (fix: the test strips and checks the Jolt line).

## Adding a template {#adding-a-template}

A template is a folder `templates/<name>/` with:

- `template.toml`: `title`, `description`, `default_description` (the README line when `--description` is not given)
  and, for a template built on another, `extends = "<base>"`.
- `game/`: files for the game's `game/` folder.
- `docs/`: pages for the game's `docs/` folder (`design/index.md` is the template's own page).

`extends` makes the base's files go in first and the template's on top, so `3d-third-person` holds a controller and
what changes in `main.tscn`, not a copy of the level. The folders `game` and `repo` of `templates/` are not templates:
`templates/game/` is what `gds sync` writes into every game, `templates/repo/` the repository files of a new one.
Something every existing game must receive belongs in `templates/game/` (synced), something only a new game needs in
`templates/repo/` or a template (copied once).

An extending template replaces a file of the base whole, with one exception: `game/project.godot` is merged. The
template's file holds only what it adds (3D Third Person: the menu scene as the main scene, the `Settings` autoload,
the landscape setting, the input map, the navigation cell height and Jolt), and `gds new game` reads the chain base
first and merges by section and key (`python/src/gds_tools/project_file.py`): a later key wins, the enabled plugins are
joined, and the file is written with the sections by name, as Godot does. A setting added to the base therefore reaches
every extending template without a copy to edit. Values are kept as the text they have, so the input map is never
re-written. Every other file, `main.tscn`, `assets/README.md` and `tests/test_main_scene.gd` among them, is still
replaced whole.

- **Approach:** A setting every game needs goes in 3D Blank's `project.godot` only; an extending template's file holds
  just its additions and is merged by `gds new game`. **Watch out for:** a hand-kept full copy drifted whenever the base
  gained a line (kit #846 failed CI that way), and a key an extending template sets must be one the base does not need to
  change (the later one wins). A key added to an extending template's file is also added to the list
  `python/tests/test_new_game.py` pins for it (`test_the_third_person_project_file_holds_only_what_it_adds`); run
  `uv run --project python pytest python/tests/test_new_game.py` before the push. **Seen:** gdstudio #928,
  2026-11-10; gdstudio #1075, 2026-11-11 (two navigation keys: the template suites passed and the kit's `test` jobs
  failed on the pinned list).
- **Approach:** When a script copies the branch's template files into a game made by `gds template game` (to test
  without making a new game), leave `project.godot` out and make the game again when the template's `project.godot`
  changes. **Watch out for:** the made game's `project.godot` is the merge of 3D Blank's and the template's (with the
  addons' autoloads); copying the template's file over it dropped `UIRouter` and `PhantomCameraManager`, and the next
  run printed dozens of parse errors that looked like the change's. **Seen:** gdstudio #890, 2026-11-10; gdstudio #966,
  2026-11-10 (a `cp -r` of the whole template folder: `UIRouter` not declared in 25 scripts, the game made again).
- **Approach:** When a script copies the branch's changes into a kept game, list them against the branch's base
  (`git diff --name-only <base>` plus untracked files), never only what is uncommitted, and prefer `gds template test`,
  which builds from the working tree each run. **Watch out for:** a sync of uncommitted files only left a mutated file
  in the game after the mutation was undone and committed, so the next run looked restored when it was not. **Seen:**
  gdstudio #968, 2026-11-11.
- **Approach:** A base template's test that reads the game scene finds its node with `find_child` (or by a group), never
  by a path from `main.tscn`, because an extending template replaces `main.tscn` and moves the node. **Watch out for:**
  3D Blank's `test_audio_settings.gd` asked the game scene for `AudioSettings` by name and failed in 3D Third Person once
  that node moved into `world/world.tscn`; only the full `gds template test` run found it, a run of the suites that
  name `main.tscn` did not; the same happened to 3D Blank's `test_web_probe.gd`, which asked `main.tscn` for its
  `WebProbe` while 3D Third Person made its probe at run time (a base test that names a node a template removes is
  replaced by a test of the same name in that template). **Seen:** gdstudio #927, 2026-11-10; gdstudio #921, 2026-11-10.

A template folder does not open clean on its own: its `project.godot` registers the `gds_ui` plugin and the `UIRouter`
autoload, but `addons/gds_ui/` is written into a game by `gds sync`, so a bare copy of `templates/<t>/game` fails to
load `res://addons/gds_ui/router/ui_router.gd` and drops the plugin. To run one outside a made game, copy it to a
probe folder in scratch (for an extending template, the base's `game/` first and the template's on top), then copy the
kit's `godot/addons/gds_ui/` and `gds_game/` to the probe's `addons/`; the import and a run are then clean (checked on
3D Blank with the pinned Godot, gdstudio #849; the probes of #838 and #847 were built this way). GdUnit4 is still missing
there, so tests run in a made game: `gds template test <name>` ([Proof](#proof)).

- **Approach:** After copying a template over a probe folder again, add the probe's editor plugin back to
  `editor_plugins/enabled` in its `project.godot` and look for the plugin's own line in the log before reading any
  result. **Watch out for:** the copy brings the template's `project.godot`, whose plugin list does not name the probe,
  so the editor opened, ran nothing and quit on its timeout with no error. **Seen:** the coordinator's handoff notes,
  2026-11-10 (an unlisted plugin never ran on the pinned 4.7.2, checked again for gdstudio #1003).

CI makes a game from every template on each kit change (a matrix over the templates), with the real Godot: it checks
the sync, the conventions, the layout, imports the project, parses every script, runs its tests and exports it for the
web (the `template` job of the kit's `ci.yml`). `python/tests/test_new_game.py` checks the local steps without Godot,
and `python/tests/test_new_game_github.py` each GitHub step with a fake `gh` and local bare repositories.

Those two files do not copy the real `templates/` (21 MB) for each test: a test about names, flags, licences, git and
GitHub steps gets a kit built once a session with `templates/repo/` and a few-file stand-in for 3D Blank
(`python/tests/fixtures/new_game_templates/`; `small_kit` and `small_git_kit` in `python/tests/conftest.py`, helpers in
`python/tests/new_game_kit.py`), and the tests about what the real templates hold read a game made once from the real
folder (`real_game`, `real_third_person_game`).

- **Approach:** A new-game test that needs a template to exist, not the real one, uses `small_kit` or `small_git_kit`;
  only a test that reads the real template's files uses `real_game` or `real_third_person_game`, which are made once
  for the module and only read. **Watch out for:** the old `kit` fixture copied all of `templates/` for each of 63
  tests (and committed and pushed it in the GitHub ones): 381 s of the 470 s of the suite, and Windows pytest was the
  longest CI job at 13 min 35 s; a test that writes into a shared game (a `title.txt` in the repository) breaks the
  tests after it, so write beside the game. **Seen:** gdstudio #918, 2026-11-10 (the review of #896 measured it).
- **Approach:** Make a repository once a session in a `scope="session"` fixture and copy it into each test with
  `python/tests/git_seed.py` (`relocate` rewrites the paths git wrote into `config`); share one run of a command
  between the tests that only read it (`default_flow`); leave out the step a test is not about (`kit_pr=False`); keep
  the seed small; pass `--fixed-fps 60` to an eval test's Godot. CI runs four workers, a file to each (`-n auto
  --maxprocesses=4 --dist loadfile`). **Watch out for:** a loaded machine moves wall time by 2x, so count processes
  per file too; a copied file costs 1 ms, a git process 30 to 110 ms; `copytree` of a git seed keeps its old origin
  path. **Seen:** gdstudio #945, 2026-11-10 (`pytest python/tests` 266 s to 157 s serial, 57 s on four workers).
