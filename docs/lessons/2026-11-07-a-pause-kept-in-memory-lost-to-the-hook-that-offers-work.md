---
areas: [process, tools]
---
# A pause kept in memory lost to the hook that offers work

2026-11-07

- **Saw:** the maintainer paused Deadnight on 2026-11-07 so that kit work came first. Later that day the coordinator
  started Deadnight #1372 (a CI budget fault found while landing a docs pull request), and a Deadnight agent opened
  #1373 for it. The issue went back in the line only when the maintainer asked why Deadnight was being worked on.
- **Cause:** the pause lived only in the coordinator's memory and in the wording of the plan. No file a tool reads said
  that Deadnight was paused. The `Stop` hook listed #1372 under "These issues may start now and no agent has them",
  `gds issue list` offered it too, and the coordinator followed the tool over its memory. A standing rule that lives
  only in an agent's memory is overridden by the first tool that does not know it.
- **Fix:** `paused = "<reason, date>"` on a repository's entry of `workspace.toml` (kit #786), set for Deadnight. A
  paused repository's window holds only `P-critical` issues, so `gds issue start` refuses the others with the reason,
  `gds issue list` shows `PAUSED` and holds them, and the `Stop` hook lists none of them. A test covers each of the
  three and the `P-critical` exception.
- **Check:** before starting an issue, check that its repository is not paused (`paused` in `workspace.toml`). When the
  maintainer gives a standing rule (a pause, an order, a limit), move it into a file that a tool reads and enforces in
  the same session; until a tool enforces it, every tool that offers work will contradict it.
- **Docs:** [Starting work: pausing a game](../starting-work.md#paused).
