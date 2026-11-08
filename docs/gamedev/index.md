# Game development

Principles that hold in any engine and any game: what makes a level read, a sound sit in the mix, a camera feel right.
A page here says what to do and why, with its sources and the check that settles it; how one engine does it goes in
that engine's folder ([Godot](../engines/godot/index.md)), and the numbers of one game go in that game's docs.

**Belongs here:** animation, camera, input, AI, netcode, audio, UI, level design, performance and testing, as
principles. **Not here:** an engine's API or its traps (`engines/<engine>/`), a tool's steps (`tools/<tool>/`), how the
studio itself works (`studio/`).

| Page | What it covers |
| --- | --- |
| [Level design](level-design.md) | The principles the `level-designer` agent carries, each with its sources and the check that settles it. |
| [Audio](audio/index.md) | Making sound assets outside the engine: voice lines, menu and interface sounds. |
| [The player's controller](controller.md) | Genre conventions, devices, aim and hip fire, states and actions, feel. |
| [UI and HUD](ui.md) | What the HUD holds, a screen of choices, what an online menu offers. |
| [Testing a game](testing.md) | When a feature counts as tested: the real path and every catalogue entry. |
| [Netcode](netcode.md) | One owner for each fact, what a client may send, shared limits, room capacity, who is in a room, branches that share the net files. |
| [Platform backend](backend.md) | The service beside the game server: HTTP and Node traps, data that crosses, tests, probes against a live backend. |
| [Balance](balance.md) | The numbers a player meets: hits to kill, the weapon roster, comparing weapons, prices, a score's step. |
| [Designing from a reference](design.md) | The reference's loop and numbers, variety beats, settings that scale, bot teammates, content and interactions. |
