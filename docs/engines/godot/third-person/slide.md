# Sliding

<!-- new section: moved out of the character page (#1041), which was over the 50 KB limit -->

The 3D Third Person character's slide: crouch pressed at a sprint, `CharacterSlide` and its `SlideTuning`. Part of
[the 3D Third Person template](../third-person-template.md); the body's other modules are on
[the character page](character.md#controller).

## Sliding {#slide}

<!-- new section: the controller section covers walking, crouch and steps; nothing said how the slide (#1011) is
     built, why its numbers are what they are, or how a second move fits into the command-driven step -->

Crouch pressed at a run of at least `min_speed` (a sprint) starts a slide. It is a module beside prone, in the same
shape ([Prone and the crawl](character.md#prone)): `CharacterSlide` (`gameplay/character/character_slide.gd`), a
`RefCounted` the `Character` holds as `_slide` and calls from `step()` at three points (`begin_tick` before the crouch,
`steer` in place of the walk, `after_move`), plus one line each in the jump and the air steering; `SlideTuning`
(`slide_tuning.gd`, the player's `slide_tuning.tres`, the `Character`'s `slide_tuning` in its Slide group) holds every
number. It reads only the command (the held `crouch` bit against the last tick's, the push, sprint, jump), the body and
its tunings, so a bot or a server slides a body by sending `crouch` at speed. No command bit was added (none is free
since prone took bit 15) and nothing new crosses the wire: `State.SLIDE` comes after `PRONE`, so the state byte keeps
its old numbers. Its step state is its own `FIELDS`, saved in `CharacterState.slide`; the read-only `sliding` says
whether it slides. Prone ends a slide, and a lying (crouched underneath) body does not start one.

What shipped games do, and the template's default for each:

| Setting | Shipped games | Default |
| --- | --- | --- |
| Entry | Titanfall 2: `slideRequiredStartSpeed` 200 u/s (5.1 m/s) against a 260 u/s (6.6 m/s) sprint, 77 percent [1][2]; Halo 5 and Infinite: from a sprint [6]; Fortnite: crouch held while running or sprinting [4] | `min_speed` 5.0 m/s (77 percent of the 6.5 m/s sprint, above the 4.0 m/s run); sprint not required (`needs_sprint` off), so a bot that sends no sprint slides at speed |
| Boost | Titanfall 2: `slideSpeedBoost` 150 u/s (3.8 m/s) capped at `slideSpeedBoostCap` 400 u/s (10.2 m/s), `boost_cooldown` 2 s [2]; its designer calls it a little boost at the start [3]; Off the Grid brought its boost back with a cooldown [7]; Deadlock has a `SprintBoostSpeed` [5] | `boost` 1.5 m/s (23 percent of the sprint, smaller than Titanfall's: a third-person camera reads a big jump in speed as a pop), `boost_cap` 8.5 m/s, `boost_cooldown` 2 s |
| Friction and length | Titanfall 2: `slidedecel` 50 u/s² (1.3 m/s²) and `slidevelocitydecay` 0.7 [1]; Off the Grid caps a slide at 1 s [7]; Fortnite: several seconds, at run speed on the flat [4] | `friction` 3.5 m/s² and `drag` 0.3 a second (Titanfall's two parts, scaled to a slide of about 1 s and 5 m on the flat from 8 m/s), `max_time` 1.5 s |
| End | Titanfall 2: `slideStopSpeed` 125 u/s (3.2 m/s), and above `slideMaxStopSpeed` 350 u/s a released crouch is ignored [2]; Deadlock: `MinSustainSpeed` [5] | `exit_speed` 3.0 m/s (between the crouch walk and the run); letting go of crouch ends it (`hold_to_continue`) |
| Slopes | Apex: a slope changes a slide's speed and length, and a steep one turns it into acceleration [8]; Fortnite: faster the steeper [4]; Deadlock: its own friction and acceleration on slopes and uphill [5]; Halo Infinite retuned the gain of landing into a ramp slide [6] | gravity along the floor (`gravity` 9.8 m/s² times the sine of the slope), a fifth of the friction downhill (`downhill_friction` 0.2: about 10 degrees and steeper speeds up), no time limit downhill, `max_speed` 11 m/s; uphill the full friction plus the pull |
| Slide jump | Titanfall 2: `slideJumpHeight` 50 against a jump of 60 (0.83), speed held to `slideMaxJumpSpeed` 350 u/s (8.9 m/s) [2]; Apex: a jump out of a slide keeps momentum longer than one out of a sprint [8]; Deadlock: air drag after a slide jump [5] | `jump_height_scale` 0.85, `jump_max_speed` 9.0 m/s, the carried speed fading by `jump_air_drag` 1 m/s² |
| Steering | Titanfall: harder to stop or turn than a walk [3]; Deadlock: a turn speed [5] | `turn_rate` 1.2 rad/s (about 70 degrees a second) |
| Capsule and camera | Titanfall 2: crouch hull 47 of 72 u (65 percent), eye 38 of 60; a crouch that starts a slide takes 0.2 s, not 0.4; `slideFOVScale` 1.1 over 0.25 s in and out [1][2] | `height` 0.9 m (half the 1.8 m capsule, under the 1.1 m crouch), `drop_time` 0.12 s, `camera_height` 0.75 m; `PlayerCamera.slide_fov_change` 5 degrees at `slide_zoom_speed` 4 a second, on top of the sprint view |
| Shooting | Deadlock reduces recoil while sliding (`SlidingRecoilReduction`) [5]; Apex, Call of Duty and Titanfall fire while sliding | `can_shoot` on: aim and fire work, and the body turns to the view |
| Spam | Titanfall's boost cooldown [2]; Call of Duty MW III cut the sprint delay after a slide by 53 percent [9] | `cooldown` 0.3 s between slides, and the boost's own 2 s |

Sources: [1] Titanfall 2's `pilot_mp.set` and `pilot_base.set` (data files, mirrored at
<https://github.com/Syampuuh/Titanfall2/tree/master/scripts/players/mp>); [2] the engine's player-settings defaults
read from a decompile, a community write-up:
<https://github.com/Kurisu003/titanium-dioxide/blob/main/docs/engine-values.md>; [3] Titanfall's designer on the
slide: <https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right>; [4]
Epic's Fortnite Creative movement page:
<https://dev.epicgames.com/documentation/fortnite/player-movements-in-fortnite-creative>; [5] the field list of
Deadlock's slide ability (names, no values): <https://s2v.app/SchemaExplorer/deadlock/server/CAbilitySlideVData>; [6]
<https://www.halopedia.org/Spartan_abilities> and Halo Infinite's Season 2 notes as reported at
<https://comicbook.com/gaming/news/halo-infinite-season-2-update-patch-notes-xbox-pc/>; [7] Off the Grid (a
third-person shooter), the patch notes of 17 and 20 December:
<https://support.gameoffthegrid.com/hc/en-us/articles/24128319096221-December-20-Patch-Notes-UPDATE-CL378092>; [8]
<https://apexlegends.wiki.gg/wiki/Movement> (sprint 7.59 m/s); [9]
<https://www.gamespot.com/articles/cod-modern-warfare-3-patch-notes-include-movement-changes-and-fix-for-a-major-zombies-issue/1100-6519282/>.
A Source unit is an inch (0.0254 m). No shipped game publishes a slide's friction in m/s²: the Titanfall numbers are
its data files, and its cooldown and stop speeds come from a decompile, not from Respawn.

[1]: https://github.com/Syampuuh/Titanfall2/tree/master/scripts/players/mp
[2]: https://github.com/Kurisu003/titanium-dioxide/blob/main/docs/engine-values.md
[3]: https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right
[4]: https://dev.epicgames.com/documentation/fortnite/player-movements-in-fortnite-creative
[5]: https://s2v.app/SchemaExplorer/deadlock/server/CAbilitySlideVData
[6]: https://www.halopedia.org/Spartan_abilities
[7]: https://support.gameoffthegrid.com/hc/en-us/articles/24128319096221-December-20-Patch-Notes-UPDATE-CL378092
[8]: https://apexlegends.wiki.gg/wiki/Movement
[9]: https://www.gamespot.com/articles/cod-modern-warfare-3-patch-notes-include-movement-changes-and-fix-for-a-major-zombies-issue/1100-6519282/

The tests are `tests/gameplay/test_slide.gd` (keys, commands, snapshots, a ramp, a low gap; 17 cases) and
`test_slide_live.gd` (the pad, the touch layer, the clips and the camera in the game scene). The capture is
`tools/capture/slide_tour.tscn` (`SLIDE_OFF=1` shows crouch at a sprint without the slide).

What it costs (`tools/bench/player_step_bench.tscn`, which presses crouch at a sprint for 40 of every 240 ticks, so its
bodies slide): 40 bodies stepped by commands took 30.2 and 32.3 µs a body a tick with the slide on and 32.7 and 30.1
with it off, within the spread between runs on a shared machine. A slide adds no node and no draw call, and makes a
shape query only on the tick it would end (or while it is slow under a low ceiling). The web export was not measured:
the bench's browser rows follow the desktop ones (24 to 28 µs in Chrome against 21 to 24 at 40 bodies), and nothing
here differs between the two.

- **Approach:** Make another move of the character its own `RefCounted` with its own step state (`FIELDS`,
  `save_step_state`, `load_step_state`) and its own tuning resource, called from `step()` by a few lines, and read a
  press from the command's held bit against the last tick's (`_wants_crouch`). **Watch out for:** `Character` sits at
  gdlint's 20 public methods, so pass state in as arguments and use a read-only property (`sliding`, as prone's
  `prone`); the slide began as a `CharacterTuning` group and moved to `SlideTuning` when prone (#1012) landed that
  way; a new `Character` export is pinned in `test_ragdoll.gd`, which only the full suite caught. **Seen:** gdstudio
  #1011, 2026-11-10.
- **Approach:** Give friction a smaller share downhill (`downhill_friction`) instead of relying on gravity along
  the floor alone. **Watch out for:** with the flat friction of a one-second slide (3.5 m/s² and 0.3 a second), the
  pull of gravity along a slope, at most half of `g` in the flat plane, never beats it: the first draft would have
  slowed on any ramp (caught by working the sum before the ramp test ran). **Seen:** gdstudio #1011, 2026-11-10
  (`test_downhill_speeds_the_slide_up_and_uphill_ends_it_sooner`).
- **Approach:** Run a slide test on a floor of its own (the arena, or a slab built high above the map), and hold crouch
  in the default hold mode for as long as the slide must last. **Watch out for:** on the map the spawn stands on a 1 m
  platform, so a slide north flew off its edge in half a second and ended; a test that tapped crouch ended its slide on
  the next tick. **Seen:** gdstudio #1011, 2026-11-10 (`test_slide_live.gd`).
