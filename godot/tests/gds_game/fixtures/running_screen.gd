extends Control
## A screen that asks the host to keep the game running while it is on top.

var pauses := false


func pauses_game() -> bool:
	return pauses
