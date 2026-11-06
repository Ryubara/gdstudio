---
areas: [general, tools]
---
# A Python edit script wrote CRLF into a GDScript file on Windows

2026-11-05

- **Saw:** after a scripted edit of `hud_reel_digit.gd`, `git diff` printed `warning: in the working copy of
  '...', CRLF will be replaced by LF the next time Git touches it`, though the file had been LF.
- **Cause:** `open(path, "w")` in Python on Windows is text mode and writes every `\n` as `\r\n`; the read in the same
  script had hidden it (text mode reads `\r\n` back as `\n`).
- **Fix:** open both ends with `newline=""` (`open(p, newline="")` to read, `open(p, "w", newline="")` to write) in an
  edit script, or strip afterwards with `sed -i 's/\r$//' <file>`; run `file <file>` (it must say `ASCII text`, not
  `with CRLF line terminators`) after any scripted edit. The hook-written CRLF of `gdformat` has the same cure.
- **Docs:** [Hooks](../hooks.md).
