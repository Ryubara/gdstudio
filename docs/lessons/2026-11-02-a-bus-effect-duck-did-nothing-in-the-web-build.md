---
areas: [audio, web]
---
# The sting's duck was a bus effect, which the web build ignores

2026-11-02

- **Saw:** through the real audio service in a browser the duck measured +0.4 dB (asked -12), the rear cue +0.4 and a
  wall only its volume part (Deadnight #423, after [the finding](2026-11-01-web-samples-ignore-bus-effects.md)).
- **Cause:** the duck was an `AudioEffectAmplify` on the ducked buses; samples (the web default) skip bus effects.
- **Fix:** build every mix move from bus volume: a `Duck` bus that Effects and Ambience send to, listed before them
  in the layout, whose volume the service moves; and where a player's low-pass is not heard (samples), a few dB of
  volume instead. Measured through the real service: duck -11.9 dB for -12 asked; desktop unchanged.
- **Docs:** [Audio](../godot/audio.md#web-samples-or-streams).
