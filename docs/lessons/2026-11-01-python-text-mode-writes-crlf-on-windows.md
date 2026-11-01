# Python `open(path, "w")` rewrites a repository's LF files as CRLF on Windows

- **Saw:** after a scripted edit, `git add` warned `CRLF will be replaced by LF`, and gdformat reformatted files on its
  own.
- **Cause:** text mode translates `\n` to `\r\n` on Windows, on every file the script rewrites.
- **Fix:** open with `newline="\n"` for writing (and read normally), or run `sed -i 's/\r$//'` on the touched files
  before committing.
- **Docs:** none yet; a note for agents that edit files with Python on Windows.
