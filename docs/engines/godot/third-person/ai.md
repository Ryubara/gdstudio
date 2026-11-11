# AI characters in 3D Third Person

<!-- new section: the AI characters (kit #963 and the chain #964 to #971 after it) are a subject of their own; the template
     page holds only its row, and nothing said how the base, the profile and the director fit together -->

The base every enemy, friendly and civilian is made from, the resource that says what kind it is, and the one node that
budgets them all (kit #963; the design is the research for #882, the costs [Crowds: AI
characters](../crowds.md#ai-characters)). Senses, the navigator, tasks and reactions come in #964 to #971, each into a
slot this base leaves for it.

## What is in it {#base}

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiCharacter` | `gameplay/ai/ai_character.gd`, `ai_character.tscn` | The template's `Character` (its body, `Model` slot, animation, `Health` and ragdoll, as the player has them: the scene inherits `character_dressed.tscn`) driven by an `AiController`. Joins the group `ai_characters`, never `player`. Signals `situation_changed`, `tier_changed`, `thought`. A hit comes through `Health`, a death goes into the same ragdoll. |
| `AiController` | `gameplay/ai/ai_controller.gd` | The `CharacterController` the parts write: the movement channel (`walk_direction`, `walk_strength`) and the action channel (`look_direction`, `aim`, `fire`), turned into one `PlayerCommand` a tick with `set_from_world`. A fire that starts is a press in exactly one command; `is_still()` says it asks for nothing. |
| `AiProfile` | `gameplay/ai/ai_profile.gd`, `profiles/grunt.tres`, `ally.tres`, `civilian.tres` | Every number a kind of character reads, in six groups (Movement, Senses, Combat, Nerve, Social, Budget), each an `@export` with a range, a unit and a tooltip, read where it is used so an edit applies live. |
| `AiDirector` | `gameplay/ai/ai_director.gd`, a node of `world/world.tscn` (group `ai_director`) | Steps every registered character's body, runs its think at its rate on its own phase, puts it in a tier by distance, and holds the shared `AiBudget`. It gives a character its `tier` and its `budget` and nothing else. |
| `AiBudget` | `gameplay/ai/ai_budget.gd` | Rays, path queries and thinks all characters together may spend in one physics tick; `take_ray()`, `take_path()`, `take_think()` refuse the one over the count. |
| `AiSituation` | `gameplay/ai/ai_situation.gd` | Unaware, Suspicious, Alert, Engaged, Fleeing, Dead: rising is at once, calming down or turning sideways waits `situation_dwell`, awareness crosses its lines with `awareness_hysteresis`, death is at once and only `revive()` leaves it. |
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
  three files change only what makes the kind: the grunt (faction `enemies`, `accuracy` 0.4), the ally (`players`,
  0.6, `obeys_orders` 0.9), the civilian (`civilians`, `engage_range` 0, `flee_below_health` 1, `courage` 0.1).
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

## Proof {#proof}

`tests/gameplay/test_ai_director.gd` (thinks at the rate and on ticks of their own, the ray budget shared and reset, the
think budget, a profile edit while running, tiers with the margin and the cap, the population cap, the rest cadence,
far characters walking as far), `test_ai_situation.gd` (rising, dwell, hysteresis, death) and `test_ai_character.gd`
(the parts, the channels, a hit that kills into the ragdoll, the overlay, the profiles). The capture is
`tools/capture/ai_tour.tscn` (the three profiles side by side with the overlay, a grunt killed into its ragdoll) and the
cost is `tools/bench/ai_cost_bench.tscn` with `ai_cost_bench.py` for Chrome ([the numbers](../crowds.md#ai-characters)).
