# Project conventions

The folder, naming and dependency rules of every GDStudio game's Godot project. They come from a review of
Deadnight's `game/` (hundreds of scripts in twelve feature folders): the by-feature layout held up, and drift showed
in the places where nothing named a rule. The 3D Blank template ([New game](new-game.md)) starts every game with this
layout, and `gds check layout` is the part of this page a program can judge, so a game's CI fails on an exception
instead of a review having to notice it.

```text
game/
  project.godot  main.tscn  default_bus_layout.tres  export_presets.cfg
  addons/    gds_* (kit-synced, tracked); gdUnit4 and godot_mcp (installed, untracked)
  core/      autoloads and foundations: no game words, no imports from features
  gameplay/<feature>/   script, scene and tuning resource together
  ui/<area>/  ui/skin/
  world/<map>/  world/lighting/
  net/       only if the game is multiplayer
  assets/<domain>/<subject>/
  tests/<feature>/test_<source>.gd     suites only; shared helpers in tests/fixtures/
  tools/     captures, benches, probes: left out of the export
```

## Rules {#rules}

| Rule | What it says | Checked as |
| --- | --- | --- |
| By feature | A feature's script, scene and tuning live in one folder (`gameplay/player/`), not spread over `scripts/`, `scenes/` and `resources/`. Godot's own [project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html) page groups assets as close to the scenes that use them as possible. | `top-level`: the project root holds only the folders above |
| snake_case | Every file and folder is lowercase words joined by `_`. `README.md`, `LICENSE`, `LICENSE.md`, `CREDITS.md`, `NOTICE.md` and dot files keep their names. Third-party code lives in `addons/` and keeps its own. | `snake-case` |
| Folders named for things | No `common`, `misc`, `vendor`, `utils`, `util`, `helpers`, `stuff`, `temp` or `tmp`: a folder that has to be called one of these has no owner yet. | `vague-folder` |
| The file is the class | A script's `class_name` is its file name in PascalCase (`ui_router.gd` holds `UIRouter` or `UiRouter`). | `class-name` |
| A scene beside its script | The script on a scene's root node has the scene's name and folder (`player.tscn`, `player.gd`). | `scene-script` |
| Committed uids | Godot writes `<script>.uid` (and one for a shader) beside each; commit it, so moving a file does not break references. The text is one Godot writes (`uid://`, then `a`-`y` and `0`-`8`, at most 63 bits): never a hand-made one. In a template, `gds template uids <template>` writes the missing ones. | `uid` |
| Dependencies run one way | `addons`, `assets` < `core` < `gameplay`, `world`, `net` < `ui` < the root scene. A file refers only to folders at its own level or below: `core` never names `gameplay`, `gameplay` never names `ui`. `tests/` and `tools/` and the root scenes may use anything. | `dependency` |
| Tools stay out of the build | Shipped code never names `res://tools/` or `res://tests/`, and every export preset's `exclude_filter` holds `tests/*` and `tools/*`. A probe that the exported game itself must carry (a browser test reads `window.gdprobe` from the web build: `ui/probe/web_probe.gd`, which a scene's script adds at run time on `?probe`, so no scene holds it) is shipped code, not a tool: it lives under `ui/probe/`, does nothing unless asked (the page has `?probe`), and names nothing in `tools/`; the script that drives it stays in `tools/web_smoke/`. | `ships-tools`, `export` |
| An addon the kit puts in a game is registered | `gds sync` copies `gds_ui` into `addons/` and enables nothing (the 3D Blank template also commits Phantom Camera, registered the same way): the game's `project.godot` enables `res://addons/gds_ui/plugin.cfg` under `[editor_plugins]` and has `UIRouter="*res://addons/gds_ui/router/ui_router.gd"` under `[autoload]`, as the plugin does when it is enabled. Without the autoload the addon's demo and focus ring do not parse. | `addon-plugin`, `addon-autoload` (`gds sync` also warns) |
| Shared gameplay code lives in the kit | A part any game of any template can use unchanged (the effect pool, `TriggerZone`, the suites' `ExportPins` and `InputSim`) is a script of the synced `addons/gds_game/`, edited in the kit and written into games by `gds sync`; the template keeps its scenes and tuning ([Sync](../../studio/sync.md#gds-game)). No other script declares one of the addon's classes. | `addon-class` |
| Generated files outside `res://` | GdUnit's reports go to a folder outside the project (`-rd ../../reports`, relative to `game/`, never an absolute `/path`: GdUnit4 reads it as `res://`); none is committed under `game/reports/`. | `generated` |
| Third-party assets | Every third-party asset folder carries a `LICENSE.md` naming source and licence, and its credit reaches the game's Credits screen. | judgment (a maintainer decision to commit one) |
| Splitting a feature | Past about 30 scripts with clear clusters, a feature folder gets subfolders named for the clusters. | judgment |
| Suffixes, no type prefixes | Names say what a thing is with a suffix the codebase already uses (`_tuning`, `_def`, `_catalog`, `_state`, `_view`, `_server`, `_screen`, `_panel`), never a type prefix (`scr_`, `tex_`). Assets are `<subject>_<variant>_<n>`. | judgment |
| No shadowed names | A local variable, parameter or member never takes the name of a property of the node's own class or a global (`scale`, `offset`, `name`, `position`); pick a name that says what it is (`gravity_scale`). [GDScript: names and types](gdscript.md#names-and-types) has the detail. | the templates' `project.godot` sets `shadowed_variable`, `shadowed_variable_base_class` and `shadowed_global_identifier` to errors, so the script fails to load and the template proof fails |

- **Approach:** Make every number a designer would tune an `@export` of a `.tres` the game loads (groups, ranges, units,
  a `##` tooltip), pin each file's defaults in a test, and keep a scene map (which scene loads which, and which one is
  the main game) in the docs from the first playable. **Watch out for:** tuned numbers sat in script constants and code
  tables and nothing said which scene was which, while the maintainer meant to tune the game in the editor. **Seen:**
  Deadnight #415, 2026-11-02 (fix: a test pins each file's defaults and flags a new export); gdstudio #904,
  2026-11-10 (`MenuScene.server_scene` added without its pin; `grep -rl <Class> tests` finds the pin suite);
  gdstudio #1255, 2026-11-11 (new `WeaponDef` fields unpinned: grep the tests for `pistol.tres` too); #1438, 11-13
  (`GaitSettings`, `test_gait_parts.gd`).
