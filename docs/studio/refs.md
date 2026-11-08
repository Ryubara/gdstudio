# References

Third-party models and images that agents build from live in `<workspace>/refs/`, never in a repository.

```sh
uv run --project python gds refs fetch https://poly.pizza/m/<id>                 # one model
uv run --project python gds refs fetch https://poly.pizza/bundle/<name>-<id>     # a whole bundle
```

| Writes | What |
| --- | --- |
| `refs/polypizza/<id>/model.glb`, `meta.json` | a model and the API's answer: title, creator, licence, attribution, triangles |
| `refs/polypizza/bundles/<id>/` | `bundle.json`, `index.json` (one row per model), `models/<id>/` as above |

Needs `POLY_PIZZA_API_KEY` in the environment (a free key from Poly Pizza; set it with `setx`, never in a file); the
key is never printed. An asset that moves into a game gets a licence entry built from its `meta.json`, and committing
it is a maintainer decision.

## Reading sources on the web {#web-sources}

<!-- new section: this page held fetching models with `gds refs fetch`; nothing held how to read the web pages, PDFs and
wikis a research page cites -->

- **Approach:** Download a PDF with `curl` into its own empty directory and extract its text with `uv run --with pypdf
  python -I` (redirect stderr: the font warnings are huge); in the research page mark each source read, fetched (by a
  summarising tool) or reported (a search summary only). **Watch out for:** the fetch tool summarises HTML, so a PDF's
  bytes came back as noise for every GDC slide deck and Game AI Pro chapter. **Seen:** Deadnight, 2026-11-01 (fix: the
  PDFs read from disk).
- **Approach:** When a wiki refuses the fetch tool, ask its own API: `curl -s -A "<a browser user agent>"
  "https://<wiki>.fandom.com/api.php?action=parse&page=<Title>&prop=wikitext&format=json&formatversion=2&redirects=1"`
  into the scratch folder, read `parse.wikitext` with `python -I`, find a title with
  `action=query&list=search&srsearch=<words>`, and cite the article's normal address as read; for numbers no wiki
  prints, read the game's scripts on GitHub. **Watch out for:** every Fandom page answered the fetch tool with HTTP 402
  and the Wayback Machine was blocked, while search summaries mixed real wikis with content farms. **Seen:**
  Deadnight #622, 2026-11-02 (fix: one API call returned the whole article, tables and trivia included).
- **Approach:** When downloading reference photos through the Commons API, wait about 1.5 s between calls, retry a 429
  or an `error` answer with a growing wait (10, 20, 30 s), and write the folder's `meta.json` (licence, author, source)
  after every file; the photos go to `<workspace>/refs/`, never a repository. **Watch out for:** two calls a second with
  no back-off ended in HTTP 429 and then a `KeyError` on an `error` object inside a 200 answer, and the second weapon's
  photos were on disk with no licence entries. **Seen:** Deadnight, 2026-11-03.
