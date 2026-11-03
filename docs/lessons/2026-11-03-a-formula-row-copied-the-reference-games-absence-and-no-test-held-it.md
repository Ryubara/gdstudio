---
areas: [process, tests]
---
# A formula row copied the reference game's "none" and nothing checked the shipped map against it

2026-11-03

- **Saw:** the second map shipped the soda fountain, the perks and the re-cut bench (Deadnight #812), while the map
  formula (row 25) still said "nothing else to buy" and the design page called that the default. Two pages
  contradicted the scene (Deadnight #859).
- **Cause:** the formula copied what the studied game lacks (Nacht has no perks) as if it were a rule for ours, and
  marked it "maintainer's call". The pull request that added the machines changed the scene and not the row, and no
  test tied a row to the scenes, so the page stayed wrong until someone read both.
- **Fix:** the maintainer ruled that every map has the machines; the row says so, and a test reads the picker's list
  of maps and fails a scene without the fountain, the coolers, the bench or a crane place (a third map is held to it
  with no edit). Check: when a "default" in a formula is only the reference game's absence, ask once and write the
  answer where the test reads it; a pull request that adds a thing a formula row forbids fixes the row in the same
  commit.
- **Docs:** Deadnight `docs/research/maps/small-map-formula.md` (row 25) and `game/tests/world/test_map_machines.gd`.
