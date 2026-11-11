# AI senses in 3D Third Person

<!-- new section: what an AI character can know (kit #966) is a subject of its own, with its parts, the test list the
     issue asks for and its own cost table; the AI page holds only its row, and was near the page size limit -->

What an AI character can know, cheaply and fairly (kit #966; the research for #882, section 1.2, and Deadnight's bots:
[What a bot knows](../../../gamedev/bots.md#perception)). The brain reads **beliefs**, never the world: a source scan
fails a script of `gameplay/ai/` outside the perception layer that names the tree's groups, the physics space or the
player. The base, the profile and the director are on [AI characters](ai.md).

## What is in it {#parts}

| Part | Where (in `templates/3d-third-person/game/gameplay/ai/senses/`) | What it does |
| --- | --- | --- |
| `AiSenses` | `ai_senses.gd`, the `Senses` child of `ai_character.tscn` (its `senses` slot, `eye` the `CameraTarget`) | Sight, hearing, touch and tellings, turned into `beliefs`; run by `AiCharacter.think()` first, before the `thought` signal the tasks hear. Signals `suspicious`, `alerted`, `entity_noticed`, `entity_lost`, `heard`. Feeds the highest awareness to the character's `AiSituation`. |
| `AiBeliefs`, `AiBelief` | `ai_beliefs.gd`, `ai_belief.gd` (`RefCounted`) | One belief per entity: last position, velocity, time, confidence, source (seen, heard, told, touched), awareness, noticed, believed. `fire_target(from)` gives only what is believed and seen now; `search_target()` the freshest memory; `believes(node)`, `knows(node)`, `most_aware()`, `describe()`. |
| `AiSensePool` | `ai_sense_pool.gd` | A group's members split by faction, shared by every senses node and built again when the group's count changes (or every 30 ticks, or when the table is rebuilt): a grunt among 200 grunts walks the 4 players, not 199 friends. |
| `AiNoise`, `AiNoiseRecord` | `ai_noise.gd`, a node of `world/world.tscn` (group `ai_noise`); `ai_noise_record.gd` | The level's noise board: `AiNoise.emit(node, kind, position, loudness, source)`; keeps the last `capacity` noises for `keep_seconds`, each with its kind's radius in `radii` times its loudness. Draws each noise's ring with `show_noises`. |
| `AiNoiseMaker` | `ai_noise_maker.gd`, the `NoiseMaker` child of `gameplay/character/character.tscn` | The noises a body makes: a footstep every `stride` metres on the ground (by ground speed, quieter crouched or prone), a landing, a shot when its weapon fires, an impact where the shot lands (with no source: "something"). It reads the body's movement, never the animation, so a server's body makes the same steps. |
| `AiSensesView` | `ai_senses_view.gd`, the `SensesView` child of `Senses` | The debug view, off by default: the cone on the ground, the near and hearing rings, a line from the eyes to each belief (green seen, amber a memory, blue heard or told) and an awareness bar per belief above the head with the `suspicious_at` mark (red once believed). |

## How a character knows {#model}

- **Sight, cheapest first.** Distance squared (`sight_range`; `lose_sight_range` for a thing seen on the last look;
  `near_radius` for arm's reach), then the cone (from the controller's `look_direction` when it has one, else ahead of
  the body; none within `near_radius`), then the relationship (only the factions whose band is at most `care_up_to`:
  the pool skips the others whole), then at most the profile's `max_rays_per_think` rays, each taken from the
  director's `AiBudget` (8 a tick for all), to the thing whose last answer is oldest, arm's reach first. A ray's answer
  is trusted for `ray_fresh_seconds`. The rays hit `sight_mask` (World and Props: never a character's capsule or hit
  zones, [Physics layers](../physics-layers.md#template-layers)). A Dormant character does not look.
- **Awareness**, 0 to 1 per thing, rises while it is seen at `1 / time_to_notice`, times a share for distance (1 at
  the eye, `far_share` at `sight_range`), for the angle (1 ahead, `side_share` at the cone's edge), for its speed
  (`still_share` standing, 1 from the profile's `walk_speed`), for crouching or lying down (`crouch_share`,
  `prone_share`) and for an Unfriendly thing (`unfriendly_share`), so no thing is noticed sooner than `time_to_notice`
  after the first clear ray (that think earns nothing). At `suspicious_at` it says `suspicious`; at 1 the thing is
  **noticed** (`alerted`) and `reaction_time` later (never under 0.2 s) **believed** (`entity_noticed`): the brain may
  act on it. Within `near_radius` with a clear line it is noticed at once. Light is not counted yet (the template has
  no light probe).
- **Out of sight**, a glimpse not yet noticed falls to 0 over `glimpse_seconds` and is dropped; a noticed thing stays
  believed as a memory, its awareness falling over `memory_seconds`, and is forgotten `memory_seconds` after it was last
  perceived (`entity_lost`). A memory is searched for at `last_position` and never fired on.
- **Hearing.** The noises made since the last think, each heard within its radius times the profile's
  `hearing_range` over the board's `reference_hearing`; the source's band filters it (an ally's footsteps are not
  heard; a noise with no source is "something", Hostile). The board files each noise under its maker's faction
  (`AiNoise.by_faction`, `unowned` for none), so a listen reads one band a faction and walks only the noises of the
  factions it cares about, in the order they were made; one that holds a grudge reads every noise (kit #1204). A
  maker whose faction changes is filed by the faction it had when it made the noise, at most `keep_seconds` (1 s)
  before. Past the board's `occlusion` share of the radius a clear line
  is needed (one ray from the same count), else the wall muffles it. A heard thing's awareness becomes at least
  `suspicious_at` plus `heard_gain` times how near it was, so two close shots alert.
- **Touch.** A hit (`Character.took_hit`) with a source the character cares about is believed at once, with awareness 1,
  at the attacker's position: an attacker that leaves the view while hitting stays believed.
- **Team.** A thing believed from the character's own senses is told, `share_delay` later, to every ally within
  `share_radius` (an ally: Friendly or Allied toward the teller). One that did not know it believes it (source told)
  after its own reaction delay and passes the telling on once; one that knew already passes nothing on.
- **Witnesses.** The senses set `AiFactions.witness_source` to `AiSenses.witnesses_of`, so a reported attack moves only
  the factions of characters that see the actor or the victim.
- **Network.** The senses and the board run on the authority only: on a client of a remote server (`--connect`, or a
  page with `?connect=`) `sense()` and `AiNoise.emit` do nothing, and only the state the senses cause (the situation,
  what the character then does) goes over the wire. The view is drawn where it is shown and never sent.

## The inspector {#inspector}

- **`AiSenses`**: Senses `sight`, `hearing`, `touch`, `team` (all on); Targets `target_groups` (`player`,
  `ai_characters`), `care_up_to` Unfriendly, `sight_mask` World and Props, `eye` (empty: 1.55 m above the feet),
  `target_height_share` 0.85; Awareness `far_share` 0.3, `side_share` 0.5, `still_share` 0.7, `crouch_share` 0.6,
  `prone_share` 0.35, `unfriendly_share` 0.5, `glimpse_seconds` 3 s, `heard_gain` 0.5, `ray_fresh_seconds` 0.3 s;
  Network `authority_only` (on); Debug `show_view` (off), `view`. The ranges, angle, times and memory are the
  profile's Senses group ([AI characters: the inspector](ai.md#inspector)); `share_radius` and `share_delay` 0.5 s its
  Social group; `max_rays_per_think` its Budget group.
- **`AiNoise`**: `radii` (footstep 9 m, landing 12, shot 45, impact 14, explosion 70), `default_radius` 10 m,
  `occlusion` 0.5, `reference_hearing` 30 m, `keep_seconds` 1 s, `capacity` 128; Debug `show_noises` (off).
- **`AiNoiseMaker`**: `enabled`; Footsteps `stride` 1.4 m, `loud_speed` 4.5 m/s, `max_loudness` 1.4,
  `min_loudness` 0.15, `crouch_share` 0.4, `prone_share` 0.2, `check_ticks` 6; Weapon `shot_loudness` 1,
  `impact_loudness` 1, `loud_landing` 8 m/s.
- **`AiSensesView`**: the colours of the cone, its edge, the rings, the three kinds of line and the bars' back;
  `bar_height` 2.45 m, `bar_thickness` 0.09 m, `bar_length` 0.9 m, `line_width` 0.04 m, `segments` 32.

## What the senses cost {#cost}

`tools/bench/ai_senses_bench.tscn` (`ai_senses_bench.py` for Chrome). **Thinks:** N characters on a 120 m map with 16
boxes and 4 hostile targets walking circles among them, a sixth of them sensing each tick (10 Hz) with 8 rays a tick, a
shot every half second; the bodies are not stepped, so the row is the senses alone. **Crowd:** 40 walking characters
with the director (12 at Full in a browser, 60 on the desktop) and the 4 targets near, senses off and on. Godot 4.7.2,
Compatibility, Jolt, the machine shared with other agents (the rows moved by 15 to 20 % between runs). A browser's
clock reads in steps of 100 µs, so a think there is read from the tick's total.

| Thinks, 4 targets | think mean (p99) | senses a tick | thinks/s | rays/s |
| --- | ---: | ---: | ---: | ---: |
| 40, native | 21 µs (60) | 0.14 ms | 400 | 150 |
| 200, native | 39 µs (215) | 1.3 ms | 2,000 | 473 |
| 40, Chrome | 52 µs (200) | 0.36 ms | 400 | 150 |
| 200, Chrome | 48 µs (300) | 1.6 ms | 2,000 | 473 |
| 40, Chrome 4x | 205 µs (700) | 1.4 ms | 400 | 150 |
| 200, Chrome 4x | 283 µs (1,600) | 9.7 ms | 2,000 | 473 |

| Crowd: 40 walking | director's step, senses off | on | the senses' share | frame work off / on |
| --- | ---: | ---: | ---: | ---: |
| Native (60 at Full) | 1.68 ms | 2.19 ms | 0.37 ms | 3.9 / 4.4 ms |
| Chrome (12 at Full) | 1.09 ms | 1.35 ms | 0.27 ms | 2.8 / 2.9 ms |
| Chrome 4x | 5.37 ms | 6.81 ms | 1.07 ms | 31 / 65 ms |

- A think is 20 to 50 µs in this calm crowd, most of it GDScript's cost per step (sight 11 µs natively with 4
  targets in view, hearing 4, the rest 5); in a fight a think is 75 to 150 µs natively, with every sense busy and the
  tasks reacting ([the behaviour's cost](ai-behaviour.md#cost), gdstudio #1104). Rays are about 2 µs each and capped
  at 8 a tick for all, so rays a second stay flat as the crowd grows.
- The senses add about a quarter of a millisecond a tick to 40 walkers in Chrome and a millisecond at 4x: the crowd was
  already at the AI budget (1 ms, 5 ms at 4x) without them, and at 4x the frame was past the tick (31 ms) before the
  senses, so the 4x frame rows are the catch-up spiral, not the senses' cost. Cutting the think further (a native
  sight pass, or sight every other think) is a follow-up.

- **Approach:** Bench a sense that loops over a group with the group itself as the crowd (characters among characters,
  not only the 4 targets), and give each think a fast path for what it does not care about (a faction it walks past
  whole, a telling it knew). **Watch out for:** see [Crowds: AI characters](../crowds.md#ai-characters): 262 µs a
  think at 200 characters before the pools, and a storm of tellings in a crowd that all saw the same players. **Seen:**
  gdstudio #966, 2026-11-10.

## Proof {#proof}

`tests/gameplay/test_ai_senses.gd`, after Deadnight's perception list: a target behind a wall at 4 m with the character
facing away is never believed in 600 ticks (and the same target in the open ahead is); one that steps out of cover is
noticed no sooner than `time_to_notice` after the first clear ray and believed no sooner than `reaction_time` after
that; a hit from behind is believed at once; an attacker that leaves the view while hitting stays believed; a thing
within `near_radius` is noticed whichever way the character faces; a memory expires once and is never a fire target; a
friend in plain view is not perceived (no ray cast); an Unfriendly thing is noticed slower than a Hostile one; a Dormant
character does not look; a client of a remote server senses nothing; the view draws only when shown; the same start
gives the same beliefs. `test_ai_hearing.gd`: a noise inside its radius is heard once and one outside is not; a wall
muffles a noise past the occlusion share; a friend's noise is not heard; a close shot alerts and an impact is
"something"; the noise maker's footsteps follow speed and crouch and a shot is heard; an ally's telling arrives once and
is not a fire target; the ray budget caps the rays of 200 characters a tick. `test_ai_senses_contract.gd`: every
export pinned, the board in the world and the noise maker on the server's body, and the brain's firewall (with a test
that it catches a brain reading the world).

Failed first: the suites do not load on `main` (no `AiSenses`), and each rule was broken in turn in a made game to see
its test fail: the reaction delay taken out (the cover test), the touch turned off (the two hit tests), the near rule
turned off (the near test), the ray budget bypassed (the 200-character cap), the "telling once" key check removed (the
share test: about 1,000 tellings each, and the run did not end).

The capture is `tools/capture/senses_tour.tscn`: from the player's camera, a grunt with `show_view` and its overlay
while the player walks up three times, from the front (Suspicious then Alert at range), the side (Unaware until arm's
reach) and behind (heard, then noticed at arm's reach), with the footstep rings on.

- **Approach:** Prove a perception rule's test by breaking the rule in a copy of the made game and watching that test
  fail, and assert each part of a timing rule on its own (noticed after `time_to_notice`, believed `reaction_time` after
  noticing), not only their sum. **Watch out for:** the cover test checked only "believed no sooner than notice plus
  reaction", and with the reaction delay taken out it still passed: the target's distance and angle shares slowed the
  noticing by more than the delay. **Seen:** gdstudio #966, 2026-11-10 (fix: the two parts asserted apart; the
  mutation fails it).
- **Approach:** Break the rule in the made game's copy of the file, never the worktree's, with a script that stops
  when the text it replaces is missing and logs each mutation it applied. **Watch out for:** a loop meant to restore
  a scratch copy ran `git checkout` on the worktree's navigator and threw away uncommitted work; a mutation written
  before gdformat wrapped its line matched nothing, so two "rule taken out" runs tested the unbroken code. **Seen:**
  gdstudio #1062, 2026-11-11 (the navigator's mutations; the work was found again in the made game's copy).
- **Approach:** Start each run of a "same start, same result" test in the same phase of a frame (an
  `await get_tree().process_frame` first) when the second run is built inside the first one's frame loop. **Watch out
  for:** the second run was built while the test was resumed from `physics_frame`, so the director ticked once before
  the target first moved and the beliefs differed by one tick's walk (4.22 against 4.19 m): the harness, not the
  senses. **Seen:** gdstudio #966, 2026-11-10.
- **Approach:** Before adding a node to `character.tscn` (every body: the player, an AI, a server's), grep the suites
  for a count of the body's nodes (`NODES_ALIVE` in `test_parts_budget.gd`) and raise it with a line that says what the
  node costs. **Watch out for:** the `NoiseMaker` passed every AI suite and failed only the full run's parts budget
  (55 nodes against 54). **Seen:** gdstudio #966, 2026-11-10.
- **Approach:** Keep a record that names a node (a noise's maker) safe to read after the node is freed: check it with
  `is_instance_valid` (`AiNoiseRecord.maker_gone()`) before any listener touches it, and test it with the maker freed
  while its noise is still on the board. **Watch out for:** a shot's noise outlived its shooter, and every listener's
  `_noise_band` raised "previously freed" until the record expired; no suite freed a body mid-noise until #968's
  scenarios did. **Seen:** gdstudio #968, 2026-11-11 (`test_a_noise_whose_maker_was_freed_is_skipped`).
