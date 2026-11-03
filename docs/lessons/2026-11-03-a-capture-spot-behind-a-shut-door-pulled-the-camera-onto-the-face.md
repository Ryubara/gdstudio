---
areas: [tests, camera]
---
# A capture spot just inside a shut door pulled the shoulder camera onto the player's face

2026-11-03

- **Saw:** a "from the yard's gate" capture (Deadnight #853) stood the player at the gate (z -2.5) and showed his face
  filling half the frame; the yard behind him was cut off.
- **Cause:** the yard's door is shut until it is bought, and its slab is solid; the spring arm hit it 1 m behind the
  player and pulled the camera in to the head. The body also kept its spawn facing, so it looked at the camera.
- **Fix:** stand a capture spot at least the arm's length (2.8 m) clear of any closed door or wall behind it, and set the
  body's facing to the camera's yaw (`state.facing` and `rotation.y`) when posing it; look at the first frame of each
  spot before taking numbers from it, since a pulled-in camera also changes the draw counts.
- **Docs:** Deadnight `game/tests/captures/generator_views.gd` (the spots and the pose).
