class_name TouchButton
extends Resource
## One round button of the touch layer: it presses an input action while a finger is on it.

## The input action it presses (`jump`, `interact`...).
@export var action: StringName = &"jump"
## The word on the button.
@export var label := "Jump"
## Where it sits: 0 is the corner under the right thumb, the next ones follow in an arc around
## it.
@export_range(0, 3, 1) var slot := 0
