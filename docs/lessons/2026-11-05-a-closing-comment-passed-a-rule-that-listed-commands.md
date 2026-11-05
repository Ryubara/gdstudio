---
areas: [tools, process]
---
# A closing comment passed a rule that listed commands

2026-11-05

- **Saw:** on #691 an agent ran `gh issue close 691 -R Ryubara/gdstudio --comment "$(cat close.md)"`, and its report
  went up as a comment under the maintainer's account, against the decision of 2026-10-12. A hook then refused its
  attempt to edit that comment, which is why the route looked like a hole in a working guard.
- **Cause:** three things, and the first is general. The rule was written as a list of commands (`gh issue comment`,
  `gh pr comment`, `gh pr review`, `gh api`) when it is about an effect, so a command that posts as a side effect of
  something else passed: 62 of the 98 routes and spellings in the new tests got through it, among them `gh issue
  reopen -c`, `gh discussion comment`, `submitPullRequestReview` and `gh api .../comments --input x.json`. Second, the
  rule lived only in a user-level hook, outside this repository: `guards.py` refused no comment at all, the kit's own
  tests pinned `gh issue comment --attach` as allowed, and `reviewer.md` credited "a hook" nobody could read here.
  Third, the same hole had been found on Coney's #772 on 2026-10-28 and closed in Coney's repository only, so a
  correction reached one project and the shared machine kept the gap.
- **Fix:** `check_comments` in `.claude/hooks/guards.py` judges what `gh` would do, wherever a line starts it: every
  command of `gh help` that posts, `--comment` and `-c` on a close or reopen in every spelling gh reads, `gh api` writes
  to a `comments` or `reviews` path, the twelve GraphQL mutations of GitHub's schema, and a query it cannot read
  ([Hooks](../hooks.md#comments)). The new tests failed 101 of 278 before the guard and all pass after it; each of 15
  mutations of the guard fails them.
- **Check for next time:** a rule about an effect (nothing is posted, nothing is merged) is checked against the tool's
  whole manual, not against the commands named after the effect: walk `gh help` for every flag that causes it, and ask
  the API's schema for the rest. A refusal seen once does not show a rule holds; find which program made it. When a
  rule in one repository closes a hole in a guard on the shared machine, carry it to every project the guard covers.
- **Docs:** [Hooks](../hooks.md#comments).
