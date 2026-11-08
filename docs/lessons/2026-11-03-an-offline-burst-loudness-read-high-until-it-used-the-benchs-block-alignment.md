---
areas: [audio]
---
# An offline burst loudness read 1.2 dB high until it used the bench's block alignment

2026-11-03

- **Saw:** the flare gun's burst measured -18.6 LUFS in the gun bench and -17.3 on the same three Vorbis files
  mixed offline (the same trim, stereo, the shots 0.8 s apart), while one shot alone agreed to 0.2 dB (Deadnight #761).
  A reshape tuned on the offline figure would have missed the 17 LU rule.
- **Cause:** the integrated loudness of a sharp, short sound depends on where ebur128's 400 ms blocks (a 100 ms hop)
  fall on it: with the shot's onset 0.0687 s into the window (where the bench's recording puts it) the blocks lose its
  loudest first 30 ms, with the onset at 0.05 s they do not. The model had placed the shots at 0.05 s.
- **Fix:** read the onset from the recording (first sample over 1e-4 after the shot's time) and place the model's shots
  there, and keep the model's spread over a few offsets around it (+-10 ms) and over the variant orders; it then read
  -18.4 against the bench's -18.6. A denser body (the reshaped flare) is also far less sensitive to it (0.3 dB over
  all 27 variant orders, 1.3 dB for the thin crack). The bench stays the figure that goes in the table.
- **Docs:** [Audio: headroom without a limiter](../engines/godot/audio.md#headroom-without-a-limiter).
