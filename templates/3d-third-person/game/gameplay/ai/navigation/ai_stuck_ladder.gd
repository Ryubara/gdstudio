class_name AiStuckLadder
extends RefCounted
## The rungs an `AiNavigator` climbs while it stays stuck, one after another, each given its time
## and the stuck window after it before the next: a sidestep, a new path from the nearest point of
## the mesh to a goal moved a little, a jump where the level allows one (a `Vaultable` ahead or a
## link near), the goal dropped for a while, a walk back along the breadcrumbs, and the report.
## Progress at any rung ends the climb. Nobody is moved by hand: a character that gets nowhere is
## reported, and moving it elsewhere is the director's or the game's choice.

enum Rung { NONE, SIDESTEP, REPATH, JUMP, DROP_GOAL, BREADCRUMB, REPORT }

## The rung names, for the debug overlay.
const NAMES: Array[String] = ["", "sidestep", "repath", "jump", "drop goal", "back", "report"]

## Seconds each rung acts before the stuck window judges it.
var sidestep_seconds := 0.6
var jump_seconds := 0.5
var breadcrumb_seconds := 3.0
## Seconds after a rung acts that progress may still show before the next.
var judge_seconds := 0.5

## The rung being tried.
var rung := Rung.NONE
## Seconds on this rung.
var rung_seconds := 0.0
## The side of the next sidestep (+1 right of the path, -1 left): it swaps every climb.
var side := -1.0
## Climbs that reached the report.
var reports := 0


## A new episode: the first rung, on the other side from the last sidestep.
func start() -> void:
	rung = Rung.SIDESTEP
	rung_seconds = 0.0
	side = -side


## Progress came, or the goal ended: off the ladder.
func reset() -> void:
	rung = Rung.NONE
	rung_seconds = 0.0


## True while climbing.
func is_climbing() -> bool:
	return rung != Rung.NONE


## The next rung.
func next() -> void:
	if rung == Rung.NONE or rung == Rung.REPORT:
		return
	rung = (rung + 1) as Rung
	rung_seconds = 0.0
	if rung == Rung.REPORT:
		reports += 1


## Seconds this rung acts for.
func acting_seconds() -> float:
	match rung:
		Rung.SIDESTEP:
			return sidestep_seconds
		Rung.JUMP:
			return jump_seconds
		Rung.BREADCRUMB:
			return breadcrumb_seconds
	return 0.0


## Counts `seconds` on the rung; true when its time and the window after it are over.
func tick(seconds: float) -> bool:
	rung_seconds += seconds
	var waits := judge_seconds if rung < Rung.DROP_GOAL else 0.0
	return rung_seconds >= acting_seconds() + waits


## The rung's name, for the overlay.
func rung_name() -> String:
	return NAMES[rung]
