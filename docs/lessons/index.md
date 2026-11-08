# Lessons

Problems we hit and how we solved them. Before solving something, search these pages: it may have happened before.

## Adding a lesson

One problem per file: `docs/lessons/<yyyy-mm-dd>-<slug>.md`, where the slug is a few words of the problem in
lowercase with hyphens. Every file here builds as a page that search finds and links reach, without any list to
edit, so adding a lesson never touches a shared file and never conflicts with another pull request. The site's sidebar
leaves this folder out until gdstudio #770 moves it ([Docs site](../studio/docs-site.md#nav)).

The `areas:` line is required: pick from [areas.toml](areas.toml) (the names and what each covers). The mistakes
glossary is built from it by `gds lessons <area>`; it is not a file in the repository, so there is nothing to render or
commit, and two lesson pull requests never conflict on it. `python .github/scripts/mistakes.py check` (pre-commit, pytest
and the docs job of CI) fails on a lesson with no area or an unknown one.

```markdown
---
areas: [net, web]
---
# Short statement of the problem

2026-11-01

- **Saw:** what you observed, with the exact error text if there is one.
- **Cause:** why it happened.
- **Fix:** what solved it.
- **Docs:** [the page that now covers it](../engines/godot/index.md).
```
