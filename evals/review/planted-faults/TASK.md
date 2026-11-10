+++
agent = "reviewer"
kind = "review"
deliver = ["REVIEW.md", "findings.json"]
read = [
  "studio/pull-requests.md#body",
  "engines/godot/test-speed.md#time-driven-values",
  "gamedev/netcode.md#client-input",
  "engines/godot/gdscript.md#names-and-types",
]

[limits]
min_found = 9
max_false = 2
max_findings = 25
+++

# Review a pull request with planted faults

A pull request by someone else is waiting for your review. It adds a reload, a reserve and ammo pickups to a
third-person shooter's weapon, and a server-side fire request. Review it the way you review any pull request: read the
description and the diff, read the files around them, judge it against the repository's rules (`rules.md`), and say
what is wrong with it. You cannot run it (there is no game here); you review by reading, and you may use any tool you
have to search the files.

## What you have

- `pr.md`: the title and description of the pull request.
- `pr.diff`: the diff.
- `repo/`: the files as they are after the change (`game/` and `docs/`), including files the pull request did not
  touch, which you may need to judge it.
- `rules.md`: the rules this repository reviews against.

## What to deliver, in this folder

- `findings.json`: a JSON list with one object for each problem you found, each with `"file"` (the file's name or its
  path under `repo/`, or `pr.md`), `"line"` (the number of the line in that file where the problem is), and
  `"summary"` (what is wrong and why, one or two sentences).
- `REVIEW.md`: your verdict, a line `Verdict: approve` or `Verdict: changes needed`, then the findings in words, most
  serious first.

Report a problem once, at the line where it is. Report only what is wrong: a finding about code that is correct costs
you as much as a problem you missed is worth, so check a suspicion against the rest of the code and the rules before
you write it down. Several faults of different kinds were planted: in the code, in the tests, and in what the
description claims.

## What judges it

| Measure | Limit |
| --- | --- |
| `REVIEW.md` has the line `Verdict: changes needed` | yes |
| `findings.json` is a list of findings, each with a file, a line and a summary | yes |
| Planted faults found (a finding on the fault's file and within a few lines of it) | at least 9 |
| Findings that match no planted fault | at most 2 |
| Findings in all | at most 25 |

`gds eval check planted-faults <this folder>` prints the numbers. It does not say which faults it found.
