---
areas: [backend, tests, ci]
---
# `CREATE TABLE IF NOT EXISTS` failed when two sessions ran it at once on an empty database

2026-11-04

- **Saw:** Deadnight's `backend` job went red on `main` (#1118) in a test that touched no changed code: `Postgres keeps
  the envelope, exact strings and optimistic concurrency` failed at `PgStore.connect` with `duplicate key value
  violates unique constraint "pg_type_typname_nsp_index"`, Key (typname, typnamespace)=(users, 2200). A failure that
  depends on timing and names no changed code looks like a flake.
- **Cause:** `connect` ran the schema (`CREATE TABLE IF NOT EXISTS ...`) with a plain `pool.query`. `IF NOT EXISTS` only
  checks for the table before it starts: two sessions that both see no table both go on to create its row type, and
  the second one hits the catalog's unique index. `node --test` runs test files in parallel, so two files connecting
  to a fresh database at the same moment race; two backend instances starting together on a new database race the same
  way. The race only shows when the tables do not exist yet, which is why it appeared rarely.
- **Fix:** the schema runs in one transaction that first takes `pg_advisory_xact_lock(<key of the schema>)`, so a second
  session waits, then finds the tables and changes nothing; a pool that failed to start is closed. The proof is a
  test that connects 12 stores at once to a fresh throwaway schema (`search_path`), 15 times: it failed 5 runs of 5
  before the fix (the same error) and passed 15 runs of 15 after (225 empty-schema starts). Check for next time: a
  start-up migration that two processes can run is made safe by a lock or by `INSERT ... ON CONFLICT`, not by
  `IF NOT EXISTS`; a red test that "passes on the rerun" and names a catalog error is a race to reproduce with
  concurrency, not to retry.
- **Docs:** none yet beyond this file; [Lessons](index.md).
