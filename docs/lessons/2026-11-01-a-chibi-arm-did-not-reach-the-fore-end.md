# A chibi arm did not reach the fore-end

2026-11-01

- **Saw:** with each long gun's left-hand grip solved to 1 mm, in the game the left fingers went 5-43 mm into the
  fore-end or floated 30 mm off it; the hand bone was 4-15 cm from its target, turned exactly right.
- **Cause:** the left arm's two-bone IK clamped: the fore-end was 0.70-0.81 m from the left shoulder and the kit
  Soldier's arm is 0.66 m, so the hand stopped short, inside the stock.
- **Fix:** a shooter's stance: turn the chest 20-30 degrees so the left shoulder comes forward (the weapon's place is
  then taken from the right shoulder after the turn), move the gun 5 cm toward the chest and the support to the
  fore-end's rear; measure the reach the IK needs for every weapon before trusting a solved grip.
- **Docs:** [Blender weapons](../blender/weapons.md#hands-on-the-weapon).
