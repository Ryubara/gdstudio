---
areas: [godot-ui, general]
---
# A card on the second map spoke of the first map's lot

2026-11-03

- **Saw:** the second map's paid link card read "A WAY THROUGH / OPENS THE NEXT PART OF THE LOT"; its feed line said
  "BOUGHT SOMETHING" and its marker had no name (Deadnight #697).
- **Cause:** the HUD's words (door names, the card's detail line, the feed's item names) were written when one map
  existed and were the default for every id, so an id the tables did not know fell through to the first map's words.
  The map had no place to hold its own.
- **Fix:** a map holds its own words (`MapWords`, from its rules overlay) and the card, marker and feed read them first;
  the first map keeps the defaults. A test loads each map's scene, checks every door has words, and checks no card of
  the second map names the lot.
- **Check:** when a second content set arrives (map, mode), grep the HUD for the first one's nouns (lot, field, yard,
  fence) and give every default a per-set override before the content lands; capture one card per set.
- **Docs:** Deadnight `docs/design/smallmap.md` (The links).
