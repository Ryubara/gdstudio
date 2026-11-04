---
areas: [tools, general]
---
# gdformat wrote CRLF and a scripted edit missed its text

2026-11-04

- **Saw:** after a commit refused by the hooks, a Python edit's `assert old in text` failed on a text copied from the
  file, and git warned `CRLF will be replaced by LF`.
- **Cause:** the `gdformat` hook reformatted the files in place on Windows and wrote CRLF.
- **Fix:** after a hook has rewritten a file, `sed -i 's/\r$//' <files>` before the next scripted edit, and keep the
  assert: it stopped the edit before it did anything.
- **Docs:** none: the formatter's line endings are the tool's.
