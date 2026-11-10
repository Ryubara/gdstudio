class_name EffectSlot
extends Node3D
## One place in an `EffectEmitter`'s pool. It holds the parts of an effect (the particles scene, an
## `AudioStreamPlayer3D`, an `OmniLight3D`), plays them when the emitter starts it, and is free for
## the next effect when they end. The emitter makes and moves slots; nothing else needs to.
##
## Idle, a slot is hidden, its light is off (a light holds one of the Compatibility renderer's
## per-object light places even at zero energy) and its particles are not emitting.

## The effect ended (or was cut) and the slot is free.
signal finished(slot: EffectSlot)

## Turns +Y to the node's -Z: a marker's forward is the way a flash points.
const FORWARD := Basis(Vector3.RIGHT, -PI / 2.0)
## The longest a sound is waited for once everything else has ended.
const SOUND_GRACE := 8.0

## The effect this slot last played (and has built its parts for).
var effect: EffectDef
## The node the effect follows while it plays (null when it stays where it started).
var target: Node3D
## Seconds since it started.
var age := 0.0
## True from `start()` to `release()`.
var active := false

var _placed := Transform3D.IDENTITY
var _built: PackedScene
var _root: Node
var _emitters: Array[Node] = []
var _sound: AudioStreamPlayer3D
var _light: OmniLight3D
var _length := 0.0
var _size := 1.0


func _init() -> void:
	name = &"EffectSlot"
	visible = false
	# Moved by script, not by the physics tick: interpolation would blend it from where it was.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Plays `def` here. `world` is where the effect stands (+Y out of it) and, with `follow`, the
## node it keeps standing on (`FORWARD` applied, so it points out of the node's -Z). `size_scale`
## multiplies the effect's own size.
func start(
	def: EffectDef,
	world: Transform3D,
	follow: Node3D,
	size_scale: float,
	with_particles: bool,
	with_sound: bool,
	with_light: bool
) -> void:
	stop()
	effect = def
	target = follow
	_placed = world
	_size = def.size * size_scale
	age = 0.0
	active = true
	visible = true
	_place()
	reset_physics_interpolation()
	_length = _start_particles(def, with_particles)
	_start_sound(def, with_sound)
	_start_light(def, with_light)
	if def.duration > 0.0:
		_length = def.duration
	elif _light != null and _light.visible:
		_length = maxf(_length, def.light_time)


## Builds the particle nodes of `def` without playing it, so its first play does not instance them.
func prepare(def: EffectDef) -> void:
	effect = def
	if def.particles != null and _built != def.particles:
		_build_particles(def.particles)
		(_root as Node3D).visible = false


## Moves time on by `delta`: follows the node, fades the light, and returns true once the effect
## has ended (its length passed and its sound finished).
func advance(delta: float) -> bool:
	if not active:
		return false
	age += delta
	if target != null:
		if is_instance_valid(target) and target.is_inside_tree():
			_place()
		else:
			target = null
	if _light != null and _light.visible:
		if age >= effect.light_time:
			_light.visible = false
		else:
			_light.light_energy = effect.light_energy * (1.0 - age / effect.light_time)
	if age < _length:
		return false
	if effect.duration > 0.0:
		return true
	return _sound == null or not _sound.playing or age >= _length + SOUND_GRACE


## Ends the effect now and frees the slot for the next one. `notify` false is for a slot that is
## taken over at once (no `finished`).
func stop(notify := false) -> void:
	if not active:
		return
	active = false
	visible = false
	target = null
	for node in _emitters:
		node.set("emitting", false)
	if _sound != null:
		_sound.stop()
	if _light != null:
		_light.visible = false
	if notify:
		finished.emit(self)


## True while this slot's light is on.
func light_on() -> bool:
	return active and _light != null and _light.visible


## The particle nodes of the built scene (empty until an effect with particles played here).
func emitters() -> Array[Node]:
	return _emitters


## The slot's sound player (null until an effect with a sound played here).
func sound_player() -> AudioStreamPlayer3D:
	return _sound


## The slot's light (null until an effect with a light played here).
func light() -> OmniLight3D:
	return _light


func _place() -> void:
	var local := effect.local_transform()
	if target != null:
		var base := target.global_transform.orthonormalized()
		global_transform = Transform3D(base.basis * FORWARD, base.origin) * local
	else:
		global_transform = _placed * local


func _start_particles(def: EffectDef, with_particles: bool) -> float:
	if not with_particles or def.particles == null:
		if _root != null:
			(_root as Node3D).visible = false
		return 0.0
	if _built != def.particles:
		_build_particles(def.particles)
	var shown := _root as Node3D
	shown.visible = true
	shown.scale = Vector3.ONE * _size
	var longest := 0.0
	for node in _emitters:
		node.call(&"restart")
		var speed := maxf(float(node.get("speed_scale")), 0.01)
		var reach := float(node.get("lifetime")) * (2.0 - float(node.get("explosiveness")))
		longest = maxf(longest, reach / speed)
	return longest


func _build_particles(scene: PackedScene) -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
		_root = null
	_emitters.clear()
	_built = scene
	_root = scene.instantiate()
	_root.name = &"Particles"
	var found: Array[Node] = [_root]
	found.append_array(_root.find_children("*", "", true, false))
	for node in found:
		if node is CPUParticles3D or node is GPUParticles3D:
			node.set("emitting", false)
			_emitters.append(node)
	add_child(_root)


func _start_sound(def: EffectDef, with_sound: bool) -> void:
	if not with_sound or def.sound == null:
		return
	if _sound == null:
		_sound = AudioStreamPlayer3D.new()
		_sound.name = &"Sound"
		add_child(_sound)
	_sound.stream = def.sound
	_sound.volume_db = def.sound_volume_db
	_sound.bus = def.sound_bus
	_sound.max_distance = def.sound_max_distance
	_sound.play()


func _start_light(def: EffectDef, with_light: bool) -> void:
	if _light != null:
		_light.visible = false
	if not with_light or def.light_energy <= 0.0 or def.light_time <= 0.0:
		return
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = &"Light"
		_light.shadow_enabled = false
		add_child(_light)
	_light.light_color = def.light_color
	_light.light_energy = def.light_energy
	_light.omni_range = def.light_range * _size
	_light.visible = true
