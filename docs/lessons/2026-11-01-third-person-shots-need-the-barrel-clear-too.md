# A bot's shots hit the car beside it while the camera saw the zombie

2026-11-01

- **Saw:** an autopilot emptied its magazine into a car five metres away and killed nothing.
- **Cause:** the shot leaves the barrel, beside and below the camera; a corner can block the barrel and not the camera
  ray.
- **Fix:** check the line to the target from both the eye and the barrel before firing.
- **Docs:** [Godot testing](../godot/index.md#testing-and-capture).
