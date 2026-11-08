# Testing a game

<!-- new section: gamedev had pages for level design and audio only; nothing held the engine-neutral rules of when a
game feature counts as tested -->

When a feature of a game counts as done: proved on the path a player takes, for every entry of a catalogue, not on its
parts one by one. How Godot runs such tests is in the testing pages of [Godot](../engines/godot/index.md).

## The real path {#real-path}

<!-- new section: proving a feature on the player's path had no home -->

- **Approach:** Count a feature as done only when one test runs its real path: press the real input in the real game,
  save through the real file, enter the real level and read what the player sees; one matrix test presses every gameplay
  action on every device and fails on an action with no row. **Watch out for:** parts tested one by one were counted as
  a working feature: a wardrobe look never reached the character (the player scene held a fixed model, no join message
  carried the look), and grenades were wired only into their test range while keys, HUD, shop and sounds existed.
  **Seen:** Deadnight, 2026-11-01 (wardrobe look); Deadnight #351, #356, 2026-11-01 (grenades) (fix: the real-path tests
  and the action matrix).

## Every catalogue entry {#catalogue}

<!-- new section: testing each entry of a catalogue (weapons, items) had no home -->

- **Approach:** Give every catalogue entry (each weapon, each item) its own play-through test with real input in the
  real game: model, grip, support hand, clip, effects and result, and a capture after each swap. Never assert a stand-in
  as correct, and report a shipped gap to the maintainer, not only on a design page. **Watch out for:** `equip` was
  never called outside tests, holds were copied from one pose, melee went through the gun effects, no game code played
  the attack clips, and tests pinned a bat standing in for the crowbar as expected. **Seen:** Deadnight, 2026-11-01
  (weapons on screen); Deadnight #285, 2026-11-01 (crowbar and revolver) (fix: one test per entry and captures that
  drive the real path).

## Random draws {#random-draws}

<!-- new section: testing a random draw against the shipped seed had no home -->

- **Approach:** Test a random draw from the seed the shipped game starts with, not only over a seed sweep, and keep
  fixed seeds to benches that set them, never to play. **Watch out for:** the crane's pool held all eight weapons and
  the dice were fair, but Deadnight #461 tested the odds over seeds 0 to N, never the one seed every solo night started
  from (`Night.SEED` 1958), so each solo night rolled the same prizes in the same order. **Seen:** Deadnight #685,
  2026-11-03 (fix: players noticed the shotgun came first).

## What is drawn {#what-is-drawn}

<!-- new section: testing a shape against the mesh the player sees, not against its own numbers, had no home -->

- **Approach:** Test a hit shape against what is drawn: a ray grid at the skinned mesh in every pose the animation can
  put a target in, through the server's own trace, with the registered and head rates before and after. **Watch out
  for:** every zombie was shot through one upright set of six shapes, scaled but never posed, so a crawler's head zone
  floated 0.97 m up behind its head and 22% of shots touching its mesh registered; the tests aimed at points made from
  the same numbers. **Seen:** Deadnight #694, 2026-11-03 (fix: players reported it).

## A test leaves nothing behind {#teardown}

<!-- new section: nothing held what one test owes the next -->

- **Approach:** Free in teardown everything a test built that owns bodies or players (a level, a night), and fix a
  leftover instead of rerunning. **Watch out for:** night suites built a level per test and never freed it, so the
  next test's player spawned on the old one's body and heard its grenades; the test failed only after another night
  test. **Seen:** Deadnight #356, 2026-11-01 (fix: `after_test` frees the level).

## A scenario proves an outcome {#scenarios}

<!-- new section: a scenario test (units put in a staged situation) and what makes it prove anything had no home -->

A scenario puts the game in a situation (a pack at a downed body, a bot with an empty gun) and checks what happens. It
proves something only when it fails without the change, asserts the outcome a player would see, and builds its
situation the way the game does.

- **Approach:** Run a scenario with the change switched off first and see it fail on the outcome (a body that bleeds
  out), not on a flag of the new code, and give a control a time bound the feature cannot erase instead of "never".
  **Watch out for:** a revive scenario built from the story passed with the rule on and off (the bodies rose at
  42.45 s both ways); a control that "cannot" clear a pack became winnable once hurt bots learned to back off.
  **Seen:** Deadnight #673, 2026-11-02; Deadnight #693, 2026-11-03 (fix: static switches kept for A/B runs; the control
  judged inside the flare's window).
