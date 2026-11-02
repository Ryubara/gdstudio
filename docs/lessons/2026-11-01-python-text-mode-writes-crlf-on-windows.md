---
areas: [tools, input]
---
# Python `open(path, "w")` rewrites a repository's LF files as CRLF on Windows

- **Saw:** after a scripted edit, `git add` warned `CRLF will be replaced by LF`, `file` showed "with CRLF line
  terminators", and gdformat reformatted files on its own.
- **Cause:** text mode translates `\n` to `\r\n` on Windows, on every file the script rewrites; reading in text mode
  hides it.
- **Fix:** open with `newline=""` (or `newline="\n"`) for writing, or use the Edit tool, or run `sed -i 's/\r$//'` on
  the touched files before committing. `.gitattributes` keeps LF in the repository, but the noisy diffs also make
  later exact-text edits fail to match.
- **Reading too:** a script that reads a CRLF working copy and searches for `\n` strings misses them silently and
  edits nothing (Deadnight challenges, #429): open with `newline=""` and normalise `\r\n` before matching, then
  check the edit landed.
- **Docs:** none yet; a note for agents that edit files with Python on Windows.
