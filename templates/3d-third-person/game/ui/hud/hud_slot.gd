@tool
class_name HudSlot
extends PanelContainer
## One place of a HUD row (a weapon slot, a hotbar place): a picture of what it holds (`Icon`),
## the key that takes or uses it (`Key`) and a count (`Count`). Its look is the nodes of
## `hud_slot.tscn` and the theme's type variations it switches between, one per state, so a
## restyle is the theme's: the panel's variation (`HudSlot`, `HudSlotLit`, `HudSlotEmpty`), the
## key's (`HudSlotKey`, `HudSlotKeyLit`) and the picture's tint, the panel variation's colour
## `icon_color`. The row that owns it fills it; it reads nothing itself.

## What the place shows.
enum State {
	EMPTY,  ## Nothing: the key alone, dim.
	IDLE,  ## Something, not in hand.
	LIT,  ## The one in hand (or on its way there).
	SPENT,  ## Something that has run out (count 0): its picture, dim.
}

@export_group("Look")
## The panel's theme variation in each state, by `State`.
@export var panel_variations: Array[StringName] = [
	&"HudSlotEmpty", &"HudSlot", &"HudSlotLit", &"HudSlotEmpty"
]
## The key's theme variation while the place is lit, and otherwise.
@export var key_variation_lit: StringName = &"HudSlotKeyLit"
@export var key_variation: StringName = &"HudSlotKey"
## How solid a spent place's picture is.
@export_range(0.0, 1.0, 0.01) var spent_alpha := 0.35

@export_group("Parts")
## The picture.
@export var icon: TextureRect
## The key's label.
@export var key_label: Label
## The count's label.
@export var count_label: Label

## The state it shows now.
var state := State.EMPTY


## Shows `texture` (null: none), the key `key` and the count `count` ("" hides it) in `new_state`.
func show_place(key: String, texture: Texture2D, count: String, new_state: State) -> void:
	state = new_state
	var variation: StringName = panel_variations[clampi(new_state, 0, panel_variations.size() - 1)]
	theme_type_variation = variation
	if key_label != null:
		key_label.text = key
		key_label.theme_type_variation = (
			key_variation_lit if new_state == State.LIT else key_variation
		)
	if icon != null:
		icon.texture = texture
		icon.visible = texture != null and new_state != State.EMPTY
		var tint := get_theme_color(&"icon_color", variation)
		if new_state == State.SPENT:
			tint.a *= spent_alpha
		icon.self_modulate = tint
	if count_label != null:
		count_label.text = count
		count_label.visible = not count.is_empty() and new_state != State.EMPTY


## The key shown.
func key_text() -> String:
	return key_label.text if key_label != null else ""


## The count shown ("" when it is hidden).
func count_text() -> String:
	return count_label.text if count_label != null and count_label.visible else ""


## The picture shown (null when hidden).
func picture() -> Texture2D:
	return icon.texture if icon != null and icon.visible else null
