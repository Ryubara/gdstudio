# Bots: players the game plays itself

<!-- new section: design.md#bot-teammates says whether a game needs bots and what orders they take; nothing held how
a bot that plays like a person is built, fitted to the balance model and soaked -->

A bot plays through the same door a person does: it hears what a client hears, sends a person's command, walks with a
body and buys at the same counters. These rules come from Deadnight's teammate bots and autopilot (the game's
`docs/research/bots.md` has their numbers). Whether a game needs bots at all, and the orders a player gives them, is in
[Designing from a reference](design.md#bot-teammates); a bot's command and the view rules it obeys are in
[The player's controller](controller.md); how the navigation server answers a bot is in
[Navigation in tests](../engines/godot/navigation-in-tests.md) and
[One navigation map for two kinds of walkers](../engines/godot/navigation-layers.md).

## What a bot knows {#perception}

A bot believes what its senses give it, through the events and the frame a client receives and after a reaction delay,
never the server's state. A rule that reads more than a person could know plays a different game.

- **Approach:** Notice a threat by every sense a person has: a dead swinging within arm's reach is known whichever way
  the bot faces, and the attackers on a bot are the larger of those it sees and those it hears close. Test a perception
  rule with a zombie that hits the bot from behind or leaves the view while hitting. **Watch out for:** a contact
  inside its reaction delay was erased whenever its zombie left the view cone, so a bot facing a revive or a choke never
  believed in the dead at its back: it held a revive under blows, and stood among three attackers with loaded guns for
  the rest of a night. **Seen:** Deadnight #229, 2026-11-02; Deadnight #695, 2026-11-03 (fix: heard contacts count and
  a swing in arm's reach is noticed at once; perception tests with the zombie behind, and controls).
- **Approach:** Give a bot only what a person's client is told, and every cue a person sees on the screen (an outline
  through walls, a marker) as a belief too; read the list of events a bot drops before widening it. **Watch out for:**
  a hit-marker event carries the zombie's health left, which no player is shown, and was nearly given to the bots for a
  "finish the wounded one" term; the last dead were outlined through walls for people only, so bots roamed 40 to 100 m
  away while two bosses kited a person with a dry gun. **Seen:** Deadnight (bots, phase 3), 2026-11-02; Deadnight #770,
  2026-11-03 (fix: the event was reverted before use, caught by the dropped-events test; bots read the marks a person
  sees).
- **Approach:** When a test or a capture sets state by calling the rules directly, hand the bots the event the next
  server step would carry, set anything a later event refills (a round start) after that event, and first assert that
  the bot's belief holds the new value. **Watch out for:** a bot hears only what a server step delivers, so bots never
  heard a round start or a grenade count of 0 set by a direct call, and a capture that emptied a bot's grenades before
  the round began got them back from the round-start refill and threw. **Seen:** Deadnight #577, 2026-11-02; Deadnight
  (bots, phase 3), 2026-11-02; Deadnight #646, 2026-11-03 (fix: `SeatedNight.start_round` hands the rules' answer to
  the bot host).
- **Approach:** Order a bot's look cheapest first (distance, then a dot product against the view), ask the costly
  question (is it lit, a ray) of the nearest few only, and measure a think at the largest crowd the rules allow, not at
  the crowd a soak happens to have. **Watch out for:** the first look asked the lamp list about every zombie before the
  cheap tests: 50 us a think with 3 zombies in a soak, 4.4 to 6.1 ms at the 99th percentile with 46, against a 0.5 ms
  budget. **Seen:** Deadnight #225, 2026-11-02 (fix: cheap tests first, 0.29 ms; the cost test runs at the alive cap).

## Choosing what to do {#decisions}

- **Approach:** Keep a choice once made: an errand whose want depends on where the bot stands keeps its target until it
  is done or a deadline passes, a chooser of "the nearest" keeps a heading with credit and counts walk length and
  height, and every goal is a place the bot asked the walk about. Test with the bot midway between two equal choices,
  and with the goal where the walk ends the want. **Watch out for:** a bot flipped between a breaker whose walk ended
  its want and a purchase; one paced a landing between two sellers of one weapon by flat metres; a flank place re-picked
  every think took turns with another. **Seen:** Deadnight #706, 2026-11-03; Deadnight #821, 2026-11-03; Deadnight
  #953, 2026-11-04 (fix: kept ids, `nearest_by_walk`, places from `BotPath.probe`).
