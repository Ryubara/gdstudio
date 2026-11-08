---
areas: [gameplay, godot, tests]
---
# A cut timed in two processes sat inside the noise; the old code beside the new in one process did not

2026-11-04

- **Saw:** Deadnight #947 cut the dead's per-step script (about 15 % of `sim.think`). Eight alternating runs of the
  old and new code as separate processes gave medians of -11 %, +9 % and -18 % for the same change on a machine with
  21 Godot processes up, and the real night (whose crowd is not the same crowd in the two arms) gave -3 % to -9 %.
  None of them could show the cut was real, or that the dead were unchanged.
- **Cause:** the machine's load moves each process by more than the cut, and two nights differ in what the dead are
  doing (42 % swinging at the players in one, 60 % in the other), so a label's mean changes with the crowd, not the code.
- **Fix:** a probe scene that holds both versions at once: the old `zombie_sim.gd` and `zombie_brain.gd` copied from
  `git show HEAD:` under other class names (`ZombieSimOld`), the same scripted night fed to both, which goes first
  alternating every step, the **median of the per-step times** of each, and the state of every dead compared after every
  step (it also proves the dead are the same, step by step). The ratio then read 0.82 to 0.85 in every repeat. A golden
  digest of the same night, taken on the old code and pinned in a test, keeps the proof after the copy is gone.
- **Check for next time:** to show a cost cut, copy the old class under a new name in the probe and time both in one
  process; report the ratio of per-step medians; compare their state in the same loop. Use a real night only for counts
  and for the shape of the crowd (how many dead are far, swinging, walking).
- **Docs:** [Performance budgets](../engines/godot/performance-budgets.md), reading a timing on a shared machine.
