---
areas: [input, tests]
---
# A second touch tap in a test was no new press

2026-11-02

- **Saw:** a GdUnit test that tapped the touch MELEE button twice in a row expected two presses and got one
  (`Expecting: 2 but was 1`).
- **Cause:** the touch layer holds a short tap down for a minimum press and releases it on frames. The test lifted
  the finger and tapped again with no frame between, so the action was still pressed and the second tap made no new
  press edge.
- **Fix:** after the lift, wait frames (`await get_tree().process_frame`, bounded) until
  `Input.is_action_pressed(action)` is false, then tap again, as the frames of a real night do.
- **Docs:** [touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md), the
  deadnight pull request for #588.
