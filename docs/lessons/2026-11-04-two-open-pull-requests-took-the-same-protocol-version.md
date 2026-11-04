---
areas: [net, general]
---
# Two open pull requests took the same protocol version

2026-11-04

- **Saw:** Deadnight #1115 (levels beside names) bumped `NetWire.VERSION` to 15 while #1100 (the helicopter drop's
  `ARRIVAL` message) merged first with 15 and `MIN_VERSION` 15. Merging main conflicted in the header, the constants,
  the docs table and the tests that say hello as "the version before"; both numbers meant different layouts.
- **Cause:** a version is a number in a shared file that every wire change bumps by one, and nothing says which
  number an open pull request holds. Each author read "the next one" from main on the day they started.
- **Fix:** after `gds merge-main`, the later pull request takes the next number (16), keeps `MIN_VERSION` at the
  earlier one's when it only adds keys, and moves every test and doc line that named the old number (grep for the
  number and for `accepts(`). Check for next time: before bumping, `gh pr list` for open pull requests that touch
  `net_wire.gd`, and take the number after the highest one named there; re-read the constants after every merge of main.
- **Docs:** [Multiplayer](https://github.com/Ryubara/deadnight/blob/main/docs/research/multiplayer.md): the protocol row
  of Deadnight says which version added what.
