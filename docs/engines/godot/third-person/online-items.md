# Item uses online

<!-- new section: inventory.md#hotbar said a timed use would be one small event online but nothing held the route; the
     template page is at its size limit (gdstudio #1386) -->

How a hotbar item (the bandage) is used in an online game of the 3D Third Person template: who decides the heal, what
travels and what each screen plays. Part of [the 3D Third Person template](../third-person-template.md); the item
use offline is [the hotbar](../inventory.md#hotbar), shots and deaths online are
[Shots, hits and deaths online](online-shots.md#template-shots).

## Who decides an item use {#item-uses}

<!-- new section: the bag and the hotbar were off the wire, so an online client refused every hotbar use -->

The server owns every bag and every health; a press travels as a command field and the rest as small events.

| Part | Where | What it does |
| --- | --- | --- |
| The press | `PlayerCommand.use_place` (-1 none), the COMMAND's byte 14 (`CommandCodec.USE_AT`: the place + 1, 0 none, more than `MAX_USE_PLACES` 32 refused) | `PlayerInput` writes the first hotbar place pressed; an edge like the other presses (`clear_edges`, `merge_edges_from`). The command stays 15 bytes. `NetWire.VERSION` 9. |
| `ItemUse` | `gameplay/character/item_use.gd` | `step(delta)` after the body's step reads the command's press and runs the use; offline its own `_physics_process` calls it, a server and a predicting client call it right after `Character.step` (`stepped_by_owner`). `role`: `AUTHORITY` (offline, the server: rules and the heal), `PREDICT` (the user's screen: starts and cuts at once, never heals), `PUPPET` (another player's body: plays the events). |
| `ServerItems` | `gameplay/net/server_items.gd`, one on each `NetServer` (`items`) | Gives each body the children of `body_items.tscn` (the player's bag of three bandages, its hotbar, an `ItemUse`), steps each use after its body and turns what it does into USE events. |
| `ClientItems` | `gameplay/net/client_items.gd`, one on each `ClientCombat` (`items`) | Plays the USE events: a puppet's use, the server's health and count, a cut. |
| The USE event | `NetEvent.Kind.USE`, 8 bytes: slot, code (`UseCode`), place, the low 16 bits of the starting command's `seq`, a detail, the health left | STARTED to the other players; APPLIED (the count left, the health) to everyone; CANCELLED (the reason, `ItemUse.CUT_REASONS`) to everyone; REFUSED (naming the refused command) to the user alone. |

- **The user's screen predicts the start.** At the press its `ItemUse` starts the clip, the free hand, the sound and the
  HUD's sign, lowers the aim and cuts by the same rules from the same commands as the server's; the apply tick passes
  with nothing changed. The server's APPLIED sets the health (`Health.set_wire_value`), the bag's count
  (`ClientItems.set_count`) and turns the sign; a CANCELLED or REFUSED of the running use's command ends it (a cut
  this screen cannot see, a hit; a press the server refused). An event names the command that started its use, so a
  late one never ends a newer use.
- **Another player's use** is a STARTED played when the puppets are drawn at its TICK (`ItemUse.play_remote` on the
  puppet: the clip, the free hand, its own sound at the puppet), ended by its time or a CANCELLED; the APPLIED puts
  the puppet's health. Its bag is not on the wire.
- **Nothing cosmetic travels:** no clip, sound, sign or progress; a use costs 8 bytes to each other player at its
  start and 8 to everyone at its heal.

Measured (Windows, Godot 4.7.2, `tests/gameplay/test_net_item_use.gd`, two predicting clients and a server in one
process in lockstep): the uplink over a use is the same as with nothing happening, 914 B a second a client (the
budget 2 KB); the downlink at most 1.6 KB a second a client in the first seconds after the join, 1.1 KB later (the
budget 5 KB); the use's own bytes are three events, 24 bytes in all. The capture is
`tools/capture/online_heal_tour.tscn` (Ada's screen and Bo's side by side).

- **Approach:** Count an event's bytes from the events each client played (`ClientItems.played`) and its codec size,
  and report the link's rates against the budget; compare two windows of link bytes only when nothing else in them
  changes. **Watch out for:** in the online rig the downlink in the first seconds after the join runs about 0.45 KB a
  second higher than later (the AI block and the views settling), so a quiet window before a 24-byte use measured
  2 KB more than the use window, and after it 2 KB less. **Seen:** gdstudio #1386, 2026-11-13
  (`test_net_item_use.gd`).
