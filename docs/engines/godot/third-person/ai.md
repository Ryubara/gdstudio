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
  `senses`, `navigator` (empty until #966 and #967 fill them), `task_runner` (the `AiTasks` node of
  `ai_character.tscn`, [Tasks](#tasks)). Everything `Character` has
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
  Tasks (#965): `under_attack` FINISH_THEN_REACT, `task_hard_timeout` 30 s, `failure_budget` 3, `failure_window`
  10 s, `fallback_seconds` 5 s, `commit_seconds` 0.5 s.
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

## Proof {#proof}

`tests/gameplay/test_ai_director.gd` (thinks at the rate and on ticks of their own, the ray budget shared and reset, the
think budget, a profile edit while running, tiers with the margin and the cap, the population cap, the rest cadence,
far characters walking as far), `test_ai_situation.gd` (rising, dwell, hysteresis, death) and `test_ai_character.gd`
(the parts, the channels, a hit that kills into the ragdoll, the overlay, the profiles). The tasks:
`test_ai_task_runner.gd` and `test_ai_task_rules.gd` ([every edge case](#edge-cases) and the replay),
`test_ai_task_composites.gd`, `test_ai_tasks_node.gd` (on a real character) and the pins in `test_ai_exports.gd`; their
capture is `tools/capture/ai_tasks_tour.tscn` (a patrol, a noise, the investigate response, the patrol going on from
its leg) and their cost `tools/bench/ai_task_bench.tscn` ([the numbers](#task-cost)). The capture is
`tools/capture/ai_tour.tscn` (the three profiles side by side with the overlay, a grunt killed into its ragdoll) and the
cost is `tools/bench/ai_cost_bench.tscn` with `ai_cost_bench.py` for Chrome ([the numbers](../crowds.md#ai-characters)).
