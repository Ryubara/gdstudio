---
areas: [gameplay, camera, net]
---
# A hip-fire shot left before the body turned

2026-11-02

- **Saw:** a hip-fire press while the body faced away from the view fired at once, through the player's back, and the
  body turned afterwards (the maintainer, Deadnight #477).
- **Cause:** the server shot on the trigger alone (`if command.fire: _shoot`). The body's turn was a second result of
  the same trigger, and nothing made the shot wait for it. Every test started with the body facing the view or waited
  for the turn before it counted hits, so none asked what leaves on the first tick from a back-facing body.
- **Fix:** the one deterministic simulation that both the server and the predicting client run computes `shot_ready`:
  the trigger or a buffered press, with the body within a tolerance of the view (or the aim button held). The server
  shoots on it. A tap is a buffered rising edge, so a press during the turn fires when the turn ends (Deadnight #488).
  For each state (turning, reloading, swapping), decide whether the action leaves, waits or is cancelled, and test it
  from the worst starting state.
- **Docs:** Deadnight `docs/research/hip-fire.md` ("Turn first, then shoot"), with the tolerance, buffer and turn-rate
  numbers; [What to plan from the start](../studio/plan-from-the-start.md).
