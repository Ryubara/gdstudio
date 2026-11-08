# Testing a game

<!-- new section: gamedev had pages for level design and audio only; nothing held the engine-neutral rules of when a
game feature counts as tested -->

When a feature of a game counts as done: proved on the path a player takes, for every entry of a catalogue, not on its
parts one by one. How Godot runs such tests is in the testing pages of [Godot](../engines/godot/index.md), and how a
long run is started and read in [Running GdUnit4](../engines/godot/running-gdunit.md).

## The real path {#real-path}

<!-- new section: proving a feature on the player's path had no home -->

- **Approach:** Count a feature as done only when one test runs its real path: press the real input in the real game,
  save through the real file, enter the real level and read what the player sees; one matrix test presses every gameplay
  action on every device and fails on an action with no row. **Watch out for:** parts tested one by one were counted as
  a working feature: a wardrobe look never reached the character (the player scene held a fixed model, no join message
  carried the look), and grenades were wired only into their test range while keys, HUD, shop and sounds existed.
  **Seen:** Deadnight, 2026-11-01 (wardrobe look); Deadnight #351, #356, 2026-11-01 (grenades) (fix: the real-path tests
  and the action matrix).
- **Approach:** Count a screen or feature as shipped when a player reaches it from the menu: its test starts at the
  menu's button (never at the scene path), and a hand-off to "the menu work" becomes an issue in the same pull request.
  **Watch out for:** the Play screen with the shared settings panel was built, its route was left as "a one-line change
  for the menu work", and its own tests opened it by path, so they passed while no player could reach it; a headless run
  also measures text as nothing, so check the fit in a windowed capture and the web build. **Seen:** Deadnight #620,
  2026-11-02 (fix: Solo opens the Play screen, a test presses Solo from the menu, another fails when a `MatchSettings`
  key has no row).
- **Approach:** Capture and probe the shipped state first (the start the game really gives: one weapon and an empty
  second place; the real scene with a real sign-in, in a [throwaway user folder](../engines/godot/throwaway-user-folder.md)),
  and run a fault seen in a capture that assembles its own parts in the real scene before believing it. **Watch out
  for:** fixtures that fill the hands look like a night, so a probe waited for two weapons and timed out; a capture that
  built its own router and overlay showed LEVEL UP 12 over a plate that said LEVEL 1, while the real menu read the
  profile once at build and the start-up sign-in landed later (level 4, 52 of 124 cells locked instead of 39). **Seen:**
  Deadnight #1130, 2026-11-04; Deadnight #682, 2026-11-03 (fix: `ProfileUplink.adopt_and_tell`, and a test that fails
  without it).
- **Approach:** Set a setting through the service the player uses (in a test-owned settings file), not the field on the
  object, in any bench or test of something that listens to `Settings.changed`. **Watch out for:** a browser run set the
  aim assist's strength and auto-fire on the object, and the first touch (the first-run hints write a setting) fired
  `changed`, so the object re-read the saved settings and every run behaved the same. **Seen:** Deadnight, 2026-11-01
  (fix: the bench sets the setting).
- **Approach:** Count a design claim against the data before a test is written to it, pin the real number with a
  comment, and report the gap to the maintainer as a question instead of re-dressing the data. **Watch out for:** the
  issue asked for four starting costumes lit at level 1; the twelve presets' pieces counted against the ladder gave two.
  **Seen:** Deadnight, 2026-11-04 (fix: the test computes each costume's level from the tables the game reads).

## Every catalogue entry {#catalogue}

<!-- new section: testing each entry of a catalogue (weapons, items) had no home -->

- **Approach:** Give every catalogue entry (each weapon, each item) its own play-through test with real input in the
  real game: model, grip, support hand, clip, effects and result, and a capture after each swap. Never assert a stand-in
  as correct, and report a shipped gap to the maintainer, not only on a design page. **Watch out for:** `equip` was
  never called outside tests, holds were copied from one pose, melee went through the gun effects, no game code played
  the attack clips, and tests pinned a bat standing in for the crowbar as expected. **Seen:** Deadnight, 2026-11-01
  (weapons on screen); Deadnight #285, 2026-11-01 (crowbar and revolver) (fix: one test per entry and captures that
  drive the real path ([lesson](../lessons/2026-11-01-a-catalogue-weapon-was-never-played-in-the-night.md))).

## Random draws {#random-draws}

<!-- new section: testing a random draw against the shipped seed had no home -->

- **Approach:** Test a random draw from the seed the shipped game starts with, not only over a seed sweep, and keep
  fixed seeds to benches that set them, never to play. **Watch out for:** the crane's pool held all eight weapons and
  the dice were fair, but Deadnight #461 tested the odds over seeds 0 to N, never the one seed every solo night started
  from (`Night.SEED` 1958), so each solo night rolled the same prizes in the same order. **Seen:** Deadnight #685,
  2026-11-03 (fix: players noticed the shotgun came first
  ([lesson](../lessons/2026-11-03-a-solo-night-had-one-fixed-seed-so-the-crane-rolled-the-same.md))).

