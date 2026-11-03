---
areas: [audio, general]
---
# A percent cut was taken from the wrong base

2026-11-03

- **Saw:** the maintainer asked twice for quieter crickets: "25%" (#382), then "50%" (#781). Each was turned into dB
  and laid on top of the level of that day: -16 to -18.5 dB, then -18.5 to -24.5 dB. When the coordinator asked whether
  "50%" meant half the amplitude or half as loud to the ear, the maintainer answered: "when I first said 50% I was
  talking about making it 50% quieter from what it was originally". Neither the base nor the scale had been asked.
- **Cause:** a percentage has a base and a scale, and neither was in the words. The agents took the base as the current
  level (each request stacked on the last one) and the scale as amplitude (50% = -6 dB), because those were the easy
  sums. The maintainer meant the original level and how loud it sounds; half as loud to the ear is about -10 dB.
- **Fix:** crickets at -26 dB: the original -16 less 10 dB. The chirp rate is already half of the original, because the
  first cut never touched it.
- **Check:** when someone asks for "N% quieter", "N% louder", "N% faster" or "N% more" of something already changed
  once, take the base as the original unless they say otherwise. Write the base and the scale (amplitude or perceived)
  in the issue and the pull request, and for loudness use the perceived scale: half as loud is -10 dB. Ask only when the
  two readings go opposite ways from the current value.
