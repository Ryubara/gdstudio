---
areas: [gameplay, tests]
---
# A floor measured on a fresh night read the work as free

2026-11-04

- **Saw:** Deadnight's extraction proposal (#1056) timed each map's chain with one real body in an empty night. "Seal
  every window" took 5.0 s and "fill the tank" took 0.0 s, so the back rooms' chain read 256 s. With every board down
  and half a tank, which is what a team finds when the chain opens, the seal took 46 s and the lot's tank 6 s, and the
  chain took 295 s. The first real nights had the same fault by another door: a seal and a full tank behind shut doors
  counted as done at the night's first tick. A run of real bots also lost its four-bot nights: `timeout` killed them at
  660 s and no report was written, so the cells were missing with nothing to say why. Then a grid's rows came back with
  quotas that grid had never run: eight nights at once, twice the machine's limit, and two grids writing one set of
  report names.
- **Cause:** a fresh night is the one state nothing has been used: full tank, whole windows, every door shut and no
  points. A step that asks for a state the night already starts in is done before it is begun, and the empty-night run
  that was meant to be the least a chain can take was less than the least. The probe stepped every open stage's steps,
  and only the assignment of workers looked at the door. The lost nights had one cause of their own:
  the report was written only at the end of a run, so the cut-off that kept the machine shared threw the run away.
- **Fix:** a floor starts from what the step will find, not from what the scene gives: the probe tears every board,
  draws the tank to half and sells the doors before the clock starts, and a step is not looked at until its door is
  open. A grid's first rows are read step by step before the rest is run: the missing seal row showed the fault after
  six nights of forty. Every long run takes its own end (`--wall=S`) and reports what it reached, with `cut_off` true,
  so a cut night is a partial answer and not a hole in the grid; the shell's `timeout` stays as the last resort.
  Stopping a background shell does not stop the `xargs` it started: the old grid went on launching nights from its list
  while the new one ran. Stop `xargs` by its id first, then its children, and count what is left. Reports are checked
  against the grid's list (quota, cut-off) and against the fault's signature (a step done that never opened) before
  they are read.
- **Also:** a reflow script merged two lists of the proposal into one paragraph, the same mistake as the lesson on a
  script that swallowed a constant. Wrap by hand, and read the page after any scripted edit.
- **Docs:** [Level design: P20](../gamedev/level-design.md#p20-an-objective-is-measured-not-read).
