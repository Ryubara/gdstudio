# Sync

Some files live in every game but belong to the kit. The kit is their one source.

| What | Kit source | Game copy |
| --- | --- | --- |
| Agent definitions | `.claude/agents/*.md` | the same path |
| The `gds_ui` Godot addon ([UI controls](../engines/godot/ui-controls.md#where)) | `godot/addons/gds_ui/` | `game/addons/gds_ui/`, the same `res://` path |
| Hook launcher and its settings | `templates/game/.claude/` | `.claude/` |
| The web boot check ([browser probes](../engines/godot/web-probes.md#boot-check)) | `templates/game/game/tools/web_smoke/boot_check.py` | `game/tools/web_smoke/boot_check.py` |
| The checker for titles, messages, descriptions | `.github/scripts/groundwork.py` | the same path (it reads the game's own `.github/conventions.yml`) |
| The hold's check and its sweep (only the label name is read from them, so one copy fits every game) | `.github/workflows/hold.yml`, `hold-sweep.yml` | the same paths |
| The message-check hooks and the hook types to install | the blocks of `.pre-commit-config.yaml` between `# gds-sync:begin <name>` and `# gds-sync:end <name>` | the same blocks in the game's config |

```sh
uv run --project python gds sync <workspace>/repos/<game>            # write them into a game, update its lock
uv run --project python gds sync <workspace>/repos/<game> --check    # exit 1 if any copy differs from the kit
```

`gds sync` records each file's hash in the game's `.claude/gds-sync.json` (`files`, and `blocks` for the pre-commit
blocks). To change one of these files: edit it in the kit (a kit pull request), then run `gds sync` on each game in a
pull request of its own. A game's CI or pre-commit can run `--check` to refuse hand edits.

## Godot addons {#addons}

The kit's own Godot project (`godot/`) is where `gds_ui` is edited and tested. The names in `KIT_ADDONS`
(`python/src/gds_tools/sync.py`) are the addons the kit owns; the folder also holds third-party addons that
`gds workspace init` installs untracked (GdUnit4, the MCP addon), which are never synced. Each file of an owned addon,
the `.uid` files included, is copied to the same path under the game's `game/`, so a `res://addons/gds_ui/...` path or
an autoload in a game does not change. Inside an owned addon the game owns nothing: `--check` also fails for a file that
is in the game's copy and not in the kit (a hand-added file, or one the kit has dropped or renamed), and `gds sync`
removes it. To take a new version, run `gds sync <game>` in a game worktree and commit what it wrote. A game that has
never had the addon gets it, its plugin enabled and the `UIRouter` autoload added by hand once (`[editor_plugins]`
and `[autoload]` in its `project.godot`: a game's project file is its own); the 3D Blank template already has both.
`gds sync` prints a warning for a game that has the addon and lacks either line, and `gds check layout` fails on it
(`addon-plugin`, `addon-autoload`), because a script that names `UIRouter` (the demo, the focus ring) does not parse
without the autoload.

A template can also commit a third-party addon (3D Blank commits Phantom Camera, with a `LICENSE.md` entry beside it); it
is not synced, and `ADDON_REGISTRATIONS` lists its plugin and its `PhantomCameraManager` autoload the same way, so
`gds check layout` fails when a game drops either. A test compares the kit's own addons with `godot/project.godot` and
the committed ones with the 3D Blank template's.

- **Approach:** When the kit syncs an addon into games that enable nothing, put the addon's registrations
  (`[editor_plugins]`, `[autoload]`) in the template's `project.godot` and in the layout check's table
  (`ADDON_REGISTRATIONS`, compared with the kit's own `godot/project.godot` by a test), so a game cannot hold the code
  without them. **Watch out for:** a new 3D Blank game opened in the editor with five parse errors, since the
  template synced `gds_ui` but never registered the `UIRouter` autoload its demo names; the export had the same
  errors and was only given an exclude filter. **Seen:** gdstudio #814, 2026-11-08 (fix: the template registers both,
  layout and sync check them, and `gds check scripts` parses every script).

### Gameplay code every template shares: `gds_game` {#gds-game}

<!-- new section: gds_ui was the only owned addon; nothing said where a universal gameplay part lives, and three
branches chose three homes on one day (gdstudio #923) -->

`godot/addons/gds_game/` holds the gameplay code any game of any template can use (the maintainer's decision on
gdstudio #923, 2026-11-10): today the effect pool (`EffectDef`, `EffectEmitter`, `EffectSlot`), `TriggerZone` and the
suites' `ExportPins` and `InputSim`. It is scripts only: no `plugin.cfg`, no autoload, no scene. A `class_name` under
`addons/` is a global class without a plugin, so a game needs no `project.godot` line for it, and `gds sync` alone
brings it to a game made before it existed. Its suites are `godot/tests/gds_game/`, run by the kit's `godot` CI job
with `gds_ui`'s.

A part goes in `gds_game` when all three hold, and stays in the template otherwise:

1. any game of any template can use it unchanged: it names no template class (`Player`, `Weapon`), no template path
   (`res://gameplay/...`), no input action and no group but its own;
2. it is code whose look and numbers come from exports, the scene it sits on or a resource the game owns;
3. its suite proves it alone, building its nodes in code in the kit's project.

Scenes (`trigger_zone.tscn`, `effect_emitter.tscn`), tuning resources and presets, levels, the character and what names
it, the HUD and menu pages stay in the template and are the game's own; they use the addon's script by its `res://`
path. A suite that tests a part inside the template (in the map, with the player, through the template's scene) stays
in the template. An issue for a universal part names its home, `addons/gds_game/<folder>/`, and a branch that adds one
puts it there, never in a template's `core/` or `gameplay/`. `gds check layout` refuses a script outside the addon that
declares one of the addon's classes (`addon-class`), so no template or game carries a second, unsynced copy.

### A file that moved into a kit addon {#moved}

<!-- new section: moving template files into a synced addon leaves games made earlier with their own copies; nothing
said how they take the move -->

A template file moved into a kit addon keeps its `.uid` (`git mv` both), and every `res://` reference in the templates
names the new path in the same commit. `MOVED` in `python/src/gds_tools/sync.py` lists each move (old `res://` path ->
the addon's). `gds sync <game>` deletes a game's old copy and its `.uid` and rewrites `"res://<old>"` in the game's own
`.gd`, `.tscn`, `.tres`, `.cfg` and `.godot` files (not its addons or `.godot/`); `gds sync --check` reports an old copy
or an old path left as drift, so the game's CI fails until it is synced. A game's own change to the old file is in its
history and the sync's pull request shows the deletion. Entries stay in `MOVED`: a game may be synced for the first time
long after. Move a part only when no open branch has changed it (`gh pr list`, the worktrees); the next one waits.

- **Approach:** Move a universal part into `gds_game` with its `.uid`, add its line to `MOVED`, rewrite the templates'
  references, prove the script alone in `godot/tests/gds_game/` and keep the template's in-the-map suites where they
  are. **Watch out for:** a part copied into a template is never fixed in the games made from it: `playground`, made
  the same morning, already had 2 stale files of 43, and the template scenes name scripts by path only (no `uid=`), so a
  move without the rewrite breaks every scene that uses the script. **Seen:** gdstudio #923, 2026-11-10 (the review of
  #896 found the stale copies; first parts moved: the effect pool, `TriggerZone`, `ExportPins`, `InputSim`).

## Not synced: what a new game is made from {#templates}

`templates/game/` is the only part of `templates/` that `gds sync` writes. `templates/repo/` and each template
(`templates/3d-blank/`) are copied once by `gds new game` ([A new game from a template](../engines/godot/new-game.md))
and are the
game's own afterwards: changing them in the kit changes no existing game. A file every game must receive goes in
`templates/game/`.

## Pre-commit blocks {#pre-commit-blocks}

A game's `.pre-commit-config.yaml` is mostly its own (GDScript formatting, texture checks), so the kit owns only the
lines between the markers: `install-hooks` (`default_install_hook_types`, which includes `pre-push`) and
`message-checks` (`commit-title`, `commit-trailers`, `push-messages`; [Hooks](hooks.md#pre-push)). The kit's own config
is the source of both blocks, so the kit runs exactly what it gives the games. Inside a block `gds sync --check`
reports every difference; outside it the game is free, except that a hook with the id of a kit hook must not be
defined twice.

A game that has no markers yet is told so (`--check` fails, `gds sync` refuses and writes nothing). Once, wrap the
game's own copy of those hooks in the two marker lines and run `gds sync`: the block is then replaced by the kit's.

```yaml
# gds-sync:begin install-hooks (kit-owned: edit it in the kit, then run `gds sync`)
default_install_hook_types: [pre-commit, commit-msg, pre-push]
# gds-sync:end install-hooks
```

`gds issue start` installs the three hook types in a game and runs the `pre-push` hook once
([Starting work](starting-work.md#worktree)), but a game whose config has no `pre-push` hook has nothing to run;
syncing the blocks is what gives it one.

- **Approach:** When a file enforces a rule and a game also carries it, put it on the sync list in the same pull request
  that changes the rule, give a file that is only partly the kit's marked blocks, not an exception, and `grep` the games
  for any kit file you change. Prove a push hook with the real remote's name and tracking refs (`git -c
  remote.origin.pushurl=<bare> push origin <branch>`). **Watch out for:** `gds sync` copied the agent definitions and
  the templates only, so the checker and the pre-commit hooks existed twice with nothing comparing them: a fix to the
  commit-message check and a new `pre-push` hook never reached the games, and a merge with a `# Conflicts:` paragraph
  still reached CI.  **Seen:** Deadnight #503, 2026-11-02 (fix: `gds sync` copies `groundwork.py` and the marked blocks,
  and `--check` reports old copies and missing markers).
