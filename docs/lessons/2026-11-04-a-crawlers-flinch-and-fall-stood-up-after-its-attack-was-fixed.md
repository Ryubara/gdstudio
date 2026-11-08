---
areas: [gameplay, blender, general]
---
# A crawler's flinch and fall stood up after its attack was fixed

2026-11-04

- **Saw:** after #971 gave the crawler an attack on the floor, a film of it through the player's camera still showed it
  rising when a shot hit it and again when it died (Deadnight #1000): the stagger plays the walker's `HitReact` (mesh top
  1.66 m against the crawl's 0.85 m) and the death the walker's `Death` (1.81 m).
- **Cause:** #971's fix and its lesson named the whole class (every action of a body that cannot stand) but the change
  and its test covered the one action that was reported. The height test was written for the attack, over a named list
  of clips, so the sibling actions had nothing to fail.
- **Fix:** a clip of its own for each (`Crawl_Stagger`, `Crawl_Death`, built from the Crawl's first frame beside
  `Crawl_Attack`), a state each chosen by the same one test of the look, the stagger's hit set refitted, and a test
  that loops over `ZombieBody.Mode.values()` through the view (the highest bone while each mode plays, stepped by hand)
  and again in the real night, so an action added later is measured the day it exists. The same test run over the walker
  proves the measure sees a body stand up, and the test failed 7 times with the view's change reverted.
- **Check:** when a fix is "this body has the wrong clip for action A", the same pull request lists every action of the
  enum for that body and tests the whole list by looping over the enum, not by naming the clips; list what a body never
  does (a crawler never tears boards: the sim sends it under) and what is not merged yet (the sill climb of #986).
- **Docs:** [AnimationTree: one action state for every body](../engines/godot/animation-tree.md#one-action-state-for-every-body).