- **Approach:** Before adding more than a few lines to a script within about 100 lines of gdlint's 1000-line limit
  (`wc -l`), put the new logic in a class of its own with one call in the old file, and lint after `gds merge-main` so
  the count is the merged head's. **Watch out for:** the night server and the rules sat at 998 and 997 lines, and a
  script 18 lines under the limit went red when main added 32 lines to it, since CI lints the merged head. **Seen:**
  Deadnight #687, 2026-11-03; Deadnight #1359, 2026-11-06 (fix: the perk and route rules moved into classes of their
  own); gdstudio #1041, 2026-11-10 (3D Third Person's `character.gd` at 1000 lines failed three pull requests that each
  passed alone; four parts moved into modules: [the body's modules](third-person/character.md#controller)); #1187,
  11-11 (`main` over it: the pre-push hook refused every push).
- **Approach:** After writing a new script or shader in a template, run `gds template uids <template>` and commit
  the `.uid` files it writes (Godot's form; a valid file is never changed, an invalid one exits 1 until
  `--replace-invalid`). Never write a uid by hand. **Watch out for:** uids copied from a kept game were left behind
  and failed the `uid` rule in CI, and hand-made ones held a `z`, a `9`, a word or over 63 bits, which Godot imports
  silently. **Seen:** gdstudio #845, #868, #872, #925 (11-08 to 11-10); #910, #1074, #1091, #968 (36 at
  once; 2026-11-11); #1186 (a
  bench built with `bench-web`, which never checks layout); seven hand-made uids replaced, kit #1129, 2026-11-11; a
  suite added after the first `gds template uids` run failed the full run's layout step, gdstudio #1187, #1052, 11-11
  (run it again after the last new script); PR #1171, 11-12 (two `-s` tool scripts); #1438, 11-13.

- **Approach:** Run a Python tool that writes a cache (`ruff`) on a template's script with `--no-cache`, import or load
  a template's module with bytecode off (`PYTHONDONTWRITEBYTECODE=1`, or `sys.dont_write_bytecode` in a kit test), and
  run `gds check layout templates/<name>/game` before the push. **Watch out for:** a left `.ruff_cache/` or
  `__pycache__/` failed the layout check (`snake-case`) and `test_new_game.py`, like a fault of the change.
  From the kit's root ruff reads no config and wraps a template's Python at 88: pass `--line-length 120` (to undo an
  88 run, first `--config "format.skip-magic-trailing-comma=true"`). **Seen:**
  gdstudio #884, 11-10; #908 (`tools/net/__pycache__`), #1110 (a kit test loading `bad_network.py` failed CI's
  `test_layout.py`), #1106, #1105 (gate files rewrapped), 11-11; #1040 (a sweep); #1293, 11-12 (Blender's).

