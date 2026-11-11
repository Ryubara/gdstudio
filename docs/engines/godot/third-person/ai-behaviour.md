# AI behaviour in 3D Third Person

<!-- new section: what makes an AI character act (kit #968: the brain, its router table, play states and the stock
     tasks) is a subject of its own with its own tests, inspector and cost; the AI page was at the page size limit -->

What turns what a character knows into what it does (kit #968; the research for #882, sections 1.4 to 1.6 and 3). The
senses ([AI senses](ai-senses.md)) say what it believes, the task runner ([Tasks](ai.md#tasks)) runs what it is
doing; the **brain** sits between them and has no branch for any behaviour: every answer is a row of a table, and a
new behaviour is a task script and a row. The base, the profile and the director are on [AI characters](ai.md).

## What is in it {#parts}

| Part | Where (in `templates/3d-third-person/game/gameplay/ai/`) | What it does |
| --- | --- | --- |
| `AiBrain` | `behaviour/ai_brain.gd`, the `Brain` node of `ai_character.tscn` (the character's `brain` slot) | Routes each event once through its `behaviour` table, feeds the play state each think, reminds itself of a threat in view every `threat_recheck_seconds`, retries an answer the runner refused inside the commit time, lets barks through past three cooldowns, chooses the target, and takes a script's `order()`. Signals `reacted`, `barked`, `play_state_changed`. Runs only where the senses run. |
| `AiBehaviourSet` | `behaviour/ai_behaviour_set.gd`, `behaviour/sets/hostile_guard.tres`, `friendly_ally.tres`, `civilian.tres` | One kind's table: `rows`, `waivers`, `situation_rules`, `default_task`. |
| `AiReactionRow`, `AiReactionWaiver`, `AiSituationRule` | `behaviour/` | A row of the table; a cell answered with nothing on purpose, with its reason; what one situation blocks and which task layers it keeps open. |
| `AiPlayState` | `behaviour/ai_play_state.gd` | Aggressive, Careful, Safe from the health share less the pressure of hostiles seen, with hysteresis and a dwell. No node, no clock. |
| `AiChoice` | `behaviour/ai_choice.gd` | Utility scoring with a commitment bonus, at exactly three places: the target, the cover spot, the next patrol stop. |
| `AiAttackSlots` | `ai_attack_slots.gd`, the `AiDirector`'s `slots` | At most N guards engage one target and at most a cap engage at all; the rest hold: [Attack slots](#attack-slots). |
| `AiMarker` | `behaviour/ai_marker.gd` | A place that means something to the AI (patrol stop, cover, lookout, spawn, scenario point), placed and tuned in the scene; the tasks find markers through a list the markers keep, never the tree's groups. |
| Stock tasks | `tasks/stock/` (base `AiStockTask`, the aim model `AiAim`) | The 18 tasks the shipped sets answer with: [Stock tasks](#stock-tasks). |
| Scenes | `ai_guard.tscn`, `ai_ally.tscn`, `ai_civilian.tscn` | `ai_character.tscn` with a profile and a set: the grunt and `hostile_guard`, the ally and `friendly_ally`, the civilian and `civilian` (its brain reminds itself up to Unfriendly, so a civilian keeps away from a stranger with a gun too). |

## The router {#router}

The brain routes an event once, when it happens; nothing polls. The events (`AiBehaviourSet.EVENTS`): `spawned`,
`noticed`, `suspicious`, `heard` (the senses' signals), `hit`, `lost_sight` and `lost_trail` (a chase or an attack
failed `TARGET_LOST`), `forgot`, `hurt` (the play state turned Safe with a hostile in view), `no_ammo` (an attack
failed dry), `link` (the navigator stopped at a link it does not cross itself) and the script orders `order_go`,
`order_hold`, `order_use` (`brain.order(event, point, object)`).

For an event about a subject the brain reads the character's band toward it (a subject-less event counts as Neutral),
the situation and the play state, and walks the rows **top down**: the first row whose `event`, `bands`,
`situations`, `play_states`, `min_awareness` and courage range match answers, at its `chance` (scaled by courage,
fear, aggression or curiosity; a failed roll passes the event to the row below). The row places a copy of its `task`
in the task's own layer, with the subject as target and the goal at the event's place, the character's home or its
leader, and may move the situation (`enter`: rising is at once, calming waits the dwell). A situation rule can block an
event outright (an Engaged guard does not turn for a footstep or a glimpse) or close task layers to reactions.

**Every cell is covered.** `test_every_cell_of_every_shipped_set_asks_for_something_or_is_waived` walks every event,
band, situation and play state of the three sets: each cell has a row sure to answer (chance 1, unscaled, any
courage), a block, or a waiver with its reason; a row taken out fails it. A game's own set gets the same test by
adding its file to the list.

**The reminder.** While a hostile at or past `remind_up_to` is seen and the running task does not answer a threat
(`answers_threat` on the stock task), the noticed event is routed again every `threat_recheck_seconds`, so a character
never stands idle with a threat in view: `test_no_shipped_kind_stands_idle_with_a_threat_for_more_than_five_seconds`
holds it over 36 cells, and `test_a_dry_gun_never_stalls_a_guard` over 27 with an empty gun.

**Tasks end, the brain routes.** A task that finds a hostile in view sets `found` and ends; the brain routes on
`task_finished` and `task_failed` (a lost target is `lost_sight`, a dry gun `no_ammo`), never from inside a task's
`update()` ([Writing a task](ai.md#writing-a-task)).

## Play states {#play-states}

`AiPlayState.feed(share, threats, seconds, profile)` each think: the health share less `pressure_per_threat` for each
hostile seen now (at most `max_pressure`). Under the profile's Safe line (`safe_line()`, `flee_below_health` scaled by
`courage`) it plays Safe, under the Careful line (`careful_line()`, `careful_margin` above) Careful, else Aggressive.
Turning more careful is at once; turning bolder needs the share `play_hysteresis` past the line and the state held
`play_dwell` seconds, so a character on the edge changes once. Rows name the play states they answer in: a Careful
guard takes cover and peeks, a Safe one hides and does not roam (a task with `roams` does not run).

## Stock tasks {#stock-tasks}

Each extends `AiStockTask` (an `AiTask`), reads beliefs and never the world, and declares its channels and contract
(`test_each_stock_task_declares_its_channels_and_contract`). `answers_threat` keeps the reminder off it, `roams` keeps
it from running while Safe.

| Task | id, layer, channels | What it does |
| --- | --- | --- |
| `AiWait` | `wait`, any, none | Stands still `seconds`; resumes with the time left. |
| `AiGoTo` | `go_to`, any, Move | Walks to `goal`; `NO_PATH` when the navigator gives it up, asked again on resume. |
| `AiFollow` | `follow`, Routine, Move | Keeps within `band` m of its subject; `TARGET_LOST` when it is gone. |
| `AiPatrol` | `patrol`, Routine, Move | Walks the route's patrol markers, waiting at each; the next stop is scored (longest unvisited less the walk). |
| `AiWander` | `wander`, Routine, Move | Strolls between seeded points within `home_radius`; roams. |
| `AiLookAt` | `look_at`, Response, Look | Turns the look toward its subject or goal for `seconds`; the shipped glance is IGNORE, so it never replaces an investigation. |
| `AiLookAround` | `look_around`, Response, Look | Sweeps the look to each side. |
| `AiInvestigate` | `investigate`, Response, Move and Look | Goes to look at a place, then looks around; a newer noise merges into it. |
| `AiSearch` | `search`, Response, Move and Look | Visits seeded spots around where the subject was last believed, then ends (`lost_trail`). |
| `AiChase` | `chase`, Response, Move and Look | Runs to where a lost subject is believed; ends when a hostile is in view again. |
| `AiAttack` | `engage`, Response, Move, Action and Look | Ranged with the aim model, only at a subject seen now and never through a friend; melee from the weapon's own blow reach (its category's) by pressing the melee button, as a player does ([melee](shooting.md#melee)); reloads a dry magazine; `NO_AMMO` with nothing to load. Fights only with an [attack slot](#attack-slots); without one it holds, gun down, watching (`held`). |
| `AiTakeCover` | `cover`, Response, Move, Action and Look | Runs to a cover marker facing the threat (scored, kept) and hides and peeks to shoot; only hides when Safe. A peek takes an [attack slot](#attack-slots) and gives it back when it goes down; without one it stays down. |
| `AiFlee` | `flee`, Response, Move | Runs to the reachable point farthest from the threat until `safe_distance`; with nowhere to run it fails `NO_PATH` and the civilian rows' fallback, a cower, runs in its place (during a failure storm too). |
| `AiCower` | `cower`, Response, Move and Look | Crouches facing the threat until it has not been believed for `panic_recovery_seconds`. |
| `AiGuard` | `guard`, Default, Move and Look | Holds a place, looks around while there; the guard's default and `order_hold`. |
| `AiUseObject` | `use`, Order, Move and Action | Walks up to an `Interactable` and presses use, as a player does. |
| `AiTraverseLink` | `traverse_link`, Reaction, Move | Crosses a navigation link the navigator stopped at, with a jump over a gap. |
| `AiSay` | `say`, Response, Speak | A bark through the brain's cooldowns; ends at once. |

**The aim** (`AiAim`, shared by Attack and TakeCover): no shot sooner than the 0.2 s reaction floor after starting on a
target, a turn no faster than `aim_speed`, tracking noise that shrinks while on target, bursts of `burst_size` at
`fire_interval`, and no shot at a memory or through a friend (`AiSenses.friend_in_line_of_fire()`).

## The inspector {#inspector}

- **`AiBrain`** (the `Brain` node): `behaviour` (empty on `ai_character.tscn`: the brain does nothing), `leader`,
  `patrol_route`, `home_radius` 6 m, `random_seed` 0 (from the name); Threats `threat_recheck_seconds` 1 s,
  `target_bonus` 0.3, `remind_up_to` Hostile (Unfriendly on the civilian), `retry_seconds` 1 s; Barks `line_cooldown`
  8 s, `any_line_cooldown` 2.5 s, `crowd_cooldown` 1.5 s; Network `authority_only` on. With the character's `debug`,
  the overlay adds the set, the play state, the last event and its answer.
- **`AiProfile`** Play states: `careful_margin` 0.3, `pressure_per_threat` 0.1, `max_pressure` 0.3,
  `play_hysteresis` 0.08, `play_dwell` 2 s.
- **`AiBehaviourSet`**: `display_name`, `rows`, `waivers`, `situation_rules`, `default_task`. **`AiReactionRow`**:
  `event`, `bands`, `situations`, `play_states`, `min_awareness`, `min_courage`, `max_courage`, `chance`,
  `chance_scale`, `noises` (the noise kinds a `heard` row answers; empty: any), `task`, `place`, `enter`, `note`.
  **`AiReactionWaiver`**: `event`, `bands`, `situations`, `reason`. **`AiSituationRule`**: `situation`, `blocks`,
  `open_layers`.
- **`AiMarker`**: `kind`, `route`, `wait_seconds` 2 s, `enabled`.
- Each stock task's numbers are its exports (group Stock: `answers_threat`, `roams`; then its own, documented on
  the script). The brain's and the profile's are pinned by `test_ai_exports.gd`, each task's channels and contract by
  `test_each_stock_task_declares_its_channels_and_contract`.

## Writing a task for a real body {#writing-a-task}

What the stock tasks met once they ran in a body that moves, beside [Writing a task](ai.md#writing-a-task).

- **Approach:** End a task that finds something new (`found = true`, then SUCCEEDED or FAILED) and let the brain route
  on `task_finished` or `task_failed`. **Watch out for:** routing an event from inside a task's `update()` places the
  answer at once and replaces the running task under the runner's feet: `active` was null when `update()` returned.
  **Seen:** gdstudio #968, 2026-11-11.
- **Approach:** Hold a press the task sets in `start()` (`controller.unarmed`, `reload`, `interact`) for one whole
  think and let go of it in a later `update()`. **Watch out for:** `start()` and the first `update()` run in the same
  advance, so a press set in one and cleared in the other never reached a command and the body never drew its fists.
  **Seen:** gdstudio #968, 2026-11-11.
- **Approach:** Have the brain retry an answer the runner refused, for `retry_seconds`, instead of trusting that a
  placed row is a placed task. **Watch out for:** a response arriving inside another response's `commit_seconds` is
  refused silently, so a civilian's noticed answer was lost behind a glance placed a moment earlier. **Seen:** gdstudio
  #968, 2026-11-11.
- **Approach:** Give a brief task that may arrive beside a longer one (a glance) `replace_policy` IGNORE. **Watch out
  for:** a glance with MERGE replaced an investigation placed in the same think (heard, then suspicious), and the guard
  only looked. **Seen:** gdstudio #968, 2026-11-11.
- **Approach:** Ask a walk for a push just over the body's `walk_below_push` (`AiStockTask.PUSH_MARGIN`, 0.02).
  **Watch out for:** a push under the line walks at `least_walk_share` whatever its size, and the command's byte rounds
  a push of 0.45 down under it: the "slow walk" ran at 0.85 m/s ([the controller](character.md#controller)).
  **Seen:** gdstudio #968, 2026-11-11.

## What it costs {#cost}

`tools/bench/ai_behaviour_bench.tscn` (`ai_behaviour_bench.py` for Chrome) times the `AiDirector`'s step (the thinks
with senses, brain and tasks, and every body's step) for `ai_guard.tscn` on a 3 m grid around two targets walking a
6 m circle, all inside the Full range, with the shipped Full cap (12 in a browser, 60 on the desktop) and the
animation throttle. Three modes: brains **off** (the `Brain` node taken out: senses and an empty runner), **calm**
(brains on, the targets of the guards' own faction: the default `Guard` task and nothing to answer) and **threat**
(the targets hostile: the guards notice, fight, chase and search). Godot 4.7.2, Compatibility, Jolt, web export
single-threaded, Chrome on the fast desktop shared with other agents. Microseconds of the director's step a tick
(mean; in brackets the median frame work in ms, then ticks a frame):

| Director's step | 50 off | 50 calm | 50 threat | 100 off | 100 calm | 100 threat |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Desktop, native (Full cap 60), two runs | 610 to 630 (1.5) | 705 to 765 (1.6) | 2845 to 3146 (4.4) | 1204 to 1416 (3.2) | 1630 to 1730 (3.6) | 3694 to 4161 (6.3) |
| Chrome (Full cap 12) | 1144 (2.6) | 1084 (2.2) | **2526** (3.9) | 1590 (3.7) | 1860 (4.0) | **3622** (6.5) |
| Chrome 4x | 5617 (13.8 / 1.5) | 5603 (12.4 / 1.3) | **16034** (82 / 5.9) | 14251 (110 / 6.7) | 10676 (58 / 4.8) | 21080 (205 / 8.0) |

At the web cap, 40 guards in Chrome: off 828 µs (1.8 ms), calm 837 (1.6), threat **2093** (3.2); at 4x 6368 (12.4 /
1.6 ticks a frame), calm 7948 (a busy minute: the calibration loop read 109 ms against 42 to 50), threat **10489**
(38.9 / 3.2).

- **The brain itself is cheap.** Calm brains add nothing measurable in Chrome at 50 and 0.27 ms at 100; natively
  about 10 µs a think for the brain and 3 µs for the guard's task (below).
- **A fight costs what the body does, not the brain.** Against a threat the step is 2.2 to 2.3 times the calm one in
  Chrome (+1.4 ms at 50, +1.8 ms at 100). Natively at 50 (all at Full), timed by part per tick: bodies 1.76 ms against
  0.34 calm (46 body steps a tick against 17: a guard that aims and fires is never at rest, `rest_step_ticks` no longer
  spreads it, and it takes the full tick, not the lean one), senses 0.53 ms against 0.13 (rays at targets in view),
  the attack task 0.36 ms against 0.05, the brain 0.13 ms against 0.09, the navigator 0.04 ms.
- **The budget.** Before kit #1104, 40 fighting guards in Chrome were twice the 1 ms AI budget of [Crowds: AI
  characters](../crowds.md#ai-characters), 50 were 2.5 times it, and at 4x both were past the tick (3.2 and 5.9 ticks
  a frame: the catch-up spiral). Natively (the desktop and a server) 50 fighting at Full are about 3 ms a tick and 100
  about 4 ms. What #1104 changed and the web count it sets: [the follow-up](#cost-follow-up).

### The follow-up {#cost-follow-up}

Kit #1104 measured the fight by part, cut the body's share and set the web count of fighting guards from the table.

**Where a fight goes.** The same bench with each part timed in a throwaway copy of the made game, 40 guards against
the two targets, 12 at Full and the rest stepped every 4th tick (the browser's defaults), microseconds a tick:

| Part, 40 fighting | Native, before | Native, after | Chrome, before | Chrome, after |
| --- | ---: | ---: | ---: | ---: |
| bodies (17 to 19 steps a tick) | 935 to 1210 (full tick) | 555 (lean) | 1089 (full) | 797 (lean) |
| senses (look, listen, settle) | 310 to 370 | 220 | 369 | 330 |
| tasks (the attack: aim 75, of which the friend-in-line check 33) | 200 to 220 | 147 | 206 | 189 |
| brain | 70 to 155 | 52 | 97 | 93 |
| the controller's command, the navigator | 105 to 120 | 65 | 125 | 110 |
| **the director's step** | **1850 to 2370** | **1180** | **2160** | **1720** |

- A guard that aims and fires took the full tick on every step (61 to 69 µs natively, 63 in Chrome): the prone stance,
  the vault's probe, the slide, the crouch and the aim's own update ran for nothing, the step climber's `test_move`
  every tick. Since #1104 the lean tick takes the aim and the trigger too
  ([the body's modules](character.md#controller)): only the tick the aim goes up or comes down is full. A fighting body
  is 30 µs natively and 43 µs in Chrome on the lean tick, against 23 µs for a walker: the shot (a pull is about
  200 µs in Chrome, 0.27 a tick for 40) and the turn to the aim every tick.
- Standing aimers stepped less often would not have helped here: in this fight every engaged guard keeps its range
  and is never still. The noise board's friendly shots, skipped from a faction index kept on the record, saved under
  10 % of the listen (64 against 70 µs a tick natively) and were left out.
- What is left is the think: a think of a fighting guard is 75 to 150 µs natively (2 to 3 times a calm one: the look
  with targets in view, the listen over every shot and step since the last think, the attack's aim), and 12 at Full
  think 10 times a second ([the think](#cost-think), kit #1204).

**Before and after**, the director's step in Chrome (ms a tick, three interleaved runs of a build of `main` and of the
change at 1x, two at 4x, with the frame's work and ticks a frame at 4x; rows of at least 600 ticks):

| Fighting guards | 1x before | 1x after | 4x before | 4x after |
| --- | ---: | ---: | ---: | ---: |
| 6 | | 0.50, 0.66 | | 4.8, 5.0 (work 5.4 to 6.2 / 0.5) |
| 12 | | 0.81, 0.96 | | 6.8, 11.6 (work 8.1 to 9.6 / 0.6 to 1.6) |
| 20 | 1.24 to 1.97 (mean 1.59) | 1.16 to 1.22 (1.19) | 11.1 (14 to 30 / 2.4 to 3.2) | 7.1 to 10.4 (7.8 to 10.8 / 0.6 to 1.2) |
| 30 | 1.37 to 2.19 (1.74) | 1.30 to 1.64 (1.49) | 10.6 to 13.4 (35 to 93 / 3.1 to 6.2) | 7.5 to 11.6 (10 to 34 / 0.9 to 3.3) |
| 40 | 1.57 to 2.41 (2.04) | 1.60 to 1.88 (1.75) | 7.9 to 11.6 (12 to 48 / 1.4 to 4.0) | 10.5 to 11.7 (22 to 55 / 2.1 to 4.3) |

- The step is 14 to 25 % shorter at 1x; at 4x the change takes 20 fighting guards out of the catch-up spiral (0.6 to
  1.2 ticks a frame against 2.4 to 3.2) but not 30 or 40, and a run at 4x moves by a third between sessions.
- **The web count of fighting guards: 12** (all at the Full tier) fit the 1 ms budget at 1x (0.81 to 0.96 ms), and
  **6** fit the 4x budget (4.8 to 5.0 ms, half a tick a frame). 20 or more fighting at once are over the budget in a
  browser at any speed: a level made for the web keeps a fight to 12 hostile guards engaged at once (6 for a weak
  machine), and may hold more around it calm (40 calm guards are 0.8 ms). The director's population caps are not
  changed: since kit #1203 the [attack slots](#attack-slots) hold a fight to that count.

- **Approach:** Bench reactions in three modes (brains off, on with nothing to answer, on against a threat) and time
  the step by part (senses, brain, tasks, navigator, bodies) in a throwaway copy of the made game before naming a
  cause. **Watch out for:** the first calm run read 3.8 ms against 0.6 off and looked like a slow brain; the
  calibration loop read 23 ms against 11 (a busy machine), and the timed parts showed the brain at 10 µs a think and
  a fight's cost in the bodies that stop resting. **Seen:** gdstudio #968, 2026-11-11; gdstudio #1104, 2026-11-11
  (the parts named the full tick of aiming bodies; a timed copy exported to the web read the same parts in Chrome).
- **Approach:** Measure a browser bench row by its ticks, not its frames, and compare two builds only on rows of
  several hundred ticks, interleaved in one session. **Watch out for:** a headless Chrome page draws about three frames
  a tick at 1x, so the bench's 300 frames held 90 ticks (15 thinks a guard): the lean fight tick that halved the step
  natively read 1.91 to 1.94 ms against 1.70 to 1.85 before in Chrome, and only rows of 600 ticks or more showed the
  20 % it saves there. **Seen:** gdstudio #1104, 2026-11-11 (the bench now measures at least 600 ticks a row).

### The think {#cost-think}

<!-- new section: the follow-up left the think as the larger half of a fight; nothing held what its parts cost
after #1104 or which ideas measured -->

Kit #1204 timed the think of the 40 fighting guards by part (the same bench, 12 at Full, a timed copy of a made game,
rows of 1200 ticks; natively three interleaved runs of each build, in Chrome four at 1x and two at 4x), and kept only
what measured. Microseconds a tick, mean of the runs (range):

**The timed copy**, so the rows can be measured again: make a game to keep (`gds template game 3d-third-person`, or
`gds template bench-web 3d-third-person ai_behaviour_bench` without `--run` for Chrome) and patch its AI scripts, never
the template's, with spans that add into one static table: `static var prof := {}` and
`static func add(key, usec)` on `AiDirector`, then `var t0 := Time.get_ticks_usec()` ... `AiDirector.add("think",
Time.get_ticks_usec() - t0)` around `_think` and `_step` in the director's step, around `sense`, the brain's `think` and
`thought.emit` in `AiCharacter`, and around the look, listen and settle in `AiSenses` and the aim, trigger and friend
check in the stock tasks; count what they walk the same way (`n_noises`, `n_friend_calls`). The bench clears the table
before a row and prints each key divided by the row's ticks. Run each build natively as `--headless --fixed-fps 60
--path <game> res://tools/bench/ai_behaviour_bench.tscn -- --counts=40 --full=12 --modes=threat`, builds in turns, and
export the same copy to the web for Chrome. Kit #1204 did it with a patch script, `prof_apply.py`, kept with its probes
in that task's scratch folder; the made game it ran on is gone, so this paragraph is the recipe.

| Part, 40 fighting | Native before | Native after | Chrome before | Chrome after | Chrome 4x before | 4x after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| the look (its rays) | 79 (16) | 72 (16) | 99 (21) | 93 (22) | 559 (124) | 521 (126) |
| the listen | 52 | 42 | 61 | 49 | 315 | 261 |
| the settle | 23 | 24 | 30 | 32 | 146 | 148 |
| **senses** | **170** | **154** | **216** | **201** | **1140** | **1054** |
| the aim (the trigger; the friend-in-line check) | 64 (50; 29) | 61 (47; 26) | 82 (62; 38) | 74 (55; 31) | 445 (334; 204) | 425 (311; 173) |
| tasks | 108 | 105 | 133 | 125 | 722 | 697 |
| brain | 46 | 47 | 57 | 56 | 275 | 275 |
| **the thinks** | **338 (327 to 347)** | **322 (319 to 324)** | **427 (416 to 446)** | **401 (391 to 413)** | **2260** | **2147** |
| bodies | 485 | 488 | 608 | 620 | 3499 | 3539 |
| the director's step | 885 (860 to 904) | 872 (867 to 876) | 1123 (1102 to 1169) | 1111 (1081 to 1153) | 6295 | 6234 |

- **Kept:** the noise board files each noise under its maker's faction (`AiNoise.by_faction`), so a listen walks only
  the factions it cares about: 20 % of the listen (the friends' shots and steps; what is left is hearing the impacts,
  "something", which the brain routes); the look's `Rates` made once per senses, not once a think: 6 % of the look;
  `get_global_position()` for `global_position` in the look's and the friend check's loops: 19 % of the friend check
  in Chrome (a microbench of the check over 40 friends: 10.7 against 9.6 µs a call).
- **Dropped:** a flat box around the line of fire before the friend check's arithmetic (no gain: in a crowd around the
  target most friends stand inside the box, and the cost is the loop over each body, not the arithmetic); a settle and
  `AiBeliefs.expire` that make no array (no gain natively or in Chrome); the trigger reading the magazine once (no
  gain). A cheaper aim between shots was not tried apart: between shots the aim only turns, adds the noise and holds
  (5 µs a call natively), and its random numbers must stay in step.
- The thinks are 6 % shorter in Chrome (5 % at 4x, 5 % natively); the director's step is lower in 3 of 4 interleaved
  pairs at 1x and both at 4x, by 1 % on the mean: the bodies (more than half the step) moved more between runs than
  the thinks saved. The behaviour is the same: a digest of every guard's position to the centimetre, its beliefs and
  its shots after 1320 ticks is equal for both builds.

- **Approach:** Time a part's pieces and count what it walks (noises read, friends checked, calls a tick) before
  choosing a fix, try each idea in interleaved runs of the timed copy, and keep only what moves its part; prove the
  behaviour unchanged with a digest of the crowd's state (positions, beliefs, shots) equal for both builds.
  **Watch out for:** a box around the line of fire looked like it would skip most of the friend check and saved
  nothing (most friends stood inside it), and a counter placed one block deeper in the old listen than the new read
  as a guard hearing twice as much. **Seen:** gdstudio #1204, 2026-11-11.

## Attack slots {#attack-slots}

<!-- new section: the cost follow-up set a web count of fighting guards from the table; nothing in the template held a
     fight to it, and how a guard waits for its turn, when a slot frees and what it saves is a subject of its own -->

The director holds one `AiAttackSlots` (`slots`, kit #1203): at most `web_attack_slots` (6) guards engage one target
at once and at most `web_fight_cap` (12) engage at all in a browser, `desktop_attack_slots` (16) and
`desktop_fight_cap` (48) on the desktop and a server ([the inspector](ai.md#inspector)); the web counts are the
[follow-up's](#cost-follow-up) 6 that fit the 4x budget a target and 12 that fit the 1 ms budget in all.

- **Who fires.** `AiAttack` asks for a slot on its subject at each think before it aims (`AiStockTask.take_slot()`);
  `AiTakeCover` asks at each peek. The first to ask when one is free takes it; asking again keeps it.
- **The Full tier goes to the fight.** At the Full cap a holder takes the place of a Full guard without a slot, nearer
  or not, so the guards that fight think at 10 Hz and step every tick and the ones that wait think at the Reduced
  rate. Without it, 11 of the 12 Full places went to guards that waited, and the 12 holders aimed on a 2 Hz think.
- **Who waits.** A guard without a slot holds: it stands, its gun down (no aim, no trigger), looking at the subject,
  and asks again each think; its overlay reads `engage held`. Its body is at rest, so the director steps it every
  `rest_step_ticks`, and its task answers the threat (`answers_threat`), so the reminder does not route it elsewhere.
  A peek with no slot stays down.
- **When a slot frees.** Its holder gives it back when the engage task ends (the subject dead or lost, a dry gun), is
  suspended or dropped, when the subject is not seen now (at once, before `lose_after`), when a peek goes down, and
  when the character leaves the director. A holder that is gone or dead, or has not asked for `slot_lease_seconds`, is
  pruned as soon as a slot is wanted and none is free.
- **The network.** Only the authority runs the tasks, so only the server holds the slots; nothing about them is sent.
  A client sees a held guard as one that does not aim.

**What it saves**, `ai_behaviour_bench.py` in Chrome, 40 guards against the two targets: the web defaults (`threat`)
against the same fight with every guard allowed to fire (`uncapped`, the slots and the fight cap set to the count), the
director's step in ms a tick:

| Mode, 40 guards | engaged | 1x, run 1 | 1x, run 2 | 4x, run 1 | 4x, run 2 |
| --- | ---: | ---: | ---: | ---: | ---: |
| calm | 0 | 0.54 | 0.64 | 4.00 | 3.72 |
| threat (6 a target, 12 in all) | 11.4 to 11.9 | 1.02 | 1.26 | 5.82 | 8.20 |
| uncapped | 32.9 to 39.5 | 1.14 | 1.20 | 6.60 | 7.42 |
| slots 4, cap 8 | 8 | 1.09 | 1.09 | 6.31 | 6.97 |
| slots 3, cap 6 | 6 | 0.99 | 1.00 | 5.89 | 5.74 |

The cap holds every engaged count to its limit, but what a slot saves (the aim and the trigger) is small next to the
40 bodies and their thinks: uncapped costs about 0.1 ms more than the defaults at 1x, and the 4x runs move more
between runs (5.8 to 8.2 ms for the defaults) than between modes. The web defaults stay 6 and 12; a lower cap saves no
clear amount and thins the fight. The slots are for how a fight reads (a few guards fire, the rest wait their turn)
as much as for its cost.

## Proof {#proof}

`tests/gameplay/test_ai_reactions.gd` plays the scenarios in an arena with a body that moves: a guard notices,
chases, loses, searches and goes back to its patrol; an ally follows its player and fights an enemy that appears; a
civilian flees by courage and one with none cowers; a careful guard takes cover and peeks; low health plays Safe and
does not roam; a melee swing hits a target 1.4 m away; no shot at a remembered entity or through a friend; a repeated
sighting does not stack tasks; a script order beats the routine but not a reaction; a hit from behind turns a guard; an
ally hit by its player complains and never fights. `test_ai_reaction_rules.gd` (noises, barks, the aim's floor and
turn, the reload, the overlay, a remote client routes nothing, the patrol and the two scored choices),
`test_ai_behaviour_sets.gd` (coverage, first row wins, chance, blocks, the brain's source has no behaviour branch),
`test_ai_play_state.gd`, `test_ai_reaction_tables.gd` and `test_ai_stock_tasks.gd` (one per task).
`test_ai_attack_slots.gd`: 20 guards on an arc against one target never have more than 4 (the test's count)
aiming or firing at one tick, the rest hold with their guns down, and a slot freed by a death, a loss of
sight and the end of the engage task is taken by a waiting guard; it failed on `main` (20 aimed at once).
`test_ai_cornered_civilian.gd`: a civilian penned by walls, its failure budget spent by a walk out of the pen, a
hostile beside it firing every second, cowers within 2 s and never stands up for half a second in 16 s; it failed on
`main` (never cowered: each flee failed `NO_PATH` and its cower was skipped, kit #1246).

Each rule was broken in a made game to see its test fail: the friend-in-line check, firing at a memory (in both the
attack and the aim), the play dwell, the melee approach and the freed noise maker
([AI senses: proof](ai-senses.md#proof)).

The capture is `tools/capture/reactions_tour.tscn` (41 s, from the player's camera with the overlays): a guard's
notice, chase, search and return; cover and peeks; civilians fleeing and a hurt one cowering.
`tools/capture/attack_slots_tour.tscn` (16 s): eight guards on an arc, three slots, five holding; one firing guard dies
at 8 s and a held one takes its place.
