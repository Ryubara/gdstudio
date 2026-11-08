---
areas: [godot-ui, input]
---
# A phone was built as a keyboard on glass, and every button passed its tests

2026-11-05

- **Saw:** the maintainer on Deadnight's phone controls (#1275 to #1280): the phone was still the desktop
  version with touch buttons and the whole interface needed a redesign; a swap button repeated the weapon display a
  player could tap instead; and aimed auto-fire did not reload at 0.
- **Cause:** touch was built by giving each desktop action a button, because the layer presses the game's input actions
  (`game/ui/touch/touch_controls.gd`) and "nothing else forks". That kept the code simple and made the phone a keyboard
  on glass. Each button passed its size, safe-area and floor tests, so no test could say there were too many, or that a
  HUD element already on screen did the job. The earlier corrections show the same thing: the phone was fixed one
  complaint at a time (Deadnight #470, #599), never designed.
- **Fix:** the rework is Deadnight's #1275 to #1280 (still open), with reload at 0 on every device in #1278. Check for
  next time: before building controls for a device, list every action and every element on the screen for that device
  and give each a verdict (keep, make the existing element tappable, drop as a duplicate). A control count and a
  duplicate check are a design review, not a size test; a button that repeats what a visible element shows is a bug.
  Reload at 0, and any rule the player expects from every device, is proved through each device's real input path.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed);
  [What to plan from the start](../studio/plan-from-the-start.md).
