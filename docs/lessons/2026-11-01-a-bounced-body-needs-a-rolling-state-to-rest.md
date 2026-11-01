# A thrown body bounced forever and never came to rest

2026-11-01

- **Saw:** a scripted grenade bounced with restitution alone: ever smaller hops, and on a fixed 60 Hz step gravity
  re-made a tiny bounce every step, so it never rested and positions drifted in the last digits.
- **Cause:** restitution scales a speed that gravity keeps refilling; nothing turns contact into rest.
- **Fix:** a floor bounce slower than a threshold along the normal moves the body into a rolling state: gravity along
  the slope only, friction against the motion, a floor probe each step so a ledge ends the roll, and a stop speed. Test
  rest, a ledge fall, repeatability and no tunnelling at 60 m/s.
- **Docs:** Deadnight `docs/research/grenades.md`.
