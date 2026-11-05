# Sync

Some files live in every game but belong to the kit. The kit is their one source.

| What | Kit source | Game copy |
| --- | --- | --- |
| Agent definitions | `.claude/agents/*.md` | the same path |
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
