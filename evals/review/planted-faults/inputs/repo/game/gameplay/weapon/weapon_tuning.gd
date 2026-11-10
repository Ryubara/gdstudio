class_name WeaponTuning
extends Resource
## How a weapon fires and reloads.

## Rounds in a full magazine.
@export var magazine_size: int = 12
## Rounds carried when the weapon is first picked up.
@export var starting_reserve: int = 36
## The most rounds carried outside the magazine.
@export var reserve_cap: int = 120
## Seconds between shots.
@export var shot_interval: float = 0.25
## Seconds a reload takes.
@export var reload_seconds: float = 1.6
## Damage of one hit.
@export var damage: int = 20
