# Pull request titles, bodies and images

<!-- new section: hooks.md says what the guards refuse and is near its size limit; no page held how to write a title, a
description and its images so that the checks pass the first time -->

What goes into a pull request before `pr-rules` reads it: the title, the description from the template, the `Model:`
line and the captures. [Hooks](hooks.md#pr-body) says what the guards refuse and why; this page is what to do so they
do not. Merging, landing and keeping a branch fresh are in [Starting work](starting-work.md#landing).

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
  issue) run only in CI. **Seen:** gdstudio #607, 2026-11-04; Deadnight #1233, 2026-11-05 (fix: always `--title`).
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

## Editing a description {#editing}

- **Approach:** Run `gh` from the worktree (or pass `-R owner/repo`), check that a saved body is not empty (`wc -c`) and
  keep a copy before replacing the description; when a script edits it, normalise `\r\n` first, replace exact strings
  with an `assert` that each is there, and run `gds pr check-body` before `gh pr edit`, never after. **Watch out for:**
  `gh pr view --json body > file` run in the scratch folder (not a repository) wrote an empty file that `gh pr edit`
  published; a body fetched from GitHub can hold CRLF, so a pattern for `\n\n` never matched and a lazy match took every
  section (80 lines became 21). The old text is in the edit history (`userContentEdits` in GraphQL). **Seen:**
  Deadnight #537, 2026-11-02; Deadnight #1342, 2026-11-06 (fix: restored from the history, checks run before the edit).

## Images {#attach}

[Hooks: which paths the image guard covers](hooks.md#attach-paths) has the measured table of what `gh --attach`
rewrites.

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
  hand check still does not).
