---
areas: [blender, tests, general]
---
# A probe's output filter hid faults, and a bone's own axis stood for a world axis

2026-11-05

- **Saw:** two small slips while fixing #1282. A probe that printed one depth per blend weight looked all clear for
  both looks and every phase, when `grep -v` of "the all-zero line" had also dropped every line that began with it (the
  table had 41 columns, the pattern 21). And the first sprint fix, an upper arm swung out "about the front-to-back axis",
  took the pistol hand from 37 to 55 mm deeper.
- **Cause:** `grep -v` on a prefix removes lines that merely start with the same text. The helper took the Torso bone's
  own Y (along the bone, up) for the world's fore-aft axis, so the arm turned about the wrong line.
- **Fix:** print only the nonzero cells (`sed 's/ [0-9]*:00//g'` leaves the faults); use the world axis (the Soldier faces
  -Y) and check the sign by where the hand should go before measuring.
- **Check next time:** a filter on a probe's table matches whole cells, not a prefix of the line; run the probe once on
  a case that must fault. A helper that turns a bone "about an axis" says in which frame the axis is, and a first
  measure that gets worse is a sign error or a frame error before it is a bad idea.
- **Docs:** Deadnight `docs/research/weapon-hold-ik.md`, "The poses #987 left over the tolerance (#1282)".
