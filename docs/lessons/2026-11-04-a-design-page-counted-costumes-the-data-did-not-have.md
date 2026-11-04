---
areas: [godot-ui, tests, process]
---
# A design page counted four starting costumes and the data has two

2026-11-04

- **Saw:** the Costumes tab issue asked for "the four starting costumes lit at level 1"; built from the data, a level 1
  player has two (Soda jerk, Carhop). The #1065 agent had found the same and left it as a note.
- **Cause:** the plan was written from the idea ("four presets of starting pieces") before anyone counted the twelve
  presets' pieces against the ladder. Rolled sleeves (level 4) and the boots (12) sit in most of the others.
- **Fix:** count a design claim against the data before a test is written to it. The test computes each costume's level
  from the same tables the game reads, pins the real number with a comment, and the report names the gap as a question
  for the maintainer instead of re-dressing presets or moving a level quietly.
- **Docs:** [Deadnight's customization page](https://github.com/Ryubara/deadnight/blob/main/docs/design/customization.md#costumes).
