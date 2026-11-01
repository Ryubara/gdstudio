# TextServer.name_to_tag is not static

2026-11-01

- **Saw:** calling `TextServer.name_to_tag("wght")` to set a variable font axis failed to parse.
- **Cause:** it is an instance method of the text server, not a static function.
- **Fix:** `TextServerManager.get_primary_interface().name_to_tag("wght")`. Also check a specimen font in the real
  title text: one face's G read as a J in "DEADNIGHT".
- **Docs:** Deadnight `docs/research/type-specimens.md`.
