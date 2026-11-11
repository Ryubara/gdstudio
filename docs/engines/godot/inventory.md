# Inventory: items, the bag and the screen

<!-- new section: menus.md holds the host that opens screens and ui-controls.md the controls; nothing said how a game
keeps items, shows them with the weapons and the player's model, or chooses a weapon from a menu without a new
network bit (gdstudio #890) -->

How a GDStudio game keeps the items a character carries and shows them (gdstudio #890): the `Inventory` component of
the synced `gds_game` addon, which any game uses as it is, and the inventory screen of 3D Third Person, which shows the
bag beside the player's weapons and its live model. Measured on Windows, Godot 4.7.2, Compatibility.

## The bag: `Inventory`, `ItemDef`, `ItemStack` {#bag}

<!-- new section: the component any game reuses; the template's screen is the next section -->

| Part | Where | What it is |
| --- | --- | --- |
| `ItemDef` | `addons/gds_game/inventory/item_def.gd` (synced) | One kind of item as a resource: `id` (a pickup's `item_id`), `display_name`, `description`, `icon`, `tint`, `max_stack`, `droppable`, `drop_scene`. A new item is a new `.tres`. |
| `ItemStack` | `addons/gds_game/inventory/item_stack.gd` (synced) | An item and a count, for `start_items`. |
| `Inventory` | `addons/gds_game/inventory/inventory.gd` (synced) | A node with `slot_count` slots, each empty or one stack. |

- **Add** fills the stacks of the same kind first, then the first empty slots, and returns what did not fit
  (`overflowed`). **Move** puts a stack in an empty slot, fills a stack of the same kind (the rest stays where it was)
  or swaps with another kind. **Remove** takes part or all of a stack. **Drop** takes it out and places the item's
  `drop_scene` at `drop_offset` in `drop_origin`'s space (for a character its `Model` slot, whose +Z is its front), under
  `drop_parent` or the collector's parent; a scene whose root has `item_id`, `amount` and `tint` gets them, so the
  template's `Pickup` comes back as the same item. `droppable` off (a coin, a key to the story) refuses the drop.
- **Pickups fill it.** The collector's `collect_signal` (a `Character`'s `item_collected(item_id, amount, total)`)
  adds the `catalog` item with that `id`; an id the catalog does not list (ammunition, which the `WeaponLoadout` takes)
  is left alone.
- **Signals, not polling:** `changed`, `slot_changed(slot)`, `item_added`, `item_dropped(item, count, node)`,
  `overflowed`. A screen redraws on `changed`.
- **Not sent over a network yet.** The bag is plain data on the character; in an online game the server owns it and a
  screen's move or drop is a request. Opening the screen is local UI and sends nothing.

In the inspector: `Inventory` Slots (`slot_count` 16, `start_items`), Pickups (`catalog`, `collector`, `collect_signal`
`item_collected`), Drop (`drop_origin`, `drop_offset` (0, 0.6, 1.6) m, `drop_parent`). Tests:
`godot/tests/gds_game/test_inventory_alone.gd` (14 cases, the component in an empty scene).

## The 3D Third Person inventory screen {#template-screen}

<!-- new section: the template's screen, its inspector list and how a weapon chosen there reaches the hands -->

| Part | Where (`templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| Screen | `ui/inventory/inventory_screen.tscn`, `.gd` (`InventoryScreen`, a `UIScreen`) | The live model on the left; the weapons row, the bag's grid and a detail line with Drop on the right; Close under the model. |
| Slot | `ui/inventory/inventory_cell.tscn`, `.gd` (`InventoryCell`, a `Button`) | One focus stop: `Icon`, `Title` (the name when there is no icon), `Count`, the `IN HAND` `Badge`, the `HeldFrame` of a picked-up stack; its styles are in the scene. |
| Preview | `ui/inventory/model_preview.tscn`, `.gd` (`ModelPreview`) | A `SubViewport` of the game's own world whose `Camera` sees one render layer, added to the model's meshes while it shows. |
| Weapon request | `gameplay/weapon/weapon_chooser.gd`, `PlayerInput.request_weapon()` | A chosen weapon reaches the hands by the weapon presses a player makes. |
| Bag | the `Inventory` node of `gameplay/player/player.tscn` (`Player.inventory`) | 16 slots, three bandages to start; catalog `gameplay/inventory/coin.tres` and `bandage.tres`; icons in `assets/ui/inventory/`. |
| Opening | `action_screens` of `ui/menus/screen_host.tscn`; `BagButton` in `MenuLayer` of `ui/player_rig/player_rig.tscn` | The `inventory` action (I, a pad's right shoulder) opens and closes it; the Bag button beside Menu on a touch screen. |
| Pausing | Settings > Controls > Pause in the inventory (`controls/pause_in_inventory`) | Whether the game stops behind it. |

- **Weapons come from the loadout.** The row is `WeaponChooser.round_of(loadout)` (its filled slots, then the fists),
  read again on every redraw and on the loadout's signals (and on a `slots_changed` signal when the loadout has one),
  so a weapon a pickup adds shows without a change here. Pressing one calls `PlayerInput.request_weapon(slot)`: from
  the next command on, the input presses `next_weapon`, `previous_weapon` (the shorter way round) or `toggle_unarmed`,
  one a tick, until the loadout is heading for the slot, then stops (after `REQUEST_TICKS`, 32, it gives up). No
  command bit is added (protocol v3 has none free) and a server sees ordinary presses. With the game paused the
  request waits; the badge shows the chosen weapon at once.
- **Items:** press a slot to pick its stack up (the `HeldFrame`), press another to put it there, the same one or Esc
  (B) to put it down; a mouse or a finger can drag one slot onto another (`InventoryCell._drop_data`). Drop drops the
  picked stack, or else the last slot the pointer or the focus showed; it is off for an item that may not be dropped.
- **Focus by hand.** Every cell's four neighbours are set in `_link_focus()`: Down from a weapon goes to the bag's
  column under it, Down from the last row to Drop, Left of the first column to Close, a side with nothing beyond keeps
  the focus. The weapons row is shorter than the grid, so the engine's guess by geometry jumped past rows.
- **The game running behind it.** `pauses_game()` reads the setting; the `ScreenHost` asks the top screen for it on
  every change of the stack (`top_pauses_game()`), so the pause menu pushed over a running inventory still stops the
  game. While the screen is up the player's `input_enabled` is off (`stop_player_input`), so a click on a slot fires
  nothing and the arrows walk the focus, not the character; a weapon request goes out all the same.
- **Phone:** the screen's `MenuFit` draws it 1.75 times bigger (a slot is about 65 points high on an 844 x 390 phone)
  and the grid is a `UIFitScroll` that keeps the card on the screen (one and a half rows show, the focus scrolls it).

In the inspector: `InventoryScreen` Nodes (`player`, empty: the group `player`; `cell_scene`), Pausing
(`pause_setting`, `pauses_by_default` on, `stop_player_input` on); `ModelPreview` Nodes (`model_slot`, set from the
player), View (`preview_layer` 20, `distance` 3.2 m, `camera_height` 1.15 m, `look_height` 0.95 m, `field_of_view` 34,
`start_angle` -25), Turning (`drag_turn` 0.45 deg/px, `stick_turn` 160 deg/s), Quality (`max_height` 1440 px, `msaa`
4x); `PauseButton.screen` (the Bag button's is the inventory). The look of a slot is `inventory_cell.tscn`, of the
screen `inventory_screen.tscn`, of the preview's light and background `model_preview.tscn`.

Tests: `tests/ui/test_inventory_screen.gd` (11 cases: keys, pad, mouse and the Bag button through the real input path),
`tests/gameplay/test_weapon_request.gd` (5), and the host's `test_screen_host_alone.gd` for `pauses_game()`. Captures:
`tools/capture/inventory_tour.tscn` (`--shots=<folder>` for a phone-sized window).

Cost: nothing while closed (the screen is made when it opens). Open, the preview draws the model's meshes once more
into a viewport the size of its control at the window's pixels, and the map is not drawn there: 380 x 613 px on a
1920 x 1080 window, 240 x 177 on 844 x 390, 507 x 817 on 2560 x 1440, each 0.04 to 0.07 ms of CPU and of GPU a frame
(RTX 5080, Compatibility, 4x MSAA, the mean of 120 frames: `inventory_tour.tscn -- --measure`). The game is paused
behind it by default.

## A live model in a menu {#live-model}

<!-- new section: ui-controls.md#3d-in-a-menu says how a menu's own 3D stage is sized; nothing said how to show the
character that stands in the game without copying it -->

A `SubViewport` without its own world draws the game's world; its camera's `cull_mask` is one render layer, added
(`layers |= bit`) to every `VisualInstance3D` under the model slot while the preview shows and taken off when it hides.
The slot's `child_entered_tree` flags a new mesh a frame later, so a model swap shows at once; the weapon in the hand
and the pose come for free, and the map costs nothing there.

- **Approach:** Show the character itself through a camera that sees one layer, and give that view its own light on
  the same layer (`layers` and `light_cull_mask`). **Watch out for:** a camera's `cull_mask` culls lights by their own
  `layers` too, so the map's sun (layer 1) never lit the preview: the model was flat ambient, black with the ambient at
  0. The preview's light also lights the model in the game view while the screen is up. **Seen:** gdstudio #890,
  2026-11-10 (`ui/inventory/model_preview.gd`).
