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
| Committed uids | Godot writes `<script>.uid` (and one for a shader) beside each; commit it, so moving a file does not break references. | `uid` |
| Dependencies run one way | `addons`, `assets` < `core` < `gameplay`, `world`, `net` < `ui` < the root scene. A file refers only to folders at its own level or below: `core` never names `gameplay`, `gameplay` never names `ui`. `tests/` and `tools/` and the root scenes may use anything. | `dependency` |
| Tools stay out of the build | Shipped code never names `res://tools/` or `res://tests/`, and every export preset's `exclude_filter` holds `tests/*` and `tools/*`. | `ships-tools`, `export` |
| Generated files outside `res://` | GdUnit's reports go to a folder outside the project (`-rd ../../reports`, relative to `game/`, never an absolute `/path`: GdUnit4 reads it as `res://`); none is committed under `game/reports/`. | `generated` |
| Third-party assets | Every third-party asset folder carries a `LICENSE.md` naming source and licence, and its credit reaches the game's Credits screen. | judgment (a maintainer decision to commit one) |
| Splitting a feature | Past about 30 scripts with clear clusters, a feature folder gets subfolders named for the clusters. | judgment |
| Suffixes, no type prefixes | Names say what a thing is with a suffix the codebase already uses (`_tuning`, `_def`, `_catalog`, `_state`, `_view`, `_server`, `_screen`, `_panel`), never a type prefix (`scr_`, `tex_`). Assets are `<subject>_<variant>_<n>`. | judgment |

- **Approach:** Make every number a designer would tune an `@export` of a `.tres` the game loads (groups, ranges, units,
  a `##` tooltip), pin each file's defaults in a test, and keep a scene map (which scene loads which, and which one is
  the main game) in the docs from the first playable. **Watch out for:** tuned numbers sat in script constants and code
  tables and nothing said which scene was which, while the maintainer meant to tune the game in the editor. **Seen:**
  Deadnight #415, 2026-11-02 (fix: a test pins each file's defaults and flags a new export).
- **Approach:** Before adding more than a few lines to a script within about 100 lines of gdlint's 1000-line limit
  (`wc -l`), put the new logic in a class of its own with one call in the old file, and lint after `gds merge-main` so
  the count is the merged head's. **Watch out for:** the night server and the rules sat at 998 and 997 lines, and a
  script 18 lines under the limit went red when main added 32 lines to it, since CI lints the merged head. **Seen:**
  Deadnight #687, 2026-11-03; Deadnight #1359, 2026-11-06 (fix: the perk and route rules moved into classes of their
  own).

- **Approach:** Give each screen a router hosts a dev entry scene that builds the same parts and starts its work
  itself (Deadnight: `game/dev/play_night.tscn`, options in the inspector), and say in the tuning guide to use it or
  go through the menu. **Watch out for:** a screen of the router starts its work in `screen_enter`, which only the
  router calls: F6 on `night_screen.tscn` instanced the scene, ran `_ready` and showed the loading card, never the
  night. **Seen:** Deadnight, 2026-11-02 (fix: the dev entry scene).

## What the check cannot see

`gds check layout` reads `res://` paths, so a dependency through a `class_name` (code that names `Player` from `core/`)
is not caught: keep `class_name` for the types a feature owns and let other folders use them only from above. It does
not judge whether a name means anything, or whether a feature folder has grown past a sensible size.

## Running it

```text
uv run --project <workspace>/repos/gdstudio/python gds check layout game
```

It prints one line per broken rule (`path: [rule] what is wrong`) and exits 1; a game's `conventions` CI job runs it
beside `gds sync --check`. The rules and the order are in `python/src/gds_tools/layout.py`, with a test for each in
`python/tests/test_layout.py`: a new rule is a kit pull request, not a game's exception.

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
  matched and read `git diff` of every file it touched before the commit).

## Where the rules came from

| Fact in Deadnight | Rule it made |
| --- | --- |
| `tools/ci/warm_GdUnitCmdTool.gd` is the one non-snake first-party file; 8 of 625 class names do not match their file | `snake-case`, `class-name` |
| 939 of 942 `ext_resource` lines have no UID, so a move needs path rewrites | `uid`, and `class_name` for code references |
| `core/` is not a foundation: `main.gd` reaches about 29 files elsewhere, and folders depend on each other both ways | `dependency` |
| `core/settings.gd` reads a `res://tests/` path as the sign of a test run | `ships-tools` |
| `reports/` is local GdUnit output with 18 pointless `.import` files | `generated`: reports go outside the project |
| `drivein`/`drive_in`, `smallmap`/`small_indoor`/`SmallMap`, `audio`/`eleven`: one subject under several names | `snake-case` catches `SmallMap`; one vocabulary per subject is judgment |