- **Approach:** Test a bot's weapon and shopping choices over the whole product of their inputs (magazine empty or not,
  rounds in reserve or not, in hand and in the pocket, points above or below each price) and assert that every cell
  asks for something: a shot, a reload, a swap, a blow, a step or a purchase. Test a new rule on a weapon (a minimum
  range, a refusal inside its splash) with a zombie at the dead's own reach. **Watch out for:** gaps between branches
  left bots standing for minutes: a dry gun with rounds only in the pocketed gun, a broke bot offered no rounds it could
  pay for, a loaded ray gun that would not fire at a zombie 1.4 m away. **Seen:** Deadnight #231, #695, 2026-11-03;
  Deadnight #1319, #1346, 2026-11-06 (fix: table tests that fail on `main`; the soak's idle samples found each).
- **Approach:** Give every rule that makes a bot wait for or yield to a person a time limit, counted per target, and a
  test that runs past it; a boss is never one person's. **Watch out for:** kill courtesy left a zombie to a person
  aiming at it with no end, so a person aiming with a dry gun, or at a boss that takes many seconds to kill, held the
  bots' fire for 5 to 12 s. **Seen:** Deadnight #769, 2026-11-03; Deadnight #770, 2026-11-03 (fix: a 3 s courtesy per
  zombie; the idle sample carries the target and the courtesy answer).
- **Approach:** Let a team job (a door, a link) be claimed by the nearest bot that is free right now, outside any
  rotating turn or one-errand lock, and pick its stand by walking cost. **Watch out for:** a door's rotating turn and
  the team's one-errand slice each named one bot, often busy in a fight, and no other bot could act, so four bots held
  thousands of points while a stair one bot alone bought by round 6 was never bought. **Seen:** Deadnight #696,
  2026-11-03 (fix: a claim by distance among the free; a four-bot soak over five seeds gates every link by round 3).
- **Approach:** Before a bot rule says "go to X", ask the navigation server whether X is reachable with the doors as
  they are now, remember a stand with no way to it until a door opens, read every phase length from the tuning (never
  a design page), and run the rule in a soak before trusting its unit tests. **Watch out for:** shop spots behind shut
  doors were picked as nearest, marked unreachable for 5 s and picked again; the break the shopping waited for was 5 s,
  not the page's 20; a rule that waited for a round to clear waited on stragglers nobody went for. **Seen:** Deadnight
  #228, 2026-11-02 (fix: stands kept as unreachable until the mesh changes; a lull counts as a break).

## Walking {#movement}

- **Approach:** Pass a path point once the bot is nearer the next point than the point is, measure progress as the
  path left to walk with a grace after a sharp turn, and end a stuck episode only after net progress; test the detector
  with traces of a U-turn and of a shuffle. **Watch out for:** a bot that ran past a corner at 0.6 m turned back for
  it; progress along a new heading called a sprinting bot that swung round stuck, while a bot sidestepping along a
  wall showed progress in every half-second window and was never stuck. **Seen:** Deadnight #226, 2026-11-02 (fix:
  `BotPath._advance` and the stuck rules, with unit tests fed those traces).
- **Approach:** Gate a soak on "standing with a goal" as well as on stuck, since a stuck detector judges only a bot that
  is told to walk; a recovery that moves a goal proves the moved goal is still reachable, and a bot with no goal for no
  visible reason prints the path query's own answer (points, end, layer). **Watch out for:** a path that stopped 2 m
  short left a bot "arrived" for 92 s; a ladder's nudged goal behind boards ended the walk and the episode; a bot on a
  mesh piece joined to nothing banned every place for ten minutes. **Seen:** Deadnight #770, 2026-11-03; Deadnight
  #1041, 2026-11-04; Deadnight #1325, 2026-11-06 (fix: `stopped_short_of`, the nudge taken back, refusals undone).
- **Approach:** When a bot's idea of the world (the mesh, its sight rays) comes from one source and its body is stopped
  by another (a players-only layer, a gate, boards), check a new path as the body would walk it and test a goal where
  the two disagree. **Watch out for:** the walking mesh ran through each breach into the dead's pocket and the boards
  were on a layer the bot's sight ray did not see, so a goal past the fence was "on the mesh" and the bot stood against
  the boards for up to 11 s. **Seen:** Deadnight #677, 2026-11-03 (fix: a ray along each segment with walls and
  boards; a probe of every pocket fails on `main`).
