# AI characters in 3D Third Person

<!-- new section: the AI characters (kit #963 and the chain #964 to #971 after it) are a subject of their own; the template
     page holds only its row, and nothing said how the base, the profile and the director fit together -->

The base every enemy, friendly and civilian is made from, the resource that says what kind it is, and the one node that
budgets them all (kit #963; the design is the research for #882, the costs [Crowds: AI
characters](../crowds.md#ai-characters)). Relationships (#964) are [below](#relations); senses, the navigator,
tasks and reactions come in #965 to #971, each into a slot this base leaves for it.

## What is in it {#base}

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiCharacter` | `gameplay/ai/ai_character.gd`, `ai_character.tscn` | The template's `Character` (its body, `Model` slot, animation, `Health` and ragdoll, as the player has them: the scene inherits `character_dressed.tscn`) driven by an `AiController`. Joins the group `ai_characters`, never `player`. Signals `situation_changed`, `tier_changed`, `thought`. A hit comes through `Health`, a death goes into the same ragdoll. |
| `AiController` | `gameplay/ai/ai_controller.gd` | The `CharacterController` the parts write: the movement channel (`walk_direction`, `walk_strength`) and the action channel (`look_direction`, `aim`, `fire`), turned into one `PlayerCommand` a tick with `set_from_world`. A fire that starts is a press in exactly one command; `is_still()` says it asks for nothing. |
| `AiProfile` | `gameplay/ai/ai_profile.gd`, `profiles/grunt.tres`, `ally.tres`, `civilian.tres` | Every number a kind of character reads, in six groups (Movement, Senses, Combat, Nerve, Social, Budget), each an `@export` with a range, a unit and a tooltip, read where it is used so an edit applies live. |
| `AiDirector` | `gameplay/ai/ai_director.gd`, a node of `world/world.tscn` (group `ai_director`) | Steps every registered character's body, runs its think at its rate on its own phase, puts it in a tier by distance, and holds the shared `AiBudget`. It gives a character its `tier` and its `budget` and nothing else. |
| `AiBudget` | `gameplay/ai/ai_budget.gd` | Rays, path queries and thinks all characters together may spend in one physics tick; `take_ray()`, `take_path()`, `take_think()` refuse the one over the count. |
| `AiSituation` | `gameplay/ai/ai_situation.gd` | Unaware, Suspicious, Alert, Engaged, Fleeing, Dead: rising is at once, calming down or turning sideways waits `situation_dwell`, awareness crosses its lines with `awareness_hysteresis`, death is at once and only `revive()` leaves it. |
| Relationships | `gameplay/ai/relations/`: `AiRelations`, `AiFaction`, `AiRelationEvent`, `ai_relations.tres`, `AiFactions` (a node of `world/world.tscn`), `AiFactionMember` (a child of `ai_character.tscn` and `player.tscn`) | Who is hostile to whom and how it changes (kit #964): [Factions and relationships](#relations). |
| Debug overlay | the `DebugLabel` (`Label3D`) of `ai_character.tscn` | The profile's name, the situation and the tier above the head, with `debug` on (off by default; written only on a change or a think while on). |

The director lives in `world.tscn`, not `main.tscn`: the main scene holds only instances and wires
([Which scene to open](../third-person-template.md#scene-map)), and the director is a system the map owns, which a server
that loads the world gets too. It finds the characters already in the tree when it starts, and a character added later
finds it through the group; a character with no director steps itself and never thinks.

## The inspector {#inspector}

- **`AiCharacter`** (group AI): `profile` (the grunt in `ai_character.tscn`), `debug`, `debug_label`; group Slots:
  `senses`, `navigator`, `task_runner` (empty until #966, #967 and #965 fill them). Everything `Character` has
  (tuning, weapon, ragdoll) is there too.
- **`AiProfile`**: `display_name`; Movement `walk_speed` 1.6 m/s, `run_speed` 4.5 m/s, `turn_rate` 360 °/s,
  `acceleration` 12 m/s²; Senses `sight_range` 24 m, `lose_sight_range` 32 m, `half_angle` 55°, `near_radius` 2 m,
  `hearing_range` 30 m, `time_to_notice` 0.6 s, `reaction_time` 0.35 s (never under 0.2), `memory_seconds` 6,
  `suspicious_at` 0.3, `awareness_hysteresis` 0.1; Combat `engage_range` 18 m, `preferred_range` 10 m,
  `attack_range` 1.6 m, `fire_interval` 0.4 s, `burst_size` 3, `accuracy` 0.5, `aim_speed` 360 °/s,
  `retreat_margin` 3 m; Nerve `courage` 0.5, `flee_below_health` 0.3, `panic_recovery_seconds` 8, `aggression` 0.5,
  `curiosity` 0.5, `alert_hold_seconds` 10, `situation_dwell` 1 s; Social `faction`, `share_radius` 12 m,
  `obeys_orders` 0.5; Budget `think_rate` 10 Hz, `reduced_think_rate` 2 Hz, `dormant_think_rate` 0.5 Hz,
  `full_range` 25 m, `reduced_range` 70 m, `tier_margin` 4 m, `max_rays_per_think` 2, `repath_seconds` 0.25 s. The
  three files change only what makes the kind: the grunt (faction `enemy`, `accuracy` 0.4), the ally (`ally`,
  0.6, `obeys_orders` 0.9), the civilian (`civilian`, `engage_range` 0, `flee_below_health` 1, `courage` 0.1); the
  faction names are rows of the relationships table ([Factions and relationships](#relations)).
- **`AiDirector`**: Population `web_cap` 40, `desktop_cap` 120, `web_full_cap` 12, `desktop_full_cap` 60,
  `player_group`; Budget a tick `rays_per_tick` 8, `paths_per_tick` 4, `thinks_per_tick` 12; Steps
  `reduced_step_ticks` 4, `dormant_step_ticks` 6, `rest_step_ticks` 3.

## How the director schedules {#schedule}

- **Thinks.** A character thinks every `ticks per second / rate` ticks at its tier's rate, read from the profile at each
  think (so an edit applies at the next one; 0 stops it). Its first think goes on the tick of the coming interval
  where the fewest thinks already fall, so N characters with the same interval take N different ticks while N is at
  most the interval (6 ticks at 10 Hz and 60 Hz). A think over `thinks_per_tick` waits for the next tick, and each
  tick the loop starts one character further along so the same one is not put off every time.
- **Tiers.** Every 8th tick on each character's own slot, by its distance to the nearest body of `player_group`:
  Full under `full_range`, Reduced under `reduced_range`, Dormant past it, and a character keeps a nearer tier until it
  is `tier_margin` past that tier's range. At most `web_full_cap` (in a browser) or `desktop_full_cap` are Full; a
  nearer character takes the slot of the farthest Full one. No player at all is infinitely far: every character is
  Dormant.
- **Steps.** A Full body is stepped every tick, a Reduced one every `reduced_step_ticks` and a Dormant one every
  `dormant_step_ticks`, on its own slot, with the missed time handed on: `Character.step(command, delta)` takes a whole
  number of physics steps and scales the velocity for the move, so a far character walks as far in the same time
  (`test_a_far_character_stepped_less_often_walks_as_far`). A character at rest (on a floor that does not move, still,
  its controller asking for nothing) or dead is stepped at most every `rest_step_ticks`. A far body moves in steps of
  four or six ticks, which shows only to a camera near it.

## What it costs {#cost}

<!-- new section: the cost of the real character, which sets the director's web defaults, is read here first -->

40 walking characters in Chrome on the fast desktop: the director's step is 0.99 ms a tick (4.75 ms at a 4x CPU
throttle) with the shipped defaults, 12 at the Full tier and the rest stepped every 4th tick; standing, 0.53 ms (2.4 ms).
A walking body at Full is about 50 µs in Chrome and 35 µs native, the director's own work about 3 µs a character. The
table and why the Full cap is 12 and not the research's 20: [Crowds: AI characters](../crowds.md#ai-characters).

- **Approach:** Raise `web_full_cap` or lower `reduced_step_ticks` only with the bench run again in Chrome at 1x and 4x
  (`tools/bench/ai_cost_bench.py`), and read the frame's work beside the director's step. **Watch out for:** at 4x the
  whole frame of 40 walkers is 19.5 ms, past the 16.7 ms tick, from the animation and the footsteps, which the AI budget
  does not count. **Seen:** gdstudio #963, 2026-11-10.

## Factions and relationships {#relations}

<!-- new section: relationships (kit #964) are a part of their own with an API the senses (#966), the router and the
     weapons call; the base's table holds only its row -->

Who is hostile, neutral or friendly to whom, and how that changes (kit #964; research for #882, section 4). Nothing in
code names a faction: a game with three player teams edits `ai_relations.tres`. The model, apart from Godot:
[Factions and relationships](../../../gamedev/simulation.md#relationships).

| Part | Where (in `gameplay/ai/relations/`) | What it does |
| --- | --- | --- |
| `AiRelations` | `ai_relations.gd`, `ai_relations.tres` | The table: the factions, the events, the band lines and the recovery rate; for every ordered pair a base and a current attitude, -100 to 100, asymmetric (A toward B is not B toward A). Signals `band_changed(a, b, previous, now)` and `attitude_changed(i, j)` (set or moved by an event, not by recovery). |
| `AiFaction` | `ai_faction.gd` (rows of the `.tres`) | `id`, `color`, `hurts_friends`, and `attitudes`: its row, the base attitude toward each faction it names (its own id included); one it does not name is at `default_attitude`. |
| `AiRelationEvent` | `ai_relation_event.gd` (rows of the `.tres`) | `id`, `delta` and `witness` (`WITNESSED`: only the factions of characters that perceived it change; `ALWAYS`: the victim's faction changes unseen, for a mission's script or an alarm). |
| `AiFactions` | `ai_factions.gd`, a node of `world/world.tscn` (group `ai_factions`) | Plays a copy of the table (`AiRelations.copy()`: a match never writes the file), answers between two entities (a grudge first, then the factions), turns reported acts into changes, calls `recover()` every physics tick, and colours the band rings when `show_bands` is on. |
| `AiFactionMember` | `ai_faction_member.gd`, a child node of `ai_character.tscn` (faction empty: the profile's) and `player.tscn` (faction `player`) | Puts its parent in a faction (`AiFactionMember.of(node)` finds it through a meta on the parent), holds its personal grudges, caches its faction's index for the hot path, and reports a hit on its parent as an `attack` by the hit's source and a death as a `kill`, witnessed by the parent. Its `band_marker` is the `BandRing` under the character's feet. |

**The shipped table.** Rows are from, columns toward:

| | player | enemy | ally | civilian |
| --- | ---: | ---: | ---: | ---: |
| **player** (`hurts_friends`) | 100 | -100 | 80 | 20 |
| **enemy** | -100 | 100 | -100 | -30 |
| **ally** | 80 | -100 | 100 | 30 |
| **civilian** | 20 | -50 | 30 | 60 |

Events: `attack` -30, `kill` -60, `help` +10, `trespass` -10, all `WITNESSED`. A kill counts on top of the blow that
made it. The enemy is Unfriendly to civilians (it does not shoot them unprovoked), civilians are Unfriendly to the enemy
(their fear is the profile's `courage`).

**Bands.** Hostile at or under `hostile_at` (-60), Unfriendly at or under `unfriendly_at` (-20), Neutral, Friendly at
or over `friendly_at` (20), Allied at or over `allied_at` (60). A pair enters a band farther from Neutral at its line
and leaves back toward Neutral only `hysteresis` (20) past it: Hostile is entered at -60 and left at -40, so a value
that wobbles on a line changes the band once. A jump across Neutral takes the new band at once.

**Change.** `set_attitude(a, b, value)` (a script), `add_attitude(a, b, delta, witnesses)` (nothing when `witnesses`
is 0), and `AiFactions.report(event, actor, victim, witnesses)`: each faction among the witnesses (once however many
of its members saw it) that is not Hostile toward the victim moves its attitude toward the actor's faction by the
event's delta, so an ally that sees the player shoot a grunt does not mind. Without a witness list the witnesses are
`witness_source`'s, or the victim alone (it feels a blow on itself). The current value drifts back to the base at
`recovery_per_minute` (10). A personal grudge (`AiFactionMember.grudge(entity, value)`, `forgive(entity)`) beats the
faction for one entity against one character.

**Friendly fire.** `AiFactions.can_hurt(attacker, victim)` is false when the attacker is Friendly or Allied toward the
victim and its faction's `hurts_friends` is off. `HitZones.deliver()` drops such a hit, so a stray shot of a grunt
through another grunt does nothing; the player's faction hurts friends, so shooting an ally lands and costs attitude
(five shots turn the allies Hostile; three and a half minutes bring them back to Unfriendly). With no `AiFactions` in
the tree, or for an entity in no faction, everyone may hurt everyone. An AI's fire decision (#968) asks `can_hurt`
before it pulls the trigger.

**Network.** The table lives on the authority. A change is `encode_change(i, j)`: 3 bytes (the two faction indexes and
the value as a signed byte), sent on `attitude_changed`; a late joiner gets `encode_all()` (1 byte and one a pair, 17
for the shipped table) once; a client applies either with `apply(bytes)` and uses the bands for colours only. Recovery
runs on both ends from the same rate; the next change or snapshot corrects any drift. Wiring it into the template's
packets comes with the networked client (#905).

### The API the senses read {#relations-api}

The senses (#966) filter what a character perceives by affiliation first (do not sense what you do not care about).
They call:

- `AiFactionMember.of(node) -> AiFactionMember` once for each thing they start to track, and keep the member beside
  its memory entry.
- `factions.band_of_members(me, it) -> int` (`AiRelations.Band`) or `is_hostile_members(me, it)`: the hot path, a
  grudge check only when `me` holds one, two cached faction indexes and one byte read. `factions` is
  `my_member.level()`, found once and kept.
- `band_between(a, b)` and `is_hostile_between(a, b)` take nodes (two meta reads more), for code that has no members.
- `factions.witness_source = func(actor, victim) -> Array`: the senses return the characters that perceived an act, so
  a reported `attack` or `kill` moves only the factions that saw it.
- `relations.band_changed` to look again at a remembered entity whose band changed (a now-hostile entity in memory
  raises the noticed response).

A member caches its faction's index and reads it again when the table is built again or after a think of its
character, so a profile's faction edited live applies at the next think; a member's own `faction` applies at once.

### The inspector {#relations-inspector}

- **`AiRelations`**: `factions`, `events`, `default_attitude` 0; Bands `hostile_at` -60, `unfriendly_at` -20,
  `friendly_at` 20, `allied_at` 60, `hysteresis` 20; Change `recovery_per_minute` 10 /min.
- **`AiFaction`**: `id`, `color`, `hurts_friends` (off), `attitudes`. **`AiRelationEvent`**: `id`, `delta`,
  `witness`.
- **`AiFactions`**: `relations` (`ai_relations.tres` in `world.tscn`); Debug `show_bands` (off),
  `band_refresh_seconds` 0.25 s, `band_colors` (Hostile red to Allied blue), `player_group`.
- **`AiFactionMember`**: `faction` (empty: the profile's), `reports_events` (on), `band_marker`.

### What it costs {#relations-cost}

`tools/bench/ai_relations_bench.tscn` (`ai_relations_bench.py` for Chrome) asks 200 entities 8 lookups each, 1600 a
round, the mean of 200 rounds on the fast desktop (the machine shared with other agents):

| A round of 1600 | Native (editor build) | Chrome | Chrome 4x |
| --- | ---: | ---: | ---: |
| `band_at(i, j)`, indexes known | 250 µs | 315 to 335 µs | 1.7 ms |
| `band_of_members(a, b)`, members kept | 920 µs | 1.05 to 1.10 ms | 6.8 ms |
| `band_between(a, b)`, nodes | 2.1 to 2.3 ms | 2.5 to 2.6 ms | 14.9 ms |
| `can_hurt(a, b)` | 2.7 to 2.8 ms | 4.7 ms | 21.7 ms |

A lookup allocates nothing. At 10 thinks a second and 60 ticks a character thinks every 6th tick, so 200 characters
with 8 member lookups a think are 0.18 ms a tick in Chrome (1.1 ms at 4x), and the web's 40 characters 35 µs (0.23 ms
at 4x), inside the AI budget of [Crowds: AI characters](../crowds.md#ai-characters) (1 ms a tick, 5 ms at 4x).
`can_hurt` is for a shot, not for every look.

- **Approach:** Give a lookup that a think makes many times a fast path that takes the parts it needs already found
  (the members) and reads cached indexes, keep the node-taking form for convenience, and bench the round in Chrome at
  1x and 4x before calling it cheap. **Watch out for:** the first lookup between two nodes made about 15 GDScript calls
  (two meta reads, two faction names, two dictionary reads, the band) and cost 2.7 µs natively, 0.7 ms a tick for
  200 characters; a call is 0.1 to 0.2 µs, so the count of calls, not the arrays, sets the cost. **Seen:** gdstudio
  #964, 2026-11-10 (`band_of_members`: 0.58 µs native, 0.66 µs in Chrome).

### Proof {#relations-proof}

`tests/gameplay/test_ai_relations.gd` (the shipped table, asymmetry, a faction not in the table, the bands with their
hysteresis and editable lines, a jump across Neutral, recovery toward base, a row edited live, the bytes a client
rebuilds from, the pinned defaults) and `test_ai_factions.gd` (an unwitnessed act changes nothing, a witnessed one
moves each witness faction once, a witness hostile to the victim does not mind, recovery on the physics clock, a grudge
beating the faction, a friend's shot refused at the hit zones, no factions, the ally the player keeps shooting turning
Hostile and back, a kill on top of the blow, the band rings, a profile's faction at the next think, the world playing
the shipped table). The capture is `tools/capture/factions_tour.tscn`: grunts and allies trading shots across a lane
with the band rings on, a grunt killed into its ragdoll, then the player shooting an ally until the allies' rings turn
from blue through grey to red.

- **Approach:** In a capture that lands hits on characters standing in rows, deliver a `HitRecord.shot` with no push,
  not a `HitRecord.blow`. **Watch out for:** a blow staggers and throws the character away from its source, so after
  four exchanges the two rows had slid out of the frame and into a pillar. **Seen:** gdstudio #964, 2026-11-10.

## Proof {#proof}

`tests/gameplay/test_ai_director.gd` (thinks at the rate and on ticks of their own, the ray budget shared and reset, the
think budget, a profile edit while running, tiers with the margin and the cap, the population cap, the rest cadence,
far characters walking as far), `test_ai_situation.gd` (rising, dwell, hysteresis, death) and `test_ai_character.gd`
(the parts, the channels, a hit that kills into the ragdoll, the overlay, the profiles). The capture is
`tools/capture/ai_tour.tscn` (the three profiles side by side with the overlay, a grunt killed into its ragdoll) and the
cost is `tools/bench/ai_cost_bench.tscn` with `ai_cost_bench.py` for Chrome ([the numbers](../crowds.md#ai-characters)).
