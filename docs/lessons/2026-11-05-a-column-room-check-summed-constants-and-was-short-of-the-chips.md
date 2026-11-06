---
areas: [godot-ui, tests]
---
# A column's "does it fit" check added up constants and was 6 units short of what the layout drew

2026-11-05

- **Saw:** the players' column on a phone (Deadnight #1301) was to take its teammates two to a row when its boxes
  stood taller than the room. The first check summed the heights from constants (`LOCAL_HEIGHT`, `COMPACT_HEIGHT`,
  `HudBotChips.CHIP_HEIGHT`) and a test that compared the sum with the laid-out column failed for every party with
  chips: 59 units drawn against 53 summed, so a column that was 6 units too tall would have counted as fitting.
- **Cause:** the chips' own constant is a minimum (25); the label inside a chip is taller (a line of 20 unit type), so
  the real row was 28. No test had set the constant against the layout, because the one test of the chips' height
  allowed 8 units of slack ("the strip adds its two rows").
- **Fix:** the decision reads the children's own minimum sizes (`HudPointsStack.height_at(columns)`), never a formula;
  a test lays out every party (1 to 8 people, with and without chips, one to a row and in pairs) and compares the
  measure with the drawn column and checks that no two boxes overlap. A test that compares a decision's measure with
  the layout must allow no slack, or the slack hides a constant that is wrong.
- **Docs:** [Players' column on a phone](https://github.com/Ryubara/deadnight/blob/main/docs/research/players-column-phone.md).
