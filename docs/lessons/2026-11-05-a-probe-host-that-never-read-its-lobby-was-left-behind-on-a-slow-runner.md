---
areas: [tests, ci, net]
---
# A probe's host that never read its lobby was left behind on a slow runner

2026-11-05

- **Saw:** a browser probe (Deadnight `phone_join.py`, #1183) joined a friend's night on the maintainer's machine and
  failed on the CI runner: the phone's seat list read `1 Alex HOST` and the host `Hostess` was gone.
- **Cause:** the probe's host was plain HTTP calls: it made the night and never read it again. The lobby marks a member
  who has not read it for a few seconds away and drops it a while later; a software-rendered page takes a minute to
  load, so the phone arrived after the host was gone. The run on the fast machine took under that.
- **Fix:** a stand-in for a player that must still be there reads its lobby every two seconds, as the real screen does
  (a thread in the probe). Proved by the pair of runs that decide it: a silent host with a 90 s wait fails with the
  CI's own seat list, the same wait with the reads joins.
- **Check for next time:** a probe that waits for something slow (a page, a night) keeps every stand-in player alive
  the way its screen does, and is run once with the wait made long on purpose.
- **Docs:** [web export](../godot/web-export.md#a-phones-keyboard-in-the-web-build).
