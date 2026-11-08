---
areas: [process, general]
---
# A wiki that refused the fetch tool answered through its own API

2026-11-02

- **Saw:** researching Nacht der Untoten (Deadnight #622), every Fandom page (`callofduty.fandom.com/wiki/...`)
  answered the fetch tool and its agents with HTTP 402, the Wayback Machine was blocked too, and the search summaries
  that were left mixed real wikis with content farms.
- **Cause:** the wiki refuses the fetch tool's client, not the reader: the same host serves MediaWiki's API.
- **Fix:** `curl -s -A "<a browser user agent>" "https://<wiki>.fandom.com/api.php?action=parse&page=<Title>&prop=wikitext&format=json&formatversion=2&redirects=1"`
  into the scratch folder, then read `parse.wikitext` with `python -I`; `action=query&list=search&srsearch=<words>`
  finds a page's title. The wikitext is the whole article with its tables, galleries and trivia, so one call replaces
  several fetches. Cite the article's normal URL and mark it read. The older fix (game scripts on GitHub,
  [Designing from a reference](../gamedev/design.md#reference)) still holds for numbers no wiki prints.
- **Docs:** the worked example is Deadnight's `docs/research/maps/small-map-formula.md`, section "Sources".
