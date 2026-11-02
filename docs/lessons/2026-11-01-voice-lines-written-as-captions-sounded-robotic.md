# Voice lines written as captions sounded robotic

2026-11-01

- **Saw:** the maintainer heard the first soldier sample (ElevenLabs v3, a stock deep voice, audio tags) and found it
  "a bit robotic and like an AI": "Reload... catch your breath" where a person would say "Reloading!" or "Jeez, gotta
  catch my breath real quick".
- **Cause:** the line was written as an instruction describing the event, not as the character reacting to it. Text to
  speech reads clipped imperative text like a narrator, whatever the voice and the tags.
- **Fix:** write barks the way a person talks under stress: first person, contractions, a filler or a breath, an
  exclamation where it fits, uneven length. Put the emotion in the words first and the audio tags second, keep the
  model's stability low enough for expression, and write several variants per event so the game never repeats one
  back to back (Deadnight #384).
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
