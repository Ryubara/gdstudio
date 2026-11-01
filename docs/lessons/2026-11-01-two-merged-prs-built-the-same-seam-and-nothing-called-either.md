# Two pull requests that merged together left a feature wired to nothing

2026-11-01

- **Saw:** the first playable night and a doors fix merged seconds apart; every check was green, yet the night rebuilt
  its navigation its own way and the new door classes had no caller.
- **Cause:** each pull request was tested against a `main` that lacked the other, and the doors fix replaced a seam the
  night had not been written against; no test ran the two together.
- **Fix:** an integration pull request that wires the night to the new classes, deletes the night's copy, and tests the
  join (a night that buys a door, and one that ends during the rebake). When pull requests touch one seam, name the
  other in Issues affected and merge origin/main before the last push.
- **Docs:** [Agents](../agents.md); Deadnight `docs/research/zombies.md`.
