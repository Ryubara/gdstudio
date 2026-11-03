---
areas: [gameplay, tests]
---
# A control soak in a fresh checkout ran for an hour and produced nothing

2026-11-03

- **Saw:** to tell a refactor from a balance change, a four-bot parity soak was started on the commit before the split,
  in a new detached worktree, beside the arm that mattered. The other arm finished in 31 minutes; the control's log had
  its header line only after 50 minutes, with two busy Godot processes and no chunk file. It had failed at the balance
  simulator step (`balance_cli.gd` exit 1), so the hour bought no control (Deadnight #827).
- **Cause:** the control was started in the background and not looked at again until the other arm ended. A fresh
  worktree is a different project folder: only `--import` was run there, and nothing checked that the first chunk
  and the simulator cells came out.
- **Fix:** after starting a soak in a new checkout, look at it within two minutes: the simulator file in `<out>/sim/`
  exists and the first chunk line is in the log (a four-bot chunk takes about 5 to 10 minutes; none after twice that is
  a failure). Run one night of one bot there first (`--nights 1 --cells rookie_1`) to see the whole path work. When
  a refactor is a pure move, a control is not worth an hour: test the move and say so.
- **Docs:** Deadnight `docs/research/bots.md`, the soak section.