- **Approach:** Give the bots of one team slots by seat and a meeting rule (who gives way, to which side), and classify
  each stuck episode by what the body ran into before tuning. **Watch out for:** players are solid to each other, every
  bot chased the same person down the same corridors, and pushing every neighbour away made two bots step the same
  way: stuck 6 to 16% of walking time, nearly all against another player. **Seen:** Deadnight #226, 2026-11-02 (fix: a
  fan of slots, a look-ahead in which a person never gives way, a standing bot steps aside; stuck 1 to 3%).
- **Approach:** Test a pull added to a weighted sum of pushes against the biggest push it will meet (a crowd, not one
  zombie), and scale its weight with that sum. **Watch out for:** a Follow bot's pull toward its person was a flat 0.9
  against eight zombies' pushes summing to 10 to 30, so a retreating bot ran 30 to 90 m away whenever the pack stood
  between. **Seen:** Deadnight #784, 2026-11-03 (fix: the pull grows with distance and with each dead felt; a steering
  test puts eight dead between the bot and a person 30 m off).
- **Approach:** Give a rule that runs before every goal (a flight from the nearest zombie) a way out: two sidesteps in
  a few seconds mean pinned, and then the body walks to its goal; a gun with nothing to load is not fled with. Copy each
  stall's own numbers into a test and run it on `main` first. **Watch out for:** the autopilot's straight-line flight
  ended in a corner and never let go, so it stood 100 to 640 s with a dry shotgun among the dead; a first fix tested on
  one zombie in the open passed and left the real stall. **Seen:** Deadnight #1351, 2026-11-06 (fix: the pin rule and
  the walk through the dead, each failing alone on the stalls' states).

## Things that fly {#throws}

- **Approach:** Plan a throw or a shot that flies with the server's own projectile code in the bot's own world (the
  walls it sees, the dead it believes in), from where the bot will stand at the release, with its hands' aim error, and
  judge where the thing lies when it goes off, not where it was aimed. A test of an arc against a body works out the
  arc's height at the body first. **Watch out for:** a grenade rolls on after landing, so flat throws lay 17 m out; a
  flare planned with the view exact hit a car 5 m off; a throw checked from where it was ordered met a post; a test put
  a zombie under a lob. **Seen:** Deadnight (bots, phase 3), 2026-11-02; Deadnight #646, #872, 2026-11-03; Deadnight
  #1019, 2026-11-04 (fix: tables of real flights, plans flown again a degree each way, `stop_point`).
- **Approach:** A bot that throws something that hurts tells the team where it will land, keeps out of that reach until
  it goes off and follows where it really lies; a rule that hurts players gets a test with a second player beside the
  source and a soak that measures every blast against where everyone stood. Measure before removing a rule whose reason
  is gone. **Watch out for:** a blast's cover ray met the target's own body; bots walked into their own grenades during
  the fuse; removing a clearance that protected nobody doubled the throws and showed both faults. **Seen:** Deadnight
  #805, #856, #872, 2026-11-03 (fix: a static cover ray, `BotTeam.add_blast`, `keep_out`; the old rule kept until then).

## Fitting a bot to the balance model {#fitting}

A bot skill level meant to play like one of the balance simulator's players is fitted on the same cells (median round,
share past a boss night) and read with the same instruments; the samples it needs are on
[Balance](balance.md#gate).

- **Approach:** Before copying a number from the balance model into a bot, read what each side does with it, and run
  the fast band tests with each candidate lever before a long fit run. **Watch out for:** a bot's `telegraph_read` was
  copied from the simulator's `read`, but one scales a blow's chance to land and the other was the chance to see it
  coming, so weak bots passed a boss night 16 times of 16 against 40%; the lever that fixed the fit moved a band.
  **Seen:** Deadnight #568, 2026-11-02 (fix: the Rookie never reads the telegraph; a lever only the boss reads is free).
- **Approach:** Read a bot's skill from the events that test it (hit rate from shots at 5 to 20 m, dodge from swings
  that reached their blow, a boss test with the trigger held and a control bot that must be hit), and make misses with
  the trigger, not aim noise. **Watch out for:** a bot that fires only inside the hit cone hits nearly every shot, and
  most were at point blank, so its rate read 0.9 whatever its noise; every hit staggers a zombie and cancels its swing,
  so a bot that never moved read a dodge of 0.6 to 0.85. **Seen:** Deadnight (bots, phase 3), 2026-11-02 (fix:
  `CombatProbe.range_hit_rate`, `fire_slop`, `CombatProbe.dodge`, `hold_fire`).
