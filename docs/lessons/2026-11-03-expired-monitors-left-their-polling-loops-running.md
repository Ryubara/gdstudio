---
areas: [tools, process]
---
# Expired monitors left their polling loops running, and bash.exe windows flashed

2026-11-03

- **Saw:** the maintainer asked which agent kept opening `bash.exe`. Console windows kept flashing on the desktop. A
  10-minute log of new `bash.exe` processes showed about 700, nearly all from the coordinator's PR monitor
  (`scratch/gdstudio/main/monitor/pr-monitor.sh`), and 35 copies of that script were running, the oldest from
  01:53 the day before.
- **Cause:** the script was a `while true` loop. The Monitor tool stops a watch after 30 minutes and the
  coordinator re-arms it, but stopping the watch did not stop the loop. Each re-arm left one more copy behind, with
  no parent and no hidden console. Every poll forks several `bash.exe` (each `$(...)` and pipe in Git Bash is a
  process), and the orphaned copies had no console to hide them in, so their children showed windows.
- **Fix:** the coordinator stopped every copy. The script now ends on its own: after 29 minutes, or as soon as the
  shell that started it is gone (`kill -0 $PPID`).
- **Check:** any script given to Monitor, `run_in_background` or a scheduled task ends on its own, by a deadline and
  when its parent goes. After re-arming, count the copies (`Get-CimInstance Win32_Process` filtered on the script
  name): one, never more.
- **Docs:** [Load tests starved another project](2026-11-01-load-tests-starved-another-project.md).
