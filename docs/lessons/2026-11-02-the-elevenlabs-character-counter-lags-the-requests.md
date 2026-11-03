---
areas: [audio]
---
# The ElevenLabs character counter lags the requests

2026-11-02

- **Saw:** after 115 text-to-speech requests `/v1/user/subscription` said 3,419 characters used; after 115
  transcripts it said 6,333, then 6,457 a minute later. Read at face value, the transcripts looked three times dearer
  than the male set's (about 3,000 against 976).
- **Cause:** the counter is updated some time after a request, so a reading right after a batch is too low and the
  difference to the next reading is not that batch's cost. Only the total, read after a pause, is reliable.
- **Fix:** estimate a batch from what the last set billed (speech: about 1.08 times the characters without audio tags;
  Scribe: about 8.5 per take of 4 s), read the total once after the last request, and record the total, not the
  differences between readings. Deadnight #679: 6,457 of 10,000 for 115 lines and their check.
- **Docs:** [Voice lines](../audio/voice-lines.md#credits-and-budget).
