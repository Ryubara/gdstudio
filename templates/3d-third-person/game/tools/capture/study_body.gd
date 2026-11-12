extends RefCounted
## The body a clip study or tour poses, by its `MODEL` setting (kit #1286): `female` (or nothing)
## and `male` are the template's bodies (`CharacterBodies`, the prototype `form` pair);
## `quaternius_female` and `quaternius_male` are the Quaternius mannequins the template's own
## clips were made on. Studies preload this file (`const STUDY_BODY := preload(...)`).

const BY_NAME := {
	"female": CharacterBodies.FEMALE,
	"male": CharacterBodies.MALE,
	"quaternius_female": CharacterBodies.QUATERNIUS_FEMALE,
	"quaternius_male": CharacterBodies.QUATERNIUS_MALE,
}


## The name `MODEL` asks for, `female` when it is not set or names no body.
static func chosen() -> String:
	var asked := OS.get_environment("MODEL")
	return asked if BY_NAME.has(asked) else "female"


## The path of the body `MODEL` asks for.
static func path() -> String:
	return BY_NAME[chosen()]
