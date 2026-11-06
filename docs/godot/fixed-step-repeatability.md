# Fixed-step repeatability: why two runs of one night differ

A game that steps at a fixed rate with a seed should play the same night twice. Deadnight's did not (round 17 and round
11 from one commit, seed and command, issue #1350), and the cause was neither the clock nor the audio. This page is how
to find where two runs part, and what was found.

## Find the first difference before choosing a theory

1. Make the run write one line a tick of **hashes by part** of the night: the simulated dead, the bodies, the dice's
   states, the paths, the points, the count standing. Hash values (`hash(PackedFloat64Array)`), not text; add the raw
   numbers of the bodies in the same line for the tick you end up reading.
2. Run the same command three times at once (a night that is identical alone and differs at three at once is a timing
   difference) and compare line by line. The **first tick and column** that differ name the part; the columns that
   differ later are the chain after it. Deadnight's order was: a body's `y` (millimetres), the dead's places 350 ticks
   later, the paths, the points, the dice.
3. Put the load-time numbers aside. Resource, node and audio counts differ run to run and say nothing about the
   night: three nights with those counts different were identical for 36 000 ticks.
4. Record the physics frame the first tick runs on (`Engine.get_physics_frames()`) and the frames each wait takes.

## What was found (Godot 4.7.2, Deadnight)

- **The age of the physics space at the first tick can change a body's contacts.** A static ground made of tiles that
  meet (CSG boxes with collision) played a standing or walking body's contacts differently until the lot was about 17
  physics frames old: the body stood 0.9 mm up or on the floor, and the collider reported for the same place was one
  tile in one run and its neighbour in another. A night begun 0 to 2 frames after the build and one begun 3 or more
  frames after gave two hashes, each identical in its group.
- **A wait for the navigation server is not a fixed number of frames.** `NavigationServer3D.map_get_path` answered
  3 to 9 physics frames after the regions were set (`map_force_update` after the regions made it 2 to 9, not
  0), a frame early or late from run to run,
  even with `map_set_use_async_iterations(map, false)`. Any "wait until it answers" loop ends at a different
  frame in two runs, so whatever else depends on the frame count differs.
- **So wait for age, not for an answer.** Build the world, then wait until it has stood a fixed number of physics frames
  (Deadnight: 24, `NightWorld.LOT_MIN_FRAMES`) before the first tick. Past that age the outcome did not depend on the
  frames: delays of 0, 1, 2, 3, 5 and 9 frames gave one hash.
- **The engine's call is a function of its state.** The same `body_test_motion` asked 20 times from one state gave one
  answer 1 440 times of 1 440; the differences between runs came from the state, not a race inside the call.
- Not isolated: why the young lot plays differently (the ground tiles' shapes are made over the first frames).
  Not tried: a map with one big floor, or Jolt (the project leaves the physics engine at the default).

## The test

Two things to keep: the build is old enough whatever the navigation does (`tests/night/test_night_repeats.gd`), and
nights of one seed started 0 and 3 frames apart keep every place to the last bit. A hash of positions in quarter metres
hides this; compare the raw floats. See also [navigation in tests](navigation-in-tests.md) and the
[lesson](../lessons/2026-11-06-two-nights-of-one-seed-differed-by-the-age-of-the-lot.md).
