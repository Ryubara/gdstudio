---
areas: [web, tests]
---
# A browser probe held the grenade before the first round and read "not cooking"

2026-11-05

- **Saw:** `touch_weapon_places.py` (Deadnight #1280) held a finger on the grenades' place and the game reported no
  cook, though the arc showed and the finger was down: `grenade_cooking` false, the count unchanged.
- **Cause:** the rules refuse `use_grenade` until the first round is on; a solo night starts in its intro ("ROUND 00,
  NEXT IN 0"), so the server rejected the cook and the client's own preview went on drawing it. The probe waited for a
  running night, which is earlier than an active round.
- **Fix:** wait for `round >= 1` before a probe that needs the rules to say yes (a grenade, a purchase, a revive), and
  read the server's own word (`grenade_cooking`: `GrenadeServer.is_cooking`), not the preview on screen.
- **Docs:** [Web export](../engines/godot/web-export.md) (probes read the server, not the picture).
