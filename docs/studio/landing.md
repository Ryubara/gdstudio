# Landing a pull request

<!-- new section: starting-work.md reached 46 KB with the landing entries of gdstudio #1193 still to come; landing and
merging main are one subject, the end of a pull request, apart from starting an issue -->

How a pull request reaches `main` once its work is done: the order the queue is landed in, the refresh before a merge,
auto-merge and the hand merges, and merging `main` into a branch. Starting the work is on
[Starting work](starting-work.md); the guards that refuse a merge on [Hooks](hooks.md#what-it-refuses).

## Landing pull requests {#landing}

Open pull requests come before new work: each one left open goes stale against `main` and makes the next harder.

- **Land, then start.** Each time the queue is read, a red `main` is fixed first, then every conflicting or failing
  pull request gets an owner, oldest first, before new feature work starts. On 2026-11-01 pull requests stacked up red
  and conflicting for hours while new ones kept landing, and each merge made the old ones worse; on 2026-11-02, 21 were
  open with 33 jobs queued.
- **Land what you would recommend.** A pull request the coordinator would recommend is refreshed and landed, and its
  trade-off reported afterwards, so the maintainer can reverse it. It is not parked behind "merge? recommended". Only
  `S-hold` ([Hooks: the hold](hooks-hold.md#hold)), a maintainer decision of `AGENTS.md`, or having no recommendation waits
  for the maintainer.
- **Refresh a parked pull request.** One whose last run is older than recent merges to `main` gets `main` merged in and
  its checks rerun before it lands, even when GitHub says CLEAN: CLEAN only says the text merges and the last checks
  passed, and new commits that look unrelated are no exception. Several land one at a time. On 2026-11-06 three parked
  pull requests landed unrefreshed and `main` went red: a shorter reload met a test added after its last run; on
  2026-11-10 #972 and #977 landed past unrelated-looking commits, and #954 nearly did the same with #986 and #989.
- **Not on a red main.** While a `CI failing on the default branch` issue is open, only its fix forward (a body
  saying `Fixes #<that issue>`) lands; the merge guard refuses the rest ([Red main](hooks-red-main.md#red-main)), and
  the required `main-green` check stops auto-merge too, then turns green when the issue closes ([CI](ci.md#main-runs)).
  Refreshing a branch with `gds merge-main` still works, and is the step before landing once the fix is on `main`.
- **Not in a paused repository.** A paused repository's pull requests are out of the queue: none is refreshed,
  rerun or landed, open ones stay as drafts, and `gds merge-main` and `gds pr` refuse them
  ([Pausing a game](starting-work.md#paused)). Landing what you would recommend does not reach past the pause.
- **Hand-merge paths** (`AGENTS.md`: conventions, `AGENTS.md`, settings, hooks, `tools.toml`) are merged by hand, never
  by auto-merge, by the maintainer or by an agent the maintainer has authorized for it.

- **Approach:** After `gds merge-main`, rerun the suites the branch touches as CI runs them now (`gds template test`
  defaults to CI's `--fixed-fps 60`; `--real-clock` opts out) and every web probe of the branch, before pushing.
  **Watch out for:** a branch that was green meets what `main` gained meanwhile: a new clock for the suites, a new
  main menu in front of the probe. **Seen:** gdstudio #903 (PR #935), 2026-11-10: the local run on the real clock
  passed 876 cases while CI failed 5 socket cases, and the web probe stopped at the new menu (fix: the command
  defaults to the CI clock, a test pins it against `ci.yml`, kit #976).

- **Approach:** Look up the owner of any pull request red for over 30 minutes and assign one at once if none is live;
  when an agent is moved to other work, hand each pull request it leaves to someone. **Watch out for:** every open pull
  request needs a live owner: #488's owner was moved to probes and the pull request dropped off the owner map, so its
  hung `godot` job sat red about 80 minutes; it was not a model-capability problem. **Seen:** Deadnight #488, 2026-11-02
  (fix: `gds issue list` shows every issue in progress with its owner and pull request and calls out the ones with none
  ([Looking](starting-work.md#looking))).

- **Approach:** Before opening a new pull request, fix a red `main` and check that every older open one has a live owner
  and moved in the last hour; work the queue oldest first, one pull request per agent, only on files no open one
  touches; start each status report with the old ones; rerun a known flake at the head of the queue at once (`gh run
  rerun <id> --failed`) and file it. **Watch out for:** parallel pull requests touched the same files, a flaky check
  stalled `main`, and a pull request in work looks abandoned from GitHub, so Deadnight #402 sat four hours on a flake.
  **Seen:** Deadnight, 2026-11-01; Deadnight #402, 2026-11-02 (fix: `S-conflict` and `S-ci-failing` kept in sync
  (kit #76)); gdstudio #1145, 2026-11-11 (pushed while main's stalls flake #1125 was open: the same flake failed its
  template job; push after the fix lands and `gds merge-main`).
- **Approach:** Rerun the balance gate on `main` after each merge that touches tuning, and let one balance owner rebase
  on the others. **Watch out for:** two pull requests each passed the gate alone (#260 changed speeds, #271 the crane
  price) and broke it once both were on `main`. **Seen:** Deadnight #260 and #271, 2026-11-01 (fix: the gate on the next
  pull request caught it).
- **Approach:** Land a fix several pull requests need once and have the rest merge `main`; parallel agents add their own
  rows to shared docs tables and never reword others', and the coordinator names the shared files in each prompt.
  **Watch out for:** five parallel art pull requests added rows to the same two docs and three rewrote one test with the
  same fix; auto-merge lands the first green pull request, not the oldest, so merge order only picks who settles a
  clash. **Seen:** Deadnight #655, #656, #660 and #661, 2026-11-03 (fix: the rule above).
- **Approach:** Before asking whether to merge, check the maintainer decisions list and `S-hold`; if neither applies and
  you would recommend the pull request, refresh it, land it, and report the trade-off afterwards. **Watch out for:** the
  coordinator had decided, then parked green pull requests for a yes though merging is not a maintainer decision, and
  each handoff carried the parked state on. **Seen:** Deadnight #1199, #1244 and #1252, 2026-11-06 (fix: land what you
  would recommend, above).

- **Approach:** Before pushing a follow-up commit to a branch that has a pull request, run `gh pr view <branch> --json
  state -q .state`; when it is `MERGED`, branch from `origin/main`, cherry-pick the commit and open a new pull request,
  and put every doc a task needs into the first pull request before turning auto-merge on. **Watch out for:** on a green
  docs pull request `--auto` merges within a minute, so a later push goes to a branch whose pull request is closed; the
  Stop gate looks for kit branches with commits and no pull request, and this one had one. **Seen:** gdstudio #175
  and #176, 2026-11-02; gdstudio, 2026-11-05 (fix: a new branch and pull request each time; the hooks name a branch that
  holds commits `main` lacks).
- **Approach:** Turn auto-merge on only after the proof is read: when the test plan is a long run, every job of that run
  (`gh run view <id> --json jobs`, none queued or in progress, each conclusion explained, named in the body), and turn
  it off in the same step as asking for changes. **Watch out for:** on a green, clean pull request `--auto` merges at
  once, so the step is a merge, not a setting: a pull request the maintainer meant to see first merged past its hold, a
  nightly fix merged before its dispatch finished a job that failed on a limit it had called harmless, and a pull
  request with stale numbers landed before the three fixes asked for. **Seen:** Deadnight #1115, 2026-11-04 (fix: the
  hold is a label and a required check, [Hooks](hooks-hold.md#hold)); Deadnight #1324, 2026-11-06; Deadnight #1084,
  2026-11-04.

- **Approach:** Before any merge call (`gh pr merge`, with or without `--auto`, or `gh api .../pulls/<n>/merge`), have
  the head contain the current tip of its base: `gds merge-main --path <worktree>`, push once, wait for the checks on
  that head. The merge guard asks GitHub, not the local clone, to compare `base...head`, refuses when `behind_by` is
  above 0 and names the missing commits; when GitHub cannot be asked the call goes through with a warning, so read
  `mergeStateStatus` yourself ([Hooks](hooks.md#what-it-refuses)). **Watch out for:** a pull request can be CLEAN and
  green on a head that never met the newest commits of `main`, and the new commits looked unrelated. **Seen:** gdstudio
  #972 (two commits behind) and #977 (#956 and #959), 2026-11-10, unrefreshed; on 2026-11-06 the same turned
  `main` red (fix: the guard, kit #982); gdstudio #1199, 2026-11-11 (three behind at first push).

- **Approach:** On a pull request off the hand-merge paths, with no `S-hold` and no long proof run still to read,
  turn auto-merge on (`gh pr merge --squash --auto`) in the step right after the refresh push, then read the checks.
  **Watch out for:** waiting for green to merge by hand gives `main` the length of a CI run to move again, so the
  merge guard refused the head as behind and a second refresh cost a second run; auto-merge lands the head the
  moment its required checks pass. **Seen:** gdstudio #1117 (PR #1152), 2026-11-11.
- **Approach:** Before turning auto-merge on, and again whenever a check of yours goes red, run
  `gh issue list --search "CI failing on the default branch" --state open`. While one is open, keep auto-merge off
  (`gh pr merge <n> --disable-auto`) and land by hand once its fix is on `main`, after `gds merge-main`. Follow the
  task's own landing words when they are stricter (for example "once green"). **Watch out for:** auto-merge went on
  as the pull request opened, then the runner's DNS failed for the template job's browser install, on `main` too, and
  #1224 opened while the pull request still had auto-merge on. A rerun going green would have landed it on a red
  `main`. **Seen:** gdstudio #1208 (PR #1219), 2026-11-11 (fix: auto-merge turned off until #1224 is closed); gdstudio #1099
  on top of #1125, 2026-11-11, the count read in the merge's own command line (fix: the guard, kit #1135).
- **Approach:** Push in one command and call `gh pr merge` (or the merge API) in a later one, once the push is done.
  **Watch out for:** the merge guard runs before the whole command and asks GitHub for the head it has, so in
  `git push && gh pr merge ...` it judged the head before the push and refused it as behind `main`. **Seen:** gdstudio
  #1150 and #1131, 2026-11-11; gdstudio #1221 (PR #1225), 2026-11-11 (`gds merge-main && git push && gh pr merge`
  in one command: run the refresh, the push and the merge as three commands).
- **Approach:** When a required check fails on the runner's network (a package mirror, DNS, a download), not on the
  code, rerun the failed jobs once (`gh run rerun <id> --failed`); when the same step fails again, check for or file
  the red-`main` issue (`CI failing on the default branch`, as #1224 was), land its fix, then `gds merge-main` and
  rerun. **Watch out for:** a third and fourth rerun on a mirror outage only queue more jobs, and the pull requests
  whose template job failed on the browser install stay red until each merges the fix: #1215, #1195 and #1218 after
  #1226. **Seen:** gdstudio #1224 (apt mirror DNS outage, fix PR #1226), 2026-11-11.
- **Approach:** A pull request that must take in another one's merge first (its numbers or its test assume that work
  on `main`) keeps auto-merge off until `gds merge-main` has brought that merge in and its checks ran on it; say so in
  the body. **Watch out for:** with auto-merge on, #1220 went green and landed before #1208 was on `main`, so the
  numbers it documented were measured without the work they described and a docs pull request (#1229) followed.
  **Seen:** gdstudio #1218 (PR #1220), 2026-11-11.
- **Approach:** While a pull request waits under `S-hold`, leave `main` alone: merge it only when the pull request is
  DIRTY when you report; the coordinator refreshes it right before it lands. **Watch out for:** an agent merged `main`
  into a held pull request four times while waiting on CI, each push restarting a full run that `main` outran again,
  and the briefs had not said that a held pull request need not chase `main`. **Seen:** gdstudio #1154 (PR #1195) and
  #1084 (PR #1171), 2026-11-11 (fix: the batch brief says it; coordinator's mistake).

**Landing a green head behind `main` (the coordinator's practice since 2026-11-11, a maintainer question).** A hand
merge on a busy day can starve: `main` takes a new commit before each full CI run ends, so the refresh above never
catches up (#1202 went through three refreshes). The coordinator's landing script now lands a green head that is
behind when every commit `main` gained since the head's base touches no file the pull request changes and `git
merge-tree` merges the two cleanly; otherwise it refreshes. Branch protection does not require an up-to-date head, so
GitHub takes the merge; the [merge guard](hooks.md#what-it-refuses) refuses a behind head from a shell command, so
this is the script's route only. It relaxes "Refresh a parked pull request" above, which exists because unrelated
commits broke `main` before; whether it stays is for the maintainer to decide, and agents keep refreshing as above.

## Merging main into a pull request {#merging-main-into-a-pull-request}

Merge `origin/main` into the branch only when the pull request is DIRTY or `main` broke one of its checks: every push
restarts its CI. A pull request parked for a while is refreshed before it lands ([above](#landing)). Test the merge
locally first, and push once. The merge commit's message is checked like any other: it
ends with the single `Co-Authored-By` trailer and nothing after it. `gds merge-main` makes that commit:

```bash
uv run --project <workspace>/repos/gdstudio/python gds merge-main     # in the worktree
# conflicts: it stops, lists the files and leaves the merge in progress; fix them, git add each, then
uv run --project <workspace>/repos/gdstudio/python gds merge-main --continue
```

It fetches `origin/main`, merges with `--no-commit`, and commits with the whole message from a file
(`git commit --cleanup=strip -F`): `Merge origin/main into <branch>`, a blank line, and the `Co-Authored-By` line of the
branch's newest commit (`--co-author "<model> <noreply address>"` names another). It refuses a dirty tree and a branch
that already has `main`. Never `git merge -m ...` and `git commit --no-edit` a merge that had conflicts: git adds a
`# Conflicts:` paragraph after the message, which pushes the trailer out of the last paragraph and fails `pr-rules`. The
`pre-push` hook now stops
such a commit before it leaves the machine ([Hooks](hooks.md#pre-push)); reword it with
`git commit --amend --cleanup=strip -F <message file>`. A commit that is already pushed cannot be reworded without a
force push, which is the maintainer's decision: open the same change from a new branch instead.

- **Approach:** Push only when a merge needs it (DIRTY, or `main` broke a check) and merge `main` locally for tests;
  read `gh run list --status queued` and the open count each cycle, and when the queue grows stop new pull requests,
  land the oldest, and land a flake's fix first. **Watch out for:** with many agents CI is the bottleneck: with 21 open,
  20 jobs running and 33 queued, every push restarted a 15-minute run and about ten workflows. **Seen:** Deadnight #447,
  2026-11-02 (fix: the rule above).
- **Approach:** After a merge of `main`, conflicted or not, read the diff of every test file against `main` and run
  `gds check scripts` (or the template's test) before pushing. **Watch out for:** a merge of `main` doubled a step in a
  test, so the branch failed for a reason the change never had; `main` retyping a shared property (the loadout's
  `slots` to `Array[Resource]`) leaves the branch's new lines on the old type, which merge cleanly and fail to parse.
  **Seen:** Deadnight, 2026-11-01 (fix: the night suite caught it after the merge); gdstudio #1258, 2026-11-11 (an
  inventory test from #1040 still typed `Array[WeaponDef]`; fix: retyped after the template check failed;
  then a new export met the pins test `main` had added since).
- **Approach:** When a branch moves a shared asset path (a body, a model), grep the merged tree for the old path after
  `gds merge-main`, in tests and in scenes, and run the full template suite, not only the suites the branch touched.
  **Watch out for:** a scene and a suite that landed on `main` after the branch started still use the old path, so
  the merge is clean but they fail. **Seen:** gdstudio #1298 on #1187, 2026-11-11 (the online enemy look and
  `test_net_ai_section.gd` from #1243 still used the Quaternius male).

- **Approach:** Commit a merge of `main` the moment its conflicts are resolved, through `gds merge-main` (the message
  from a file, nothing after the trailer); run `uvx pre-commit run --files <resolved files>` before `--continue`, run it
  unpiped, and check that `git log -1` shows the merge before rebuilding or pushing. **Watch out for:** a hand-written
  title (`ui: Merge main into x`) is refused (`Merge` is not a verb on the list); `--continue` commits through
  pre-commit, where a 155-character licence line met the 120 limit, a merge staged for hours met `gdlint` at 1,016
  lines, and two `Seen:` lists joined in a conflict passed the 900-character rule limit. **Seen:** Deadnight #539,
  #656 and #410, 2026-11-02; gdstudio #1023, 2026-11-10 (merged with `--no-edit`); gdstudio #1256, 2026-11-11.
- **Approach:** Never push a merge of another open pull request's branch: build the parts that do not need it and merge
  after it lands. If you must build on it, keep your own work as a patch of your commits (`git diff <that branch's tip>
  HEAD > mine.patch`, saved outside the worktree), `git reset --hard origin/main` on the unpushed branch and `git apply
  --3way mine.patch`; a pull request stacked on a hand-merged sync one takes its own side of the synced files, runs `gds
  sync <game>` and `gds sync --check`, and says what it is stacked on. **Watch out for:** a squash merge writes a commit
  no branch contains, so 17 files conflicted with none of the agent's own lines, and `.claude/gds-sync.json` and
  `groundwork.py` conflicted on identical content. **Seen:** Deadnight #230 on
  #643, 2026-11-03; Deadnight #575 on #571, 2026-11-02; gdstudio #1291 on #1040, 2026-11-11.
- **Approach:** After every `gds merge-main`, diff the branch against `origin/main` for each file it shares with a
  merged pull request (`git diff origin/main -- <file>`), delete the branch's own copy of a fix `main` landed, and drop
  a workaround whose blocking issue has closed. **Watch out for:** a clean textual merge hid a second copy: a stub
  `has_voice` and a `near_only` grip option stayed beside the real female voices and the same far-hand fix that `main`
  had landed. **Seen:** Deadnight #678, 2026-11-03 (fix: the branch wired to `main`'s mechanism, the workaround and its
  test dropped).
- **Approach:** A commit you add to another agent's pull request (a resolved merge, a fix) carries your own model in
  its trailer, so add your model to that body's `Model:` line in the same step. **Watch out for:** the `commits` check
  matches each trailer against the body's `Model:` line; the coordinator resolved conflicts on two pull requests with
  its own trailer and left `Model:` naming only the agent's model, so #1016 failed the check and cost a run.
  **Seen:** gdstudio #1016 and #1113, 2026-11-11 (coordinator's mistake).
