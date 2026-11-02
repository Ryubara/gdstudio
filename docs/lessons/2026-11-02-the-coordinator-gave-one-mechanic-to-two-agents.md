---
areas: [process, gameplay]
---
# The coordinator gave one mechanic to two agents

2026-11-02

- **Saw:** Deadnight #511 (bots, for #224) built a revive (a `revive` rules action, `revive_channel.gd`, a `reviving`
  frame field) while the revive agent (#486) built a second one on its own branch; both touched `game_rules.gd`,
  `player_health.gd`, `night_server.gd` and the HUD binding. It was found only when the second branch was ready, and
  most of it was thrown away after #511 merged.
- **Cause:** the coordinator assigned #224 (bots revive teammates) and #486 (revive) to two agents without checking that
  one needed the other's mechanic; neither brief named the other branch or its files. The agent's side, not checking
  open pull requests before building, is its own lesson
  ([same system in two branches](2026-11-02-same-system-built-in-two-branches.md)).
- **Fix:** the older pull request lands first; the other rebuilds on it and keeps only what is new.
- **Check:** before assigning, compare each issue's mechanics with the open issues and pull requests (`gds issue list`
  with owners). When two need the same mechanic, one owns it and the other waits on it (`Waiting on #N`), and each
  brief names the open pull requests and files to stay out of.
- **Docs:** [Agents: the loop](../agents.md#the-loop).
