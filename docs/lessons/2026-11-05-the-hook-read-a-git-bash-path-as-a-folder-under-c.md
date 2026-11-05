---
areas: [tools, process]
---
# The hook read `/c/...` as `C:/c/...`, and a wrapped "Issues affected" line was refused

2026-11-05

- **Saw:** `gh pr create --body-file /c/Repositories/.../prbody.md` was refused with "the body file does not exist yet
  (looked for C:/c/Repositories/...)"; `gds pr check-body` refused an "Issues affected" entry whose second line did not
  start with `#N:`.
- **Cause:** the hook is a Windows program: a Git Bash path (`/c/...`) is resolved as a folder named `c` on the current
  drive. The body check reads each line of "Issues affected" on its own, so a line wrapped at 120 characters is read as
  a second entry with no number.
- **Fix:** write paths given to `gh` as `C:/Repositories/...` (an absolute path with the drive letter); keep each
  "Issues affected" entry on one line, short enough that it is not wrapped.
- **Docs:** none beyond this lesson (the hook's message names the path it looked for).
