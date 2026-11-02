---
areas: [gameplay, blender]
---
# Weapon models sat in the assets with no definition, and nothing asked where a player gets one

2026-11-02

- **Saw:** "We also need to make sure all weapons are properly in the game and can be properly accessed from the mystery
  box." The game had 10 weapon models and 6 definitions; the baseball bat and the fire axe had models and class holds
  but no id, no numbers and no source, and the crane's pool was a hand-written list of four.
- **Cause:** the art, the definitions, the shop and the crane were each added by their own task and nothing connected
  them: no table said which models are weapons, and no test asked "where does a player get this?". The earlier lesson
  (every catalogue entry is played through) covers a weapon that exists; this is one level up.
- **Fix (Deadnight #461, PR #530):** a roster table in the game's `docs/design/weapons.md` (model, definition, source,
  numbers); a test that fails when a definition has no start, wall or crane source or a source names an unknown id; a
  seeded test that the crane's pool is drawn whole; one test that takes each source's weapon in hand with the real
  command. A model whose role is unclear is a question to the maintainer, not a definition by guess.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
