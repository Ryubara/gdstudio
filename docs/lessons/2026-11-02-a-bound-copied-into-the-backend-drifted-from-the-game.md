---
areas: [net, backend, tests]
---
# A bound copied into the backend drifted when the game raised its cap

2026-11-02

- **Saw:** the host's rules panel (Deadnight #559) offers `max_alive` up to the game's cap. Merging #556, which raised
  that cap from 40 to 120, left the backend (`spikes/backend/src/settings.ts`, `MAX_ALIVE = 40`) refusing every value
  above 40 with `bad_settings`; the game's ticket test (`max_alive: 41` as "out of bounds") failed after the merge.
  An earlier run of the same change had found the same family of drift in a different place: the backend's JSON gives
  `max_alive` as `12.0`, which the game's strict `MatchSettings.from_dict` refused, so a lobby read back as the usual
  rules.
- **Cause:** the backend does not read the game's tuning; it holds its own copy of the bounds ("mirrors
  `MatchSettings`"), and nothing compares the two. A change on one side passes its own tests and the other side only
  disagrees at runtime. The numbers also cross JSON, which has one kind of number.
- **Fix:** raise the backend bound with the game's and move the out-of-bounds test values past the new cap. Read what the
  backend sends with one shared parser (`MatchSettings.from_json`) instead of a copy per caller. A test over a real
  backend and game server (`test_lobby_online`) is what found the float case; keep one for every value that crosses.
- **Check next time:** when a game constant is mirrored in the backend, search the backend for the old number in the
  same pull request, and put the constant's name in a comment on both sides; when a merge brings a new ceiling, run
  the real-socket suite, not only the unit tests of each side.
