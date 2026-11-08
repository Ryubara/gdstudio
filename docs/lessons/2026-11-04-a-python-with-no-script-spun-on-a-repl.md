---
areas: [tools]
---
# A `python -` left in a command spun on a broken REPL until the timeout

2026-11-04

- **Saw:** a Bash command ran into its 120 s limit, printing `_pyrepl` tracebacks (`OSError: [WinError 123]`) over and
  over, and none of the steps after it had run.
- **Cause:** a leftover `python -` with an empty heredoc started Python's interactive prompt in a shell with no
  console, and the prompt fails and retries for ever. The same command's `sed` with `\n` in a Python pattern had put
  real line breaks in a script, so a failure sat in front of the hang as well.
- **Fix:** stop the task, then run each Python step with a script file, `timeout` and `</dev/null`, so that a prompt
  ends at once. Change a scripted edit by rewriting its file with the Write tool, not with `sed` on escapes. Write long
  files with the Write tool too ([large heredocs](../engines/godot/headless-probes.md#writing-a-probe)).
- **Docs:** this page.
