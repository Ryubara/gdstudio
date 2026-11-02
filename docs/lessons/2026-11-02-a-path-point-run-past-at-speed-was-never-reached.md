---
areas: [gameplay, tests]
---
# A bot that ran past a path corner turned back for it

2026-11-02

- **Saw:** in the stuck soak a bot cutting a corner at run speed slowed, turned round and walked back to the corner
  before going on, and the stuck detector counted the time as no progress.
- **Cause:** the path advanced only when the bot came within half the look-ahead (0.4 m) of its point; a bot that
  passed the corner at 0.6 m never did, so the point stayed the target behind it.
- **Fix:** a point is also passed once the bot is nearer the next point than this point is to the next point.
  `BotPath._advance` in Deadnight; the path unit tests feed a trace that cuts a corner.
- **Docs:** Deadnight `docs/research/bots.md` (phase 2, what the tests found).
