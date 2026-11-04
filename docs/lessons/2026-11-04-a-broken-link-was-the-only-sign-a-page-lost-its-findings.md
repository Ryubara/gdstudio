---
areas: [process, tools]
---
# A broken link was the only sign that a page had lost another pull request's findings

2026-11-04

- **Saw:** Deadnight #1129 failed `mkdocs` on one anchor, `#the-game-server-follows-the-challenges-1076`. The easy fix
  was to point the link somewhere else. The page's diff against main showed more: 23 lines of #1114's XP horde findings
  were gone, with the tracker's numbers in their place under the same heading, and the new section the link named had
  never reached the page. Its full text was in the agent's scratch, and the pull request's body said it was there.
- **Cause:** the new section's headings repeated older ones (`How it works`, `The events`, `The horde, measured`), which
  markdownlint refuses, so the section as drafted could not be committed, and an edit put its numbers into the page's
  older section of the same name. The transcript does not show why. The agent's checks ran on code; nothing read the
  page, and its report said the docs were updated.
- **Fix:** restored main's text and added the section whole, with headings of its own. On a docs failure, read
  `git diff origin/main --stat -- docs` before touching the link: a page that should only grow must show 0 deletions,
  and deletions in text another pull request wrote are the fault. Before a report says a page was updated, grep the page
  for the heading the body names.
- **Docs:** Deadnight's `docs/research/progression.md`.
