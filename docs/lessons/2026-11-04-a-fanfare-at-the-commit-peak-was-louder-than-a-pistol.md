---
areas: [audio]
---
# A fanfare at the peak the table gave was louder than a pistol and hid a groan

2026-11-04

- **Saw:** a level-up cue made to the issue's peaks (2 dB over the menu's commit, -10.3 dBFS in the mix)
  played in a fight stood 4 dB over a zombie's groan from 6 m in the groan's own band, 2.4 dB over a soldier's
  urgent line, and had a loudest 400 ms of -18.5 LUFS-M against a pistol shot's -24.5, with the peaks of the
  two within 0.3 dB of each other.
- **Cause:** equal peaks are not equal loudness or equal masking. A brass note is sustained and narrow-band, a
  shot is a click; at the same peak the note is 6 LU louder over 400 ms and sits on top of the groan's whole
  band for a second. The menu's ladder is read against the menu, so it never saw the fight.
- **Fix:** record the cues through the real service next to the sounds they must not hide (shot, groan,
  shriek, beep, a soldier's line), put the two together (the mix is linear), and gate the reference's loudest
  moment in its own band (80 percent of its energy; 10 ms for a click, 50 ms for the rest) over the cue's by 6
  dB. Then a trim for the context: the cues are 10 dB under their menu level while a night runs, and still
  stand out of a burst of automatic fire in 2 to 6 third-octave bands. The peak in a table of a ticket is a
  menu level, not a fight level.
- **Docs:** [Menu and interface sounds, section 4](../audio/ui-sounds.md#4-level-the-bus-and-the-mix).
