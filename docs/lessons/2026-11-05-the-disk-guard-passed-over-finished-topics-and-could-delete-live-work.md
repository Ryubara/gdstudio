---
areas: [tools, process, tests]
---
# The disk guard passed over finished topics, and its holds had holes that could delete live work

2026-11-05

- **Saw:** the guard reported 0 B freed with 43 GiB in scratch, and #691 freed 28.61 GiB by hand. A report said the
  guard reads only `PR:` lines; the code said otherwise: it also tries the folder name as a branch and a 3-day clock.
  Replayed on a mirror of the folder as it stood before #691, the old guard freed 0.00 GiB from one topic.
- **Cause:** "finished" came from one spelling of one kind of reference, so topics naming their issue in `STATUS.md`
  were never judged, and the file list stopped at archives and numbered PNGs (no WAV, no log, no frame folder without
  numbers). The same gap ran the other way: `PR: #12`, the second number on a line and a number in prose were invisible
  to the holds as well. Reading the code for what must stay found more: a download folder was deleted whole with any
  `.md`, `kept/` or `.keep` inside it; an empty PowerShell answer read as "nothing is running"; the process list was up
  to 15 minutes old by the time scratch was judged; a folder that could not be listed counted as old. Every one of
  these failed open. `gh pr view` also fails on an issue's number, so reusing it for issues would have kept every such
  topic unknown for ever, and a fake that answers anything would have passed.
- **Fix:** a topic's work comes from its `PR:` and `Issue:` lines and the first lines of its notes; any note naming open
  work, an open issue or pull request naming its folder, a process saying its path or bare name, or a change in the last
  12 hours holds it, and any read that fails holds it. Captures go only from a topic known to be over: the clock alone
  frees the old list. A folder holding a note, `kept/`, `.keep`, `source` or a link is emptied around it. A sweep refusal
  names untracked, staged and modified files. States come from `gh issue list` and `gh pr list`, one call per
  repository, and a list that reaches its limit counts as unread.
- **Second miss, caught by the replay, not the tests:** the first version scanned every `*.md` and held 7.42 GiB. A
  copied `LICENSE.md` cites the game's tracking issue #252 and held 127 finished topics. Unit tests cannot show that:
  only real names did. A topic's notes now leave out what a repository carries. The replay frees 27.10 of the 28.61 GiB;
  1.26 GiB of the rest is in topics that do name open work. No `.md` (3,294), `kept/` file (87) or `.keep` was lost.
- **Check for next time:** a clean-up is written from what must stay, and each hold is proved twice: a test with the
  same topic cleared when nothing is live (else the test passes on a harness that never deletes), and a mutation that
  removes the hold and sees a test fail (6 of 34 first survived; 4 were real gaps in the tests, 2 are equivalent). Any
  check that cannot answer holds. A fake answers as the real tool does, including its refusals, and a tripwire in the
  suite proves the default route ends at it. Replay a rule over a mirror of the real folder before trusting its numbers:
  zero-byte files with real names, real notes and real ages, on temporary folders, never the real folder.
- **Docs:** [the disk guard](../workspace.md#disk).
