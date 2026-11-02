---
areas: [tests, input]
---
# A pad test failed only when it ran after the touch suite: the emulated left mouse button was still down

2026-11-02

- **Saw:** `test_night_pad_pause > test_the_trigger_fires_while_the_mouse_waits_for_its_lock` failed
  (`command.fire` false) in 3 of 3 shuffled runs of `tests/ui` plus the other folders of its shard, and in the pair
  `touch/test_touch_controls.gd` then `test_night_pad_pause.gd`; it passed alone and in file order, where the touch
  folder runs last. This was found while closing Deadnight #456 (a folder passes "in file order and in a shuffled
  order"), not from a red CI run, because CI always runs the same order.
- **Cause:** `test_touches_do_nothing_while_the_layer_is_off` puts a finger down on a layer that is off, so the
  engine's touch-to-mouse emulation presses the left mouse button in the `Input` singleton, and the test ends
  with the finger down. `TouchFixture.free_all` released the actions but not that button. The player's
  `trigger_held()` returns false while the mouse waits for its lock and the left button is down, which is what the
  pad test then saw.
- **Fix:** `TouchFixture.free_all` lets go of any mouse button still down (a release event, then
  `Input.flush_buffered_events()`); a test pins it. (`Input.release_pressed_events` does not exist in 4.7.)
- **Check for next time:** a fixture that sends input through the `Input` singleton (`parse_input_event`, touch
  emulation) releases everything it may have pressed when it is freed, mouse buttons included; and a folder is
  proved in a shuffled order as well as in file order (`gds`-less recipe: pass `-a res://tests/<folder>/<suite>.gd` for
  each suite in a seeded random order). Diagnose it by printing the `Input` state (`is_mouse_button_pressed`,
  `is_action_pressed`) in the failing test when it runs after the suspect.
