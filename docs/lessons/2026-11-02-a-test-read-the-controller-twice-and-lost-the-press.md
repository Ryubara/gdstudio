---
areas: [tests, input]
---
# A test read the controller twice a tick and the key press never reached the night

2026-11-02

- **Saw:** a real `V` key event went in, `HumanController.command()` was fed to the night every tick, and the night
  never swung, though the same press in a bare test did. The quick melee (Deadnight #411) is an edge: it is true on the
  tick the key went down, once.
- **Cause:** the test also called `controller.command(player, 1)` a second time each tick to learn which way the player
  faced (to put a zombie in reach). The controller keeps the last state of each button (`_edge`), so the first call
  took the press and the call that was sent to the night saw none. Levels (the trigger) hide this, edges do not.
- **Fix:** read the view from the camera rig (`camera_rig.aim_transform()`), never from a second `command()`; one call
  per tick, and that one is sent. A matrix row for an action with a cooldown (the same quick melee) also needs ticks
  between its bindings, or the second binding's one-tick press falls inside the cooldown and is refused: let the
  cooldown pass after each binding.
- **Docs:** Deadnight `docs/research/input-tests.md` (the matrix), [Godot animation tree](../godot/animation-tree.md)
  for the clip half of the same task.
