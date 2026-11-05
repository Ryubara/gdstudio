---
areas: [general, tools]
---
# A scripted edit put a real line break inside a GDScript string, and it still parsed

2026-11-04

- **Saw:** a helper that joined lines with `"\n".join(lines)` came out of a Python edit script as `return "` and
  `".join(lines)` on two lines. GDScript accepts a string with a raw line break, so the import and the capture ran and
  the title was right (the line break meant the same); only reading `git diff` showed the damage to the
  source. The same session a shell heredoc with quotes inside it failed with `unexpected EOF while looking for
  matching`.
- **Cause:** the replacement text was written in a Python string where `\n` is already a line break, in a heredoc the
  shell had read first. Two layers of escaping around code that is itself about escapes.
- **Fix:** write an edit script that has a quote or a backslash in it to a file with the Write tool and run the file
  (never a heredoc), double a backslash that must reach the file (`"\\n"`), and read the changed lines of
  `git diff` after any scripted edit, because a parser that accepts the wrong text will not say so. Python's text mode
  on Windows also wrote CRLF again here: open with `newline=""`.
- **Docs:** [the CRLF lesson](2026-11-03-python-write-turned-gd-files-into-crlf.md) and the checks of
  `gds lessons general`.
