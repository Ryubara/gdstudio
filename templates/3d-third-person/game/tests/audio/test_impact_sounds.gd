# The impact sounds the template ships, three seeded variants for each of the default, wood and
# metal surfaces: short, not looping, starting at once, and quieter in the mix than a pistol shot.
extends GdUnitTestSuite

const SOUND := "res://assets/audio/impacts/impact_%s_%d.ogg"
const SURFACES: Array[String] = ["default", "wood", "metal"]


func test_each_surface_has_three_short_one_shot_variants() -> void:
	for surface in SURFACES:
		for n in range(1, 4):
			assert_bool(ResourceLoader.exists(SOUND % [surface, n])).is_true()
			var sound: AudioStreamOggVorbis = load(SOUND % [surface, n])
			assert_float(sound.get_length()).is_between(0.1, 0.6)
			assert_bool(sound.loop).is_false()


func test_the_surfaces_play_their_variants_on_the_sfx_bus_near_the_shots_level() -> void:
	var impacts := auto_free(load("res://gameplay/impacts/impacts.tscn").instantiate()) as Impacts
	add_child(impacts)
	var shot := auto_free(load("res://gameplay/weapon/weapon.tscn").instantiate()) as Weapon
	add_child(shot)
	var shot_db := (shot.get_node("%ShotSound") as AudioStreamPlayer3D).volume_db
	for surface: ImpactSurface in impacts.surfaces_by_name().values():
		assert_bool(surface.sound.bus == &"SFX").is_true()
		assert_float(surface.sound.volume_db).is_less(shot_db + 14.0)
		assert_int((surface.sound.stream as AudioStreamRandomizer).streams_count).is_equal(3)
