# Inventory

The player carries a bag of items beside its weapons and opens it on a screen over the game: its own model on the left
(turned by a drag or the right stick), the weapons it carries, the bag's slots and a line about what is selected. How
the parts work and every value in the inspector is in the kit's `docs/engines/godot/inventory.md`.

## What the player sees

| Action | How | What happens |
| --- | --- | --- |
| Open and close | I, a pad's right shoulder, the Bag button on a touch screen; Esc, B or Close close it | The game pauses behind it (Settings > Controls > Pause in the inventory turns that off; the character then stands still while the world runs) |
| Take a weapon in hand | Press its slot in the Weapons row | The weapon comes up when the game runs again, by the same switch the wheel or the d-pad makes |
| Move a stack | Press a slot, then another (or drag one onto another with a mouse or a finger) | It fills a stack of the same kind or swaps; press it again or Esc to put it back |
| Drop | Drop, under the grid | The stack lies in front of the player and is taken back by walking over it; coins cannot be dropped |

The bag starts with three bandages (a sample item that does nothing yet) and fills with the coins the player picks up.

## Things you will do

- **Add an item:** make an `ItemDef` resource (`id`, name, description, icon, how many stack in a slot, whether it can be
  dropped, the scene a drop leaves), add it to the `catalog` of the `Inventory` node in `gameplay/player/player.tscn`,
  and put a `Pickup` in the map whose `item_id` is the item's `id`.
- **Give the player items at the start:** add an `ItemStack` to `start_items` on the same node.
- **Make the bag bigger:** `slot_count` on the `Inventory` node; the grid's columns are `columns` of the `Grid` node in
  `ui/inventory/inventory_screen.tscn`.
- **Add a weapon:** add its `WeaponDef` to the `Loadout`'s `slots`; the screen lists it with no change.
- **Restyle a slot:** open `ui/inventory/inventory_cell.tscn` (its styles, the icon's margins, the count, the badge).

## Where the files are

`ui/inventory/` the screen, the slot and the model preview; `gameplay/inventory/` the coin and bandage items;
`assets/ui/inventory/` their icons and the weapons'; `gameplay/weapon/weapon_chooser.gd` the weapon presses a chosen
weapon is sent as; `tools/capture/inventory_tour.tscn` a tour for captures (`--shots=<folder>` for a phone-sized
window, `--measure` for the preview's cost).
