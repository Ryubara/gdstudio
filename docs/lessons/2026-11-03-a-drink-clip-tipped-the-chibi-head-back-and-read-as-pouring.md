---
areas: [blender]
---
# A drink clip that tipped the chibi head back read in the game as pouring the bottle over it

2026-11-03

- **Saw:** Deadnight's perk drink (#912) was solved in Blender with the bottle's lip on the mouth at every key (0 mm
  off) and the head tipped back 18 to 24 degrees with the neck and chest, as a person drinks. In the game capture from
  the side the head lay back so far that the bottle stood over the top of the head: it read as pouring, not drinking.
  From the shoulder camera behind him the bottle was hidden by the head for the whole drink.
- **Cause:** the kit head is a third of the body and its origin is low at the neck, so a few degrees at the neck move
  the face a long way, and the mouth (which the lip follows) rises with it. The front-view contact sheet hid it: the
  hand covered the face there. And a bottle brought to the mouth from straight ahead sits behind the head from the
  camera over the right shoulder.
- **Fix:** the head tips back 3 to 9 degrees in all (neck and chest less), the bottle comes to the mouth from his right
  (its bottom 56 to 58 degrees round to the right and raised 100 to 135 degrees from upright), so the arm and the bottle
  show beside the head. Checked in the game from the side, from a teammate's place and from the shoulder camera.
- **Check for next time:** pose anything that moves the kit head in the game's own captures (side and the shoulder
  camera) after the first build; a pose right in a front sheet can be wrong on a head this big.
- **Docs:** [Rig sharing, a prop to the mouth](../blender/rig-sharing.md#a-held-prop-to-the-mouth).
