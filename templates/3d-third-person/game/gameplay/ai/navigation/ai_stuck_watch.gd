class_name AiStuckWatch
extends RefCounted
## Says when a walking character is stuck, from what is left of its path (not how far it moved: a
## body sliding along a wall moves and gets nowhere). Stuck is a commanded speed over
## `min_commanded_speed` with the path left shrinking slower than `min_progress_speed` over
## `window` seconds. An episode ends only after net progress (`end_progress` metres off the path
## left since it began, or since a new path was taken), so a shuffle back and forth stays stuck.
##
## It counts the seconds walked, the seconds stuck, the episodes and the longest, which the
## course test gates on.

## Below this commanded speed (m/s) nothing is judged.
var min_commanded_speed := 1.0
## Less progress along the path than this (m/s) over a window is stuck.
var min_progress_speed := 0.25
## Seconds a window lasts.
var window := 0.5
## Metres of path left that end an episode.
var end_progress := 0.5

## True during an episode.
var stuck := false
## Seconds walked with a goal (a commanded speed over 0).
var walking_seconds := 0.0
## Seconds stuck, all episodes together.
var stuck_seconds := 0.0
## Seconds into the running episode.
var episode_seconds := 0.0
## The longest episode, seconds.
var longest_episode := 0.0
## Episodes since the start.
var episodes := 0

var _window_time := 0.0
var _window_left := INF
var _episode_left := INF


## Starts the window again from `left` (a new path, or a sharp corner just passed).
func rebase(left: float) -> void:
	_window_time = 0.0
	_window_left = left
	if stuck:
		_episode_left = left


## One sample, `seconds` after the last: the speed asked of the body and the path left. True on
## the sample an episode begins.
func sample(seconds: float, commanded_speed: float, left: float) -> bool:
	if commanded_speed > 0.0:
		walking_seconds += seconds
	if stuck:
		episode_seconds += seconds
		stuck_seconds += seconds
		longest_episode = maxf(longest_episode, episode_seconds)
		if _episode_left - left >= end_progress:
			stuck = false
			rebase(left)
		return false
	if commanded_speed <= min_commanded_speed or not is_finite(_window_left):
		rebase(left)
		return false
	_window_time += seconds
	if _window_time < window:
		return false
	var speed := (_window_left - left) / _window_time
	if speed >= min_progress_speed:
		rebase(left)
		return false
	stuck = true
	episodes += 1
	episode_seconds = _window_time
	stuck_seconds += _window_time
	longest_episode = maxf(longest_episode, episode_seconds)
	_episode_left = left
	return true


## Ends any episode (the goal was dropped or reached) and forgets the window.
func clear() -> void:
	stuck = false
	_window_time = 0.0
	_window_left = INF


## The share of walking time spent stuck, 0 to 1.
func stuck_share() -> float:
	return stuck_seconds / walking_seconds if walking_seconds > 0.0 else 0.0
