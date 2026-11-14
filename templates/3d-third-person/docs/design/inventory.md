# Inventory

The player carries a bag of items beside its weapons and opens it on a screen over the game: its own model on the left
(turned by a drag or the right stick), the weapons it carries, the hotbar, the bag's slots and a line about what is
selected. The HUD shows the weapons as two numbered slots and the hotbar as a row of quick-access places. How the parts
work and every value in the inspector is in the kit's `docs/engines/godot/inventory.md` (the hotbar:
`inventory.md#hotbar`; the HUD's rows: `third-person/camera-and-ui.md#hud`).

## What the player sees

| Action | How | What happens |
| --- | --- | --- |
| Open and close | I, a pad's right shoulder, the Bag button on a touch screen; Esc, B or Close close it | The game pauses behind it (Settings > Controls > Pause in the inventory turns that off; the character then stands still while the world runs) |
| Take a weapon in hand | Press its slot in the Weapons row | The weapon comes up when the game runs again, by the same switch the wheel or the d-pad makes |
| Move a stack | Press a slot, then another (or drag one onto another with a mouse or a finger) | It fills a stack of the same kind or swaps; press it again or Esc to put it back |
| Drop | Drop, under the grid | The stack lies in front of the player and is taken back by walking over it; coins cannot be dropped |
| Take a weapon in hand from the HUD | 1 or 2 (a finger on the slot on a phone) | Slot 1 is the first weapon carried (the pistol), slot 2 the next (the fists today); the one in hand is lit amber, whichever way it was switched |
| Put an item on the hotbar | Drag a bag slot onto a hotbar place, press a hotbar key (3 to 6) on a bag slot, or pick a stack up and press a place | The place names that kind of item and shows how many the bag holds; press a filled place on the screen to take it off |
| Use an item | Its hotbar key (3 to 6; a finger on the place on a phone) | The bandage takes 1.6 s: the character lowers its aim and wraps it on (its clip and sound, a sign above the hotbar), then gets 25 health back as one leaves the bag. Sprinting, firing, aiming again, jumping, a melee blow, a reload, a switch, lying down or a hit stops it and nothing is used; a second press during it does nothing; at full health it is refused and kept |

The bag starts with three bandages (on hotbar place 3) and fills with the coins the player picks up. Online the
server owns the bag and the health: the use starts on your screen at the press, the heal and the count come from the
server, and the other players see your character wrap the bandage on.

## Things you will do

- **Add an item:** make an `ItemDef` resource (`id`, name, description, icon, how many stack in a slot, whether it can be
  dropped, the scene a drop leaves), add it to the `catalog` of the `Inventory` node in `gameplay/player/player.tscn`,
  and put a `Pickup` in the map whose `item_id` is the item's `id`.
- **Give the player items at the start:** add an `ItemStack` to `start_items` on the same node.
- **Make the bag bigger:** `slot_count` on the `Inventory` node; the grid's columns are `columns` of the `Grid` node in
  `ui/inventory/inventory_screen.tscn`.
- **Add a weapon:** add its `WeaponDef` to the `Loadout`'s `slots`; the screen lists it with no change.
- **Restyle a slot:** open `ui/inventory/inventory_cell.tscn` (its styles, the icon's margins, the count, the badge).
- **Make an item usable:** give its `ItemDef` a `use_effect` (a `HealEffect`, or a script of your own that extends
  `ItemEffect`); `consumed_on_use` says whether a use takes one out of the bag; `use_time`, `use_apply_share`,
  `use_clip` and `use_sound` make a use take time (the player's `ItemUse` plays it).
- **Change the hotbar:** `place_count` and `start_items` on the `Hotbar` node of `gameplay/player/player.tscn`; the
  keys are the `hotbar_1`... actions of the Input Map (add `hotbar_5` for a fifth key). Restyle a HUD place in
  `ui/hud/hud_slot.tscn` and the `HudSlot` variations of `ui/hud/hud_theme.tres`.

## Where the files are

`ui/inventory/` the screen, the slot and the model preview; `gameplay/inventory/` the coin and bandage items;
`assets/ui/inventory/` their icons and the weapons'; `gameplay/weapon/weapon_chooser.gd` the weapon presses a chosen
weapon is sent as; `gameplay/player/quick_keys.gd` the number keys of the HUD's places; `ui/hud/hud_weapon_slots.tscn`
and `ui/hud/hud_hotbar.tscn` the HUD's rows; `tools/capture/inventory_tour.tscn` and `tools/capture/hotbar_tour.tscn`
tours for captures (`--shots=<folder>` for a phone-sized window, `--measure` for the preview's cost).
