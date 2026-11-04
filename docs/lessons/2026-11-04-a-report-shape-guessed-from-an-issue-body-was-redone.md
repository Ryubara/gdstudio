---
areas: [net, process]
---
# A backend interface guessed from the issue body had to be rebuilt when the backend landed

2026-11-04

- **Saw:** Deadnight #1059 built its report (a path per round, `final`, `user`, one-offs paid by the server from
  ticket claims) while #1075 ran in parallel; the merged backend takes one `POST /internal/matches/:id/report` with
  `kind`, `userId`, claims for the one-offs and a ticket of `xp`, `level` and `icon` only. The game side was rebuilt
  after.
- **Cause:** the two issue bodies named what is sent, not the path, the keys or who pays the one-offs, and the other
  side's worktree had no code yet; the shape was filled in from guesses and written down as if agreed.
- **Fix:** when two issues share an interface, write its exact shape (path, keys, who decides what) in the first issue
  that settles it, or ask the other task's agent for the route and the body before building; look at its pull request
  at each milestone, not only at the end.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
