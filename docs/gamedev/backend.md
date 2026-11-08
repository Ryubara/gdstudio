# Platform backend

<!-- new section: gamedev listed no page for the service beside the game server (sign-in, lobbies, saves, reports); the
Godot page covers the client and the game server -->

The service beside the game server: sign-in, lobbies and tickets, saved progress, the reports a finished night posts.
Deadnight's is TypeScript on Node 24 with Fastify and Postgres (`spikes/backend`, its `docs/research/platform-backend.md`).
What crosses between this service and the game server is on [Netcode](netcode.md); how it is deployed is
[Railway](../studio/railway.md); how a feature that crosses services is called done is
[Multiplayer in Godot](../engines/godot/multiplayer.md#across-services).

## HTTP and Node {#http}

<!-- new section: nothing covered the traps of the backend's framework and runtime -->

- **Approach:** Authenticate in an `onRequest` hook, which runs before the body is parsed and validated, and test the
  empty-body, no-session request. **Watch out for:** Fastify validates the body before `preHandler` hooks, so a request
  with no session and an empty JSON body answered 400, not 401. **Seen:** Deadnight, 2026-11-01 (fix: the auth check
  moved to `onRequest`; a test asks for 401 with no session).
- **Approach:** Turn on `erasableSyntaxOnly` in `tsconfig.json` and write plain fields. **Watch out for:** Node 24 runs
  TypeScript by stripping types only, so constructor parameter properties, enums and namespaces, which need code
  generation, crash at start with a syntax error although `tsc` accepted them. **Seen:** Deadnight, 2026-11-01 (fix:
  the flag makes `tsc` refuse them).

## Data that crosses {#data}

<!-- new section: nothing covered what the backend's data does on its way into the game -->

- **Approach:** Do not wrap a `Dictionary.get` of server data in `int()` or `float()` unless the field can never be
  null: JSON gives a key with a null value as well as a key that is absent, and `get`'s default covers only the second.
  **Watch out for:** the backend lists a night with `round: null` until it has a round, `row.get("round", 0)` returned
  the null and `int(null)` threw in one shard of a pull request that had not touched it; the suite passed alone, so it
  read as a flake. **Seen:** Deadnight #1307, 2026-11-06 (fix: the wait compares the value without `int()`; a red in an
  untouched suite is read for its error before it is called chance).
- **Approach:** When an interface has a second store written by hand for tests (an in-memory one), give it everything
  the database does for free (a cascade, a unique key, a transaction): a pull request that adds a table with a foreign
  key adds the same cleanup to every store, with a delete test that lists every table that has the key. **Watch out
  for:** `MemoryStore.deleteUser` cleared the account and its saves but not the new ledger lines the database cascaded,
  and the two pull requests were each green against the main before the other merged. **Seen:** Deadnight #1103,
  2026-11-04 (fix: one test body `expiredGuestLeavesNoLedger` runs against both stores; the Postgres half runs against
  a throwaway `postgres:17-alpine` with `TEST_DATABASE_URL`; the whole backend suite runs on main after two merges).
- **Approach:** Make a start-up migration that two processes can run safe with a lock or `INSERT ... ON CONFLICT`, not
  with `IF NOT EXISTS`: take `pg_advisory_xact_lock(<key>)` in the transaction that runs the schema. **Watch out for:**
  `CREATE TABLE IF NOT EXISTS` only looks before it starts, so two sessions on an empty database both create the row
  type and the second hits `pg_type_typname_nsp_index`; `node --test` runs files in parallel and shows it rarely, and a
  red test that passes on rerun and names a catalog error is a race. **Seen:** Deadnight #1118, 2026-11-04 (fix: the
  lock; a test connects 12 stores at once to a fresh schema 15 times, red 5 of 5 before, green 15 of 15 after).

## Tests of the backend {#tests}

<!-- new section: nothing covered running and scoping the backend's tests locally and in CI -->

- **Approach:** A test that opens a path outside its own package names that path in the job's checkout and in the job's
  scope rule in the same pull request, and the first push is watched to green before the report says done. **Watch out
  for:** the `backend` job sparse-checked out `spikes/backend` only, so a test that holds the backend's level curve
  equal to the game's failed on `ENOENT` in CI and passed in a worktree, and a change to the curve alone would not have
  started the job. **Seen:** Deadnight #1097, 2026-11-04 (fix: the job checks out `game/gameplay/progression` and
  `ci_scope.py` starts it when those scripts change, with a self-test line).
- **Approach:** Before reporting a net change, `npm ci` in the backend folder and read the suite's statistics for `0
  skipped`; do not call a timeout a stall: run the named suite alone on the branch and on main, and run a big folder in
  chunks with a long timeout in the background. **Watch out for:** a lock on the map picker broke a suite that only CI
  ran (no Node locally, so `PASSED 0ms`), and a whole-folder run (55 suites) ended with exit 124 while node-backed
  suites paid a 90 s `/health` wait in `before_test` for each skipped test; a timed-out run leaves its children alive.
  **Seen:** Deadnight #1049, 2026-11-04 (fix: the suite gives the host the level the map needs, both cases fail when a
  move changed nothing, leftovers are stopped by PID).

## Probes against a live backend {#probes}

<!-- new section: nothing covered a probe that runs against a shared environment that is deployed all day -->

- **Approach:** A probe against a shared, continuously deployed environment acts only on rows it made (never "the first
  thing listed"), says which build it ran against and whether that changed during the run (`GET /health` names the run,
  `boot`), and ends `INCONCLUSIVE` (exit code 2) when it did; read the deployment list and the logs of the deployment
  that was live in the failing minutes before calling a failure a fault. **Watch out for:** a deployed probe failed 2
  of 16 after passing 16 of 16: it joined the first row of the list, the night it had just left, which the game server's
  `/left` removes a moment later, and the backend (lobbies live in one process's memory) was redeployed mid-run, 36 s of
  404. **Seen:** Deadnight #1240, 2026-11-05 (fix: the probe joins a row it set up and checks the left night is out).
- **Approach:** A stand-in for a player that must still be there reads its lobby every two seconds, as the real screen
  does, and the probe runs once with the wait made long on purpose. **Watch out for:** the probe's host was plain HTTP
  calls that never read the lobby again, the lobby marks a silent member away and drops it, and a software-rendered page
  that takes a minute to load arrived after the host was gone, on the CI runner only. **Seen:** Deadnight #1183,
  2026-11-05 (fix: a thread in the probe reads the lobby; a silent host with a 90 s wait fails with the CI's own seat
  list, the same wait with the reads joins).
