---
areas: [tests]
---
# A capture spot outside the room had no floor

2026-11-03

- **Saw:** the backdrop tour's yard shot showed the sky and a band of horizon: the player had fallen through the world.
- **Cause:** the blockout room's floor covered the room only, and the backdrop's ground has no collision (nothing
  walks it).
- **Fix:** a hidden floor under every spot the capture uses; look at every spot's frame before believing the tour.
- **Docs:** [A backdrop past the playable bounds](../engines/godot/compat-lighting.md#a-backdrop-past-the-playable-bounds).
