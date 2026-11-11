# The shell and scripted edits

<!-- new section: no studio page held how to run commands and edit files from the Bash tool on Windows; hooks.md is
about
what the dispatcher refuses, and these habits cost a commit each time they were missed -->

The agents run Git Bash and Python on a Windows machine that other agents share. This page holds what went wrong when
a command hid its own failure, a script rewrote a file, or a stop took another agent's process, each with the habit
that avoids it. The refusals a hook makes are in [Hooks](hooks.md); the shared-machine caps are in
[The workspace](workspace.md#shared-machine).

## Pipes and chains {#pipes}

A commit, a merge and a lint run are read whole, on their own, and the next step runs only after a look at the result.

- **Approach:** Run a commit, `uvx pre-commit run`, `gds merge-main --continue` and a test run on their own (a test
  run's output whole to a scratch log) and read all of it; never end them in `| tail` or `| grep`. Check `git log
  --oneline -1` and `git status --short` before a push, and `gh pr diff N --name-only` after opening a pull request.
  **Watch out for:** a pipe returns the filter's exit code and `tail` shows the last lines, so a refused commit (a title
  verb, MD013, a `gdformat` roll-back) or a failed suite looked done. **Seen:** Deadnight #1003, 2026-11-04; Deadnight
  #656, 2026-11-02 (a licence line); gdstudio, 2026-11-02 (a lint failure); Deadnight #1374, 2026-11-07; gdstudio
  #916, 2026-11-10 (twice); gdstudio #954, 2026-11-10 (`grep | tail -6` over the template suites hid a failing one).
- **Approach:** Chain a commit and the push after it with `&&`, put `|| exit 1` on every step that gates the next, and
  run a fixer (`--fix`, which exits 1 after fixing) on its own line. **Watch out for:** `;` let `gds merge-main; git
  push` run after a refused title and push only the older commit; in the Bash tool a `set -e` at the top of a command
  stops nothing (`bash <file>` honours it), so a refused description was published and the pull request marked ready; a
  fixer's exit 1 made `&&` skip the edit that followed it. **Seen:** Deadnight #1280, 2026-11-05; gdstudio #621,
  2026-11-05; Deadnight, 2026-11-03 (fix: `;` only for steps that may fail, every gate read before the next step).

## Line endings and encodings {#line-endings}

- **Approach:** In an edit script on Windows open both ends with `newline=""` and `encoding="utf-8"` (or
  `read_text(encoding="utf-8")` and `write_bytes(text.encode("utf-8"))`), keep an `assert old in text`, or use the Edit
  tool; after the script, or a `gdformat` run, `sed -i 's/\r$//' <files>` and `file <path>` (`ASCII text`, not `with
  CRLF line terminators`). **Watch out for:** text mode turns every `\n` into `\r\n`, whatever the file had, and reading
  in text mode hides it; the Write tool and `gdformat` write CRLF too, and a later exact-text replace then finds nothing
  and edits nothing. A bare `write_text` used cp1252, so one `m²` broke the docs build. **Seen:** Deadnight #429, #415
  and #442, 2026-11-01; gdstudio, 2026-11-02; Deadnight, 2026-11-03 to 2026-11-05 (fix: the habit above);
  gdstudio #830, 2026-11-08; gdstudio #875, #903, #1011 and tether #31, 2026-11-10 (CRLF again); #1127.

## Scripted edits {#scripted-edits}

- **Approach:** Put text with a backslash, a quote or `\n` in an Edit call, or write the edit script to a file with the
  Write tool and run the file, never a heredoc or a `sed` replacement; build a backslash with `chr(92)`; read the
  changed lines of `git diff` after any scripted edit. **Watch out for:** an escape passes through the shell and then
  the Python literal, so `\n` became a real line break inside a GDScript string (which still parsed), `\b` and `\t`
  vanished from a regex, and a `sed` replacement split a line over three; a parser that accepts the wrong text says
  nothing. **Seen:** gdstudio, 2026-11-02; Deadnight, 2026-11-03; Deadnight, 2026-11-04 (fix: the tests and `ruff` run
  straight after the edit, not at the end); gdstudio #770, 2026-11-07 (two heredoc scripts never ran: Write tool);
  gdstudio #1005, 2026-11-10 (a heredoc broke `"\n"` in a test: the Edit tool).
- **Approach:** A script that changes several places of one file works from the end upward, or finds its place again
  after each edit, and cuts "to the next top-level `func` or `class`", never to the end of the file; then it imports the
  project and runs `godot --headless --check-only -s <script>` on every edited script that no suite loads. **Watch out
  for:** the first edit moved the line numbers, so a reflow joined `const SETTINGS_SCENE` into the comment above it; a
  cut from a heading to the end of a capture tour removed `_key`, `_press` and `_still`, and nothing failed because no
  test loads a capture script. **Seen:** Deadnight, 2026-11-04 (fix: the constant put back, the suites of every touched
  file run); Deadnight, 2026-11-05 (fix: the helpers restored from `git show HEAD:<path>`).

- **Approach:** When a script reflows a page you are adding to, wrap only your own text, then read `git diff --stat` and
  every hunk outside your additions. **Watch out for:** a wrap-everything pass at 120 columns rewrapped existing lines
  that markdownlint accepts (a long link has no space to break at), so a dozen lines of other people's text changed in
  the pull request. **Seen:** gdstudio #770, 2026-11-07 (fix: the hunks whose text only rewrapped were restored from
  `HEAD`, and the wrapper skips a line whose overflow is one unbreakable link).
- **Approach:** When the text an edit writes holds backslash escapes (`$'\r'`, `'\n'`, a regex), put the edit in a
  Python file written with the Write tool and run it, or use the Edit tool, then `cat -A` the lines it changed.
  **Watch out for:** a Python heredoc and a `sed -i` inside the Bash tool both turned `\r` into a real carriage return,
  twice over, so `tr -d '\r'` became `tr -d '<CR>'` and the script still passed `bash -n`. **Seen:** gdstudio #839,
  2026-11-08 (fix: a Python file with the backslash built from a variable).

## Folders and paths {#paths}

- **Approach:** Give `git worktree add` an absolute path, start a command line with `cd <worktree> || exit 1` (or use
  `git -C <worktree>`), chain everything after it with `&&`, and read `git branch --show-current` before a commit.
  **Watch out for:** `git -C repos/x worktree add worktrees/x/y` resolves the path against the repository and made the
  worktree inside it; `cd <worktree>; ... git commit` ran in the shell's start folder after the `cd` failed, which is
  the kit's main checkout, and committed there. **Seen:** Deadnight, 2026-11-01 (a worktree inside the repository);
  gdstudio, 2026-11-03 (a commit on the kit's `main`, moved to a branch before any push); gdstudio #1073, 2026-11-11
  (`cp ... && cd <worktree> && check; git add -A; git commit`: the `cp` failed, the `cd` was skipped and `git commit`
  ran on the main checkout, which was clean).
- **Approach:** Give a Windows program (Python, a hook, `gh --body-file`) a path with its drive letter,
  `C:/Repositories/...`, never Git Bash's `/c/...`; keep helper scripts in the session's own scratchpad, not under a
  shared temp name, and pass the worktree as an argument. **Watch out for:** `/c/Repositories` is read as a folder named
  `c` on the current drive (`FileNotFoundError`, "the body file does not exist yet"), and a `gdt.sh` kept under one name
  in the shared temp folder changed into another agent's worktree and reported its pass for my branch. **Seen:**
  gdstudio, 2026-11-02; Deadnight, 2026-11-05; Deadnight, 2026-11-01 (fix: read the line that names the scanned folder
  before trusting a result); gdstudio #879, 2026-11-10 (the scratchpad itself is shared: another agent's `sync.sh` there
  copied its branch into its game; fix: a subfolder named for the issue; also #903, #966).

## Background commands and processes {#background}

- **Approach:** Run each long step as its own `run_in_background` command with no inner `&`, ending in `echo done >
  marker`; wait on the file the script writes last or on the task's own completion notice, never on a redirect target;
  give every `cat >` a heredoc, and every Python step a script file, a `timeout` and `</dev/null`. **Watch out for:** `(
  a; b ) &` was reported complete at once and the second part never started; `until [ -f summary ]` fired when `>
  summary` created the file at the start; a bare `cat > file` waited on the terminal for two minutes, and a leftover
  `python -` spun on a broken REPL until the timeout. **Seen:** Deadnight, 2026-11-01 to 2026-11-04 (fix: the checks
  above; a monitor script also ends on its own, [Agents](agents.md#the-loop)).
- **Approach:** Stop only a process you started: keep its PID (`echo $! > pid`) or find it by your worktree's path in
  its command line, print the candidates before the first `Stop-Process`, end it by tree (`taskkill /PID <pid> /T /F`),
  and give each run a log of its own. **Watch out for:** every agent shares one pinned Godot, so its name or a runner's
  name does not say whose it is; `taskkill /IM` and a `GdUnitCmdTool` pattern ended other agents' suites and a
  pre-commit run; stopping a background task ends the shell, not the `timeout` and Godot under it, which kept writing to
  the same log beside the new run. **Seen:** Deadnight, 2026-11-01; Deadnight #1086, 2026-11-04; gdstudio, 2026-11-06
  (fix: the hooks refuse a kill by name ([Hooks](hooks.md)); a short `timeout` on every run).
- **Approach:** Leave a shell script alone while a background run executes it: edit the source, and copy it over the
  running copy only after the run ends (or run a copy made for that run). **Watch out for:** bash reads a script as
  it goes, by byte offset, so a `cp` over `check.sh` during a 10 minute bot run made bash resume inside the new text:
  the run's last step (the older client's hello) never ran and printed nothing, no failure either. **Seen:** gdstudio
  #910, 2026-11-11 (the 2-bot run of the deployed series; the 4 and 8 bot runs checked the refusal).

## Before committing {#before-commit}

- **Approach:** `git add -A` (or `git add -N .`) before `uvx pre-commit run --all-files`, run the hooks after each batch
  of edits (`--files <the files just edited>`; twice, since the second run shows what the first rewrote), wrap Markdown
  at 120 and comments at 98 as you write, put constants before functions. **Watch out for:** `--all-files` means the
  files git tracks, so new scripts, tests, capture scenes and docs were skipped until the commit hook ran on them
  (`gdlint` lines over 100, a missing `.gd.uid`, MD007, MD012 and MD013, CRLF), after hours of edits; `gdformat` and
  `gdlint` skip an untracked script the same way. **Seen:** Deadnight, 2026-11-01 to 2026-11-04 (#787, #987, #1063)
  (fix: add first, run after each batch, read every failure).
- **Approach:** When pre-commit names a lint in a line you did not write, run `gds merge-main` before changing the code.
  **Watch out for:** pre-commit lints whole files, so a one-word comment edit pulled in a `gdlint` fault that `main` had
  fixed since the branch began. **Seen:** Deadnight, 2026-11-04 (fix: main merged first, then the commit passed).
- **Approach:** Before adding a function to a large script, count its lines (`gdlint` refuses a file over 1000) and put
  the new part in a script of its own from the start; give a new template script or test its `.gd.uid` by importing a
  game made from the branch (`gds template game`) and copying the file back. **Watch out for:** a 980-line
  `player_ragdoll.gd` passed 1000 with one helper and had to be split after the code was written, and `gds template
  test` refused a new test with no `.uid` before running any suite. **Seen:** gdstudio #975, 2026-11-10
  (`RagdollBraces`, `test_ragdoll_cones.gd.uid`); gdstudio #926, 2026-11-10 (`character_ragdoll.gd` reached 1027
  lines with the lazy bones: the pose sample moved to `RagdollPose` and an unused helper went); gdstudio #963,
  2026-11-10 (eleven new scripts' `.uid`s, a tour's found late); #906, 2026-11-11 (a tour's, four jobs red).

## Reverting and checking out {#checkout}

- **Approach:** Copy a file to the scratch folder before instrumenting it, or commit or stash a rewrite first; take a
  "before" capture or measurement from a separate checkout, never by swapping files under a running test. **Watch out
  for:** `git checkout <file>` restores the last commit, not the file before the last edit, so dropping a timing probe
  reverted the whole uncommitted rewrite; old weapon files put back for a capture were read by a suite that started
  during the swap. **Seen:** Deadnight, 2026-11-03 (two cases; fix: the rewrite written again, the run repeated).
- **Approach:** To run another commit in a scratch checkout, give the commit's hash (`git rev-parse HEAD` taken in the
  branch's worktree), print `git -C <checkout> log --oneline -1` before the run, give each run a new output folder and
  stop the old run by its PID first. **Watch out for:** `git checkout --detach HEAD` in the other checkout stays on that
  checkout's own `HEAD`, so a soak arm ran the old code, its new tuning field did not exist, and the arms looked the
  same. **Seen:** Deadnight #767, 2026-11-03 (fix: hash passed, the commit printed before every arm).
- **Approach:** Show that a new test fails on the thing it guards in a detached worktree (`git worktree add --detach`,
  `git checkout <fix>^ -- <files>`, run the test) with no commit; a hook in the way of a commit is a reason to stop,
  never a setting to switch off. **Watch out for:** the revert was committed on a scratch branch with `git -c
  core.hooksPath=/dev/null commit` so the title hook would not refuse `scratch:`, which is `--no-verify` by another
  name. **Seen:** Deadnight #848, 2026-11-03 (fix: `git reset --soft HEAD~1` before any push, the revert kept as
  working-tree changes); tether #28, 2026-11-10 (`git stash push -- src hooks` to run the new tests on the old code
  was refused by the permission settings; fix: `git archive HEAD` unpacked in the scratch folder with the new tests
  copied in).
