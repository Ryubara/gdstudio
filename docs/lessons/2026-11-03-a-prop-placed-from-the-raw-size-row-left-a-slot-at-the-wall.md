---
areas: [gameplay, godot, tests]
---
# A prop placed from its raw size row left a slot at the wall and poked through it

2026-11-03

- **Saw:** two props set against a new 3.0 m end wall failed two world tests: the slot scan found a 0.29 m channel
  between the wall and a dumpster, and a "nothing of the lot lies past the wall" test found a plank 0.09 m through it.
  A stack of tyres set exactly a body's width (0.70 m) off the side wall was flagged too.
- **Cause:** the props' report (`game/assets/props/props.json`) lists `size_xzy` as `[x, depth, height]`, and the
  placement table's helper `lot_props.sizes()` turns it into `(width, height, depth)`. Centres were worked out from the
  raw row (the dumpster's 1.04 m depth read as its 1.62 m height; a 1.38 m long plank read as a depth), so each was
  off by a half-size from the wall.
- **Fix:** work a wall-side prop's centre from `sizes()`: wall face minus half its depth, a side wall's face minus half
  its width, keep a flat prop's whole length inside the wall, and touch a wall or leave clear air (0.8 m), never
  exactly a body's width. Run the scene generator and the world tests (`test_lot_gaps.gd`, the greybox test) after
  every prop move; they caught both in one run. The two tests are the
  proof, not the picture: a half-metre of a plank through a wall does not show in a capture from the field.
- **Docs:** the game's map page, "Props" ([Deadnight map](https://github.com/Ryubara/deadnight/blob/main/docs/design/map.md)).
