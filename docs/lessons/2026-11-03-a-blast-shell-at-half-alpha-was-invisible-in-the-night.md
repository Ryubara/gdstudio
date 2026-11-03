---
areas: [gameplay, godot, tests]
---
# A burst drawn as one translucent shell could not be seen at night

2026-11-03

- **Saw:** the captured frames of a re-cut revolver's blast showed zombies hit (floating numbers) and no burst at all.
- **Cause:** one unshaded sphere at 55% alpha fading out fast reads as nothing against a dark lot, and the frame the
  capture happened to land on was the end of the fade.
- **Fix:** a brighter shell (80%) plus a hot core a third as wide that swells and is gone by half the time; then look
  at the frames of the shot itself (the largest PNGs after the shot are the burst), not at a fixed frame number.
- **Docs:** Deadnight `docs/design/upgrades.md#the-four-elements`.
