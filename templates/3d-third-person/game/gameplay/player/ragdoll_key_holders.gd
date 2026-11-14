class_name RagdollKeyHolders
extends RefCounted
## How many `PlayerInput` nodes hold each key on the `ragdoll` input action, shared by all of them:
## the action is the project's, so a key goes on it with its first holder and comes off with its
## last.
##
## The counts live here, not in `PlayerInput`: a script that extends a game class and keeps a
## static variable of its own left GdUnit4's scripts and the autoloads' in use at exit (213
## objects) when a suite named the base class first (gdstudio #1500; the kit's
## `docs/engines/godot/test-exit-leaks.md#a-subclass-with-statics`).

static var _holders: Dictionary[Key, int] = {}


## Adds a holder of `key` on `action`; the first one puts the key on the action.
static func hold(action: StringName, key: Key) -> void:
	var holders: int = _holders.get(key, 0)
	if holders == 0:
		InputMap.action_add_event(action, key_event(key))
	_holders[key] = holders + 1


## Takes a holder of `key` off `action`; the last one takes the key off the action.
static func release(action: StringName, key: Key) -> void:
	var holders: int = _holders.get(key, 0) - 1
	if holders > 0:
		_holders[key] = holders
		return
	_holders.erase(key)
	if InputMap.has_action(action):
		# The action drops the event equal to this one.
		InputMap.action_erase_event(action, key_event(key))


## How many hold `key` now.
static func count(key: Key) -> int:
	return _holders.get(key, 0)


## The event that stands for `key` on the action (its physical key).
static func key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event
