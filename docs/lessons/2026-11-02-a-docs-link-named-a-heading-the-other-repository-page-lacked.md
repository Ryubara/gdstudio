---
areas: [process]
---
# A docs link named a heading that the page in this repository did not have

2026-11-02

- **Saw:** the `mkdocs` check of Deadnight pull request 648 failed on the first push: `Doc file 'research/hit-blood.md'
  contains a link 'first-use-hitches.md#particle-systems-...', but the doc ... does not contain an anchor`.
- **Cause:** the heading was copied from the kit's page of the same name (`docs/engines/godot/first-use-hitches.md`),
  which has
  a section the game's own page does not. Same file name, different page; the link was never built before the push.
- **Fix:** link the page without the anchor, or read the target's own headings (`grep -n '^## '`) before writing the
  anchor.
- **Check for next time:** run `uvx --with-requirements requirements-docs.txt mkdocs build --strict` in the repository
  that holds the page before the first push of any change that adds a docs link; a link to a heading is only as good as
  the headings of that repository's copy.
- **Docs:** [Docs rules](../studio/hooks.md#docs).
