# Gaits from kit clips

How to author locomotion clips (a sprint, strafes, a backpedal) on a Quaternius rig from the kit's own Run, so the
feet cover a known ground speed and the new clips blend in step with the old. Learned in Deadnight #278 (the zombie
`Sprint`, `tools/blender/build_zombie_clips.py`) and #74 (the Soldier's `Walk_Shoot`, `Walk_Back`, `Strafe_Left`,
`Strafe_Right`, `tools/blender/gaitlib.py` and `soldier_clips.aim_moves`). The clean-up before it is
[rig sharing](rig-sharing.md).

## What the kit Run gives {#what-the-kit-run-gives}

| | Zombie | Soldier |
| --- | --- | --- |
| Length | 16 frames (0.67 s) | 17 frames (0.71 s) |
| Feet | `Foot.L/R` hang from `Root` and carry location keys (the baked IK targets the boots are weighted to); the legs are keyed separately | same |
| Leg (kit scale) | thigh 0.24 m, ankle 0.26 m from the knee | thigh 0.34 m, ankle 0.54 m |
| Ankle in the lower leg's frame | constant to 1 cm over the clip | strays up to 14 cm |
| Planted foot | barely moves at touchdown, then sweeps fast | same |

## The recipe {#the-recipe}

1. **Keep the Run's length.** A clip of the same length steps with the Run, so the game can blend the two linearly
   by speed; a different length drifts out of phase in a synced blend space.
2. **Author the feet, solve the legs.** Move the `Foot` bones where the gait needs them, then turn `UpperLeg` and
   `LowerLeg` so the ankle meets them: a two-bone solve in the plane of the kit's knee, with the thigh length and
   the ankle's place in the lower leg's frame measured from the kit Run. Pull a foot out of reach back toward the
   hip (97 % of the leg) so the boot never stretches off the shin.
3. **A steady planted sweep.** In contact, cross the kit's contact length at one speed; touch down and lift off
   already moving at it (blend the swing's ends onto the sweep's line); replay the kit's swing in the rest of the
   cycle. The planted-foot speed is then the design speed, in any direction.
4. **Turn the paths for other directions.** Rotate each foot's offsets about its lane for a strafe or a backpedal;
   stagger the lanes ahead and behind on a strafe so the feet pass; turn knees and toes a third toward the step.
   Off the forward direction, replace the kit's high back-kick with an even low arc, or the backpedal lifts its foot
   in front with the toes down.
5. **Measure it the way the game does**: the planted foot (within 20 % of its own lift from its lowest point),
   sampled at 60 Hz from 0.5 s in for 5 s, linearly between frames, median of its ground speed.

## Measured {#measured}

| Clip | Design | Blender reading | Godot reading |
| --- | --- | --- | --- |
| Zombie Run (kit) | - | 5.74 m/s | 4.40 m/s |
| Zombie Sprint | 7.0 m/s sweep | 6.60 | 6.52 |
| Soldier aim clips (four ways) | 2.6 m/s | 2.60 | 2.60 (every direction) |

## What broke {#what-broke}

- **The kit's stride is already the legs' reach.** A 1.5 times longer stride on the zombie's short legs was out of
  reach by up to 18 cm; pulling the feet into reach lifted the touchdown off the ground. A faster gait shortens the
  contact (2.7 frames instead of 4) and flies further between steps instead.
- **The kit Run's speed reading is ill-conditioned**: its planted samples mix a near-still touchdown and a fast sweep,
  so the median jumps (5.7 in Blender, 4.4 in Godot; a 1.2 times stride read 9.7). A steady sweep reads the same in
  both.
- **The returning foot counted as planted** when the swing was lowered by subtracting the planted height: it came
  forward 8-12 cm off the ground, inside the planted band (and would scrape). Lift by the kit's full height and take
  the planted height off only near the ends.
- **Blender's IK constraint cannot solve these legs**: glTF-imported bones have arbitrary tails (every zombie leg
  bone is 0.518 long), so it solves the wrong lengths (100+ degrees off the kit's own legs).
- **A pose set by hand reads back as the NLA's** while the clean-up's tracks are unmuted: mute every track before
  posing and reading bone matrices.
