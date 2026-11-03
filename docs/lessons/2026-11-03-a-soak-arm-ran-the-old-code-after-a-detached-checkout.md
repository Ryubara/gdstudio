---
areas: [general, tests]
---
# A soak arm ran the old code because `git checkout --detach HEAD` was run in the other worktree

2026-11-03

- **Saw:** an arm that set a new profile field (`--tune aims_off_weak_spot=true`) passed the boss night exactly as
  often as the arm without it, and a lens share of 72% that did not move (Deadnight #767).
- **Cause:** the arms ran from scratch checkouts moved with `git -C <checkout> checkout --detach HEAD`; `HEAD` there is
  the checkout's own, so it stayed on the old commit, the field did not exist, and the tune was printed as an error that
  nothing read. A second run into a folder that had just been deleted also kept writing chunks into it from the first.
- **Fix:** pass the commit's hash (`git rev-parse HEAD` taken in the branch's worktree), print `git -C <checkout> log
  --oneline | head -1` before starting, give every run a new output folder, and stop the old run by its process id
  before reusing a name.
- **Docs:** Deadnight `docs/research/bots.md#rookie-parity-767` (how the arms were run).
