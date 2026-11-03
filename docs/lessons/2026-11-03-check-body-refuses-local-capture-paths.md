---
areas: [process, tools]
---
# `gds pr check-body` said the Before and After captures were missing

2026-11-03

- **Saw:** a visual pull request body with `![after](./after.png)` lines under `Before:` and `After:` failed
  `gds pr check-body` with "the 'Before:' capture is missing", though the files exist.
- **Cause:** the check wants uploaded images (`github.com/user-attachments/...`); a relative path only becomes one when
  `gh pr create --attach ./after.png` rewrites it.
- **Fix:** check a copy of the body whose `(./name.png)` links are replaced with `(https://github.com/user-attachments/assets/name)`
  (`sed -E`), then create the pull request with the real body and `--attach` for each image, and read the description
  back for any `(./` left.
- **Docs:** this page.
