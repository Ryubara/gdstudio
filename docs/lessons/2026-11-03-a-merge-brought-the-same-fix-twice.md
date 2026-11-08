---
areas: [process, general]
---
# A branch carried a second copy of a fix that main landed meanwhile

2026-11-03

- **Saw:** merging main into a long-running branch (Deadnight #678) conflicted on two files and silently doubled a
  third: a stub `has_voice` and an empty female voice folder (waiting for #679), and a `near_only` option on the grip
  measure with a test allowance, while main had landed the real female voices (#721) and the same far-hand fix (#727).
- **Cause:** the branch worked around a dependency it expected to wait for, and found a bug that others were also
  fixing; nobody re-read main between the days. A clean textual merge hid the second copy.
- **Fix:** after every `gds merge-main`, diff the branch against `origin/main` for each file it shares with a merged
  pull request (`git diff origin/main -- <file>`) and delete the branch's copy; wire the new thing to main's
  mechanism (here a `voice` in the frame entry, set from the chosen character) and drop the workaround and its test.
  Check a workaround's blocking issue before keeping it.
- **Docs:** this page; [starting work](../studio/starting-work.md).