- **Approach:** List what the bot does that the model's player cannot (kite, back off when hurt, dodge, revive,
  throw), switch each off for the profile meant to match the model, rerun the parity soak after every feature that
  changes how long a bot lives, and read the cheap number that decides the fight (boss zones, time to kill, blows
  landed) before tuning. **Watch out for:** kiting when last up and hurt states kept fitted bots alive; days of aim and
  shopping levers moved nothing; 60% of boss hits met a weak spot the model gave 20%. **Seen:** Deadnight #767,
  2026-11-03; Deadnight #767, 2026-11-04 (fix: `kites_when_last`, `careful_below` 0, `aims_off_weak_spot`, `--tune`).

## Soaks {#soaks}

A soak is many real nights of bots with gates on what must never happen (a bot idle with a zombie in view, a round
that will not end). A broken gate is read for its cause before a bot is tuned.

- **Approach:** Make a soak print, for each gate it breaks, what the bot held, did and decided (weapon and ammunition,
  target and why none, note, last errand), measure a gate from what it means (a trip the order allows is counted
  apart), and read what a counter counts before calling it evidence. **Watch out for:** bots tuned by the median round
  hid one cause in 58 of 64 broken nights (a gun held back by its own splash); a Hold gate counted the walk home from an
  allowed trip as time off the spot; a stand-in's stall count was mostly its own wedging and lying downed. **Seen:**
  Deadnight #231, #769, #914, 2026-11-03; Deadnight #1319, 2026-11-06 (fix: `idle_samples`, `off_after`, `--stalls`).
- **Approach:** Look at a soak within two minutes of starting it in a new checkout (its first chunk, the simulator
  file), run one night of one bot there first, and give each test one job: a scripted night proves a behaviour
  happens, a free soak asserts a safety limit and prints its count. **Watch out for:** a control soak in a fresh
  worktree failed at the simulator step and ran an hour with no result; a soak that had to see a throw failed on CI once
  the bots threw less. **Seen:** Deadnight #827, 2026-11-03; Deadnight (grenade soak), 2026-11-03 (fix: the soak
  section of the bots page; a scripted throw night).

### The AI characters' soak (3D Third Person) {#ai-soak}

<!-- new section: the soaks above are Deadnight's bots; nothing said how the template's AI characters are soaked, what
     each gate means, how its teeth are proved or how a replay is checked -->

