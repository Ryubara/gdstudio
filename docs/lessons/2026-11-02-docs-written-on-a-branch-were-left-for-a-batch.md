---
areas: [process]
---
# Docs written on a kit branch were left for a batch and went unpublished

2026-11-02

- **Saw:** the maintainer: "I keep asking to have you update documentation over stuff that wasn't considered when it was
  first done. This needs to be made into a 'learning workflow' that's enforced." Deadnight #507 fixed the hand grips and
  its agent wrote the how-to and seven lessons on a kit branch, then left them "for the coordinator's docs batch"; two
  lessons sat unpushed for hours (published in #98).
- **Cause:** the learning loop fired only on a maintainer message, and "write it up" was advice. Nothing failed when a
  kit branch had commits and no pull request, nothing tied a game `Fix` pull request to the documentation of what it
  fixed, and an agent's own corrections (a red check, a rework) left no lesson at all.
- **Fix:** whoever does the work publishes the docs, in the same task. A Stop and SubagentStop gate holds back a kit
  branch with commits and no pull request; a report with a `Mistakes` section must name its lesson file; every lesson
  carries `areas:` and a generated glossary by area is put into the context of an agent whose issue has those areas.
- **Docs:** [Hooks: docs ship with the change](../hooks.md#docs), [Mistakes by area](../research/mistakes-by-area.md).
