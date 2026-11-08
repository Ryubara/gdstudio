---
areas: [audio]
---
# A limited crack raised the close peak more than the limiter took off

2026-11-03

- **Saw:** the boards, the door and the debris blocker were 5 to 10 LU over the beds close up once held at -9.8 dBFS
  (Deadnight #762). A limiter in their recipes took 6 to 8 dB off each file's crest, the files were normalised lower
  by that and the cap raised by the same, and the first recording read the close peaks at -7.2 to -10.3 dBFS: a torn
  board 2.8 dB higher than before, three of five over the room.
- **Cause:** the cap had been set against a close peak the distance low-pass shaped (it takes 10 to 14 dB off a click's
  peak), so the crack never reached the mix at its file's level; after limiting, the highest sample is the body's,
  which the low-pass keeps, and the crest at 1.2 m changed by less (1 to 6 dB) than in the file (3 to 7).
- **Fix:** read the close peak of each limited sound again, then set the caps from those peaks (cap = cap + the miss,
  and the file level lowered by what the limiter took off so the far level stays), and measure once more; the loudest
  400 ms at 1.2 m came back 3.5 to 6.4 LU at -9.9 dBFS or lower. A test reads the files' crest (highest sample over the
  loudest 400 ms), the table's loudness over the beds and the order of the boards.
- **Docs:** [Audio: headroom without a limiter](../engines/godot/audio.md#headroom-without-a-limiter). Check: after a change
  to a file's dynamics, never reuse the cap measured for the old file: record the close peak again and pin the new
  table.
