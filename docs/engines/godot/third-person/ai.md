# AI characters in 3D Third Person

<!-- new section: the AI characters (kit #963 and the chain #964 to #971 after it) are a subject of their own; the template
     page holds only its row, and nothing said how the base, the profile and the director fit together -->

The base every enemy, friendly and civilian is made from, the resource that says what kind it is, and the one node that
budgets them all (kit #963; the design is the research for #882, the costs [Crowds: AI
characters](../crowds.md#ai-characters)). Relationships (#964) are [below](#relations), tasks (#965)
[below](#tasks), the navigator (#967) [below](#navigator), senses, awareness and memory (#966) on [AI
senses](ai-senses.md), reactions (#968) on [AI behaviour](ai-behaviour.md); #969 to #971 follow, each into a slot
this base leaves for it.

## What is in it {#base}

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiCharacter` | `gameplay/ai/ai_character.gd`, `ai_character.tscn` | The template's `Character` (its body, `Model` slot, animation, `Health` and ragdoll, as the player has them: the scene inherits `character_dressed.tscn`) driven by an `AiController`. Joins the group `ai_characters`, never `player`. Signals `situation_changed`, `tier_changed`, `thought`. A hit comes through `Health`, a death goes into the same ragdoll. |
| `AiController` | `gameplay/ai/ai_controller.gd` | The `CharacterController` the parts write: the movement channel (`walk_direction`, `walk_strength`) and the action channel (`look_direction`, `aim`, `fire`), turned into one `PlayerCommand` a tick with `set_from_world`. A fire that starts is a press in exactly one command; `is_still()` says it asks for nothing. |
| `AiProfile` | `gameplay/ai/ai_profile.gd`, `profiles/grunt.tres`, `ally.tres`, `civilian.tres` | Every number a kind of character reads, in six groups (Movement, Senses, Combat, Nerve, Social, Budget), each an `@export` with a range, a unit and a tooltip, read where it is used so an edit applies live. |
| `AiDirector` | `gameplay/ai/ai_director.gd`, a node of `world/world.tscn` (group `ai_director`) | Steps every registered character's body, runs its think at its rate on its own phase, puts it in a tier by distance, and holds the shared `AiBudget`. It gives a character its `tier` and its `budget` and nothing else. |
| `AiAnimationThrottle` | `gameplay/ai/ai_animation_throttle.gd`, the `AnimationThrottle` child of the `AiDirector` in `world/world.tscn` (the director's `animation_throttle`) | Moves each managed character's `AnimationTree` on less often where nobody would see it (far, out of view, Dormant), with the footsteps only near the camera: [The animation throttle](#animation-throttle). |
| `AiBudget` | `gameplay/ai/ai_budget.gd` | Rays, path queries and thinks all characters together may spend in one physics tick; `take_ray()`, `take_path()`, `take_think()` refuse the one over the count. |
| `AiSituation` | `gameplay/ai/ai_situation.gd` | Unaware, Suspicious, Alert, Engaged, Fleeing, Dead: rising is at once, calming down or turning sideways waits `situation_dwell`, awareness crosses its lines with `awareness_hysteresis`, death is at once and only `revive()` leaves it. |
| Relationships | `gameplay/ai/relations/`: `AiRelations`, `AiFaction`, `AiRelationEvent`, `ai_relations.tres`, `AiFactions` (a node of `world/world.tscn`), `AiFactionMember` (a child of `ai_character.tscn` and `player.tscn`) | Who is hostile to whom and how it changes (kit #964): [Factions and relationships](#relations). |
| Senses | `gameplay/ai/senses/`: `AiSenses` (the `Senses` child of `ai_character.tscn`, its `senses` slot) with its `AiSensesView`, `AiBeliefs` and `AiBelief`, `AiSensePool`, the level's `AiNoise` board (a node of `world/world.tscn`) with `AiNoiseRecord`, and the `AiNoiseMaker` of `character.tscn` | What a character can know (kit #966): sight, hearing, touch and tellings turned into beliefs the brain reads instead of the world, on the think tick and the shared ray budget: [AI senses](ai-senses.md). |
| Behaviour | `gameplay/ai/behaviour/` (`AiBrain`, the `Brain` child of `ai_character.tscn`, its `brain` slot; `AiBehaviourSet` and `sets/*.tres`), `tasks/stock/`, `ai_guard.tscn`, `ai_ally.tscn`, `ai_civilian.tscn` | What a character does (kit #968): events routed through a table into stock tasks, play states: [AI behaviour](ai-behaviour.md). |
| Debug overlay | the `DebugLabel` (`Label3D`) of `ai_character.tscn` | The profile's name, the situation and the tier above the head, with `debug` on (off by default; written only on a change or a think while on). |

The director lives in `world.tscn`, not `main.tscn`: the main scene holds only instances and wires
([Which scene to open](../third-person-template.md#scene-map)), and the director is a system the map owns, which a server
that loads the world gets too. It finds the characters already in the tree when it starts, and a character added later
finds it through the group; a character with no director steps itself and never thinks.

## The inspector {#inspector}

- **`AiCharacter`** (group AI): `profile` (the grunt in `ai_character.tscn`), `debug`, `debug_label`; group Slots:
  `navigator` (the `Navigator` node, an `AiNavigator`, [below](#navigator)), `senses` (the `Senses` node of
  `ai_character.tscn`, [AI senses](ai-senses.md#inspector)), `task_runner` (the `AiTasks` node of
  `ai_character.tscn`, [Tasks](#tasks)), `brain` (the `Brain` node, [AI behaviour](ai-behaviour.md#inspector)).
  Everything `Character` has (tuning, weapon, ragdoll) is there too.
- **`AiProfile`**: `display_name`; Movement `walk_speed` 1.6 m/s, `run_speed` 4.5 m/s, `turn_rate` 360 °/s,
  `acceleration` 12 m/s²; Senses `sight_range` 24 m, `lose_sight_range` 32 m, `half_angle` 55°, `near_radius` 2 m,
  `hearing_range` 30 m, `time_to_notice` 0.6 s, `reaction_time` 0.35 s (never under 0.2), `memory_seconds` 6,
  `suspicious_at` 0.3, `awareness_hysteresis` 0.1; Combat `engage_range` 18 m, `preferred_range` 10 m, `attack_range`
  1.6 m, `fire_interval` 0.4 s, `burst_size` 3, `accuracy` 0.5, `aim_speed` 360 °/s, `retreat_margin` 3 m; Nerve
  `courage` 0.5, `flee_below_health` 0.3, `panic_recovery_seconds` 8, `aggression` 0.5, `curiosity` 0.5,
  `alert_hold_seconds` 10, `situation_dwell` 1 s; Social `faction`, `share_radius` 12 m, `share_delay` 0.5 s,
  `obeys_orders` 0.5; Budget `think_rate` 10 Hz, `reduced_think_rate` 2 Hz, `dormant_think_rate` 0.5 Hz, `full_range`
  25 m, `reduced_range` 70 m, `tier_margin` 4 m, `max_rays_per_think` 2, `repath_seconds` 0.25 s. The three files
  change only what makes the kind: the grunt (faction `enemy`, `accuracy` 0.4), the ally (`ally`, 0.6, `obeys_orders`
  0.9), the civilian (`civilian`, `engage_range` 0, `flee_below_health` 1, `courage` 0.1); the faction names are rows
  of the relationships table ([Factions and relationships](#relations)). Tasks (#965): `under_attack`
  FINISH_THEN_REACT, `task_hard_timeout` 30 s, `failure_budget` 3, `failure_window` 10 s, `fallback_seconds` 5 s,
  `commit_seconds` 0.5 s.
- **`AiTasks`** (a child of the character): Tasks `default_task`, `routine`, `attack_task`, `needs`; Debug `label`
  (the `TaskLabel` above the head). All empty by default: an empty runner costs one call a think.
- **`AiTask`**: Task `id`, `layer` ROUTINE, `channels` Move; Interruption `interruptible` YES, `when_interrupted`
  SUSPEND_RESUME, `resume_valid_for` 0, `under_attack` PROFILE, `abort_damage` 20, `abort_window` 1 s, `persistent`
  off, `reactive` on, `replace_policy` MERGE; Time `timeout` 0, `hard_timeout` -1 (the profile's),
  `ends_on_condition` off, `expires_after` 0; Failure `on_fail` SKIP, `retry_count` 1, `retry_delay` 0.5 s,
  `fallback`; Order `authority` 0, `need`. Composites add `children` (`AiTaskParallel` `finish_on_first`,
  `AiTaskRepeat` `count` 0 = forever). `AiNeedRow`: `need`, `order` `*`, `gives_way_at` 0.5.
- **`AiDirector`**: Population `web_cap` 40, `desktop_cap` 120, `web_full_cap` 12, `desktop_full_cap` 60,
  `player_group`; Budget a tick `rays_per_tick` 8, `paths_per_tick` 4, `thinks_per_tick` 12; Steps
  `reduced_step_ticks` 4, `dormant_step_ticks` 6, `rest_step_ticks` 3; Animation `animation_throttle` (the
  `AnimationThrottle` node in `world.tscn`; empty: every character animates every frame).
- **`AiAnimationThrottle`**: `enabled`; Distances `near_distance` 15 m, `far_distance` 25 m, `footstep_range` 15 m
  (all from the camera); Periods `reduced_period` 3, `far_period` 6 (frames), `freeze_unseen`, `max_catch_up` 0.25 s,
  `hit_hold` 1 s; Work `recheck_frames` 4, `throttle_skeleton`, `camera` (empty: the viewport's).

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

## The navigator {#navigator}

The `AiNavigator` in the character's navigator slot (kit #967, its web cost #1062): its rules, inspector, cost and
proof are on [The AI navigator](ai-navigator.md).

## The animation throttle {#animation-throttle}

<!-- new section: with the director in, the AI step held its budget but every character's animation tree and footsteps
     ran every frame and put the 4x frame past the tick (gdstudio #1046); nothing said how a character's animation is
     cut down by its tier and the view -->

`AiAnimationThrottle` (gdstudio #1046) is the first payoff of [the crowd spike](../crowds.md#recommendation). Its
rules live in `CharacterAnimationThrottle` since #1138 (the online puppets use it too); the subclass adds the tier. The
director hands it every character it registers and takes it back on `unregister`; it gives each one a period in frames,
worked out again every `recheck_frames` on a frame of its own and at once on a tier change, a hit, a death or a revive:

| The character is | Its tree |
| --- | --- |
| new (its first 8 frames), nearer the camera than `near_distance`, dead or in its ragdoll, or hit in the last `hit_hold` | runs itself every frame, untouched, as the player's does |
| Dormant, or out of the camera's view (feet, chest and head all outside the frustum) | holds its pose; seen again it moves on by the time it missed, `max_catch_up` at most |
| Full, in view | every frame |
| Reduced, in view | every `reduced_period` frames |
| either, farther than `far_distance` from the camera | every `far_period` frames at least |

A throttled tree is advanced by the time since its last advance, so the clips keep their speed, and with it the
skeleton's modifiers (`throttle_skeleton`: the hand on the weapon); the `WeaponHold` puts its weights on at each advance
instead of every frame, and the ragdoll keeps no per-tick pose for its bones' own velocities (a death in that time
leaves with the character's velocity, as `pose_velocity` off does). Footsteps play only for a character animated every
frame within `footstep_range` of the camera, which is the listener. The tree keeps its callback mode: only its own
update stops ([AnimationTree: throttling a running tree](../animation-tree.md#throttling-a-running-tree)). Cosmetic and
per machine: nothing in it changes what a body does or what a network sends, and the player, a `character_dressed.tscn`
alone and a director without a throttle animate exactly as before.

Near the camera nothing changes: `tools/capture/ai_tour.tscn` filmed with the throttle on and off matches frame for
frame to the run-to-run noise of two runs with it off (160 and 194 of 203 frames identical, no pixel off by more than 8
of 255 in either). What it saves is in [What it costs](#cost).

## What it costs {#cost}

<!-- new section: the cost of the real character, which sets the director's web defaults, is read here first -->

40 walking characters in Chrome on the fast desktop: the director's step is 0.99 ms a tick (4.75 ms at a 4x CPU
throttle) with the shipped defaults, 12 at the Full tier and the rest stepped every 4th tick; standing, 0.53 ms (2.4 ms).
A walking body at Full is about 50 µs in Chrome and 35 µs native, the director's own work about 3 µs a character. The
table and why the Full cap is 12 and not the research's 20: [Crowds: AI characters](../crowds.md#ai-characters).

With the animation throttle (#1046) the whole frame of 40 walkers in Chrome is 1.4 ms against 2.8 ms, and at 4x 9 to
10 ms with one tick a frame or fewer against 53 to 63 ms with five or six; what is left over 8 ms at 4x is the director's
step, the walking body ([the table and where it goes](../crowds.md#ai-characters)).

Since #1059 an AI's body takes the lean tick (`CharacterLean`, chosen by `AiController.lean_step`) whenever it only
walks or stands: the same result as the full tick with the modules that have nothing to do left out, the step climber
run only after the move met a wall, and the controller's command built again only when a channel changes. The
director's step for 40 walkers is 22 to 30 % shorter (0.9 ms at 1x, 4.4 to 5.5 ms at 4x on a quiet machine) and the
4x frame 7.2 to 8.9 ms ([the module profile and the runs](../crowds.md#ai-characters)). Since #1104 it takes the aim
and the trigger too, so a fighting body is lean on every tick but the one its aim goes up or comes down, and a fight
has a web count of its own: 12 fighting guards at 1x, 6 at 4x
([AI behaviour: the follow-up](ai-behaviour.md#cost-follow-up)). A part that gives an AI's body
something to do on a walking tick (a held bit, a timer) goes in `CharacterLean.can_take()`
([the body's modules](character.md#controller)).

- **Approach:** Raise `web_full_cap` or lower `reduced_step_ticks` only with the bench run again in Chrome at 1x and 4x
  (`tools/bench/ai_cost_bench.py`), and read the frame's work, its ticks a frame and the calibration loop beside the
  director's step. **Watch out for:** at 4x the whole frame of 40 walkers was 19.5 ms, past the 16.7 ms tick, from the
  animation and the footsteps, which the AI budget does not count (the throttle answers that), and a busy machine
  reads 20 to 40 % slower: compare runs by the calibration loop. **Seen:** gdstudio #963, 2026-11-10; gdstudio #1046,
  2026-11-11; gdstudio #1059, 2026-11-11 (the same build read 7.2 to 8.1 ms and 8.7 to 11.6 ms at 4x hours apart:
  interleave a build of `main` in every session).

## Tasks {#tasks}

<!-- new section: the base above leaves a task-runner slot; nothing said how a task is written, what its contract
     fields do, or what the runner does in each edge case, which #968's stock tasks and every game build on -->

What a character is doing, as layers of tasks any system can hand it (kit #965; the design is section 3 of the
research for #882). The core needs no scene: a test makes an `AiTaskRunner` and steps it.

| Part | Where (in `templates/3d-third-person/game/gameplay/ai/tasks/`) | What it does |
| --- | --- | --- |
| `AiTask` | `ai_task.gd` (with `ai_task_contract.gd`, its base) | One task: a `Resource` whose exports are the contract below and whose script overrides the virtual methods. `AiTaskContract` holds the enums, the exports and the virtuals (what an author sets and overrides), `AiTask` what the runner drives (time limits, retries, fallback, the watchdog); every task script extends `AiTask`. |
| Composites | `ai_task_sequence.gd`, `ai_task_parallel.gd`, `ai_task_repeat.gd`, `ai_task_selector.gd` (base `ai_task_composite.gd`) | Tasks made of tasks, authored in the inspector (`children`), so a patrol route is data: a `Repeat` of a `Sequence` of walks and waits. A child runs under its own contract. |
| `AiTaskRunner` | `ai_task_runner.gd` (`RefCounted`) | Five layers, highest first REACTION, RESPONSE, ORDER, ROUTINE, DEFAULT, each an ordered queue. The active task is the head of the highest layer whose head `can_run()`; a lower one is suspended, never dropped. Signals `task_started`, `task_finished`, `task_suspended`, `task_resumed`, `task_failed`, `task_refused`, `attacker_pending`. |
| `AiTasks` | `ai_tasks.gd`, a node of `ai_character.tscn` (the character's `task_runner` slot) | Owns one runner: steps it on each of the character's thinks (the `thought` signal), pauses it on `died`, resumes it on `revived`, reports `took_hit`; assigns `default_task` and `routine` at the start; shows the stack on the `TaskLabel` while the character's `debug` is on. |
| `AiNeeds`, `AiNeedRow` | `ai_needs.gd`, `ai_need_row.gd` | The table of needs against orders (research 3.6): for an order id (or `*`) and a need, how badly the need must be felt (0 to 1, from the runner's `beliefs`) before the order gives way to a task that serves it. |
| `AiDecisionLog` | `ai_decision_log.gd` | The last 300 decisions with the beliefs that produced them, written only when something is decided; `dump()` for a failure message. |

### The contract {#contract}

Every field is an export of the task, set in the inspector or in code before `assign`.

| Field | Values | What the runner does |
| --- | --- | --- |
| `layer` | REACTION, RESPONSE, ORDER, ROUTINE, DEFAULT | The queue it goes in; a higher layer takes over at the next step. |
| `channels` | MOVE, ACTION, LOOK, SPEAK (flags) | What the task writes on the `AiController`; the runner lets go of these when the task is suspended or ends (`walk_direction` zero, `aim` and `fire` off, `look_direction` zero). A composite claims its children's. |
| `interruptible` | YES, BY_HIGHER_LAYER, NO, FINISH_THEN_REACT | YES: anything takes over. BY_HIGHER_LAYER: only a higher layer; a same-layer replacement waits behind it. NO and FINISH_THEN_REACT: a higher-layer task assigned meanwhile is deferred and delivered when it ends (unless it `expires_after`); NO also survives `clear()` and `revoke()` unless forced. |
| `when_interrupted` | SUSPEND_RESUME, RESTART, ABORT, SKIP_TO_NEXT | What happens to it when taken off: kept and resumed, kept and started over, or dropped (`CANCELLED`). Inside a sequence, the running child's SKIP_TO_NEXT moves the sequence on and ABORT fails it. |
| `resume_valid_for` | seconds, 0 always | After a longer interruption the task is asked `still_valid()`; false ends it `FAILED(STALE)`. |
| `under_attack` | PROFILE, IGNORE, FINISH_THEN_REACT, FIGHT_BACK_WHILE, ABORT_ABOVE | Only while the task is NO or FINISH_THEN_REACT: nothing; the attacker is answered when it ends (`attacker_pending`, and `attack_task` assigned against it); `attack_task` runs on the ACTION channel beside it (a task that claims ACTION falls back to answering after); or it ends `FAILED(ATTACKED)` once `abort_damage` arrives within `abort_window`. PROFILE reads the profile's `under_attack`. Damage always sets the beliefs `attacker` and `attacked_at`. |
| `timeout`, `hard_timeout` | seconds | `timeout` calls `on_timeout()` once; `hard_timeout` ends it `TIMED_OUT` (-1 the profile's `task_hard_timeout`, 0 never: only with `ends_on_condition`, else a configuration warning). Time counts only while it runs. |
| `on_fail` | SKIP, RETRY, FALLBACK, PROPAGATE | A failure: the next task takes over (a sequence goes on with its next step); `retry_count` more tries after `retry_delay`; `fallback` runs in its place; the parent fails too. A script error (`INVALID`) is never retried. |
| `replace_policy` | MERGE, REPLACE, QUEUE, IGNORE | An arriving task with the same `id` as one in its layer merges into it (`merge(incoming)`: the base takes `target`, `goal`, `issuer`) unless QUEUE; with no equal id: MERGE and REPLACE take the head's place (the head ends `CANCELLED(REPLACED)`), QUEUE goes last, IGNORE drops itself when the layer is busy. A running RESPONSE is not replaced by another response for the profile's `commit_seconds`. |
| `authority` | 0 to 100 (`AUTHORITY_SQUAD` 10, `AUTHORITY_MISSION` 20, `AUTHORITY_SCRIPT` 30) | ORDER only: a higher or equal authority replaces the head (the newer of two equal ones wins), a lower one queues behind every higher one. An order below `(1 - obeys_orders) * 20` is refused (`task_refused`). |
| `need` | a belief name (`&"ammo"`) | A task that serves a need is refused while an order holds unless the `AiNeeds` table says the order gives way at the need's current value. |
| `persistent`, `reactive`, `expires_after`, `ends_on_condition` | | Survives `clear()`; off refuses responses (not reactions) while it runs; dropped `EXPIRED` if not started that many seconds after `assign`; ends on its own, so no hard timeout is fine. |

The runner's own calls: `assign(task, issuer)` (returns the running instance, the task it merged into, or null when
refused), `revoke(issuer, force)`, `clear(layer, force)`, `force_cancel(task)`, `report_damage(amount, source)`,
`set_can_think(bool)`, `describe()` (a dictionary for an overlay or a test) and `describe_text()`, `active_kind()` and
`active_target_id()` (all that replication sends of tasks, #969). A failure budget (the profile's `failure_budget`
failures in `failure_window` seconds, or one script error) stops ORDER and ROUTINE for `fallback_seconds`, so DEFAULT
runs and a failing task cannot storm.

### Every edge case {#edge-cases}

The 13 rows of research 3.3 as built, each with the test that fails on a runner without the rule
(`tests/gameplay/test_ai_task_runner.gd` rows 1 to 6, `test_ai_task_rules.gd` rows 7 to 13).

| # | Case | Rule as built | Test |
| --- | --- | --- | --- |
| 1 | Interrupted by an event | The response preempts; the patrol is suspended (`suspend()`), then resumed (`resume()`) with its own progress | `test_an_interrupted_task_resumes_where_it_was` |
| 2 | Same layer | MERGE, REPLACE, QUEUE, IGNORE as above; 50 identical events make one task | `test_a_same_layer_task_replaces_queues_ignores_or_merges`, `test_fifty_identical_events_make_one_task` |
| 3 | Must complete | Higher layers deferred and delivered after; `clear()` skips it; it still ends at its hard timeout as `TIMED_OUT`; `force_cancel` always wins | `test_a_must_complete_task_defers_events_and_ends_at_its_hard_timeout`, `test_force_cancel_ends_a_must_complete_task` |
| 4 | Attacked while uninterruptible | The four `under_attack` policies | `test_attacked_under_ignore_changes_nothing` and the three after it |
| 5 | Resume after a changed world | `resume()` answers RESUME, RESTART, SUCCEEDED or FAILED (a movement task asks for its path again there and fails `NO_PATH` for a goal now unreachable); `resume_valid_for` and `still_valid()` | `test_resume_after_a_changed_world_follows_the_task_answer`, `test_resume_can_restart_or_finish_the_task`, `test_a_long_interruption_asks_still_valid` |
| 6 | A failure | Each `on_fail`; the failure budget | `test_a_failure_follows_on_fail`, `test_propagate_fails_the_sequence_and_skip_goes_on`, `test_a_failing_task_cannot_storm` (3 starts, not one a step) |
| 7 | Time-outs | Soft once, hard ends it; -1 is the profile's; a task with no limit and no end is a warning (`AiTasks` shows it) | `test_soft_and_hard_timeouts`, `test_a_task_with_no_timeout_and_no_end_is_a_warning` |
| 8 | Orders from other systems | Authority, revoke, refusal by obedience, needs against orders | `test_orders_follow_authority_and_revoke`, `test_a_character_that_obeys_little_refuses_a_low_order`, `test_an_order_gives_way_to_a_need_only_as_the_table_says` |
| 9 | The body cannot act | `set_can_think(false)` suspends the active task with its timers frozen and lets go of its channels; true resumes it | `test_death_pauses_the_runner_and_a_revive_resumes_it`, `test_death_pauses_it_and_a_revive_resumes_it` (the node) |
| 10 | Two reactions at once | A reaction preempts a response and returns; a response wobbling between two ids changes once inside `commit_seconds` | `test_a_wobble_changes_the_response_once_and_a_reaction_preempts` |
| 11 | Assigned while dead | Queued, delivered on revive, dropped `EXPIRED` past `expires_after` | `test_a_task_assigned_while_dead_waits_or_expires` |
| 12 | A script error in a task | The watchdog ends it `FAILED(INVALID)` (no retry), warns with the decision log and starts the fallback, so DEFAULT runs | `test_a_task_that_errors_ends_invalid_and_default_runs` |
| 13 | Idle, and replication | An empty runner returns at once (no work, no decision, no growth of memory or objects); only `active_kind()` and `active_target_id()` leave the machine | `test_an_idle_runner_does_no_work_and_allocates_nothing_per_step`; the replay: `test_a_replay_gives_the_same_decisions` |

### Writing a task {#writing-a-task}

For #968's stock tasks and a game's own: extend `AiTask`, export what an author sets, override what you need.

- `start()` once (and again on a restart); `update(delta) -> Status` each think: RUNNING, SUCCEEDED, or FAILED with
  `reason` set (`NO_PATH`, `TARGET_LOST`, `BLOCKED`, `NO_AMMO`...). `elapsed` is the running time, `goal` and `target`
  what it is about, `character` and `controller` the body and its channels, `runner().beliefs` what the character
  believes, `run_profile()` its profile.
- Write only the `AiController` channels in `channels` (the runner releases them); never the command, never
  `character.gd`. A movement task asks for its path again in `resume()` and answers `Resume.FAILED` with `NO_PATH`
  when the goal is now unreachable.
- `merge(incoming)` takes a newer goal (a chase); `can_run()` false lets the runner pass to the next layer;
  `detail()` names a composite's running step for the overlay; `has_end_condition()` true when it ends on its own.
- Assign from a reaction router, a mission or a squad with `runner.assign(task, issuer)`; listen to `task_finished`
  and read `task.issuer`. A task kept in a file or in a scene is a template: the runner runs a copy (`fresh_copy()`),
  with `target`, `goal` and `issuer` carried over.
- Four traps a task meets in a real body (routing from `update()`, a press in the first think, the commit time, the
  walk's push line): [AI behaviour: writing a task](ai-behaviour.md#writing-a-task).

### What it costs {#task-cost}

`tools/bench/ai_task_bench.tscn` (`ai_task_bench.py` for Chrome) steps 40 and 200 runners, each with a typical stack
(DEFAULT idle, a ROUTINE patrol that repeats a walk and a wait, a RESPONSE investigate every 4 s that suspends it),
every one on every 60 Hz tick (six times the 10 Hz think, so a ceiling), and 200 idle runners. Godot 4.7.2, fast
desktop, web export single-threaded:

| | 40 busy | 200 busy | 200 idle | 40 thinking at 10 Hz, per tick |
| --- | ---: | ---: | ---: | ---: |
| Native, µs a tick (each) | 81 (2.0) | 437 (2.2) | 39 (0.19) | 14 |
| Chrome, µs a tick (each) | 104 (2.6) | 531 (2.7) | 36 (0.18) | 17 |
| Chrome 4x, µs a tick (each) | 657 (16.4) | 2974 (14.9) | 235 (1.2) | 110 |

Inside the AI budget of [Crowds: AI characters](../crowds.md#ai-characters) (1 ms a tick, 5 ms at 4x) even with all
200 stepped every tick; at the 40 characters of the web cap thinking at 10 Hz the tasks add 17 µs a tick (110 µs at
4x), under 2 % of the budget.

- **Approach:** Pick the task again only when something changed (a task came or went, `can_think` or the fallback
  flipped) or a head waits on `can_run()`; a quiet step goes straight to the active task's `advance`, and the hard
  timeout is read inline. **Watch out for:** the first runner chose the task on every step and called a helper per
  check: 4.9 µs a runner natively, more than the spike's whole brain; with the selection skipped and three helpers
  inlined it is 2.2 µs. **Seen:** gdstudio #965, 2026-11-10.
- **Approach:** Prove "nothing runs when empty" with a counter of steps that did work and the decision log's count,
  and check memory and the object count only for what stays. **Watch out for:** a test that compared
  `OS.get_static_memory_usage()` before and after 2000 idle steps passed with a `describe()` in every step: memory
  freed before the step returns does not show; a mutation run (removing the idle return) found the counter is the
  check that fails. **Seen:** gdstudio #965, 2026-11-10.

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

## Proof {#proof}

`tests/gameplay/test_ai_director.gd` (thinks at the rate and on ticks of their own, the ray budget shared and reset, the
think budget, a profile edit while running, tiers with the margin and the cap, the population cap, the rest cadence,
far characters walking as far), `test_ai_situation.gd` (rising, dwell, hysteresis, death) and `test_ai_character.gd`
(the parts, the channels, a hit that kills into the ragdoll, the overlay, the profiles), `test_ai_animation_throttle.gd`
(a Dormant tree does not advance and a Full one near the camera does every frame, Reduced and far periods with the
missed time, an unseen character held and caught up, footsteps only near, a death, `enabled` off and `unregister`
giving the tree back, the player untouched). The tasks:
`test_ai_task_runner.gd` and `test_ai_task_rules.gd` ([every edge case](#edge-cases) and the replay),
`test_ai_task_composites.gd`, `test_ai_tasks_node.gd` (on a real character) and the pins in `test_ai_exports.gd`; their
capture is `tools/capture/ai_tasks_tour.tscn` (a patrol, a noise, the investigate response, the patrol going on from
its leg) and their cost `tools/bench/ai_task_bench.tscn` ([the numbers](#task-cost)). The capture is
`tools/capture/ai_tour.tscn` (the three profiles side by side with the overlay, a grunt killed into its ragdoll) and the
cost is `tools/bench/ai_cost_bench.tscn` with `ai_cost_bench.py` for Chrome ([the numbers](../crowds.md#ai-characters)).
