# Factions and relationships in 3D Third Person

<!-- new section: moved whole from ai.md's relationships section when that page passed the 50 KB limit (kit #1208);
     relationships (#964) are a part with their own API, inspector, cost and proof -->

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
- `factions.witness_source = func(actor, victim) -> Array`: the characters that perceived an act, so a reported
  `attack` or `kill` moves only the factions that saw it. The senses set it to `AiSenses.witnesses_of` (the victim and
  every character that sees the actor or the victim now) when it is unset.
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
