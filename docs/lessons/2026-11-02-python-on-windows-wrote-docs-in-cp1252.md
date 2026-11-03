---
areas: [tools]
---
# A Python edit on Windows wrote a page in cp1252 and the docs build failed

2026-11-02

- **Saw:** `mkdocs build --strict` stopped with `'utf-8' codec can't decode byte 0xb2` in a page an agent had
  edited with a short Python script; git also warned that several files now had CRLF line ends.
- **Cause:** `Path.read_text()` and `write_text()` with no `encoding` use the Windows code page (cp1252) and turn
  `\n` into `\r\n`: the page's old UTF-8 bytes went through unchanged, but the new `m²` was written as one cp1252
  byte.
- **Fix:** in edit scripts use `read_text(encoding="utf-8")` and `write_bytes(text.encode("utf-8"))` (or the Edit
  tool); before committing, run the docs build and `file <paths>` to catch CRLF and non-UTF-8 files.
- **Docs:** this lesson.
