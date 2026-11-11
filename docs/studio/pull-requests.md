# Pull request titles, bodies and images

<!-- new section: hooks.md says what the guards refuse and is near its size limit; no page held how to write a title, a
description and its images so that the checks pass the first time -->

What goes into a pull request before `pr-rules` reads it: the title, the description from the template, the `Model:`
line and the captures. [Hooks](hooks.md#what-it-refuses) says what the guards refuse; this page is what to do so they
do not, with [the body guard](#pr-body) and [the image guard](#attach-paths) themselves. Merging, landing and keeping
a branch fresh are in [Starting work](starting-work.md#landing).

## Titles {#titles}

- **Approach:** Write the title into a file at the start, count it (`wc -c`, at most 72), check it against the verb list
  with `gds pr check-body <body> --title <title file>` before the commit, and make a merge commit only with `gds
  merge-main`. **Watch out for:** an issue's title is not checked, so `art: Keep the hand IK...` was refused by the
  commit hook twice for a verb off the list; a 74-character title was refused and the push that followed carried the
  older commit; `ui: Merge main into x` is not a title the convention knows (only git's own `Merge remote-tracking
  branch ...` is exempt), so the merge stayed uncommitted. **Seen:** Deadnight #987, 2026-11-04; Deadnight #1280,
  2026-11-05; Deadnight, 2026-11-02 (fix: the title checked as a file before the commit).

## The description {#body}

- **Approach:** Start every description from `.github/pull_request_template.md`; fill every section (`None (reason)` and
  `Screenshots: none (reason)` are answers); keep each Issues affected entry on one line; run `gds pr check-body <file>
  --title <title file> --repo <worktree>` with all three inputs until it says ok, before `gh pr create`. **Watch out
  for:** a freehand body lacked three sections, and the game pull request waited; a run without `--title` skips the
  screenshots, failed-first and lessons rules and printed `description: ok` for a body `pr-rules` refused; a wrapped
  Issues affected line is read as a second entry with no number; the history rules (a failed earlier check, a `bug`
  issue) run only in CI. **Seen:** gdstudio #607, 2026-11-04; Deadnight #1233, 2026-11-05 (fix: always `--title`);
  gdstudio #869, 2026-11-10 (a wrapped Issues affected line, not checked first).
- **Approach:** Write the `Screenshots: none (reason)` line bare or as a list item (`- Screenshots: none (reason)`, also
  with bold); the checker strips the list marker and bold before it compares, and a test pins each form. **Watch out
  for:** the check once matched the line from its first character, so a listed line read as "no capture" and the
  refusal asked for a Before and After pair, which does not fit a change with nothing visible; a listed line still
  needs its reason in parentheses. **Seen:** gdstudio #931 (opened from #930), 2026-11-10 (fix: `_plain_line` in
  `groundwork.py`).
- **Approach:** When you add a commit to another agent's pull request, take a branch over or carry a commit into yours,
  name every model of its commits on the `Model:` line in the same step (`git log
  --format=%(trailers:key=Co-Authored-By) origin/main..HEAD`) and check the body before you push. **Watch out for:** the
  `commits` check matches each commit's `Co-Authored-By` model against that line; a coordinator cherry-picking a Sonnet
  agent's commit, merging main to settle a conflict, or finishing a handed-over branch wrote only one model. **Seen:**
  gdstudio #207 and #208, 2026-11-02; Deadnight #553, 2026-11-02 (fix: every model listed, checked before the push).
- **Approach:** Name the model that wrote the commits on the `Model:` line and in each `Co-Authored-By` trailer (`Claude
  Opus 5.5`, `Claude Sonnet 5.5`), never the harness that ran the session or an alias. **Watch out for:** an
  attribution line that names a tool (`Claude Code`) is not a model name; when a machine maps an alias to another
  model, the mapped model is the author. **Seen:** gdstudio #866, 2026-11-09 (fix: the line and the trailers named the
  model); gdstudio #873, 2026-11-10 (a brief named a model the agent was not and its commits and Model line copied it;
  the model the harness reports wins over a brief, and merged trailers cannot be rewritten).
- **Approach:** For a repository whose `groundwork.py` is not the kit's (Tether), check the body with that repository's
  own checker from its checkout (`python .github/scripts/groundwork.py check-body --body <file>`), or run `gds pr
  check-body <file> --repo <checkout>` without `--title`. **Watch out for:** `gds pr check-body` uses the repository's
  own `groundwork.py` and passes `--title` when given one; Tether's takes `--body` alone, so the command stops with
  `unrecognized arguments: --title` and judges nothing. **Seen:** tether #27, 2026-11-10 (checked again on Tether's
  `main` for gdstudio #1003).

## Editing a description {#editing}

- **Approach:** Run `gh` from the worktree (or pass `-R owner/repo`), check that a saved body is not empty (`wc -c`) and
  keep a copy before replacing the description; when a script edits it, normalise `\r\n` first, replace exact strings
  with an `assert` that each is there, and run `gds pr check-body` before `gh pr edit`, never after. **Watch out for:**
  `gh pr view --json body > file` run in the scratch folder (not a repository) wrote an empty file that `gh pr edit`
  published; a body fetched from GitHub can hold CRLF, so a pattern for `\n\n` never matched and a lazy match took every
  section (80 lines became 21). The old text is in the edit history (`userContentEdits` in GraphQL). **Seen:**
  Deadnight #537, 2026-11-02; Deadnight #1342, 2026-11-06 (fix: restored from the history, checks run before the edit).

## Images {#attach}

[Which paths the image guard covers](#attach-paths) has the measured table of what `gh --attach` rewrites.

- **Approach:** Make the reference and the `--attach` path one file: `cd` into the images' folder and write `--attach
  ./x.png` with `![alt](./x.png)` under `## Screenshots` (or the same absolute path in both), write paths literally
  (never `$S/x.png`), and edit the body file in a command of its own. **Watch out for:** `gh` rewrites a reference only
  when it names the same file as an `--attach` path, so an absolute `--attach` with a `./` reference left the local path
  in the body and appended the upload after `## AI use`; the guard reads the body and command before they run, so a body
  edited in the same command, or a path in a variable, is read as it was. **Seen:** Deadnight #553 and #586, 2026-11-02;
  Deadnight #611, #637 and #787, 2026-11-03; Deadnight, 2026-11-04 (fix: the guard compares files, not names).
- **Approach:** After the pull request is open, read the description back (`gh pr view N --json body -q .body`) and look
  for a `github.com/user-attachments` URL on the `Before:` and `After:` lines; move any appended upload into place and
  delete the extra block, then `gh pr edit N --body-file <file>` without `--attach`. **Watch out for:** a report said
  the captures were uploaded because a grep count matched the appended copies, while the lines still held `./` paths and
  `pr-rules` refused them. **Seen:** Deadnight, 2026-11-02 (fix: the read-back is the check).
- **Approach:** To check a body whose captures are still `./` paths, check a copy whose `(./name.png)` links are
  replaced by an upload address (`sed -E`), or upload the images first on the issue the pull request fixes (`gh issue
  edit N --body-file <file> --attach <png>`), read the URLs back and put them in the pull request body; never ask for an
  upload through a comment. **Watch out for:** by hand `gds pr check-body` has no `--attach` and wants uploaded images
  while the attach guard wanted `./` references, so each guard refused what the other accepted. **Seen:** Deadnight,
  2026-11-02 and 2026-11-03 (fix: gdstudio #186, the guard reads a `./` reference to an attached file as an upload; the
  hand check still does not); gdstudio #875, 2026-11-10.

## Pull request bodies before they are sent {#pr-body}

<!-- new section: moved from hooks.md, which had reached its 50 KB limit; the body rules live on this page -->

`pr-rules` judges a description after the push, and an agent whose body failed only found out there (a `None` line
without its reason, text after it, a missing section). `gds pr check-body <file> [--title <file>] [--repo <folder>]`
runs the same function, `groundwork.py check-body`, on the machine and exits 1 with the reasons (2 when it cannot run:
no conventions, not a checkout). It runs in the checkout of the repository the pull request is for and reads that
repository's `.github/conventions.yml`, with its own `.github/scripts/groundwork.py` when it has one (a game's rules
differ from the kit's), else the kit's. The Git/GitHub guard does the same before `gh pr create|edit` runs: it reads
the body once, the same read `--attach` uses, runs the check in the checkout around the current folder (or the
`<workspace>/repos/<name>` checkout that `-R owner/name` names, when that is another repository) and refuses with the
reasons and the command to run. `--title` on the command turns on the title rules (screenshots, failed first, lessons).
Not judged, because they cannot be read first: a body from standard input, a file not written yet, a literal body with a
backtick or `$(`, a `gh pr edit` without a body, and a repository with no checkout. The pull request's history is not
asked (no network), so "a check failed on an earlier commit" is still `pr-rules`' alone to judge.
A `](../path)` reference to a file the same command passes with `--attach` (the same file, [below](#attach-paths)) counts
as an uploaded capture there (the guard swaps in an upload address before it asks, as `--attach` does), so one body
satisfies both guards; a reference to a file that is not attached, or the same body without `--attach`, is refused.
`gds pr check-body` by hand has no `--attach` and still wants uploaded captures
([Images](#attach)). A relative `--body-file` is read
from the folder the command is in after its `cd` (`cd <dir> &&` or `cd <dir>;`, quoted paths, `cd /d`, `~` and Git
Bash's `/c/dir` included), the way `gh` reads it. A `cd` the guard cannot follow (`cd -`, `cd $DIR`, a glob) leaves a
relative body file unplaced: `--attach` is then refused with "use an absolute path", and without `--attach` the body
is not judged. The refusal for a missing file names the path it looked in
([Writing checks](writing-checks.md#paths)). `--attach` paths are never
opened by the guard, only placed and compared with the references ([below](#attach-paths)). The docs rule of
`pr-rules` (code changed, no docs changed, no `Docs: none` line) reads the branch's files: `gds pr check-body` and the
guard run the same `groundwork.py check-docs` on `git diff --name-only origin/main...HEAD` of the checkout. With no
branch to read (no commit, a detached head, the checkout on `main`, no `origin/main`) `gds pr check-body` prints
`docs: cannot tell` rather than `docs: ok`, and the guard lets the command through
([Writing checks](writing-checks.md#same-input)). The guard is a hand-merge path
(`.claude/hooks/`): a maintainer merges changes to it.

- **Approach:** Give the pull request template an Issues affected section and a Failed first test from the first day,
  and update every affected issue after a merge. **Watch out for:** follow-up work and real regressions went untracked
  when a pull request had nowhere to name them. **Seen:** Deadnight, 2026-11-01 (fix: the template carries both sections
  and the body check reads them before a pull request is sent).
- **Approach:** Run `groundwork.py check-body` on a pull request body before opening it. **Watch out for:** a body wrote
  `None` without the expected form, and the body check in CI refused it after the pull request was open. **Seen:**
  Deadnight, 2026-11-01 (fix: the CI body check caught it; the hook here now checks a body before it is sent).

- **Approach:** When a required check fails on a pull request's first commit, add `Lessons: <page.md#anchor>` to the
  body in the same push that fixes it, naming the topic section the fix is recorded in. **Watch out for:** the local
  `check-body` does not see the history, so it passed; the `body` check then failed on the fix commit ("build-ok failed
  on an earlier commit of it") and the pull request sat red until the line was added. **Seen:** gdstudio #821, 2026-11-08
  (the `template` job failed once; the body got its `Lessons:` line after the fix push).

## Which paths the image guard covers {#attach-paths}

<!-- new section: moved from hooks.md with the body guard, which had reached its 50 KB limit -->

`gh pr create|edit --attach` uploads each file and rewrites a `![alt](../path)` reference in the body to the upload, in
place, **only when the reference and the `--attach` path name the same file**. `gh` places both from the folder it runs
in. With the command run in the worktree, `--attach <scratch>/before.png` and `![before](../before.png)` are two files:
the reference stays `./before.png`, the upload is appended after `## AI use`, and `pr-rules` fails with "the 'Before:'
capture is missing". Measured on 2026-11-03 with `gh` 2.102.0 (`gh issue edit --attach` shares the code):

| `gh` runs in | `--attach` | reference in the body | rewritten in place |
| --- | --- | --- | --- |
| the worktree | `<scratch>/x.png` | `./x.png` | no (the upload is appended after `## AI use`) |
| the images' folder | `<scratch>/x.png`, `./x.png` or `x.png` | `./x.png` or `x.png` | yes |
| the worktree | `<scratch>/x.png` | `<scratch>/x.png` | yes |
| the worktree | `<scratch>/x.png` | a relative path that resolves to it | yes |

The guard before the command used to match by file name alone, so it passed the first row. Deadnight #611 and #637
were opened that way through the Bash tool, which the guard does see: the body file was written first, `--attach` took
absolute paths in the scratch folder, and the command ran in the worktree (the agents' transcripts; the body history
on GitHub shows the first body with `](../before-desktop-2-solo.png)` references and the uploads appended). The same
history shows 17 Deadnight pull requests of 2026-11-02 and 03 with a description revision that had `./` image
references. The guard now places the reference and the `--attach` path (`file_key` in
`.claude/hooks/guards.py`, following a plain `cd`, `pushd` or `Set-Location`) and refuses the pair that is not one
file, naming both paths and the folder `gh` would read from. The Bash and PowerShell tools are judged alike. A `cd` it
cannot follow (`cd $DIR`) leaves a relative reference unplaced, so it is refused too. The body guard reads the same
placing (`as_uploaded`): a `./x.png` reference that `gh` would leave local stays local for the description rules, and
the two guards agree.

Paths the guard cannot read are covered by a second line, a `PostToolUse` read-back. After a shell command that ran
`gh pr create|edit`, or whose last output line is a pull request address (a script that runs `gh`, an alias), the
description is fetched (`gh pr view <url> --json body`) and any `![x](../x.png)` reference to an image that is not an
upload is named in the answer, with the command that repairs it. It is advice, not a refusal (the pull request already
exists), and `readback = false` in `[attach]` turns it off. Neither check can read a script file (`python open_pr.py`
runs `gh` out of sight; only the read-back sees its result) or a `gh api` call that sets a body; `pr-rules` in CI
remains the last check.
