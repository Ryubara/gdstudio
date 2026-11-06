---
areas: [ci, process]
---
# A scheduled workflow failed two nights running and told nobody

2026-11-06

- **Saw:** Deadnight's `bots-nightly` (cron 03:17 UTC, run on GitHub about 10:55 UTC) failed on 2026-11-04 and 2026-11-05
  (runs 41817408169 and 42014815270), each time in two jobs (`leak` and `report`). No issue, no pull request and no
  message followed. It was found by reading the run list for another reason, and then it turned out that the workflow had
  never been green: its first two runs were the only two it had. `ui-windowed.yml` (a scheduled windowed run of the UI
  suites) is on the same footing and its first run had not started when this was written.
- **Cause:** a push-triggered check is watched through its pull request and the merge queue; a scheduled run belongs to
  no
  pull request, and GitHub tells only the account that last edited the cron line, which here is an agent's account that
  nobody reads between tasks. The coordinator's routine (the issue list, the pull request queue) never looks at the run
  list, so a red scheduled workflow is invisible until someone happens to open Actions. Two nights of data were lost
  to this and the first red run was already the symptom of faults that had been there since the soak was built.
- **Fix (proposed, not built):**
    1. A last job in each scheduled workflow, `if: failure() && github.event_name == 'schedule'`, with `issues: write`
       on that job only, that opens one issue (`From:` line, `task` and `A-<area>` labels, the run link and the names of
       the failed jobs) unless an open issue for that workflow already exists, and otherwise adds the run to it.
       About fifteen lines of YAML, the same in every game.
    2. A kit command, `gds ci scheduled`, that prints the latest scheduled run of every workflow that has a `schedule:`
       trigger in the workspace's repositories with its conclusion and age; the coordinator reads it where it reads the
       issue list.
- **Check next time:** a pull request that adds a `schedule:` trigger also adds where its failure goes (the step above)
  and says who reads the first week of runs; and a scheduled workflow with a red first run is an issue the same day.
- **Docs:** this page; Deadnight's `docs/research/bots.md` (the first nightly runs) and `docs/research/performance.md`
  (the leak budget) hold the faults the two red runs found.
