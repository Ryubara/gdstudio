---
areas: [tests, ci, tools]
---
# A test that counted how many samples saw a state failed on a loaded runner

2026-11-02

- **Saw:** `test_a_cursor_clip_on_the_hidden_desktop_does_not_hold_the_real_cursor` failed once on `test (windows-2025)`
  in kit #110 (`assert 9 <= 6`) on a change that did not touch it; the rerun passed (kit #113).
- **Cause:** the test sampled the clip from a thread of the test process 20 times and allowed a third to be "held". That
  counts the share of time the state lasted, which is set by how the guard thread, the sampling thread and the program
  on the hidden desktop are scheduled against each other, not by what the guard does. The guard frees a clip 3 to 16 ms
  after it is set (measured on an idle machine and with four runs at once); one stalled guard or sampler on a shared
  runner moves a sample count by several, and replaying the same logic 60 times under four parallel runs gave 7 and 8
  held in 2 of them (bound 6). A guard slowed to 0.1 s fails the old test with `10 <= 6`, which is what a starved runner
  looks like.
- **Fix (kit #113):** measure what the guard promises, not a ratio. The program on the hidden desktop sets the clip and
  times how long it lasts by polling it, 10 times; the test asserts every clip is freed within 1 s (far above any stall,
  far below "never freed", which is what a missing guard gives). A second test checks the guard loop against a fake
  `user32`: it frees repeatedly while the program runs and once more at the end, with nothing timed. Over 60 runs under
  four parallel runs the new test failed 0 times, and it still fails with the guard removed.
- **Check for next time:** a test of a time-based guard asserts a latency bound the guard can only miss by being absent
  (seconds, measured at the source of the event), or a count of calls against a fake; never "at most N of M samples saw
  it", whose N is a guess about the scheduler. Reproduce a flake by injecting the delay (here the guard's period), not by
  waiting for the runner.
