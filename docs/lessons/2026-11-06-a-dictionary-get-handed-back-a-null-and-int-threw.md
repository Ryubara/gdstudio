---
areas: [tests, net, general]
---
# A dictionary's get handed back a null, and int threw

2026-11-06

- **Saw:** Deadnight's `test_server_browser_online.gd` threw `Invalid call. Nonexistent 'int' constructor.` once, in a
  shard of #1306, which had not touched it. It passed 6 of 6 alone on main.
- **Cause:** the backend lists a night with `round: null` until it has a round. `row.get("round", 0)` returns the null,
  because the default is only for a key that is missing, and `int(null)` throws. The test only met it when the list was
  read in the short gap before the first round.
- **Fix:** Deadnight #1307. The condition compares the value without `int()`, so a null is simply not there yet and the
  wait goes on.
- **Check next time:** JSON gives a key with a null value as well as a key that is absent; `get`'s default covers only
  the second. Do not wrap a `get` of server data in `int()` or `float()` unless the field can never be null. A red in a
  suite a pull request did not touch that passes alone: read its error before calling it chance, because the cause may be
  a window, not a flake.
