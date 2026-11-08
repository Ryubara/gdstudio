# CI and deploys

<!-- new section: the studio folder had no page on how CI and deploys run on the default branch; the hooks page covers what
runs on the machine -->

How the continuous integration runs on the default branch and how a merge reaches the live deploy: every commit of
`main` is checked, and a deploy that can skip itself is sized against the real merge rate.

## Runs on the default branch {#main-runs}

<!-- new section: the studio pages cover hooks, issues and the workspace; nothing held how CI and deploys run on the
default branch -->

- **Approach:** Use `cancel-in-progress` for pull requests only; every run on the default branch finishes. **Watch out
  for:** main's CI cancelled its run when the next merge landed, so four of five merges in three minutes were never
  checked. **Seen:** Deadnight #290, 2026-11-01 (fix: the evening review found it (Deadnight #290) and Deadnight #296
  kept the cancel to pull requests).
- **Approach:** When a job can skip itself, work out how often it skips at the real run time and merge rate and give a
  recurring skip a signal; deploy any green commit newer than the live one, and read the live commit after a merge
  someone waits on. **Watch out for:** deploy jobs skipped unless their commit was still main's head; CI took 10 to 25
  minutes and merges came every few, so every run skipped and Railway fell 13 merges behind, each skip a green job. The
  guard was tested for an older commit refused, never for any run deploying. **Seen:** Deadnight #732, 2026-11-03 (fix:
  [lesson](../lessons/2026-11-03-a-deploy-check-skipped-every-run-and-nobody-saw.md)).

## Scripts in a workflow {#workflow-scripts}

<!-- new section: the page covers when CI runs; nothing covered how a workflow's shell steps are written and linted -->

- **Approach:** Write a `run:` step so that shellcheck needs no directive: read words into an array (`read -r -a folders
  < <(cmd)`) and pass `"${folders[@]}"`; a directive is `key=value` and nothing else on its line. Run actionlint where
  `shellcheck` is installed. **Watch out for:** `# shellcheck disable=SC2086 -- reason` reads the reason as another key
  (`SC1072`, `SC1073`) and fails the `actionlint` job; actionlint checks `run:` scripts only with shellcheck installed,
  so a Windows machine without it passes what CI rejects. **Seen:** Deadnight, 2026-11-02 (fix: the unquoted `$folders`
  became an array and the directive was removed).
