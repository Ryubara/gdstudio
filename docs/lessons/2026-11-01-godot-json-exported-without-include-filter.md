# `*.json` was said to be missing from a web export; in Godot 4.7.2 it is not

2026-11-01

- **Saw:** docs said a web export loses a `.json` data file unless `*.json` is in the export filter; an export with an
  empty include filter has the identical `.pck` (same md5) and the screen that reads the file loads in Chromium.
- **Cause:** Godot 4.4 and later treat `.json` as a resource type, so `all_resources` exports it with no import file.
  Other plain files (`.cfg`, `.txt`, `.csv`) still need the filter.
- **Fix:** keep `*.json` in the filter as insurance, and prove a plain-file dependency by opening the screen that reads
  it in a browser, not by assuming.
- **Docs:** Deadnight `docs/research/web-export.md`.