- **Approach:** Make a scenario's assertion name the units it is about (the dead within 14 m of the body, the flare the
  bot fired) and assert what they do to the thing under test; before parking units somewhere, ask whom the simulation
  lets them chase. **Watch out for:** a "no zombie alive at the hold" check counted two at a gate 60 m off; dead parked
  round a downed body walked off to the reviver, since the downed are no target, so "the dead are at the body" passed
  or failed by chance. **Seen:** Deadnight #229, 2026-11-02; Deadnight #646, 2026-11-03 (fix: a count near the body,
  outcome checks with a control).
- **Approach:** Build what a test stands in for with the game's own setup (one function both call), forward what the
  real server broadcasts, give a fake frame only the keys the real one carries, and assume a stand-in for a person acts.
  **Watch out for:** bots seated by hand without the host's table each took the other for a person; a soak's person
  stand-in was seated bare, never shopped and was dry 64% of its time; a test rig's frame invented `max_health`; a
  takeover check compared points the autopilot had already spent. **Seen:** Deadnight #676, #998, #230, 2026-11-03;
  Deadnight (bot play states), 2026-11-03 (fix: the host's table shared, `AutopilotSetup.configure`, the field read from
  events, unchangeable things compared).
- **Approach:** Read a test helper for the state it changes besides its job (points, health, the clock) before
  trusting a run that uses it, and print that state in the run's first line. **Watch out for:** a door helper granted
  100,000 points for each purchase to be sure it went through, so a soak "with the whole map open" was one rich bot.
  **Seen:** Deadnight (second map bot nights), 2026-11-03 (fix: the points read before and put back after).
- **Approach:** When a test places a body, check what stands under it and where it ended after the first step, set all
  of its state as the game's own drop does, and stand the person where each thing under test is the way in. **Watch
  out for:** a body teleported against a door slab was pushed to its front and pressed from there; a dead set in the
  air off a deck walked to a shed roof and a flag from the wrong window passed; a window test with the person in the
  hall sent three windows' dead through one gap. **Seen:** Deadnight #810, #817, 2026-11-03; Deadnight #994,
  2026-11-04 (fix: the shared drop helper, a 0.15 m check after the press, starts on the mesh).
- **Approach:** Give a test about a time window the time it needs: reset carried state between rounds of a rate test
  and count enough events that one is a few percent, give a test about calm a break longer than its run, and list the
  times of the event over many seeds before choosing how long a night runs. **Watch out for:** a fire-rate test read a
  weapon still cooling from the round before; a shop test said "in the break" and bought in the rounds when the dead
  happened to be far; a solo night bought its weapon in one break with 70 s of margin and missed it on CI. **Seen:**
  Deadnight #734, #817, #827, 2026-11-03 (fix: the cooldown reset over 5 s, a break longer than the run, a 330 s night).
- **Approach:** Check a probe that reports "never" against its own loop before believing it: print why the last step
  did nothing (blocked, empty, no target), make every listener before the events it hears, and assert that the first
  action took effect. **Watch out for:** a weapon audit stopped at an empty magazine, since only a fire attempt reloads,
  and its combat server was made after the zombies spawned and tracked none, so every gun read "99 pulls". **Seen:**
  Deadnight #972, 2026-11-04 (fix: the audit makes the server first and reloads).
- **Approach:** Derive a test's numbers from what it tests (a magazine from the weapon's definition, a count from the
  scene or the rules' list), keep a classification ("needs a crowd") beside the list others extend, and when a second
  place starts doing what only one did, search for hard-coded counts and for state made on first use. **Watch out
  for:** a test's "under a magazine" of 4 was two magazines after another pull request retuned the gun; a crowd-stat
  list kept in its consumer went stale; new breaches made nodes mid-fight and broke tests that counted six. **Seen:**
  Deadnight #730, #849, 2026-11-03; Deadnight #1168, 2026-11-05 (fix: extremes or definition values,
  `ChallengeStats.CROWD`, pools made when a breach is built).

## Seeded runs and baselines {#seeded-runs}

<!-- new section: a seeded night is chaotic (any change redraws it); how to judge one had no home -->

