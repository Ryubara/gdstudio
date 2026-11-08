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
