---
areas: [net, backend, tests]
---
# An in-memory store kept the rows the database deleted with their account

2026-11-04

- **Saw:** Deadnight's #1097 added a ledger table to the backend `Store` with `ON DELETE CASCADE` on the account, and a
  ledger map to `MemoryStore`, but `MemoryStore.deleteUser` still cleared only the account and its saves.
  A Guest deleted after 7 days (#1085) left its ledger lines behind in the memory store only (#1103). The same two
  merges left four `guest_account` tests red: they wrote a bare `{ xp: 120 }` to the `profile` slot, which #1097
  now validates.
- **Cause:** one interface, two stores, and the second one is written by hand to copy what the database does for free
  (a cascade, a unique key, a transaction). The new table was tested in each store, but the delete was only tested for
  the old table (saves), so nothing asked "what else belongs to this account". The two pull requests were each green
  against `main` as it was before the other merged.
- **Fix:** `MemoryStore.deleteUser` clears the account's ledger lines; one test body (`expiredGuestLeavesNoLedger`)
  runs against both stores, and a report posted afterwards for the deleted account pays nobody (`unknown_user`). The
  Postgres half of a backend test is run, not skipped, against a throwaway `postgres:17-alpine` container
  (`TEST_DATABASE_URL`) before the report says the counts. Check for next time: a pull request that adds a table with
  a foreign key adds the same-named cleanup to every store that has no database, and a delete test that lists every
  table that has the key; after two backend pull requests merge, the whole backend suite is run on `main`.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
