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
