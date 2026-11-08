---
areas: [backend, tools]
---
# `railway up` from a folder that was not linked made a new project

2026-11-02

- **Saw:** a bench service was added with `railway add --service` from the linked folder, then `railway up .` was run
  from the staging folder next to it. The CLI answered "Select a workspace", "Created project dependable-courtesy on
  Noah" and built the image there, so a stray project was running a bench beside the user's projects.
- **Cause:** the link to a project is stored per folder. A folder that was never `railway link`ed has none, and `up`
  makes a project instead of failing.
- **Fix:** run every `railway` command from the folder that is linked, and pass the staging folder as the path
  (`railway up <stage> --path-as-root --service <name> --ci`, as `deploy/server/deploy.sh` does). Read `railway status`
  first when unsure. A stray project is removed with `railway delete --project <id> --yes`; the project list then still
  shows it with a `deletedAt` two days ahead, which is the soft delete, not a failure.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#headless-server-image).
