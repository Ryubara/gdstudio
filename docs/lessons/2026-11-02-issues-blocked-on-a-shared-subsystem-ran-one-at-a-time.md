---
areas: [process, tools]
---
# Issues blocked on a shared subsystem ran one at a time while the idle check passed

2026-11-02

- **Saw:** the maintainer pointed out that the rest of the issues were not being worked on. One agent was tuning bot
  following (Deadnight #564), and four more bot issues (#568, #229, #230, #231) were `S-blocked` on it. Only one
  issue, filed minutes earlier, could start.
- **Cause:** the coordinator blocked them with "the same bot brain; the agent takes them one at a time after #564".
  That is a preference for one agent, not a dependency. #229's `Depends on:` line names phases 0 to 3, not #564, and
  #568 changes the Rookie profile, not the follow code. The idle check counts a written block as a reason, so it
  passed. The example in `docs/starting-work.md` gave "the same bot brain; started one at a time" as a block, so the
  kit taught the habit. The same rule had already been raised twice that day (the rows on no open pull requests and
  on running every issue that can run in parallel); a block was the way around it.
- **Fix:** #568, #229 and the new #615 were started beside #564, each told to keep to its own part and merge
  `origin/main` before each push. #230 stays behind #229 (it needs phases 1 to 5) and #231 behind #230 (it measures
  them). `docs/starting-work.md#parallel` now says a block needs a `Depends on:` entry or named files; kit #218 makes
  `gds issue block` refuse anything else.
- **Check:** before `gds issue block --on "#N"`, read the blocked issue's `Depends on:` line. If #N is not in it and
  no file would be edited both ways, start the issue.
- **Docs:** [Starting work](../starting-work.md#parallel), [Hooks: idle issues](../hooks.md#idle),
  [A rule in memory is broken under pressure](2026-11-02-a-rule-in-memory-is-broken-under-pressure.md).
