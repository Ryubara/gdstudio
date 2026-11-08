---
areas: [audio, godot]
---
# Two arrays for the same duration differed by one sample

2026-11-01

- **Saw:** `ValueError: operands could not be broadcast together with shapes (30870,) (30869,)` while mixing a 0.7 s
  noise layer with its envelope.
- **Cause:** `int(0.7 * 44100)` is 30869 (the product is 30869.999...) while another helper rounded to 30870.
- **Fix:** One `samples(seconds)` helper that rounds, used everywhere a duration becomes a length
  (`tools/audio/dsp.py`).
- **Docs:** [Audio](../engines/godot/audio.md#making-sounds-with-code)
