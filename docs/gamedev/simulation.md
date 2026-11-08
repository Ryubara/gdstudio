# Simulation rules: timers, ids, events and space

<!-- new section: crowds.md is the Godot cost of a crowd and nothing held the engine-neutral rules a game's own
simulation keeps (timers on a fixed step, ids two owners share, events, scripted bodies in space) -->

A game's rules and its crowd are often its own code, stepped at a fixed rate, with no physics engine to lean on. These
rules hold in any engine. What a crowd off physics costs, and how Godot's navigation answers it, is in
[Zombie crowds](../engines/godot/crowds.md); bots that play inside the simulation are on [Bots](bots.md).

## Timers on a fixed step {#timers}

- **Approach:** Carry a fixed-step timer's remainder (`t -= interval`, a wait never shorter than one tick, nothing
  banked while idle), and test shots, spawns or pulses over a long run against the nominal rate of every definition.
  **Watch out for:** a cooldown clamped at zero threw away the rest of the tick, so every interval rounded up to whole
  ticks (an SMG fired 360 shots in 30 s, not 400) and a x1.33 fire-rate perk gave x1.2; the test's range had been
  widened, with a comment explaining the loss. **Seen:** Deadnight #708, 2026-11-03 (fix: the leftover is carried;
  `test_weapon_fire_rate.gd`).
- **Approach:** Give every loop in which one actor undoes another's work (mend and tear, heal and hurt, lock and pick)
  a time limit and a test that runs past it, and a rescue for the last unit nothing else moves. **Watch out for:** a
  dead tore a board every 1.2 s from beside a jamb while a person, who mended when nothing was in sight, put one back
  every 1.0 s, and the round waited 190 s. **Seen:** Deadnight #950, 2026-11-03 (fix: a dead that pulls at one window
  for 30 s bursts it; the last dead rise nearer the people).

## Ids and events {#ids-and-events}

- **Approach:** When two owners hold different views of one id (the rules know every unit asked for, the simulation
  only those admitted), have the seam that joins them check both before it acts. **Watch out for:** a hit on a zombie
  still queued under the crowd cap killed it and paid the shooter for a body that was not in the world. **Seen:**
  Deadnight, 2026-11-01 (fix: the hit seam asks the simulation for the id).
- **Approach:** Never give an event's fields a name its envelope uses (`type`, `id`), and test that every event still
  carries its own type. **Watch out for:** events built as `{"type": name}` and then merged with their fields lost
  their name to a zombie's `type` field without an error, and a reader matched the wrong arm. **Seen:** Deadnight,
  2026-11-01 (fix: the field is `zombie_type`; a test checks each event's type).

## Scripted bodies in space {#space}

- **Approach:** Push coincident bodies apart along a direction made from their ids, at the normal speed, cap the sum of
  pushes on one body, and test the degenerate input (distance zero) with a per-tick bound on movement. **Watch out
  for:** the exact-overlap branch divided by 0.001 and threw two zombies spawned on one point 66 m, forty up to 2.6 km;
  the test spread its bodies 0.01 m apart and never reached the branch. **Seen:** Deadnight, 2026-11-01 (fix: the
  id-made direction and a capped push).
- **Approach:** Give a scripted bouncing body a rolling state: a floor bounce slower than a threshold rolls (gravity
  along the slope, friction, a floor probe each step, a stop speed), and test rest, a ledge fall, repeatability and no
  tunnelling at full speed. **Watch out for:** restitution alone scales a speed gravity refills, so on a fixed step a
  grenade made a tiny bounce every step, never rested and drifted in the last digits. **Seen:** Deadnight, 2026-11-01
  (fix: the rolling state; Deadnight's `docs/research/grenades.md`).
- **Approach:** Give a rule that reads a line, a zone or a range in the world its extent from the thing it stands for
  (a gate as wide as its gap), and test it with two of the thing side by side and a path that does not lead straight
  at it. **Watch out for:** a barricade's gate was a line with no width, so on a wall of windows it was the whole wall:
  a dead tore one window's boards from beside the next and walked through that one's standing boards. **Seen:**
  Deadnight #810, 2026-11-03 (fix: gates as wide as their gap; a two-window test fails on `main`).
- **Approach:** Hold a mover's route against a new one that sends it back the way it came unless the new one is clearly
  shorter, print its first leg at every repath when it moves and goes nowhere (a flipping sign is a chatter, not a
  trap), and ship the hold with a measure of the case it can hurt and a control that reads nonzero. **Watch out for:**
  two near-equal ways round a booth were named from strips beside its face, so a slow dead walked between them for six
  minutes, never stuck; the first check covered only the case it fixed. **Seen:** Deadnight #1347, 2026-11-06 (fix: a
  4 m gain to turn back; a grid test round the face, and a dodge-past test with the hold on and off).
