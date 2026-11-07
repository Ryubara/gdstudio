---
areas: [gameplay, process]
---
# A map met every row of its formula and did not make sense to a player

2026-11-03

- **Saw:** the maintainer, playing Deadnight's second map: both floors looked out on the same flat land; too many
  windows on the ground floor; a window above the stairs; perks side by side. The map passed
  every formula row and every window test (Deadnight #917).
- **Cause:** the map was built to a formula of counts and distances (five, three and four windows; spawns 5 to 15 m
  out; each room's dead reaching that room only). To hold the last row, the generator gave every room's windows
  "ground of their own": a bank raised to the upper floor's height behind the building and the hall's roof walked by
  the dead, so both floors looked out on flat land at their sills. Five windows went in one wall line because the count
  asked for five, and one upper window landed over a stairwell (#824). Every check measured a number; none asked what a
  person standing there sees outside each window, or why the dead come from there.
- **Fix:** the map was laid out again from a written and drawn proposal: one yard at one level, the drive-in in front
  of the hall's window, the hall's roof a terrace and a gallery the dead reach by an outside stair, one window a wall
  downstairs and three upstairs each onto that deck, each perk in its own alcove. The "only its room" row became "in by
  its own window". Tests fail a window with no floor inside it or no ground or deck outside it at its own height, and an
  upper window whose dead do not rise on the yard and climb to it; both fail on the old map.
- **Check:** before building, and again from the player's camera, write for every opening what is outside it at its
  sill and the dead's way to it from the world's ground; the outside is one place from every floor; a structure built
  only so a count holds is a sign the count is wrong for this map, not that the map should bend.
- **Docs:** [Map review: does it make sense?](../godot/map-review.md#does-it-make-sense),
  [Level design P19](../research/level-design.md#p19-the-place-makes-sense-to-a-player); Deadnight
  `docs/design/smallmap.md`, "Outside and windows".
