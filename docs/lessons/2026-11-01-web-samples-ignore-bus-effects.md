---
areas: [audio, web]
---
# In the web export, sounds played as samples ignore bus effects

2026-11-01

- **Saw:** the sting's duck, the rear cue and the occlusion low-pass were designed and tested natively; nobody had
  heard them in the browser, where a -12 dB `AudioEffectAmplify` changed the level by 0.1 dB and an 800 Hz
  `attenuation_filter_cutoff_hz` by 0.0 dB (Deadnight #421).
- **Cause:** Godot 4.3+ plays players in a web export as samples by default
  (`audio/general/default_playback_type.web`); samples are the browser's own buffer sources and skip bus effects and
  player filters. Bus volume still works.
- **Fix:** measured both modes with a tap on the browser's audio output; kept samples (streams crackle when the main
  thread stalls in a build with no threads) and documented what is lost.
- **Docs:** [Audio](../godot/audio.md#web-samples-or-streams).
