---
areas: [gameplay, process]
---
# Reference research found no numbers on the open web, while the games' scripts were on GitHub

2026-11-01

- **Saw:** web searches and fetches for "zombie speed in units per second" returned forum guesses; the Fandom wikis
  answered HTTP 402 and 403, and a fetch tool paraphrases code instead of quoting it.
- **Cause:** the numbers live in the games' scripts and configuration, not in prose, and the wikis block fetching.
- **Fix:** `gh search code "<identifier>"` finds the decompiled script dumps (several repositories per game); list a
  repository with `gh api repos/<owner>/<repo>/git/trees/HEAD?recursive=1`, fetch a file with
  `gh api -H "Accept: application/vnd.github.raw" repos/<owner>/<repo>/contents/<path>` into the scratch folder and
  read it with grep. Cross-check one rule in two dumps of different games before trusting it. What the scripts do not
  hold (animation root motion, weapon files) stays an estimate and is marked so.
- **Docs:** the worked example is Deadnight's `docs/research/movement-speeds.md`, section "Where each number comes from".
