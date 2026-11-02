---
areas: [tools]
---
# gdformat and gdlint skip untracked scripts

2026-11-01

- **Saw:** pre-commit passed, then failed on the same scripts after they were committed.
- **Cause:** the gdformat and gdlint hooks only check tracked files.
- **Fix:** `git add` new scripts before running `uvx pre-commit run --all-files`.
- **Docs:** Deadnight `docs/research/rules-engine.md`.
