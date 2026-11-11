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
| `AiAttack` | `engage`, Response, Move, Action and Look | Ranged with the aim model, only at a subject seen now and never through a friend; melee from the weapon's own reach; reloads a dry magazine; `NO_AMMO` with nothing to load. |
| `AiTakeCover` | `cover`, Response, Move, Action and Look | Runs to a cover marker facing the threat (scored, kept) and hides and peeks to shoot; only hides when Safe. |
| `AiFlee` | `flee`, Response, Move | Runs to the reachable point farthest from the threat until `safe_distance`. |
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
  `chance_scale`, `task`, `place`, `enter`, `note`. **`AiReactionWaiver`**: `event`, `bands`, `situations`, `reason`.
  **`AiSituationRule`**: `situation`, `blocks`, `open_layers`.
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
  think 10 times a second (kit #1204).

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
  changed: nothing enforces the count yet (attack slots that only N guards hold at once: kit #1203).

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

Each rule was broken in a made game to see its test fail: the friend-in-line check, firing at a memory (in both the
attack and the aim), the play dwell, the melee approach and the freed noise maker
([AI senses: proof](ai-senses.md#proof)).

The capture is `tools/capture/reactions_tour.tscn` (41 s, from the player's camera with the overlays): a guard's
notice, chase, search and return; cover and peeks; civilians fleeing and a hurt one cowering.
