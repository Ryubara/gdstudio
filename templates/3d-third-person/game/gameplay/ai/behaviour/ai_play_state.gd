class_name AiPlayState
extends RefCounted
## How boldly an AI character plays (Deadnight's play states, the research for #882 section 1.5):
## Aggressive, Careful or Safe, from its share of health less the pressure of the hostiles it sees
## now. Two lines from the profile (`safe_line()` and `careful_line()`, which `courage` and
## `flee_below_health` set): under a line it turns more careful at once; it turns bolder only once
## the share is `play_hysteresis` past the line and the state has held `play_dwell` seconds, so a
## character on the edge changes state once. The rows of an `AiBehaviourSet` name the play states
## they answer in (a Careful guard takes cover, a Safe one hides and does not roam).
##
## It holds no node and reads no clock: `feed(share, threats, seconds)` steps it.

signal changed(state: State, previous: State)

enum State { AGGRESSIVE, CAREFUL, SAFE }

const NAMES: Array[String] = ["Aggressive", "Careful", "Safe"]

## The state now.
var current := State.AGGRESSIVE
## Seconds since it last changed.
var held := 0.0
## The last score fed (health share less pressure), for the overlay and tests.
var score := 1.0


## The name of `state`.
static func name_of(state: State) -> String:
	return NAMES[state]


## One step, `seconds` after the last: `share` is health over max health (0 to 1), `threats` the
## hostiles seen now. Returns true when the state changed.
func feed(share: float, threats: int, seconds: float, profile: AiProfile) -> bool:
	held += seconds
	if profile == null:
		return false
	var pressure := minf(profile.pressure_per_threat * threats, profile.max_pressure)
	score = clampf(share - pressure, 0.0, 1.0)
	var safe_at := profile.safe_line()
	var careful_at := profile.careful_line()
	var wanted := current
	if score < safe_at:
		wanted = State.SAFE
	elif score < careful_at:
		wanted = State.CAREFUL if current != State.SAFE else current
	elif current != State.AGGRESSIVE:
		wanted = current
	# Bolder only past the line by the hysteresis and after the dwell.
	if current == State.SAFE and score >= safe_at + profile.play_hysteresis:
		wanted = State.CAREFUL if score < careful_at + profile.play_hysteresis else State.AGGRESSIVE
	elif current == State.CAREFUL and score >= careful_at + profile.play_hysteresis:
		wanted = State.AGGRESSIVE
	if wanted == current:
		return false
	if wanted < current and held < profile.play_dwell:
		return false
	var previous := current
	current = wanted
	held = 0.0
	changed.emit(current, previous)
	return true


## Back to Aggressive at once (a revive).
func reset() -> void:
	current = State.AGGRESSIVE
	held = 0.0
	score = 1.0
