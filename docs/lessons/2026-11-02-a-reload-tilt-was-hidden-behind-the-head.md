---
areas: [camera, gameplay, tests]
---
# A reload tilt that passed its test was hidden behind the head

2026-11-02

- **Saw:** players missed reloads (Deadnight #683) although #383 tilted the weapon 35 degrees down for every reload
  and its test checked the barrel's pitch tick by tick. Counting the gun's pixels from the shoulder camera, the tommy
  gun showed 284 at rest and 0 during its reload.
- **Cause:** the shoulder camera sits 0.6 m right and 2.3 m behind; the chibi Soldier's head covers the space in front
  of his chest, where a hip-held gun is, and tilting it down took it further behind him. The test measured the pose,
  not what the camera draws, and the captures were side views.
- **Fix:** a motion per mechanism that carries the weapon out to the right of the head and up, turns the chest the
  left shoulder forward so the left hand reaches, and moves a part of the gun; proved by drawing the frame again without
  the weapon (6,700 to 8,700 pixels for the long guns mid-reload) and by sheets from the player's camera.
- **Docs:** [Measuring an effect on the screen](../engines/godot/measuring-effects-on-screen.md#a-held-weapon-from-the-shoulder-camera),
  [Moving parts and a reload's ammunition](../tools/blender/weapons.md#moving-parts-and-a-reloads-ammunition).
