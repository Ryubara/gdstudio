---
areas: [process, tools]
---
# A corrections row copied from a game agent's draft kept a relative link to a game page

2026-11-04

- **Saw:** kit #478 failed `mkdocs --strict`: "contains a link 'dead-contact.md', but the target
  'research/dead-contact.md' is not found". The coordinator had pasted the #914 agent's drafted row onto the kit's
  corrections page without reading its links.
- **Cause:** the agent wrote the row in the game's terms: `[The player and the dead](dead-contact.md)` points at
  Deadnight's `docs/research/dead-contact.md`, which sits beside the game's research pages, not the kit's. A relative
  link is resolved against the page that holds it, so the same text that was right in the game is broken in the kit.
  The local build was skipped for this one-row PR, so CI found it.
- **Fix:** name a page of another repository as text (Deadnight's `docs/research/dead-contact.md`) or by its full
  GitHub URL; relative links only to kit pages. Before publishing a drafted row, check every link in it and run
  `mkdocs build --strict`, even for one row.
- **See also:** [a link to a heading the other repository's page lacked](2026-11-02-a-docs-link-named-a-heading-the-other-repository-page-lacked.md).
