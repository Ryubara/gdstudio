class_name ClientItems
extends RefCounted
## The client's half of using an item (gdstudio #1386): it plays the server's USE events on this
## screen and decides nothing. `ClientCombat` (which owns one) hands it each USE when it is due
## (the local player's at once, another player's when the puppets are drawn at its TICK).
##
## - STARTED (another player's): its puppet's `ItemUse` plays the use (`ItemUse.play_remote`):
##   the clip over the upper body, the free hand, the sound; it ends at the item's time.
## - APPLIED: the user's health is the server's (`Health.set_wire_value`), the running use of that
##   command says `applied` (the sign turns), and on the local player the bag holds the count the
##   server left (`set_count`).
## - CANCELLED, REFUSED: the running use of that command ends on this screen too.

## USE events played, by code (`NetEvent.UseCode`).
var played := {}


## Plays one USE event now on `combat`'s screen (kept by no reference: the combat owns this).
func play(event: NetEvent, combat: ClientCombat) -> void:
	played[event.code] = int(played.get(event.code, 0)) + 1
	var body := combat.body_of(event.slot)
	if body == null:
		return
	var own := body == combat.client.player
	var use := ItemUse.of(body)
	match event.code:
		NetEvent.UseCode.STARTED:
			if use != null and not own:
				use.play_remote(event.id, event.seq)
		NetEvent.UseCode.APPLIED:
			var health := Health.of(body)
			if health != null and event.amount != NetEvent.NO_HEALTH:
				health.set_wire_value(event.amount)
			if own:
				var hotbar := Hotbar.of(body)
				if hotbar != null:
					set_count(hotbar.inventory, hotbar.item_at(event.id), event.detail)
			if use != null:
				use.server_applied(event.seq)
		NetEvent.UseCode.CANCELLED, NetEvent.UseCode.REFUSED:
			if use != null:
				use.server_cancelled(event.seq, ItemUse.reason_of(event.detail))


## Makes `inventory` hold `count` of `item` (the server's word): the difference comes out of the
## last stacks, or goes in as new ones.
static func set_count(inventory: Inventory, item: ItemDef, count: int) -> void:
	if inventory == null or item == null:
		return
	var extra := inventory.count_of(item) - count
	if extra < 0:
		inventory.add(item, -extra)
		return
	for slot in range(inventory.slot_count - 1, -1, -1):
		if extra <= 0:
			return
		if inventory.item_at(slot) == item:
			extra -= inventory.remove(slot, mini(extra, inventory.count_at(slot)))
