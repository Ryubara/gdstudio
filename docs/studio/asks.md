# Reading an ask

<!-- new section: nothing in the studio folder covered how an agent reads the maintainer's asks and decisions (numbers,
defaults, words about people) or weighs a new tool against what exists -->

How an agent turns what the maintainer asks or decides into work: the base and scale of a number, the shape behind an
average, what a word about people or defaults covers, and what already owns a job before a new tool is proposed.

## Numbers in an ask {#numbers}

- **Approach:** For N% quieter, louder or faster of something changed before, take the original as the base unless told
  otherwise, use perceived loudness for quieter, and write the base, the scale and the resulting number in the issue and
  the pull request. **Watch out for:** the 50% cut was taken from the level of the day (already cut 25%) and as
  amplitude (-6 dB), where the original level (-16 dB) and half as loud (about -10 dB, so -26 dB) were meant; each
  request was stacked on the last. **Seen:** Deadnight #781, 2026-11-03 (fix:
  [lesson](../lessons/2026-11-03-a-percent-cut-was-taken-from-the-wrong-base.md)).
- **Approach:** When reporting a pace or a curve, give its ends (the first and the last step) and its shape, and say
  when a number is an average. **Watch out for:** a reply gave the average of a rising XP curve (9 minutes a level),
  which described a pace nobody plays and read as if the climb were flat. **Seen:** Deadnight, 2026-11-04 (fix: the
  maintainer asked for a curve that climbs, as the reference's does).

## Words in a decision {#decision-words}

- **Approach:** Before a rule turns on who a person is, read how the sign-in works in the code and say what that kind of
  account can do today; a reading marked to confirm holds its issues back, and behaviour the maintainer describes is
  checked against the code with the gap filed. **Watch out for:** a guest was read as having no account and the XP
  issues were filed on that reading, while guests were meant as server accounts that expire after 7 days; the code does
  neither: each guest sign-in makes a new account kept in memory. **Seen:** Deadnight, 2026-11-04 (fix:
  issues #1058, #1066, #1068, #1075 and #1077 were corrected and #1080 builds the Guest account described).
- **Approach:** When a decision names a default, ask what the choice is a default among before writing the rule. **Watch
  out for:** a costume's default colours were read as fixed data of the costume, where a Default option in its own
  colours beside colours a player picks was meant: a phrase about the starting state was read as the whole feature.
  **Seen:** Deadnight, 2026-11-04 (fix: the maintainer corrected the plan).

## Proposing a new tool {#new-tools}

- **Approach:** Before proposing a new tool, mod, layer or repository, name what in the current setup already sees the
  data and acts at that moment, and give the work to the simplest owner. **Watch out for:** the foundation plan proposed
  a mod to rewrite a subagent's prompt at spawn, believing no hook could see it, though the `PreToolUse` guard on the
  Agent tool reads every prompt and the orchestrator writes it; the same day a new repository was offered for shared
  assets the kit already holds. **Seen:** gdstudio #771, 2026-11-07 (fix: the orchestrator writes `Read:` lines and the
  guard refuses a prompt without them).
