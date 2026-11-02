---
areas: [web, tests, audio]
---
# A project setting injected as `audio/...` under `[audio]` did nothing

2026-11-02

- **Saw:** a browser probe asked for streams (`default_playback_type.web=0`) but the game's own players still played
  as samples: no filter, no duck (Deadnight #423). Its `--latency` option had been dead the same way.
- **Cause:** the probe wrote `audio/general/default_playback_type.web=0` inside an `[audio]` section of
  `project.godot`. In that section the key is `general/default_playback_type.web`; the full path is an unknown key and
  is ignored without a message. The setting's values (0 stream, 1 sample) are also not
  `AudioServer.PlaybackType`'s (1 stream, 2 sample), so a code check against the enum read the wrong thing.
- **Fix:** write the key without its section, compare with the setting's own numbers, and confirm a settings switch
  with a level measurement in the browser before trusting it.
- **Docs:** [Audio](../godot/audio.md#web-samples-or-streams).
