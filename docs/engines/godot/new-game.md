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

- **Approach:** Prove a new game or template change with a parse of every script (`gds check scripts`) and an editor
  open, and when a script fails, find the registration or file it needs, never an export exclusion. **Watch out
  for:** a new 3D Blank game opened with five parse errors from the `gds_ui` demo (`Identifier "UIRouter" not
  declared`): the template synced the addon but never registered the autoload, and #778 met the same errors in the
  export, excluded the demo and proved only an import and a 60-frame run. Start a `-s` check script in `_initialize`:
  the autoloads join the tree after `_init`. **Seen:** gdstudio #814, 2026-11-08 (fix: the template registers the
  plugin and the autoload, and the parse check fails 5 of 329 scripts on the old template).
- **Approach:** To run a template's own tests, make a game from it (`gds new game <name> --template <t> --local
  --workspace <throwaway>`), copy each changed file into that game, and make a second one when the template's
  committed files changed after the first. **Watch out for:** `templates/<t>/game` has no GdUnit addon, so its tests
  cannot run there, and a game made earlier keeps the template as it was (the old `.tres` and scene of a dropped
  approach stayed in it and broke every test until the game was made again). **Seen:** gdstudio #830, 2026-11-08.
- **Approach:** Try `gds new game` in a throwaway workspace outside the real one: a folder of its own holding a copy of
  `.gdstudio-workspace`, `gdstudio.local.toml` and the addon folders under `tools/`, and in a test of a template's
  `project.godot`, read the file with `ConfigFile`. **Watch out for:** a throwaway folder inside the real workspace
  finds the real marker, so `gds new game` wrote `repos/zz-parse` into the real `repos/`; and
  `editor_plugins/enabled` is an editor setting that `ProjectSettings` does not hold at run time, so a test reading it
  there failed with the plugin enabled. **Seen:** gdstudio #814, 2026-11-08 (the stray repository deleted at once; the
  test changed to `ConfigFile`).

## With `--local` {#with-local}

Only the local steps run. The command prints the GitHub steps it left out, for whoever publishes the game later:
create the repository and push `main`; Pages' source to GitHub Actions and the three `groundwork.py ... --apply`;
`gh workflow run hold-sweep.yml`; `[repos.<name>]` in the kit's `workspace.toml`. The kit's CI makes its template
check this way (`gds new game template-check --template 3d-blank --local`).

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
| `3d-blank` | The shared base: a bounded floor and walls on the grid surface (cell size and editor snap from one project value), sky, sun, baked light, a Forward+ graphics profile (Compatibility on the web and phones), `ProtoBlock` for the floor and walls (resize them in the inspector), Phantom Camera with a static view camera, the touch controls component (real `Control` nodes you arrange in the 2D editor), the folder layout and the web export ([Prototype surfaces and daylight](prototype-surfaces.md#web-first-rework)); every template follows [the checklist](#template-checklist). | made; trimmed to this in #821, the checklist applied in #831 |
| `3d-third-person` | `3d-blank` plus a character controller, a Phantom Camera third-person view, touch controls bound to it, the Quaternius mannequin with the Universal Animation Library 1 and 2, and the #788 prototype map with its six components ([The 3D Third Person template](third-person-template.md)). | made in #821 |
| `3d-first-person`, `3d-universal`, `3d-top-down`, `3d-vehicle` | Controllers and sample content on the same base, filed one at a time after the one before it is tested. | planned |

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
7. **Node references are exported (`@export var x: Node3D`) or unique names (`%Name`)**, never long hard-coded paths.
   *Why:* a component then works when it is moved or reused.
8. **Each component works alone** when dropped into an empty scene and set up from the inspector, and talks to the others
   through signals. *Why:* a template that only works whole cannot be taken apart.
9. **Whatever a person sees or places is real nodes in its scene**, laid out in the editor: UI (the touch stick, look
   zone and buttons as `Control` nodes with anchors), the HUD, markers, spawn points and map pieces. Scripts hold
   behaviour; they do not build or `_draw` visible parts at run time. *Why:* a developer opening the scene sees what is
   there and moves or restyles it there, and an agent reads the `.tscn` text for placements as easily as code.

10. **Generated structures stay in code only where a scene could not hold them well** (the animation tree's graph, built
    in code with `@tool` so the editor shows it). Typed GDScript, short scripts, a `##` doc comment on every class,
    export and signal. *Why:* code is what agents change most reliably, and a graph of many nodes is not worth placing
    by hand.
11. **Scene and resource files stay small and diff cleanly**: no editor-only state, no generated data, stable node names.
    *Why:* a review reads the diff.
12. **Every component has tests**: each export's default is pinned (`ExportPins`, in `tests/fixtures/`) and a test
    changes each live export at run time and checks its effect. *Why:* a pinned default is a decision someone made, and
    a test of the change is the only proof that item 2 holds.

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
  property that holds a float32 (use `is_equal_approx`). **Seen:** gdstudio #831, 2026-11-08.

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

An extending template replaces a file of the base whole, it does not merge: `3d-third-person` carries its own
`project.godot` (the base's text plus the input map and the landscape setting; a kit test compares them) and its own
`main.tscn`, `assets/README.md` and `tests/test_main_scene.gd`.

CI makes a game from every template on each kit change (a matrix over the templates), with the real Godot: it checks
the sync, the conventions, the layout, imports the project, parses every script, runs its tests and exports it for the
web (the `template` job of the kit's `ci.yml`). `python/tests/test_new_game.py` checks the local steps without Godot,
and `python/tests/test_new_game_github.py` each GitHub step with a fake `gh` and local bare repositories.
