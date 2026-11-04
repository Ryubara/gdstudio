---
areas: [gameplay, tests]
---
# Use zones overlapped, and the purchase won over the repair

2026-11-03

- **Saw:** the maintainer, at round 12: "sometimes I'll be boarding something, and then I'll accidentally interact with
  a weapon on the wall or a perk or something else next to it, the interactions need to be properly spaced with one
  another to prevent accidental inputs and losing your weapons" (Deadnight #908). From the player's camera at the
  second map's upper window, looking at the boards, the card offered the baseball bat ("REPLACES REVOLVER"); at the
  window's own repair spot it offered the locker's rounds, which sat under the window.
- **Cause:** three things, none of them wrong alone. Every use reached 3.2 m, a number set by the first playable night
  and never revisited, so each zone was a disc 6.4 m across; nothing checked two zones against each other (the one
  spacing test asked for one reach between spots, not two, and left out windows; the second map had none); and where
  two met, the prompt took the first match in a fixed order (door, any shop spot, then the window), whatever the player
  looked at. A gun bought with full hands replaced the one in hand on one press, and a person mending taps use again.
  The wall-sight work of #831 had noticed "next to a wall weapon the board prompt never shows" and left it as older
  than its change, and the two-map design review (#833) walked prompts through walls but not prompts beside each other.
- **Fix:** a rule and a sweep. Two use zones never share standing ground, with 0.5 m between; a zone is the floor the
  server would offer the thing from, so the sweep (`test_use_zone_spacing.gd`) asks the same functions the server does
  (`UseZones`). The reaches shrank to what a hand needs (1.5 m from a shop spot's standing marker, 2.5 m from a slab,
  window or post, whose stands are 1.4 to 1.5 m out); the lot needed three moves in its generator, and the second map's
  26 remaining pairs are named in the test for its rework, which fails on any new pair and on one that is gone. In the
  code: no purchase during a held repair or 1.5 s after its last board, a replacing purchase only from a press made
  once its card has been up 0.4 s, and where two zones still meet the one looked at wins.
- **Docs:** Deadnight `docs/research/use-reach.md#spacing-and-the-press-908`; the kit's map review, section 5, and
  level design P10. Check for next time: when a map gets an interactable, or a reach changes, walk the floor for points
  inside two use zones (with the gap), on every map; a priority order between two kinds is not a design, and a press
  that can cost a weapon needs a deliberate press.
