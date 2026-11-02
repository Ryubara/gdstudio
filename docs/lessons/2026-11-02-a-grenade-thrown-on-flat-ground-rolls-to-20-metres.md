---
areas: [gameplay]
---
# A grenade aimed at a pack 10 m away lay 17 to 26 m out, whatever the pitch

2026-11-02

- **Saw:** a bot that pitched a throw by the arc to the first touch of the ground sent every grenade far past the pack:
  the real `GrenadeArc` ended 20 to 26 m out for a 6 to 14 m aim.
- **Cause:** the grenade bounces (restitution 0.42) and rolls (3.5 m/s deceleration) for the rest of the 3 s fuse, and
  what counts is where it lies when the fuse runs out. A flat overarm throw always ends 17 m or more away.
- **Fix:** a table of real flights, one per pitch and style, made once with `GrenadeArc` on flat ground (`BotGrenadier`),
  read for the highest pitch that reaches the distance: a lob. Short throws are underarm lobs, 14 m ones steep overarm
  lobs. The blast point is checked 4 m plus a metre and a half (the landing scatter) from every teammate.
- **Docs:** [bots research page, phase 3](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).
