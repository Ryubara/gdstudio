---
areas: [gameplay, tests]
---
# A new shop spot picked from the map's numbers clashed with a window, a breaker post and a reach

2026-11-02

- **Saw:** Deadnight #577 (a grenade rack). Three places were tried on the stand's front wall: the first sat within a
  reach (3.2 m) of the shotgun's spot, so a press at the shotgun fell through to the rack; the second overlapped the
  serving window; the third stood behind the concession's breaker post, which hid the plaque in the capture. Only the
  first was caught by a test, the others by looking at the frames.
- **Cause:** the plan had a wall and an x coordinate, not the wall's cut-outs and neighbours: windows, the door and the
  breaker post are in other parts of `build_greybox.py` (`wall` cut lists, `SWITCHES`, `FUEL_STANDS`), and
  `test_shop_spots.gd` only checks distances between spots and door slabs.
- **Fix:** the rack went on the stand's east wall in the alley, clear of every cut-out and post; the spot test now lists
  the new kind. Before placing, read the groups the wall hosts (cut lists, `SWITCHES`, `FUEL_STANDS`, the shop spots) and
  capture the new thing from the side the player sees it.
- **Check for next time:** a new marker in the lot is captured from a free camera (not the player's) in the same pull
  request, and checked against every group that stands on the same wall.
- **Docs:** the game's `docs/design/map.md` (Shop spots, the grenade rack row).