## What is drawn {#what-is-drawn}

<!-- new section: testing a shape against the mesh the player sees, not against its own numbers, had no home -->

- **Approach:** Test a hit shape against what is drawn: a ray grid at the skinned mesh in every pose the animation can
  put a target in, through the server's own trace, with the registered and head rates before and after. **Watch out
  for:** every zombie was shot through one upright set of six shapes, scaled but never posed, so a crawler's head zone
  floated 0.97 m up behind its head and 22% of shots touching its mesh registered; the tests aimed at points made from
  the same numbers. **Seen:** Deadnight #694, 2026-11-03 (fix: players reported it
  ([lesson](../lessons/2026-11-03-hit-zones-were-one-standing-set-that-ignored-the-pose.md))).

## Waits have an end {#bounded-waits}

<!-- new section: the sections above say what to prove; none said how a test or probe may wait -->

- **Approach:** Bound every wait in a test or probe (frames or seconds) and assert on what was seen after the bound, so
  a failed expectation fails at once and names itself; wait for the platform's real ceiling, not a number counted on
  another build. **Watch out for:** an unbounded wait turns a failed expectation into a hang that names no test; a probe
  that waited for 64 dead on a platform whose ceiling (`alive_cap`) is 40 sat in its 400 s night and never ended.
  **Seen:** Deadnight #429, 2026-11-02 (a count that never came); Deadnight #948, 2026-11-03 (fix: waits end in a frame
  count; the probe waits for `hudalive=40` and a number that cannot be reached ends the run with a line saying so).

## What a test leaves behind {#leftover-state}

<!-- new section: nothing said that a suite hands its shared state to the suites after it -->

- **Approach:** A suite that sets shared state (a static, a screen on the UI router, a held key, a menu) clears it
  when it ends, in `after_test` or the node's `_exit_tree`, never by resetting to another screen; click-driven suites
  also clear in `before_test`. To find the leaker, run each suspect before the failing suite and list the controls
  under the click point. **Watch out for:** statics live for the whole process, so a path the game root set outlived
  the root; a full-rect screen with a stopping mouse filter left on the router (`UIRouter.reset(_screen("end"))`)
  took the clicks and keys of later suites and failed 6 slider tests only in the folder run; a failed run left the
  sprint key held for the next arm. **Seen:** Deadnight #429, 2026-11-02; Deadnight #458, #466, 2026-11-02; Deadnight
  #914, 2026-11-03 (fix: `RouterFixture.clear` ends the leaking suites; 438 cases, 0 failures).

## A test that can fail {#teeth}

<!-- new section: nothing said how to know a new test measures anything -->

- **Approach:** See every new test fail once before trusting it (revert the fix, break the behaviour, or remove the
  switch from a suite), and make a test that filters a table by name assert the names are in the table. **Watch out
  for:** the checks had been renamed for a diagnosis and the test still filtered by the old names: a filter that
  matches nothing measures nothing and reports no fault, so a gun 59 mm off passed; a scan pattern looking for
  `NightScreen.arrival_enabled =` was satisfied by the line that puts the old value back (`= _arrival`). **Seen:**
  Deadnight #987, 2026-11-04; Deadnight, 2026-11-05 (fix: the checks were put back and the test seen red; the pattern
  became `= (false|true)` and two deliberate breaks fail the scan).
- **Approach:** Before trusting a placement in a test, print a trace (body, target, its mode) every quarter second, put
  the target where a ray from the body reaches it, and release every key in `after_test` and before each arm.
  **Watch out for:** an online test put a walking zombie 12 m ahead and the sprinting body stopped 1.3 m short, read
  as the rule under test; a fence 8.4 m ahead had stopped it, and the failed run left the sprint key held. **Seen:**
  Deadnight #914, 2026-11-03 (fix: `DEAD_TRACE=1` in `tests/net/test_dead_online.gd` prints the trace).

## Tests that read shared data {#shared-data}

<!-- new section: nothing said how a test stays true when the data or other tests around it change -->

- **Approach:** A test of arithmetic feeds its own table (`LadderUnlocks.from_text`) and checks the shipped table only
  against the function, never against numbers read off it; give a new field of a tuning resource its row in the test
  that loops over every field. **Watch out for:** CI tests the merge with the current `main`: another pull request
  made levels 18 and 19 available, the next unlock moved from 20 to 18, and three tests of the shipped ladder failed
  after a green local run; a suite that loops over every `HudTuning` field was never run. **Seen:** Deadnight #1136,
  2026-11-04 (fix: tests feed their own table; `tests/tuning/default_values.gd` got the row).
- **Approach:** When adding to a registry (actions, sounds, wire types, snapshot keys), grep the tests for loops over
  it (`grep -rn "REQUIRED\|SoundCatalog.ids()" game/tests`), give the new entry what each asserts of every entry, and
  run those folders whole before the first push. **Watch out for:** a new rules action and an on-demand sound bank each
  broke an older suite (every action type needs a sample; the background load leaves 0 files) that the new suites never
  touched. **Seen:** Deadnight #1057, 2026-11-04 (fix: a sample for the action; the load test loops over
  `SoundCatalog.ids_for_night()`).
