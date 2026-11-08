# Writing a check or a guard

<!-- new section: hooks.md says what the guards refuse; no page held what went wrong when a check was written, so the
next
one repeats it -->

Hooks, `groundwork.py`, CI jobs and the `gds` guards are programs that judge text, commits and commands. Most of their
faults were not in the rule but in what the check was given: a draft instead of the stored object, a text without the
title, a command it could not follow. Each entry is for the person writing the next check. The checks themselves are in
[Hooks](hooks.md) and [CI and deploys](ci.md).

## Give it the same input as the real check {#same-input}

- **Approach:** When a local check and a remote check apply one rule, make them one function over the same artifact (the
  stored commit, not the draft or the file a hook is handed), run the local one again at the last point before the push,
  and test with the real command sequence that makes the bad object, not with a string. **Watch out for:** the
  `commit-msg` hook dropped every `#` line to ignore the editor's help text, but with `-m`, `-F` and `--no-edit` git
  keeps them, so a merge's `# Conflicts:` list passed locally and failed CI on the stored commit; the fix was a force
  push, which is refused, so the pull request was replaced twice. **Seen:** Deadnight #503 and #539, 2026-11-02 (fix:
  `stored_message()` removes only the editor's help text, and a `pre-push` hook judges the stored commits).
- **Approach:** Judge a body as the command will leave it: when a command changes the input (`--attach` uploads), every
  check reads it as it will be after the command. **Watch out for:** the attach guard wanted `./file` references and the
  body check wanted uploaded images, so each refused the body the other accepted. **Seen:** Deadnight #586, 2026-11-02
  (fix: gdstudio #186, `check_body` reads a reference to an attached file as an upload).
- **Approach:** When a local check stands in for a CI check, list every job of the CI check and what it reads (text,
  diff, title, history, API); a job whose input the local check lacks is added or reported as "cannot tell", never "ok",
  and a check with optional inputs is run with all of them. **Watch out for:** `gds pr check-body` ran the text rules
  only, so a body whose docs rule reads the changed files passed locally and was refused after the push; the same run
  without `--title` skipped three more rules. **Seen:** Deadnight #612, 2026-11-02 (fix: `pr.check_docs`, and `docs:
  cannot tell` when the branch cannot be read); Deadnight #1233, 2026-11-05.
- **Approach:** Test a guard that predicts what a tool will do against the tool: run the real command on something
  disposable before writing the rule, put the measured table in the docs, and add a test that fails on the case that
  went wrong in production. **Watch out for:** the image guard matched the file name and `gh` matches the file; the
  kit's own test expected a pair `gh` leaves alone to pass, so the wrong rule had a green test and 17 pull requests
  reached CI with local image paths. **Seen:** Deadnight #611 and #637, 2026-11-03 (fix: the guard places both paths as
  `gh` does, with a read-back as the second line).

## Say where it looked {#paths}

- **Approach:** A guard that reads a relative path says where it looked; when it cannot know the folder it says so and
  asks for an absolute path, and it never reports a missing file from a guess. Run it on every spelling of the folder
  change (`cd`, `;`, quotes, `cd /d`, `/c/dir`, `~`, `$VAR`) before calling it right. **Watch out for:** a body file
  "does not exist yet" blamed the file when the guard had not followed a `cd` it could not place, and the issue named
  only the one case that reading the code reproduced. **Seen:** Deadnight #611, 2026-11-02 (fix: `change_dir` follows
  the forms above; an unfollowable one marks the folder unknown).

## Inputs that arrive in more than one form {#forms}

- **Approach:** A rule that reads free text takes both ways of writing the line before it merges: run the check on a
  sentence form and a bare form, and call one shared helper instead of copying the test. **Watch out for:** `_reasoned`
  required a `none (reason)` line to end with `)`, but agents write a closing full stop, so three pull requests were
  refused on lines that had a reason. **Seen:** gdstudio #146 and #149, Deadnight #550, 2026-11-02 (fix: one full stop
  is dropped after the parenthesis, and the tests run every `none (reason)` line with and without it).
- **Approach:** When a rule reads a check's conclusion as "someone made a mistake", list what else produces that
  conclusion (a cancelled run, a skipped needed job, a lost runner) and test each; a conclusion alone needs the jobs
  behind it. **Watch out for:** `build-ok` fails when the jobs it needs are cancelled by the next push, so the
  `Lessons:` rule counted a cancellation as earlier work that went wrong. **Seen:** gdstudio #244, 2026-11-03 (fix:
  `failed_checks` reads the jobs of the run and skips a failure beside only a cancellation).

## Test it where it will run {#where-it-runs}

- **Approach:** Test a check on the commits of a push with a merge of `main` in the range and with the real remote's
  tracking refs, and show that a passing hook looked at something; tests that make commits set `GIT_AUTHOR_*` and
  `GIT_COMMITTER_*`, `chmod` their stand-in hooks, and run once with `GIT_CONFIG_GLOBAL=/dev/null`. **Watch out for:**
  `check-push` judged the commits a merge of `main` brought in (75-character squash titles CI never judges); a probe
  pushing to a bare repository by path had no `refs/remotes`, so pre-commit passed no range and a bad merge got through;
  stand-in hooks without the executable bit and a missing global identity passed here and failed on the runners.
  **Seen:** gdstudio #152, 2026-11-02 (fix: `--not origin/main` in the range and a test that merges a 75-character
  title).
- **Approach:** A counter that bounds a gate resets at the event that ends the thing it counts; test it across the whole
  life of the key (end, resume, end again), not one pass. **Watch out for:** the stall gate's refusal count was kept per
  `agent_id` and dropped after a day, a resumed agent keeps its id, so its second stall started above the limit and went
  free. **Seen:** gdstudio #156, 2026-11-02 (fix: an end that is let through removes the entry).

## A rule is about an effect {#effects}

- **Approach:** Write a rule about an effect (nothing is posted, nothing is merged) against the tool's whole manual:
  walk `gh help` for every flag that causes it and ask the API's schema for the rest; find which program made a refusal
  before trusting a guard; carry a hole closed in one repository to every project the guard covers. **Watch out for:** a
  rule that listed the commands named `comment` let `gh issue close --comment` post, 62 of the 98 routes in the new
  tests got through, the rule lived in a user-level hook outside the repository, and the same hole had been closed in
  one game only. **Seen:** gdstudio #691, 2026-11-05 (fix: `check_comments` judges what `gh` would do, wherever a line
  starts; [Hooks](hooks.md#comments)).
- **Approach:** Commit what a person writes, never what a program derives from it; build the derived page where it is
  read (the docs build, a `gds` command, a hook) and, before adding a generated file to the repository, ask what two
  concurrent pull requests do to it. **Watch out for:** the committed mistakes-by-area page was rewritten by every
  lesson pull request, so the second to merge failed its tests on a page without the first's lesson and needed another
  CI round. **Seen:** gdstudio #117, #125 and #129, 2026-11-02 (fix: the page is built at read time, and a test merges
  two lesson branches from one `main` in both orders).
