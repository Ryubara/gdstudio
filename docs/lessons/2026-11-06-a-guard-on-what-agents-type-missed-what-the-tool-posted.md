---
areas: [tools, process]
---
# A guard on what agents type missed what the tool posted

2026-11-06

- **Saw:** the maintainer found comments under their account on issues and pull requests, against their decision of
  2026-10-12 that nothing comments on their behalf. The account held 682 comments in three repositories: 595
  were `gds` status lines ("Started by agent", "Unblocked", "Released"), and 87 were agents' notes.
- **Cause:** two hooks read the commands an agent types, and `gds` calls `gh` from Python, where neither reads. The gap
  was not hidden: `docs/studio/hooks.md` listed it and called it "by design", and a handoff carried it as an open question
  ("labels only?"). A written exception to a maintainer's rule reads as settled, so nobody treated it as a fault.
- **Fix:** `gds` posts nothing, and its one runner refuses every posting route (`posts_a_comment`), with a test that fails
  if a second way to run `gh` appears. The unused claim exception went from both hooks. The comments were deleted, with
  a local backup.
- **Next time:** enforce a rule about an effect where the effect happens, not only where someone asks for it. When a
  known gap contradicts a maintainer's rule, fix it in the task that finds it; never document it as a design or put it
  to them as a question. Same family as
  [a closing comment passed a rule that listed commands](2026-11-05-a-closing-comment-passed-a-rule-that-listed-commands.md).
- **Not covered:** a guard cannot see `curl` with a token or a script that runs `gh` by itself (`docs/studio/hooks.md#comments`).
