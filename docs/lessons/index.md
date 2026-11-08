# Lessons

Problems we hit and how we solved them, one file each: the old record. **No new file goes here** (gdstudio #769): a
mistake now updates the topic section it belongs to, found first with `gds learn <words>` ([Learning in the topic
pages](../studio/rules.md)), and `python .github/scripts/mistakes.py check` refuses a file added to this folder. The
files below stay readable, and feed `gds learn` and `gds lessons <area>`, until #770 moves each into its section.

## The old format

One problem per file, `docs/lessons/<yyyy-mm-dd>-<slug>.md`, with a required `areas:` line from
[areas.toml](areas.toml). The site's sidebar leaves this folder out ([Docs site](../studio/docs-site.md#nav)):

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
