---
areas: [tools, tests]
---
# Stopping a background task left its Godot running

2026-11-04

- **Saw:** Deadnight's #1086: a suite was stopped with the task tool and started again after an edit. The log then failed
  a test on a message that edit had removed, and the worst count ignored the change, so the "failure" was the old run's.
- **Cause:** the stop ended the shell around the run, not the run: `timeout` and Godot lived on as children and kept writing
  to the same fixed log, beside the new run. The stop's success message says nothing about them.
- **Fix:** after a stop, list what is left (`Get-CimInstance Win32_Process`, the command line and start time) and end your
  own by process tree (`taskkill /PID <pid> /T /F`), never by name: other agents' Godots look alike until you read their
  arguments. Give each run a log of its own, so a survivor cannot pass for the new result.
- **Docs:** this file; see also [two runs in one log](../engines/godot/running-gdunit.md#logs).