- **Approach:** When adding a test that reads other tests' source as text, run the other scans of that folder
  (`grep -l "FileAccess.get_file_as_string" game/tests`) and the whole folder headless again after every merge of main;
  exempt the new file from the older scans or build its example strings from two parts. **Watch out for:** the example
  text the new scan's own assertions held (`UIRouter.push(NIGHT, ...)`) was taken by an older scan for a real call, and
  a third scan merged later failed on the same strings. **Seen:** Deadnight, 2026-11-05 (twice) (fix: the new file
  joined the older scan's `EXEMPT` list and the third scan's file joins its scene name from two parts).

## Chaotic runs: a rate, not seeds {#chaotic-runs}

<!-- new section: nothing said how to assert on a simulation where one changed hit changes every later night -->

- **Approach:** Test a chaotic simulation (a bot night) as a rate with a limit measured on `main`: a sweep of many seeds
  (100), the limit and margin written in the test, its false-red chance from the binomial, and its teeth shown by a
  deliberate break; keep a sweep too costly for the suite in a capture scene, and give a red seed after an unrelated
  change that sweep before a fix or a skip. **Watch out for:** one moved hit moves every later night on every seed;
  four pinned seeds, picked on the night they passed, ask "is this seed one of the 5%?" (main itself fails 5 of seeds
  1 to 100) and a reshuffle answers at random: a change to where the dead are hit failed seed 7 only, while the aim
  was no worse. **Seen:** Deadnight
  #1038, #821, #890, #910, 2026-11-04 (fix: the test plays seeds 1 to 10 and allows 3 failures, the limit from 5 of
  100 on main; the sweep is `smallmap_solo_sweep.tscn`).

## Time-based tests {#time-based}

<!-- new section: nothing said how to assert on a guard whose speed depends on the scheduler -->

- **Approach:** Test a time-based guard by a latency bound it can only miss by being absent (seconds, measured at the
  source of the event) or by a count of calls against a fake; reproduce a flake by injecting the delay, and when a fix
  lands search the folder for the same shape (`grep -rnE "of [0-9]+ samples|held.*<=|len\(held\)"`). **Watch out for:**
  "at most N of M samples saw it" is set by how the guard thread, the sampler and the program are scheduled: a
  cursor-clip test allowed a third of 20 samples held and failed `9 <= 6` on a loaded runner; the same shape failed in
  the browser test next because nobody searched. **Seen:** kit #113, #166, 2026-11-02 (fix: the probe times the
  longest stretch the clip differed and the test asserts it under 1 s; a fake clip and clock test the measure, mutant
  included).

## When something shared changes {#shared-change}

<!-- new section: a changed default, constant or row turned suites red that never named it; no page held the habit that
finds them first -->

- **Approach:** When a default, a constant or a row of a table changes, search the tests and the code for every reader
  of it (`LookStore.load_look`, `unlocks.json`, `STICK_`) and run those suites, then the whole folder once more after
  `gds merge-main`; a test that is not about the thing says what it owns (`LookUnlocks.at_level(55)`). **Watch out
  for:** a level on 26 wearables made every default mean "a level 1 player" and 88 assertions failed in look, loadout,
  menu and network suites; flipping 24 rows to `available` was checked against the readers in the checkout, and a
  popup test over every available row, merged meanwhile, found four with no art; a stick ring moved to CSS pixels broke
  the night input matrix's pushes of 70 and 150 units. **Seen:** Deadnight, 2026-11-04; Deadnight #1070, 2026-11-04;
  Deadnight, 2026-11-05 (fix: tests name what they own; the readers learned the new art).
- **Approach:** Derive a number a test depends on from the thing it counts (circles minus the hidden button plus the
  places) or name it with its reason, and treat an element that shows only in a context as a hidden case in every suite
  that lists, counts or presses the elements: search for it first, give the fixture a switch for the context, run a fit
  matrix with the context down and up, and add a new hint to every "first run" list in the same commit. **Watch out
  for:** a Strike button that shows with a dead in reach broke seven suites that each held their own picture of "the
  buttons"; a fourth hint made two suites that compared with the constant list go red; merging another layout change
  turned a marker capacity of eight and a box count of 15 red with no test edit. **Seen:** Deadnight #1285, #1286,
  #1280, 2026-11-05 (fix: `TouchFixture.strike_up`, `WITHOUT_BOTS`, `CROWDED_HOLDS`).
- **Approach:** Print the failure count and every `FAILED` line (`grep -c FAILED`, never `head` on a mixed list),
  compare the `Overall Summary` line, and run the whole test folder of the game before the pull request, not the
  folders you think you touched. **Watch out for:** a test script piped through `head -60` showed 55 passes and two
  failures; a sixth settings row used the 50 units the Play screen's fit tests had left, and only the folders run were
  green. **Seen:** Deadnight #715, 2026-11-03 (fix: the skill selector went beside the Bots count; the tour's hook was
  cleared).
