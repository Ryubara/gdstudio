# Discord's URL mapping kept the /api prefix, so every backend route answered 404

2026-11-02

- **Saw:** inside the Activity the game called `/api/auth/guest` and the backend answered 404; in a plain browser,
  which calls the backend directly, the route worked.
- **Cause:** an Activity reaches outside hosts only through its URL mappings (`<id>.discordsays.com/api` to the
  backend), and the proxy forwards the path unchanged: the backend sees `/api/auth/guest`, not `/auth/guest`.
- **Fix:** the backend serves its routes with and without the mapping prefix (Deadnight #469). Test the web build
  behind the real `<id>.discordsays.com` host, or a local stand-in that keeps the prefix, before asking the
  maintainer to try it.
- **Docs:** [Web export](../godot/web-export.md#discord-activity-the-proxy-and-the-iframe).
