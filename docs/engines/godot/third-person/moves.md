# Prone and sliding

<!-- new section: split out of the character page when it reached the size limit (gdstudio #1029) -->

The 3D Third Person character's stances beside [the controller](character.md#controller): lying down and crawling, and
the slide from a sprint. Part of [the 3D Third Person template](../third-person-template.md).

## Prone and the crawl {#prone}

<!-- new section: the controller section covers standing and crouched moves; nothing said how the template lies a
     body down, crawls, fits under a gap and gets up, or where its defaults come from (gdstudio #1012) -->

The character lies down and crawls below crouch. It is its own module beside the body's other moves:
`CharacterProne` (`gameplay/character/character_prone.gd`) holds the stance (down or not, how far down, the time off
the ground) and what lying changes; `ProneTuning` (`prone_tuning.gd`, the player's `prone_tuning.tres`, the
`Character`'s `prone_tuning` in its Prone group) holds every number. The body asks the module once a step from the
command's held `prone` bit, so a server, a bot or a test lies a body down by sending that bit
(`CommandCodec.F_PRONE`, bit 15; `NetWire.VERSION` 3), and the stance is saved and put back with the rest of the step
state (`CharacterState.prone`). The human's `PlayerInput` turns the `prone` action (Z, the pad's d-pad down, the
Prone touch button) into that bit by the tuning's `input_mode`: a toggle (the default), a hold, or a long hold of
crouch (`crouch_hold_time`) with a press of crouch to get up; a jump or a sprint press gets up (`jump_gets_up`,
`sprint_gets_up`).

- **Down and up.** Going down takes `enter_time` and getting up `exit_time`; the capsule shrinks from the top to
  `height` and `radius` and the camera's target to `camera_height`, eased by the module's `share()`. A lying body is
  crouched underneath, so getting up ends at the crouch height and stands over the crouch time when crouch is let go
  and there is room (or stays crouched under a low ceiling). Getting up needs a crouched capsule's room above
  (`CharacterProne.has_room`, the stand probe's shape at the crouch height): under a gap only a lying body fits, it
  stays down. Off a ledge it stays down `air_time`, then gets up; it lies down again on landing while the bit is held.
- **The crawl.** `crawl_speed` ahead, `sideways_share` and `backward_share` of it to the side and behind (by the angle
  between the push and the facing), `aim_move_share` of it while aiming, its own `acceleration`, `deceleration` and
  `turn_speed` (a body on the ground turns slowly), and no crawl while going down or up unless
  `move_while_changing`.
- **Aim.** `aim_allowed` and `fire_allowed`; the weapon's spread times `spread_share` (`Weapon.spread_share`, set by
  the body each step); the look held to `look_up_limit` and `look_down_limit` (the view, the aim pose and the aim ray,
  so an AI is held too), and `PlayerCamera.pitch_limits()` draws the orbit in to the same limits as the body lies down.
- **The picture.** `Character.State.PRONE` (after `DEAD`, so the snapshot's state byte keeps its old numbers),
  `prone_changed(down)`, the read-only `prone` and `prone_amount`. `CharacterAnimation` has a `prone` state that
  plays the template's own clips (gdstudio #1009, the library `prone` from `assets/animation/prone/`, one file a
  body with the same clip names, lengths and crawl speed, kit #1090 and #1293;
  [how they are solved](../../../tools/blender/animation.md#solved-clips)): `prone/Prone_Idle` at `prone_idle_pace`,
  and `prone/Crawl_Fwd`, which replaces the idle over `blend_time` as soon as the body moves and plays at
  `ground speed / crawl_clip_speed` (0.618 m/s, the clip's stride), backwards when the body moves away from the way it
  faces (aiming and pulling back; without aim the body turns toward the push at `turn_speed` while the crawl plays).
  `prone/Crouch_To_Prone` and `prone/Prone_To_Crouch` play over the body for `enter_time` and `exit_time` (0.9 s and
  1.0 s clips played in 0.5 and 0.7 s), from and to the crouch idle's first pose. The clips rest the body on the
  forearms and fists, so lying puts the weapon away (`ProneAnimation.stow_share`: its model hidden and the grip off)
  until the body aims. A model whose body needs clips of its own gets them from `prone_libraries` (its scene file to a
  library with the same clip names), swapped in when the model is set or replaced, in the game only. The share, the
  pace, the weapon and the library swap are `ProneAnimation` (`gameplay/character/prone_animation.gd`), cosmetic and
  never sent.
- **One clip file a body.** A clip that rests limbs on the floor fits one body's bone lengths and skin, so each of
  the template's bodies has the four clips solved on itself (kit #1293), and so has each Quaternius mannequin (kit
  #1090): `character_dressed.tscn` holds `prone_form_female.glb` as the library `prone` (the player, the friendlies
  and the online puppets wear `form_female.glb`) and its `prone_libraries` names `prone_form_male.glb` for
  `form_male.glb` (the enemies), `prone.glb` for `mannequin_female.glb` and `prone_male.glb` for
  `mannequin_male.glb`. In the Quaternius female's file the `form` bodies lay 33 to 55 mm in the floor at the
  forearms with their planted elbows rolling 19 and 32 mm a stride (kit #1286); in their own files no forearm, hand,
  thigh, shin or foot is more than 5 mm under it, the planted elbows stay within a millimetre and no limb crosses
  another (`tests/gameplay/test_prone_clips.gd`, each body in its own file; `tools/capture/prone_clips_tour.tscn`
  films any of the four, `MODEL`, read by `tools/capture/study_body.gd`).

The defaults, from shipped third-person and squad games (the numbers are measured or published by players, not the
studios; the template's run is 4.0 m/s and its walk 1.7):

| Setting | Default | Why |
| --- | --- | --- |
| `crawl_speed` | 1.0 m/s | PUBG crawls at 1.2 m/s against a 1.7 m/s walk ([PUBG wiki](https://pubg.wiki.gg/wiki/Movement_Speed)); Battlefield V at 0.85 m/s against 3.4 ([Symthic](https://sym.gg/legacy/pages/bfv/bfv_generalinfo.html)); between the two, under the template's 1.5 m/s crouch walk. |
| `backward_share`, `sideways_share` | 0.7, 0.8 | Arma 3: sideways about 80 % and backwards about 70 % of forward in every stance, from a 2013 post in [Bohemia's movement thread](https://forums.bohemia.net/topic/144224-movement-speed-tweaking/). |
| `aim_move_share` | 0.5 | Battlefield V halves the prone speed while aiming (0.425 of 0.85 m/s). |
| `enter_time`, `exit_time` | 0.5 s, 0.7 s | Battlefield V: 500 ms to go prone, 700 ms from prone to a sprint. The #1009 clips are 0.9 s and 1.0 s at their own pace and are played to these times. |
| `turn_speed`, `aim_turn_speed` | 3, 6 rad/s | A quarter of the standing turn (12) and a third of the standing aim turn (18): Arma's players ask for a slow, single-speed turn on the ground, not a snap. |
| `acceleration`, `deceleration` | 10, 12 m/s² | Up to the crawl in 0.1 s: a lying body has no burst. |
| `height`, `radius` | 0.6 m, 0.28 m | A soldier on elbows is about 0.4 to 0.5 m high; the capsule stands upright, so it is a little taller and covers the raised head. A 0.8 m gap fits it and not the 1.1 m crouch. |
| `camera_height`, `look_up_limit`, `look_down_limit` | 0.55 m, 12, 40 degrees | Arma's players note the short look up lying down. With the 1.7 m camera, 12 degrees up keeps the lens about 0.3 m over the floor; 20 put it 7 cm over (below). |
| `spread_share` | 0.5 | Lying is the steadiest stance in PUBG and Battlefield. |
| `input_mode`, `crouch_hold_time` | toggle, 0.5 s | PUBG (Z) and Ghost Recon Breakpoint (its own prone button) toggle; Metal Gear Solid V and the pads hold the stance button ([Konami](https://eu-support.konami.com/hc/en-gb/articles/9667348797975-Metal-Gear-Solid-V-Sneaking)). |
| `jump_gets_up`, `sprint_gets_up` | on, on | A jump press in PUBG and a sprint in Battlefield get up instead. |

What it costs (`tools/bench/player_step_bench.tscn`, `prone` mode: lying and crawling 80 % of the time, getting up
every 5 s; microseconds a body a physics tick, 40 bodies, two headless desktop runs on a shared machine): main's
`commands` 32.7 and 28.0, this branch's `commands` 31.4 and 32.5, `prone` 32.4 and 31.2. Lying costs what standing
does; the only new query is the room check, made only while a body that was let go of is still down. On the web the
same ratio is expected (the bench's browser rows track the desktop's within a few microseconds at 40 bodies); nothing
of the stance is sent but the command's bit; the clips are cosmetic and played in `_process`.

- **Approach:** Derive a prone camera's look-up limit from the follow distance and the target height (`target +
  offset - distance * sin(limit)` stays over the floor by more than the spring arm's margin) and test the lens height
  in the real map with the stick held up. **Watch out for:** a limit taken from aim comfort alone (20 degrees) put the
  lens 7 cm over the floor, 2 cm from the near plane; the spring arm meets the floor at a grazing angle, so its margin
  is along the arm, not up. **Seen:** gdstudio #1012, 2026-11-10 (`test_prone_camera.gd`; 12 degrees keeps 0.3 m).
- **Approach:** Lay a placeholder on the ground with a pose offset on the model inside its slot, applied by how far
  down the body is and nothing at all while it is zero, and look at the capture before picking the clip. **Watch out
  for:** the crouch clips tipped forward still knelt, and the library's swim stroke is horizontal but floats under a
  water line (0.42 m low) with a treading idle; the stroke held on its first pose (`prone_idle_pace` 0) is the idle.
  **Seen:** gdstudio #1012, 2026-11-10 (captures of three tries); the offset and the swim stroke were removed when
  the real clips landed (gdstudio #1026).
- **Approach:** Blend a crawl in over a time as soon as the body moves and let its pace (ground speed over the clip's
  stride) follow the speed, and measure a planted joint in the game: throttle the tree (`set_throttled(true)`) and
  `advance()` it by the tick after each physics frame, read the bone in world space and take the least drift over
  most of its planted share of the cycle, at the slowest, the default and the fastest crawl. **Watch out for:** the
  crawl first blended with the idle by ground speed up to 0.2 m/s, so at the slowest crawl the tuning allows
  (0.1 m/s) half the idle stayed in and a planted elbow slid 12 cm a stride (the swim stand-in: 8.5 cm); eased in
  time it is 0.1 to 2.4 mm from 0.1 to 3 m/s. **Seen:** gdstudio #1026, 2026-11-11 (`test_prone_animation.gd`).
- **Approach:** Keep a body's stance changes out of its state names when the capsule is what matters: getting up from
  prone passes the crouch height on the way (test the height the tick the stance reaches zero), and the state goes
  from `PRONE` to `IDLE` as a released crouch does. **Watch out for:** a test that expected a `CROUCH` state between
  them failed, though the capsule went through crouch. **Seen:** gdstudio #1012, 2026-11-10.
- **Approach:** When a body gains a stance, expose its reads as read-only properties (`var prone: bool: get:`) rather
  than methods, and split a suite at 18 tests. **Watch out for:** gdlint's twenty public methods counts every
  `func`, so three small getters took `Character` from 18 to 21 and failed the hook. **Seen:** gdstudio #1012,
  2026-11-10.

## Sliding {#slide}

<!-- new section: the controller section covers walking, crouch and steps; nothing said how the slide (#1011) is
     built, why its numbers are what they are, or how a second move fits into the command-driven step -->

Crouch pressed at a run of at least `min_speed` (a sprint) starts a slide. It is a module beside prone, in the same
shape ([Prone and the crawl](#prone)): `CharacterSlide` (`gameplay/character/character_slide.gd`), a `RefCounted` the
`Character` holds as `_slide` and calls from `step()` at three points (`begin_tick` before the crouch, `steer` in place
of the walk, `after_move`), plus one line each in the jump and the air steering; `SlideTuning` (`slide_tuning.gd`, the
player's `slide_tuning.tres`, the `Character`'s `slide_tuning` in its Slide group) holds every number. It reads only
the command (the held `crouch` bit against the last tick's, the push, sprint, jump), the body and its tunings, so a bot
or a server slides a body by sending `crouch` at speed. No command bit was added (none is free since prone took bit
15) and nothing new crosses the wire: `State.SLIDE` comes after `PRONE`, so the state byte keeps its old numbers. Its
step state is its own `FIELDS`, saved in `CharacterState.slide`; the read-only `sliding` says whether it slides. Prone
ends a slide, and a lying (crouched underneath) body does not start one.

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
| Shooting | Deadlock reduces recoil while sliding (`SlidingRecoilReduction`) [5]; Apex, Call of Duty and Titanfall fire while sliding | `can_shoot` on: aim and fire work; the body keeps along the slide and the [aim layer](shooting.md#aim-layer) turns the upper body to the aim within `aim_limits` (75 degrees each side), and past them the body turns (or the weapon refuses the shot) |
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
