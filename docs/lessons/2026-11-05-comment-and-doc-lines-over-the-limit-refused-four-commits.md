---
areas: [godot-ui, tools]
---
# Comment and doc lines over the limit refused one commit four times

2026-11-05

- **Saw:** a commit of a UI fix was refused four times in a row: `gdlint` (`Max allowed line length (100)`) on four
  comment lines, then `markdownlint` (`MD013`, 120) on one research line, then two more, then one more.
- **Cause:** a scripted edit replaced `62` with `64` and added words inside existing comment and doc lines, so they
  grew past the limit; each hook stops at its first failing group and a commit runs them in turn, so each fix showed
  the next. A line check run with `awk` covered only the `.gd` files, not the Markdown.
- **Fix:** after a scripted text edit, check every touched file for both limits before the commit
  (`awk 'length>100'` on `.gd`, `length>120` on `.md`), or run `uvx pre-commit run --all-files` once and fix all of
  its output in one pass; rewrap by hand, never leave a long line for the hook to find.
- **Check for next time:** a scripted word or number change in a comment is a change to its line length: measure the
  lines it touched, in every file type it touched.
- **Docs:** [Hooks](../studio/hooks.md).
