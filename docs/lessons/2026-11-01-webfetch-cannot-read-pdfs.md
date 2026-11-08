---
areas: [process, gameplay]
---
# WebFetch could not read PDF sources

2026-11-01

- **Saw:** researching AI bots, an agent fetched GDC slides and Game AI Pro chapters with WebFetch and got unreadable
  output for every PDF.
- **Cause:** the fetch tool summarises HTML; a PDF's bytes come back as noise.
- **Fix:** download the PDF with `curl` into its own empty directory and extract the text with `uv run --with pypdf
  python -I` (redirect stderr: the font warnings are huge). In the research page, mark each source read, fetched (a
  summarising tool) or reported (search summary only).
- **Docs:** [Building games with agents](../studio/building-games-with-agents.md).
