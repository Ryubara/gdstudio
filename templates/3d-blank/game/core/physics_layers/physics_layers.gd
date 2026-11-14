class_name PhysicsLayers
extends RefCounted
## The game's physics layers by name, as the bits a `collision_layer` or a `collision_mask` holds.
## The same names are the project's `[layer_names]` (Project Settings > Layer Names > 3D Physics),
## so the inspector's layer grid and the code say the same thing; a test fails on a bit that a
## scene uses and the project does not name.
##
## A body sits on the layer of what it is; a mask lists what it meets. An area says what it senses
## by its mask (a pickup: characters), so it never hears about the floor it stands in.
##
## Two characters do not block each other (`CHARACTER_MASK` leaves out `CHARACTERS`): a networked
## client draws the other players as puppets with no collision, so a server whose bodies stop at
## each other ends up metres from the client (kit `engines/godot/multiplayer.md`, Deadnight #760).
## A game without networking that wants solid characters adds `CHARACTERS` to the player's mask.

## Floors, walls, blocks, doors, platforms, targets: what stops everything.
const WORLD := 1 << 0
## Played bodies (the player, later AI characters and networked bodies): a capsule each.
const CHARACTERS := 1 << 1
## Shots in flight. Nothing lists them in its mask: a shot finds what it hits, never the reverse.
const PROJECTILES := 1 << 2
## Bodies that physics moves (a pushed crate, a ball).
const PROPS := 1 << 3
## The bones of a body lying limp. Shots meet them (a dead body takes shots); the camera, the
## player's capsule, its ground probes and trigger areas never do.
const RAGDOLL := 1 << 4
## The body parts a shot can hit on a living character (`HitZones`). Scanned only by a shot's
## second test, once the shot met the character's capsule (`HIT_ZONE_MASK`); nothing moves into
## them.
const HIT_ZONES := 1 << 5
## Areas that sense something (a pickup, a trigger zone, a door's sensor), so an area or a query
## that looks for them can; no body lists them.
const SENSORS := 1 << 6
## A shot-only capsule around a living character, wider and taller than its moving capsule, so a
## part the pose holds outside that capsule (a crouch's hips, the head while it stands up) is still
## reached (`ShotHull`, gdstudio #1431). Only shots and aim rays list it.
const SHOT_HULLS := 1 << 7

## What a character's capsule (and its ground and ceiling probes) stands on and is stopped by.
const CHARACTER_MASK := WORLD | PROPS
## What a prop collides with: the level, the characters that push it, other props.
const PROP_MASK := WORLD | CHARACTERS | PROPS
## What a shot (and the aim ray that picks its point) meets. A living character is met at its shot
## hull (or its capsule, with none); the shot then looks for the body part inside it with
## `HIT_ZONE_MASK`.
const SHOT_MASK := WORLD | CHARACTERS | PROPS | RAGDOLL | SHOT_HULLS
## What a shot's mark is put on: what it meets, less the shot hulls (nothing is drawn there).
const SURFACE_MASK := WORLD | CHARACTERS | PROPS | RAGDOLL
## What a shot's second test looks for inside a character's capsule: its hit zones, and only them.
const HIT_ZONE_MASK := HIT_ZONES
## What a limp bone falls onto: the level, props, and the other bones of the body.
const RAGDOLL_MASK := WORLD | PROPS | RAGDOLL
## What pushes the camera in: the level and props, never a character or a body part.
const CAMERA_MASK := WORLD | PROPS
## What a pickup or a door's sensor senses: characters only.
const CHARACTER_SENSOR_MASK := CHARACTERS
## What a trigger zone senses: characters and props (a crate presses a pad too).
const TRIGGER_MASK := CHARACTERS | PROPS

## Each layer's number (1 to 32, as the inspector counts) and the name the project gives it.
const NAMES: Dictionary[int, String] = {
	1: "World",
	2: "Characters",
	3: "Projectiles",
	4: "Props",
	5: "Ragdoll",
	6: "Hit Zones",
	7: "Sensors",
	8: "Shot Hulls",
}


## The inspector's number (1 to 32) of the single layer `bit` (`PhysicsLayers.PROPS` is 4).
static func number(bit: int) -> int:
	assert(bit > 0 and bit & (bit - 1) == 0, "one layer at a time")
	var layer := 1
	while bit > 1:
		bit >>= 1
		layer += 1
	return layer


## The project's name for layer `layer_number` (1 to 32), empty when it has none.
static func project_name(layer_number: int) -> String:
	var key := "layer_names/3d_physics/layer_%d" % layer_number
	return str(ProjectSettings.get_setting(key, ""))


## The layers set in `bits` that the project does not name (their numbers, 1 to 32).
static func unnamed(bits: int) -> Array[int]:
	var missing: Array[int] = []
	for index in 32:
		if bits & (1 << index) and project_name(index + 1).is_empty():
			missing.append(index + 1)
	return missing
