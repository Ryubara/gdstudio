# Sync

Some files live in every game but belong to the kit: the agent definitions (`.claude/agents/*.md`) and the hook
launcher with its settings (`templates/game/.claude/`). The kit is their one source.

```sh
uv run --project python gds sync <workspace>/repos/<game>            # write them into a game, update its lock
uv run --project python gds sync <workspace>/repos/<game> --check    # exit 1 if any copy differs from the kit
```

`gds sync` records each file's hash in the game's `.claude/gds-sync.json`. To change one of these files: edit it in
the kit (a kit pull request), then run `gds sync` on each game in a pull request of its own. A game's CI or
pre-commit can run `--check` to refuse hand edits.