- **Approach:** Give each screen a router hosts a dev entry scene that builds the same parts and starts its work
  itself (Deadnight: `game/dev/play_night.tscn`, options in the inspector), and say in the tuning guide to use it or
  go through the menu. **Watch out for:** a screen of the router starts its work in `screen_enter`, which only the
  router calls: F6 on `night_screen.tscn` instanced the scene, ran `_ready` and showed the loading card, never the
  night. **Seen:** Deadnight, 2026-11-02 (fix: the dev entry scene).

## What the check cannot see {#what-the-check-cannot-see}

`gds check layout` reads `res://` paths, so a dependency through a `class_name` (code that names `Player` from `core/`)
is not caught: keep `class_name` for the types a feature owns and let other folders use them only from above. It does
not judge whether a name means anything, or whether a feature folder has grown past a sensible size.

## Running it {#running-it}

```text
uv run --project <workspace>/repos/gdstudio/python gds check layout game
```

It prints one line per broken rule (`path: [rule] what is wrong`) and exits 1; a game's `conventions` CI job runs it
beside `gds sync --check`. It reads files only. What it cannot judge, whether every script parses, is
`gds check scripts game` ([New game](new-game.md#proof)); a template's suites run with both checks in
`gds template test <name>`. The rules and the order are in `python/src/gds_tools/layout.py`, with a test for each in
`python/tests/test_layout.py`: a new rule is a kit pull
request, not a game's exception.

`game` is the folder argument, read from where you stand: in a game's checkout it is that game's `game/`. A template
has no checkout of its own, so check it with `gds check layout templates/<name>/game` from the kit worktree's root, or
through `gds template test <name>`, which runs the layout check in the game it makes.

- **Approach:** Check a template's layout with `gds template test <name>` (or `gds check layout templates/<name>/game`
  from the kit worktree), not with the bare `gds check layout game` of a game's docs. **Watch out for:** run from the
  kit worktree's root, `gds check layout game` found no project there, and nothing on this page or the godot-engineer
  page said where a template's check runs. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11.

## Editing a file by script {#scripted-edits}

<!-- new section: the page lists the layout rules; the line-length limits of the commit hooks, which a scripted edit
breaks without anyone reading the line, had no home -->

The general rules of an edit made by a script (escapes, working from the end, reflowing only your own text) are in
[The shell and scripted edits](../../studio/shell.md#scripted-edits); this section is the line limits a Godot
project's hooks hold.

- **Approach:** After a scripted word or number change, measure the lines it touched in every file type it touched
  (`awk 'length>100'` on `.gd`, `length>120` on `.md`), or run `uvx pre-commit run --all-files` once and fix all of its
  output in one pass, and rewrap by hand. **Watch out for:** a script replaced `62` with `64` and added words inside
  existing comment and doc lines, so they grew past the limit; each hook stops at its first failing group, so one UI fix
  was refused four times in a row (`gdlint` at 100, then `markdownlint` MD013 at 120, one line at a time); a
  clean-up regex for empty parentheses, run over whole files, also cut `()` out of code. **Seen:** Deadnight,
  2026-11-05; gdstudio #770, 2026-11-07 (fix: both limits checked on every touched file; limit a script to the spans it
  matched and read `git diff` of every file it touched before the commit); gdstudio #1059, #1120.

## Where the rules came from {#where-the-rules-came-from}

| Fact in Deadnight | Rule it made |
| --- | --- |
| `tools/ci/warm_GdUnitCmdTool.gd` is the one non-snake first-party file; 8 of 625 class names do not match their file | `snake-case`, `class-name` |
| 939 of 942 `ext_resource` lines have no UID, so a move needs path rewrites | `uid`, and `class_name` for code references |
| `core/` is not a foundation: `main.gd` reaches about 29 files elsewhere, and folders depend on each other both ways | `dependency` |
| `core/settings.gd` reads a `res://tests/` path as the sign of a test run | `ships-tools` |
| `reports/` is local GdUnit output with 18 pointless `.import` files | `generated`: reports go outside the project |
| `drivein`/`drive_in`, `smallmap`/`small_indoor`/`SmallMap`, `audio`/`eleven`: one subject under several names | `snake-case` catches `SmallMap`; one vocabulary per subject is judgment |
