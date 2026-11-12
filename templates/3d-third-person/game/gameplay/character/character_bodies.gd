class_name CharacterBodies
extends RefCounted
## The bodies the template's characters wear (kit #1187), named once: GDStudio's prototype
## mannequins in the `form` look (`assets/characters/prototype/`). The player, the friendlies and
## the online puppets wear `FEMALE` (`character_dressed.tscn` holds it), the enemies `MALE` (their
## scenes set it as `CharacterModel.variant`). The pistol's solved hold, the ragdoll's capsules and
## the hit zones are measured on these two; the tests, benches and captures that pose "the
## template's body" read the paths here, so a game that moves to other bodies changes them here
## and in the scenes, then solves the hold again (`tools/hold/`).
##
## The Quaternius mannequins (`assets/characters/mannequin/`) stay in the template on the same
## rig, for the clip checks made on them and as another body a game can swap in.

const FEMALE := "res://assets/characters/prototype/form_female.glb"
const MALE := "res://assets/characters/prototype/form_male.glb"
## Both, by the name the fixtures and tools take (`HoldStage.make(holder, "male")`).
const BY_NAME: Dictionary[String, String] = {"female": FEMALE, "male": MALE}

const QUATERNIUS_FEMALE := "res://assets/characters/mannequin/mannequin_female.glb"
const QUATERNIUS_MALE := "res://assets/characters/mannequin/mannequin_male.glb"


## The meshes of a body that are drawn up close: every `MeshInstance3D` under `rig`, but for the
## farther levels of detail of a prototype body (`Body_LOD1`, `Body_LOD2`), which lie inside the
## nearest one and would count each surface three times in a measure of the skin.
static func near_meshes(rig: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var level := instance.name.rfind("_LOD")
		if level >= 0 and not instance.name.ends_with("_LOD0"):
			continue
		found.append(instance)
	return found
