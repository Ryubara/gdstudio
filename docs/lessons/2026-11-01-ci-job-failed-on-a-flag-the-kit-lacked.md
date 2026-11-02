---
areas: [ci, net]
---
# A CI job passed a kit flag that the checked-out kit did not have yet

2026-11-01

- **Saw:** the `godot` job failed in 19 s: `gds: error: unrecognized arguments: --no-mcp`.
- **Cause:** a game's CI checks out the kit's `main`, and the game's pull request was written before the kit pull
  request that added the flag had merged.
- **Fix:** merge the kit change first, then rerun or push; read `gh run view --log-failed` before changing anything.
- **Docs:** none.
