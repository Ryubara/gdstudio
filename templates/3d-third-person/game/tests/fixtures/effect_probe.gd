class_name EffectProbe
extends RefCounted
## For a suite of the effect emitter: small `EffectDef`s made in code, and a count of the nodes an
## emitter keeps, so a test reads what a play leaves behind.

const DUST := "res://gameplay/impacts/effects/impact_dust.tscn"
const SOUND := "res://assets/audio/impacts/impact_default_1.ogg"


## A new effect. `particles` is the dust burst (0.47 s), `sound` a short thud, `light` the energy
## of a 0.06 s flash (0 makes none). Each call makes a different effect.
static func def(particles := true, sound := false, light := 0.0) -> EffectDef:
	var made := EffectDef.new()
	if particles:
		made.particles = load(DUST)
	if sound:
		made.sound = load(SOUND)
	made.light_energy = light
	return made


## The nodes under `root` that are a `Light3D`, a particle node or an audio player: what an effect
## that did not end properly would leave behind.
static func parts_under(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "", true, false):
		if node is Light3D or node is CPUParticles3D or node is AudioStreamPlayer3D:
			count += 1
	return count


## Every node under `root`, itself included.
static func nodes_under(root: Node) -> int:
	return 1 + root.find_children("*", "", true, false).size()
