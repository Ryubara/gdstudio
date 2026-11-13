# The hold

<!-- new section: moved from hooks.md#hold, which went over the 50 KB page limit (gdstudio #1202) -->

## The hold {#hold}

A pull request the maintainer must see first carries the label `S-hold`. GitHub enforces it, not this hook: the `hold`
job of `.github/workflows/hold.yml` fails while the label is on, and the `Main` ruleset requires that job, so no route
merges it. The rule is `merge.hold` in `.github/conventions.yml`. A failed `hold` is a decision, not a broken build: it
stays out of `merge.required_checks`, so `pr-status` does not label it `S-ci-failing`.

- **Set it** with `gds pr hold <owner/repo>#N`: it adds the label and returns once the check is red, because until then
  the green run before it still counts (on a real pull request: 3 s to pending, 7 to 10 s to red). Or open it held:
  `gh pr create --label S-hold`.
- **Take it off** only on the maintainer's word: by hand on the pull request's page, or by the coordinator once the
  maintainer approves that lift in the coordinator's own session (below). The check re-runs with no new commit.
  Auto-merge that is on stays on through the hold, so the pull request merges the moment the label comes off.
- **The guard** in `guards/merges.py` gives a session the reason, and it is the only thing that stops a session taking the
  label off: every agent uses the maintainer's token, so GitHub cannot tell them apart. It reads shell commands, so it
  does not see a script that calls the API itself.
- **The approval** is the maintainer's message in the coordinator's session. The coordinator (no `agent_type` or
  `agent_id`) may run `gh pr|issue edit <N> --remove-label S-hold` when the session's transcript (`transcript_path`)
  holds, from the last 24 hours, a message the maintainer typed that names N with lift, remove, approve, land, merge or
  yes in the same sentence, or any sentence with no digit that approves or says yes, in any words and in a message of
  any length, answering the coordinator's last message when that message named N and the hold or an approval; a sentence
  naming N with a negation vetoes N for the whole message. A run ("#A through #B", "A-B", at most 30 apart) names every
  number in it, and "looks good", "is good" or "is great" says yes. There is no set wording to ask for. Only a `user`
  entry whose `origin` kind is `human`, not `isMeta`, not a sidechain and not a tool result counts: a prompt tether
  submits (origin kind `plugin`), agent reports and monitor events (`task-notification`), peers, hook output and tool
  results do not. Pasted blocks (`<pasted_content>`), `>` lines, fenced code and quoted text are dropped first; a
  question, a negation or a condition (if, once, after, until) does not approve. Each approval lifts once:
  `scratch/hold-lifts.log` gets the pull request, the approving message's timestamp (never its text) and the session,
  and a spent timestamp is refused. Name the number, not a branch. Task agents, the API, `gh label` and merges stay
  refused. No session writes a transcript (`[protect]` for Edit and Write; a redirect, `tee`, `sed -i`, `Set-Content` or
  a copy onto one) or spells an entry with a human origin in a shell line or new file text. Code:
  `gds_tools/hold_approval.py`.
- **While it waits**, its agent merges `main` only when the pull request is DIRTY at report time; the coordinator
  refreshes it right before it lands ([Landing](landing.md#landing): an agent merged `main` four times into a held
  pull request, each push restarting CI).
- **A pull request opened before the check was required** has no run on its head and stays pending: run
  `gh workflow run hold-sweep.yml` once. It reports the check through the Checks API and does not touch the pull
  request. A new game runs it once when its ruleset starts requiring `hold`.

Do not put an `if:` or a `paths:` filter on `hold`: a job skipped by `if:` reports success, so a filter on the label's
name would let any other label replace a failed run. `python/tests/test_hold.py` has a test for each such reason.

- **Approach:** Let the maintainer's approval in the coordinator's own session be what allows a lift, read from the
  transcript entries the maintainer typed, and fail closed on anything else. **Watch out for:** the first version
  made lifting wait on a switch the maintainer had to set by hand in `gdstudio.local.toml`, a step the maintainer had
  not asked for; and tether submits prompts through the same path as typed ones, so only the entry's `origin` kind
  tells them apart, never its text. **Seen:** gdstudio #1202 then #1244, 2026-11-11 (fix: the switch was removed and
  `hold_approval.py` reads the transcript; `test_hook_hold_approval.py` covers each kind of text that does not count).
- **Approach:** Hold a pull request stacked on a held one (`gds pr hold`) and leave its auto-merge off: its branch
  carries the held pull request's commits, so merging it lands them past the maintainer. Take the `owner/repo` for
  `gds pr hold` from `gh repo view --json nameWithOwner`, never from memory. **Watch out for:** the body said the
  base was "now on main" while it was still open and held, and the first hold named a guessed owner and failed.
  **Seen:** gdstudio #1273 on #1171, 2026-11-12.
- **Approach:** Read the maintainer's approval in whatever words they use, a blanket one for the held list included,
  and never ask them to repeat it in a set form. **Watch out for:** the guard took only a sentence naming the number or
  a bare yes of at most 20 words, so a longer message that approved every listed pull request among other remarks was
  refused, and the coordinator asked for one approve line per number. **Seen:** gdstudio #1191-#1285 holds,
  2026-11-12 (fix: a digitless approving sentence answers the list at any message length, and a negation naming a
  number vetoes it; `test_hook_hold_approval.py`).
- **Approach:** Read a refusal word in the guard as the maintainer means it, and test every refusal phrase against the
  label's own name and the usual ways of saying the hold comes off. **Watch out for:** `hold off` was a refusal phrase,
  and it matched inside an approval that named the label and then "off" with the numbers (`S-hold off 7`, also "take
  the hold off 7"), so a clear yes was refused. **Seen:** gdstudio #1332, 2026-11-12 (fix: `hold off` refuses only as
  a verb, not after `S-`, `the`, `that`, `this`, `its` or `their`; `test_hook_hold_approval.py` has both sides).
- **Approach:** Read a run of numbers ("#A through #B", "A-B", "A to B", at most 30 apart) as naming every number in
  it, and a reviewer's "looks good", "is good" or "is great" next to a number as a yes. **Watch out for:** a review
  that gave picks per pull request ("for #N, B looks good") and closed with an approval of the whole run named only
  the run's two ends, so the guard lifted the last one and refused the three between; a "not a fan" of one number in
  the same message still vetoes that one. **Seen:** gdstudio #1369-#1378 holds, 2026-11-12 (fix: `_RANGE` and the
  plain-good words in `hold_approval.py`; `test_hook_hold_approval.py` has both sides).
