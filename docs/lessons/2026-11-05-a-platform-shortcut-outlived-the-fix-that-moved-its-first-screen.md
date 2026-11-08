---
areas: [net, web, process]
---
# A platform shortcut outlived the fix that moved only its first screen

2026-11-05

- **Saw:** the maintainer found that Play together in the Activity made a lobby on the first press, and that a second
  player doing the same got a lobby of their own instead of joining the maintainer's (Deadnight #1178).
  The Discord Activity skipped the Play together screen (no code field, no create button) and made the lobby of its instance.
- **Cause:** Deadnight #495 said "a platform entry point is still the same game", and its fix (#531) made the Activity
  open on the main menu. The check it left read "name the screen the platform opens on", so it passed: the Activity did
  open on the menu. The shortcut stayed one press later, in `_use_activity_room` and the backend's `byInstance`, and a
  new feature (the voice channel's night) kept being built on it. The instance id is a client claim and not one room
  per voice channel, so players who launched separately never met.
- **Why the #495 check missed it:** it was about boot routing, one screen, and the review compared screens, not what
  each press does. A shortcut is a branch on the platform (`instance_id`, `ActivityRoom.current`, a field only the
  Activity sends), and nobody listed the branches.
- **Fix:** removed the instance routing from the game and the backend, not only the call: no `preview_instance`, no
  `findByInstance`, no instance id on `POST /lobbies` (a stale client that still sends one is ignored). The Activity
  keeps only its sign-in. A test boots the Activity and fails on any request that makes or reads a lobby when Play
  together opens; the harness shows the Activity's screen beside the website's.
- **Check for next time:** grep for every branch on the platform and justify each one against the website; a fix for
  "the platform skips X" removes what X needed too.
- **Docs:** [the corrections row](../studio/maintainer-corrections.md) and
  [what to plan from the start](../studio/plan-from-the-start.md#platforms).
