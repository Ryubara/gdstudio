---
areas: [audio, tests]
---
# Two voice lines queued in the same instant both waited for the same moment, and the second was dropped

2026-11-04

- **Saw:** two players levelled up in one server tick; the soldier cheered one and the other never played, though the
  one-player case and the "queue after the line that speaks" test passed (Deadnight #1063).
- **Cause:** a queue-after-the-line helper reads "how long until the channel is free" when it is called, and the channel
  was still free for both calls. Both lines were scheduled for the same instant; the first started, the second found the
  channel busy and a cheer cannot cut a cheer. A wait computed before the first line commits is the wait of an empty
  channel. A hand-stepped test with one big step hides it the other way (the director's clock ends the step before
  the schedule's callbacks run).
- **Fix:** one queue of lines said one after another: say the front line, and when it started (or was refused with the
  channel free) schedule the next after the channel's wait; when it was held back, retry after that wait (never less
  than a few hundredths, so a big test step cannot spin). Test two speakers at once in small steps (0.1 s).
- **Docs:** [audio: a queue of cheers](../godot/audio.md#a-queue-of-lines-said-one-after-another).
