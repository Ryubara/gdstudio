---
areas: [audio]
---
# A layer over a gun's shot was either inaudible or took its headroom

2026-11-03

- **Saw:** the first re-cut layer (a sweep, a ring and a sub pulse, trimmed 18 dB under the shot) lifted a rifle's burst
  peak by 0.7 dB and a shotgun's by 0.8 dB (the guns peak at -4.5 to -5.5 dBFS and nothing may pass -4.5), and was not
  heard: the tail of the shot (0.08 to 0.5 s after the report) was +0.3 dB for the revolver and -0.3 dB for the rifle.
- **Cause:** the layer started with the shot, so its loudest moment (a sweep and a click) landed on the report's peak, where
  amplitudes add; and its own crest was 16 dB, so at a level its peak could afford its body was 25 dB under the report's.
  A gun's energy is almost all in its first 50 ms (the tail is 14 dB under), so the place a layer is audible is after
  that, not on top of it.
- **Fix:** bake a 30 ms lead-in into the layer's file (the crack is over, as a tail starts late), make its body dense with
  a limited crest of 7 dB (`limit_crest` run three times: one pass leaves the crest 5 dB over, because limiting also
  lowers the loudest 400 ms it was measured against) and give it a ring that pulses and lasts. Then choose its trim on a
  model: add the rendered layer to the recorded plain shots of the gun bench at a few gains and read the peak, the tail
  and the 2 to 8 kHz band against the plain shot. At -16 dB the peak added was 0.0 to 0.1 dB and the layer stood
  14 to 26 dB over the shot's own tail in the bright band. The bench confirms it.
- **Docs:** [Audio: a layer over a peaking sound](../godot/audio.md#a-layer-over-a-sound-that-already-peaks).