`tools/soak/ai_soak.tscn` (kit #971) runs the real `main.tscn` headless at `--fixed-fps 60`, seeded: the AI section's
population (3 grunts, 2 shooters, 2 allies, 3 civilians) times `population_scale`, six civilians going about the
pathing section, and the invulnerable player walked round the AI section by `SectionPilot`, which shoots every hostile
in its sight at its chest as it stands now (crouched behind a low wall included). `AiSoakWatch` (`ai_soak_watch.gd`)
is universal: it reads the group `ai_characters` and the parts in their slots, so any scene can hold one. Its gates,
each an exported threshold:

| Gate | Breaks when |
| --- | --- |
| `error` | the engine logs an error (a `Logger`) |
| `stuck_episode` | a living character keeps asking its navigator for a goal and moves under 0.5 m for 10 s (a gap of a second without a goal ends the episode; a death or a respawn starts it again) |
| `stuck_share` | the stuck seconds of all characters (episodes past 2 s) are over 1 % of their walking seconds |
| `idle_with_threat` | its brain has a hostile in view and its controller asks for nothing (no reload, no switch) for 5 s |
| `task_overdue` | the runner's active task, or the fallback it failed into, is active without a break past its hard timeout and 1 s |
| `path_storm` | more queries in 5 s than 5 s over the navigator's `repath_seconds`, and one |
| `think_p99` | the 99th percentile of every think (`AiCharacter.last_think_usec`) is over 2000 us times the calibration loop's slowdown against 11 ms |
| `belief` | a belief names a node that is not a character with a faction (a wall) or one out of the tree (a body in the pool) |
| `round` | the section's hostiles alive at a round's start are not all dead 30 s after `round_seconds` (120): the pilot is walked to the nearest at 120 s (a rescue), the soak kills what is left at 135 s (the safety net, counted as `rescue_kills`), and only a body nothing can end breaks it |

Every broken gate prints `AI_SOAK_GATE {...}`: the character's beliefs, layer stack, last 20 decisions, path end,
navigator, tier, situation and last event. `--lines` prints `AI_SOAK_CHARACTER {...}` a character (stuck and
idle-with-threat seconds, think p50 and p99, path queries, tasks failed by reason): the nightly job's rows. The
`command_hash` folds every living character's position and controller channels each tick.

- **Teeth:** `AiSoakFaults` (`--faults all`, one hostile a fault, each taken when its state lets the fault show)
  breaks each gate: an injected error, a body held while its navigator is sent on, a paused runner with a refreshed
  belief in the player (kept alive for the gate's `idle_seconds` and 1 s, then mortal again), a never-ending task
  with its clock held, the navigator's query clock put back each tick, a think 6 ms longer, an invulnerable hostile, a
  fully aware belief in a wall. `test_ai_soak.gd` runs them in one 60 s run at scale 2 and checks each gate names its
  target.
- **Replay:** the same seed in a fresh process gives the same `command_hash`; another seed does not. In one process the
  second run differs: the navigators take their phase and seed from a static counter of navigators made.
- **Where it runs:** the pull-request suite runs seed 1 for 120 s (about 10 s); `.github/workflows/ai-soak.yml` runs 50
  seeds of 120 s nightly in five shards, with the teeth run, and opens an issue when one breaks.
- **What it found on its first sweeps** (24 runs of 180 s at scale 1, seeds 1 to 16, Windows, 2026-11-11): 19 green; 5
  broke `idle_with_threat`, all on one cause: a cornered civilian whose flee finds no path every second while its runner
  is in its failure fallback, so the flee's own fallback (cower) never runs and it stands looking round with a hostile
  in view (gdstudio issue below in the pull request). A grunt placed outside the AI section with no `patrol_route`
  patrols the section's stops, which its mesh does not reach (the two sections' meshes do not join), so the soak's
  pathing kinds are civilians.

- **Approach:** Reset everything a watch keeps of a character when it was out of sight for a tick (dead, back in the
  pool, spawned again), since a pooled character is the same object across lives. **Watch out for:** the first stuck
  gate kept a shooter's anchor and goal time through its death and broke 20 s after it respawned on the marker it died
  near. **Seen:** gdstudio #971, 2026-11-11 (`AiSoakWatch._begin_life`).
- **Approach:** Give a soak's autopilot what it needs to keep the scenario going (ammunition refilled, aim at the
  target's chest as it stands now) and count the rescues apart, so a round that needs the safety net says so.
  **Watch out for:** the pilot ran dry after its 24 rounds and clicked an empty pistol for minutes, and it aimed over
  crouched grunts behind low walls, so rounds ended only by the rescue (0 to 3 rounds a run); refilled and aiming at
  the body's height, 4 to 22 rounds a run ended with no rescue. **Seen:** gdstudio #971, 2026-11-11
  (`AiSoak._refill_pilot`, `SectionPilot.chest_of`).
- **Approach:** Make each injected fault force the state its gate reads (a task of its own with a clock held, a belief
  refreshed after the senses, a navigator's query clock put back) instead of hoping the scenario brings it. **Watch out
  for:** a held task clock never broke the overdue gate because the AI's tasks change every few seconds; an injected
  unnoticed belief faded in the same think; resetting a goal every tick did not storm because the navigator holds its
  own interval. **Seen:** gdstudio #971, 2026-11-11 (`AiSoakFaults`).
- **Approach:** Keep a fault's target alive for the whole window its gate needs (the `IDLE` target cannot die for the
  watch's `idle_seconds` and a second, then it can), and run the teeth case for many seeds in fresh processes before
  calling it deterministic. **Watch out for:** the pilot shoots every hostile in its sight and a still one is the
  easiest, so the idle target died 2.4 s into its 5 s window whenever the pilot's loop passed it; whether it did
  turned on the process's history (the navigators' static counters), so the case passed alone and failed inside the
  full suite and on main's CI (seed 1 in a fresh process failed too). **Seen:** gdstudio #1328, 2026-11-12
  (`AiSoakFaults._hold_idle`; 24 of 24 seeds then broke the gate).
- **Approach:** For a soak's engine error with no backtrace (a C++ check such as `instance_set_transform:
  !v.is_finite()`), add a probe node that checks every `Node3D`'s global transform each tick and prints the first
  one that is not finite with its character's state, and keeps a ring of the last 40 ticks of the suspect bodies
  (server mode, distance from the clip, speeds, contacts) to dump at the first wild value. **Watch out for:** the
  error was named Linux-only, but the same flinches went 3 to 7 m wild on Windows and only the NaN tail fell on Linux
  seeds; a change anywhere moved the failing seed (5 and 27, then 26 on a later main), so judge a fix by the probe's
  counts over several seeds, not by one seed turning green. **Seen:** gdstudio #1326, 2026-11-12 (the cause was the
  flinch's partial ragdoll: [A partial ragdoll](../engines/godot/ragdoll.md#partial)).
- **Approach:** When a playtest reports AI standing stuck and the soak's stuck gates pass, log what each still
  character holds (its active task, its navigator's mode, its controller's channels) beside how it is drawn (the
  state machine's node, the drawn head's height against the capsule's): a body doing its task as asked can still
  look wrong. **Watch out for:** the "stuck" enemies were in their cover task, still as designed, crouched in the
  body and drawn standing (a crouch asked during a stop clip was sent back to `ground`,
  [the cause](../engines/godot/animation-tree.md#gait-fitting)); no gate reads the drawn pose. **Seen:** gdstudio
  #1412, 2026-11-13.
- **Approach:** Reproduce a soak failure on the commit it was seen on (keep that game, with its probe, until the fix is
  proved), track the failing body every tick in a ring of full snapshots (transforms, velocities, contacts, seconds
  since the death) and dump it with the static shapes around at the first wild value; prove the fix there, and judge
  main by a sweep of seeds. **Watch out for:** the issue's two seeds ran clean on later main (50 of 50) while seed 28
  still broke on the old commit, and copying the dumped state of the body into a test, at the death or 20 ticks before
  the throw, gave a calm body on Windows and Linux alike: the solver's history is not in a snapshot. Velocities
  parsed out of `var_to_str` text with a number regex pick up the 3 of `Vector3`. **Seen:** gdstudio #1372,
  2026-11-13 (`FiniteProbe` snapshots, [Joint limits](../engines/godot/ragdoll.md#limits)).
- **Approach:** Check a soak's replay in fresh processes, and look for static counters (`static var`) before calling a
  run nondeterministic. **Watch out for:** two runs of the same seed in one GdUnit process gave different hashes
  while separate processes matched. **Seen:** gdstudio #971, 2026-11-11 (`test_the_same_seed_repeats_its_commands`).
- **Approach:** To prove a fix for a seed the nightly soak broke on Linux, dispatch the soak on the branch (`gh workflow
  run ai-soak.yml --ref <branch>`) and read all five shards; run seeds locally only as a second look. **Watch out
  for:** the soak diverges by platform, so the same seed on Windows took another course: seed 21 never showed the
  director's fault there and broke on another error instead. **Seen:** gdstudio #1419, 2026-11-13 (the dispatch ran 50
  seeds green, seed 21 included).
- **Approach:** When `think_p99` (or any time gate) fails in a full local run on the shared machine, run that suite
  again alone before treating it as a failure, and put both readings in the pull request's body; CI on the branch is
  the judge. **Watch out for:** the full run beside other agents' Godot processes read think p99 just over its gate
  (2764 against 2678 us) on a change to the first shot; run again alone it passed. **Seen:** gdstudio #1411 (PR #1424)
  and #1412 (PR #1432), 2026-11-13 (with `test_parts_budget.gd`: [Reading a timing on a shared
  machine](../engines/godot/performance-budgets.md#reading-a-timing-on-a-shared-machine)).
