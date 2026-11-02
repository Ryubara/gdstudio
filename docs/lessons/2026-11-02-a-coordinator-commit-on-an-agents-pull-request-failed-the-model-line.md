---
areas: [process, ci]
---
# A coordinator commit on an agent's pull request failed the Model line

2026-11-02

- **Saw:** the `commits` check refused two kit pull requests in an hour: "a commit names the model 'Claude Sonnet 5.5'
  (or 'Claude Opus 5.5') in its trailer, but the description's 'Model:' line does not".
    - Kit #207: the coordinator cherry-picked a stranded lesson commit, written by a Sonnet agent, into its own pull
      request, and wrote its own model on the Model line.
    - Kit #208: the coordinator pushed a merge of main to resolve a conflict in an agent's docs pull request. The
      description named only the agent's model.
- **Cause:** the check matches every commit's `Co-Authored-By` model against the description's `Model:` line. A pull
  request that carries commits from two models needs both named. Taking over or rescuing someone else's commits
  changes who wrote them, and the description isn't updated with them.
- **Fix:** when you add a commit to another agent's pull request, or carry their commit into yours, edit the `Model:`
  line in the same step to name every model in `git log --format=%(trailers:key=Co-Authored-By) origin/main..HEAD`. Then
  run `gds pr check-body` before you push.
- **Docs:** [Hooks: docs](../hooks.md#docs), and the stranded-push lesson
  (2026-11-02-a-lesson-pushed-after-its-pull-request-merged-was-lost.md), whose fix leads to this case.
