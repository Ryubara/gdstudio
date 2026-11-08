---
areas: [blender]
---
# A support placed at the real gun's distance was out of the left arm's reach

2026-11-03

- **Saw:** Deadnight's M249, .50 calibre rifle and pump shotgun (#796), held in the capture with their grips solved,
  had the left hand 3 to 29 mm into the weapon in every pose (`HandContact`), while the Tommy gun and the double beside
  them held clean.
- **Cause:** the plan placed each `Support` where the real gun's hand guard is, 0.32-0.34 ahead of the grip in drawing
  units, but these guns are held 1.21-1.3 times their drawing (the first long guns 0.84-0.96), so 0.35 m in the game;
  with real-length stocks pushing the grip forward from the shoulder, the support was 0.75-0.85 m from the shoulder and
  the Soldier's 0.66 m arm stopped short, inside the gun.
- **Fix:** shoulder to support about 0.70 m or less (`|grip_offset.z| + |support.x| x model_scale x 0.8`), then
  measure the gap between the left hand bone and the IK's target (it was 1.7-3.4 cm still at 0.71-0.72 m). The support
  comes back only until the hand clears the magazine or the box (closer, the solved grip left the thumb 80 mm off), and
  the stock takes the rest: supports at 0.28-0.32 ahead of the grip, butts at 0.30-0.345 behind it, shorter than the
  real guns'; grips solved again and measured in the capture.
- **Docs:** [Weapons in the Toon Shooter style](../tools/blender/weapons.md#hands-on-the-weapon); Deadnight's
  `docs/research/weapon-models.md` "The left hand's reach".
