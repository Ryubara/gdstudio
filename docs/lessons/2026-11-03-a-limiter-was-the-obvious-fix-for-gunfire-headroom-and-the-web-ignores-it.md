---
areas: [audio, web]
---
# A limiter was the obvious fix for gunfire headroom, and the web build ignores it

2026-11-03

- **Saw:** the player's own tommy gun, fired without a break, peaked at -1.5 dBFS alone; with a teammate's reload, a
  teammate's gun or a zombie's voice landing on a shot the mix went to 0.0 dBFS (286 samples over -1 dBFS in one 7 s
  cell). Deadnight #718.
- **Cause:** the loudest source had 1.5 dB of headroom, and peaks of unrelated sounds add: -6 dBFS plus -6 dBFS can be
  0 dBFS, and a gun at 13 shots a second puts a shot under every sound that starts. A limiter on Master is the usual
  answer, but the web build plays samples, which ignore bus effects: the same probe (the tommy gun, a hard limiter at
  -9 dB on Master) held its ceiling natively (-9.0 dBFS against -6.0 without) and did nothing in headless Chromium
  (-6.0 either way) while a bus volume of -9 dB worked in both (-15.0).
- **Fix:** headroom lives in the trims: every gun that fires without a break peaks at most 4.5 dBFS under full scale
  alone (the trims 3 to 4 dB lower, the loudness rule against the beds still met), and a capture fires each own gun
  without a break while a reload, a teammate's gun, zombie voices and world sounds land on it and counts the samples
  over -1 dBFS (1 of 25 cells after, 14 of 25 before; the one left is the one gun whose trim was not cut). Measure the
  sum, not each source.
- **Docs:** [Audio](../godot/audio.md#headroom-without-a-limiter).
