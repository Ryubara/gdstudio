---
areas: [tests]
---
# A Movie Maker frame shows the state one step late

2026-11-01

- **Saw:** the frame numbered N already showed a change made at step N.
- **Cause:** frame N is written after that step's script code ran.
- **Fix:** read frame N-1 to see the state before a change; frames are always at the project viewport size.
- **Docs:** [Capture](../studio/capture.md).
