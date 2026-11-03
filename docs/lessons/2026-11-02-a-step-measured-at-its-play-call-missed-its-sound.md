---
areas: [audio, tests]
---
# A reload step measured at its play call missed its sound

2026-11-02

- **Saw:** measuring whether reload steps were heard under fire (Deadnight #683), the pouch came out at -39 dBFS and
  the lever at -23, though their files peak at -5 and -4; the plot showed both sounding after the window.
- **Cause:** under Movie Maker a sound starts 40 to 60 ms after the frame that called `play`, and a step's loudest part
  can come later in its file (the pouch's snap at 0.1 s, the lever's clack at 0.2 s); an 80 ms window from the call saw
  the quiet start. A search span longer than the gap to the next step then found the next step's peak instead.
- **Fix:** render the reload alone and find each step in that track, from its call to the next step's call (at most
  0.45 s), and compare it with the gunfire in the 80 ms around its own loudest moment, by octave band.
- **Docs:** [Audio: Is a sound heard under fire?](../godot/audio.md#is-a-sound-heard-under-fire).
