---
areas: [tools, general]
---
# A Python edit wrote CRLF line endings into GDScript files

2026-11-03

- **Saw:** after editing `.gd` and `.md` files with `python -c "open(p,'w').write(s)"` on Windows, git warned
  "CRLF will be replaced by LF" and the diff showed whole files changed.
- **Cause:** text mode `open(..., 'w')` translates `\n` to `\r\n` on Windows (and reading translated `\r\n` away, so a
  replace worked, but the write added them back).
- **Fix:** open with `newline=''` for both read and write (and `encoding='utf-8'`), or use the Edit tool; check with
  `git diff --stat` and `sed -i 's/\r$//' <files>` if it already happened.
- **Docs:** this page.
