---
areas: [blender, tests]
---
# Clips checked by where the hand bone ends put the arms through the body

2026-11-04

- **Saw:** Deadnight's clip sampler (#895) found forearms and hands up to 142 mm inside the body: both dual pistols
  through each other in the quick melee and the equip, the revive's hands through each other, the downed hand through
  the drawn-up thigh, the crawling knee through the hand on the belly, the strikes' free hand in the knee (#939).
- **Cause:** every clip was authored by where a bone ends (a hand on a grip, at a wound, on a chest) and checked
  there, never by what the limb's mesh passes through. The dual clips mirrored the one-handed pistol arm, so both hands
  sat on the body's middle line; the night's hand IK holds them apart while aiming, which hid it there, but equip and
  the melee play the clip's own arms. The sampler took four slice centres per clip and missed key poses (a windup at
  0.25 s, 83 mm into the head). Turning the revive's hands did nothing: that clip leaves the hand bones unkeyed.
- **Fix:** an arm-clearance check in Blender (the game's six-ray inside test on the kit body, at every key frame and
  eight samples) prints an `ARMS` line per clip at build time; poses were tuned against it, then confirmed in Godot. The
  dual base is the IK's own hold, read in Godot; a probe drives the real player through every action and measures the
  pose after the IK. The test now samples eight frames and allows no clip over 3 cm.
- **Docs:** [Clips that keep the arms out](../tools/blender/variants.md#clips-that-keep-the-arms-out).
