---
areas: [gameplay, process]
---
# A wall-tier rule judged on damage per hit put the melee weapons on the walls

2026-11-03

- **Saw:** the maintainer ruled that melee weapons are too strong to sell on the walls (Deadnight #910).
  The second map sold a crowbar, a bat and an axe from its walls.
- **Cause:** the wall-tier rule (#858) ranked weapons on one axis, damage per hit, and `WallTier.TIERS` listed the
  crowbar, bat and axe as tier 1 "hand", the lowest a wall may sell; the second map's generator kept three melee wall
  spots. A melee weapon never runs dry, needs no reload and no locker rounds, so it is strong on the axis the rule
  never named.
- **Fix:** melee is box-only by its kind (`WeaponDef.is_melee`), whatever the table says; the three wall spots are
  removed, not reused, and a test checks every wall spot of every map against the kind.
- **Check next time:** when a rule says "weaker" or "stronger", write down every axis it is judged on (per-hit damage,
  ammunition and reload upkeep, range, reach), and class a weapon of another kind by its kind, not by a table row that
  someone can add.
