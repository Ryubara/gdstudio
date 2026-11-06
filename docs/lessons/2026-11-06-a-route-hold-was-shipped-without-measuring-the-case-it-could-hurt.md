---
areas: [gameplay, tests]
---
# A rule that holds a dead's route was shipped before its cost to a dodging player was measured

2026-11-06

- **Saw:** the fix for a crawler chattering between two ways round a booth (Deadnight #1347) holds a dead's route against
  a new one that turns it back. The review asked what that does to a dead chasing a person who runs past it, and neither
  the booth test nor the soak could say: nothing in them dodged past a dead.
- **Cause:** the rule was checked against the case it was written for (a grid of starts at the booth, 45 soak nights) and
  not against the opposite case a hold can hurt, the player kiting. The reading of the code ("the gain test is always
  true when little route is left") was right and the conclusion was not: the hold needs the person to get from in front
  of the dead to behind it inside one repath (0.25 s), a pass within about a metre, inside the dead's reach, where the
  dead swings and lets the stale route go.
- **Fix:** `test_zombie_dodge_past.gd` runs a crawler and a walker on open ground against a person who sidesteps and
  runs past (run and sprint speed, three repath phases) or circles it, hold on and off, and counts the metres the dead
  walks away from the person: 0.00 in 36 rows both ways, 1.4 to 2.7 m for a dead that never repaths (the control). A
  zero with no control can be a count that cannot see; the control is the line that makes it a result.
- **Check next time:** a rule that makes a unit hold a decision ships with a measure of the case where the held decision
  is wrong, not only the case it fixes, and with a control that makes the measure read nonzero; the switch to turn the
  rule off for that measure is a field of the sim, not an edit of its source.
- **Docs:** Deadnight `docs/research/bots.md`, "A crawler that parks at the drive-in's west ticket booth (#1347)".
