class_name AiSituation
extends RefCounted
## What an AI character believes is going on, the state its decisions read: Unaware, Suspicious,
## Alert, Engaged, Fleeing or Dead. Transitions come from what happens to it (the senses' awareness
## through `feed_awareness`, an event through `request`, death and getting up); the machine adds
## the two rules that keep it from flickering:
##
## - **Minimum dwell.** A situation holds at least `dwell` seconds before it may calm down
##   (Engaged to Alert) or turn sideways (Engaged to Fleeing); a request made sooner waits and the
##   latest one wins. Rising (Unaware to Alert, a hit to Engaged) and dying are at once.
## - **Hysteresis.** Awareness turns the character Suspicious at `suspicious_at` and Alert at 1, and
##   calms it only once it falls `hysteresis` under the line it crossed.
##
## It holds no node and reads no clock: `advance(seconds)` moves its time, so a test steps it.

## Emitted when the situation changes, with the new one and the one before.
signal changed(situation: Situation, previous: Situation)

enum Situation { UNAWARE, SUSPICIOUS, ALERT, ENGAGED, FLEEING, DEAD }

## How tense each situation is; going up is at once, going down or sideways waits for the dwell.
const RANK: Array[int] = [0, 1, 2, 3, 3, 4]
## The names, for the debug overlay and logs.
const NAMES: Array[String] = ["Unaware", "Suspicious", "Alert", "Engaged", "Fleeing", "Dead"]

## The situation now.
var current := Situation.UNAWARE
## Seconds since the situation last changed.
var held := 0.0
## The least time a situation holds before it may calm down or turn sideways.
var dwell := 1.0
## Awareness at which the character turns Suspicious (1 is Alert).
var suspicious_at := 0.3
## How far awareness falls under a line before the situation calms down past it.
var hysteresis := 0.1
## Seconds Alert holds before falling awareness may calm it (the profile's `alert_hold_seconds`,
## set by an `AiBrain`); 0 calms it as soon as awareness falls.
var alert_hold := 0.0

var _pending := -1


## The name of `situation` (or of the current one).
static func name_of(situation: Situation) -> String:
	return NAMES[situation]


## Takes the numbers from `profile` (each call, so an edit applies live).
func configure(profile: AiProfile) -> void:
	if profile == null:
		return
	dwell = profile.situation_dwell
	suspicious_at = profile.suspicious_at
	hysteresis = profile.awareness_hysteresis


## Moves the machine's time on by `seconds` and applies a request that waited for the dwell.
func advance(seconds: float) -> void:
	held += seconds
	if _pending >= 0 and held >= dwell:
		var wanted: Situation = _pending as Situation
		_pending = -1
		_enter(wanted)


## Asks for `situation`. Rising is at once; calming down or turning sideways waits until the
## current one has held `dwell` seconds. A dead character changes only by `revive()`.
func request(situation: Situation) -> void:
	if current == Situation.DEAD or situation == current:
		_pending = -1
		return
	if situation == Situation.DEAD:
		die()
		return
	if RANK[situation] > RANK[current] or held >= dwell:
		_pending = -1
		_enter(situation)
	else:
		_pending = situation


## Reads the senses' awareness (0 to 1) of the most worrying thing: Suspicious from
## `suspicious_at`, Alert from 1, and back down only `hysteresis` under the line. Leaves Engaged
## and Fleeing alone (an event decides those).
func feed_awareness(awareness: float) -> void:
	if RANK[current] > RANK[Situation.ALERT]:
		return
	var wanted := current
	match current:
		Situation.UNAWARE:
			if awareness >= 1.0:
				wanted = Situation.ALERT
			elif awareness >= suspicious_at:
				wanted = Situation.SUSPICIOUS
		Situation.SUSPICIOUS:
			if awareness >= 1.0:
				wanted = Situation.ALERT
			elif awareness < suspicious_at - hysteresis:
				wanted = Situation.UNAWARE
		Situation.ALERT:
			if held < alert_hold:
				return
			if awareness < suspicious_at - hysteresis:
				wanted = Situation.UNAWARE
			elif awareness < 1.0 - hysteresis:
				wanted = Situation.SUSPICIOUS
	request(wanted)


## The character died: Dead at once, whatever the dwell.
func die() -> void:
	_pending = -1
	if current != Situation.DEAD:
		_enter(Situation.DEAD)


## The character got up: Unaware at once.
func revive() -> void:
	_pending = -1
	if current == Situation.DEAD:
		_enter(Situation.UNAWARE)


## True while a request waits for the dwell.
func has_pending() -> bool:
	return _pending >= 0


func _enter(situation: Situation) -> void:
	var previous := current
	current = situation
	held = 0.0
	changed.emit(current, previous)
