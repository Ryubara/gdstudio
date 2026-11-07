# Sync

Some files live in every game but belong to the kit. The kit is their one source.

| What | Kit source | Game copy |
| --- | --- | --- |
| Agent definitions | `.claude/agents/*.md` | the same path |
| The `gds_ui` Godot addon ([UI controls](godot/ui-controls.md#where)) | `godot/addons/gds_ui/` | `game/addons/gds_ui/`, the same `res://` path |
| Hook launcher and its settings | `templates/game/.claude/` | `.claude/` |
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
and `[autoload]` in its `project.godot`: a game's project file is its own).

## Not synced: what a new game is made from {#templates}

`templates/game/` is the only part of `templates/` that `gds sync` writes. `templates/repo/` and each template
(`templates/3d-blank/`) are copied once by `gds new game` ([A new game from a template](godot/new-game.md)) and are the
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
