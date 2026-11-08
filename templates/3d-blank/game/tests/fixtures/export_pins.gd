class_name ExportPins
extends RefCounted
## Pins the inspector contract of a node or resource in a test: the names of its exports and each
## one's default. A new export fails the test until its default is pinned too, so every export is
## looked at once. Pin an export that holds a node or a resource as `null`.


## The names of the script exports of `object`, in the order the inspector shows them.
static func names(object: Object) -> Array[StringName]:
	var found: Array[StringName] = []
	for property in object.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR:
			found.append(StringName(property["name"]))
	return found


## Each export of `object` with its current value, as a dictionary.
static func values(object: Object) -> Dictionary:
	var found := {}
	for property_name in names(object):
		found[property_name] = object.get(property_name)
	return found


## The exports that are in `pins` but not on the object, or on the object but not in `pins`
## (empty when they match), for a failure message.
static func differences(object: Object, pins: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var present := names(object)
	for key: StringName in pins:
		if not present.has(key):
			found.append("%s is pinned but not an export" % key)
	for property_name in present:
		if not pins.has(property_name):
			found.append("%s is an export with no pinned default" % property_name)
	return found


## The exports whose value is not the pinned one (a vector or a colour compared by value, a float
## to a millionth), for a failure message.
static func wrong_values(object: Object, pins: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: StringName in pins:
		if not names(object).has(key):
			continue
		var now: Variant = object.get(key)
		var want: Variant = pins[key]
		var same := false
		if typeof(now) == TYPE_FLOAT and typeof(want) in [TYPE_FLOAT, TYPE_INT]:
			same = is_equal_approx(now, float(want))
		else:
			same = now == want
		if not same:
			found.append("%s is %s, pinned %s" % [key, now, want])
	return found
