# Vaulting and mantling

<!-- new section: the 3D Third Person character gained vaulting and mantling (gdstudio #1013) and no page said how
     obstacles are marked, measured and crossed, or where the numbers come from -->

The 3D Third Person character vaults over and mantles onto obstacles that carry a `Vaultable`. The parts that any game
can use are in the synced `addons/gds_game/traversal/` ([gds_game](../../../studio/sync.md#gds-game)); the character's
side is `gameplay/character/character_vault.gd`. Part of [the 3D Third Person template](../third-person-template.md).

## How it works {#how}

<!-- new section: what each part does and in which order, for whoever changes it -->

| Part | Where | What it does |
| --- | --- | --- |
| `Vaultable` | `addons/gds_game/traversal/vaultable.gd` | A node under an obstacle's body (or beside it, under the node that holds the body: a `ProtoBlock`). Without one, nothing is ever crossed. Says which moves (vault, mantle) and faces are allowed, and can override the height, the depth and the clips. A body's script can name its component instead (a `vaultable` property). |
| `VaultSettings` | `addons/gds_game/traversal/vault_settings.gd`, 3D Third Person's `gameplay/character/vault_settings.tres` | Every number, in five inspector groups (Trigger, Detection, Vault, Mantle, Body). |
| `VaultProbe` | `addons/gds_game/traversal/vault_probe.gd` | Five shape casts, never a single ray: a box as wide as the body cast ahead finds the face; a small sphere cast down past it finds the top; a thin box cast back from a vault's depth beyond finds the far face (only the obstacle's own body counts); a sphere cast down past the far face finds the landing floor; the body's capsule cast along the whole path must touch nothing and fit at the end. A vault needs the obstacle low and thin enough and a landing; otherwise a mantle needs room to stand on top. |
| `VaultPlan` | `addons/gds_game/traversal/vault_plan.gd` | The crossing: vault, mantle or none (with the reason), the measurements and a path of key points with the share of the time each is reached at. `position_at(share)` is where the feet are. |
| `CharacterVault` | `gameplay/character/character_vault.gd` | Inside `Character.step`: asks for a plan when the command asks (a buffered jump press, or a sprint with the automatic trigger), then moves the body along the path tick by tick, by numbers alone, and leaves it on the landing with the crossing's speed. Its state (time in, cooldown, the plan's path) is `CharacterState.vault`. |
| `CharacterAnimation` | Traversal group | Plays the vault or mantle clip (low or high by the plan, or the obstacle's own) over the whole body for the crossing's time. |
| `PuppetVault` | `gameplay/character/puppet_vault.gd` | Online, a body drawn from the network (a player's puppet, an AI replica) plans the crossing itself when its drawn state turns to `VAULT` or `MANTLE`, so the clip plays on every screen with nothing sent ([online](#online)). |

One clip serves every height because the body never follows the clip's root: the clips are in place (the library's
`ClimbUp_1m` keeps its pelvis where it starts and ends), the path is made for the obstacle measured, and the clip is
played at the speed that makes it last the crossing. Its contact times line up with the path's key points through
`plant_at` and `clear_at` (the hand plant over the near edge and the feet past the far edge, as shares of the clip):
set them to a new clip's own contact times.

## What shipped games and engines do, and the defaults {#research}

<!-- new section: the defaults needed sources; nothing in the docs held traversal research -->

What the sources show:

- **Detection by shape casts in stages.** The Advanced Locomotion System's mantle (Unreal, community C++ source) casts
  a capsule forward to find a wall that is not walkable, casts a sphere down from the highest ledge just past the
  impact point to find a walkable top, then checks that the standing capsule has room there; the height above the feet
  picks the low or the high mantle (over 125 cm is high), and the montage's play rate is mapped from the height. The
  Kinemation mantle component does the same three stages (a capsule trace, a sphere edge check between a min and a max
  height, a room check) with a "low height" threshold between two clips. Guerrilla's Horizon Zero Dawn talk runs vault
  probes, measures depth and height variation with fixed offsets, then looks for a valid landing position, with a
  1.8 m tall capsule up to 70 cm wide and a 1.5 m jump.
- **Opt-in markup.** Horizon's vaults can be disabled by triggers or game assets and its climbing uses annotations
  tagged climbable; Opsive's vault can identify vaultable objects by an Object Identifier ID instead of a cast; the
  Replicated Vaulting and Mantling plugin has an ignored tag. Our `Vaultable` is that markup, opt-in: the maintainer's
  rule for the template is that the level designer decides.
- **Vault, else mantle.** The Replicated Vaulting and Mantling plugin has min and max vault height and length, mantles
  when an obstacle is longer than a vault (`bMantleIfVaultFails`) and has a switch for vaulting with no landing found.
- **Approach angle.** Opsive's vault recommends an angle threshold under 30 degrees; wider only when the clip and the
  far side allow a diagonal entry.
- **The trigger.** Unreal's Game Animation Sample uses the jump input (Space, the bottom face button) to jump and to
  take ledges and vaults. Fortnite offers both as a player setting: mantle by holding jump, or by sprinting into the
  ledge (hold forward).
- **Warping one clip.** Unreal's Motion Warping puts a warp window on the stretch of the clip where the hand meets the
  obstacle and skews the root motion so the character reaches the warp target at the end of the window. Horizon warps
  only inside set time ranges, best while the feet are off the ground, and changes the playback speed to keep the
  original velocity (twice the distance, half the speed). Opsive starts the vault earlier at a run by an offset that
  grows with the forward speed.
- **Heights.** No source found gives a shipped game's own thresholds; the numbers below are from the ALS split
  (1.25 m), the clip family planned in gdstudio #1010 (a low one-hand vault for about 0.5 to 1.0 m and a two-hand one
  for 1.0 to 1.3 m) and the template's own body (step height 0.32 m, jump 1.25 m, 1.8 m tall).

The defaults (`vault_settings.tres`):

| Setting | Default | Why |
| --- | --- | --- |
| trigger | press jump | The jump button already exists on every device (key, pad A, the touch Jump button), as in the Game Animation Sample; the automatic trigger is the other choice, as in Fortnite's setting, and costs a probe every sprinting tick. |
| auto_min_speed | 5.5 m/s | Above the 4 m/s run and under the 6.5 m/s sprint: only a sprint climbs on its own. |
| min_vault_speed | 0 | A standing character may vault; raise it to mantle from a standstill. |
| cooldown | 0.25 s (automatic trigger only) | Stops a sprint from climbing the next wall the moment it lands; a press is meant, and chains walls. |
| detect_distance, detect_ahead_time | 0.7 m, 0.15 s | About two strides at a walk; the time term (Opsive's speed offset) lets a press a moment early at a run find the wall instead of making a jump into it. |
| max_approach_angle | 35 degrees | Opsive's "under 30" with a little room for the stick; the crossing always goes square across the face. |
| min_vault_height | 0.45 m | Above the step height (0.32 m), so kerbs stay steps. |
| max_vault_height, high_vault_above | 1.3 m, 1.0 m | The two-hand vault's top in #1010's plan; the split between the two clips. |
| max_vault_depth | 0.9 m | One hand plant crosses a wall or a crate; deeper is mantled, as RVM does. |
| foot_clearance, landing_margin | 0.12 m, 0.3 m | The feet clear the top; the landing is clear of the far face by the radius and a step. |
| max_drop | 1.2 m | A parapet over a deeper drop is not vaulted (RVM's no-landing switch, off). |
| crossing_speed, min/max_vault_time | 4 m/s, 0.45 s, 0.9 s | The crossing keeps the entry speed (Horizon's velocity rule) and never goes slower than a run; the clip is never sped up or slowed past these. |
| exit_speed_share | 0.85 | The body runs on after the landing, a little slower. |
| min/max_mantle_height, high_mantle_above | 0.45 m, 2.0 m, 1.25 m | About the standing reach of a 1.8 m body; the ALS low/high split. |
| mantle_base_time, mantle_time_per_metre | 0.45 s, 0.5 s/m | 0.95 s onto 1 m (ClimbUp_1m is 0.67 s, played at 0.7), 1.45 s onto 2 m. |
| drop_aim | on | Both hands are busy; aim and fire stop and the arm comes down. |

Sources: [ALS-Community `ALSMantleComponent.cpp`](https://github.com/ShadowfallStudios/ALS-Community/blob/main/Source/ALSV4_CPP/Private/Components/ALSMantleComponent.cpp),
[Unreal Motion Warping](https://dev.epicgames.com/documentation/en-us/unreal-engine/motion-warping-in-unreal-engine),
[Unreal Game Animation Sample](https://dev.epicgames.com/documentation/en-us/unreal-engine/game-animation-sample-project-in-unreal-engine),
[Player Traversal Mechanics in the Vast World of Horizon Zero Dawn (Guerrilla)](https://www.slideshare.net/guerrillagames/player-traversal-mechanics-in-the-vast-world-of-horizon-zero-dawn),
[Kinemation Motion Warping: Mantle Component](https://kinemation.gitbook.io/motion-warping-for-unity/components/mantle-component),
[Opsive Agility Pack: Vault](https://opsive.com/support/documentation/character-controller-agility-pack/vault/),
[Replicated Vaulting and Mantling: Vaulting settings](https://docs.superhuman.com/@aurora-devs/documentation-replicated-vaulting-and-mantling/vaulting-9),
[Fortnite mantle activation setting (Sportskeeda)](https://sportskeeda.com/fortnite/how-mantle-fortnite-chapter-4-season-1);
seen only as a title: [Vault, Slide, Mantle: Building Brink's SMART System (GDC)](https://gdcvault.com/play/1015813/contactUs).

## For level designers {#level-designers}

<!-- new section: the issue asked for a short how-to for whoever places obstacles -->

1. Select the obstacle in the Scene dock: a `StaticBody3D` (or any body), or a `ProtoBlock`.
2. Add a child node and pick `Vaultable` (for a `ProtoBlock`, under the block itself, beside its `Body`).
3. In the inspector, leave both moves on, or untick `allow_vault` (only climbed onto) or `allow_mantle` (only vaulted
   over); untick the faces it must not be crossed from (a one-way wall). The node warns when it sits under no body or
   allows nothing.
4. Size it for what you want: vaulted from 0.45 to 1.3 m high and up to 0.9 m thick with 0.65 m of clear floor past the
   far side; mantled up to 2.0 m with room for the body to stand on top; anything else is only jumped or walked into.
   A wall with no landing room (a wall right behind it) is mantled instead.
5. Run at it and press jump. The map's `VaultCourse` (west of the room) has one of each and a dark wall without the
   component.

Use the overrides only for a shape the probe misreads (a rounded rail: `height_override`), and the clip fields for a
special crossing (a window: a clip of its own).

## Online: a puppet's vault {#online}

<!-- new section: the vault ran only on the body that steps it; nothing said how a body drawn from the network shows
     one, and online-client.md is at its size limit -->

A body drawn from the network (another player's puppet, [online-client.md#puppets](online-client.md#puppets); an AI's
puppet, [ai.md#replication](ai.md#replication)) never steps, so its `CharacterVault` never planned and the clip never
started: it showed the capsule's path over the wall in its gait. `PuppetVault` (`gameplay/character/puppet_vault.gd`,
kit #1222) plans it on the screen that draws it. When the drawn state turns to `VAULT` or `MANTLE`, the puppet runs
the same `VaultProbe` from where it was drawn the frame before, set down on the floor under it, along the heading the
server sent (the stepping body turns square to the face as it starts), at the speed it was drawn moving; the plan goes
into its `vault_motion`, `started` plays the clip as on the stepping body, the plan's time runs with the frames drawn
and the crossing ends with the drawn state. `PlayerPuppet.place` and `AiReplica` call it after a puppet's place and
state; the probe is lent the map's layers (an AI puppet's own mask is 0).

Nothing is sent: the TICK, its 12-byte player entry and the AI row are unchanged, so the bandwidth is the same. On the
course's 0.9 m wall at a run (`test_net_puppet_vault.gd`, loopback), the puppet's plan had the server's top to 0.1 mm,
its start within 7 cm and its time within 16 ms (0.466 s against 0.482 s). A probe that finds no crossing of the
server's kind (the map differs on this screen, something stands in the way here) plays no clip, as before. The clip
tour is `tools/capture/puppet_vault_tour.tscn` (Ada's own screen beside Bo's).

- **Approach:** Work out a puppet's one-off move (a vault's start) from a snapshot place, or set the drawn place down
  on the floor, never from the place drawn the frame before as it is. **Watch out for:** that frame is drawn between
  the last snapshot on the ground and the first one of the move, already part of the way up its path: the puppet's
  vault planned from 0.22 m above the floor and started 0.23 m from the server's. **Seen:** gdstudio #1222,
  2026-11-11 (`PuppetVault._on_floor`; `test_net_puppet_vault.gd`).

## Cost and the web {#cost}

<!-- new section: templates ship to the web; the probe's cost needed numbers -->

`tools/bench/vault_bench.tscn` steps 1, 8 and 40 `player.tscn` by commands down lanes of 0.9 m walls (microseconds a
body a physics tick, the body's own tick only): `off` without `vault_settings`, `press` with jump pressed every half
second, `auto` with the automatic trigger, and `open_off` / `open_auto` sprinting where there is no wall (the probe
finds nothing every tick). Desktop: the mean of three headless runs; Chrome: one run of the web export in headless
Chrome under `gds quiet` (`tools/bench/player_step_bench.py`, which reads the same page global), on a machine other
agents were using.

| 40 bodies | off (walls) | press | auto | open_off | open_auto |
| --- | ---: | ---: | ---: | ---: | ---: |
| Desktop | 56 | 26 | 26 | 29 | 42 |
| Chrome | 61 | 35 | 31 | 34 | 46 |
| Chrome at a 4x CPU throttle | 426 | 210 | 156 | 177 | 264 |

One probe alone takes 6 µs when nothing is ahead and about 60 µs when it plans a crossing (desktop). A crossing is
cheaper than running: the body moves by numbers, with no slide, so bodies that vault cost less than bodies blocked by
the same walls. The pressed trigger probes only on a press; the automatic one probes on every sprinting tick and costs
about 12 µs a body a tick on the desktop and in Chrome and about 90 µs at a 4x throttle (40 sprinting bodies: 3.5 ms a
tick on a weak machine), so the template keeps the press. Nothing of a crossing is networked beyond the command (the
jump press): the server and a predicting client step the same plan from the same state.

## Mistakes made building it {#mistakes}

<!-- new section: the first build of vaulting met these; each is a trap for the next traversal move -->

- **Approach:** Measure an obstacle's depth by casting back toward its face and count only the obstacle's own body:
  leave any other body out (add it to the cast's `exclude`) and cast again. **Watch out for:** a wall right behind a
  vaultable one stopped the back cast first, so the depth read 0.8 m instead of 0.4 m, the vault's landing landed in
  the second wall and the refusal said "no room" instead of "no landing". **Seen:** gdstudio #1013, 2026-11-10
  (`test_vault_probe_alone.gd`, the no-landing case).
- **Approach:** Look farther ahead at speed when a jump press may become a vault (`detect_ahead_time`), and test the
  press from a real approach (keys held, the press at a distance), not only from a body standing at the wall. **Watch
  out for:** the jump buffer is consumed by the ordinary jump on the same tick when the probe finds nothing, so a press
  a moment early made the character jump into the wall: every keyboard and pad test failed while the command-driven
  bot, pressed close, passed. **Seen:** gdstudio #1013, 2026-11-10.
- **Approach:** Hold only the automatic trigger with a cooldown; let a press start a crossing at once. **Watch out
  for:** a cooldown on every crossing ate a press made just after a landing, the press became a jump into the next
  wall and the tour stood against the mantle block for four seconds. **Seen:** gdstudio #1013, 2026-11-10 (the capture
  of `tools/capture/vault_tour.tscn`).
- **Approach:** Count crossings by `CharacterVault.started`, not by `state_changed`. **Watch out for:** two vaults in a
  row with no ordinary tick between them keep the state `VAULT`, so the setter says nothing and a test that counted
  state changes saw one vault for two. **Seen:** gdstudio #1013, 2026-11-10.
- **Approach:** Run a `gds_game` suite in the kit's own project (`godot/`, the physics engine its CI uses) as well as
  in a game, and assert against the measured value at a threshold, never the built size. **Watch out for:** the kit's
  project runs Godot Physics and the template Jolt: a 1.0 m wall measured a hair under 1.0 in one, so a test of the
  high clip "from 1.0 m" passed in the game and failed in the kit. **Seen:** gdstudio #1013, 2026-11-10.
- **Approach:** End every suite that runs the real player in a level with `AudioDrain.stop_all(<root>)` in
  `after_test`, as the arena suites do. **Watch out for:** `test_vault_course.gd` left a footstep playing when the run
  quit, so the run logged a leaked `AudioStreamOggVorbis` and the template command (and CI) refused it although every
  case passed; it showed only when it ran last in a short run. **Seen:** gdstudio #1013, 2026-11-10.
- **Approach:** Keep a move's whole tick in its own part (`CharacterVault.drive(body, delta)`) and leave one call in
  `Character._move`. **Watch out for:** `character.gd` sits near gdlint's 1000-line cap with three moves landing in
  it the same day; the vault's 40 lines there pushed the merge of the slide to 1028 lines and the commit was refused.
  **Seen:** gdstudio #1013, 2026-11-10 (refreshing on top of #1019).
