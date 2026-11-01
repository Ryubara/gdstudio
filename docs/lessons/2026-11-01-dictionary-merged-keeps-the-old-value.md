# An override passed to `Dictionary.merged` was ignored

2026-11-01

- **Saw:** a sound's options said `max_distance` 120, but the built sound had the base's 70.
- **Cause:** `Dictionary.merged(other)` keeps the receiver's value for a key both have (`overwrite` defaults to false),
  so a default in the base silently wins over the override.
- **Fix:** pass `true` (`base.merged(options, true)`), or keep defaults out of the base; a test that reads the built
  result catches it.
- **Again:** a sound catalog's priority override was silently ignored the same way, so a special-round sting lost
  its voice to a lower-priority one. Route every override through one helper that passes `true`, and add a test that
  fails on any other `.merged(` call in that file.
- **Docs:** Deadnight `docs/research/grenades.md`.
