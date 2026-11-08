---
areas: [audio, blender]
---
# Speech-to-text catches audio tags the voice read aloud

2026-11-01

- **Saw:** 115 generated voice takes carried audio tags (`[laughs]`, `[sighs]`), and a tag a model reads aloud
  instead of performing is easy to miss when listening through that many takes.
- **Cause:** a text-to-speech model can speak a tag as words. ElevenLabs Scribe (`scribe_v1`, speech-to-text) writes
  performed sounds in brackets (`[laughs]`), so a performed tag comes back bracketed and a spoken one as plain words.
- **Fix:** transcribe every take and flag any whose transcript holds a tag word outside brackets; regenerate those
  (Deadnight #442: 0 of 115 flagged). Audio tags in a line are not billed, but Scribe bills the same character quota
  as speech (976 characters for 115 takes), so budget for the check.
- **Docs:** [Audio](../engines/godot/audio.md#making-sounds-with-code).
