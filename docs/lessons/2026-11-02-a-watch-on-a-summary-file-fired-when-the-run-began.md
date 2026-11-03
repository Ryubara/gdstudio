---
areas: [process, tools]
---
# A monitor waiting for a result file fired the moment the run started

2026-11-02

- **Saw:** a monitor `until [ -f m3.summary ]` reported "finished" while the test run had just begun; the summary was
  empty.
- **Cause:** the command was `gt.sh ... | grep ... > m3.summary`: the shell creates the redirect target when the
  pipeline starts, not when it ends. The file that marks the end (`run_m3.log.clean`) is the one the script writes last.
- **Fix:** wait on the file the script writes last, or on the background task's own completion notice, never on a
  redirect target.
- **Check for next time:** before a watch on "file exists", ask which command creates it and when; a redirect target
  exists from the first second.
