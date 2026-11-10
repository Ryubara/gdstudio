class_name Player
extends CharacterBody3D
## The player's body: moves, aims and owns a weapon. (Not changed by this pull request.)

## Metres a second on level ground.
const WALK_SPEED := 5.0

@onready var weapon: Weapon = $Weapon

var health: int = 100


func _ready() -> void:
	add_to_group(&"player")


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	velocity.x = input.x * WALK_SPEED
	velocity.z = input.y * WALK_SPEED
	move_and_slide()
	if Input.is_action_pressed("fire"):
		weapon.fire()
	if Input.is_action_just_pressed("reload"):
		weapon.reload()


## Take a hit; the server decides what happens at zero.
func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
