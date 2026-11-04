---
areas: [ci]
---
# An apt cache keyed by the runner image missed on the very next run

2026-11-04

- **Saw:** Deadnight #1112 cached the `.deb` files of the web job's browser install under a key with the runner's
  `ImageVersion`; the second run, 20 minutes later, logged `Cache not found` for it (`20261101.360.1` after
  `20261026.354.1`).
- **Cause:** GitHub's `ubuntu-24.04` pool serves more than one image version at a time, so an exact image key hits only
  by luck. The key was also not needed for correctness: apt takes the cached files whose version it wants and fetches
  the others.
- **Fix:** `restore-keys: <prefix without the image>` for any image's newest entry; copy only the `.deb` files fetched
  now (find them with `-cnewer <marker file>`: apt gives a download the server's modification time, so `-newermt` misses
  them) into the folder and drop versions that are not installed, so entries do not collect old versions. The log line
  `Need to get 0 B/21.1 MB of archives` is the proof of a warm run.
- **Docs:** Deadnight's `docs/research/ci-time.md`, "The web job".
