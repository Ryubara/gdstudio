---
areas: [blender, tests]
---
# A clip test sampled a new clip only after another suite had loaded it

2026-11-04

- **Saw:** Deadnight's arm sampler (`ClipFit`) failed on CI for the new perk drink (`Drink_Perk` right arm 37 mm, head)
  but its own measuring tool, run alone, printed `Animation not found: "Drink_Perk"`. Every quarter frame the clip had
  the fist 60 mm in the head at the gulps and the fingers 50 mm in the hip, which eight samples did not all reach.
- **Cause:** the sampler loads the clip files it knows by name; the drink's file was not among them. It was sampled on
  CI only because an earlier suite in the same run had added it to the Soldier's library, a resource every model
  shares. The clip itself was authored by where the bottle's lip ends (on the mouth), as the clips of #939 had been: with
  the bottle tipped up past level from far round to his right, the hand holding it sat over the big head's face.
- **Fix:** the sampler loads every file the player's animation loads (the drink added), so the test is the same alone
  and in any order; the bottle comes round 45 degrees, not 58, raised to 126, not 135, the elbow back a little, and it
  starts further out from the hip: 13 mm at most, every quarter frame, both looks, lip still on the mouth.
- **Docs:** [Clips that keep the arms out](../blender/variants.md#clips-that-keep-the-arms-out).
