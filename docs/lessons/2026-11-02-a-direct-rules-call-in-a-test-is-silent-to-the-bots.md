---
areas: [tests, gameplay]
---
# A bot never learned the grenade count a test set by calling the rules directly

2026-11-02

- **Saw:** Deadnight #577. A test (and then a capture) set a bot's grenades to 0 with `rules._set_grenades(...)` and the
  bot never went to the rack: its belief stayed at the 2 it started with, so the buy rule saw a full hand.
- **Cause:** a bot only knows what the allow-listed events of a server step say. A direct call to the rules emits its
  events into the rules' queue, which is no part of a step, so no bot hears it (the same reason `SeatedNight.start_round`
  hands the rules' answer to `host.hear`).
- **Fix:** after setting state by calling the rules, tell the bots what the next step would: `night.host.hear([{type:
  &"grenade_count_changed", player_id: 1, count: 0}])`; or change the state through an action the server steps.
- **Check for next time:** a test that makes a bot do something from state it set by hand asserts first that the bot's
  belief (`perception.beliefs`) holds the new value.
- **Docs:** `docs/research/bots.md` (the economy, grenades).
