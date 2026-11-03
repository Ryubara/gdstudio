---
areas: [tools]
---
# A Wikimedia Commons fetch was rate limited and lost its metadata

2026-11-03

- **Saw:** a script downloading reference photos through the Commons API (`list=search`, then `prop=imageinfo` per
  file) died with `HTTP Error 429: Too Many Requests` after the first weapon, and on the next run with a `KeyError:
  'query'` (an `error` object in a 200 answer); the second weapon's photos were on disk with no licence entries.
- **Cause:** about two API calls a second with no back-off, and the `meta.json` (licence, author, source) written only
  once a folder was finished.
- **Fix:** wait about 1.5 s between API calls, retry a 429 or an `error` answer with a growing wait (10, 20, 30 s),
  and write the folder's `meta.json` after every file, so a crash leaves no photo without its licence.
- **Docs:** [Weapons in the Toon Shooter style](../blender/weapons.md); the photos go to `<workspace>/refs/`, never a
  repository.
