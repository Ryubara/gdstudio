---
areas: [net, godot-ui]
---
# Two branches bumped the same snapshot version

2026-11-01

- **Saw:** two pull requests each changed the rules snapshot layout and each bumped `SNAPSHOT_VERSION` from 3 to 4; both
  merged cleanly, so one number named two layouts, and an old snapshot was refused as `malformed` instead of
  `bad_version`.
- **Cause:** a version bump is a one-line change git merges silently when both sides make the same edit.
- **Fix:** when a branch changes a serialized layout, merge `origin/main` right before merging and bump again if the
  version moved; check the version before any keys; keep a test with a snapshot from each older layout that must answer
  `bad_version`.
- **Also:** a feature that adds state to the snapshot must bump the version and add its `bad_version` test (match
  settings moved it to 9, Deadnight #449). The same rule holds for the network protocol version (`VERSION` and
  `MIN_VERSION`): several branches bump it at once (the scoreboard #472, the lag work #54, the delta work #57), so
  merge `origin/main` right before the final push and bump past main's number.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md); Deadnight `docs/research/rules-engine.md`.
