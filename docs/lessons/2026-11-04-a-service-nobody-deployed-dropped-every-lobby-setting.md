---
areas: [backend, net, ci, tests]
---
# The backend nobody deployed dropped every setting a host chose, and every test passed

2026-11-04

- **Saw:** the maintainer made a multiplayer lobby, set a second map, bots and the multipliers, and every night was the
  usual one on the drive-in with no bots (Deadnight #944). The lobby said "Something went wrong (Not Found). Try again."
  and went on.
- **Cause:** one thing, not six: the live `backend` service was last deployed on 2026-11-02, two hours before the
  change that gave the lobby its rules landed, and the `ci` workflow deployed the web build and the game server on every
  merge but never the backend. The old backend answered the rules' route with a 404, ignored the `settings` a start
  carries and sent lobbies with none, so the ticket had none and the room used the defaults. Every test of the rules
  ran a backend built from the checkout, so every test passed while the real one was two weeks of changes behind. The
  silent part made it last: nothing named the missing setting (a 404 is not a refusal of a key), and the game server
  ignores a key it does not know.
- **Fix:** every service a feature needs is deployed by the pipeline that merges the feature (`deploy-backend`, with the
  same skip of an older build); a deploy ends by asking the live service what it takes (`/health` lists its settings
  keys) and fails when that differs from the client's keys; an unknown key is an error that names it at every border
  (backend, ticket, command line) and a 404 on the rules' route is said to the host; and one test per setting runs the
  real client, backend and game server and reads the value back from the running night.
- **Check for next time:** when a game feature crosses a service (client, backend, game server), find out how each
  service gets deployed before calling it done: a service with no deploy job is a service that is behind. Test each
  value by its key through the real stack and read it back from the end of the path, never from what was sent; and make
  the deploy compare the versions of the services it joins (a keys list, a version) so a stale one fails a job, not a
  player. A boundary that drops what it does not know is the same mistake: refuse it by name.
- **Docs:** the game's `docs/research/platform-backend.md#a-setting-is-never-dropped-944` and
  `docs/research/ci-jobs.md`.
