---
areas: [process]
---
# A lesson linked AGENTS.md and the strict docs build refused it

2026-11-03

- **Saw:** the kit's `mkdocs` check failed on a lesson pull request (kit #432): the lesson "contains a link
  '../../AGENTS.md#commits-and-pull-requests', but the target '../AGENTS.md' is not found among documentation files".
- **Cause:** `AGENTS.md` sits at the repository root, outside `docs/`, so the site has no page for it, and
  `mkdocs build --strict` turns a link to a file it does not publish into an error.
- **Fix:** name the file in code (`AGENTS.md`, its section in quotes) and link a docs page that covers the rule
  (`docs/hooks.md`).
- **Check:** run `uvx --with-requirements requirements-docs.txt mkdocs build --strict` before pushing a docs change, and
  link only files under `docs/`.
