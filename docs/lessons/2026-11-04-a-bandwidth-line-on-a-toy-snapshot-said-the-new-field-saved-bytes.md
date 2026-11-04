---
areas: [net]
---
# A bandwidth line measured on a toy snapshot said a new field made the WELCOME smaller

2026-11-04

- **Saw:** the first "what a join costs" line of the level tags (Deadnight #1077) read `welcome 4 seats: 173 -> 151
  (+-22)`: adding a `levels` table to the WELCOME made it 22 bytes shorter.
- **Cause:** the snapshot was a hand-made dictionary of three keys. A packed variable is compressed only above
  `NetWire.COMPRESS_FROM` (256 bytes): the plain one stayed under it and went out raw, the one with the new key went over
  it and was compressed. Two sizes on either side of a threshold are not a difference of the field.
- **Fix:** measure on the real thing: the room's own `_welcome_snapshot()` with four seats, with and without the key
  (1017 -> 1052, +35), and the event as a tick of its own (110 -> 154, +44). Put the line in the test's log and the
  numbers in the pull request.
- **Docs:** [multiplayer](https://github.com/Ryubara/deadnight/blob/main/docs/research/multiplayer.md) in the game, the
  section on the level and icon beside a name.
