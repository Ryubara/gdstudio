# The rifle's trigger finger

<!-- new section: weapon-pickups.md went over 50 KB when gdstudio #1348 (the upright carry) met main's left-shoulder
     hold; the trigger finger's way is its own planned step of the hold, with its own tools and entries -->

How the 3D Third Person rifle's trigger finger goes from along the receiver onto the trigger without passing through
the rifle. Part of [the rifle in both hands](weapon-pickups.md#rifle-hands), whose fingers it moves.

## The trigger finger's way {#rifle-trigger}

- **The trigger finger's way** (kit #1036, kit #1283). The straight way from along the receiver to the trigger (a
  slerp of the two poses) takes the fingertip 19.9 mm (female) and 24.5 mm (male) into the magazine well and the
  trigger guard: the straight finger lies along the well's side ahead of the guard and curls in before it is over the
  guard's opening. `trigger_way` (a `HandPoseWay`, `HandPoseModifier.second_way`) is the poses the finger passes
  through instead, spread evenly over the raise, seven on each body: the knuckle lifts the finger off the receiver's
  side and turns it down and about its length (30 to 35 degrees, no more: a finger has only a little of that turn),
  the finger curls beside the rifle clear of the guard, then the knuckle brings the curled finger in through the
  guard's side onto the trigger. It is planned by `tools/hold/plan_trigger_way.py` on what
  `tools/hold/solve_trigger_way.gd -- <body> --dump=<file>` writes (that body's skinned finger as `HandContact`
  counts it, with that body's hold on, and the rifle's triangles): every pose of a grid of the knuckle's spread,
  bend and roll and the two joints' bends (4 million) is measured against the rifle's distance grid, a fine grid
  round each end leaves it (each end sits wedged on two faces), the shortest walk through the poses off the surface
  joins them, and it is cut to the fewest poses whose legs stay within 1.6 mm (two minutes a body).
  `solve_trigger_way.gd -- <body> --way=<file>` checks every leg at 40 steps with the game's own measure and writes
  the female's into `rifle_trigger_way.tres` and the male's into his fit (`HoldFit.trigger_way`), nothing when a
  step is deeper than 2 mm; run it after `write_hold.gd`, which keeps a fit's way. Measured at every hundredth of
  the raise (`test_rifle_fingers.gd`): at most 1.59 mm in (female) and 1.60 mm (male), against 3.7 and 4.6 mm for
  the way of two poses before (a roll of 90 and 105 degrees). The ends hold as before. The planner knows nothing of the
  rifle: the pistol's trigger finger is planned by it too, its dump adding the grid, the limit, the left hand's skin
  and depth read through thin parts ([between the poses](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md#between-the-poses));
  what both solvers share is `tools/hold/finger_way_files.gd`.

What went wrong before, and what to do instead:

- **Approach:** Measure a blend between two hand poses at its in-between steps too, and when the straight blend goes
  through the weapon, give the bones a way of poses round it (`HandPoseModifier.second_way`), solved on each body's
  skinned hand. **Watch out for:** the rifle's grip and trigger poses each held within 2 mm and the tests sampled
  only aim 0 and 1; a live test caught the finger half-way after a burst, 12.6 mm inside (the straight blend is 17
  to 24 mm deep). Poses put in at the deepest step stall when the end pose sits in a pocket (the trigger in its
  guard): try whole first ways (a roll, a bend, a turn) first. A way belongs to the poses it joins: once the grip
  place moved and each body had its own hold, it was solved again on each. **Seen:** gdstudio #1036, 2026-11-11
  (fix: `trigger_way` a body, `test_rifle_fingers.gd` sweeping the raise in 50 steps).
- **Approach:** Plan a finger's way round a part as a search over a grid of its poses (`tools/hold/plan_trigger_way.py`:
  every node measured, the shortest walk through the nodes off the surface, then cut to the fewest poses whose
  legs stay within the limit), leave each end by a finer grid of its own, and check the result with the game's own
  measure before it is written. **Watch out for:** a tree grown from each end (RRT) never left them in 40,000
  tries: an end sits wedged (the straight finger's tip and middle on two faces at once), so almost every step from it
  goes deeper, and steps down the depth's slope turn back and forth between the points that hold it. With the
  knuckle's roll held at 0 no walk passed under 5.5 mm; with up to 30 degrees one passes clear. **Seen:** gdstudio
  #1283, 2026-11-12.
- **Approach:** Make a solver's distance grid cover everywhere the searched poses reach (the corners of their grid
  and many poses inside it), clipped to the weapon's own bounds. **Watch out for:** a grid round the straight way
  alone read a point beyond it as the edge's distance plus the way there, so a way through the receiver above it
  read 1.6 mm on the grid and 6 mm in the game. **Seen:** gdstudio #1283, 2026-11-12.
