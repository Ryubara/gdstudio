---
areas: [general, tools]
---
# A reflow script swallowed a constant into a comment

2026-11-04

- **Saw:** after wrapping the over-long comments the linter named, `--import` failed: `Identifier "SETTINGS_SCENE" not
  declared`. The line `const SETTINGS_SCENE := ...` had been joined into the comment above it.
- **Cause:** the script took the flagged line numbers once and edited several places of one file; the first edit added
  a line, so every later number pointed one line too high, and the block it rewrapped began on a code line.
- **Fix:** put the constant back and wrap by hand. A script that edits several places of one file works from the end
  of the file upwards, or finds its place again after each edit; after any scripted edit run the import (or the
  linter) and read `git diff` for the lines it touched. The import only loads what the game uses: the same script had
  swallowed a constant in a test file too, and that showed only when the suite ran (`Identifier "OPEN_VIEW" not
  declared`), so run the suites of every file it touched.
- **Docs:** none needed beyond this lesson.
