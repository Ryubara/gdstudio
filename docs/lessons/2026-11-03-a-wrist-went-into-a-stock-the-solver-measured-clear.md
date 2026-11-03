---
areas: [blender, tests]
---
# A wrist went into a stock the solver measured clear

2026-11-03

- **Saw:** the M4A1's right `thumb_base` went 9.1 mm into the gun in the shouldered capture (the limit is 2 mm), where
  the solver had measured it 0.4 mm off (Deadnight #795).
- **Cause:** the `thumb_base` skin is partly the forearm's, and the solver poses the arm differently from the game's
  shouldered pose, so the wrist lands elsewhere; here it was at model (0.20, 0.01) under the stock, whose underside
  dropped from z 0.03 to 0.0 just behind the buffer tube's root.
- **Fix:** the stock's underside keeps its front high (z 0.035 at x 0.15, 0.02 at x 0.22) before it drops to the butt.
  Trust the game-pose capture over the solver's table for the palm and the thumb's root, and keep a stock's underside
  clear of the wrist for about 20 cm behind the grip.
- **Docs:** [Weapons, hands on the weapon](../blender/weapons.md#hands-on-the-weapon).
