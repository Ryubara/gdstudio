---
areas: [net, general]
---
# A pull request built a second path for data another pull request landed

2026-11-04

- **Saw:** Deadnight #1115 (levels beside names) sent each seat's level from the ticket through `NightHost`, the
  WELCOME and a new `player_leveled` event, and bumped `NetWire.VERSION` to 15. While it waited, #1100 took 15 for
  `ARRIVAL` and #1114 landed the server's XP tally with its own seat levels (`xp.levels()`, `account_seated`,
  `level_up`, `account_left`). Merging main conflicted in five server files and the protocol header; most of the
  pull request's server side and its 11-case net test were replaced by what main already had.
- **Cause:** the issue said "the level comes from the ticket" and named the tally's wiring as later work, so the pull
  request built the whole path itself instead of asking what the tally pull request in flight would own. Two open
  pull requests were writing to the same files (`night_host.gd`, `client_state.gd`, `ticket_verifier.gd`,
  `net_wire.gd`) and nobody compared them.
- **Fix:** take main's files wholesale for the server and the protocol (no version bump: the new keys needed none),
  keep only what nothing else owned (the HUD, the setting, the lobby list), and let the HUD read the events main
  sends. Check for next time: before building a data path in shared net files, `gh pr list` the open pull requests
  that touch them and read their diffs; where one owns the data, build only the consumer and say so in the issue.
  The same check covers a protocol version: take the number after the highest one an open pull request names.
- **Docs:** none yet; this file is the record.
