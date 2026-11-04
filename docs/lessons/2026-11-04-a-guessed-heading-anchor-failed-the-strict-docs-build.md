---
areas: [process]
---
# A guessed heading anchor failed the strict docs build

2026-11-04

- **Saw:** the kit's `mkdocs` check failed on this pull request: a lesson linked `one-shot-effects.md#process-is-on-after-ready`
  and the strict build refused the anchor.
- **Cause:** the heading is "`_process` is on after ready"; the site's anchor keeps the underscore
  (`#_process-is-on-after-ready`). The anchor was written from the words, not looked up.
- **Fix:** copy the anchor from the built page (or build the docs) instead of guessing it.
- **Check:** run `uvx --with-requirements requirements-docs.txt mkdocs build --strict` before pushing a docs change;
  also name every model in the commit trailers on the description's `Model:` line.
