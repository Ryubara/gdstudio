---
areas: [blender]
---
# The commits check refused a description naming one model

2026-11-01

- **Saw:** `commits: refused - a commit names the model 'Claude Opus 5.5' in its trailer, but the description's 'Model:'
  line does not`, after an old branch got a commit from a different model.
- **Cause:** the check compares every commit's trailer with the description, and history cannot be rewritten (no
  force-push).
- **Fix:** list every model in the `Model:` line (`Claude Opus 5.5, Claude Sonnet 5.5`) and edit the description.
- **Docs:** none.
