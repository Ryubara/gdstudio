---
areas: [tests, ci, tools]
---
# A process tree walked by parent id took the machine's orphans for the program's children

2026-11-02

- **Saw:** `test_a_headless_chrome_pointer_lock_does_not_hold_the_real_cursor` failed on `test (windows-2025)` on a
  docs-only pull request (kit #227) with `browser windows on the person's desktop: ['CASCADIA_HOSTING_WINDOW_CLASS',
  'COMTASKSWINDOWCLASS', 'CicLoaderWndClass', 'IME', 'MSCTFIME UI', 'Mozilla_firefox_...Background Tasks Profiles...',
  'WorkerW', 'Windows Terminal Admin ...', ...]`. The third flake fix on this one test in a day (kit #157, #169, #229).
- **Cause:** the test already looked only at "the program's tree" (`process_tree(pid)`), but it built the tree from
  `(pid, parent pid)` pairs alone, and a parent id proves nothing on Windows: ids are reused within seconds, and a
  process whose parent exited keeps the dead parent's id. 169 of 709 processes on a developer machine are such orphans
  (Explorer, Windows Terminal, the IME host, a Firefox background task on a runner). When a new program is given an
  id that an orphan names as its parent, the walk takes that orphan, and everything below it, for the program's
  children, and every window of the machine's shell is "a browser window on the person's desktop". The issue's own
  reading ("it takes every window that appears") was not what the code did; the log's list (`WorkerW`,
  `PushNotificationsPowerManagement`, `Windows.UI.Core.CoreWindow` are Explorer's) said it was a wrong tree.
- **Fix (kit #229):** a process is a child only if it was created after its parent (`python/tests/process_tree.py`;
  `GetProcessTimes` for each candidate), and the tree takes the root's creation time as read at `on_start`, so it is
  empty once the root exited and its id went to another program. The rule is a plain function tested on a planted
  process table (an older orphan with the root's id as its parent id, its child, a process whose time is unknown, a
  reused root) on every platform; a second test plants a hidden window in the test process and one in a grandchild and
  checks that only the grandchild's is counted. The Godot test, which walked the tree the same way, uses it too. 30
  runs on the Windows runner passed (see the pull request). A positive control came free: the browser test run inside
  `gds quiet`, where the "person's desktop" is the private one the browser also runs on, found the browser's own
  `Chrome_WidgetWin_1`, `crashpad_SessionEndWatcher` and `Base_PowerMessageWindow`, so the tree does find a real
  browser's windows. The test now skips when `GDS_QUIET=1` (it cannot tell the two desktops apart there), so the suite
  passes under `gds quiet`.
- **Check for next time:** a process tree is never "the processes whose parent id is in the set": compare creation
  times, keep the root's creation time from when it started, and treat a process you cannot open as not proven a
  child. Better still, ask the job object the program was started in (it lists exactly its processes). A program that
  has a window also gets an `IME` window from Windows, so a test asserting "no window" must look at the program's own
  tree and not expect a lone `Static`. When the same test is fixed a third time, stop and re-read the failure's
  evidence against the code before changing the design again: here the first two fixes were right and this was a
  different bug the same assertion exposed.
