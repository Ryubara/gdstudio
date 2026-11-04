---
areas: [process, tools]
---
# A blank draft held a checkpoint, and the diagnosis named only the other term

2026-11-04

- **Saw:** Tether's checkpoint did not clear a long coordinator session, and the context ran past 950,000 tokens
  against a limit of 300,000. Asked why, the coordinator blamed the stream of background notifications and stated that
  as the cause. The maintainer then named a stray Shift+Enter left in the prompt box.
- **Cause:** the checkpoint's rule is `quiet = !o.busy && o.draft === ''` (Tether 1.0.0-alpha.32,
  `src/checkpoint/cycle.ts`). The comparison is raw, so a lone newline counts as a draft and the checkpoint waits for
  ever. The same test elsewhere in Tether is `draft.trim() !== ''` (`notices/notice.ts`, `watch/findings.ts`), so wakes
  went on through the blank draft and the session kept growing. The coordinator read that line and reported only the
  `busy` half. It never had the draft's state, so it could not rule that half out. The draft itself was not observed
  after the fact either; the code shows it would hold the checkpoint, and the maintainer saw the newline.
- **Fix:** the kit holds no Tether code; the fix belongs in Tether (`draft.trim()`, and a limit on the wait).
- **Check for next time:** to say why a guard did not fire, list every term of its condition and mark each as ruled
  out by evidence or not checked. Report a cause as likely while any term is unchecked. When two places in a program
  test the same state, compare them: one written differently is a first suspect.
