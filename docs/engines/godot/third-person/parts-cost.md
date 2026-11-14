# What the parts cost

<!-- new section: the character page reached the 50 KB limit, and what its parts cost is its largest subject and
     keeps growing with every part (gdstudio #1471) -->

## What the parts cost {#parts-cost}

<!-- new section: the step bench timed the body alone; nothing said what a dressed character's other parts or the world
     parts cost a frame, which an AI crowd and the web build multiply -->

`tools/bench/parts_cost_bench.tscn` (gdstudio #926) prints what the parts cost a frame: a crowd of
`character_dressed.tscn` with a walking stand-in controller (an AI's body), each character part timed apart with its own
processing off and called by hand, a first death, and 100 of each world part against an empty arena. The web numbers
come from its export in headless Chrome (`tools/bench/parts_cost_bench.py`, under `gds quiet`). A frame's "work" is from
its first physics tick to its last node processed (the scripts, the animation and the physics step, not the drawing).
`tests/gameplay/test_parts_budget.gd` holds the counts tight in CI and ten walking characters' frame loosely, as a
multiple of a calibration loop.

| Median frame work, ms | 1 | 10 | 25 | 50 walking |
| --- | ---: | ---: | ---: | ---: |
| Desktop, before #926 | 0.22 | 0.99 to 1.01 | 2.24 to 2.39 | 5.16 to 5.59 |
| Desktop, after | 0.21 | 0.74 to 0.84 | 1.47 to 1.54 | 3.23 to 3.28 |
| Chrome, before | 0.3 | 1.1 to 1.2 | 2.6 to 3.2 | 6.5 to 9.4 |
| Chrome, after | 0.3 | 0.8 to 1.0 | 1.9 | 3.8 to 4.1 |

| µs a character a frame (25 walking) | Step | Animation script | Tree | Footsteps | Ragdoll |
| --- | ---: | ---: | ---: | ---: | ---: |
| Desktop, before | 29 to 30 | 5.7 | 22.6 to 23.0 | 14 to 16 | 14.5 |
| Desktop, after | 23 to 26 | 2.6 to 3.1 | 21.4 to 23.2 | 14 to 15 | 3.4 to 3.9 |
| Chrome, before | 35 | 6.7 to 7.0 | 20 to 22 | 22 | 18 to 19 |
| Chrome, after | 30 | 4.5 to 4.8 | 21 | 23 | 4.6 to 5.2 |

What changed: the ragdoll's bones are made on the first death ([Ragdoll: cost](../ragdoll.md#cost)), so a living
character is 29 nodes and one physics body instead of 62 and 17 (53 and 2 with the hit zones of #876, the weapons
of #887, the pistol hold of #1001 and the `Health` of #925; the body's own step is cheaper with 16 fewer bodies in the
space); the pose the death needs is sampled into arrays made once; the animation tree's parameter paths are constants
and the blend spaces follow the tuning's `changed` (the four speeds say it) instead of comparing an array every frame. A
first death costs 0.45 ms on the desktop and 1 ms in Chrome (bones from a pool, #1022). A standing `Target` is no longer
processed (1 µs each before, 0 after); a `Door` keeps the characters in its range from its sensor's signals instead of a
query a tick (1.9 to 2.1 µs each, 1.4 to 1.6 after); a `Pickup` finds its `Visual` once (2.2 to 2.4 µs, 1.8 to 2.0
after); a lone `Weapon` costs 0.2 to 0.3 µs (a character's is ticked by its step). The level holds 11 pickups, 4 targets
and 2 doors, under 40 µs together.

What is left: the step and the tree. The footsteps' 14 µs was almost all starting a sound: a walking character starts
about two steps a second, and `AudioStreamPlayer3D.play()` of an Ogg Vorbis step cost about 250 µs on the desktop (the
decoder is set up for every play; with the step list emptied the part costs 1.6 µs). Since gdstudio #1023 the steps
play decoded to PCM once (`DecodedSounds` of `gds_game`, [Audio: starting sounds](../audio.md#starting-sounds)), and a
WAV starts in about 1 µs:

| Footsteps, µs a character a frame (25 walking) | Before #1023 | After |
| --- | ---: | ---: |
| Desktop | 12.9 to 13.7 | 2.25 to 2.30 |
| Chrome | 22.1 to 22.3 | 7.0 to 7.9 |

The four steps decode once for every character (shared), when the first `Footsteps` is ready: about 2 ms on the
desktop and 7 to 16 ms in Chrome, inside the first character's spawn (65 to 68 ms before, 72 to 84 after, in Chrome).
The samples are the decoder's own (16-bit), so the steps sound as before: Movie Maker mixes before and after differ by
-65 dB (25 walkers) and -70 to -83 dB (the action tour's walking), 16-bit rounding; only the tour's shooting stretch
differs, from run to run. What Chrome still pays is the WAV's own start.

The desktop rows are three interleaved runs of each build (before, after, before, ...), the browser rows two, headless,
on a machine other agents were using; a range is the lowest and the highest run.

**What the gaits of 2026-11-11 to 13 added** (gdstudio #1360). The budget case's ten walkers went from 0.92 to 1.07
times the calibration (db19fdc0) to 1.50 to 1.80 (main at dc9dc2fb, 1.79 to 2.99 ms median), eight interleaved runs
each on a desktop at 97 to 100 % load. Read by the bench's parts, as a share of the body's step (which no change
touched, so it cancels the load), the animation script and the tree rose at three commits, a game made at each:

| Animation script and tree, share of the step (25 walking) | Script | Tree |
| --- | ---: | ---: |
| Before (db19fdc0) | 0.31 | 0.66 |
| Our walk, jog and sprint (#1275) | 0.40 | 0.70 |
| Gait speed matching, momentum and lean (#1368) | 0.90 | 0.87 |
| The starts and stops exist (#1375), and main | 1.18 to 1.37 | 0.85 to 0.91 |
| After #1360 | 0.99 | 0.80 |

At the step's 72 µs that is a script of 22 µs before and 99 on main. Of main's, the gait's blend took 16 to 25 µs (the
speed matching of both spaces), the lean 1, the momentum blend 6.5 in the skeleton's update, and the transitions 19 to
33: once #1375 gave the player its starts and stops, every moving body looked up its main gait, its phase in the tree
and its next foot each frame before asking whether it wanted a stop, a reversal or a pivot, and each look at a clip's
record built its library's name and its contact list again. #1360 asks the controller's numbers first and keeps each
record's lookup and contacts once (`GaitClips`): 7 to 9 µs, the same transitions picked. Our clips key the four `ik_`
targets (8 of 61 tracks), which the tree blends too. What #1360 left is
[gdstudio #1438](https://github.com/Ryubara/gdstudio/issues/1438). The lean's share of the tree went from 1.0 to 0.3
of the step in gdstudio #1403 ([the lean's cost](clips.md#gait-settings)).

**The budget on CI** (gdstudio #1451). The limit of 1.7 was set on the desktop and failed main at 2.40 on code whose
parts held still. `.github/workflows/parts-budget.yml` runs the suite 50 times on the runners (by hand, and on a pull
request that changes it). Over 100 runs that printed four more rulers beside the loop (an `AnimationTree` of its own
blending three clips of a 61-bone skeleton made in code, `PhysicsRuler`, 6,000 small objects visited in a shuffled
order, and a walk through a 16 MB table), the frame spread 1.50 times over the loop, 1.44 to 1.58 over the animation
and physics rulers, 1.46 over the best mix and 2.0 over the memory ones. Within one processor model the runs agree
within a few percent; the models are up to 1.5 times apart for every ruler, so no ruler removes the spread, and the
loop stays. Heavy rulers timed between the measured frames made the frame about a third slower on the runners, so
the suite times only the loop. The case now subtracts the empty arena's frame and takes the lowest of three windows'
ratios (each window's median frame over its median loop). In the red run the AI step was 1.2 to 1.5 times slower
too while the physics ruler held: a runner slows for a while on its own. The limits, by system:

| Ten walkers, frame over loop | Unchanged | Twice as slow | Limit |
| --- | ---: | ---: | ---: |
| Linux, 150 soak runs (AMD EPYC 7763, 9V74, 9V45, Intel Xeon 8573C, 6975P-C) | 1.26 to 1.78 | 2.54 to 4.00 | 2.2 |
| Windows, 10 desktop runs beside 9 to 11 Godot processes | 1.54 to 1.83 | 3.07 to 3.43 | 2.4 |

One window of the 450 read 2.24 (four over 1.9): a single window would still fail now and then; the best of three
did not fail once. The twice-as-slow case (the frame spun on the clock as long again) runs in the suite and failed
the budget in all 150 runs.

**The aim layer and the hold at rest** (gdstudio #1478). A walking character that never aims ran the whole
`AimLayer.refresh()` and `WeaponHold.refresh()` every frame with every modifier of theirs off. Now the layer writes
nothing while the weapon is not aimed, the aim amount is 0 and its three modifiers are off (`is_at_rest()`), and the
hold, once a second frame has no aim, no reload or rack and no hand let go (`HoldRest`), places only the grip and the
slide: its left arm, fingers, stance, floor keeper and rack are off whatever else the frame holds. Nothing is culled:
`test_aim_hold_rest.gd` steps two players through a walk, an aim in and out with a shot, an empty reload and its rack,
a hand let go and the fists aimed crouched, one with both shortcuts off (`AimLayer.full_refresh`, `HoldRest.off`), and
every bone is the same in all 444 drawn frames (0.0005 mm, single precision). 25 walking, µs a character a frame
(three interleaved desktop runs, two in Chrome, games made at 021427f7 and with the change):

| | AimLayer | WeaponHold | AimLayer, share of the step | WeaponHold, share |
| --- | ---: | ---: | ---: | ---: |
| Desktop, before | 11.6 to 13.9 | 13.0 to 15.5 | 0.30 to 0.31 | 0.33 to 0.35 |
| Desktop, after | 4.9 to 6.3 | 7.1 to 9.5 | 0.13 to 0.15 | 0.20 to 0.22 |
| Chrome, before | 12.6 to 14.4 | 15.3 to 18.3 | 0.28 to 0.30 | 0.35 to 0.38 |
| Chrome, after | 6.3 to 6.6 | 11.3 to 11.4 | 0.13 to 0.14 | 0.24 |

What is left at rest: the layer's aim ray each tick (kept, so the first aimed frame is placed from the last two
steps as before) and one look at the aim; the hold's read of the weapon layer, the reload and the rack, the grip's
weights and the slide.

- **Approach:** A part added to a living character (a weapon hold's modifier or marker, an aim or peek layer, an idle
  sound player, a component node) changes the node count `NODES_ALIVE` pins in `tests/gameplay/test_parts_budget.gd`:
  count what the part adds to a dressed character, raise the pin by that many and add a line naming the part and its
  pull request to the comment above it, in the same commit, and run the budget suite beside the part's own suites.
  **Watch out for:** a hold's, a lean's or an aim layer's own suites never run the budget suite, so the pin fails
  only in the full run or on CI; nine pull requests from the pistol hold (#1001) to the fists' upright aim (#1395)
  each moved it by 1 to 6 nodes. **Seen:** gdstudio #1001, #1337, #1351 and #1395; gdstudio #1435, 2026-11-13 (the
  peek lean's left-shoulder hold; agents' reports of the day named the pin late).

- **Approach:** Empty the `RagdollPool` (`clear()`) before counting a living character's nodes, so it makes the pool's
  sets whatever ran first; leave out the controller the test added and hold the count equal. The count includes the
  empty `PhysicalBoneSimulator3D` every `Skeleton3D` adds as an internal child on entering the tree (4.7.2's
  `setup_simulator`): `find_children` lists it. **Watch out for:** handing a set to the pool left its `RagdollDrawing`
  on the skeleton that made it: 57 nodes alone, 56 in the full run, where earlier suites had filled the pool;
  `_release` now drops it. **Seen:** gdstudio #1210, 2026-11-11.
- **Approach:** When a change adds a node or a skeleton modifier to every character (a modifier the `AimLayer` makes,
  however inactive), raise `NODES_ALIVE` in `test_parts_budget.gd` by as many, with a line on what it is, in the same
  commit; grep the suites for `NODES_ALIVE` before the full run. **Watch out for:** the aim suites pass and only the
  full run counts the body, so the extra node shows up as an off-by-one in a suite that looks unrelated. **Seen:**
  gdstudio #1351, 2026-11-12 (`AimUprightModifier`, 65 to 66).
- **Approach:** Save a part's cost by skipping work whose result is not drawn (a modifier that stays off), never by
  distance or visibility, and prove it with a switch that turns the shortcut off: two bodies side by side through the
  same commands, one with it off, every bone read inside `skeleton_updated`, through every state that turns the
  modifiers on and off. Break the shortcut once (let it rest while busy) to see the test fail. **Watch out for:** a
  call skipped at rest may have a side effect another part relies on (`MeleeLayer.aim_of` keeps a flag); ask such a
  call once instead of dropping it, and keep what the first frame out of rest reads (the aim ray of the last two
  ticks). **Seen:** gdstudio #1478, 2026-11-13.
