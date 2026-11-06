---
areas: [tests, godot-ui]
---
# A fixed count of frames raced the client and failed half the runs

2026-11-05

- **Saw:** Deadnight's `test_the_button_comes_with_a_dead_in_reach_and_goes_when_it_is_gone` (#1296) failed about half
  its runs, 4 of 8 on main and 3 of 6 on #1300, and first showed as a red shard on #1300, which had not touched it. It
  landed green because a suite run a few times can pass by chance.
- **Cause:** the test moved the dead away, ran two ticks and waited two frames, then asserted the button had gone. The
  client's frame and the layer's read of it each land a frame or so after a tick, so at that moment the frame could still
  hold the old position, or the frame was new and the layer had not read it. The game was right one tick later, every
  time.
- **Fix:** Deadnight #1302. A bounded wait on the state the test asserts (`_until_the_button_is`): a tick a frame, at
  most 30, then the same assertion, so a button that never comes or goes still fails. 0 of 12 runs failed.
- **Check next time:** a test over a live night waits for the state, inside a bound, never for a count of frames. A red
  in a suite a pull request did not touch: run that suite six to eight times alone, on the pull request and on main,
  before deciding it is either's fault. A new suite that reads the client runs ten times alone before it is called green.
