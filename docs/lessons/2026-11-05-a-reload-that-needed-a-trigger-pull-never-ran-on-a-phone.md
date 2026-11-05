---
areas: [gameplay, input]
---
# A reload that needed a trigger pull never ran for a phone aiming with auto-fire

2026-11-05

- **Saw:** the maintainer, aiming with auto-fire on a phone, emptied the magazine and nothing reloaded
  (Deadnight #1278). With a mouse held down it did reload.
- **Cause:** the only automatic reload was the server refusing a shot at an empty gun (`fire_block` `empty`), so the
  rule lived on an input edge, not on the state "dry gun in hand". Auto-fire (`TouchAimAssist.wants_fire`) stops
  pulling the trigger at 0 rounds, so no shot was ever refused. The same hole was open on every device: a trigger let
  go after the last round, and a swap back to a dry gun, left it dry. Every earlier test pressed Reload or held the
  trigger.
- **Fix:** the server checks the state each tick (`NightServer._reload_if_dry`): gun in hand, magazine 0, reserve above
  0, not reloading, not a bot, nothing to say when it cannot. The tests press the real keys, buttons and a finger on
  Aim and read the server's weapon state, from the worst start (the trigger already let go).
- **Docs:** [Weapons: a dry gun reloads by itself](https://github.com/Ryubara/deadnight/blob/main/docs/design/weapons.md);
  check for next time: a rule that follows from a state ("empty", "downed", "in the light") is evaluated from the state
  every tick on the server, never as a side effect of an action that a control can stop sending; a test lets go of
  every input at the moment the state arrives.
