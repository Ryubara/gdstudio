---
areas: [tools, process]
---
# A body check refused a "none (reason)" line that ended with a full stop

2026-11-02

- **Saw:** `pr-rules` and the `body` check failed three pull requests (kit #146, kit #149, Deadnight #550) with
  "'None' needs a reason in parentheses" on lines that had one: `Failed first: none (documentation only).` and
  `None (one new lesson page).`. Each was fixed by hand.
- **Cause:** `_reasoned` in `groundwork.py` required the text to end with `)`. People and agents write these lines as
  sentences, so a closing full stop is the usual form, not a mistake. The checker was tested only with the form its
  author wrote.
- **Fix:** `_reasoned` drops one full stop after the closing parenthesis and still refuses anything else after it
  (`(why) extra`, `(why)..`). The `Screenshots: none` line used its own copy of the test and now calls `_reasoned`
  too. The tests run every `none (reason)` line of the checker with and without the full stop.
- **Check for next time:** a rule that reads free text takes both ways of writing the line before it is merged: run
  the new check on a sentence form and a bare form, and call one shared helper instead of copying the test.
- **Docs:** [Hooks](../hooks.md).