A seeded night of bodies, bots and the dead is chaotic: a node more, a centimetre of route or a 1% change of fire rate
plays another night from the same seed. Why two runs of one night differ in Godot is on
[Fixed-step repeatability](../engines/godot/fixed-step-repeatability.md).

- **Approach:** Stage the fight a test measures (each dead put once ahead of the bot, walking straight) instead of
  waiting for a march across the map, and run a test's body 10 to 40 times in one suite, printing the number it asserts
  on. **Watch out for:** a boss-fight test counted shots of a 40 s march whose length moved by centimetres a run (3 to
  218 shots); a skill test read the map, and 20 hand-placed lamps changed every band with no bot change. **Seen:**
  Deadnight #596, 2026-11-02; Deadnight #719, #783, 2026-11-03 (fix: `SeatedNight.stage_the_dead`, a trigger-up fight
  for the dodge).
- **Approach:** When a band test fails after an unrelated change, run it on `main` and on the branch, locally and on the
  runner, with more seeds before touching it; if `main` reads near an edge, recalibrate the band in the change that
  moves what it measures. **Watch out for:** a navigation mesh change and a 1% fire-rate change each redrew a fight read
  from a few dozen blows; four seeds on `main` sat inside the band and ten outside, so a wider tolerance chased noise.
  **Seen:** Deadnight (navmesh contour), 2026-11-02; Deadnight #708, 2026-11-03 (fix: `BOTS_BANDS_SEEDS=10`, the band
  recalibrated with the hit-zone rework).
- **Approach:** Judge a seeded night by what holds over time or by a mean over many seeds with an interval, never by
  trying seeds till one passes; when it goes red on an unrelated change, rerun `origin/main` many times, print the
  decision log of both and find the choice that differs, and read a number that will not repeat with a probe, not a
  bisect. **Watch out for:** three shop spots, three removed nodes or one commit each redrew a night: a roam test judged
  one moment, a solo bot met round 3 unarmed, one draw of a nightly (round 13, not 17) read as a regression. **Seen:**
  Deadnight #793, 2026-11-03; Deadnight #952, #1019, 2026-11-04; Deadnight #1341, 2026-11-06 (fix: distance over
  time, a bot that saves for its first gun, 20 seeds a commit).
- **Approach:** Measure a baseline before the first edit or from a detached checkout of `origin/main`, name its commit
  in the log, run it twice and over at least eight seeds, and compare the kind of failure, not the seed. **Watch out
  for:** a "baseline" soak started after the edit measured the new code; a stall blamed on dressing a map was in the
  baseline on another seed; one A/B of a whole night proved nothing because `main` differed from itself. **Seen:**
  Deadnight (link soak), 2026-11-03; Deadnight (second map dressing), 2026-11-03; Deadnight (crowd budget), 2026-11-03
  (fix: the baselines redone; the bots' deterministic suites named as the proof).

## Which suites a change runs {#what-to-run}

<!-- new section: which tests a change must run before it is pushed, and after a merge of main, had no home -->

- **Approach:** Before pushing a change to something many suites read (a default bot behaviour, a shared node, a
  roster number, the map, the walking mesh, the pool of bodies), grep for its readers and its old value, run every
  folder that holds them (the night, bot and world suites, not only the new one), and make each old test say what it
  stands for. **Watch out for:** a mark made a node mid-night, a default order made standing tests roam, a moved lamp
  post broke a test that wrote its cover as coordinates, and a pinned list order and a copied boss health went red in
  folders nobody ran. **Seen:** Deadnight (outline), 2026-11-02; Deadnight #641, #682, #688, #719, #938, 2026-11-03
  (fix: those folders run before the push; cover read from the lot).
- **Approach:** After every merge of main, grep the merged tree (tests and captures included) for each field, action
  or default the branch removes or changes, run the suites of what landed meanwhile, and diff each file the branch
  shares with a merged pull request; grep again right before auto-merge. **Watch out for:** clean merges left a
  duplicate dictionary key, another pull request's test assuming the old default order, readers of a removed field,
  and suites that bought perks in a row against a purchase that now takes 2.5 s. **Seen:** Deadnight #676, #814,
  2026-11-03; Deadnight #959, 2026-11-04; Deadnight #1233, 2026-11-05 (fix: a shared fixture step that finishes an
  action; the grep named in the pull request is the one after the merge).
