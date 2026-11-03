---
areas: [audio]
---
# Equal peaks made whooshes louder than clicks

2026-11-03

- **Saw:** the first levels of the menu's sounds had the peaks in perfect order by weight, yet by loudness the screen
  change (a whoosh) was 5 LU louder than the press that caused it, and the commit sound (a rip and a punch) was 2 LU
  louder than a pistol shot of the night.
- **Cause:** levels were set by peak. Noise is louder than a click at the same peak: the momentary loudness (LUFS-M)
  of a whoosh was 8 to 10 LU over a click's.
- **Fix:** the ladder is read on the median of each weight in peak **and** in LUFS-M (3 dB or more between the rungs
  for each), whooshes sit 12 dB under the presses, the commit 3 LU under a pistol shot; `tools/audio/menu_levels.py
  levels` fails on a flat ladder in either, and a test predicts the peak from the files.
- **Docs:** [Menu and interface sounds](../audio/ui-sounds.md#4-level-the-bus-and-the-mix).
